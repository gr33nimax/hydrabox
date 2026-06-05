package com.etonify.meow_client.singbox

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import com.etonify.meow_client.MeowApplication

class MeowVpnService : VpnService() {
    companion object {
        private const val TAG = "MeowVpnService"
        private const val WAKE_LOCK_TAG = "meow:vpn"
    }

    private lateinit var boxService: MeowBoxService
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "onCreate")
        MeowDiagnostics.log(TAG, "onCreate")
        acquireWakeLock()
        boxService = MeowBoxService(
            this,
            MeowVpnPlatformInterface(this) { fd -> boxService.onTunOpened(fd) },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand action=${intent?.action}")
        MeowDiagnostics.log(TAG, "onStartCommand action=${intent?.action} startId=$startId")
        return boxService.onStartCommand(intent, startId)
    }

    override fun onBind(intent: Intent): IBinder? {
        return super.onBind(intent)
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        MeowDiagnostics.log(TAG, "onDestroy")
        boxService.onDestroy()
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.w(TAG, "onRevoke")
        MeowDiagnostics.log(TAG, "onRevoke")
        boxService.serviceStop()
        super.onRevoke()
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        if (wakeLock != null) {
            SingboxController.log("debug", "wakelock acquire skipped: already held tag=$WAKE_LOCK_TAG")
            return
        }
        if (!MeowApplication.wakeLockEnabled) {
            SingboxController.log(
                "info",
                "wakelock disabled: keeping VPN core active without partial wakelock tag=$WAKE_LOCK_TAG",
            )
            return
        }
        runCatching {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire()
            }
            SingboxController.log("info", "wakelock acquired tag=$WAKE_LOCK_TAG")
        }.onFailure {
            Log.w(TAG, "acquireWakeLock failed", it)
            SingboxController.log("error", "wakelock acquire failed tag=$WAKE_LOCK_TAG error=${it.message}")
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        wakeLock = null
        runCatching {
            val wasHeld = lock.isHeld
            if (wasHeld) lock.release()
            SingboxController.log("info", "wakelock released tag=$WAKE_LOCK_TAG wasHeld=$wasHeld")
        }.onFailure {
            Log.w(TAG, "releaseWakeLock failed", it)
            SingboxController.log("error", "wakelock release failed tag=$WAKE_LOCK_TAG error=${it.message}")
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (!SingboxController.running) {
            Log.i(TAG, "onTaskRemoved – runtime is stopped; stopping lingering VPN service")
            MeowDiagnostics.log(TAG, "onTaskRemoved – runtime is stopped; stopping lingering VPN service")
            boxService.requestStop("task_removed_runtime_stopped")
            stopSelf()
            return
        }
        Log.i(TAG, "onTaskRemoved – scheduling service restart")
        MeowDiagnostics.log(TAG, "onTaskRemoved – scheduling service restart")
        // Schedule restart via AlarmManager so the VPN survives app-swipe.
        val restartIntent = Intent(this, MeowVpnService::class.java)
            .setAction(MeowBoxService.ACTION_START)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_ONE_SHOT
        }
        val pending = PendingIntent.getService(this, 0, restartIntent, flags)
        val alarm = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.set(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + 1_000,
            pending,
        )
    }
}
