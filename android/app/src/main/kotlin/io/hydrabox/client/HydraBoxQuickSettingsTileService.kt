package io.hydrabox.client

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
import io.hydrabox.client.singbox.HydraBoxService
import io.hydrabox.client.singbox.HydraBoxProxyService
import io.hydrabox.client.singbox.HydraBoxVpnService
import io.hydrabox.client.singbox.RuntimeServiceModeResolver
import io.hydrabox.client.singbox.SingboxController
import org.json.JSONObject

class HydraBoxQuickSettingsTileService : TileService() {
    companion object {
        private const val QUICK_TILE_LABEL_FILE = "quick_tile_label.txt"
        private const val TILE_LABEL = "HydraBox"
        private const val MAX_LABEL_LENGTH = 18

        fun requestRefresh(context: android.content.Context) {
            requestListeningState(
                context,
                ComponentName(context, HydraBoxQuickSettingsTileService::class.java),
            )
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val activeMode = activeRuntimeMode()
        if (activeMode != null) {
            stopRuntime(activeMode)
            renderTile(isActive = false)
            scheduleRefreshes()
            return
        }

        val hasConfig = runCatching {
            HydraBoxApplication.configFile.exists() && HydraBoxApplication.configFile.readText().isNotBlank()
        }.getOrDefault(false)
        if (!hasConfig) {
            Toast.makeText(this, "No VPN config yet", Toast.LENGTH_SHORT).show()
            openApp()
            return
        }

        val targetMode = configuredMode()
        if (targetMode == null) {
            Toast.makeText(this, "No VPN or proxy inbound enabled", Toast.LENGTH_SHORT).show()
            openApp()
            return
        }
        if (targetMode == RuntimeServiceModeResolver.VPN) {
            val vpnPrepareIntent = VpnService.prepare(this)
            if (vpnPrepareIntent != null) {
                openIntent(vpnPrepareIntent)
                return
            }
        }

        startRuntime(targetMode)
        renderTile(
            isActive = true,
            activeLabel = readActiveTileLabel(),
        )
        scheduleRefreshes()
    }

    private fun activeRuntimeMode(): String? = RuntimeServiceModeResolver.activeMode(
        runningMode = SingboxController.serviceMode.takeIf { SingboxController.running },
        vpnRecorded = HydraBoxApplication.isRecordedServiceAlive(RuntimeServiceModeResolver.VPN),
        proxyRecorded = HydraBoxApplication.isRecordedServiceAlive(RuntimeServiceModeResolver.PROXY),
    )

    private fun stopRuntime(mode: String) {
        HydraBoxService.requestStopAll("quick_tile_stop")
        val serviceClass = serviceClass(mode)
        startService(
            Intent(this, serviceClass)
                .setAction(HydraBoxService.ACTION_STOP)
                .putExtra(HydraBoxService.EXTRA_STOP_REASON, "quick_tile"),
        )
        Handler(Looper.getMainLooper()).postDelayed({
            if (!SingboxController.running) {
                stopService(Intent(this, HydraBoxVpnService::class.java))
                stopService(Intent(this, HydraBoxProxyService::class.java))
                HydraBoxApplication.clearServiceState()
                HydraBoxApplication.clearRuntimeIntent()
                requestRefresh(this)
            }
        }, 1_200L)
    }

    private fun startRuntime(targetMode: String) {
        val runningMode = SingboxController.serviceMode
        if (SingboxController.running && runningMode != targetMode) {
            startService(
                Intent(this, serviceClass(runningMode)).setAction(HydraBoxService.ACTION_STOP),
            )
            SingboxController.awaitStopped { stopped ->
                if (stopped) {
                    startRuntimeService(targetMode)
                } else {
                    SingboxController.log(
                        "error",
                        "quick tile mode switch aborted: $runningMode stop timed out",
                    )
                    requestRefresh(this)
                }
            }
            return
        }
        startRuntimeService(targetMode)
    }

    private fun startRuntimeService(mode: String) {
        val intent = Intent(this, serviceClass(mode)).setAction(HydraBoxService.ACTION_START)
        startForegroundService(intent)
    }

    private fun serviceClass(mode: String): Class<out android.app.Service> =
        if (mode == RuntimeServiceModeResolver.PROXY) {
            HydraBoxProxyService::class.java
        } else {
            HydraBoxVpnService::class.java
        }

    private fun configuredMode(): String? {
        val rawConfig = runCatching { HydraBoxApplication.configFile.readText() }.getOrNull()
            ?: return null
        return runCatching {
            val inbounds = JSONObject(rawConfig).optJSONArray("inbounds") ?: return@runCatching null
            val types = buildList {
                for (index in 0 until inbounds.length()) {
                    val type = inbounds.optJSONObject(index)?.optString("type").orEmpty()
                    if (type.isNotBlank()) add(type)
                }
            }
            RuntimeServiceModeResolver.configuredMode(types)
        }.getOrNull()
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
    @Suppress("DEPRECATION")
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
            isActive = activeRuntimeMode() != null,
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
        tile.icon = Icon.createWithResource(this, R.drawable.ic_hydrabox_status)
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

        val rawConfig = runCatching { HydraBoxApplication.configFile.readText() }.getOrNull() ?: return null
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
