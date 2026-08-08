package io.hydrabox.client.singbox

import android.app.Service
import android.content.Intent
import android.os.IBinder

class HydraBoxProxyService : Service() {
    private val boxService by lazy {
        HydraBoxService(this, HydraBoxProxyPlatformInterface(this))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return boxService.onStartCommand(intent, startId)
    }

    override fun onBind(intent: Intent): IBinder? = null

    override fun onDestroy() {
        boxService.onDestroy()
        super.onDestroy()
    }
}
