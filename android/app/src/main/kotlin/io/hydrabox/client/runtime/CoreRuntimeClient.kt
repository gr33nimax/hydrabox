package io.hydrabox.client.runtime

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.google.protobuf.ByteString
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.hydrabox.client.singbox.RuntimeEventConsumer
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import org.json.JSONObject

class CoreRuntimeException(
    val code: String,
    val stage: String,
    val retryable: Boolean,
    message: String,
) : IllegalStateException(message)

private const val MAX_AUTOMATIC_REBIND_ATTEMPTS = 3

internal fun shouldRebind(attempt: Int): Boolean = attempt in 1..MAX_AUTOMATIC_REBIND_ATTEMPTS

internal fun epochChangedEvent(
    previousEpoch: String?,
    snapshot: CoreRuntimeProtocol.RuntimeSnapshot,
): Map<String, Any?>? {
    val epoch = snapshot.processEpoch.takeIf { it.isNotBlank() } ?: return null
    return if (previousEpoch != null && previousEpoch != epoch) {
        mapOf("type" to "epochChanged", "processEpoch" to epoch)
    } else {
        null
    }
}

internal class RebindAttemptCounter {
    private var attempt = 0

    fun next(): Boolean = shouldRebind(++attempt)

    fun reset() {
        attempt = 0
    }
}

internal class UtilityRequestRegistry {
    private val callbacks = mutableMapOf<String, (Result<ByteArray>) -> Unit>()

    @Synchronized
    fun register(requestId: String, callback: (Result<ByteArray>) -> Unit): Boolean {
        if (requestId in callbacks) return false
        callbacks[requestId] = callback
        return true
    }

    @Synchronized
    fun remove(requestId: String): ((Result<ByteArray>) -> Unit)? = callbacks.remove(requestId)

    fun complete(response: CoreRuntimeProtocol.CoreUtilityResponse): Boolean {
        val callback = remove(response.requestId) ?: return false
        callback(
            if (response.hasError()) Result.failure(
                CoreRuntimeException(
                    response.error.code,
                    response.error.stage,
                    response.error.retryable,
                    response.error.safeMessage.ifBlank { "HydraCore utility failed." },
                ),
            )
            else Result.success(response.payload.toByteArray()),
        )
        return true
    }

    fun failAll(error: Throwable) {
        val pending = synchronized(this) {
            callbacks.values.toList().also { callbacks.clear() }
        }
        pending.forEach { it(Result.failure(error)) }
    }
}

/** Main-process proxy for the :core binder. It contains no libbox references. */
class CoreRuntimeClient(context: Context) {
    private data class PendingServiceCall(
        val action: (ICoreRuntimeService) -> Unit,
        val onFailure: (Throwable) -> Unit,
    )

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val rebindAttempts = RebindAttemptCounter()
    private val waitingForService = ArrayDeque<PendingServiceCall>()
    private val resultCallbacks = ConcurrentHashMap<String, (Result<Unit>) -> Unit>()
    private val probeResultCallbacks =
        ConcurrentHashMap<String, (Result<CoreRuntimeProtocol.ProbeResult>) -> Unit>()
    private val utilityResultCallbacks = UtilityRequestRegistry()
    private val eventConsumers = CopyOnWriteArrayList<RuntimeEventConsumer>()
    private val ipcExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HydraCoreIpc").apply { isDaemon = true }
    }
    private var service: ICoreRuntimeService? = null
    private var binding = false
    private var bound = false
    @Volatile
    private var latestSnapshot: CoreRuntimeProtocol.RuntimeSnapshot? = null
    @Volatile
    private var latestContract: CoreRuntimeProtocol.CoreContract? = null
    @Volatile
    private var latestPreconnectSessionId: String? = null
    private var lastProcessEpoch: String? = null

    private val listener = object : ICoreRuntimeListener.Stub() {
        override fun onEvent(eventBytes: ByteArray?) {
            val event = runCatching {
                require(eventBytes != null && eventBytes.isNotEmpty())
                CoreRuntimeProtocol.RuntimeEvent.parseFrom(eventBytes)
            }.getOrNull() ?: return
            val previousEpoch = lastProcessEpoch
            val observedEpoch = event.processEpoch.takeIf { it.isNotBlank() }
                ?: event.snapshot.processEpoch.takeIf { event.hasSnapshot() && it.isNotBlank() }
            if (previousEpoch != null && observedEpoch != null && previousEpoch != observedEpoch) {
                utilityResultCallbacks.failAll(
                    CoreRuntimeException(
                        "runtime.ipc.epoch_changed",
                        "ipc",
                        true,
                        "HydraCore process restarted.",
                    ),
                )
            }
            val epochEvent = if (event.hasSnapshot()) {
                val snapshot = event.snapshot
                latestSnapshot = snapshot
                epochChangedEvent(previousEpoch, snapshot).also {
                    lastProcessEpoch = snapshot.processEpoch.takeIf { it.isNotBlank() }
                }
            } else {
                if (observedEpoch != null) lastProcessEpoch = observedEpoch
                null
            }
            if (event.hasCommandResult()) completeCommand(event.commandResult)
            if (event.hasUtilityResult()) utilityResultCallbacks.complete(event.utilityResult)
            if (event.hasProbeResult()) {
                probeResultCallbacks.remove(event.probeResult.sessionId)?.let { completion ->
                    mainHandler.post { completion(Result.success(event.probeResult)) }
                }
            }
            if (event.hasProbeSession() && event.probeSession.state !=
                CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_RUNNING
            ) {
                probeResultCallbacks.remove(event.probeSession.sessionId)?.let { completion ->
                    mainHandler.post {
                        completion(
                            Result.failure(
                                CoreRuntimeException(
                                    "probe.result.unavailable",
                                    "probe_result",
                                    true,
                                    "The probe session finished without a result.",
                                ),
                            ),
                        )
                    }
                }
            }
            val legacyEvents = listOfNotNull(epochEvent) + event.toLegacyEventMaps()
            if (legacyEvents.isNotEmpty()) {
                mainHandler.post {
                    legacyEvents.forEach { legacyEvent ->
                        eventConsumers.forEach { consumer -> consumer.success(legacyEvent) }
                    }
                }
            }
        }
    }

    private val connection: ServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val connected = ICoreRuntimeService.Stub.asInterface(binder)
            val pending: List<PendingServiceCall>
            synchronized(lock) {
                service = connected
                binding = false
                bound = true
                rebindAttempts.reset()
                pending = waitingForService.toList()
                waitingForService.clear()
            }
            runCatching { connected.registerListener(listener) }
                .onFailure { disconnect(it) }
            pending.forEach { call ->
                runCatching { call.action(connected) }
                    .onFailure { error ->
                        call.onFailure(error)
                        disconnect(error)
                    }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            disconnect(CoreRuntimeException("runtime.ipc.disconnected", "ipc", true, "HydraCore process disconnected."))
        }

        override fun onBindingDied(name: ComponentName?) {
            runCatching { appContext.unbindService(connection) }
            synchronized(lock) { bound = false }
            if (synchronized(lock) { rebindAttempts.next() }) {
                disconnect(CoreRuntimeException("runtime.ipc.binding_died", "ipc", true, "HydraCore binding died."))
                connect()
            } else {
                val unavailable = CoreRuntimeException(
                    "runtime.ipc.unavailable",
                    "ipc",
                    false,
                    "HydraCore IPC remains unavailable after automatic rebind attempts.",
                )
                CoreStartupFailureStore(appContext).readFresh()?.toException()?.let(unavailable::initCause)
                disconnect(unavailable, preferStartupFailure = false)
            }
        }

        override fun onNullBinding(name: ComponentName?) {
            runCatching { appContext.unbindService(connection) }
            synchronized(lock) { bound = false }
            disconnect(CoreRuntimeException("runtime.ipc.null_binding", "ipc", false, "HydraCore service refused the binding."))
        }
    }

    fun connect() {
        synchronized(lock) {
            if (service != null || binding) return
            binding = true
        }
        val accepted = runCatching {
            appContext.bindService(
                Intent(appContext, CoreRuntimeService::class.java),
                connection,
                Context.BIND_AUTO_CREATE or Context.BIND_IMPORTANT,
            )
        }.getOrElse {
            disconnect(
                CoreRuntimeException(
                    "runtime.ipc.bind_exception",
                    "ipc_bind",
                    true,
                    "HydraCore service binding failed before the runtime started.",
                ),
            )
            return
        }
        if (!accepted) {
            disconnect(CoreRuntimeException("runtime.ipc.bind_failed", "ipc", true, "HydraCore service could not be started."))
            return
        }
        synchronized(lock) { bound = true }
        mainHandler.postDelayed({
            val timedOut = synchronized(lock) { binding && service == null }
            if (!timedOut) return@postDelayed
            runCatching { appContext.unbindService(connection) }
            synchronized(lock) { bound = false }
            disconnect(
                CoreRuntimeException(
                    "runtime.ipc.bind_timeout",
                    "ipc",
                    true,
                    "HydraCore service did not accept the binding in time.",
                ),
            )
        }, SERVICE_BIND_DEADLINE_MILLIS)
    }

    fun reconnectFromUser() {
        synchronized(lock) { rebindAttempts.reset() }
        connect()
    }

    fun close() {
        val current = synchronized(lock) {
            val value = service
            service = null
            binding = false
            value
        }
        if (current != null) runCatching { current.unregisterListener(listener) }
        if (bound) runCatching { appContext.unbindService(connection) }
        bound = false
        ipcExecutor.shutdownNow()
        failPending(CoreRuntimeException("runtime.ipc.closed", "ipc", true, "HydraCore client was closed."))
    }

    fun registerEventConsumer(consumer: RuntimeEventConsumer) {
        eventConsumers += consumer
        latestSnapshot?.let { snapshot ->
            mainHandler.post {
                snapshot.toLegacyEventMaps().forEach(consumer::success)
            }
        }
    }

    fun unregisterEventConsumer(consumer: RuntimeEventConsumer) {
        eventConsumers -= consumer
    }

    fun start(
        config: ByteArray,
        useVpn: Boolean,
        restartCore: Boolean = false,
        applyConfig: Boolean = false,
        interactiveDeadlineMillis: Long = 0L,
        source: String = "ui",
        callback: (Result<Unit>) -> Unit,
    ) {
        val start = CoreRuntimeProtocol.StartRuntime.newBuilder()
            .setMode(
                if (useVpn) CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN
                else CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY,
            )
            .setCompiledConfig(ByteString.copyFrom(config))
            .setConfigSha256(ByteString.copyFrom(MessageDigest.getInstance("SHA-256").digest(config)))
            .setRestartCore(restartCore)
            .setApplyConfig(applyConfig)
            .setInteractiveDeadlineMillis(interactiveDeadlineMillis)
            .setSource(source)
            .build()
        submit(
            CoreRuntimeProtocol.RuntimeCommand.newBuilder()
                .setKind(CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START)
                .setStart(start),
            callback,
        )
    }

    fun stop(reason: String, callback: (Result<Unit>) -> Unit) {
        submit(
            CoreRuntimeProtocol.RuntimeCommand.newBuilder()
                .setKind(CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP)
                .setStop(CoreRuntimeProtocol.StopRuntime.newBuilder().setReason(reason)),
            callback,
        )
    }

    fun reload(callback: (Result<Unit>) -> Unit) {
        submit(
            CoreRuntimeProtocol.RuntimeCommand.newBuilder()
                .setKind(CoreRuntimeProtocol.CommandKind.COMMAND_KIND_RELOAD)
                .setReload(CoreRuntimeProtocol.ReloadRuntime.getDefaultInstance()),
            callback,
        )
    }

    fun selectOutbound(groupId: String, outboundId: String, callback: (Result<Unit>) -> Unit) {
        submit(
            CoreRuntimeProtocol.RuntimeCommand.newBuilder()
                .setKind(CoreRuntimeProtocol.CommandKind.COMMAND_KIND_SELECT_OUTBOUND)
                .setSelectOutbound(
                    CoreRuntimeProtocol.SelectOutbound.newBuilder()
                        .setGroupId(groupId)
                        .setOutboundId(outboundId),
                ),
            callback,
        )
    }

    fun startProbe(
        groupId: String,
        outboundIds: List<String>,
        url: String,
        timeoutMillis: Int,
        concurrency: Int,
        deadlineMillis: Int,
        config: ByteArray? = null,
        callback: (Result<Map<String, Any?>>) -> Unit,
    ) {
        val sessionId = UUID.randomUUID().toString()
        submitProbe(
            sessionId = sessionId,
            groupId = groupId,
            outboundIds = outboundIds,
            url = url,
            timeoutMillis = timeoutMillis,
            concurrency = concurrency,
            deadlineMillis = deadlineMillis,
            config = config,
        ) { result ->
            callback(
                result.map {
                    mapOf(
                        "id" to sessionId,
                        "state" to "running",
                        "startedAt" to System.currentTimeMillis(),
                        "total" to outboundIds.size,
                        "completed" to 0,
                    )
                },
            )
        }
    }

    fun preconnectProbe(
        config: ByteArray,
        groupId: String,
        outboundId: String,
        url: String,
        timeoutMillis: Int,
        deadlineMillis: Int,
        callback: (Result<CoreRuntimeProtocol.ProbeResult>) -> Unit,
    ) {
        val sessionId = UUID.randomUUID().toString()
        latestPreconnectSessionId = sessionId
        probeResultCallbacks[sessionId] = { result ->
            if (latestPreconnectSessionId == sessionId) latestPreconnectSessionId = null
            callback(result)
        }
        submitProbe(
            sessionId = sessionId,
            groupId = groupId,
            outboundIds = listOf(outboundId),
            url = url,
            timeoutMillis = timeoutMillis,
            concurrency = 1,
            deadlineMillis = deadlineMillis,
            config = config,
        ) { result ->
            result.onFailure { error ->
                probeResultCallbacks.remove(sessionId)?.let { completion ->
                    mainHandler.post { completion(Result.failure(error)) }
                }
            }
        }
        mainHandler.postDelayed({
            probeResultCallbacks.remove(sessionId)?.invoke(
                Result.failure(
                    CoreRuntimeException(
                        "probe.result.deadline",
                        "probe_result",
                        true,
                        "The probe result deadline expired.",
                    ),
                ),
            )
        }, deadlineMillis.coerceIn(timeoutMillis, 120_000).toLong() + 500L)
    }

    fun cancelPreconnectProbe(callback: (Result<Unit>) -> Unit) {
        val sessionId = latestPreconnectSessionId
        if (sessionId == null) {
            callback(Result.success(Unit))
            return
        }
        cancelProbe(sessionId) { result ->
            latestPreconnectSessionId = null
            probeResultCallbacks.remove(sessionId)
            callback(result.map { Unit })
        }
    }

    private fun submitProbe(
        sessionId: String,
        groupId: String,
        outboundIds: List<String>,
        url: String,
        timeoutMillis: Int,
        concurrency: Int,
        deadlineMillis: Int,
        config: ByteArray?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val request = CoreRuntimeProtocol.ProbeRequest.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setSessionId(sessionId)
            .setGroupId(groupId)
            .addAllOutboundIds(outboundIds.ifEmpty { listOf(ALL_OUTBOUNDS) })
            .setUrl(url)
            .setTimeoutMillis(timeoutMillis.coerceIn(500, 120_000))
            .setConcurrency(concurrency.coerceIn(1, 32))
            .setDeadlineAtMillis(System.currentTimeMillis() + deadlineMillis.coerceIn(timeoutMillis, 120_000))
        if (config != null) {
            request.setCompiledConfig(ByteString.copyFrom(config))
            request.setConfigSha256(ByteString.copyFrom(
                MessageDigest.getInstance("SHA-256").digest(config),
            ))
        }
        submit(
            CoreRuntimeProtocol.RuntimeCommand.newBuilder()
                .setKind(CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START_PROBE)
                .setStartProbe(request),
            callback,
        )
    }

    fun getProbeSession(sessionId: String, callback: (Result<Map<String, Any?>>) -> Unit) {
        snapshot { result ->
            callback(
                result.mapCatching { snapshot ->
                    val session = snapshot.probeSessionsList.firstOrNull { it.sessionId == sessionId }
                        ?: throw CoreRuntimeException(
                            "probe.session.missing",
                            "probe_session",
                            false,
                            "The probe session is unavailable.",
                        )
                    mapOf(
                        "id" to session.sessionId,
                        "state" to session.state.name,
                        "startedAt" to session.startedAtMillis,
                        "completedAt" to session.finishedAtMillis,
                        "total" to session.requestedCount,
                        "completed" to session.completedCount,
                    )
                },
            )
        }
    }

    fun cancelProbe(sessionId: String, callback: (Result<Map<String, Any?>>) -> Unit) {
        submit(
            CoreRuntimeProtocol.RuntimeCommand.newBuilder()
                .setKind(CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_PROBE)
                .setCancelProbe(CoreRuntimeProtocol.CancelProbe.newBuilder().setSessionId(sessionId)),
        ) { result ->
            callback(result.map { mapOf("id" to sessionId, "state" to "cancelled") })
        }
    }

    fun cancelRuntimeChallenge(challengeId: String, callback: (Result<Unit>) -> Unit) {
        submit(
            CoreRuntimeProtocol.RuntimeCommand.newBuilder()
                .setKind(
                    CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_RUNTIME_CHALLENGE,
                )
                .setCancelRuntimeChallenge(
                    CoreRuntimeProtocol.CancelRuntimeChallenge.newBuilder()
                        .setChallengeId(challengeId),
                ),
            callback,
        )
    }

    fun snapshot(callback: (Result<CoreRuntimeProtocol.RuntimeSnapshot>) -> Unit) {
        withService(
            onFailure = { error -> mainHandler.post { callback(Result.failure(error)) } },
        ) { connected ->
            runCatching { CoreRuntimeProtocol.RuntimeSnapshot.parseFrom(connected.getSnapshot()) }
                .onSuccess {
                    latestSnapshot = it
                    mainHandler.post { callback(Result.success(it)) }
                }
                .onFailure { mainHandler.post { callback(Result.failure(it)) } }
        }
    }

    /** Last authoritative snapshot received from or read from the :core process. */
    fun cachedSnapshot(): CoreRuntimeProtocol.RuntimeSnapshot? = latestSnapshot

    fun cachedProcessEpoch(): String =
        latestSnapshot?.processEpoch?.takeIf { it.isNotBlank() }
            ?: latestContract?.processEpoch.orEmpty()

    fun contract(callback: (Result<CoreRuntimeProtocol.CoreContract>) -> Unit) {
        withService(
            onFailure = { error -> mainHandler.post { callback(Result.failure(error)) } },
        ) { connected ->
            runCatching { CoreRuntimeProtocol.CoreContract.parseFrom(connected.getContract()) }
                .onSuccess {
                    latestContract = it
                    mainHandler.post { callback(Result.success(it)) }
                }
                .onFailure { mainHandler.post { callback(Result.failure(it)) } }
        }
    }

    fun coreString(
        kind: CoreRuntimeProtocol.CoreUtilityKind,
        arguments: List<String> = emptyList(),
        callback: (Result<String>) -> Unit,
    ) {
        utility(kind, arguments.map { it.toByteArray(Charsets.UTF_8) }) { result ->
            callback(result.map { it.toString(Charsets.UTF_8) })
        }
    }

    fun checkConfig(config: String, callback: (Result<Unit>) -> Unit) {
        utility(
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_CHECK_CONFIG,
            listOf(config.toByteArray(Charsets.UTF_8)),
        ) { result -> callback(result.map { Unit }) }
    }

    fun lookupOutboundExternalInfo(
        outboundId: String,
        callback: (Result<Map<String, String>>) -> Unit,
    ) {
        val id = UUID.randomUUID().toString()
        val request = CoreRuntimeProtocol.CoreUtilityRequest.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setRequestId(id)
            .setKind(CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_LOOKUP_OUTBOUND_EXTERNAL_INFO)
            .addArguments(ByteString.copyFrom(outboundId.toByteArray(Charsets.UTF_8)))
            .build()
        val completion: (Result<ByteArray>) -> Unit = { result ->
            mainHandler.post {
                callback(
                    result.mapCatching { payload ->
                        val value = CoreRuntimeProtocol.OutboundExternalInfo.parseFrom(payload)
                        mapOf("ip" to value.ipAddress, "countryCode" to value.countryCode)
                    },
                )
            }
        }
        if (!utilityResultCallbacks.register(id, completion)) {
            completion(
                Result.failure(
                    CoreRuntimeException(
                        "core.utility.duplicate",
                        "utility_request",
                        false,
                        "The utility request is already pending.",
                    ),
                ),
            )
            return
        }
        mainHandler.postDelayed({
            utilityResultCallbacks.remove(id)?.invoke(
                Result.failure(
                    CoreRuntimeException(
                        "core.utility.deadline",
                        "utility_result",
                        true,
                        "HydraCore utility did not return a result.",
                    ),
                ),
            )
        }, UTILITY_DEADLINE_MILLIS)
        withService(
            onFailure = { error ->
                utilityResultCallbacks.remove(id)?.invoke(Result.failure(error))
            },
        ) { connected ->
            ipcExecutor.execute {
                runCatching {
                    CoreRuntimeProtocol.CoreUtilityResponse.parseFrom(
                        connected.executeUtility(request.toByteArray()),
                    )
                }.onSuccess { acknowledgement ->
                    if (acknowledgement.hasError()) {
                        utilityResultCallbacks.remove(id)?.invoke(Result.failure(acknowledgement.error.toException()))
                    } else if (acknowledgement.requestId != id) {
                        utilityResultCallbacks.remove(id)?.invoke(
                            Result.failure(
                                CoreRuntimeException(
                                    "core.utility.invalid_response",
                                    "utility_acknowledgement",
                                    false,
                                    "HydraCore returned an invalid utility response.",
                                ),
                            ),
                        )
                    }
                }.onFailure { error ->
                    utilityResultCallbacks.remove(id)?.invoke(Result.failure(error))
                }
            }
        }
    }

    fun updateNotificationPresentation(
        value: CoreRuntimeProtocol.NotificationPresentation,
        callback: (Result<Unit>) -> Unit,
    ) {
        utility(
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_UPDATE_NOTIFICATION,
            listOf(value.toByteArray()),
        ) { result -> callback(result.map { Unit }) }
    }

    fun refreshRuntimeFlags(callback: (Result<Unit>) -> Unit = {}) {
        utility(
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_REFRESH_RUNTIME_FLAGS,
            emptyList(),
        ) { result -> callback(result.map { Unit }) }
    }

    fun setUiForeground(foreground: Boolean, callback: (Result<Unit>) -> Unit = {}) {
        val value = CoreRuntimeProtocol.UiForegroundState.newBuilder()
            .setForeground(foreground)
            .build()
        utility(
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_SET_UI_FOREGROUND,
            listOf(value.toByteArray()),
        ) { result -> callback(result.map { Unit }) }
    }

    fun performanceCounters(callback: (Result<Map<String, Long>>) -> Unit) {
        utility(
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_PERFORMANCE_COUNTERS,
            emptyList(),
        ) { result ->
            callback(
                result.mapCatching { bytes ->
                    val json = JSONObject(bytes.toString(Charsets.UTF_8))
                    val map = mutableMapOf<String, Long>()
                    for (key in json.keys()) {
                        map[key] = json.optLong(key)
                    }
                    map
                },
            )
        }
    }

    private fun utility(
        kind: CoreRuntimeProtocol.CoreUtilityKind,
        arguments: List<ByteArray>,
        callback: (Result<ByteArray>) -> Unit,
    ) {
        val id = UUID.randomUUID().toString()
        val request = CoreRuntimeProtocol.CoreUtilityRequest.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setRequestId(id)
            .setKind(kind)
            .addAllArguments(arguments.map { ByteString.copyFrom(it) })
            .build()
        withService(
            onFailure = { error -> mainHandler.post { callback(Result.failure(error)) } },
        ) { connected ->
            ipcExecutor.execute {
                val result = runCatching {
                    val response = CoreRuntimeProtocol.CoreUtilityResponse.parseFrom(
                        connected.executeUtility(request.toByteArray()),
                    )
                    if (response.hasError()) throw response.error.toException()
                    response.payload.toByteArray()
                }
                mainHandler.post { callback(result) }
            }
        }
    }

    private fun submit(
        builder: CoreRuntimeProtocol.RuntimeCommand.Builder,
        callback: (Result<Unit>) -> Unit,
    ) {
        val id = UUID.randomUUID().toString()
        val command = builder
            .setSchemaVersion(SCHEMA_VERSION)
            .setCommandId(id)
            .setIssuedAtMillis(System.currentTimeMillis())
            .build()
        val resultDeadline = if (
            command.kind == CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START
        ) IPC_LIVENESS_DEADLINE_MILLIS else COMMAND_RESULT_DEADLINE_MILLIS
        resultCallbacks[id] = callback
        mainHandler.postDelayed({
            resultCallbacks.remove(id)?.invoke(
                Result.failure(
                    CoreRuntimeException(
                        if (command.kind == CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START) {
                            "runtime.ipc.lost"
                        } else {
                            "runtime.command.deadline"
                        },
                        "command_result",
                        true,
                        "HydraCore IPC did not return a command result.",
                    ),
                ),
            )
        }, resultDeadline)
        withService(onFailure = { }) { connected ->
            val receiptResult = runCatching {
                CoreRuntimeProtocol.CommandReceipt.parseFrom(connected.submit(command.toByteArray()))
            }
            receiptResult.onSuccess { receipt ->
                if (receipt.status != CoreRuntimeProtocol.ReceiptStatus.RECEIPT_STATUS_ACCEPTED) {
                    resultCallbacks.remove(id)?.let { completion ->
                        mainHandler.post { completion(Result.failure(receipt.rejection.toException())) }
                    }
                }
            }.onFailure { error ->
                resultCallbacks.remove(id)?.let { completion ->
                    mainHandler.post { completion(Result.failure(error)) }
                }
            }
        }
    }

    private fun withService(
        onFailure: (Throwable) -> Unit,
        action: (ICoreRuntimeService) -> Unit,
    ) {
        val connected = synchronized(lock) {
            service?.also { return@synchronized it }
            waitingForService += PendingServiceCall(action, onFailure)
            null
        }
        if (connected != null) action(connected) else connect()
    }

    private fun completeCommand(result: CoreRuntimeProtocol.CommandResult) {
        val callback = resultCallbacks.remove(result.commandId) ?: return
        mainHandler.post {
            if (result.outcome == CoreRuntimeProtocol.CommandOutcome.COMMAND_OUTCOME_SUCCEEDED) {
                callback(Result.success(Unit))
            } else {
                callback(Result.failure(result.error.toException()))
            }
        }
    }

    private fun disconnect(error: Throwable, preferStartupFailure: Boolean = true) {
        val reportedError = if (preferStartupFailure) {
            CoreStartupFailureStore(appContext).readFresh()?.toException() ?: error
        } else {
            error
        }
        val pending = synchronized(lock) {
            val values = waitingForService.toList()
            waitingForService.clear()
            service = null
            binding = false
            values
        }
        pending.forEach { call -> mainHandler.post { call.onFailure(reportedError) } }
        failPending(reportedError)
        mainHandler.post {
            eventConsumers.forEach { consumer ->
                val coreError = reportedError as? CoreRuntimeException
                consumer.error(
                    coreError?.code ?: "runtime_ipc_disconnected",
                    coreError?.message ?: "HydraCore process disconnected.",
                    coreError?.stage,
                )
            }
        }
    }

    private fun failPending(error: Throwable) {
        val callbacks = resultCallbacks.values.toList()
        resultCallbacks.clear()
        val probeCallbacks = probeResultCallbacks.values.toList()
        probeResultCallbacks.clear()
        utilityResultCallbacks.failAll(error)
        mainHandler.post {
            callbacks.forEach { it(Result.failure(error)) }
            probeCallbacks.forEach { it(Result.failure(error)) }
        }
    }

    private fun CoreRuntimeProtocol.CoreError.toException(): CoreRuntimeException =
        CoreRuntimeException(code, stage, retryable, safeMessage.ifBlank { "HydraCore command failed." })

    private fun CoreRuntimeProtocol.RuntimeEvent.toLegacyEventMaps(): List<Map<String, Any?>> = when {
        hasSnapshot() -> snapshot.toLegacyEventMaps()
        hasCommandResult() -> listOf(mapOf(
            "type" to "commandResult",
            "commandId" to commandResult.commandId,
            "outcome" to commandResult.outcome.name,
            "generation" to commandResult.generation,
            "errorCode" to commandResult.error.code,
            "error" to commandResult.error.safeMessage,
        ))
        hasProbeSession() -> listOf(mapOf(
            "type" to "urlTestSession",
            "sessionId" to probeSession.sessionId,
            "state" to probeSession.state.name,
            "completedCount" to probeSession.completedCount,
            "requestedCount" to probeSession.requestedCount,
        ))
        hasProbeResult() -> listOf(mapOf(
            "type" to "urlTestResult",
            "sessionId" to probeResult.sessionId,
            "tag" to probeResult.outboundId,
            "delay" to probeResult.delayMillis,
            "time" to probeResult.measuredAtMillis,
            "errorCode" to probeResult.error.code,
            "error" to probeResult.error.safeMessage,
        ))
        hasLog() -> listOf(mapOf(
            "type" to "log",
            "level" to log.level,
            "message" to log.safeMessage,
        ))
        hasTransportHealth() -> listOf(transportHealth.toLegacyTransportHealthMap())
        else -> emptyList()
    }

    private fun CoreRuntimeProtocol.RuntimeSnapshot.toLegacyEventMaps(): List<Map<String, Any?>> =
        listOf(
            toLegacyStateMap(),
            mapOf(
                "type" to "status",
                "uplink" to traffic.uplinkBytesPerSecond,
                "downlink" to traffic.downlinkBytesPerSecond,
                "uplinkTotal" to traffic.uplinkTotalBytes,
                "downlinkTotal" to traffic.downlinkTotalBytes,
                "trafficAvailable" to true,
            ),
            mapOf(
                "type" to "groups",
                "runtimeGeneration" to generation,
                "pendingSelectedOutboundIds" to pendingSelectedOutboundIdsMap,
                "groups" to outboundGroupsList.map { group ->
                    mapOf(
                        "tag" to group.groupId,
                        "selected" to group.selectedOutboundId,
                        "items" to group.outboundsList.map { item ->
                            mapOf(
                                "tag" to item.outboundId,
                                "delay" to item.delayMillis,
                                "time" to item.measuredAtMillis,
                                "status" to item.status,
                                "errorCode" to item.error.code,
                                "error" to item.error.safeMessage,
                            )
                        },
                    )
                },
            ),
            mapOf(
                "type" to "urlTestSessions",
                "runtimeGeneration" to generation,
                "sequence" to lastSequence,
                "reset" to true,
                "sessions" to probeSessionsList.map { session ->
                    mapOf(
                        "id" to session.sessionId,
                        "state" to session.state.name,
                        "startedAt" to session.startedAtMillis,
                        "completedAt" to session.finishedAtMillis,
                        "total" to session.requestedCount,
                        "completed" to session.completedCount,
                    )
                },
            ),
            transportHealth.toLegacyTransportHealthMap(),
        )

    private fun CoreRuntimeProtocol.TransportHealthSnapshot.toLegacyTransportHealthMap(): Map<String, Any?> =
        mapOf(
            "type" to "transportHealth",
            "applicable" to applicable,
            "state" to when (state) {
                CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_STARTING -> "starting"
                CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_WAITING_USER -> "waiting_user"
                CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_HEALTHY -> "healthy"
                CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_DEGRADED -> "degraded"
                CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_RECOVERING -> "recovering"
                CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_FAILED -> "failed"
                else -> ""
            },
            "activeLanes" to activeLanes,
            "totalLanes" to totalLanes,
            "demand" to demand,
            "lastProgressAt" to lastProgressAtMillis,
            "lastAggregateProgressAt" to lastAggregateProgressAtMillis,
            "lastInboundAt" to lastInboundAtMillis,
            "observedAt" to observedAtMillis,
            "runtimeGeneration" to runtimeGeneration,
            "networkGeneration" to networkGeneration,
            "failure" to if (hasFailure()) mapOf(
                "stage" to failure.stage,
                "kind" to failure.kind,
                "code" to failure.code,
                "retryAfterMillis" to failure.retryAfterMillis,
                "challengeId" to failure.challengeId,
                "domain" to failure.failureDomain,
                "terminal" to failure.failureTerminal,
            ) else null,
            "challenge" to if (hasChallenge()) mapOf(
                "id" to challenge.challengeId,
                "kind" to challenge.kind,
                "url" to challenge.url,
                "createdAt" to challenge.createdAtMillis,
                "expiresAt" to challenge.expiresAtMillis,
            ) else null,
        )

    private fun CoreRuntimeProtocol.RuntimeSnapshot.toLegacyStateMap(): Map<String, Any?> = mapOf(
        "type" to "state",
        "running" to (state == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING),
        "state" to state.name,
        "mode" to when (mode) {
            CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN -> "vpn"
            CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY -> "proxy"
            else -> ""
        },
        "runtimeGeneration" to generation,
        "uplink" to traffic.uplinkBytesPerSecond,
        "downlink" to traffic.downlinkBytesPerSecond,
        "uplinkTotal" to traffic.uplinkTotalBytes,
        "downlinkTotal" to traffic.downlinkTotalBytes,
        "lastError" to lastError.safeMessage,
        "errorCode" to lastError.code,
        "probeLastError" to probeLastError.safeMessage,
        "probeErrorCode" to probeLastError.code,
        "sequence" to lastSequence,
        "processEpoch" to processEpoch,
    )

    companion object {
        private const val SCHEMA_VERSION = 2
        private const val COMMAND_RESULT_DEADLINE_MILLIS = 30_000L
        // Binding may consume 10 seconds, followed by the bounded start and
        // visible challenge phases. This detects a lost IPC channel, not a
        // failed runtime start.
        private const val IPC_LIVENESS_DEADLINE_MILLIS = 180_000L
        private const val SERVICE_BIND_DEADLINE_MILLIS = 10_000L
        private const val ALL_OUTBOUNDS = "*"
    }
}
