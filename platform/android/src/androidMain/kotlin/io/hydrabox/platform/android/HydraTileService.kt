package io.hydrabox.platform.android

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import io.hydrabox.core.projection.Connection
import io.hydrabox.core.projection.ErrorMessage
import io.hydrabox.core.projection.PrimaryAction
import io.hydrabox.core.projection.ScreenProjection
import io.hydrabox.core.projection.primaryAction

/**
 * Quick Settings tile. It reflects the runtime rather than its own idea of state: the tile
 * reads the snapshot over the same binder the UI uses, so it cannot drift from reality.
 */
class HydraTileService : TileService() {
    private var transport: BinderRuntimeTransport? = null
    private var bound = false

    private val connection =
        object : ServiceConnection {
            override fun onServiceConnected(
                name: ComponentName?,
                binder: IBinder?,
            ) {
                transport = binder?.let(::BinderRuntimeTransport)
                render()
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                transport = null
                render()
            }
        }

    override fun onStartListening() {
        super.onStartListening()
        if (!bound) {
            // Deliberately without BIND_AUTO_CREATE. Pulling down the shade should not start a
            // second process with the core's native library in it, and it did: `batterystats`
            // counted nine launches of `HydraVpnService` for one actual start, alongside thirteen
            // tile bindings. Without the flag the bind succeeds only while the tunnel is already
            // up, which is the only case where there is any state to read; otherwise there is
            // nothing running and the tile is inactive, which is the truth.
            bound =
                runCatching { bindService(Intent(this, HydraVpnService::class.java), connection, 0) }
                    .getOrDefault(false)
            // A bind that found nothing still leaves the connection registered.
            if (!bound) runCatching { unbindService(connection) }
        }
        render()
    }

    override fun onStopListening() {
        if (bound) {
            runCatching { unbindService(connection) }
            bound = false
            transport = null
        }
        super.onStopListening()
    }

    // The pre-34 overload is the only way to start an activity from a tile on those
    // versions, and minSdk is 26. The modern overload is used wherever it exists.
    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        super.onClick()
        val projected = connection()
        val action = projected?.primaryAction
        if (action == PrimaryAction.DISCONNECT || action == PrimaryAction.CANCEL) {
            startService(Intent(this, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_STOP))
        } else if (action != PrimaryAction.NONE) {
            val requestStart =
                when (projected) {
                    is Connection.Stopped -> action == PrimaryAction.RETRY
                    is Connection.Unreachable -> action == PrimaryAction.RETRY
                    else -> action == null || action == PrimaryAction.CONNECT || action == PrimaryAction.ADD_SUBSCRIPTION
                }
            // Starting can need the system VPN consent dialog, which a tile cannot show,
            // so the activity is asked to start instead of the service directly. The
            // PendingIntent overload only exists from API 34; below that the deprecated
            // Intent overload is the only way.
            val target =
                Intent(this, RuntimeControlActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (requestStart) target.setAction(RuntimeControlActivity.ACTION_REQUEST_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(this, 0, target, PendingIntent.FLAG_IMMUTABLE),
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(target)
            }
        }
        render()
    }

    private fun render() {
        val projected = connection()
        val action = projected?.primaryAction
        qsTile?.apply {
            state =
                when (action) {
                    PrimaryAction.NONE -> Tile.STATE_UNAVAILABLE
                    PrimaryAction.DISCONNECT, PrimaryAction.CANCEL -> Tile.STATE_ACTIVE
                    else -> Tile.STATE_INACTIVE
                }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = getString(projected.toTileLabel())
            }
            updateTile()
        }
    }

    private fun connection(): Connection? =
        runCatching { transport?.snapshot()?.let { ScreenProjection.project(it).connection } }.getOrNull()

    private fun Connection?.toTileLabel(): Int =
        when (this) {
            is Connection.Connected -> R.string.notification_connected
            is Connection.Connecting -> R.string.notification_connecting
            is Connection.Reconnecting -> R.string.notification_reconnecting
            Connection.Disconnecting -> R.string.notification_disconnecting
            is Connection.Unreachable -> errorLabel(presentation.message)
            is Connection.Stopped -> errorLabel(presentation.message)
            else -> R.string.tile_disconnected
        }

    private fun errorLabel(message: ErrorMessage): Int =
        when (message) {
            ErrorMessage.NO_INTERNET -> R.string.notification_no_internet
            ErrorMessage.SERVER_UNREACHABLE -> R.string.notification_unreachable
            ErrorMessage.SUBSCRIPTION_UNAVAILABLE -> R.string.notification_subscription
            ErrorMessage.CONFIG_REJECTED -> R.string.notification_config
            ErrorMessage.PERMISSION_REQUIRED -> R.string.notification_permission
            ErrorMessage.CONNECTION_LOST -> R.string.notification_connection_lost
            ErrorMessage.UNKNOWN -> R.string.notification_failed
        }
}
