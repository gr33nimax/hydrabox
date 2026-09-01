package io.hydrabox.platform.android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.pm.ApplicationInfo
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
import io.hydrabox.core.config.ConfigGenerator
import io.hydrabox.core.config.ConfigInput
import io.hydrabox.core.contract.RuntimeMode
import io.hydrabox.core.contract.RuntimeState
import io.hydrabox.core.contract.RuntimeGeneration
import io.hydrabox.core.contract.TransportHealth
import io.hydrabox.core.runtime.Effect
import io.hydrabox.core.runtime.RuntimeInput

class HydraVpnService : VpnService() {
    private lateinit var runtime: AndroidRuntime
    private lateinit var endpoint: BinderRuntimeEndpoint
    private var commandServer: CommandServer? = null

    override fun onCreate() {
        super.onCreate()
        runtime = AndroidRuntime(::execute)
        endpoint = BinderRuntimeEndpoint(runtime)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> start()
            ACTION_STOP -> stop()
        }
        return Service.START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? =
        if (VpnService.SERVICE_INTERFACE == intent?.action) super.onBind(intent) else endpoint

    override fun onDestroy() {
        stopRuntime()
        super.onDestroy()
    }

    private fun start() {
        startForeground(NOTIFICATION_ID, notification(RuntimeState.STARTING))
        runtime.submit(RuntimeCommand.Start(RuntimeMode.VPN))
        startForeground(NOTIFICATION_ID, notification(runtime.snapshot().state))
    }

    private fun execute(effect: Effect) = when (effect) {
        is Effect.StartCore -> startCore(effect.commandGeneration)
        is Effect.StopCore -> {
            stopRuntime()
            runtime.dispatch(RuntimeInput.Released(effect.commandGeneration, true))
        }
        else -> Unit
    }

    private fun startCore(commandGeneration: Long) {
        val content = ConfigGenerator.generate(ConfigInput("https://dns.cloudflare.com/dns-query", ready = true))
        ensureLibboxSetup()
        Libbox.checkConfig(content)
        stopRuntime()
        commandServer = Libbox.newCommandServer(handler, MinimalVpnPlatform(this)).also {
            it.start()
            it.startOrReloadService(content, OverrideOptions())
        }
        runtime.dispatch(RuntimeInput.Launched(commandGeneration, commandGeneration))
        runtime.dispatch(RuntimeInput.Health(commandGeneration, commandGeneration, TransportHealth(applicable = false, runtimeGeneration = RuntimeGeneration(commandGeneration))))
    }

    private fun stop() {
        runtime.submit(RuntimeCommand.Stop)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopRuntime() {
        commandServer?.closeService()
        commandServer?.close()
        commandServer = null
    }

    private fun ensureLibboxSetup() = synchronized(HydraVpnService::class.java) {
        if (libboxReady) return
        val base = filesDir.resolve("libbox-base").apply { mkdirs() }
        val work = filesDir.resolve("libbox-work").apply { mkdirs() }
        val temp = cacheDir.resolve("libbox-temp").apply { mkdirs() }
        Libbox.setup(SetupOptions().apply {
            basePath = base.path
            workingPath = work.path
            tempPath = temp.path
            debug = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        })
        libboxReady = true
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
        private const val CHANNEL_ID = "hydrabox-vpn"
        private const val NOTIFICATION_ID = 1
        @Volatile private var libboxReady = false
        private val handler = object : CommandServerHandler {
            override fun getSystemProxyStatus() = SystemProxyStatus().apply { available = false; enabled = false }
            override fun serviceReload() = Unit
            override fun serviceStop() = Unit
            override fun setSystemProxyEnabled(enabled: Boolean) = Unit
            override fun writeDebugMessage(message: String?) = Unit
        }
    }
}
