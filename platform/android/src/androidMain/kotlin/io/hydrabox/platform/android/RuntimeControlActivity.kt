package io.hydrabox.platform.android

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.widget.Button

class RuntimeControlActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(Button(this).apply {
            text = "Start tunnel"
            setOnClickListener { prepareAndStart() }
        })
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN && resultCode == RESULT_OK) startRuntime()
    }

    private fun prepareAndStart() {
        VpnService.prepare(this)?.let { startActivityForResult(it, REQUEST_VPN) } ?: startRuntime()
    }

    private fun startRuntime() {
        startForegroundService(Intent(this, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
    }

    private companion object { const val REQUEST_VPN = 1 }
}
