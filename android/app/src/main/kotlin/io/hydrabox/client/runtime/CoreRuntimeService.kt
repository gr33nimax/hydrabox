package io.hydrabox.client.runtime

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.RemoteCallbackList
import android.util.AtomicFile
import android.util.Log
import com.google.protobuf.ByteString
import com.google.protobuf.InvalidProtocolBufferException
import io.hydrabox.client.HydraBoxApplication
import io.hydrabox.client.DesiredRuntime
import io.hydrabox.client.DesiredRuntimeDecision
import io.hydrabox.client.DesiredRuntimeEvent
import io.hydrabox.client.desiredRuntimeDecision
import io.hydrabox.client.desiredRuntimeTransition
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.hydrabox.client.singbox.HydraBoxProxyService
import io.hydrabox.client.singbox.HydraBoxService
import io.hydrabox.client.singbox.HydraBoxDiagnostics
import io.hydrabox.client.singbox.HydraBoxVpnService
import io.hydrabox.client.singbox.HydraBoxForegroundNotification
import io.hydrabox.client.singbox.RuntimeEventConsumer
import io.hydrabox.client.singbox.SingboxController
import io.hydrabox.client.singbox.NativeCoreEnvironment
import io.hydrabox.client.singbox.HydraBoxDefaultNetworkMonitor
import io.nekohasekai.libbox.Libbox
import org.json.JSONObject
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

internal object CoreProcessIdentity {
    val epoch: String = UUID.randomUUID().toString()
    val sequence = AtomicLong(0L)
    val generation = AtomicLong(0L)
}

private fun shortId(value: String): String = value.take(8).ifEmpty { "none" }

internal fun nativeSourceLabel(): String = "embedded"

private fun shortHex(bytes: ByteArray): String =
    if (bytes.isEmpty()) "none" else bytes.take(4).joinToString("") { "%02x".format(it.toInt() and 0xff) }

internal enum class ProbeExecutionMode {
    EPHEMERAL,
    MANAGED,
    REJECT_MISSING_PLAN,
}

internal fun selectProbeExecutionMode(
    runtimeRunning: Boolean,
    compiledConfigBytes: Int,
): ProbeExecutionMode = when {
    compiledConfigBytes > 0 -> ProbeExecutionMode.EPHEMERAL
    runtimeRunning -> ProbeExecutionMode.MANAGED
    else -> ProbeExecutionMode.REJECT_MISSING_PLAN
}

internal fun pruneAliases(
    aliases: Map<String, String>,
    sessions: Iterable<CoreRuntimeProtocol.ProbeSession>,
): Map<String, String> {
    val terminalSessionIds = sessions.asSequence()
        .filter { it.state in setOf(
            CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_COMPLETED,
            CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_PARTIAL,
            CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_CANCELLED,
            CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_TIMED_OUT,
        ) }
        .map { it.sessionId }
        .toSet()
    return aliases.filterValues { it !in terminalSessionIds }
}

internal fun notificationStatusFor(
    state: CoreRuntimeProtocol.RuntimeState,
): String? = when (state) {
    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING -> "Connecting"
    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING -> "Connected"
    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING -> "Disconnecting"
    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED -> "Failed"
    else -> null
}

/**
 * Sole binder owner of native runtime state. The UI process only exchanges
 * versioned protobuf bytes with this service and never initializes libbox.
 */
class CoreRuntimeService : Service() {
    private val processEpoch = CoreProcessIdentity.epoch
    private val sequence = CoreProcessIdentity.sequence
    private val generation = CoreProcessIdentity.generation
    private val state = AtomicReference(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED)
    private val mode = AtomicReference(CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED)
    private val listeners = RemoteCallbackList<ICoreRuntimeListener>()
    private val commandExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HydraCoreRuntimeCommands").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val selectedOutbounds = linkedMapOf<String, String>()
    private val snapshotLock = Any()
    private var activeConfigSha256 = ByteArray(0)
    private var lastError: CoreRuntimeProtocol.CoreError? = null
    private var outboundGroups = emptyList<CoreRuntimeProtocol.OutboundGroupSnapshot>()
    private var probeSessions = emptyList<CoreRuntimeProtocol.ProbeSession>()
    private val managedProbeAliases = linkedMapOf<String, String>()
    private var ephemeralProbeSessionId: String? = null
    private var networkSnapshot = CoreRuntimeProtocol.NetworkSnapshot.getDefaultInstance()
    private var transportHealth = CoreRuntimeProtocol.TransportHealthSnapshot.getDefaultInstance()
    @Volatile private var transportHealthRequired = false
    private var controllerRegistration = 0L
    private lateinit var coreContract: CoreRuntimeProtocol.CoreContract
    private val transportHealthPoll = object : Runnable {
        override fun run() {
            refreshTransportHealth(emitIfChanged = true)
            mainHandler.postDelayed(this, TRANSPORT_HEALTH_POLL_MILLIS)
        }
    }

    private val binder = object : ICoreRuntimeService.Stub() {
        override fun getContract(): ByteArray = coreContract.toByteArray()

        override fun getSnapshot(): ByteArray = buildSnapshot().toByteArray()

        override fun submit(commandBytes: ByteArray?): ByteArray {
            val parsed = parseCommand(commandBytes)
            if (parsed.isFailure) {
                return rejectedReceipt(
                    commandId = "",
                    code = "runtime.command.invalid",
                    stage = "command_decode",
                    safeMessage = "The runtime command is invalid.",
                ).toByteArray()
            }
            val command = parsed.getOrThrow()
            val validationError = validateCommand(command)
            if (validationError != null) {
                return rejectedReceipt(
                    commandId = command.commandId,
                    code = validationError.first,
                    stage = "command_validation",
                    safeMessage = validationError.second,
                ).toByteArray()
            }
            val receipt = CoreRuntimeProtocol.CommandReceipt.newBuilder()
                .setSchemaVersion(SCHEMA_VERSION)
                .setCommandId(command.commandId)
                .setStatus(CoreRuntimeProtocol.ReceiptStatus.RECEIPT_STATUS_ACCEPTED)
                .setProcessEpoch(processEpoch)
                .setGeneration(generation.get())
                .setAcceptedAtMillis(System.currentTimeMillis())
                .build()
            commandExecutor.execute { execute(command) }
            return receipt.toByteArray()
        }

        override fun executeUtility(requestBytes: ByteArray?): ByteArray =
            executeCoreUtility(requestBytes).toByteArray()

        override fun registerListener(listener: ICoreRuntimeListener?) {
            if (listener != null) {
                listeners.register(listener)
                runCatching { listener.onEvent(snapshotEvent().toByteArray()) }
            }
        }

        override fun unregisterListener(listener: ICoreRuntimeListener?) {
            if (listener != null) listeners.unregister(listener)
        }

        override fun isRuntimeDisconnected(): Boolean =
            state.get() == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED &&
                !SingboxController.running
    }

    override fun onCreate() {
        super.onCreate()
        val startupFailure = CoreStartupFailureStore(this)
        try {
            startupFailure.markStage("native_setup", nativeSourceLabel())
            NativeCoreEnvironment.ensureSetup()

            startupFailure.markStage("contract", nativeSourceLabel())
            coreContract = buildContract()
            HydraBoxDiagnostics.event(
                "EPOCH",
                "ep" to shortId(processEpoch), "cg" to generation.get(),
                "rg" to SingboxController.activeRuntimeGeneration,
                "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("epoch").generation,
                "prof" to shortHex(activeConfigSha256),
                "native_source" to nativeSourceLabel(),
                "api" to "${coreContract.apiMajor}.${coreContract.apiMinor}",
            )

            startupFailure.markStage("controller", nativeSourceLabel())
            controllerRegistration = SingboxController.registerEventSink(
                object : RuntimeEventConsumer {
                    override fun success(event: Any?) {
                        // The legacy controller still produces maps internally. No map crosses
                        // the binder boundary: clients receive a typed authoritative snapshot.
                        handleControllerEvent(event)
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        failRuntime(
                            commandId = "",
                            code = "runtime.controller.event",
                            stage = "runtime_event",
                            safeMessage = "HydraCore reported a runtime event failure.",
                            retryable = true,
                        )
                    }

                    override fun endOfStream() {
                        refreshFromController()
                        emit(snapshotEvent())
                    }
                },
            )
            refreshFromController()
            refreshNetworkSnapshotFromMonitor("core_service_start")

            // A stale 0.x or interrupted-write config is a configuration recovery,
            // not a broken native core. Keep the binder alive and quarantine the
            // invalid private file so the UI can compile a clean plan.
            startupFailure.markStage("config_recovery", nativeSourceLabel())
            recoverInvalidPersistedConfig()

            startupFailure.markStage("snapshot", nativeSourceLabel())
            buildSnapshot()
            mainHandler.post(transportHealthPoll)
            startupFailure.clear()
            Log.i(
                TAG,
                "startup_healthy source=${nativeSourceLabel()} api=${coreContract.apiMajor}.${coreContract.apiMinor}",
            )
            // Moves to submitInternal(Event.Reconcile) in HB-RW-008.
            commandExecutor.execute { reconcile() }
        } catch (error: Throwable) {
            Log.e(TAG, "startup_failed source=${nativeSourceLabel()}", error)
            HydraBoxDiagnostics.log(
                "CoreRuntimeService",
                "startup failed source=${nativeSourceLabel()}",
                error,
            )
            throw error
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    private fun recoverInvalidPersistedConfig() {
        val configFile = HydraBoxApplication.configFile
        if (!configFile.isFile) return
        val validation = runCatching {
            val bytes = configFile.readBytes()
            require(bytes.isNotEmpty() && bytes.size <= MAX_CONFIG_BYTES) {
                "Persisted HydraCore config is invalid"
            }
            Libbox.checkConfig(bytes.toString(Charsets.UTF_8))
        }
        if (validation.isSuccess) return

        val recoveryDir = java.io.File(filesDir, "core-config-recovery").apply {
            require(mkdirs() || isDirectory)
        }
        val recovered = java.io.File(
            recoveryDir,
            "singbox-config-${System.currentTimeMillis()}.invalid.json",
        )
        require(configFile.renameTo(recovered)) {
            "Invalid HydraCore config could not be quarantined"
        }
        recovered.setReadable(false, false)
        recovered.setWritable(false, false)
        recovered.setReadable(true, true)
        recovered.setWritable(true, true)
        recoveryDir.listFiles()
            .orEmpty()
            .filter { it.isFile && it.name.endsWith(".invalid.json") }
            .sortedByDescending { it.lastModified() }
            .drop(MAX_RECOVERED_CONFIGS)
            .forEach { it.delete() }

        val error = coreError(
            code = "runtime.config.quarantined",
            stage = "config_validation",
            safeMessage = "The previous runtime configuration was invalid and has been quarantined.",
            retryable = false,
            correlationId = UUID.randomUUID().toString(),
            userAction = CoreRuntimeProtocol.UserAction.USER_ACTION_SELECT_PROFILE,
        )
        synchronized(snapshotLock) { lastError = error }
        HydraBoxDiagnostics.log(
            "CoreRuntimeService",
            "invalid persisted config quarantined",
        )
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(transportHealthPoll)
        SingboxController.clearEventSink(controllerRegistration)
        listeners.kill()
        commandExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun parseCommand(bytes: ByteArray?): Result<CoreRuntimeProtocol.RuntimeCommand> =
        runCatching {
            require(bytes != null && bytes.isNotEmpty() && bytes.size <= MAX_COMMAND_BYTES)
            CoreRuntimeProtocol.RuntimeCommand.parseFrom(bytes)
        }.recoverCatching { error ->
            if (error is InvalidProtocolBufferException) throw error
            throw IllegalArgumentException("Invalid command envelope", error)
        }

    private fun validateCommand(command: CoreRuntimeProtocol.RuntimeCommand): Pair<String, String>? {
        if (command.schemaVersion != SCHEMA_VERSION) {
            return "runtime.command.schema" to "The runtime command schema is unsupported."
        }
        if (!COMMAND_ID_PATTERN.matches(command.commandId)) {
            return "runtime.command.id" to "The runtime command identifier is invalid."
        }
        if (command.expectedGeneration != 0L && command.expectedGeneration != generation.get()) {
            return "runtime.command.stale_generation" to "Runtime state changed before the command was applied."
        }
        val payloadMatchesKind = when (command.kind) {
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START -> command.hasStart()
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP -> command.hasStop()
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_RELOAD -> command.hasReload()
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_SELECT_OUTBOUND -> command.hasSelectOutbound()
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START_PROBE -> command.hasStartProbe()
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_PROBE -> command.hasCancelProbe()
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_REQUEST_RECOVERY -> command.hasRequestRecovery()
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_RUNTIME_CHALLENGE ->
                command.hasCancelRuntimeChallenge()
            else -> false
        }
        return if (payloadMatchesKind) null else {
            "runtime.command.payload" to "The runtime command payload does not match its kind."
        }
    }

    private fun execute(command: CoreRuntimeProtocol.RuntimeCommand) {
        when (command.kind) {
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START -> start(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP -> stop(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_RELOAD -> reload(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_SELECT_OUTBOUND -> selectOutbound(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START_PROBE -> startProbe(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_PROBE -> cancelProbe(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_REQUEST_RECOVERY -> recover(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_RUNTIME_CHALLENGE ->
                cancelRuntimeChallenge(command)
            else -> Unit
        }
    }

    private fun cancelRuntimeChallenge(command: CoreRuntimeProtocol.RuntimeCommand) {
        val challengeId = command.cancelRuntimeChallenge.challengeId
        if (challengeId.isBlank() || !Libbox.hydraCoreCancelRuntimeChallenge(challengeId)) {
            commandFailed(
                command.commandId,
                "runtime.challenge.missing",
                "challenge_cancel",
                "The runtime challenge is no longer active.",
                false,
            )
            return
        }
        refreshTransportHealth(emitIfChanged = true)
        commandSucceeded(command.commandId, state.get())
    }

    private fun executeCoreUtility(bytes: ByteArray?): CoreRuntimeProtocol.CoreUtilityResponse {
        val request = runCatching {
            require(bytes != null && bytes.isNotEmpty() && bytes.size <= MAX_COMMAND_BYTES)
            CoreRuntimeProtocol.CoreUtilityRequest.parseFrom(bytes)
        }.getOrElse {
            return utilityFailure(
                "",
                "core.utility.invalid",
                "utility_decode",
                "The HydraCore request is invalid.",
            )
        }
        if (request.schemaVersion != SCHEMA_VERSION ||
            !COMMAND_ID_PATTERN.matches(request.requestId) ||
            request.argumentsList.any { it.size() > MAX_CONFIG_BYTES }
        ) {
            return utilityFailure(
                request.requestId,
                "core.utility.invalid",
                "utility_validation",
                "The HydraCore request is invalid.",
            )
        }
        return runCatching {
            val payload = when (request.kind) {
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VERSION ->
                    Libbox.version().toByteArray(Charsets.UTF_8)
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_CAPABILITIES ->
                    invokeCoreString(request.argumentsList) { Libbox.hydraCoreCapabilities() }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_BUILD_INFO ->
                    invokeCoreString(request.argumentsList) { Libbox.hydraCoreBuildInfo() }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VALIDATE_CONFIG ->
                    invokeCoreString(request.argumentsList, 2) { values ->
                        Libbox.hydraCoreValidateConfig(values[0], values[1])
                    }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VALIDATE_SUBSCRIPTION ->
                    invokeCoreString(request.argumentsList, 1) { values ->
                        Libbox.hydraCoreValidateSubscription(values[0])
                    }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_INSPECT_SUBSCRIPTION ->
                    invokeCoreString(request.argumentsList, 1) { values ->
                        Libbox.hydraCoreInspectSubscription(values[0])
                    }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_OPEN_SUBSCRIPTION_JWE ->
                    invokeCoreString(request.argumentsList, 2) { values ->
                        Libbox.hydraCoreOpenSubscriptionJWE(values[0], values[1])
                    }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VALIDATE_SUBSCRIPTION_JWE ->
                    invokeCoreString(request.argumentsList, 2) { values ->
                        Libbox.hydraCoreValidateSubscriptionJWE(values[0], values[1])
                    }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_INSPECT_SUBSCRIPTION_JWE ->
                    invokeCoreString(request.argumentsList, 2) { values ->
                        Libbox.hydraCoreInspectSubscriptionJWE(values[0], values[1])
                    }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_CHECK_CONFIG -> {
                    require(request.argumentsCount == 1)
                    Libbox.checkConfig(request.getArguments(0).toStringUtf8())
                    ByteArray(0)
                }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_LOOKUP_OUTBOUND_EXTERNAL_INFO ->
                    lookupOutboundExternalInfo(request)
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_UPDATE_NOTIFICATION -> {
                    require(request.argumentsCount == 1)
                    val value = CoreRuntimeProtocol.NotificationPresentation.parseFrom(
                        request.getArguments(0),
                    )
                    check(
                        HydraBoxService.updateNotificationPresentation(
                            buildMap<String, Any?> {
                                put("detailed", value.detailed)
                                put("trafficDisplayMode", value.trafficDisplayMode)
                                put("title", value.title)
                                if (value.hasLatencyMillis()) put("latencyMillis", value.latencyMillis)
                                put("groupTag", value.groupId)
                                put("targetOutboundTag", value.targetOutboundId)
                                put("priorityOutboundTag", value.priorityOutboundId)
                                put("excludeOutboundTag", value.excludedOutboundId)
                                put("url", value.url)
                                put("timeoutMillis", value.timeoutMillis)
                                put("concurrency", value.concurrency)
                                put("deadlineMillis", value.deadlineMillis)
                                put("connectedText", value.connectedText)
                                put("checkingText", value.checkingText)
                                put("unavailableText", value.unavailableText)
                                put("refreshLabel", value.refreshLabel)
                                put("stopLabel", value.stopLabel)
                            },
                        ),
                    )
                    ByteArray(0)
                }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_REFRESH_RUNTIME_FLAGS -> {
                    HydraBoxDefaultNetworkMonitor.refreshHeartbeat()
                    ByteArray(0)
                }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_SET_UI_FOREGROUND -> {
                    require(request.argumentsCount == 1)
                    val value = CoreRuntimeProtocol.UiForegroundState.parseFrom(request.getArguments(0))
                    SingboxController.setUiForeground(value.foreground, controllerRegistration)
                    ByteArray(0)
                }
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_PERFORMANCE_COUNTERS -> {
                    val counters = JSONObject().apply {
                        for ((k, v) in SingboxController.performanceCounters()) {
                            put(k, v)
                        }
                        put("notificationUpdateCount", HydraBoxForegroundNotification.updateCount())
                        put("managedProbeAliasCount", synchronized(snapshotLock) { managedProbeAliases.size })
                    }
                    counters.toString().toByteArray(Charsets.UTF_8)
                }
                else -> throw IllegalArgumentException("Unsupported utility operation")
            }
            CoreRuntimeProtocol.CoreUtilityResponse.newBuilder()
                .setSchemaVersion(SCHEMA_VERSION)
                .setRequestId(request.requestId)
                .setPayload(ByteString.copyFrom(payload))
                .build()
        }.getOrElse {
            utilityFailure(
                request.requestId,
                "core.utility.failed",
                "utility_execution",
                "HydraCore could not complete the request.",
            )
        }
    }

    private fun invokeCoreString(
        arguments: List<ByteString>,
        expectedCount: Int = 0,
        operation: (Array<String>) -> String,
    ): ByteArray {
        require(arguments.size == expectedCount) { "HydraCore argument count is invalid" }
        val values = arguments.map { it.toStringUtf8() }.toTypedArray()
        return operation(values).toByteArray(Charsets.UTF_8)
    }

    private fun lookupOutboundExternalInfo(
        request: CoreRuntimeProtocol.CoreUtilityRequest,
    ): ByteArray {
        require(request.argumentsCount == 1)
        val outboundId = request.getArguments(0).toStringUtf8().trim()
        require(outboundId.isNotEmpty())
        val latch = CountDownLatch(1)
        var result: Result<Map<String, String>>? = null
        SingboxController.lookupOutboundExternalInfo(outboundId) {
            result = it
            latch.countDown()
        }
        check(latch.await(UTILITY_DEADLINE_MILLIS, TimeUnit.MILLISECONDS))
        val value = requireNotNull(result).getOrThrow()
        return CoreRuntimeProtocol.OutboundExternalInfo.newBuilder()
            .setOutboundId(outboundId)
            .setIpAddress(value["ip"].orEmpty())
            .setCountryCode(value["countryCode"].orEmpty())
            .build()
            .toByteArray()
    }

    private fun utilityFailure(
        requestId: String,
        code: String,
        stage: String,
        safeMessage: String,
    ): CoreRuntimeProtocol.CoreUtilityResponse =
        CoreRuntimeProtocol.CoreUtilityResponse.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setRequestId(requestId)
            .setError(coreError(code, stage, safeMessage, false, requestId))
            .build()

    private fun start(command: CoreRuntimeProtocol.RuntimeCommand, recovery: Boolean = false) {
        val request = command.start
        val expectedDigest = request.configSha256.toByteArray()
        val config = request.compiledConfig.toByteArray()
        if (request.mode == CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED ||
            config.isEmpty() || config.size > MAX_CONFIG_BYTES || expectedDigest.size != SHA256_BYTES ||
            !MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(config), expectedDigest)
        ) {
            commandFailed(
                command.commandId,
                "runtime.start.invalid_plan",
                "config_validation",
                "The compiled runtime plan is invalid.",
                false,
            )
            return
        }
        transportHealthRequired = TransportHealthBridge.configRequiresHealth(config)
        refreshTransportHealth(emitIfChanged = false)
        val commandGeneration = generation.incrementAndGet()
        mode.set(request.mode)
        updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_PREPARING)
        val writeError = runCatching { writeConfigAtomically(config) }.exceptionOrNull()
        if (writeError != null) {
            commandFailed(
                command.commandId,
                "runtime.start.config_write",
                "config_write",
                "The runtime configuration could not be stored.",
                true,
            )
            return
        }
        synchronized(snapshotLock) { activeConfigSha256 = expectedDigest.copyOf() }
        if (!recovery) {
            HydraBoxApplication.writeDesiredRuntime(
                DesiredRuntime(true, modeName(request.mode), expectedDigest.toHex(), 0, System.currentTimeMillis()),
            )
        }
        HydraBoxDiagnostics.event(
            "CONNECT",
            "ep" to shortId(processEpoch), "cg" to commandGeneration,
            "rg" to SingboxController.activeRuntimeGeneration,
            "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("connect").generation,
            "prof" to shortHex(activeConfigSha256),
            "mode" to request.mode.name.lowercase().removePrefix("runtime_mode_"),
            "source" to if (recovery) "recovery" else "ui",
        )
        updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING)
        mainHandler.post {
            val targetName = if (request.mode == CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN) "vpn" else "proxy"
            val sameRunningMode = SingboxController.running && SingboxController.serviceMode == targetName
            when {
                sameRunningMode && request.restartCore -> {
                    val previousNativeGeneration = SingboxController.activeRuntimeGeneration
                    val serviceClass = serviceClass(request.mode)
                    updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING)
                    startService(Intent(this, serviceClass).setAction(HydraBoxService.ACTION_RESTART_CORE))
                    awaitRunning(
                        command.commandId,
                        commandGeneration,
                        request.mode,
                        System.currentTimeMillis(),
                        previousNativeGeneration,
                    )
                }
                sameRunningMode && request.applyConfig -> {
                    SingboxController.reloadService { result ->
                        result.onSuccess {
                            updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING)
                            verifyHealthAndCompleteStart(command.commandId, commandGeneration)
                        }.onFailure {
                            failStartAndRollback(
                                command.commandId,
                                commandGeneration,
                                "runtime.reload.failed",
                                "reload",
                                "HydraCore could not reload the plan.",
                                true,
                            )
                        }
                    }
                }
                sameRunningMode -> verifyHealthAndCompleteStart(command.commandId, commandGeneration)
                else -> {
                    dispatchStart(request.mode)
                    awaitRunning(command.commandId, commandGeneration, request.mode, System.currentTimeMillis())
                }
            }
        }
    }

    private fun serviceClass(targetMode: CoreRuntimeProtocol.RuntimeMode): Class<out Service> =
        if (targetMode == CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN) {
            HydraBoxVpnService::class.java
        } else {
            HydraBoxProxyService::class.java
        }

    private fun dispatchStart(targetMode: CoreRuntimeProtocol.RuntimeMode) {
        val serviceClass = serviceClass(targetMode)
        val targetName = if (targetMode == CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN) "vpn" else "proxy"
        if (SingboxController.running && SingboxController.serviceMode != targetName) {
            HydraBoxService.requestStopAll("runtime_mode_switch")
            SingboxController.awaitStopped { stopped ->
                if (stopped) {
                    startForegroundService(Intent(this, serviceClass).setAction(HydraBoxService.ACTION_START))
                }
            }
            return
        }
        startForegroundService(Intent(this, serviceClass).setAction(HydraBoxService.ACTION_START))
    }

    private fun awaitRunning(
        commandId: String,
        commandGeneration: Long,
        expectedMode: CoreRuntimeProtocol.RuntimeMode,
        startedAt: Long,
        previousNativeGeneration: Long = -1L,
    ) {
        if (generation.get() != commandGeneration) return
        val expectedName = if (expectedMode == CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN) "vpn" else "proxy"
        if (SingboxController.running && SingboxController.serviceMode == expectedName &&
            (previousNativeGeneration < 0L || SingboxController.activeRuntimeGeneration > previousNativeGeneration)
        ) {
            updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING)
            verifyHealthAndCompleteStart(commandId, commandGeneration)
            return
        }
        refreshTransportHealth(emitIfChanged = true)
        val waitingForUser = synchronized(snapshotLock) {
            transportHealth.state ==
                CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_WAITING_USER
        }
        val startDeadline = if (waitingForUser) CHALLENGE_DEADLINE_MILLIS else START_DEADLINE_MILLIS
        if (System.currentTimeMillis() - startedAt >= startDeadline) {
            failStartAndRollback(
                commandId,
                commandGeneration,
                "runtime.start.deadline",
                "runtime_start",
                "HydraCore did not reach the running state before the deadline.",
                true,
            )
            return
        }
        mainHandler.postDelayed(
            {
                awaitRunning(
                    commandId,
                    commandGeneration,
                    expectedMode,
                    startedAt,
                    previousNativeGeneration,
                )
            },
            STATE_POLL_MILLIS,
        )
    }

    private fun verifyHealthAndCompleteStart(commandId: String, commandGeneration: Long) {
        SingboxController.getRuntimeSnapshot { result ->
            if (generation.get() != commandGeneration) return@getRuntimeSnapshot
            result.onSuccess {
                refreshNetworkSnapshotFromMonitor("runtime_start_complete")
                if (transportHealthRequired) {
                    awaitTransportReady(commandId, commandGeneration, System.currentTimeMillis())
                } else {
                    completeHealthyStart(commandId)
                }
            }.onFailure {
                failStartAndRollback(
                    commandId,
                    commandGeneration,
                    "runtime.start.snapshot",
                    "runtime_snapshot",
                    "HydraCore started but did not provide a valid runtime snapshot.",
                    true,
                )
            }
        }
    }

    private fun awaitTransportReady(commandId: String, commandGeneration: Long, startedAt: Long) {
        if (generation.get() != commandGeneration) return
        refreshTransportHealth(emitIfChanged = true)
        val health = synchronized(snapshotLock) { transportHealth }
        if (TransportHealthBridge.isConnected(health)) {
            completeHealthyStart(commandId)
            return
        }
        val elapsed = System.currentTimeMillis() - startedAt
        val waitingForUser = health.state ==
            CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_WAITING_USER
        val deadline = if (waitingForUser) CHALLENGE_DEADLINE_MILLIS else TRANSPORT_START_DEADLINE_MILLIS
        if (health.state == CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_FAILED ||
            elapsed >= deadline
        ) {
            failStartAndRollback(
                commandId,
                commandGeneration,
                "runtime.transport.unhealthy",
                "transport_health",
                "HydraCore did not establish a usable transport.",
                true,
            )
            return
        }
        mainHandler.postDelayed(
            { awaitTransportReady(commandId, commandGeneration, startedAt) },
            TRANSPORT_HEALTH_POLL_MILLIS,
        )
    }

    private fun completeHealthyStart(commandId: String) {
        HydraBoxApplication.readDesiredRuntime()?.let {
            HydraBoxApplication.writeDesiredRuntime(desiredRuntimeTransition(it, DesiredRuntimeEvent.READY))
        }
        commandSucceeded(commandId, CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING)
        val health = synchronized(snapshotLock) { transportHealth }
        HydraBoxDiagnostics.event(
            "READY",
            "ep" to shortId(processEpoch), "cg" to generation.get(), "rg" to SingboxController.activeRuntimeGeneration,
            "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("ready").generation,
            "prof" to synchronized(snapshotLock) { shortHex(activeConfigSha256) },
            "active_lanes" to health.activeLanes, "target_lanes" to health.totalLanes, "elapsed_ms_from_connect" to 0,
        )
    }

    private fun failStartAndRollback(
        commandId: String,
        commandGeneration: Long,
        code: String,
        stage: String,
        safeMessage: String,
        retryable: Boolean,
    ) {
        if (generation.get() != commandGeneration) return
        updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING)
        shutdownRuntimeServices("failed_start:$code") { stopped ->
            if (generation.get() != commandGeneration) return@shutdownRuntimeServices
            if (stopped) {
                resetStoppedRuntimeState()
                failRuntime(commandId, code, stage, safeMessage, retryable)
            } else {
                failRuntime(
                    commandId,
                    "runtime.start.rollback_failed",
                    "runtime_start_rollback",
                    "HydraCore could not release the failed VPN runtime.",
                    true,
                )
            }
        }
    }

    private fun shutdownRuntimeServices(reason: String, onComplete: (Boolean) -> Unit) {
        HydraBoxApplication.clearRuntimeIntent()
        mainHandler.post {
            HydraBoxService.requestStopAll(reason)
            // Destroy both possible owners as part of the same transaction. A
            // failed start must not leave Android's VPN service and its TUN
            // alive while the runtime is reported as failed.
            stopService(Intent(this, HydraBoxVpnService::class.java))
            stopService(Intent(this, HydraBoxProxyService::class.java))
            awaitRuntimeServicesReleased(System.currentTimeMillis(), onComplete)
        }
    }

    private fun awaitRuntimeServicesReleased(startedAt: Long, onComplete: (Boolean) -> Unit) {
        val stopped = !SingboxController.running && !HydraBoxService.hasActiveRuntimeOwner()
        if (stopped) {
            HydraBoxApplication.clearServiceState()
            onComplete(true)
            return
        }
        if (System.currentTimeMillis() - startedAt >= RUNTIME_SHUTDOWN_DEADLINE_MILLIS) {
            onComplete(false)
            return
        }
        mainHandler.postDelayed(
            { awaitRuntimeServicesReleased(startedAt, onComplete) },
            STATE_POLL_MILLIS,
        )
    }

    private fun resetStoppedRuntimeState() {
        mode.set(CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED)
        transportHealthRequired = false
        synchronized(snapshotLock) {
            transportHealth = CoreRuntimeProtocol.TransportHealthSnapshot.getDefaultInstance()
            managedProbeAliases.clear()
        }
    }

    private fun stop(command: CoreRuntimeProtocol.RuntimeCommand) {
        generation.incrementAndGet()
        writeStoppedDesiredRuntime()
        HydraBoxDiagnostics.event(
            "STOP",
            "ep" to shortId(processEpoch), "cg" to generation.get(), "rg" to SingboxController.activeRuntimeGeneration,
            "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("stop").generation,
            "prof" to synchronized(snapshotLock) { shortHex(activeConfigSha256) },
            "reason" to command.stop.reason.ifBlank { "runtime_command" }, "stage" to "requested",
        )
        updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING)
        shutdownRuntimeServices(command.stop.reason.ifBlank { "runtime_command" }) { stopped ->
            if (stopped) {
                resetStoppedRuntimeState()
                updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED)
                commandSucceeded(command.commandId, CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED)
            } else {
                commandFailed(
                    command.commandId,
                    "runtime.stop.deadline",
                    "runtime_stop",
                    "HydraCore did not confirm that it stopped.",
                    true,
                )
            }
        }
    }

    private fun reload(command: CoreRuntimeProtocol.RuntimeCommand) {
        if (!SingboxController.running) {
            commandFailed(command.commandId, "runtime.reload.stopped", "reload", "HydraCore is not running.", false)
            return
        }
        SingboxController.reloadService { result ->
            result.onSuccess {
                generation.incrementAndGet()
                commandSucceeded(command.commandId, CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING)
            }.onFailure {
                commandFailed(command.commandId, "runtime.reload.failed", "reload", "HydraCore could not reload the plan.", true)
            }
        }
    }

    private fun selectOutbound(command: CoreRuntimeProtocol.RuntimeCommand) {
        val request = command.selectOutbound
        if (request.groupId.isBlank() || request.outboundId.isBlank()) {
            commandFailed(command.commandId, "runtime.selector.invalid", "selector", "The outbound selection is invalid.", false)
            return
        }
        SingboxController.selectOutbound(request.groupId, request.outboundId) { result ->
            result.onSuccess {
                synchronized(snapshotLock) { selectedOutbounds[request.groupId] = request.outboundId }
                commandSucceeded(command.commandId, state.get())
            }.onFailure {
                commandFailed(command.commandId, "runtime.selector.failed", "selector", "HydraCore rejected the outbound selection.", true)
            }
        }
    }

    private fun startProbe(command: CoreRuntimeProtocol.RuntimeCommand) {
        val request = command.startProbe
        if (request.sessionId.isBlank() || request.groupId.isBlank() || request.outboundIdsCount == 0 ||
            request.url.isBlank() || request.concurrency !in 1..32 ||
            request.timeoutMillis !in 500..120_000
        ) {
            commandFailed(command.commandId, "probe.request.invalid", "probe", "The probe request is invalid.", false)
            return
        }
        // A compiled config means the caller requested an isolated probe plan.
        // It may describe a profile that is intentionally absent from the
        // active runtime, so never discard it merely because a VPN is running.
        // Requests without a plan continue to use the managed core session.
        when (selectProbeExecutionMode(SingboxController.running, request.compiledConfig.size())) {
            ProbeExecutionMode.EPHEMERAL -> {
                startEphemeralProbe(command, request)
                return
            }
            ProbeExecutionMode.REJECT_MISSING_PLAN -> {
                commandFailed(
                    command.commandId,
                    "probe.ephemeral.missing_plan",
                    "probe_bootstrap",
                    "A disconnected probe requires a compiled configuration.",
                    false,
                )
                return
            }
            ProbeExecutionMode.MANAGED -> Unit
        }
        SingboxController.startManagedUrlTest(
            groupTag = request.groupId,
            targetOutboundTag = if (
                request.outboundIdsCount == 1 && request.getOutboundIds(0) != ALL_OUTBOUNDS
            ) request.getOutboundIds(0) else "",
            priorityOutboundTag = "",
            excludeOutboundTag = "",
            url = request.url,
            timeoutMillis = request.timeoutMillis.toInt(),
            concurrency = request.concurrency.toInt(),
            deadlineMillis = (request.deadlineAtMillis - System.currentTimeMillis())
                .coerceIn(request.timeoutMillis.toLong(), 120_000L).toInt(),
            force = true,
        ) { result ->
            result.onSuccess { nativeSession ->
                val nativeId = nativeSession["id"]?.toString().orEmpty()
                if (nativeId.isNotBlank()) {
                    synchronized(snapshotLock) { managedProbeAliases[nativeId] = request.sessionId }
                }
                val session = CoreRuntimeProtocol.ProbeSession.newBuilder()
                    .setSessionId(request.sessionId)
                    .setState(CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_RUNNING)
                    .setRequestedCount(request.outboundIdsCount)
                    .setStartedAtMillis(System.currentTimeMillis())
                    .setNetworkFingerprint(request.networkFingerprint)
                    .build()
                emit(eventBuilder().setProbeSession(session).build())
                commandSucceeded(command.commandId, state.get())
            }.onFailure {
                commandFailed(command.commandId, "probe.start.failed", "probe_start", "HydraCore could not start the probe session.", true)
            }
        }
    }

    private fun startEphemeralProbe(
        command: CoreRuntimeProtocol.RuntimeCommand,
        request: CoreRuntimeProtocol.ProbeRequest,
    ) {
        val config = request.compiledConfig.toByteArray()
        val digest = request.configSha256.toByteArray()
        val outboundId = request.getOutboundIds(0)
        if (request.outboundIdsCount != 1 || outboundId == ALL_OUTBOUNDS ||
            config.isEmpty() || config.size > MAX_CONFIG_BYTES || digest.size != SHA256_BYTES ||
            !MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(config), digest)
        ) {
            commandFailed(
                command.commandId,
                "probe.ephemeral.invalid_plan",
                "probe_bootstrap",
                "The disconnected probe plan is invalid.",
                false,
            )
            return
        }
        val startedAt = System.currentTimeMillis()
        val runningSession = CoreRuntimeProtocol.ProbeSession.newBuilder()
            .setSessionId(request.sessionId)
            .setState(CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_RUNNING)
            .setRequestedCount(1)
            .setStartedAtMillis(startedAt)
            .setNetworkFingerprint(request.networkFingerprint)
            .build()
        synchronized(snapshotLock) {
            ephemeralProbeSessionId = request.sessionId
            probeSessions = probeSessions.filterNot { it.sessionId == request.sessionId } + runningSession
        }
        emit(eventBuilder().setProbeSession(runningSession).build())
        commandSucceeded(command.commandId, state.get())
        val deadlineDelay = (request.deadlineAtMillis - System.currentTimeMillis())
            .coerceIn(request.timeoutMillis.toLong(), 120_000L)
        mainHandler.postDelayed({
            val timedOut = synchronized(snapshotLock) {
                if (ephemeralProbeSessionId == request.sessionId) {
                    ephemeralProbeSessionId = null
                    true
                } else false
            }
            if (timedOut) {
                SingboxController.cancelPreconnectUrlTest("probe_deadline")
                finishEphemeralProbe(
                    request,
                    CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_TIMED_OUT,
                    startedAt,
                    System.currentTimeMillis(),
                )
            }
        }, deadlineDelay)
        SingboxController.preconnectUrlTest(
            config = config.toString(Charsets.UTF_8),
            groupTag = request.groupId,
            targetOutboundTag = outboundId,
            url = request.url,
            timeoutMillis = request.timeoutMillis.toInt(),
            deadlineMillis = (request.deadlineAtMillis - System.currentTimeMillis())
                .coerceIn(request.timeoutMillis.toLong(), 120_000L).toInt(),
        ) { result ->
            val stillCurrent = synchronized(snapshotLock) {
                ephemeralProbeSessionId == request.sessionId
            }
            if (!stillCurrent) return@preconnectUrlTest
            val finishedAt = System.currentTimeMillis()
            result.onSuccess { value ->
                val probe = CoreRuntimeProtocol.ProbeResult.newBuilder()
                    .setSessionId(request.sessionId)
                    .setOutboundId(outboundId)
                    .setDelayMillis(value.delayMillis.coerceAtLeast(0L))
                    .setMeasuredAtMillis(secondsToMillis(value.timeSeconds))
                    .setNetworkFingerprint(request.networkFingerprint)
                if (value.errorCode.isNotBlank()) {
                    probe.setError(
                        coreError(
                            safeErrorCode(value.errorCode).ifBlank { "probe.failed" },
                            "probe_result",
                            "HydraCore could not probe this outbound.",
                            true,
                            "probe:${request.sessionId}:$outboundId",
                        ),
                    )
                }
                emit(eventBuilder().setProbeResult(probe).build())
                finishEphemeralProbe(
                    request,
                    if (value.delayMillis > 0L) {
                        CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_COMPLETED
                    } else {
                        CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_PARTIAL
                    },
                    startedAt,
                    finishedAt,
                )
            }.onFailure {
                finishEphemeralProbe(
                    request,
                    CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_PARTIAL,
                    startedAt,
                    finishedAt,
                )
            }
        }
    }

    private fun finishEphemeralProbe(
        request: CoreRuntimeProtocol.ProbeRequest,
        finalState: CoreRuntimeProtocol.ProbeSessionState,
        startedAt: Long,
        finishedAt: Long,
    ) {
        val session = CoreRuntimeProtocol.ProbeSession.newBuilder()
            .setSessionId(request.sessionId)
            .setState(finalState)
            .setRequestedCount(1)
            .setCompletedCount(1)
            .setStartedAtMillis(startedAt)
            .setFinishedAtMillis(finishedAt)
            .setNetworkFingerprint(request.networkFingerprint)
            .build()
        synchronized(snapshotLock) {
            ephemeralProbeSessionId = null
            probeSessions = probeSessions.filterNot { it.sessionId == request.sessionId } + session
        }
        emit(eventBuilder().setProbeSession(session).build())
        emit(snapshotEvent())
    }

    private fun cancelProbe(command: CoreRuntimeProtocol.RuntimeCommand) {
        val requestedId = command.cancelProbe.sessionId
        val isEphemeral = synchronized(snapshotLock) { ephemeralProbeSessionId == requestedId }
        if (isEphemeral) {
            SingboxController.cancelPreconnectUrlTest("probe_cancel") { result ->
                result.onSuccess {
                    val session = CoreRuntimeProtocol.ProbeSession.newBuilder()
                        .setSessionId(requestedId)
                        .setState(CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_CANCELLED)
                        .setFinishedAtMillis(System.currentTimeMillis())
                        .build()
                    synchronized(snapshotLock) {
                        ephemeralProbeSessionId = null
                        probeSessions = probeSessions.filterNot { it.sessionId == requestedId } + session
                    }
                    emit(eventBuilder().setProbeSession(session).build())
                    commandSucceeded(command.commandId, state.get())
                }.onFailure {
                    commandFailed(
                        command.commandId,
                        "probe.cancel.failed",
                        "probe_cancel",
                        "HydraCore could not cancel the probe session.",
                        true,
                    )
                }
            }
            return
        }
        val nativeId = synchronized(snapshotLock) {
            managedProbeAliases.entries.firstOrNull { it.value == requestedId }?.key ?: requestedId
        }
        SingboxController.cancelManagedUrlTest(nativeId) { result ->
            result.onSuccess {
                val session = CoreRuntimeProtocol.ProbeSession.newBuilder()
                    .setSessionId(requestedId)
                    .setState(CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_CANCELLED)
                    .setFinishedAtMillis(System.currentTimeMillis())
                    .build()
                synchronized(snapshotLock) { managedProbeAliases.remove(nativeId) }
                emit(eventBuilder().setProbeSession(session).build())
                commandSucceeded(command.commandId, state.get())
            }.onFailure {
                commandFailed(command.commandId, "probe.cancel.failed", "probe_cancel", "HydraCore could not cancel the probe session.", true)
            }
        }
    }

    private fun recover(command: CoreRuntimeProtocol.RuntimeCommand) {
        if (!SingboxController.running) {
            commandFailed(command.commandId, "runtime.recovery.stopped", "recovery", "HydraCore is not running.", false)
            return
        }
        updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING)
        HydraBoxDiagnostics.event(
            "RECOVERY",
            "ep" to shortId(processEpoch), "cg" to generation.get(), "rg" to SingboxController.activeRuntimeGeneration,
            "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("recovery").generation,
            "prof" to synchronized(snapshotLock) { shortHex(activeConfigSha256) },
            "reason" to "transport_lost", "elapsed_ms" to 0,
        )
        HydraBoxService.requestStopAll("recovery:${command.requestRecovery.reason}")
        mainHandler.postDelayed({
            dispatchStart(mode.get())
            awaitRunning(command.commandId, generation.incrementAndGet(), mode.get(), System.currentTimeMillis())
        }, STATE_POLL_MILLIS)
    }

    private fun buildContract(): CoreRuntimeProtocol.CoreContract {
        val version = runCatching { Libbox.version() }.getOrElse { "unavailable" }
        val capabilities = runCatching {
            Libbox.hydraCoreCapabilities().toByteArray(Charsets.UTF_8)
        }.getOrElse { ByteArray(0) }
        require(capabilities.isNotEmpty()) { "HydraCore capabilities are unavailable" }
        val supportedProtocolIds = CoreCapabilityContract.supportedProtocolIds(capabilities)
        val runtimeSchema = CoreRuntimeProtocol.SchemaRange.newBuilder()
            .setMinimum(SCHEMA_VERSION)
            .setMaximum(SCHEMA_VERSION)
            .build()
        val configSchema = CoreRuntimeProtocol.SchemaRange.newBuilder()
            .setMinimum(1)
            .setMaximum(1)
            .build()
        return CoreRuntimeProtocol.CoreContract.newBuilder()
            .setApiMajor(CoreCapabilityContract.bundleApiMajor(capabilities))
            .setApiMinor(CORE_API_MINOR)
            .setCoreVersion(version)
            .setProcessEpoch(processEpoch)
            .setRuntimeSnapshotSchema(runtimeSchema)
            .setRuntimeEventSchema(runtimeSchema)
            .setConfigSchema(configSchema)
            .setSubscriptionSchema(
                CoreRuntimeProtocol.SchemaRange.newBuilder().setMinimum(2).setMaximum(2),
            )
            .addOptionalFeatureIds("runtime.snapshot.sequence")
            .addOptionalFeatureIds("runtime.command.receipt_result")
            .addOptionalFeatureIds("probe.managed")
            .addOptionalFeatureIds("transport.health.structured")
            .addOptionalFeatureIds("runtime.challenge.visible")
            .addAllSupportedProtocolIds(supportedProtocolIds)
            .setCapabilitiesSha256(
                ByteString.copyFrom(MessageDigest.getInstance("SHA-256").digest(capabilities)),
            )
            .build()
    }

    private fun refreshFromController() {
        val newState = when {
            SingboxController.running -> CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING
            state.get() == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING -> state.get()
            state.get() == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING -> state.get()
            else -> CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED
        }
        state.set(newState)
        mode.set(
            when (SingboxController.serviceMode) {
                "vpn" -> CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN
                "proxy" -> CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY
                else -> if (newState == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED) {
                    CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED
                } else mode.get()
            },
        )
    }

    private fun handleControllerEvent(value: Any?) {
        refreshFromController()
        val event = value as? Map<*, *>
        when (event?.get("type")?.toString()) {
            "groups" -> updateOutboundGroups(event)
            "urlTestSessions" -> updateProbeSessions(event)
            "network" -> updateNetworkSnapshot(event)
        }
        emit(snapshotEvent())
    }

    private fun updateNetworkSnapshot(event: Map<*, *>) {
        val interfaceName = event["interfaceName"]?.toString().orEmpty()
        val generation = (event["networkGeneration"] as? Number)?.toLong()?.coerceAtLeast(0L) ?: 0L
        writeNetworkSnapshot(
            available = interfaceName.isNotBlank(),
            interfaceName = interfaceName,
            interfaceIndex = (event["interfaceIndex"] as? Number)?.toInt() ?: -1,
            generation = generation,
            updatedAtMillis = System.currentTimeMillis(),
        )
    }

    private fun refreshNetworkSnapshotFromMonitor(reason: String) {
        val current = runCatching {
            HydraBoxDefaultNetworkMonitor.currentInterfaceState(reason)
        }.onFailure { error ->
            HydraBoxDiagnostics.log(
                "CoreRuntimeService",
                "network snapshot refresh failed reason=$reason",
                error,
            )
        }.getOrNull() ?: return
        writeNetworkSnapshot(
            available = current.available,
            interfaceName = current.interfaceName,
            interfaceIndex = current.interfaceIndex,
            generation = current.generation,
            updatedAtMillis = current.updatedAtMillis,
        )
    }

    private fun writeNetworkSnapshot(
        available: Boolean,
        interfaceName: String,
        interfaceIndex: Int,
        generation: Long,
        updatedAtMillis: Long,
    ) {
        val fingerprintBytes = MessageDigest.getInstance("SHA-256").digest(
            "$interfaceName:$generation".toByteArray(Charsets.UTF_8),
        )
        synchronized(snapshotLock) {
            networkSnapshot = CoreRuntimeProtocol.NetworkSnapshot.newBuilder()
                .setAvailable(available)
                .setInterfaceName(interfaceName)
                .setInterfaceIndex(interfaceIndex)
                .setGeneration(generation)
                .setFingerprint(fingerprintBytes.joinToString("") { "%02x".format(it.toInt() and 0xff) })
                .setUpdatedAtMillis(updatedAtMillis)
                .build()
        }
    }

    private fun updateOutboundGroups(event: Map<*, *>) {
        val parsed = (event["groups"] as? Iterable<*>)?.mapNotNull { rawGroup ->
            val group = rawGroup as? Map<*, *> ?: return@mapNotNull null
            val groupId = group["tag"]?.toString()?.takeIf(String::isNotBlank)
                ?: return@mapNotNull null
            val builder = CoreRuntimeProtocol.OutboundGroupSnapshot.newBuilder()
                .setGroupId(groupId)
                .setSelectedOutboundId(group["selected"]?.toString().orEmpty())
            (group["items"] as? Iterable<*>)?.forEach { rawItem ->
                val item = rawItem as? Map<*, *> ?: return@forEach
                val outboundId = item["tag"]?.toString()?.takeIf(String::isNotBlank)
                    ?: return@forEach
                val probe = CoreRuntimeProtocol.OutboundProbeValue.newBuilder()
                    .setOutboundId(outboundId)
                    .setDelayMillis((item["delay"] as? Number)?.toLong()?.coerceAtLeast(0L) ?: 0L)
                    .setMeasuredAtMillis(secondsToMillis(item["time"] as? Number))
                    .setStatus(item["status"]?.toString().orEmpty())
                val errorCode = safeErrorCode(item["errorCode"]?.toString())
                if (errorCode.isNotEmpty()) {
                    probe.setError(coreError(
                        errorCode,
                        "probe_result",
                        "HydraCore could not probe this outbound.",
                        true,
                        "probe:$outboundId",
                    ))
                }
                builder.addOutbounds(probe)
            }
            builder.build()
        }.orEmpty()
        synchronized(snapshotLock) {
            outboundGroups = parsed
            selectedOutbounds.clear()
            parsed.forEach { group ->
                if (group.selectedOutboundId.isNotBlank()) {
                    selectedOutbounds[group.groupId] = group.selectedOutboundId
                }
            }
        }
    }

    private fun updateProbeSessions(event: Map<*, *>) {
        val reset = event["reset"] == true
        val parsed = (event["sessions"] as? Iterable<*>)?.mapNotNull { rawSession ->
            val session = rawSession as? Map<*, *> ?: return@mapNotNull null
            val nativeId = session["id"]?.toString()?.takeIf(String::isNotBlank)
                ?: return@mapNotNull null
            val id = synchronized(snapshotLock) { managedProbeAliases[nativeId] ?: nativeId }
            val state = probeState(session["state"]?.toString())
            val result = CoreRuntimeProtocol.ProbeSession.newBuilder()
                .setSessionId(id)
                .setState(state)
                .setRequestedCount((session["total"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 0)
                .setCompletedCount((session["completed"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 0)
                .setStartedAtMillis(secondsToMillis(session["startedAt"] as? Number))
                .setFinishedAtMillis(secondsToMillis(session["completedAt"] as? Number))
                .build()
            (session["results"] as? Iterable<*>)?.forEach { rawResult ->
                val item = rawResult as? Map<*, *> ?: return@forEach
                val outboundId = item["outboundTag"]?.toString()?.takeIf(String::isNotBlank)
                    ?: return@forEach
                val probe = CoreRuntimeProtocol.ProbeResult.newBuilder()
                    .setSessionId(id)
                    .setOutboundId(outboundId)
                    .setDelayMillis((item["delayMillis"] as? Number)?.toLong()?.coerceAtLeast(0L) ?: 0L)
                    .setMeasuredAtMillis(secondsToMillis(item["observedAt"] as? Number))
                val errorCode = safeErrorCode(item["errorCode"]?.toString())
                if (errorCode.isNotEmpty()) {
                    probe.setError(coreError(
                        errorCode,
                        "probe_result",
                        "HydraCore could not probe this outbound.",
                        true,
                        "probe:$id:$outboundId",
                    ))
                }
                emit(eventBuilder().setProbeResult(probe).build())
            }
            result
        }.orEmpty()
        synchronized(snapshotLock) {
            val aliases = pruneAliases(managedProbeAliases, parsed)
            managedProbeAliases.clear()
            managedProbeAliases.putAll(aliases)
            probeSessions = if (reset) parsed else {
                (probeSessions.associateBy { it.sessionId } + parsed.associateBy { it.sessionId })
                    .values.toList()
            }
        }
        parsed.forEach { emit(eventBuilder().setProbeSession(it).build()) }
    }

    private fun probeState(value: String?): CoreRuntimeProtocol.ProbeSessionState =
        when (value?.lowercase()) {
            "completed" -> CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_COMPLETED
            "partial" -> CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_PARTIAL
            "cancelled", "canceled" -> CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_CANCELLED
            "timedout", "timed_out", "timeout" ->
                CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_TIMED_OUT
            else -> CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_RUNNING
        }

    private fun safeErrorCode(value: String?): String {
        val normalized = value.orEmpty().trim().lowercase()
        return if (Regex("^[a-z0-9._-]{1,96}$").matches(normalized)) normalized else {
            if (normalized.isBlank()) "" else "probe.failed"
        }
    }

    private fun secondsToMillis(value: Number?): Long {
        val raw = value?.toLong()?.coerceAtLeast(0L) ?: return 0L
        return if (raw in 1..9_999_999_999L) raw * 1000L else raw
    }

    private fun refreshTransportHealth(emitIfChanged: Boolean) {
        val applicable = transportHealthRequired && state.get() !in setOf(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED,
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING,
        )
        val parsed = if (!applicable) {
            CoreRuntimeProtocol.TransportHealthSnapshot.newBuilder()
                .setApplicable(false)
                .build()
        } else {
            runCatching {
                TransportHealthBridge.parse(Libbox.hydraCoreTransportState(), true)
            }.getOrElse {
                CoreRuntimeProtocol.TransportHealthSnapshot.newBuilder()
                    .setApplicable(true)
                    .setState(
                        CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_FAILED,
                    )
                    .setObservedAtMillis(System.currentTimeMillis())
                    .setFailure(
                        CoreRuntimeProtocol.TransportFailure.newBuilder()
                            .setStage("transport_snapshot")
                            .setKind("runtime")
                            .setCode("runtime.transport.snapshot"),
                    )
                    .build()
            }
        }
        val changed = synchronized(snapshotLock) {
            if (transportHealth == parsed) false else {
                transportHealth = parsed
                true
            }
        }
        if (changed) {
            val failure = parsed.failure
            HydraBoxDiagnostics.log(
                "CoreRuntimeService",
                "transport_health state=${parsed.state.name} lanes=${parsed.activeLanes}/${parsed.totalLanes} " +
                    "demand=${parsed.demand} failureStage=${failure.stage} " +
                    "failureKind=${failure.kind} failureCode=${failure.code}",
            )
        }
        if (changed && emitIfChanged) emit(snapshotEvent())
    }

    private fun buildSnapshot(): CoreRuntimeProtocol.RuntimeSnapshot {
        synchronized(snapshotLock) {
            val effectiveState = TransportHealthBridge.effectiveRuntimeState(
                state.get(),
                transportHealth,
            )
            val traffic = CoreRuntimeProtocol.TrafficSnapshot.newBuilder()
                .setUplinkBytesPerSecond(SingboxController.uplink)
                .setDownlinkBytesPerSecond(SingboxController.downlink)
                .setUplinkTotalBytes(SingboxController.uplinkTotal)
                .setDownlinkTotalBytes(SingboxController.downlinkTotal)
                .setSampledAtMillis(System.currentTimeMillis())
                .build()
            val builder = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder()
                .setSchemaVersion(SCHEMA_VERSION)
                .setProcessEpoch(processEpoch)
                .setGeneration(generation.get())
                .setLastSequence(sequence.get())
                .setState(effectiveState)
                .setMode(mode.get())
                .setActiveConfigSha256(ByteString.copyFrom(activeConfigSha256))
                .putAllSelectedOutboundIds(selectedOutbounds)
                .setTraffic(traffic)
                .setNetwork(networkSnapshot)
                .setUpdatedAtMillis(System.currentTimeMillis())
                .setHealthy(
                    effectiveState == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING &&
                        TransportHealthBridge.isConnected(transportHealth),
                )
                .addAllOutboundGroups(outboundGroups)
                .addAllProbeSessions(probeSessions)
                .setTransportHealth(transportHealth)
            lastError?.let(builder::setLastError)
            return builder.build()
        }
    }

    private fun updateState(value: CoreRuntimeProtocol.RuntimeState) {
        state.set(value)
        notificationStatusFor(value)?.let(HydraBoxService::applyRuntimeStatus)
        emit(snapshotEvent())
    }

    private fun snapshotEvent(): CoreRuntimeProtocol.RuntimeEvent =
        eventBuilder().setSnapshot(buildSnapshot()).build()

    private fun eventBuilder(): CoreRuntimeProtocol.RuntimeEvent.Builder =
        CoreRuntimeProtocol.RuntimeEvent.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setProcessEpoch(processEpoch)
            .setSequence(sequence.incrementAndGet())
            .setGeneration(generation.get())
            .setEmittedAtMillis(System.currentTimeMillis())

    private fun emit(event: CoreRuntimeProtocol.RuntimeEvent) {
        val bytes = event.toByteArray()
        val count = listeners.beginBroadcast()
        try {
            for (index in 0 until count) {
                runCatching { listeners.getBroadcastItem(index).onEvent(bytes) }
            }
        } finally {
            listeners.finishBroadcast()
        }
    }

    private fun commandSucceeded(commandId: String, finalState: CoreRuntimeProtocol.RuntimeState) {
        synchronized(snapshotLock) { lastError = null }
        val result = CoreRuntimeProtocol.CommandResult.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setCommandId(commandId)
            .setOutcome(CoreRuntimeProtocol.CommandOutcome.COMMAND_OUTCOME_SUCCEEDED)
            .setFinalState(finalState)
            .setGeneration(generation.get())
            .setCompletedAtMillis(System.currentTimeMillis())
            .build()
        emit(eventBuilder().setCommandResult(result).build())
        emit(snapshotEvent())
    }

    private fun commandFailed(
        commandId: String,
        code: String,
        stage: String,
        safeMessage: String,
        retryable: Boolean,
    ) {
        failRuntime(commandId, code, stage, safeMessage, retryable)
    }

    private fun failRuntime(
        commandId: String,
        code: String,
        stage: String,
        safeMessage: String,
        retryable: Boolean,
    ) {
        val error = coreError(code, stage, safeMessage, retryable, commandId.ifBlank { UUID.randomUUID().toString() })
        synchronized(snapshotLock) { lastError = error }
        if (!stage.startsWith("probe") && stage != "selector") {
            HydraBoxApplication.readDesiredRuntime()?.let {
                HydraBoxApplication.writeDesiredRuntime(desiredRuntimeTransition(it, DesiredRuntimeEvent.FAILED))
            }
            state.set(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED)
        }
        val result = CoreRuntimeProtocol.CommandResult.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setCommandId(commandId)
            .setOutcome(CoreRuntimeProtocol.CommandOutcome.COMMAND_OUTCOME_FAILED)
            .setFinalState(state.get())
            .setGeneration(generation.get())
            .setCompletedAtMillis(System.currentTimeMillis())
            .setError(error)
            .build()
        emit(eventBuilder().setCommandResult(result).build())
        emit(snapshotEvent())
    }

    private fun rejectedReceipt(
        commandId: String,
        code: String,
        stage: String,
        safeMessage: String,
    ): CoreRuntimeProtocol.CommandReceipt = CoreRuntimeProtocol.CommandReceipt.newBuilder()
        .setSchemaVersion(SCHEMA_VERSION)
        .setCommandId(commandId)
        .setStatus(CoreRuntimeProtocol.ReceiptStatus.RECEIPT_STATUS_REJECTED)
        .setProcessEpoch(processEpoch)
        .setGeneration(generation.get())
        .setAcceptedAtMillis(System.currentTimeMillis())
        .setRejection(coreError(code, stage, safeMessage, false, commandId))
        .build()

    private fun coreError(
        code: String,
        stage: String,
        safeMessage: String,
        retryable: Boolean,
        correlationId: String,
        userAction: CoreRuntimeProtocol.UserAction? = null,
    ): CoreRuntimeProtocol.CoreError = CoreRuntimeProtocol.CoreError.newBuilder()
        .setCode(code)
        .setStage(stage)
        .setRetryable(retryable)
        .setUserAction(
            userAction ?: if (retryable) CoreRuntimeProtocol.UserAction.USER_ACTION_RETRY
            else CoreRuntimeProtocol.UserAction.USER_ACTION_EXPORT_DIAGNOSTICS,
        )
        .setSafeMessage(safeMessage)
        .setCorrelationId(correlationId)
        .build()

    private fun writeConfigAtomically(config: ByteArray) {
        val target = HydraBoxApplication.configFile
        target.parentFile?.let { require(it.mkdirs() || it.isDirectory) }
        val atomic = AtomicFile(target)
        var output: FileOutputStream? = null
        try {
            output = atomic.startWrite()
            output.write(config)
            atomic.finishWrite(output)
        } catch (error: Throwable) {
            output?.let(atomic::failWrite)
            throw error
        }
    }

    private fun reconcile() {
        val desired = HydraBoxApplication.readDesiredRuntime()
        if (desired != null && !HydraBoxApplication.desiredRuntimeFile.exists()) {
            HydraBoxApplication.writeDesiredRuntime(desired)
        }
        if (desired == null || !desired.wantRunning) {
            updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED)
            return
        }
        val config = runCatching {
            HydraBoxApplication.configFile.readBytes().also {
                require(it.isNotEmpty() && it.size <= MAX_CONFIG_BYTES)
                Libbox.checkConfig(it.toString(Charsets.UTF_8))
            }
        }.getOrElse {
            failRuntime("", "config.quarantined", "config_validation", "The stored runtime configuration is invalid.", false)
            return
        }
        when (val decision = desiredRuntimeDecision(desired, config.toHex())) {
            DesiredRuntimeDecision.None -> updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED)
            is DesiredRuntimeDecision.Failed ->
                failRuntime("", decision.code, "reconciliation", "The stored runtime configuration cannot be recovered.", false)
            is DesiredRuntimeDecision.Recover -> {
                HydraBoxApplication.writeDesiredRuntime(decision.next)
                val targetMode = if (decision.next.mode == "vpn") {
                    CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN
                } else {
                    CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY
                }
                val command = CoreRuntimeProtocol.RuntimeCommand.newBuilder()
                    .setSchemaVersion(SCHEMA_VERSION)
                    .setCommandId(UUID.randomUUID().toString())
                    .setKind(CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START)
                    .setStart(
                        CoreRuntimeProtocol.StartRuntime.newBuilder()
                            .setMode(targetMode)
                            .setCompiledConfig(ByteString.copyFrom(config))
                            .setConfigSha256(ByteString.copyFrom(config.toSha256Bytes()))
                    )
                    .build()
                start(command, recovery = true)
            }
        }
    }

    private fun writeStoppedDesiredRuntime() {
        val current = HydraBoxApplication.readDesiredRuntime()
            ?: DesiredRuntime(false, modeName(mode.get()), currentConfigSha256(), 0, System.currentTimeMillis())
        HydraBoxApplication.writeDesiredRuntime(desiredRuntimeTransition(current, DesiredRuntimeEvent.USER_STOP))
    }

    private fun currentConfigSha256(): String = runCatching {
        HydraBoxApplication.configFile.readBytes().toHex()
    }.getOrDefault("0".repeat(64))

    private fun modeName(value: CoreRuntimeProtocol.RuntimeMode): String =
        if (value == CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY) "proxy" else "vpn"

    private fun ByteArray.toSha256Bytes(): ByteArray = MessageDigest.getInstance("SHA-256").digest(this)

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it.toInt() and 0xff) }

    companion object {
        private const val TAG = "HydraCoreRuntime"
        private const val SCHEMA_VERSION = 2
        private const val CORE_API_MINOR = 1
        private const val SHA256_BYTES = 32
        // Binder's transaction buffer is finite and shared by the process.
        private const val MAX_COMMAND_BYTES = 768 * 1024
        private const val MAX_CONFIG_BYTES = 700 * 1024
        private const val START_DEADLINE_MILLIS = 30_000L
        private const val TRANSPORT_START_DEADLINE_MILLIS = 30_000L
        private const val CHALLENGE_DEADLINE_MILLIS = 120_000L
        private const val RUNTIME_SHUTDOWN_DEADLINE_MILLIS = 5_000L
        private const val TRANSPORT_HEALTH_POLL_MILLIS = 250L
        private const val STATE_POLL_MILLIS = 100L
        private const val UTILITY_DEADLINE_MILLIS = 10_000L
        private const val ALL_OUTBOUNDS = "*"
        private const val MAX_RECOVERED_CONFIGS = 2
        private val COMMAND_ID_PATTERN = Regex("^[A-Za-z0-9._:-]{1,128}$")
    }
}
