package com.etonify.meow_client.singbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SystemProxyStatus
import com.etonify.meow_client.MeowApplication
import com.etonify.meow_client.MeowQuickSettingsTileService
import com.etonify.meow_client.R
import org.json.JSONObject
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class MeowBoxService(
    private val service: Service,
    private val platformInterface: PlatformInterface,
) : CommandServerHandler {
    companion object {
        private const val TAG = "MeowBoxService"
        const val ACTION_START = "com.etonify.meow_client.singbox.START"
        const val ACTION_STOP = "com.etonify.meow_client.singbox.STOP"
        const val ACTION_RELOAD = "com.etonify.meow_client.singbox.RELOAD"
        const val ACTION_RESTART_CORE = "com.etonify.meow_client.singbox.RESTART_CORE"
        const val EXTRA_STOP_REASON = "stop_reason"
        private const val NOTIFICATION_CHANNEL_ID = "meow_singbox"
        private const val NOTIFICATION_ID = 42
        private const val CLEANUP_STEP_TIMEOUT_MS = 1_200L
        private const val NETWORK_WAIT_TIMEOUT_MS = 2_500L
        private const val NETWORK_WAIT_RETRY_DELAY_MS = 1_500L
        private const val NETWORK_WAIT_MAX_RETRIES = 5
        private const val POST_START_INTERFACE_REASSERT_DELAY_MS = 500L
        private val activeServices = CopyOnWriteArraySet<MeowBoxService>()

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
            MeowDiagnostics.log(
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
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val retryExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "MeowBoxStartRetry").apply { isDaemon = true }
    }

    @Volatile
    private var commandServer: CommandServer? = null

    @Volatile
    private var receiverRegistered = false

    @Volatile
    private var serviceGeneration = 0L

    private val startRequestGeneration = AtomicLong(0L)

    @Volatile
    private var pendingStartRetry: ScheduledFuture<*>? = null

    @Volatile
    private var destroyed = false

    @Volatile
    private var runningConfigHash: Int? = null

    init {
        activeServices += this
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        updateDeviceIdleMode()
                    }
                }
            }
        }
    }

    fun onStartCommand(intent: Intent?, startId: Int): Int {
        val action = intent?.action
        MeowDiagnostics.log(TAG, "onStartCommand action=$action startId=$startId")
        if (action == null) {
            val mode = currentMode()
            if (shouldRestoreStickyStart(mode)) {
                Log.w(TAG, "restoring sticky restart mode=$mode")
                SingboxController.log(
                    "warning",
                    "sticky_restart_restore mode=$mode startId=$startId " +
                        "intent=${MeowApplication.describeRuntimeIntent()} " +
                        "serviceState=${MeowApplication.describeRecordedServiceState()}",
                )
                val token = nextStartToken("sticky_restart")
                submitServiceTask("sticky_restart") { startInternal("sticky_restart", token) }
                return Service.START_STICKY
            }
            Log.w(TAG, "ignoring sticky restart without fresh runtime intent")
            MeowDiagnostics.log(
                TAG,
                "ignoring sticky restart without fresh runtime intent mode=$mode " +
                    "intent=${MeowApplication.describeRuntimeIntent()}",
            )
            submitServiceTask("sticky_null_intent") {
                stopInternal("sticky_null_intent", startId = startId)
            }
            return Service.START_NOT_STICKY
        }
        var sticky = false
        when (action) {
            ACTION_START -> {
                sticky = true
                val token = nextStartToken("action_start")
                submitServiceTask("action_start") { startInternal("action_start", token) }
            }
            ACTION_STOP -> {
                val reason = intent.getStringExtra(EXTRA_STOP_REASON)?.takeIf { it.isNotBlank() }
                    ?: "unspecified"
                MeowApplication.clearRuntimeIntent()
                submitServiceTask("action_stop:$reason") {
                    stopInternal("action_stop:$reason", startId = startId)
                }
            }
            ACTION_RESTART_CORE -> {
                sticky = true
                val token = nextStartToken("action_restart_core")
                submitServiceTask("action_restart_core") {
                    restartCoreInternal("action_restart_core", token)
                }
            }
            ACTION_RELOAD -> {
                sticky = true
                val token = nextStartToken("action_reload")
                submitServiceTask("action_reload") { startOrReloadInternal(token) }
            }
            else -> {
                Log.w(TAG, "ignoring unknown action=$action")
                MeowDiagnostics.log(TAG, "ignoring unknown action=$action")
                submitServiceTask("unknown_action") {
                    stopInternal("unknown_action", startId = startId)
                }
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
        MeowDiagnostics.log(TAG, "onDestroy")
        activeServices -= this
        startRequestGeneration.set(Long.MIN_VALUE)
        cancelPendingStartRetry("service_onDestroy")
        retryExecutor.shutdownNow()
        submitServiceTask("service_onDestroy", allowAfterDestroy = true) {
            stopInternal("service_onDestroy", stopSelf = false, cancelStarts = false)
        }
        executor.shutdown()
    }

    fun requestStop(source: String) {
        submitServiceTask("requestStop:$source") { stopInternal(source) }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply {
            available = false
            enabled = false
        }

    override fun serviceReload() {
        val token = nextStartToken("handler_serviceReload")
        submitServiceTask("handler_serviceReload") { startOrReloadInternal(token) }
    }

    override fun serviceStop() {
        MeowDiagnostics.log(TAG, "serviceStop requested by libbox/platform")
        submitServiceTask("handler_serviceStop") { stopInternal("handler_serviceStop") }
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) = Unit

    override fun triggerNativeCrash() {
        Thread {
            Thread.sleep(200)
            throw RuntimeException("debug native crash")
        }.start()
    }

    override fun writeDebugMessage(message: String?) {
        SingboxController.log("debug", message ?: "")
    }

    private fun currentMode(): String = if (service is MeowVpnService) "vpn" else "proxy"

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
        runCatching { MeowApplication.configFile.readText().hashCode() }.getOrNull()

    private fun shouldRestoreStickyStart(mode: String): Boolean =
        MeowApplication.isRuntimeIntentFresh(mode) &&
            MeowApplication.configFile.exists() &&
            MeowApplication.configFile.length() > 0L

    private fun nextStartToken(reason: String): Long {
        if (destroyed) {
            MeowDiagnostics.log(TAG, "start token ignored after destroy reason=$reason")
            return Long.MIN_VALUE
        }
        val token = SingboxController.nextStartToken("${service.javaClass.simpleName}:$reason")
        startRequestGeneration.set(token)
        return token
    }

    private fun cancelStartRequests(reason: String): Long {
        val token = SingboxController.cancelStartTokens("${service.javaClass.simpleName}:$reason")
        startRequestGeneration.set(token)
        cancelPendingStartRetry(reason)
        return token
    }

    private fun startTokenCurrent(token: Long): Boolean =
        !destroyed &&
            startRequestGeneration.get() == token &&
            SingboxController.isStartTokenCurrent(token)

    private fun cancelPendingStartRetry(reason: String) {
        val pending = pendingStartRetry ?: return
        pendingStartRetry = null
        if (pending.cancel(false)) {
            SingboxController.log(
                "info",
                "service_start_retry_cancelled reason=$reason service=${service.javaClass.simpleName}",
            )
        }
    }

    private fun submitServiceTask(
        source: String,
        allowAfterDestroy: Boolean = false,
        task: () -> Unit,
    ): Boolean {
        if (destroyed && !allowAfterDestroy) {
            MeowDiagnostics.log(TAG, "service task ignored after destroy source=$source")
            return false
        }
        return try {
            executor.execute(task)
            true
        } catch (error: RejectedExecutionException) {
            MeowDiagnostics.log(TAG, "service task rejected source=$source", error)
            false
        }
    }

    private fun scheduleRetry(
        source: String,
        task: () -> Unit,
        delayMillis: Long,
    ): ScheduledFuture<*>? {
        if (destroyed) {
            return null
        }
        return try {
            retryExecutor.schedule(task, delayMillis, TimeUnit.MILLISECONDS)
        } catch (error: RejectedExecutionException) {
            MeowDiagnostics.log(TAG, "retry task rejected source=$source", error)
            null
        }
    }

    private fun startInternal(source: String, token: Long) {
        if (!startTokenCurrent(token)) {
            MeowDiagnostics.log(TAG, "start ignored for stale token=$token source=$source")
            return
        }
        val mode = currentMode()
        MeowApplication.writeRuntimeIntent(mode, source)
        val alreadyRunning =
            SingboxController.running && SingboxController.serviceMode == mode && commandServer != null
        if (alreadyRunning) {
            val configHash = currentConfigHash()
            if (configHash != null && runningConfigHash != null && configHash != runningConfigHash) {
                Log.i(
                    TAG,
                    "startInternal reloading source=$source mode=$mode configHash=$configHash runningConfigHash=$runningConfigHash",
                )
                MeowDiagnostics.log(
                    TAG,
                    "startInternal reload requested source=$source mode=$mode configHash=$configHash runningConfigHash=$runningConfigHash",
                )
                startOrReloadInternal(token)
                return
            }
            Log.i(TAG, "startInternal ignored source=$source already running mode=$mode")
            MeowDiagnostics.log(
                TAG,
                "startInternal ignored source=$source already running mode=$mode " +
                    "current=${MeowDefaultNetworkMonitor.describeCurrentState()}",
            )
            showForeground("Connected")
            MeowApplication.writeServiceState(mode)
            MeowQuickSettingsTileService.requestRefresh(service)
            return
        }
        startOrReloadInternal(token)
    }

    private fun startOrReloadInternal(
        token: Long = nextStartToken("startOrReloadInternal"),
        networkWaitAttempt: Int = 0,
    ) {
        if (!startTokenCurrent(token)) {
            Log.i(TAG, "startOrReloadInternal ignored stale token=$token")
            MeowDiagnostics.log(TAG, "startOrReloadInternal ignored stale token=$token")
            return
        }
        Log.i(TAG, "startOrReloadInternal begin service=${service.javaClass.simpleName}")
        val mode = currentMode()
        MeowApplication.writeRuntimeIntent(mode, "start_or_reload")
        SingboxController.log(
            "info",
            "native_start_marker phase=begin service=${service.javaClass.simpleName} " +
                "mode=$mode token=$token attempt=$networkWaitAttempt pid=${android.os.Process.myPid()} " +
                "intent=${MeowApplication.describeRuntimeIntent()} " +
                "serviceState=${MeowApplication.describeRecordedServiceState()}",
        )
        MeowDiagnostics.log(
            TAG,
            "startOrReloadInternal begin service=${service.javaClass.simpleName} " +
                "current=${MeowDefaultNetworkMonitor.describeCurrentState()}",
        )
        try {
            SingboxController.log(
                "info",
                "native_start_marker phase=before_libbox_setup memoryLimit=${MeowApplication.memoryLimitEnabled}",
            )
            MeowApplication.ensureLibboxSetup()
            SingboxController.log("info", "native_start_marker phase=after_libbox_setup")
            showForeground("Starting")
            SingboxController.log("info", "native_start_marker phase=foreground_starting")
        } catch (error: Throwable) {
            Log.e(TAG, "startOrReloadInternal setup failed", error)
            MeowDiagnostics.log(TAG, "startOrReloadInternal setup failed", error)
            fail("Native service setup failed: ${error.message ?: error}")
            return
        }
        registerRuntimeReceiver()
        MeowDefaultNetworkMonitor.start()
        if (!MeowDefaultNetworkMonitor.awaitUsableDefaultInterface(NETWORK_WAIT_TIMEOUT_MS)) {
            SingboxController.log(
                "warning",
                "network_interface_wait_timeout attempt=$networkWaitAttempt token=$token " +
                    "current=${MeowDefaultNetworkMonitor.describeCurrentState()}",
            )
            if (networkWaitAttempt < NETWORK_WAIT_MAX_RETRIES) {
                showForeground("Waiting for network")
                cancelPendingStartRetry("replace_network_wait_retry")
                pendingStartRetry = scheduleRetry(
                    "network_wait",
                    {
                        if (startTokenCurrent(token)) {
                            submitServiceTask("network_wait_retry") {
                                startOrReloadInternal(token, networkWaitAttempt + 1)
                            }
                        }
                    },
                    NETWORK_WAIT_RETRY_DELAY_MS,
                )
                SingboxController.log(
                    "info",
                    "service_start_retry_scheduled attempt=${networkWaitAttempt + 1} " +
                        "token=$token service=${service.javaClass.simpleName}",
                )
                return
            }
            fail("No usable network interface")
            return
        }
        SingboxController.log(
            "info",
            "network_interface_ready token=$token current=${MeowDefaultNetworkMonitor.describeCurrentState()}",
        )
        if (!startTokenCurrent(token)) {
            MeowDiagnostics.log(TAG, "start cancelled after network wait token=$token")
            return
        }
        val config = runCatching { MeowApplication.configFile.readText() }.getOrElse {
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
        if (!startTokenCurrent(token)) {
            MeowDiagnostics.log(TAG, "start cancelled before command server token=$token")
            return
        }
        try {
            SingboxController.log(
                "info",
                "native_start_marker phase=before_command_server configChars=${preparedRuntimeConfig.config.length} " +
                    "configHash=$configHash splitMode=$mode",
            )
            val server = commandServer ?: createCommandServer()
            Log.i(TAG, "starting/reloading libbox service")
            SingboxController.log(
                "info",
                "native_start_marker phase=before_start_or_reload_service hasCommandServer=${commandServer != null}",
            )
            MeowDiagnostics.log(
                TAG,
                "starting/reloading libbox service current=${MeowDefaultNetworkMonitor.describeCurrentState()}",
            )
            val startedAt = System.currentTimeMillis()
            server.startOrReloadService(
                preparedRuntimeConfig.config,
                preparedRuntimeConfig.overrideOptions,
            )
            val elapsedMs = System.currentTimeMillis() - startedAt
            SingboxController.log(
                "info",
                "native_start_marker phase=after_start_or_reload_service " +
                    "tun_fd_ownership owner=libbox service=${service.javaClass.simpleName} " +
                    "startElapsedMs=$elapsedMs",
            )
            MeowDefaultNetworkMonitor.reassertDefaultInterface("after_start_or_reload_service")
            scheduleRetry(
                "post_start_interface_reassert",
                {
                    if (startTokenCurrent(token) && commandServer != null) {
                        MeowDefaultNetworkMonitor.reassertDefaultInterface(
                            "after_start_or_reload_service_delayed",
                        )
                    }
                },
                POST_START_INTERFACE_REASSERT_DELAY_MS,
            )
            showForeground("Connected")
            MeowApplication.writeServiceState(mode)
            Log.i(TAG, "libbox service started mode=$mode")
            MeowDiagnostics.log(
                TAG,
                "libbox service started mode=$mode current=${MeowDefaultNetworkMonitor.describeCurrentState()}",
            )
            serviceGeneration = SingboxController.markServiceStarted(mode)
            runningConfigHash = configHash
            SingboxController.log(
                "info",
                "VPN service running mode=$mode generation=$serviceGeneration hasCommandServer=${commandServer != null}",
            )
            cancelPendingStartRetry("start_success")
            MeowQuickSettingsTileService.requestRefresh(service)
        } catch (error: Throwable) {
            Log.e(TAG, "startOrReloadInternal failed", error)
            MeowDiagnostics.log(TAG, "startOrReloadInternal failed", error)
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
        val shouldCancelStartRequests = cancelStarts && ownsRuntime
        val shouldStopRuntimeState = ownsRuntime || (cancelStarts && !SingboxController.running)
        if (shouldCancelStartRequests) {
            cancelStartRequests("stop:$source")
        } else {
            cancelPendingStartRetry("stop:$source")
        }
        Log.i(TAG, "stopInternal source=$source service=${service.javaClass.simpleName}")
        SingboxController.log(
            "warning",
            "VPN service stop requested source=$source service=${service.javaClass.simpleName} " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                "generation=$generation activeGeneration=$activeGeneration " +
                "hasCommandServer=${server != null} ownsRuntime=$ownsRuntime",
        )
        MeowDiagnostics.log(
            TAG,
            "stopInternal source=$source service=${service.javaClass.simpleName} " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                "generation=$generation activeGeneration=$activeGeneration " +
                "hasCommandServer=${server != null} ownsRuntime=$ownsRuntime",
        )
        if (!hasLocalRuntime && SingboxController.running) {
            MeowDiagnostics.log(
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
        commandServer = null
        unregisterRuntimeReceiver()
        if (shouldStopRuntimeState) {
            MeowDefaultNetworkMonitor.stop()
        } else {
            MeowDiagnostics.log(
                TAG,
                "network monitor stop skipped source=$source generation=$generation active=$activeGeneration",
            )
        }
        if (server != null) {
            runCleanupStep("closeService source=$source") {
                server.closeService()
            }
            if (shouldStopRuntimeState) {
                runCleanupStep("disconnect command client source=$source") {
                    SingboxController.disconnectClientBlocking()
                }
            } else {
                MeowDiagnostics.log(
                    TAG,
                    "command client disconnect skipped source=$source generation=$generation active=$activeGeneration",
                )
            }
            runCleanupStep("close command server source=$source") {
                server.close()
            }
        } else {
            if (shouldStopRuntimeState) {
                runCleanupStep("disconnect command client source=$source") {
                    SingboxController.disconnectClientBlocking()
                }
            } else {
                MeowDiagnostics.log(
                    TAG,
                    "command client disconnect skipped source=$source generation=$generation active=$activeGeneration",
                )
            }
        }
        runningConfigHash = null
        serviceGeneration = 0L
        if (shouldStopRuntimeState) {
            SingboxController.markServiceStopped(generation, source)
            MeowApplication.clearServiceState()
            MeowApplication.clearRuntimeIntent()
            MeowQuickSettingsTileService.requestRefresh(service)
        } else {
            MeowDiagnostics.log(
                TAG,
                "runtime state stop skipped source=$source generation=$generation active=$activeGeneration",
            )
        }
        SingboxController.log(
            "warning",
            "VPN service stopped source=$source service=${service.javaClass.simpleName}",
        )
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                service.stopForeground(true)
            }
        }
        if (stopSelf) {
            if (startId != null) {
                val stopped = service.stopSelfResult(startId)
                MeowDiagnostics.log(TAG, "stopSelfResult source=$source startId=$startId result=$stopped")
            } else {
                service.stopSelf()
                MeowDiagnostics.log(TAG, "stopSelf source=$source")
            }
        }
    }

    private fun restartCoreInternal(source: String, token: Long = nextStartToken("restartCoreInternal:$source")) {
        if (!startTokenCurrent(token)) {
            MeowDiagnostics.log(TAG, "core restart ignored for stale token=$token source=$source")
            return
        }
        Log.i(TAG, "restartCoreInternal source=$source service=${service.javaClass.simpleName}")
        MeowDiagnostics.log(
            TAG,
            "restartCoreInternal source=$source service=${service.javaClass.simpleName} " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                "hasCommandServer=${commandServer != null}",
        )
        runCatching { commandServer?.closeService() }.onFailure {
            MeowDiagnostics.log(TAG, "restartCoreInternal closeService failed source=$source", it)
        }
        runningConfigHash = null
        startOrReloadInternal(token)
    }

    private fun createCommandServer(): CommandServer {
        val server = Libbox.newCommandServer(this, platformInterface)
        try {
            Log.i(TAG, "creating new command server")
            MeowDiagnostics.log(TAG, "creating new command server")
            server.start()
            commandServer = server
            return server
        } catch (error: Throwable) {
            MeowDiagnostics.log(TAG, "command server start failed after allocation; closing", error)
            runCatching { server.closeService() }
            runCatching { server.close() }
            throw error
        }
    }

    private fun runCleanupStep(label: String, block: () -> Unit) {
        var failure: Throwable? = null
        val threadName = "MeowBoxCleanup-${label.take(32).replace(' ', '_')}"
        val thread = Thread(
            {
                try {
                    block()
                } catch (error: Throwable) {
                    failure = error
                }
            },
            threadName,
        ).apply {
            isDaemon = true
            start()
        }
        try {
            thread.join(CLEANUP_STEP_TIMEOUT_MS)
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            MeowDiagnostics.log(TAG, "$label interrupted during cleanup", error)
            return
        }
        if (thread.isAlive) {
            MeowDiagnostics.log(
                TAG,
                "$label timed out after ${CLEANUP_STEP_TIMEOUT_MS}ms; continuing service stop",
            )
            thread.interrupt()
            return
        }
        failure?.let {
            MeowDiagnostics.log(TAG, "$label failed during cleanup", it)
        }
    }

    private fun fail(message: String) {
        Log.e(TAG, "fail: $message")
        MeowDiagnostics.log(TAG, "fail: $message")
        SingboxController.log("error", message)
        SingboxController.setRunning(false, error = message)
        stopInternal("fail")
    }

    private fun showForeground(status: String) {
        val manager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Etonify sing-box",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(service, NOTIFICATION_CHANNEL_ID)
        } else {
            Notification.Builder(service)
        }.setContentTitle("Etonify")
            .setContentText(status)
            .setSmallIcon(R.drawable.ic_meow_status)
            .setOngoing(true)
            .build()
        service.startForeground(NOTIFICATION_ID, notification)
    }

    private data class PreparedRuntimeConfig(
        val config: String,
        val overrideOptions: OverrideOptions,
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
                        MeowDiagnostics.log(
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
                MeowDiagnostics.log(
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
            MeowDiagnostics.log(TAG, "prepareConfig parse failed", error)
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            }
        }
        if (filter.countActions() == 0) {
            return
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                service.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                service.registerReceiver(receiver, filter)
            }
            receiverRegistered = true
            MeowDiagnostics.log(TAG, "runtime receiver registered")
            updateDeviceIdleMode()
        }.onFailure {
            MeowDiagnostics.log(TAG, "runtime receiver registration failed", it)
        }
    }

    private fun unregisterRuntimeReceiver() {
        if (!receiverRegistered) {
            return
        }
        runCatching {
            service.unregisterReceiver(receiver)
            receiverRegistered = false
            MeowDiagnostics.log(TAG, "runtime receiver unregistered")
        }.onFailure {
            receiverRegistered = false
            MeowDiagnostics.log(TAG, "runtime receiver unregister failed", it)
        }
    }

    private fun updateDeviceIdleMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }
        val powerManager = service.getSystemService(Context.POWER_SERVICE) as PowerManager
        val idle = powerManager.isDeviceIdleMode
        MeowDiagnostics.log(TAG, "device idle mode changed idle=$idle")
        val server = commandServer
        if (server == null) {
            val level = if (SingboxController.running) "warning" else "debug"
            SingboxController.log(
                level,
                "device idle update skipped idle=$idle: command server is missing " +
                    "running=${SingboxController.running} mode=${SingboxController.serviceMode}",
            )
            return
        }
        runCatching {
            if (idle) {
                SingboxController.log(
                    "info",
                    "Android device idle/doze entered; keeping VPN core active",
                )
            } else {
                SingboxController.log(
                    "info",
                    "core wake requested by Android device idle exit",
                )
                server.wake()
            }
        }.onFailure {
            MeowDiagnostics.log(TAG, "device idle mode update failed idle=$idle", it)
            SingboxController.log(
                "error",
                "device idle mode update failed idle=$idle error=${it.message}",
            )
        }
    }
}
