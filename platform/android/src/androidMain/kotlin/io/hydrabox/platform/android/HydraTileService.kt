package io.hydrabox.platform.android

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import io.hydrabox.core.contract.RuntimeEvent
import io.hydrabox.core.contract.RuntimeState
import java.util.concurrent.Executors

/**
 * Quick Settings tile. It reflects the runtime rather than its own idea of state: the tile
 * reads the snapshot over the same binder the UI uses, so it cannot drift from reality.
 */
class HydraTileService : TileService() {
    private var transport: BinderRuntimeTransport? = null
    private var bound = false
    private var subscription: AutoCloseable? = null
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var listening = false
    private var preparingStart = false
    private var destroyed = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val connected = binder?.let(::BinderRuntimeTransport)
            transport = connected
            subscription = runCatching { connected?.subscribe { event ->
                if (event is RuntimeEvent.Snapshot) {
                    main.post {
                        if (transport === connected) render(event.snapshot.state)
                    }
                }
            } }.getOrNull()
            render()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            subscription = null
            transport = null
            render()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        listening = true
        bindRuntime(createIfMissing = false)
        render()
    }

    private fun bindRuntime(createIfMissing: Boolean) {
        if (!bound) {
            // Deliberately without BIND_AUTO_CREATE. Pulling down the shade should not start a
            // second process with the core's native library in it, and it did: `batterystats`
            // counted nine launches of `HydraVpnService` for one actual start, alongside thirteen
            // tile bindings. Without the flag the bind succeeds only while the tunnel is already
            // up, which is the only case where there is any state to read; otherwise there is
            // nothing running and the tile is inactive, which is the truth.
            val flags = if (createIfMissing) Context.BIND_AUTO_CREATE else 0
            bound = runCatching { bindService(Intent(this, HydraVpnService::class.java), connection, flags) }
                .getOrDefault(false)
            // A bind that found nothing still leaves the connection registered.
            if (!bound) runCatching { unbindService(connection) }
        }
    }

    override fun onStopListening() {
        listening = false
        unbindRuntime()
        super.onStopListening()
    }

    private fun unbindRuntime() {
        runCatching { subscription?.close() }
        subscription = null
        if (bound) {
            runCatching { unbindService(connection) }
            bound = false
            transport = null
        }
    }

    override fun onClick() {
        super.onClick()
        if (preparingStart) return
        when (state()) {
            RuntimeState.RUNNING, RuntimeState.STARTING, RuntimeState.RECOVERING ->
                startService(Intent(this, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_STOP))
            RuntimeState.STOPPING -> return
            else -> prepareStart()
        }
        render()
    }

    private fun prepareStart() {
        preparingStart = true
        // Configuration generation reads and decrypts the catalogue, just as the activity's
        // start does. Keep it off the tile's main thread and close its database connection.
        io.execute {
            val readiness = runCatching {
                AppStore(this).use { store ->
                    val settings = store.settings()
                    val ready = settings.acceptedLegalAtMillis != null && store.generateConfig() != null
                    ready to store.proxyOnly(settings)
                }
            }.getOrDefault(false to false)
            main.post {
                if (destroyed) return@post
                preparingStart = false
                if (!readiness.first || (!readiness.second && VpnService.prepare(this) != null)) {
                    openForStart()
                } else {
                    startForegroundService(Intent(this, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
                    // Replace a dead binding from the previous connection. Only a deliberate
                    // start may create the service; opening the shade still uses flags = 0.
                    if (listening) {
                        if (transport == null) unbindRuntime()
                        bindRuntime(createIfMissing = true)
                    }
                }
                render()
            }
        }
    }

    // A tile cannot present VPN consent itself. Open the activity only when consent or
    // initial setup is required; an already configured connection stays in the shade.
    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openForStart() {
        val target = Intent(this, RuntimeControlActivity::class.java)
            .setAction(RuntimeControlActivity.ACTION_REQUEST_START)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, 0, target, PendingIntent.FLAG_IMMUTABLE),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(target)
        }
    }

    override fun onDestroy() {
        destroyed = true
        io.shutdownNow()
        main.removeCallbacksAndMessages(null)
        unbindRuntime()
        super.onDestroy()
    }

    private fun render(current: RuntimeState? = state()) {
        qsTile?.apply {
            state = if (preparingStart) Tile.STATE_UNAVAILABLE else when (current) {
                RuntimeState.RUNNING -> Tile.STATE_ACTIVE
                null, RuntimeState.STOPPED, RuntimeState.FAILED -> Tile.STATE_INACTIVE
                else -> Tile.STATE_UNAVAILABLE
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // The words the product uses, not the reducer's state names: the tile used to
                // read `running` and `stopping` in English under a Russian interface.
                subtitle = getString(
                    when (if (preparingStart) RuntimeState.STARTING else current) {
                        RuntimeState.RUNNING -> R.string.notification_connected
                        RuntimeState.STOPPING -> R.string.notification_disconnecting
                        RuntimeState.FAILED -> R.string.notification_failed
                        RuntimeState.STARTING, RuntimeState.RECOVERING -> R.string.notification_connecting
                        null, RuntimeState.STOPPED -> R.string.tile_disconnected
                    },
                )
            }
            updateTile()
        }
    }

    private fun state(): RuntimeState? = runCatching { transport?.snapshot()?.state }.getOrNull()
}
