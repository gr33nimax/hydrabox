package io.hydrabox.client.core

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.hydrabox.client.BuildConfig
import io.hydrabox.client.HydraBoxApplication
import io.hydrabox.client.generated.CheckedCoreReleaseMessage
import io.hydrabox.client.generated.CoreBundleSlotMessage
import io.hydrabox.client.generated.CoreCandidateProbeMessage
import io.hydrabox.client.generated.CoreManagerHostApi
import io.hydrabox.client.generated.CoreManagerStateMessage
import io.hydrabox.client.generated.FlutterError
import io.hydrabox.client.runtime.CoreRuntimeClient
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Explicit, typed bridge for the manual HydraCore lifecycle. */
class CoreManagerHostApiHandler(
    context: Context,
    private val runtimeClient: () -> CoreRuntimeClient,
    private val cycleCoreProcess: (
        mutation: () -> Unit,
        callback: (Result<Unit>) -> Unit,
    ) -> Unit,
) : CoreManagerHostApi {
    private val appContext = context.applicationContext
    private val manager = CoreBundleManager(appContext)
    private val updater = CoreBundleUpdater(appContext)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HydraCoreManager").apply { isDaemon = true }
    }

    override fun getState(callback: (Result<CoreManagerStateMessage>) -> Unit) {
        executor.execute {
            val state = runCatching(manager::readState)
            mainHandler.post {
                state.onFailure {
                    callback(failure("core.state.unavailable", "HydraCore state is unavailable."))
                }.onSuccess { bundleState ->
                    // Core Manager must remain usable even when the active core cannot bind.
                    runtimeClient().snapshot { snapshot ->
                        val disconnected = snapshot.getOrNull()?.state ==
                            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED
                        callback(
                            Result.success(
                                bundleState.toMessage(
                                    runtimeDisconnected = disconnected,
                                    recoveryRollbackAllowed = disconnected ||
                                        (snapshot.isFailure && canRecoverUnreachableRuntime()),
                                ),
                            ),
                        )
                    }
                }
            }
        }
    }

    override fun checkLatest(callback: (Result<CheckedCoreReleaseMessage>) -> Unit) {
        execute("core.update.check_failed", "HydraCore update check failed.", callback) {
            val checked = updater.checkLatest()
            CheckedCoreReleaseMessage(
                releaseId = checked.releaseId,
                releaseSequence = checked.releaseSequence,
                version = checked.version,
                publishedAt = checked.publishedAt,
                coreApiMajor = checked.coreApiMajor.toLong(),
                coreApiMinor = checked.coreApiMinor.toLong(),
                artifactSizeBytes = checked.artifactSizeBytes,
            )
        }
    }

    override fun downloadChecked(callback: (Result<CoreBundleSlotMessage>) -> Unit) {
        execute("core.update.download_failed", "HydraCore download failed.", callback) {
            updater.downloadChecked().toMessage()
        }
    }

    override fun probeCandidate(callback: (Result<CoreCandidateProbeMessage>) -> Unit) {
        executor.execute {
            val prepared = runCatching {
                requireNotNull(manager.readState().candidate) to validationFixtures()
            }.getOrElse {
                mainHandler.post {
                    callback(failure("core.probe.fixture_failed", "HydraCore fixtures are unavailable."))
                }
                return@execute
            }
            val (candidate, fixtures) = prepared
            mainHandler.post {
                CoreCandidateProbeClient(appContext).probe(fixtures) { result ->
                    result.onFailure {
                        callback(failure("core.probe.failed", "HydraCore candidate probe failed."))
                    }.onSuccess { report ->
                        callback(
                            Result.success(
                                CoreCandidateProbeMessage(
                                    healthy = report.healthy,
                                    candidate = candidate.toMessage(),
                                    validatedFixtureCount = report.validatedFixtureCount.toLong(),
                                    errorCode = report.error.code.takeIf(String::isNotBlank),
                                ),
                            ),
                        )
                    }
                }
            }
        }
    }

    override fun activateCandidate(callback: (Result<CoreManagerStateMessage>) -> Unit) {
        requireDisconnected("core.activate.runtime_connected", callback) {
            cycleCoreProcess(
                { manager.activateCandidate(runtimeDisconnected = true) },
            ) { result ->
                result.onFailure {
                    callback(failure("core.activate.failed", "HydraCore activation failed."))
                }.onSuccess { getState(callback) }
            }
        }
    }

    override fun rollback(callback: (Result<CoreManagerStateMessage>) -> Unit) {
        requireDisconnected(
            "core.rollback.runtime_connected",
            callback,
            allowUnreachableRecovery = true,
        ) {
            cycleCoreProcess(
                { manager.restorePreviousOrEmbedded() },
            ) { result ->
                result.onFailure {
                    callback(failure("core.rollback.failed", "HydraCore rollback failed."))
                }.onSuccess { getState(callback) }
            }
        }
    }

    fun close() {
        executor.shutdownNow()
    }

    private fun requireDisconnected(
        errorCode: String,
        callback: (Result<CoreManagerStateMessage>) -> Unit,
        allowUnreachableRecovery: Boolean = false,
        action: () -> Unit,
    ) {
        runtimeClient().snapshot snapshot@ { result ->
            val snapshot = result.getOrNull()
            val disconnected = snapshot?.state ==
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED
            val recoverable = result.isFailure && allowUnreachableRecovery &&
                canRecoverUnreachableRuntime()
            if (!disconnected && !recoverable) {
                callback(failure(errorCode, "Disconnect HydraCore before changing its version."))
                return@snapshot
            }
            action()
        }
    }

    private fun canRecoverUnreachableRuntime(): Boolean {
        if (HydraBoxApplication.isRecordedServiceAlive()) return false
        val activityManager = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val processes = activityManager.runningAppProcesses ?: return false
        return processes.none { it.processName == "${appContext.packageName}:core" }
    }

    private fun validationFixtures(): List<ByteArray> = buildList {
        add(SMOKE_CONFIG.toByteArray(Charsets.UTF_8))
        val activeConfig = HydraBoxApplication.configFile
        if (activeConfig.isFile && activeConfig.length() in 1..MAX_ACTIVE_FIXTURE_BYTES.toLong()) {
            val bytes = activeConfig.readBytes()
            if (!bytes.contentEquals(first())) add(bytes)
        }
    }

    private fun <T> execute(
        errorCode: String,
        safeMessage: String,
        callback: (Result<T>) -> Unit,
        operation: () -> T,
    ) {
        executor.execute {
            val result = runCatching(operation).fold(
                onSuccess = { Result.success(it) },
                onFailure = { failure(errorCode, safeMessage) },
            )
            mainHandler.post { callback(result) }
        }
    }

    private fun CoreBundleState.toMessage(
        runtimeDisconnected: Boolean,
        recoveryRollbackAllowed: Boolean,
    ) =
        CoreManagerStateMessage(
            embeddedVersion = BuildConfig.EMBEDDED_HYDRACORE_VERSION,
            active = active?.toMessage(),
            previous = previous?.toMessage(),
            candidate = candidate?.toMessage(),
            trustedKeyRingAvailable = trustedKeyRingAvailable,
            usingEmbeddedFallback = usingEmbeddedFallback,
            runtimeDisconnected = runtimeDisconnected,
            recoveryRollbackAllowed = recoveryRollbackAllowed,
        )

    private fun InstalledCoreBundle.toMessage() = CoreBundleSlotMessage(
        releaseSequence = releaseSequence,
        version = version,
        abi = abi,
        sha256 = sha256,
    )

    private fun <T> failure(code: String, message: String): Result<T> =
        Result.failure(FlutterError(code, message, null))

    companion object {
        private const val MAX_ACTIVE_FIXTURE_BYTES = 240 * 1024
        private const val SMOKE_CONFIG =
            "{\"log\":{\"disabled\":true},\"outbounds\":[{\"type\":\"direct\",\"tag\":\"direct\"}]," +
                "\"route\":{\"final\":\"direct\"}}"
    }
}
