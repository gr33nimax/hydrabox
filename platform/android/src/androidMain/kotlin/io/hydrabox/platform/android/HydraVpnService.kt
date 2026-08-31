package io.hydrabox.platform.android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.IBinder
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.SystemProxyStatus
import io.hydrabox.core.contract.RuntimeCommand
import io.hydrabox.core.contract.RuntimeMode
import io.hydrabox.core.contract.RuntimeState

class HydraVpnService : VpnService() {
    private val runtime = StubRuntime()
    private val endpoint = BinderRuntimeEndpoint(runtime)
    private var commandServer: CommandServer? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> start()
            ACTION_STOP -> stop()
        }
        return Service.START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? =
        if (VpnService.SERVICE_INTERFACE == intent?.action) super.onBind(intent) else endpoint

    private fun start() {
        val config = filesDir.resolve(CONFIG_FILE)
        require(config.isFile && config.length() > 0) { "Put a valid config in ${config.path}" }
        val content = config.readText()
        Libbox.checkConfig(content)
        commandServer?.closeService()
        commandServer?.close()
        commandServer = Libbox.newCommandServer(handler, MinimalVpnPlatform(this)).also {
            it.start()
            it.startOrReloadService(content, OverrideOptions())
        }
        runtime.submit(RuntimeCommand.Start(RuntimeMode.VPN))
        startForeground(NOTIFICATION_ID, notification(RuntimeState.RUNNING))
    }

    private fun stop() {
        runtime.submit(RuntimeCommand.Stop)
        commandServer?.closeService()
        commandServer?.close()
        commandServer = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun notification(state: RuntimeState) = (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).let { manager ->
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "HydraBox VPN", NotificationManager.IMPORTANCE_LOW))
        android.app.Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("HydraBox")
            .setContentText(state.name.lowercase())
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .build()
    }

    companion object {
        const val ACTION_START = "io.hydrabox.platform.android.START"
        const val ACTION_STOP = "io.hydrabox.platform.android.STOP"
        const val CONFIG_FILE = "hydra-config.json"
        private const val CHANNEL_ID = "hydrabox-vpn"
        private const val NOTIFICATION_ID = 1
        private val handler = object : CommandServerHandler {
            override fun getSystemProxyStatus() = SystemProxyStatus().apply { available = false; enabled = false }
            override fun serviceReload() = Unit
            override fun serviceStop() = Unit
            override fun setSystemProxyEnabled(enabled: Boolean) = Unit
            override fun writeDebugMessage(message: String?) = Unit
        }
    }
}
