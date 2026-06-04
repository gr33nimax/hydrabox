package com.etonify.meow_client.singbox

import android.app.Service
import android.content.Intent
import android.os.IBinder

class MeowProxyService : Service() {
    private val boxService by lazy {
        MeowBoxService(this, MeowProxyPlatformInterface(this))
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
