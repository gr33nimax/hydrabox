package io.hydrabox.client.singbox

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SystemProxyStatus
import io.hydrabox.client.HydraBoxApplication
import io.hydrabox.client.HydraBoxQuickSettingsTileService
import io.hydrabox.client.runtime.CoreProcessIdentity
import org.json.JSONObject
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

private fun shortServiceId(value: String): String = value.take(8).ifEmpty { "none" }

internal enum class RuntimeSessionStage {
    FOREGROUND, NATIVE_SETUP, NETWORK_WAIT, COMMAND_SERVER, LIBBOX_START, COMMAND_CLIENT,
}

internal enum class RuntimeSessionOutcome { CONTINUE, CANCELLED }

internal fun runtimeSessionOutcome(
    stage: RuntimeSessionStage,
    launchGeneration: Long,
    currentCommandGeneration: Long,
    cancelled: Boolean,
): RuntimeSessionOutcome =
    if (cancelled || launchGeneration != currentCommandGeneration) {
        RuntimeSessionOutcome.CANCELLED
    } else {
        RuntimeSessionOutcome.CONTINUE
    }

class RuntimeSession(
    private val service: Service,
    private val platformInterface: PlatformInterface,
) : CommandServerHandler {
    companion object {
        private const val TAG = "RuntimeSession"
        const val ACTION_START = "io.hydrabox.client.singbox.START"
        const val EXTRA_COMMAND_GENERATION = "command_generation"
        const val ACTION_STOP = "io.hydrabox.client.singbox.STOP"
        const val ACTION_RELOAD = "io.hydrabox.client.singbox.RELOAD"
        const val ACTION_RESTART_CORE = "io.hydrabox.client.singbox.RESTART_CORE"
        const val EXTRA_STOP_REASON = "stop_reason"
        private const val NOTIFICATION_ID = 42
        private const val CLEANUP_STEP_TIMEOUT_MS = 1_200L
        private const val CLOSE_DEADLINE_MS = 5_000L
        private const val NETWORK_WAIT_TIMEOUT_MS = 2_500L
        private const val NETWORK_WAIT_RETRY_DELAY_MS = 1_500L
        private const val NETWORK_WAIT_MAX_RETRIES = 5
        private const val POST_START_INTERFACE_REASSERT_DELAY_MS = 500L
        private const val RUNTIME_RECOVERY_MIN_INTERVAL_MS = 1_000L
        private val activeServices = CopyOnWriteArraySet<RuntimeSession>()

        fun requestStopAll(source: String) {
            for (boxService in activeServices) {
                boxService.requestStop(source)
            }
        }

        fun requestStopForMode(mode: String, source: String): Boolean {
            var requested = false
            for (boxService in activeServices) {
                if (boxService.currentMode() == mode) {
                    requested = true
                    boxService.requestStop(source)
                }
            }
            HydraBoxDiagnostics.log(
                TAG,
                "requestStopForMode mode=$mode source=$source requested=$requested active=${activeServices.size}",
            )
            return requested
        }

        fun hasActiveRuntimeOwner(mode: String? = null): Boolean {
            return activeServices.any { service ->
                service.ownsActiveRuntime(mode)
            }
        }

        fun applyRuntimeStatus(state: String) {
            for (boxService in activeServices) {
                boxService.showForeground(state)
            }
        }

        /**
         * Flutter may be paused or its event sink detached while the VPN keeps
         * running. Keep the notification snapshot with the foreground service.
         */
        fun updateNotificationPresentation(arguments: Map<*, *>): Boolean {
            var updated = false
            for (boxService in activeServices) {
                updated = boxService.foregroundNotification.updatePresentation(arguments) || updated
            }
            return updated
        }

        fun publishNotificationTraffic(
            uplink: Long,
            downlink: Long,
            uplinkTotal: Long,
            downlinkTotal: Long,
            trafficAvailable: Boolean,
        ) {
            for (boxService in activeServices) {
                boxService.foregroundNotification.updateTraffic(
                    uplink = uplink,
                    downlink = downlink,
                    uplinkTotal = uplinkTotal,
                    downlinkTotal = downlinkTotal,
                    trafficAvailable = trafficAvailable,
                )
            }
        }

        fun publishNotificationUrlTestResult(
            tag: String?,
            delayMillis: Long,
            timeSeconds: Long,
            status: String?,
        ) {
            for (boxService in activeServices) {
                boxService.foregroundNotification.onUrlTestResult(
                    tag = tag,
                    delayMillis = delayMillis,
                    timeSeconds = timeSeconds,
                    status = status,
                )
            }
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val recoveryExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HydraBoxRecovery").apply { isDaemon = true }
    }
    private val recoveryGate = RuntimeRecoveryGate(RUNTIME_RECOVERY_MIN_INTERVAL_MS)
    private val foregroundNotification = HydraBoxForegroundNotification(
        service = service,
        notificationId = NOTIFICATION_ID,
    )

    @Volatile
    private var commandServer: CommandServer? = null

    @Volatile
    private var receiverRegistered = false

    @Volatile
    private var serviceGeneration = 0L

    @Volatile
    private var activeLaunch: LaunchTask? = null

    @Volatile
    private var destroyed = false

    @Volatile
    private var runningConfigHash: Int? = null

    init {
        activeServices += this
        val powerManager = service.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val interactive = powerManager?.isInteractive ?: true
        SingboxController.setScreenInteractive(interactive)
        foregroundNotification.setScreenInteractive(interactive)
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> updateDeviceIdleMode()
                Intent.ACTION_SCREEN_ON -> {
                    foregroundNotification.setScreenInteractive(true)
                    SingboxController.setScreenInteractive(true)
                    requestRuntimeRecovery("screen_on")
                }
                Intent.ACTION_SCREEN_OFF -> {
                    foregroundNotification.setScreenInteractive(false)
                    SingboxController.setScreenInteractive(false)
                }
                Intent.ACTION_USER_PRESENT -> requestRuntimeRecovery("user_present")
            }
        }
    }

    fun onStartCommand(intent: Intent?, startId: Int): Int {
        val action = intent?.action
        HydraBoxDiagnostics.log(TAG, "onStartCommand action=$action startId=$startId")
        if (action == null) {
            val mode = currentMode()
            if (shouldRestoreStickyStart(mode)) {
                // A service started with startForegroundService() must enter the
                // foreground before any queued native work. JNI cleanup/startup
                // can legitimately take several seconds during a VPN restart.
                showForeground("Connecting")
                Log.w(TAG, "restoring sticky restart mode=$mode")
                SingboxController.log(
                    "warning",
                    "sticky_restart_restore mode=$mode startId=$startId " +
                        "intent=${HydraBoxApplication.describeRuntimeIntent()}",
                )
                // переводится на команду в HB-RW-012B
                run("sticky_restart", currentCommandGeneration())
                return Service.START_STICKY
            }
            Log.w(TAG, "ignoring sticky restart without fresh runtime intent")
            HydraBoxDiagnostics.log(
                TAG,
                "ignoring sticky restart without fresh runtime intent mode=$mode " +
                    "intent=${HydraBoxApplication.describeRuntimeIntent()}",
            )
            close("sticky_null_intent", startId = startId)
            return Service.START_NOT_STICKY
        }
        var sticky = false
        when (action) {
            ACTION_START -> {
                showForeground("Connecting")
                sticky = true
                val generation = intent.commandGeneration(action) ?: return Service.START_NOT_STICKY
                run("action_start", generation)
            }
            ACTION_STOP -> {
                val reason = intent.getStringExtra(EXTRA_STOP_REASON)?.takeIf { it.isNotBlank() }
                    ?: "unspecified"
                HydraBoxApplication.clearRuntimeIntent()
                showForeground("Disconnecting")
                cancel()
                close("action_stop:$reason", startId = startId)
            }
            HydraBoxForegroundNotification.ACTION_REFRESH_LATENCY -> {
                val accepted = foregroundNotification.requestLatencyRefresh()
                HydraBoxDiagnostics.log(
                    TAG,
                    "notification_latency_refresh accepted=$accepted running=${SingboxController.running}",
                )
                return Service.START_STICKY
            }
            ACTION_RESTART_CORE -> {
                showForeground("Connecting")
                sticky = true
                val generation = intent.commandGeneration(action) ?: return Service.START_NOT_STICKY
                run("action_restart_core", generation)
            }
            ACTION_RELOAD -> {
                showForeground("Connecting")
                sticky = true
                val generation = intent.commandGeneration(action) ?: return Service.START_NOT_STICKY
                run("action_reload", generation)
            }
            else -> {
                Log.w(TAG, "ignoring unknown action=$action")
                HydraBoxDiagnostics.log(TAG, "ignoring unknown action=$action")
                close("unknown_action", startId = startId)
                return Service.START_NOT_STICKY
            }
        }
        return if (sticky) Service.START_STICKY else Service.START_NOT_STICKY
    }

    fun onDestroy() {
        if (destroyed) {
            return
        }
        destroyed = true
        HydraBoxDiagnostics.log(TAG, "onDestroy")
        activeServices -= this
        cancel()
        recoveryGate.reset()
        recoveryExecutor.shutdownNow()
        close("service_onDestroy", stopSelf = false)
        executor.shutdown()
    }

    fun requestStop(source: String) {
        cancel()
        close(source)
    }

    fun requestRuntimeRecovery(source: String) {
        val server = commandServer
        val ownsRuntime = ownsActiveRuntime()
        if (destroyed || !SingboxController.running || !ownsRuntime || server == null) {
            HydraBoxDiagnostics.log(
                TAG,
                "runtime recovery skipped source=$source destroyed=$destroyed " +
                    "running=${SingboxController.running} owner=$ownsRuntime server=${server != null}",
            )
            return
        }
        val now = SystemClock.elapsedRealtime()
        val accepted = recoveryGate.tryAcquire(now)
        if (!accepted) {
            HydraBoxDiagnostics.log(TAG, "runtime recovery coalesced source=$source")
            return
        }
        HydraBoxDiagnostics.log(
            TAG,
            "runtime recovery requested source=$source " +
                "current=${HydraBoxDefaultNetworkMonitor.describeCurrentState()}",
        )
        // Re-apply Android's physical upstream immediately. This path remains
        // owned by the foreground service and therefore does not depend on a
        // Flutter Activity or command-event subscription being attached.
        HydraBoxDefaultNetworkMonitor.start()
        HydraBoxDefaultNetworkMonitor.reassertDefaultInterface(
            "runtime_recovery_before_wake:$source",
        )

        try {
            recoveryExecutor.execute {
                if (
                    destroyed ||
                    commandServer !== server ||
                    !SingboxController.running ||
                    !ownsActiveRuntime()
                ) {
                    return@execute
                }
                runCatching {
                    // The platform interface callback owns router ResetNetwork
                    // for a real Network/interface change. Calling it again
                    // here duplicates that reset and used to close XHTTP
                    // permanently. Wake only resumes a paused runtime.
                    server.wake()
                }.onSuccess {
                    HydraBoxDiagnostics.log(
                        TAG,
                        "runtime recovery completed source=$source",
                    )
                    HydraBoxDefaultNetworkMonitor.reassertDefaultInterface(
                        "runtime_recovery_after_wake:$source",
                    )
                }.onFailure { error ->
                    HydraBoxDiagnostics.log(TAG, "runtime recovery wake failed source=$source", error)
                    SingboxController.log(
                        "error",
                        "runtime recovery wake failed source=$source error=${error.message}",
                    )
                }
            }
        } catch (_: RejectedExecutionException) {
            HydraBoxDiagnostics.log(TAG, "runtime recovery rejected source=$source destroyed=$destroyed")
        }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply {
            available = false
            enabled = false
        }

    override fun serviceReload() {
        // переводится на команду в HB-RW-012B
        run("handler_serviceReload", currentCommandGeneration())
    }

    override fun serviceStop() {
        HydraBoxDiagnostics.log(TAG, "serviceStop requested by libbox/platform")
        cancel()
        close("handler_serviceStop")
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) = Unit

    override fun writeDebugMessage(message: String?) {
        SingboxController.log("debug", message ?: "")
    }

    private fun currentMode(): String = if (service is HydraBoxVpnService) "vpn" else "proxy"

    private fun ownsActiveRuntime(mode: String? = null): Boolean {
        if (mode != null && mode.isNotBlank() && currentMode() != mode) {
            return false
        }
        val generation = serviceGeneration
        return generation != 0L &&
            generation == SingboxController.activeRuntimeGeneration &&
            commandServer != null
    }

    private fun currentConfigHash(): Int? =
        runCatching { HydraBoxApplication.configFile.readText().hashCode() }.getOrNull()

    private fun shouldRestoreStickyStart(mode: String): Boolean =
        HydraBoxApplication.isRuntimeIntentFresh(mode) &&
            HydraBoxApplication.configFile.exists() &&
            HydraBoxApplication.configFile.length() > 0L

    private fun currentCommandGeneration(): Long = CoreProcessIdentity.generation.get()

    private fun Intent.commandGeneration(action: String): Long? {
        val generation = getLongExtra(EXTRA_COMMAND_GENERATION, 0L)
        if (generation > 0L) return generation
        val message = "runtime start rejected action=$action commandGeneration=$generation"
        Log.w(TAG, message)
        HydraBoxDiagnostics.log(TAG, message)
        SingboxController.log("error", message)
        return null
    }

    private fun launchCurrent(stage: RuntimeSessionStage, launch: LaunchTask): Boolean =
        !destroyed && runtimeSessionOutcome(
            stage,
            launch.generation,
            currentCommandGeneration(),
            launch.cancelled.get(),
        ) == RuntimeSessionOutcome.CONTINUE

    private fun submitServiceTask(
        source: String,
        allowAfterDestroy: Boolean = false,
        task: () -> Unit,
    ): Boolean {
        if (destroyed && !allowAfterDestroy) {
            HydraBoxDiagnostics.log(TAG, "service task ignored after destroy source=$source")
            return false
        }
        return try {
            executor.execute(task)
            true
        } catch (error: RejectedExecutionException) {
            HydraBoxDiagnostics.log(TAG, "service task rejected source=$source", error)
            false
        }
    }

    private fun scheduleRetry(
        source: String,
        task: () -> Unit,
        delayMillis: Long,
    ): Thread? {
        if (destroyed) {
            return null
        }
        return Thread(
            {
                try {
                    Thread.sleep(delayMillis)
                    task()
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            },
            "RuntimeLaunchRetry",
        ).apply {
            isDaemon = true
            start()
        }
    }

    fun run(plan: String, generation: Long) {
        if (destroyed || generation <= 0L || generation != currentCommandGeneration()) {
            val message =
                "runtime start rejected plan=$plan commandGeneration=$generation current=${currentCommandGeneration()}"
            HydraBoxDiagnostics.log(
                TAG,
                message,
            )
            SingboxController.log("error", message)
            return
        }
        activeLaunch?.cancelled?.set(true)
        lateinit var task: LaunchTask
        val thread = Thread(
            { startInternal(plan, generation, task) },
            "RuntimeLaunch",
        ).apply { isDaemon = true }
        task = LaunchTask(generation, thread, AtomicBoolean())
        activeLaunch = task
        thread.start()
    }

    fun cancel() {
        activeLaunch?.cancelled?.set(true)
    }

    fun close(source: String, stopSelf: Boolean = true, startId: Int? = null) {
        lateinit var task: CloseTask
        val thread = Thread(
            {
                activeLaunch?.thread?.takeIf { it !== Thread.currentThread() }?.join(CLOSE_DEADLINE_MS)
                stopInternal(source, stopSelf, startId, cancelStarts = false)
            },
            "RuntimeClose",
        ).apply { isDaemon = true }
        task = CloseTask(serviceGeneration, thread, AtomicBoolean())
        thread.start()
    }

    private fun startInternal(source: String, generation: Long, task: LaunchTask) {
        if (!launchCurrent(RuntimeSessionStage.FOREGROUND, task)) {
            HydraBoxDiagnostics.log(TAG, "start ignored for stale commandGeneration=$generation source=$source")
            return
        }
        val mode = currentMode()
        HydraBoxApplication.writeRuntimeIntent(mode, source)
        val alreadyRunning =
            SingboxController.running && SingboxController.serviceMode == mode && commandServer != null
        if (alreadyRunning) {
            val configHash = currentConfigHash()
            if (configHash != null && runningConfigHash != null && configHash != runningConfigHash) {
                Log.i(
                    TAG,
                    "startInternal reloading source=$source mode=$mode configHash=$configHash runningConfigHash=$runningConfigHash",
                )
                HydraBoxDiagnostics.log(
                    TAG,
                    "startInternal reload requested source=$source mode=$mode configHash=$configHash runningConfigHash=$runningConfigHash",
                )
                startOrReloadInternal(generation, task = task)
                return
            }
            Log.i(TAG, "startInternal ignored source=$source already running mode=$mode")
            HydraBoxDiagnostics.log(
                TAG,
                "startInternal ignored source=$source already running mode=$mode " +
                    "current=${HydraBoxDefaultNetworkMonitor.describeCurrentState()}",
            )
            registerRuntimeReceiver()
            HydraBoxDefaultNetworkMonitor.start()
            requestRuntimeRecovery("existing_runtime:$source")
            showForeground("Connecting")
            HydraBoxQuickSettingsTileService.requestRefresh(service)
            return
        }
        startOrReloadInternal(generation, task = task)
    }

    private fun startOrReloadInternal(
        generation: Long,
        networkWaitAttempt: Int = 0,
        task: LaunchTask? = null,
    ) {
        val launch = task ?: return
        if (!launchCurrent(RuntimeSessionStage.FOREGROUND, launch)) {
            Log.i(TAG, "startOrReloadInternal ignored stale commandGeneration=$generation")
            HydraBoxDiagnostics.log(TAG, "startOrReloadInternal ignored stale commandGeneration=$generation")
            return
        }
        Log.i(TAG, "startOrReloadInternal begin service=${service.javaClass.simpleName}")
        val mode = currentMode()
        val startedAt = SystemClock.elapsedRealtime()
        HydraBoxDiagnostics.event(
            "START", "ep" to shortServiceId(CoreProcessIdentity.epoch), "cg" to CoreProcessIdentity.generation.get(),
            "rg" to SingboxController.activeRuntimeGeneration,
            "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("start").generation,
            "stage" to "foreground", "result" to "ok",
        )
        HydraBoxApplication.writeRuntimeIntent(mode, "start_or_reload")
        HydraBoxDiagnostics.log(
            TAG,
            "startOrReloadInternal begin service=${service.javaClass.simpleName} " +
                "current=${HydraBoxDefaultNetworkMonitor.describeCurrentState()}",
        )
        try {
            if (!launchCurrent(RuntimeSessionStage.NATIVE_SETUP, launch)) return
            NativeCoreEnvironment.ensureSetup()
            showForeground("Connecting")
        } catch (error: Throwable) {
            Log.e(TAG, "startOrReloadInternal setup failed", error)
            HydraBoxDiagnostics.log(TAG, "startOrReloadInternal setup failed", error)
            fail("Native service setup failed: ${error.message ?: error}")
            return
        }
        if (!launchCurrent(RuntimeSessionStage.NETWORK_WAIT, launch)) return
        registerRuntimeReceiver()
        HydraBoxDefaultNetworkMonitor.start()
        if (!HydraBoxDefaultNetworkMonitor.awaitUsableDefaultInterface(NETWORK_WAIT_TIMEOUT_MS)) {
            HydraBoxDiagnostics.event(
                "START", "ep" to shortServiceId(CoreProcessIdentity.epoch), "cg" to CoreProcessIdentity.generation.get(),
                "rg" to SingboxController.activeRuntimeGeneration,
                "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("network_wait").generation,
                "stage" to "network_wait", "result" to "fail",
                "elapsed_ms" to SystemClock.elapsedRealtime() - startedAt, "attempt" to networkWaitAttempt,
            )
            SingboxController.log(
                "warning",
                "network_interface_wait_timeout attempt=$networkWaitAttempt commandGeneration=$generation " +
                    "current=${HydraBoxDefaultNetworkMonitor.describeCurrentState()}",
            )
            if (networkWaitAttempt < NETWORK_WAIT_MAX_RETRIES) {
                showForeground("Waiting for network")
                scheduleRetry(
                    "network_wait",
                    {
                        if (launch.generation == currentCommandGeneration() && !launch.cancelled.get()) {
                            submitServiceTask("network_wait_retry") {
                                startOrReloadInternal(generation, networkWaitAttempt + 1, launch)
                            }
                        }
                    },
                    NETWORK_WAIT_RETRY_DELAY_MS,
                )
                SingboxController.log(
                    "info",
                    "service_start_retry_scheduled attempt=${networkWaitAttempt + 1} " +
                        "commandGeneration=$generation service=${service.javaClass.simpleName}",
                )
                return
            }
            fail("No usable network interface")
            return
        }
        SingboxController.log(
            "info",
            "network_interface_ready commandGeneration=$generation current=${HydraBoxDefaultNetworkMonitor.describeCurrentState()}",
        )
        HydraBoxDiagnostics.event(
            "START", "ep" to shortServiceId(CoreProcessIdentity.epoch), "cg" to CoreProcessIdentity.generation.get(),
            "rg" to SingboxController.activeRuntimeGeneration,
            "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("network_wait").generation,
            "stage" to "network_wait", "result" to "ok",
            "elapsed_ms" to SystemClock.elapsedRealtime() - startedAt, "attempt" to networkWaitAttempt,
        )
        if (!launchCurrent(RuntimeSessionStage.NETWORK_WAIT, launch)) {
            HydraBoxDiagnostics.log(TAG, "start cancelled after network wait commandGeneration=$generation")
            return
        }
        val config = runCatching { HydraBoxApplication.configFile.readText() }.getOrElse {
            Log.e(TAG, "failed to read config", it)
            fail("Failed to read config: ${it.message}")
            return
        }
        if (config.isBlank()) {
            Log.e(TAG, "generated config is empty")
            fail("Generated config is empty")
            return
        }
        val configHash = config.hashCode()
        val preparedRuntimeConfig = prepareRuntimeConfig(config)
        if (!launchCurrent(RuntimeSessionStage.COMMAND_SERVER, launch)) {
            HydraBoxDiagnostics.log(TAG, "start cancelled before command server commandGeneration=$generation")
            return
        }
        try {
            if (!launchCurrent(RuntimeSessionStage.COMMAND_SERVER, launch)) return
            val server = commandServer ?: createCommandServer()
            Log.i(TAG, "starting/reloading libbox service")
            HydraBoxDiagnostics.log(
                TAG,
                "starting/reloading libbox service current=${HydraBoxDefaultNetworkMonitor.describeCurrentState()}",
            )
            val startedAt = System.currentTimeMillis()
            if (!launchCurrent(RuntimeSessionStage.LIBBOX_START, launch)) return
            server.startOrReloadService(
                preparedRuntimeConfig.config,
                preparedRuntimeConfig.overrideOptions,
            )
            if (!launchCurrent(RuntimeSessionStage.COMMAND_CLIENT, launch)) return
            val elapsedMs = System.currentTimeMillis() - startedAt
            HydraBoxDiagnostics.event(
                "START", "ep" to shortServiceId(CoreProcessIdentity.epoch), "cg" to CoreProcessIdentity.generation.get(),
                "rg" to SingboxController.activeRuntimeGeneration,
                "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("libbox_start").generation,
                "stage" to "libbox_start", "result" to "ok", "elapsed_ms" to elapsedMs,
            )
            HydraBoxDefaultNetworkMonitor.reassertDefaultInterface("after_start_or_reload_service")
            scheduleRetry(
                "post_start_interface_reassert",
                {
                    if (launch.generation == currentCommandGeneration() && !launch.cancelled.get() && commandServer != null) {
                        HydraBoxDefaultNetworkMonitor.reassertDefaultInterface(
                            "after_start_or_reload_service_delayed",
                        )
                    }
                },
                POST_START_INTERFACE_REASSERT_DELAY_MS,
            )
            showForeground("Connecting")
            Log.i(TAG, "libbox service started mode=$mode")
            HydraBoxDiagnostics.log(
                TAG,
                "libbox service started mode=$mode current=${HydraBoxDefaultNetworkMonitor.describeCurrentState()}",
            )
            serviceGeneration = SingboxController.markServiceStarted(mode)
            runningConfigHash = configHash
            SingboxController.log(
                "info",
                "VPN service running mode=$mode generation=$serviceGeneration hasCommandServer=${commandServer != null}",
            )
            HydraBoxQuickSettingsTileService.requestRefresh(service)
        } catch (error: Throwable) {
            Log.e(TAG, "startOrReloadInternal failed", error)
            HydraBoxDiagnostics.log(TAG, "startOrReloadInternal failed", error)
            fail(error.message ?: error.toString())
        }
    }

    private fun stopInternal(
        source: String,
        stopSelf: Boolean = true,
        startId: Int? = null,
        cancelStarts: Boolean = true,
    ) {
        val generation = serviceGeneration
        val activeGeneration = SingboxController.activeRuntimeGeneration
        val server = commandServer
        val staleRuntimeStop = generation != 0L && generation != activeGeneration
        val ownsRuntime = generation != 0L && !staleRuntimeStop
        val hasLocalRuntime = generation != 0L || server != null
        val shouldStopRuntimeState = ownsRuntime || (cancelStarts && !SingboxController.running)
        if (cancelStarts && ownsRuntime) {
            cancel()
        }
        Log.i(TAG, "stopInternal source=$source service=${service.javaClass.simpleName}")
        SingboxController.log(
            "warning",
            "VPN service stop requested source=$source service=${service.javaClass.simpleName} " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                "generation=$generation activeGeneration=$activeGeneration " +
                "hasCommandServer=${server != null} ownsRuntime=$ownsRuntime",
        )
        HydraBoxDiagnostics.log(
            TAG,
            "stopInternal source=$source service=${service.javaClass.simpleName} " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                "generation=$generation activeGeneration=$activeGeneration " +
                "hasCommandServer=${server != null} ownsRuntime=$ownsRuntime",
        )
        if (!hasLocalRuntime && SingboxController.running) {
            HydraBoxDiagnostics.log(
                TAG,
                "stale empty stop ignored source=$source active=$activeGeneration",
            )
            if (stopSelf) {
                if (startId != null) {
                    service.stopSelfResult(startId)
                } else {
                    service.stopSelf()
                }
            }
            return
        }
        unregisterRuntimeReceiver()

        if (shouldStopRuntimeState) {
            HydraBoxDefaultNetworkMonitor.stop()
        } else {
            HydraBoxDiagnostics.log(
                TAG,
                "network monitor stop skipped source=$source " +
                    "generation=$generation active=$activeGeneration",
            )
        }

        var cleanupComplete = true

        // Сначала отключаем активный CommandClient.
        if (shouldStopRuntimeState) {
            val clientDisconnected = SingboxController.disconnectClientBlocking(
                timeoutMs = CLEANUP_STEP_TIMEOUT_MS,
            )

            if (!clientDisconnected) {
                HydraBoxDiagnostics.log(
                    TAG,
                    "command client disconnect timed out source=$source",
                )
            }

            cleanupComplete = clientDisconnected && cleanupComplete
        }

        // Затем закрываем native runtime и CommandServer.
        if (server != null) {
            cleanupComplete = runCatching { server.closeService() }.onFailure {
                HydraBoxDiagnostics.log(TAG, "closeService failed source=$source", it)
            }.isSuccess && cleanupComplete

            cleanupComplete = runCatching { server.close() }.onFailure {
                HydraBoxDiagnostics.log(TAG, "close command server failed source=$source", it)
            }.isSuccess && cleanupComplete
        }

        if (!cleanupComplete) {
            SingboxController.log(
                "error",
                "VPN service cleanup incomplete source=$source " +
                    "service=${service.javaClass.simpleName}",
            )
            HydraBoxDiagnostics.log(
                TAG,
                "runtime stop not acknowledged source=$source " +
                    "generation=$generation activeGeneration=$activeGeneration " +
                    "cleanupComplete=false",
            )

            showForeground("Disconnecting")
            return
        }

        commandServer = null
        runningConfigHash = null
        serviceGeneration = 0L

        if (shouldStopRuntimeState) {
            SingboxController.markServiceStopped(generation, source)
            HydraBoxApplication.clearRuntimeIntent()
            foregroundNotification.clearSavedPresentation()
            HydraBoxQuickSettingsTileService.requestRefresh(service)
        } else {
            HydraBoxDiagnostics.log(
                TAG,
                "runtime state stop skipped source=$source " +
                    "generation=$generation active=$activeGeneration",
            )
        }

        SingboxController.log(
            "warning",
            "VPN service stopped source=$source " +
                "service=${service.javaClass.simpleName}",
        )
        HydraBoxDiagnostics.event(
            "STOP", "ep" to shortServiceId(CoreProcessIdentity.epoch), "cg" to CoreProcessIdentity.generation.get(),
            "rg" to SingboxController.activeRuntimeGeneration,
            "ng" to HydraBoxDefaultNetworkMonitor.currentInterfaceState("stop_released").generation,
            "stage" to "released", "elapsed_ms" to 0,
        )

        runCatching {
            service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
        }

        if (stopSelf) {
            if (startId != null) {
                val stopped = service.stopSelfResult(startId)
                HydraBoxDiagnostics.log(
                    TAG,
                    "stopSelfResult source=$source startId=$startId result=$stopped",
                )
            } else {
                service.stopSelf()
                HydraBoxDiagnostics.log(TAG, "stopSelf source=$source")
            }
        }
    }

    private fun createCommandServer(): CommandServer {
        val server = Libbox.newCommandServer(this, platformInterface)
        try {
            Log.i(TAG, "creating new command server")
            HydraBoxDiagnostics.log(TAG, "creating new command server")
            server.start()
            commandServer = server
            return server
        } catch (error: Throwable) {
            HydraBoxDiagnostics.log(TAG, "command server start failed after allocation; closing", error)
            runCatching { server.closeService() }
            runCatching { server.close() }
            throw error
        }
    }

    private fun fail(message: String) {
        Log.e(TAG, "fail: $message")
        HydraBoxDiagnostics.log(TAG, "fail: $message")
        SingboxController.log("error", message)
        SingboxController.setRunning(false, error = message)
        stopInternal("fail")
    }

    private fun showForeground(status: String) {
        val notification = foregroundNotification.buildForForeground(status)
        service.startForeground(NOTIFICATION_ID, notification)
    }

    private data class PreparedRuntimeConfig(
        val config: String,
        val overrideOptions: OverrideOptions,
    )

    private data class LaunchTask(
        val generation: Long,
        val thread: Thread,
        val cancelled: AtomicBoolean,
    )

    private data class CloseTask(
        val generation: Long,
        val thread: Thread,
        val cancelled: AtomicBoolean,
    )

    private class ListStringIterator(
        values: List<String>,
    ) : io.nekohasekai.libbox.StringIterator {
        private val items = values.toList()
        private var index = 0

        override fun hasNext(): Boolean = index < items.size

        override fun len(): Int = items.size

        override fun next(): String = items[index++]
    }

    private fun prepareRuntimeConfig(config: String): PreparedRuntimeConfig {
        val overrideOptions = OverrideOptions()
        return runCatching {
            val root = JSONObject(config)
            val splitIncludePackages = mutableListOf<String>()
            val splitExcludePackages = mutableListOf<String>()
            val inbounds = root.optJSONArray("inbounds")
            val outbounds = root.optJSONArray("outbounds")
            var changed = false
            for (index in 0 until (inbounds?.length() ?: 0)) {
                val inbound = inbounds?.optJSONObject(index) ?: continue
                if (inbound.optString("type") != "tun") {
                    continue
                }
                splitIncludePackages += readPackageList(inbound.optJSONArray("include_package"))
                splitExcludePackages += readPackageList(inbound.optJSONArray("exclude_package"))
                if (inbound.has("include_package")) {
                    inbound.remove("include_package")
                    changed = true
                }
                if (inbound.has("exclude_package")) {
                    inbound.remove("exclude_package")
                    changed = true
                }
            }
            for (index in 0 until (outbounds?.length() ?: 0)) {
                val outbound = outbounds?.optJSONObject(index) ?: continue
                if (outbound.optString("type") == "vless" && outbound.has("packet_encoding")) {
                    val packetEncoding = outbound.opt("packet_encoding")
                    val packetEncodingValue = packetEncoding as? String
                    if (packetEncodingValue !in setOf("", "packetaddr", "xudp")) {
                        val tag = outbound.optString("tag", "#$index")
                        Log.w(
                            TAG,
                            "dropping invalid vless packet_encoding tag=$tag value=$packetEncoding",
                        )
                        HydraBoxDiagnostics.log(
                            TAG,
                            "dropping invalid vless packet_encoding tag=$tag value=$packetEncoding",
                        )
                        outbound.remove("packet_encoding")
                        changed = true
                    }
                }
            }
            val includePackages = normalizePackageList(splitIncludePackages)
            val excludePackages = normalizePackageList(splitExcludePackages)
            requireExclusiveSplitTunnelPackages(includePackages, excludePackages)
            if (includePackages.isNotEmpty()) {
                overrideOptions.includePackage = ListStringIterator(includePackages)
            }
            if (excludePackages.isNotEmpty()) {
                overrideOptions.excludePackage = ListStringIterator(excludePackages)
            }
            if (splitIncludePackages.isNotEmpty() || splitExcludePackages.isNotEmpty()) {
                HydraBoxDiagnostics.log(
                    TAG,
                    "split packages moved to OverrideOptions include=${includePackages.size} " +
                        "exclude=${excludePackages.size} rawInclude=${splitIncludePackages.size} " +
                        "rawExclude=${splitExcludePackages.size}",
                )
            }
            val preparedConfig = if (changed) {
                root.toString()
            } else {
                config
            }
            PreparedRuntimeConfig(preparedConfig, overrideOptions)
        }.getOrElse { error ->
            if (error is SplitTunnelConfigurationException) {
                throw error
            }
            HydraBoxDiagnostics.log(TAG, "prepareConfig parse failed", error)
            PreparedRuntimeConfig(config, overrideOptions)
        }
    }

    private fun readPackageList(array: org.json.JSONArray?): List<String> {
        if (array == null) {
            return emptyList()
        }
        val result = mutableListOf<String>()
        for (index in 0 until array.length()) {
            val value = array.optString(index, "").trim()
            if (value.isNotEmpty()) {
                result += value
            }
        }
        return result
    }

    private fun normalizePackageList(values: List<String>): List<String> {
        val seen = linkedSetOf<String>()
        for (value in values) {
            val packageName = value.trim()
            if (
                packageName.isNotEmpty() &&
                packageName != service.packageName &&
                isAndroidPackageName(packageName)
            ) {
                seen += packageName
            }
            if (seen.size >= MAX_SPLIT_TUNNEL_PACKAGE_COUNT) {
                break
            }
        }
        return seen.toList()
    }

    private fun isAndroidPackageName(value: String): Boolean =
        value.length <= 255 &&
            Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$").matches(value)

    private fun registerRuntimeReceiver() {
        if (receiverRegistered) {
            return
        }
        val filter = IntentFilter().apply {
            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                service.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                service.registerReceiver(receiver, filter)
            }
            receiverRegistered = true
            HydraBoxDiagnostics.log(TAG, "runtime receiver registered")
            updateDeviceIdleMode()
        }.onFailure {
            HydraBoxDiagnostics.log(TAG, "runtime receiver registration failed", it)
        }
    }

    private fun unregisterRuntimeReceiver() {
        if (!receiverRegistered) {
            return
        }
        runCatching {
            service.unregisterReceiver(receiver)
            receiverRegistered = false
            HydraBoxDiagnostics.log(TAG, "runtime receiver unregistered")
        }.onFailure {
            receiverRegistered = false
            HydraBoxDiagnostics.log(TAG, "runtime receiver unregister failed", it)
        }
    }

    private fun updateDeviceIdleMode() {
        val powerManager = service.getSystemService(Context.POWER_SERVICE) as PowerManager
        val idle = powerManager.isDeviceIdleMode
        HydraBoxDiagnostics.log(TAG, "device idle mode changed idle=$idle")
        if (idle) {
            SingboxController.log(
                "info",
                "Android device idle/doze entered; keeping VPN core active",
            )
            return
        }
        SingboxController.log(
            "info",
            "core wake requested by Android device idle exit",
        )
        requestRuntimeRecovery("device_idle_exit")
    }
}
