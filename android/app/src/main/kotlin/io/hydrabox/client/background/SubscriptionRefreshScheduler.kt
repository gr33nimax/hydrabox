package io.hydrabox.client.background

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ListenableWorker.Result as WorkResult
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.hydrabox.client.runtime.CoreRuntimeClient
import io.hydrabox.client.runtime.CoreRuntimeException
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.hydrabox.client.storage.DomainCrypto
import io.hydrabox.client.storage.HydraDatabase
import io.hydrabox.client.storage.IncidentRepository
import io.hydrabox.client.storage.SubscriptionEntity
import io.hydrabox.client.storage.SubscriptionRepository
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

object SubscriptionRefreshScheduler {
    private const val UNIQUE_WORK = "hydrabox-subscription-refresh-dispatcher-v1"

    fun ensureScheduled(context: Context) {
        val request = PeriodicWorkRequestBuilder<SubscriptionRefreshDispatcherWorker>(
            15,
            TimeUnit.MINUTES,
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
            UNIQUE_WORK,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }
}

/** Native-only dispatcher; it never creates or depends on a Flutter engine. */
class SubscriptionRefreshDispatcherWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    private enum class Outcome { SUCCESS, RETRY, PERMANENT_FAILURE }

    override suspend fun doWork(): WorkResult {
        val database = HydraDatabase.open(applicationContext)
        val crypto = DomainCrypto(applicationContext)
        val repository = SubscriptionRepository(database, crypto)
        val incidents = IncidentRepository(database.incidents(), crypto)
        val due = database.subscriptions().dueForRefresh(
            System.currentTimeMillis(),
            MAX_PARALLEL_REFRESHES,
        )
        if (due.isEmpty()) return WorkResult.success()

        val core = CoreRuntimeClient(applicationContext)
        core.connect()
        return try {
            val outcomes = coroutineScope {
                due.map { subscription ->
                    async(Dispatchers.IO) {
                        refreshOne(subscription, repository, database, incidents, core)
                    }
                }.awaitAll()
            }
            if (outcomes.any { it == Outcome.RETRY }) WorkResult.retry() else WorkResult.success()
        } finally {
            core.close()
        }
    }

    private suspend fun refreshOne(
        subscription: SubscriptionEntity,
        repository: SubscriptionRepository,
        database: HydraDatabase,
        incidents: IncidentRepository,
        core: CoreRuntimeClient,
    ): Outcome {
        val correlationId = UUID.randomUUID().toString()
        return try {
            val source = repository.readRemoteSource(subscription.id)
            val document = withContext(Dispatchers.IO) {
                NativeSubscriptionFetcher(applicationContext).fetch(source)
            }
            val content = document.toString(Charsets.UTF_8)
            val validation = coreString(
                core,
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VALIDATE_SUBSCRIPTION,
                content,
            )
            val validationObject = JSONObject(validation)
            if (!validationObject.optBoolean("valid", false)) {
                scheduleAfterPermanentFailure(subscription, database)
                recordSafeIncident(incidents, subscription.id, correlationId, "subscription_invalid")
                return Outcome.PERMANENT_FAILURE
            }
            val inspection = coreString(
                core,
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_INSPECT_SUBSCRIPTION,
                content,
            ).toByteArray(Charsets.UTF_8)
            repository.stageValidatedRefresh(
                subscriptionId = subscription.id,
                rawDocument = document,
                inspectionProjection = inspection,
            )
            Outcome.SUCCESS
        } catch (error: Throwable) {
            when (error) {
                is NativeSubscriptionFetcher.HttpStatusException -> {
                    if (error.statusCode == 408 || error.statusCode == 429 || error.statusCode >= 500) {
                        Outcome.RETRY
                    } else {
                        scheduleAfterPermanentFailure(subscription, database)
                        recordSafeIncident(incidents, subscription.id, correlationId, "refresh_http_rejected")
                        Outcome.PERMANENT_FAILURE
                    }
                }
                is IOException,
                is TimeoutCancellationException,
                -> Outcome.RETRY
                is CancellationException -> throw error
                is CoreRuntimeException -> {
                    if (error.retryable) {
                        Outcome.RETRY
                    } else {
                        scheduleAfterPermanentFailure(subscription, database)
                        recordSafeIncident(incidents, subscription.id, correlationId, "core_rejected_refresh")
                        Outcome.PERMANENT_FAILURE
                    }
                }
                else -> {
                    scheduleAfterPermanentFailure(subscription, database)
                    recordSafeIncident(incidents, subscription.id, correlationId, "refresh_internal_failure")
                    Outcome.PERMANENT_FAILURE
                }
            }
        }
    }

    private suspend fun coreString(
        core: CoreRuntimeClient,
        kind: CoreRuntimeProtocol.CoreUtilityKind,
        content: String,
    ): String = withTimeout(CORE_OPERATION_DEADLINE_MILLIS) {
        suspendCancellableCoroutine { continuation ->
            core.coreString(kind, listOf(content)) callback@ { result ->
                if (!continuation.isActive) return@callback
                result.onSuccess { value -> continuation.resume(value) }
                    .onFailure { error -> continuation.resumeWithException(error) }
            }
        }
    }

    private suspend fun scheduleAfterPermanentFailure(
        subscription: SubscriptionEntity,
        database: HydraDatabase,
    ) {
        val now = System.currentTimeMillis()
        database.subscriptions().scheduleNextRefresh(
            subscription.id,
            now + subscription.refreshIntervalMillis.coerceAtLeast(MINIMUM_REFRESH_INTERVAL_MILLIS),
            now,
        )
    }

    private suspend fun recordSafeIncident(
        incidents: IncidentRepository,
        subscriptionId: String,
        correlationId: String,
        code: String,
    ) {
        try {
            incidents.record(
                category = "subscription",
                code = code,
                correlationId = correlationId,
                safePayload = JSONObject()
                    .put("subscriptionId", subscriptionId)
                    .put("worker", "native_refresh_v1")
                    .toString()
                    .toByteArray(Charsets.UTF_8),
            )
        } catch (_: Throwable) {
            // Incident persistence must never replace the refresh outcome.
        }
    }

    companion object {
        private const val MAX_PARALLEL_REFRESHES = 3
        private const val CORE_OPERATION_DEADLINE_MILLIS = 15_000L
        private const val MINIMUM_REFRESH_INTERVAL_MILLIS = 15L * 60L * 1000L
    }
}
