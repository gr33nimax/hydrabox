package com.etonify.meow_client.singbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
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
        private val activeServices = CopyOnWriteArraySet<MeowBoxService>()

        fun requestStopAll(source: String) {
            for (boxService in activeServices) {
                boxService.requestStop(source)
            }
        }
    }

    private val executor = Executors.newSingleThreadExecutor()

    private var protectServer: SnowtunProtectServer? = null

    @Volatile
    private var commandServer: CommandServer? = null

    @Volatile
    private var receiverRegistered = false

    @Volatile
    private var serviceGeneration = 0L

    @Volatile
    private var runningConfigHash: Int? = null

    @Volatile
    private var tunFd: Int = -1

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
            Log.w(TAG, "ignoring sticky restart without action")
            MeowDiagnostics.log(TAG, "ignoring sticky restart without action")
            executor.execute { stopInternal("sticky_null_intent", startId = startId) }
            return Service.START_NOT_STICKY
        }
        when (action) {
            ACTION_START -> executor.execute { startInternal("action_start") }
            ACTION_STOP -> {
                val reason = intent.getStringExtra(EXTRA_STOP_REASON)?.takeIf { it.isNotBlank() }
                    ?: "unspecified"
                executor.execute { stopInternal("action_stop:$reason", startId = startId) }
            }
            ACTION_RESTART_CORE -> executor.execute { restartCoreInternal("action_restart_core") }
            ACTION_RELOAD -> executor.execute { startOrReloadInternal() }
            else -> {
                Log.w(TAG, "ignoring unknown action=$action")
                MeowDiagnostics.log(TAG, "ignoring unknown action=$action")
                executor.execute { stopInternal("unknown_action", startId = startId) }
                return Service.START_NOT_STICKY
            }
        }
        return Service.START_NOT_STICKY
    }

    fun onDestroy() {
        MeowDiagnostics.log(TAG, "onDestroy")
        activeServices -= this
        executor.execute { stopInternal("service_onDestroy", stopSelf = false) }
    }

    fun requestStop(source: String) {
        executor.execute { stopInternal(source) }
    }

    fun onTunOpened(fd: Int) {
        tunFd = fd
        Log.i(TAG, "onTunOpened fd=$fd detached=true")
        MeowDiagnostics.log(TAG, "onTunOpened fd=$fd detached=true")
    }

    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply {
            available = false
            enabled = false
        }

    override fun serviceReload() {
        executor.execute { startOrReloadInternal() }
    }

    override fun serviceStop() {
        MeowDiagnostics.log(TAG, "serviceStop requested by libbox/platform")
        executor.execute { stopInternal("handler_serviceStop") }
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

    private fun currentConfigHash(): Int? =
        runCatching { MeowApplication.configFile.readText().hashCode() }.getOrNull()

    private fun startInternal(source: String) {
        val mode = currentMode()
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
                startOrReloadInternal()
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
        startOrReloadInternal()
    }

    private fun startOrReloadInternal() {
        Log.i(TAG, "startOrReloadInternal begin service=${service.javaClass.simpleName}")
        SingboxController.log(
            "info",
            "VPN service start/reload requested service=${service.javaClass.simpleName}",
        )
        MeowDiagnostics.log(
            TAG,
            "startOrReloadInternal begin service=${service.javaClass.simpleName} " +
                "current=${MeowDefaultNetworkMonitor.describeCurrentState()}",
        )
        MeowApplication.ensureLibboxSetup()
        showForeground("Starting")
        registerRuntimeReceiver()
        MeowDefaultNetworkMonitor.start()
        MeowDefaultNetworkMonitor.awaitUsableDefaultInterface()
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
        val preparedConfig = prepareConfig(config)
        if (!startProtectServerIfNeeded(preparedConfig)) {
            return
        }
        try {
            val server = commandServer ?: createCommandServer()
            Log.i(TAG, "starting/reloading libbox service")
            MeowDiagnostics.log(
                TAG,
                "starting/reloading libbox service current=${MeowDefaultNetworkMonitor.describeCurrentState()}",
            )
            server.startOrReloadService(preparedConfig, OverrideOptions())
            showForeground("Connected")
            val mode = currentMode()
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
    ) {
        val generation = serviceGeneration
        Log.i(TAG, "stopInternal source=$source service=${service.javaClass.simpleName}")
        SingboxController.log(
            "warning",
            "VPN service stop requested source=$source service=${service.javaClass.simpleName} " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                "generation=$generation hasCommandServer=${commandServer != null}",
        )
        MeowDiagnostics.log(
            TAG,
            "stopInternal source=$source service=${service.javaClass.simpleName} " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                "generation=$generation hasCommandServer=${commandServer != null}",
        )
        val server = commandServer
        commandServer = null
        unregisterRuntimeReceiver()
        MeowDefaultNetworkMonitor.stop()
        stopProtectServer()
        forceCloseTunFd(source)
        runCleanupStep("disconnect command client source=$source") {
            SingboxController.disconnectClient()
        }
        if (server != null) {
            runCleanupStep("closeService source=$source") {
                server.closeService()
            }
            runCleanupStep("close command server source=$source") {
                server.close()
            }
        }
        runningConfigHash = null
        serviceGeneration = 0L
        SingboxController.markServiceStopped(generation, source)
        MeowApplication.clearServiceState()
        MeowQuickSettingsTileService.requestRefresh(service)
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

    private fun forceCloseTunFd(source: String) {
        val fd = tunFd
        if (fd < 0) return
        tunFd = -1
        runCatching {
            ParcelFileDescriptor.adoptFd(fd).close()
            MeowDiagnostics.log(TAG, "force closed detached TUN fd=$fd source=$source")
        }.onFailure {
            MeowDiagnostics.log(TAG, "force close detached TUN fd=$fd failed source=$source", it)
        }
    }

    private fun restartCoreInternal(source: String) {
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
        startOrReloadInternal()
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

    private fun startProtectServerIfNeeded(config: String): Boolean {
        if (!config.contains("\"protect_path\"")) {
            stopProtectServer()
            return true
        }
        val vpnService = service as? VpnService ?: return true
        if (protectServer != null) {
            return true
        }
        val server = SnowtunProtectServer(
            vpnService,
            SnowtunProtectServer.DEFAULT_SOCKET_PATH,
        )
        return runCatching {
            server.start()
            protectServer = server
            true
        }.getOrElse { error ->
            protectServer = null
            Log.e(TAG, "failed to start protect server", error)
            MeowDiagnostics.log(TAG, "failed to start protect server", error)
            fail("Failed to start protect server: ${error.message ?: error}")
            false
        }
    }

    private fun stopProtectServer() {
        runCatching { protectServer?.stop() }.onFailure {
            MeowDiagnostics.log(TAG, "protect server stop failed", it)
        }
        protectServer = null
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

    private fun prepareConfig(config: String): String {
        return runCatching {
            val root = JSONObject(config)
            val outbounds = root.optJSONArray("outbounds")
            var changed = false
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
            if (changed) {
                root.toString()
            } else {
                config
            }
        }.getOrElse { error ->
            MeowDiagnostics.log(TAG, "prepareConfig parse failed", error)
            config
        }
    }

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
            SingboxController.log(
                "warning",
                "device idle update skipped idle=$idle: command server is missing " +
                    "running=${SingboxController.running} mode=${SingboxController.serviceMode}",
            )
            return
        }
        runCatching {
            if (idle) {
                SingboxController.log(
                    "warning",
                    "core pause requested by Android device idle/doze; " +
                        "wakeLockEnabled=${MeowApplication.wakeLockEnabled}",
                )
                server.pause()
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
