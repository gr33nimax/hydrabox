package com.etonify.meow_client

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import com.etonify.meow_client.singbox.MeowBoxService
import com.etonify.meow_client.singbox.MeowProxyService
import com.etonify.meow_client.singbox.MeowVpnService
import com.etonify.meow_client.singbox.SingboxController
import org.json.JSONObject

class MeowQuickSettingsTileService : TileService() {
    companion object {
        private const val QUICK_TILE_LABEL_FILE = "quick_tile_label.txt"
        private const val TILE_LABEL = "Etonify"
        private const val MAX_LABEL_LENGTH = 18

        fun requestRefresh(context: android.content.Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                requestListeningState(
                    context,
                    ComponentName(context, MeowQuickSettingsTileService::class.java),
                )
            }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val isVpnRunning = isVpnRunning()
        if (isVpnRunning) {
            stopVpn()
            renderTile(isActive = false)
            scheduleRefreshes()
            return
        }

        val vpnPrepareIntent = VpnService.prepare(this)
        if (vpnPrepareIntent != null) {
            openIntent(vpnPrepareIntent)
            return
        }

        val hasConfig = runCatching {
            MeowApplication.configFile.exists() && MeowApplication.configFile.readText().isNotBlank()
        }.getOrDefault(false)
        if (!hasConfig) {
            Toast.makeText(this, "No VPN config yet", Toast.LENGTH_SHORT).show()
            openApp()
            return
        }

        startVpn()
        renderTile(
            isActive = true,
            activeLabel = readActiveTileLabel(),
        )
        scheduleRefreshes()
    }

    private fun isVpnRunning(): Boolean {
        return SingboxController.running && SingboxController.serviceMode == "vpn" ||
            MeowApplication.isRecordedServiceAlive("vpn")
    }

    private fun stopVpn() {
        MeowBoxService.requestStopAll("quick_tile_stop")
        startService(
            Intent(this, MeowVpnService::class.java)
                .setAction(MeowBoxService.ACTION_STOP)
                .putExtra(MeowBoxService.EXTRA_STOP_REASON, "quick_tile"),
        )
        Handler(Looper.getMainLooper()).postDelayed({
            if (!SingboxController.running) {
                stopService(Intent(this, MeowVpnService::class.java))
                stopService(Intent(this, MeowProxyService::class.java))
                MeowApplication.clearServiceState()
                requestRefresh(this)
            }
        }, 1_200L)
    }

    private fun startVpn() {
        if (SingboxController.running && SingboxController.serviceMode == "proxy") {
            startService(Intent(this, MeowProxyService::class.java).setAction(MeowBoxService.ACTION_STOP))
            Handler(Looper.getMainLooper()).postDelayed({ startVpnService() }, 300)
            return
        }
        startVpnService()
    }

    private fun startVpnService() {
        val intent = Intent(this, MeowVpnService::class.java).setAction(MeowBoxService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            ?: Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        openIntent(intent)
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openIntent(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTile() {
        renderTile(
            isActive = isVpnRunning(),
            activeLabel = readActiveTileLabel(),
        )
    }

    private fun renderTile(
        isActive: Boolean,
        activeLabel: String? = null,
    ) {
        val tile = qsTile ?: return
        val resolvedActiveLabel = formatActiveLabel(activeLabel)
        tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.icon = Icon.createWithResource(this, R.drawable.ic_meow_status)
        tile.label = if (isActive) resolvedActiveLabel ?: TILE_LABEL else TILE_LABEL
        tile.updateTile()
    }

    private fun scheduleRefreshes() {
        Handler(Looper.getMainLooper()).postDelayed({ requestRefresh(this) }, 350)
        Handler(Looper.getMainLooper()).postDelayed({ requestRefresh(this) }, 1200)
        Handler(Looper.getMainLooper()).postDelayed({ requestRefresh(this) }, 2500)
    }

    private fun formatActiveLabel(label: String?): String? {
        val normalized = label?.trim().orEmpty()
        if (normalized.isEmpty()) {
            return null
        }
        return if (normalized.length <= MAX_LABEL_LENGTH) {
            normalized
        } else {
            normalized.take(MAX_LABEL_LENGTH - 1).trimEnd() + "…"
        }
    }

    private fun readActiveTileLabel(): String? {
        val persistedLabel = runCatching {
            val value = openFileInput(QUICK_TILE_LABEL_FILE).bufferedReader().use { it.readText() }
            value.trim().ifEmpty { null }
        }.getOrNull()
        if (persistedLabel != null) {
            return persistedLabel
        }

        val rawConfig = runCatching { MeowApplication.configFile.readText() }.getOrNull() ?: return null
        return runCatching {
            val root = JSONObject(rawConfig)
            val outbounds = root.optJSONArray("outbounds") ?: return@runCatching null
            for (index in 0 until outbounds.length()) {
                val outbound = outbounds.optJSONObject(index) ?: continue
                if (outbound.optString("type") != "selector" || outbound.optString("tag") != "select") {
                    continue
                }
                val selected = outbound.optString("default").trim()
                if (selected.isNotEmpty()) {
                    return@runCatching selected
                }
            }
            null
        }.getOrNull()
    }
}
