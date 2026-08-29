package io.hydrabox.client.runtime

import android.app.Service
import android.content.Intent
import android.net.Network
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
import io.hydrabox.client.singbox.RuntimeSession
import io.hydrabox.client.singbox.HydraBoxDiagnostics
import io.hydrabox.client.singbox.HydraBoxVpnService
import io.hydrabox.client.singbox.HydraBoxForegroundNotification
import io.hydrabox.client.singbox.RuntimeEventConsumer
import io.hydrabox.client.singbox.SingboxController
import io.hydrabox.client.singbox.NativeCoreEnvironment
import io.hydrabox.client.singbox.HydraBoxDefaultNetworkMonitor
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.InterfaceUpdateListener
import org.json.JSONObject
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

internal object CoreProcessIdentity {
    val epoch: String = UUID.randomUUID().toString()
    val sequence = AtomicLong(0L)
    val generation = AtomicLong(0L)
}

private fun shortId(value: String): String = value.take(8).ifEmpty { "none" }

internal fun nativeSourceLabel(): String = "embedded"

internal const val START_DEADLINE_MILLIS = 45_000L
internal const val CHALLENGE_DEADLINE_MILLIS = 120_000L
internal const val LOST_GRACE_MILLIS = 10_000L
internal const val RECOVERY_DEADLINE_MILLIS = 60_000L
internal const val UTILITY_DEADLINE_MILLIS = 10_000L

internal fun startSourceFor(recovery: Boolean, requestSource: String, sticky: Boolean): String = when {
    recovery -> "recovery"
    sticky -> "sticky"
    requestSource.isNotBlank() -> requestSource
    else -> "ui"
}

internal fun setNetworkGenerationBeforeRebind(
    generation: Long,
    setGeneration: (Long) -> Unit,
    rebind: () -> Unit,
) {
    runCatching { setGeneration(generation) }
    rebind()
}

/** Additive, side-effect-free runtime transition model; production wiring follows separately. */
internal sealed interface RuntimeInput {
    sealed interface Command : RuntimeInput {
        data class Submitted(val value: CoreRuntimeProtocol.RuntimeCommand) : Command
        data class Start(
            val commandId: String = "",
            val configSha256: String = "",
            val mode: CoreRuntimeProtocol.RuntimeMode = CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED,
        ) : Command
        data class Stop(val commandId: String = "") : Command
        data class NetworkChanged(
            val payload: CoreRuntimeProtocol.NetworkChanged = CoreRuntimeProtocol.NetworkChanged.getDefaultInstance(),
            val network: Network? = null,
            val listeners: List<InterfaceUpdateListener> = emptyList(),
        ) : Command
        data object Reload : Command
        data object SelectOutbound : Command
    }

    sealed interface Event : RuntimeInput {
        data class Launched(val commandGeneration: Long, val runtimeGeneration: Long) : Event
        data class Health(
            val commandGeneration: Long,
            val runtimeGeneration: Long,
            val ready: Boolean,
            val challenge: Boolean = false,
            val activeLanes: Int = 0,
            val applicable: Boolean = false,
            val lostForMillis: Long = 0L,
        ) : Event
        data class Deadline(val commandGeneration: Long) : Event
        data class Released(val commandGeneration: Long, val success: Boolean) : Event
        data class StickyRestart(val mode: String) : Event
        data class Replay(val listener: ICoreRuntimeListener) : Event
        data class ControllerEvent(val value: Any?) : Event
    }
}

internal data class ActiveCommand(
    val kind: CoreRuntimeProtocol.CommandKind,
    val configSha256: String,
    val mode: CoreRuntimeProtocol.RuntimeMode,
    val commandGeneration: Long,
    val commandIds: MutableList<String>,
)

internal enum class RuntimeCommandDecision { NoOp, Join, Supersede, Reject, Queue }

internal enum class NetworkChangeAction { ApplyUnderlying, ApplyUnderlyingAndRebind }

internal data class RuntimeMachineState(
    val value: CoreRuntimeProtocol.RuntimeState,
    val commandGeneration: Long,
    val runtimeGeneration: Long = 0L,
    val activeCommand: ActiveCommand? = null,
)

internal data class RuntimeReduceContext(
    val startDeadlineMillis: Long = START_DEADLINE_MILLIS,
    val challengeDeadlineMillis: Long = CHALLENGE_DEADLINE_MILLIS,
)

internal data class Decision(
    val state: RuntimeMachineState,
    val deadlineMillis: Long? = null,
    val commandDecision: RuntimeCommandDecision? = null,
    val networkChangeAction: NetworkChangeAction? = null,
)

internal data class PendingSelection(
    val outboundId: String,
    val commandGeneration: Long,
)

internal fun pendingSelectionsAfterAcceptedSelection(
    pendingSelections: Map<String, PendingSelection>,
    groupId: String,
    outboundId: String,
    commandGeneration: Long,
): Map<String, PendingSelection> = pendingSelections + (
    groupId to PendingSelection(outboundId, commandGeneration)
)

internal fun pendingSelectionsAfterGroups(
    pendingSelections: Map<String, PendingSelection>,
    selectedOutbounds: Map<String, String>,
    commandGeneration: Long,
): Map<String, PendingSelection> = pendingSelections.filterValues { pending ->
    pending.commandGeneration == commandGeneration
}.filter { (groupId, pending) -> selectedOutbounds[groupId] != pending.outboundId }

internal fun reduce(
    state: RuntimeMachineState,
    input: RuntimeInput,
    ctx: RuntimeReduceContext,
): Decision = when (input) {
    is RuntimeInput.Command.Submitted -> Decision(state)
    is RuntimeInput.Command.Start -> when (state.value) {
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED,
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED -> Decision(
            state.copy(
                value = CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
                commandGeneration = state.commandGeneration + 1,
                runtimeGeneration = 0L,
                activeCommand = ActiveCommand(
                    CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START,
                    input.configSha256,
                    input.mode,
                    state.commandGeneration + 1,
                    mutableListOf(input.commandId),
                ),
            ),
            ctx.startDeadlineMillis,
        )
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING -> when {
            state.activeCommand?.kind == CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START &&
                state.activeCommand.configSha256 == input.configSha256 &&
                state.activeCommand.mode == input.mode -> Decision(state, commandDecision = RuntimeCommandDecision.NoOp)
            else -> Decision(state, commandDecision = RuntimeCommandDecision.Supersede)
        }
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING -> if (
            state.activeCommand?.mode == input.mode
        ) {
            Decision(state, commandDecision = RuntimeCommandDecision.NoOp)
        } else {
            Decision(
                state.copy(
                    value = CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING,
                    commandGeneration = state.commandGeneration + 1,
                ),
                commandDecision = RuntimeCommandDecision.Supersede,
            )
        }
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING -> Decision(state, commandDecision = RuntimeCommandDecision.Queue)
        else -> Decision(state, commandDecision = RuntimeCommandDecision.Reject)
    }
    is RuntimeInput.Command.Stop -> when (state.value) {
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED -> Decision(state, commandDecision = RuntimeCommandDecision.Reject)
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING -> if (
            state.activeCommand?.kind == CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP
        ) {
            Decision(state, commandDecision = RuntimeCommandDecision.Join)
        } else {
            Decision(state, commandDecision = RuntimeCommandDecision.Reject)
        }
        else -> Decision(
            state.copy(
                value = CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING,
                commandGeneration = state.commandGeneration + 1,
                activeCommand = ActiveCommand(
                    CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP,
                    "",
                    CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED,
                    state.commandGeneration + 1,
                    mutableListOf(input.commandId),
                ),
            ),
            commandDecision = RuntimeCommandDecision.Queue,
        )
    }
    is RuntimeInput.Command.NetworkChanged -> when (state.value) {
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING ->
            Decision(state, commandDecision = RuntimeCommandDecision.Reject)
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING ->
            Decision(state, networkChangeAction = NetworkChangeAction.ApplyUnderlying)
        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING ->
            Decision(state, networkChangeAction = NetworkChangeAction.ApplyUnderlyingAndRebind)
        else -> Decision(state, commandDecision = RuntimeCommandDecision.Reject)
    }
    RuntimeInput.Command.Reload,
    RuntimeInput.Command.SelectOutbound -> if (
        state.value != CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING
    ) Decision(state, commandDecision = RuntimeCommandDecision.Reject) else Decision(state)
    is RuntimeInput.Event.Launched -> if (
        state.value in setOf(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING,
        ) && input.commandGeneration == state.commandGeneration
    ) {
        Decision(state.copy(runtimeGeneration = input.runtimeGeneration))
    } else {
        Decision(state)
    }
    is RuntimeInput.Event.Health -> if (
        state.value in setOf(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING,
        ) && input.commandGeneration == state.commandGeneration &&
        state.runtimeGeneration != 0L &&
        input.runtimeGeneration == state.runtimeGeneration
    ) {
        when {
            input.challenge -> Decision(state, ctx.challengeDeadlineMillis)
            input.ready -> Decision(
                state.copy(value = CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING),
            )
            else -> Decision(state)
        }
    } else if (
        state.value == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING &&
        input.commandGeneration == state.commandGeneration &&
        input.runtimeGeneration == state.runtimeGeneration
    ) {
        when {
            input.activeLanes > 0 || !input.applicable -> Decision(state)
            input.lostForMillis >= LOST_GRACE_MILLIS -> Decision(
                state.copy(value = CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING),
                RECOVERY_DEADLINE_MILLIS,
            )
            else -> Decision(state)
        }
    } else {
        Decision(state)
    }
    is RuntimeInput.Event.Deadline -> if (
        state.value in setOf(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING,
        ) && input.commandGeneration == state.commandGeneration
    ) {
        Decision(state.copy(value = CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED))
    } else {
        Decision(state)
    }
    is RuntimeInput.Event.Released -> if (
        state.value == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING &&
        input.commandGeneration == state.commandGeneration
    ) {
        Decision(
            state.copy(
                value = if (input.success) {
                    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED
                } else {
                    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED
                },
                runtimeGeneration = 0L,
            ),
        )
    } else {
        Decision(state)
    }
    is RuntimeInput.Event.StickyRestart,
    is RuntimeInput.Event.Replay,
    is RuntimeInput.Event.ControllerEvent -> Decision(state)
}

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

internal fun deadlineFor(interactive: Boolean, waitingUser: Boolean): Long =
    if (interactive && waitingUser) CHALLENGE_DEADLINE_MILLIS else START_DEADLINE_MILLIS

internal fun isReady(health: CoreRuntimeProtocol.TransportHealthSnapshot): Boolean =
    !health.applicable || (
        health.activeLanes >= 1 && health.state in setOf(
            CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_HEALTHY,
            CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_DEGRADED,
        )
    )

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
    private val commandThread = AtomicReference<Thread?>()
    private val commandExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HydraCoreRuntimeCommands").apply {
            commandThread.set(this)
            isDaemon = true
        }
    }
    private val probeThread = AtomicReference<Thread?>()
    private val probeExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HydraCoreProbe").apply {
            probeThread.set(this)
            isDaemon = true
        }
    }
    private val scheduler = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "HydraCoreRuntimeTimers").apply { isDaemon = true }
    }
    private val pendingUtilityRequestIds = ConcurrentHashMap.newKeySet<String>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val selectedOutbounds = linkedMapOf<String, String>()
    private var pendingSelections = emptyMap<String, PendingSelection>()
    private val snapshotLock = Any()
    private var activeConfigSha256 = ByteArray(0)
    private var lastError: CoreRuntimeProtocol.CoreError? = null
    private var probeLastError: CoreRuntimeProtocol.CoreError? = null
    private var outboundGroups = emptyList<CoreRuntimeProtocol.OutboundGroupSnapshot>()
    private var probeSessions = emptyList<CoreRuntimeProtocol.ProbeSession>()
    private val managedProbeAliases = linkedMapOf<String, String>()
    private var ephemeralProbeSessionId: String? = null
    private var networkSnapshot = CoreRuntimeProtocol.NetworkSnapshot.getDefaultInstance()
    private var appliedNetworkGeneration = 0L
    private var transportHealth = CoreRuntimeProtocol.TransportHealthSnapshot.getDefaultInstance()
    @Volatile private var transportHealthRequired = false
    @Volatile private var interactiveStart = false
    @Volatile private var startDeadlineStartedAt = 0L
    @Volatile private var activeRuntimeGeneration = 0L
    @Volatile private var activeStartCommandId = ""
    private var activeCommand: ActiveCommand? = null
    private var deferredStart: CoreRuntimeProtocol.RuntimeCommand? = null
    private var transportHealthPoll: ScheduledFuture<*>? = null
    private var transportLostSinceMillis = 0L
    private var pendingRelease: CloseTask? = null
    private var controllerRegistration = 0L
    private lateinit var coreContract: CoreRuntimeProtocol.CoreContract
    private data class CloseTask(val commandGeneration: Long, val onComplete: (Boolean) -> Unit)

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
            if (command.kind in setOf(
                    CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START_PROBE,
                    CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_PROBE,
                )
            ) {
                probeExecutor.execute { execute(command) }
            } else {
                submitInternal(RuntimeInput.Command.Submitted(command))
            }
            return receipt.toByteArray()
        }

        override fun executeUtility(requestBytes: ByteArray?): ByteArray =
            executeCoreUtility(requestBytes).toByteArray()

        override fun registerListener(listener: ICoreRuntimeListener?) {
            if (listener != null) {
                listeners.register(listener)
                submitInternal(RuntimeInput.Event.Replay(listener))
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
        currentService = this
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
                        submitInternal(RuntimeInput.Event.ControllerEvent(event))
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
                        submitInternal(RuntimeInput.Event.ControllerEvent(null))
                    }
                },
            )
            refreshNetworkSnapshotFromMonitor("core_service_start")

            // A stale 0.x or interrupted-write config is a configuration recovery,
            // not a broken native core. Keep the binder alive and quarantine the
            // invalid private file so the UI can compile a clean plan.
            startupFailure.markStage("config_recovery", nativeSourceLabel())
            recoverInvalidPersistedConfig()

            startupFailure.markStage("snapshot", nativeSourceLabel())
            buildSnapshot()
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

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STICKY_RESTART) {
            submitInternal(RuntimeInput.Event.StickyRestart(intent.getStringExtra(EXTRA_STICKY_MODE).orEmpty()))
        }
        return START_NOT_STICKY
    }

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
        if (currentService === this) currentService = null
        transportHealthPoll?.cancel(true)
        scheduler.shutdownNow()
        SingboxController.clearEventSink(controllerRegistration)
        listeners.kill()
        commandExecutor.shutdownNow()
        probeExecutor.shutdownNow()
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
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START -> executeStart(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP -> executeStop(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_RELOAD -> executeReload(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_SELECT_OUTBOUND -> executeSelectOutbound(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START_PROBE -> startProbe(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_PROBE -> cancelProbe(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_REQUEST_RECOVERY -> recover(command)
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_CANCEL_RUNTIME_CHALLENGE ->
                cancelRuntimeChallenge(command)
            else -> Unit
        }
    }

    private fun executeStart(command: CoreRuntimeProtocol.RuntimeCommand) {
        val request = command.start
        when (reduce(
            RuntimeMachineState(state.get(), generation.get(), activeRuntimeGeneration, activeCommand),
            RuntimeInput.Command.Start(command.commandId, request.configSha256.toByteArray().toHex(), request.mode),
            RuntimeReduceContext(),
        ).commandDecision) {
            RuntimeCommandDecision.NoOp -> activeCommand?.commandIds?.add(command.commandId)
            RuntimeCommandDecision.Supersede -> {
                activeCommand?.let(::commandSuperseded)
                activeCommand = null
                deferredStart = command
                stopForSupersededStart()
            }
            RuntimeCommandDecision.Queue -> {
                deferredStart?.let { commandSuperseded(listOf(it.commandId)) }
                deferredStart = command
            }
            else -> start(command)
        }
    }

    private fun executeStop(command: CoreRuntimeProtocol.RuntimeCommand) {
        if (state.get() == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING &&
            activeCommand?.kind == CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP
        ) {
            activeCommand?.commandIds?.add(command.commandId)
            return
        }
        activeCommand?.takeIf { it.kind == CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START }
            ?.let(::commandCancelled)
        activeCommand = null
        stop(command)
    }

    private fun executeReload(command: CoreRuntimeProtocol.RuntimeCommand) {
        if (state.get() != CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING) {
            commandFailed(command.commandId, "runtime.reload.not_running", "reload", "HydraCore is not running.", false)
            return
        }
        reload(command)
    }

    private fun executeSelectOutbound(command: CoreRuntimeProtocol.RuntimeCommand) {
        if (state.get() != CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING) {
            failCommand(command.commandId, "runtime.selector.not_running", "selector", "HydraCore is not running.", false)
            return
        }
        selectOutbound(command)
    }

    // HB-RW-010 uses the existing start/shutdownRuntimeServices flow; this baseline has no LaunchTask.
    private fun stopForSupersededStart() {
        generation.incrementAndGet()
        updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING)
        HydraBoxDiagnostics.event(
            "STOP",
            "prof" to synchronized(snapshotLock) { shortHex(activeConfigSha256) },
            "reason" to "superseded",
        )
        shutdownRuntimeServices("superseded") { stopped ->
            if (stopped) {
                resetStoppedRuntimeState()
                deferredStart?.also { deferredStart = null; start(it) }
            } else {
                deferredStart?.also {
                    deferredStart = null
                    commandFailed(
                        it.commandId,
                        "runtime.stop.deadline",
                        "runtime_stop",
                        "HydraCore did not confirm that it stopped.",
                        true,
                    )
                }
            }
        }
    }

    private fun submitInternal(input: RuntimeInput) {
        commandExecutor.execute {
            when (input) {
                is RuntimeInput.Command.Submitted -> execute(input.value)
                is RuntimeInput.Command.Start,
                is RuntimeInput.Command.Stop -> Unit
                is RuntimeInput.Command.NetworkChanged -> handleNetworkChanged(input)
                RuntimeInput.Command.Reload,
                RuntimeInput.Command.SelectOutbound -> Unit
                is RuntimeInput.Event.Launched -> handleLaunched(input)
                is RuntimeInput.Event.Deadline -> handleDeadline(input)
                is RuntimeInput.Event.Released -> handleReleased(input)
                is RuntimeInput.Event.Health -> handleHealth(input)
                is RuntimeInput.Event.StickyRestart -> if (
                    state.get() !in setOf(
                        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
                        CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING,
                    )
                ) reconcile("sticky")
                is RuntimeInput.Event.Replay ->
                    runCatching { input.listener.onEvent(snapshotEvent().toByteArray()) }
                is RuntimeInput.Event.ControllerEvent -> handleControllerEvent(input.value)
            }
        }
    }

    private fun isOnCommandThread(): Boolean = Thread.currentThread() === commandThread.get()

    private fun isOnProbeThread(): Boolean = Thread.currentThread() === probeThread.get()

    private fun handleNetworkChanged(input: RuntimeInput.Command.NetworkChanged) {
        val commandId = "network:${input.payload.networkGeneration}"
        val decision = reduce(
            RuntimeMachineState(state.get(), generation.get(), activeRuntimeGeneration, activeCommand),
            input,
            RuntimeReduceContext(),
        )
        if (decision.commandDecision == RuntimeCommandDecision.Reject ||
            input.payload.networkGeneration <= appliedNetworkGeneration
        ) {
            commandFailed(
                commandId,
                "runtime.network.rejected",
                "network_changed",
                "The network update is no longer applicable.",
                false,
            )
            return
        }
        appliedNetworkGeneration = input.payload.networkGeneration
        val applied = HydraBoxVpnService.setUnderlyingNetwork(input.network, "network_changed")
        if (!applied && input.network != null) {
            HydraBoxVpnService.setUnderlyingNetwork(null, "network_changed_fallback")
        }
        writeNetworkSnapshot(
            available = input.payload.available,
            interfaceName = input.payload.interfaceName,
            interfaceIndex = input.payload.interfaceIndex,
            generation = input.payload.networkGeneration,
            updatedAtMillis = System.currentTimeMillis(),
        )
        if (decision.networkChangeAction == NetworkChangeAction.ApplyUnderlyingAndRebind) {
            setNetworkGenerationBeforeRebind(
                input.payload.networkGeneration,
                { Libbox.hydraCoreSetNetworkGeneration(it) },
            ) {
                input.listeners.forEach { listener ->
                    runCatching {
                        listener.updateDefaultInterface(
                            input.payload.interfaceName,
                            input.payload.interfaceIndex,
                            false,
                            false,
                        )
                    }.onFailure { Log.e(TAG, "updateDefaultInterface failed", it) }
                }
            }
            HydraBoxDiagnostics.event(
                "REBIND", "ep" to shortId(processEpoch), "cg" to generation.get(),
                "rg" to activeRuntimeGeneration, "ng" to input.payload.networkGeneration,
                "prof" to synchronized(snapshotLock) { shortHex(activeConfigSha256) },
                "paths_closed" to 0,
            )
        }
        SingboxController.cancelPreconnectUrlTest("network_changed")
        commandSucceeded(commandId, state.get())
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
        refreshTransportHealth(emitEvent = true)
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
                    return lookupOutboundExternalInfo(request)
                CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_UPDATE_NOTIFICATION -> {
                    require(request.argumentsCount == 1)
                    val value = CoreRuntimeProtocol.NotificationPresentation.parseFrom(
                        request.getArguments(0),
                    )
                    check(
                        RuntimeSession.updateNotificationPresentation(
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
    ): CoreRuntimeProtocol.CoreUtilityResponse {
        require(request.argumentsCount == 1)
        val outboundId = request.getArguments(0).toStringUtf8().trim()
        require(outboundId.isNotEmpty())
        if (!pendingUtilityRequestIds.add(request.requestId)) {
            return utilityFailure(
                request.requestId,
                "core.utility.duplicate",
                "utility_request",
                "The utility request is already pending.",
            )
        }
        SingboxController.lookupOutboundExternalInfo(outboundId) {
            commandExecutor.execute {
                val response = it.fold(
                    onSuccess = { value ->
                        CoreRuntimeProtocol.CoreUtilityResponse.newBuilder()
                            .setSchemaVersion(SCHEMA_VERSION)
                            .setRequestId(request.requestId)
                            .setPayload(
                                CoreRuntimeProtocol.OutboundExternalInfo.newBuilder()
                                    .setOutboundId(outboundId)
                                    .setIpAddress(value["ip"].orEmpty())
                                    .setCountryCode(value["countryCode"].orEmpty())
                                    .build()
                                    .toByteString(),
                            )
                            .build()
                    },
                    onFailure = {
                        utilityFailure(
                            request.requestId,
                            "core.utility.failed",
                            "utility_execution",
                            "HydraCore could not complete the request.",
                        )
                    },
                )
                pendingUtilityRequestIds.remove(request.requestId)
                emit(eventBuilder().setUtilityResult(response).build())
            }
        }
        return CoreRuntimeProtocol.CoreUtilityResponse.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setRequestId(request.requestId)
            .build()
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

    private fun start(
        command: CoreRuntimeProtocol.RuntimeCommand,
        recovery: Boolean = false,
        recoverySource: String = "recovery",
        recoveryAttempt: Int = 0,
    ) {
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
        refreshTransportHealth(emitEvent = false)
        val commandGeneration = generation.incrementAndGet()
        activeStartCommandId = command.commandId
        activeCommand = ActiveCommand(
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START,
            expectedDigest.toHex(),
            request.mode,
            commandGeneration,
            mutableListOf(command.commandId),
        )
        interactiveStart = request.interactiveDeadlineMillis > START_DEADLINE_MILLIS
        startDeadlineStartedAt = System.currentTimeMillis()
        mode.set(request.mode)
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
            "source" to startSourceFor(
                recovery = recovery && recoverySource != "sticky",
                requestSource = request.source,
                sticky = recovery && recoverySource == "sticky",
            ),
            "attempt" to recoveryAttempt,
        )
        updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING)
        scheduleDeadline(commandGeneration, START_DEADLINE_MILLIS)
        mainHandler.post {
            val targetName = if (request.mode == CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN) "vpn" else "proxy"
            val sameRunningMode = SingboxController.running && SingboxController.serviceMode == targetName
            when {
                sameRunningMode && request.restartCore -> {
                    val serviceClass = serviceClass(request.mode)
                    updateState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING)
                    startService(
                        Intent(this, serviceClass)
                            .setAction(RuntimeSession.ACTION_RESTART_CORE)
                            .putExtra(RuntimeSession.EXTRA_COMMAND_GENERATION, commandGeneration),
                    )
                }
                sameRunningMode && request.applyConfig -> {
                    SingboxController.reloadService { result ->
                        result.onSuccess {
                            submitInternal(
                                RuntimeInput.Event.Launched(
                                    commandGeneration,
                                    SingboxController.activeRuntimeGeneration,
                                ),
                            )
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
                sameRunningMode -> submitInternal(
                    RuntimeInput.Event.Launched(commandGeneration, SingboxController.activeRuntimeGeneration),
                )
                else -> {
                    dispatchStart(request.mode, commandGeneration)
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

    private fun dispatchStart(targetMode: CoreRuntimeProtocol.RuntimeMode, commandGeneration: Long) {
        val serviceClass = serviceClass(targetMode)
        startForegroundService(
            Intent(this, serviceClass)
                .setAction(RuntimeSession.ACTION_START)
                .putExtra(RuntimeSession.EXTRA_COMMAND_GENERATION, commandGeneration),
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

    private fun scheduleDeadline(commandGeneration: Long, delayMillis: Long) {
        scheduler.schedule(
            { submitInternal(RuntimeInput.Event.Deadline(commandGeneration)) },
            delayMillis,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun handleLaunched(input: RuntimeInput.Event.Launched) {
        val decision = reduce(
            RuntimeMachineState(state.get(), generation.get(), activeRuntimeGeneration),
            input,
            RuntimeReduceContext(),
        )
        if (decision.state == RuntimeMachineState(state.get(), generation.get(), activeRuntimeGeneration)) return
        activeRuntimeGeneration = decision.state.runtimeGeneration
        refreshNetworkSnapshotFromMonitor("runtime_start_complete")
        refreshTransportHealth(emitEvent = true)
    }

    private fun handleHealth(input: RuntimeInput.Event.Health) {
        val current = RuntimeMachineState(state.get(), generation.get(), activeRuntimeGeneration)
        val decision = reduce(current, input, RuntimeReduceContext())
        if (decision.deadlineMillis != null) {
            scheduleDeadline(input.commandGeneration, decision.deadlineMillis)
        }
        if (decision.state.value != current.value) {
            updateState(decision.state.value)
            if (decision.state.value == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING) {
                completeHealthyStart(activeStartCommandId)
            }
        } else if (current.value in setOf(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING,
            ) && synchronized(snapshotLock) {
                transportHealth.state ==
                    CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_FAILED
            }
        ) {
            failStartAndRollback(
                activeStartCommandId,
                input.commandGeneration,
                "runtime.transport.unhealthy",
                "transport_health",
                "HydraCore did not establish a usable transport.",
                true,
            )
        }
        emit(snapshotEvent())
    }

    private fun handleDeadline(input: RuntimeInput.Event.Deadline) {
        val current = RuntimeMachineState(state.get(), generation.get(), activeRuntimeGeneration)
        val health = synchronized(snapshotLock) { transportHealth }
        val deadline = deadlineFor(
            interactiveStart,
            health.state == CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_WAITING_USER,
        )
        val remaining = deadline - (System.currentTimeMillis() - startDeadlineStartedAt)
        if (remaining > 0L) {
            scheduleDeadline(input.commandGeneration, remaining)
            return
        }
        val decision = reduce(current, input, RuntimeReduceContext())
        if (decision.state.value != CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED) return
        val transportFailed = health.state ==
            CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_FAILED
        failStartAndRollback(
            activeStartCommandId,
            input.commandGeneration,
            if (transportFailed) "runtime.transport.unhealthy" else "runtime.start.deadline",
            if (transportFailed) "transport_health" else "runtime_start",
            if (transportFailed) "HydraCore did not establish a usable transport."
            else "HydraCore did not reach the running state before the deadline.",
            true,
        )
    }

    private fun handleReleased(input: RuntimeInput.Event.Released) {
        val current = RuntimeMachineState(state.get(), generation.get(), activeRuntimeGeneration)
        val decision = reduce(current, input, RuntimeReduceContext())
        if (decision.state == current) return
        val pending = pendingRelease ?: return
        if (pending.commandGeneration != input.commandGeneration) return
        pendingRelease = null
        updateState(decision.state.value)
        HydraBoxDiagnostics.event(
            "STOP",
            "cg" to input.commandGeneration,
            "prof" to synchronized(snapshotLock) { shortHex(activeConfigSha256) },
            "stage" to "released",
        )
        pending.onComplete(input.success)
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
            if (generation.get() != commandGeneration) {
                return@shutdownRuntimeServices
            }
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
        val commandGeneration = generation.get()
        pendingRelease = CloseTask(commandGeneration, onComplete)
        mainHandler.post {
            RuntimeSession.requestStopAll(reason)
            // Destroy both possible owners as part of the same transaction. A
            // failed start must not leave Android's VPN service and its TUN
            // alive while the runtime is reported as failed.
            stopService(Intent(this, HydraBoxVpnService::class.java))
            stopService(Intent(this, HydraBoxProxyService::class.java))
            scheduler.schedule(
                { submitInternal(RuntimeInput.Event.Released(commandGeneration, false)) },
                CLOSE_DEADLINE_MILLIS,
                TimeUnit.MILLISECONDS,
            )
        }
    }

    private fun resetStoppedRuntimeState() {
        mode.set(CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED)
        transportHealthRequired = false
        synchronized(snapshotLock) {
            transportHealth = CoreRuntimeProtocol.TransportHealthSnapshot.getDefaultInstance()
            managedProbeAliases.clear()
            pendingSelections = emptyMap()
        }
    }

    private fun stop(command: CoreRuntimeProtocol.RuntimeCommand) {
        generation.incrementAndGet()
        activeCommand = ActiveCommand(
            CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP,
            "",
            CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED,
            generation.get(),
            mutableListOf(command.commandId),
        )
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
            failCommand(command.commandId, "runtime.selector.invalid", "selector", "The outbound selection is invalid.", false)
            return
        }
        val commandGeneration = generation.incrementAndGet()
        SingboxController.selectOutbound(request.groupId, request.outboundId) { result ->
            commandExecutor.execute {
                result.onSuccess {
                    if (generation.get() == commandGeneration) {
                        synchronized(snapshotLock) {
                            pendingSelections = pendingSelectionsAfterAcceptedSelection(
                                pendingSelections,
                                request.groupId,
                                request.outboundId,
                                commandGeneration,
                            )
                        }
                    }
                    commandSucceeded(command.commandId, state.get())
                }.onFailure {
                    failCommand(command.commandId, "runtime.selector.failed", "selector", "HydraCore rejected the outbound selection.", true)
                }
            }
        }
    }

    private fun startProbe(command: CoreRuntimeProtocol.RuntimeCommand) {
        val request = command.startProbe
        if (request.sessionId.isBlank() || request.groupId.isBlank() || request.outboundIdsCount == 0 ||
            request.url.isBlank() || request.concurrency !in 1..32 ||
            request.timeoutMillis !in 500..120_000
        ) {
            failProbe(command.commandId, "probe.request.invalid", "probe", "The probe request is invalid.", false)
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
                failProbe(
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
        ) { result -> probeExecutor.execute callback@{
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
                emitProbe { eventBuilder().setProbeSession(session).build() }
                probeSucceeded(command.commandId)
            }.onFailure {
                failProbe(command.commandId, "probe.start.failed", "probe_start", "HydraCore could not start the probe session.", true)
            }
        } }
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
            failProbe(
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
        emitProbe { eventBuilder().setProbeSession(runningSession).build() }
        probeSucceeded(command.commandId)
        val deadlineDelay = (request.deadlineAtMillis - System.currentTimeMillis())
            .coerceIn(request.timeoutMillis.toLong(), 120_000L)
        mainHandler.postDelayed({ probeExecutor.execute {
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
        } }, deadlineDelay)
        SingboxController.preconnectUrlTest(
            config = config.toString(Charsets.UTF_8),
            groupTag = request.groupId,
            targetOutboundTag = outboundId,
            url = request.url,
            timeoutMillis = request.timeoutMillis.toInt(),
            deadlineMillis = (request.deadlineAtMillis - System.currentTimeMillis())
                .coerceIn(request.timeoutMillis.toLong(), 120_000L).toInt(),
        ) { result -> probeExecutor.execute callback@{
            val stillCurrent = synchronized(snapshotLock) {
                ephemeralProbeSessionId == request.sessionId
            }
            if (!stillCurrent) return@callback
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
                emitProbe { eventBuilder().setProbeResult(probe).build() }
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
        } }
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
        emitProbe { eventBuilder().setProbeSession(session).build() }
        emitProbe(::snapshotEvent)
    }

    private fun cancelProbe(command: CoreRuntimeProtocol.RuntimeCommand) {
        val requestedId = command.cancelProbe.sessionId
        val isEphemeral = synchronized(snapshotLock) { ephemeralProbeSessionId == requestedId }
        if (isEphemeral) {
            SingboxController.cancelPreconnectUrlTest("probe_cancel") { result -> probeExecutor.execute {
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
                    emitProbe { eventBuilder().setProbeSession(session).build() }
                    probeSucceeded(command.commandId)
                }.onFailure {
                    failProbe(
                        command.commandId,
                        "probe.cancel.failed",
                        "probe_cancel",
                        "HydraCore could not cancel the probe session.",
                        true,
                    )
                }
            } }
            return
        }
        val nativeId = synchronized(snapshotLock) {
            managedProbeAliases.entries.firstOrNull { it.value == requestedId }?.key ?: requestedId
        }
        SingboxController.cancelManagedUrlTest(nativeId) { result -> probeExecutor.execute {
            result.onSuccess {
                val session = CoreRuntimeProtocol.ProbeSession.newBuilder()
                    .setSessionId(requestedId)
                    .setState(CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_CANCELLED)
                    .setFinishedAtMillis(System.currentTimeMillis())
                    .build()
                synchronized(snapshotLock) { managedProbeAliases.remove(nativeId) }
                emitProbe { eventBuilder().setProbeSession(session).build() }
                probeSucceeded(command.commandId)
            }.onFailure {
                failProbe(command.commandId, "probe.cancel.failed", "probe_cancel", "HydraCore could not cancel the probe session.", true)
            }
        } }
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
        RuntimeSession.requestStopAll("recovery:${command.requestRecovery.reason}")
        val commandGeneration = generation.incrementAndGet()
        activeStartCommandId = command.commandId
        scheduleDeadline(commandGeneration, START_DEADLINE_MILLIS)
        scheduler.schedule(
            { mainHandler.post { dispatchStart(mode.get(), commandGeneration) } },
            STATE_POLL_MILLIS,
            TimeUnit.MILLISECONDS,
        )
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

    private fun handleControllerEvent(value: Any?) {
        val event = value as? Map<*, *>
        when (event?.get("type")?.toString()) {
            "state" -> if (event["running"] == true) {
                submitInternal(
                    RuntimeInput.Event.Launched(
                        generation.get(),
                        (event["runtimeGeneration"] as? Number)?.toLong() ?: 0L,
                    ),
                )
            }
            "released" -> pendingRelease?.takeIf {
                state.get() == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING
            }?.let { close ->
                submitInternal(RuntimeInput.Event.Released(close.commandGeneration, true))
            }
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
            pendingSelections = pendingSelectionsAfterGroups(
                pendingSelections,
                selectedOutbounds,
                generation.get(),
            )
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

    private fun refreshTransportHealth(emitEvent: Boolean) {
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
                TransportHealthBridge.parse(Libbox.hydraCoreTransportState(), transportHealthRequired)
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
        val now = System.currentTimeMillis()
        val health = synchronized(snapshotLock) { transportHealth }
        val lostForMillis = if (health.applicable && health.activeLanes == 0) {
            if (transportLostSinceMillis == 0L) transportLostSinceMillis = now
            now - transportLostSinceMillis
        } else {
            transportLostSinceMillis = 0L
            0L
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
        if (emitEvent) {
            submitInternal(
                RuntimeInput.Event.Health(
                    commandGeneration = generation.get(),
                    runtimeGeneration = SingboxController.activeRuntimeGeneration,
                    ready = isReady(health),
                    challenge = health.state ==
                        CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_WAITING_USER,
                    activeLanes = health.activeLanes,
                    applicable = health.applicable,
                    lostForMillis = lostForMillis,
                ),
            )
        }
    }

    private fun buildSnapshot(): CoreRuntimeProtocol.RuntimeSnapshot {
        synchronized(snapshotLock) {
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
                .setState(state.get())
                .setMode(mode.get())
                .setActiveConfigSha256(ByteString.copyFrom(activeConfigSha256))
                .putAllSelectedOutboundIds(selectedOutbounds)
                .putAllPendingSelectedOutboundIds(pendingSelections.mapValues { it.value.outboundId })
                .setTraffic(traffic)
                .setNetwork(networkSnapshot)
                .setUpdatedAtMillis(System.currentTimeMillis())
                .setHealthy(
                    state.get() == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING && isReady(transportHealth),
                )
                .addAllOutboundGroups(outboundGroups)
                .addAllProbeSessions(probeSessions)
                .setTransportHealth(transportHealth)
            HydraBoxApplication.readDesiredRuntime()?.let { desired ->
                builder.setDesiredRuntime(
                    CoreRuntimeProtocol.DesiredRuntime.newBuilder()
                        .setWantRunning(desired.wantRunning)
                        .setMode(
                            if (desired.mode == "proxy") CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY
                            else CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN,
                        )
                        .setConfigSha256(ByteString.copyFromUtf8(desired.configSha256))
                        .setRecoveryAttempt(desired.recoveryAttempt)
                        .setUpdatedAtMillis(desired.updatedAtMillis),
                )
            }
            lastError?.let(builder::setLastError)
            probeLastError?.let(builder::setProbeLastError)
            return builder.build()
        }
    }

    private fun updateState(value: CoreRuntimeProtocol.RuntimeState) {
        if (!isOnCommandThread()) {
            commandExecutor.execute { updateState(value) }
            return
        }
        state.set(value)
        if (value in setOf(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING,
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING,
            )
        ) {
            if (transportHealthPoll == null || transportHealthPoll?.isCancelled == true) {
                transportHealthPoll = scheduler.scheduleAtFixedRate(
                    { refreshTransportHealth(emitEvent = true) },
                    0L,
                    TRANSPORT_HEALTH_POLL_MILLIS,
                    TimeUnit.MILLISECONDS,
                )
            }
        } else {
            transportHealthPoll?.cancel(false)
            transportHealthPoll = null
        }
        notificationStatusFor(value)?.let(RuntimeSession::applyRuntimeStatus)
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

    private fun emitProbe(buildEvent: () -> CoreRuntimeProtocol.RuntimeEvent) {
        commandExecutor.execute { emit(buildEvent()) }
    }

    private fun probeSucceeded(commandId: String) {
        if (!isOnProbeThread()) {
            probeExecutor.execute { probeSucceeded(commandId) }
            return
        }
        emitProbe {
            eventBuilder().setCommandResult(
                CoreRuntimeProtocol.CommandResult.newBuilder()
                    .setSchemaVersion(SCHEMA_VERSION)
                    .setCommandId(commandId)
                    .setOutcome(CoreRuntimeProtocol.CommandOutcome.COMMAND_OUTCOME_SUCCEEDED)
                    .setFinalState(state.get())
                    .setGeneration(generation.get())
                    .setCompletedAtMillis(System.currentTimeMillis())
                    .build(),
            ).build()
        }
    }

    private fun failProbe(
        commandId: String,
        code: String,
        stage: String,
        safeMessage: String,
        retryable: Boolean,
    ) {
        if (!isOnProbeThread()) {
            probeExecutor.execute { failProbe(commandId, code, stage, safeMessage, retryable) }
            return
        }
        val error = coreError(code, stage, safeMessage, retryable, commandId.ifBlank { UUID.randomUUID().toString() })
        synchronized(snapshotLock) { probeLastError = error }
        emitProbe {
            eventBuilder().setCommandResult(
                CoreRuntimeProtocol.CommandResult.newBuilder()
                    .setSchemaVersion(SCHEMA_VERSION)
                    .setCommandId(commandId)
                    .setOutcome(CoreRuntimeProtocol.CommandOutcome.COMMAND_OUTCOME_FAILED)
                    .setFinalState(state.get())
                    .setGeneration(generation.get())
                    .setCompletedAtMillis(System.currentTimeMillis())
                    .setError(error)
                    .build(),
            ).build()
        }
        emitProbe(::snapshotEvent)
    }

    private fun commandSucceeded(commandId: String, finalState: CoreRuntimeProtocol.RuntimeState) {
        if (!isOnCommandThread()) {
            commandExecutor.execute { commandSucceeded(commandId, finalState) }
            return
        }
        val commandIds = activeCommand
            ?.takeIf { commandId in it.commandIds }
            ?.commandIds
            ?.toList()
            ?: listOf(commandId)
        if (commandIds.size > 1 || activeCommand?.commandIds?.contains(commandId) == true) activeCommand = null
        commandIds.forEach { completedCommandId ->
            emitCommandSuccess(completedCommandId, finalState)
        }
    }

    private fun emitCommandSuccess(commandId: String, finalState: CoreRuntimeProtocol.RuntimeState) {
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
        if (!isOnCommandThread()) {
            commandExecutor.execute { commandFailed(commandId, code, stage, safeMessage, retryable) }
            return
        }
        val commandIds = activeCommand
            ?.takeIf { commandId in it.commandIds }
            ?.commandIds
            ?.toList()
            ?: listOf(commandId)
        if (activeCommand?.commandIds?.contains(commandId) == true) activeCommand = null
        commandIds.forEach { failedCommandId ->
            failRuntime(failedCommandId, code, stage, safeMessage, retryable)
        }
    }

    private fun failCommand(
        commandId: String,
        code: String,
        stage: String,
        safeMessage: String,
        retryable: Boolean,
    ) {
        val error = coreError(code, stage, safeMessage, retryable, commandId)
        synchronized(snapshotLock) { lastError = error }
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

    private fun commandSuperseded(command: ActiveCommand) = commandSuperseded(command.commandIds)

    private fun commandSuperseded(commandIds: List<String>) =
        emitTerminalFailures(commandIds, "runtime.superseded", "runtime_command", "The runtime command was superseded.")

    private fun commandCancelled(command: ActiveCommand) =
        emitTerminalFailures(command.commandIds, "runtime.cancelled", "runtime_command", "The runtime command was cancelled.")

    private fun emitTerminalFailures(commandIds: List<String>, code: String, stage: String, safeMessage: String) {
        commandIds.forEach { commandId ->
            val error = coreError(code, stage, safeMessage, false, commandId)
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
        }
        emit(snapshotEvent())
    }

    private fun failRuntime(
        commandId: String,
        code: String,
        stage: String,
        safeMessage: String,
        retryable: Boolean,
    ) {
        if (!isOnCommandThread()) {
            commandExecutor.execute { failRuntime(commandId, code, stage, safeMessage, retryable) }
            return
        }
        val error = coreError(code, stage, safeMessage, retryable, commandId.ifBlank { UUID.randomUUID().toString() })
        synchronized(snapshotLock) { lastError = error }
        HydraBoxApplication.readDesiredRuntime()?.let {
            HydraBoxApplication.writeDesiredRuntime(desiredRuntimeTransition(it, DesiredRuntimeEvent.FAILED))
        }
        state.set(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED)
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

    private fun reconcile(source: String = consumeReconcileSource()) {
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
        when (val decision = desiredRuntimeDecision(desired, config.toSha256Bytes().toHex())) {
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
                start(
                    command,
                    recovery = true,
                    recoverySource = source,
                    recoveryAttempt = decision.next.recoveryAttempt,
                )
            }
        }
    }

    private fun writeStoppedDesiredRuntime() {
        val current = HydraBoxApplication.readDesiredRuntime()
            ?: DesiredRuntime(false, modeName(mode.get()), currentConfigSha256(), 0, System.currentTimeMillis())
        HydraBoxApplication.writeDesiredRuntime(desiredRuntimeTransition(current, DesiredRuntimeEvent.USER_STOP))
    }

    private fun currentConfigSha256(): String = runCatching {
        HydraBoxApplication.configFile.readBytes().toSha256Bytes().toHex()
    }.getOrDefault("0".repeat(64))

    private fun modeName(value: CoreRuntimeProtocol.RuntimeMode): String =
        if (value == CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY) "proxy" else "vpn"

    private fun ByteArray.toSha256Bytes(): ByteArray = MessageDigest.getInstance("SHA-256").digest(this)

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it.toInt() and 0xff) }

    companion object {
        @Volatile private var currentService: CoreRuntimeService? = null
        private val stickyRestartSource = AtomicReference<String?>(null)

        const val ACTION_STICKY_RESTART = "io.hydrabox.client.runtime.STICKY_RESTART"
        const val EXTRA_STICKY_MODE = "sticky_mode"

        fun markStickyRestart() {
            stickyRestartSource.set("sticky")
        }

        fun consumeReconcileSource(): String = stickyRestartSource.getAndSet(null) ?: "recovery"

        fun submitInternalNetwork(
            network: Network?,
            payload: CoreRuntimeProtocol.NetworkChanged,
            listeners: List<InterfaceUpdateListener>,
        ) {
            currentService?.submitInternal(RuntimeInput.Command.NetworkChanged(payload, network, listeners))
        }

        private const val TAG = "HydraCoreRuntime"
        private const val SCHEMA_VERSION = 2
        private const val CORE_API_MINOR = 1
        private const val SHA256_BYTES = 32
        // Binder's transaction buffer is finite and shared by the process.
        private const val MAX_COMMAND_BYTES = 768 * 1024
        private const val MAX_CONFIG_BYTES = 700 * 1024
        private const val CLOSE_DEADLINE_MILLIS = 5_000L
        private const val TRANSPORT_HEALTH_POLL_MILLIS = 250L
        private const val STATE_POLL_MILLIS = 100L
        private const val ALL_OUTBOUNDS = "*"
        private const val MAX_RECOVERED_CONFIGS = 2
        private val COMMAND_ID_PATTERN = Regex("^[A-Za-z0-9._:-]{1,128}$")
    }
}
