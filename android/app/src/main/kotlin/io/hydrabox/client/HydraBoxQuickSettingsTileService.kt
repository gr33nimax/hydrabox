package io.hydrabox.client

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import io.hydrabox.client.runtime.CoreRuntimeClient
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.hydrabox.client.singbox.RuntimeEventConsumer
import io.hydrabox.client.singbox.RuntimeServiceModeResolver
import org.json.JSONObject

internal fun tileActiveFor(state: CoreRuntimeProtocol.RuntimeState): Boolean = state in setOf(
    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING,
    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING,
)

class HydraBoxQuickSettingsTileService : TileService() {
    private val coreRuntimeClient by lazy { CoreRuntimeClient(applicationContext) }
    private val tileEventConsumer = object : RuntimeEventConsumer {
        override fun success(event: Any?) = updateTile()

        override fun error(code: String, message: String?, details: Any?) = Unit

        override fun endOfStream() = Unit
    }

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
        coreRuntimeClient.connect()
        coreRuntimeClient.registerEventConsumer(tileEventConsumer)
        updateTile()
    }

    override fun onStopListening() {
        coreRuntimeClient.unregisterEventConsumer(tileEventConsumer)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (tileActiveFor(coreRuntimeClient.cachedSnapshot()?.state
                ?: CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_UNSPECIFIED)) {
            stopRuntime()
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

        val targetMode = snapshotMode() ?: configuredMode()
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
    }

    private fun snapshotMode(): String? = when (coreRuntimeClient.cachedSnapshot()?.mode) {
        // Переводится на snapshot.desiredRuntime.mode в HB-RW-012.
        CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN -> RuntimeServiceModeResolver.VPN
        CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY -> RuntimeServiceModeResolver.PROXY
        else -> null
    }

    private fun stopRuntime() {
        coreRuntimeClient.stop("quick_tile") { }
    }

    private fun startRuntime(targetMode: String) {
        val config = runCatching { HydraBoxApplication.configFile.readBytes() }.getOrNull()
        if (config == null || config.isEmpty()) {
            requestRefresh(this)
            return
        }
        coreRuntimeClient.start(
            config = config,
            useVpn = targetMode == RuntimeServiceModeResolver.VPN,
            source = "tile",
        ) { result ->
            if (result.isFailure) {
                Toast.makeText(this, "HydraCore could not start", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onDestroy() {
        coreRuntimeClient.close()
        super.onDestroy()
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
            isActive = tileActiveFor(
                coreRuntimeClient.cachedSnapshot()?.state
                    ?: CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_UNSPECIFIED,
            ),
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
