package io.hydrabox.platform.android

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import io.hydrabox.core.contract.CommandGeneration
import io.hydrabox.core.contract.EventSequence
import io.hydrabox.core.contract.NetworkGeneration
import io.hydrabox.core.contract.ProcessEpoch
import io.hydrabox.core.contract.RuntimeCommand
import io.hydrabox.core.contract.RuntimeEvent
import io.hydrabox.core.contract.RuntimeGeneration
import io.hydrabox.core.contract.RuntimeMode
import io.hydrabox.core.contract.RuntimeSnapshot
import io.hydrabox.core.contract.RuntimeState
import io.hydrabox.core.model.OperationError
import io.hydrabox.core.model.OperationState
import io.hydrabox.core.projection.AppReadModel
import io.hydrabox.core.projection.DiagnosticsSummary
import io.hydrabox.core.projection.ScreenProjection
import io.hydrabox.ui.app.AppActions
import io.hydrabox.ui.app.HydraApp
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.concurrent.Executors

/**
 * Composition root. It binds the runtime, combines the read models and hands them to the
 * projection. It holds no phase of its own, no timer, and no branch on runtime state; the
 * only thing it decides is which thread a store call runs on.
 */
class RuntimeControlActivity : ComponentActivity() {
    private lateinit var store: AppStore
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var transport: BinderRuntimeTransport? = null
    private var subscription: AutoCloseable? = null

    private var snapshot by mutableStateOf(stoppedSnapshot())
    private var revision by mutableStateOf(0)
    private var message by mutableStateOf<String?>(null)
    private var busy by mutableStateOf<OperationState<Unit>>(OperationState.Idle)

    private val permission = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK) launch() else message = "VPN permission was declined"
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            binder ?: return
            BinderRuntimeTransport(binder).let { bound ->
                transport = bound
                snapshot = runCatching { bound.snapshot() }.getOrElse { stoppedSnapshot() }
                subscription = runCatching {
                    bound.subscribe { event ->
                        (event as? RuntimeEvent.Snapshot)?.let { update -> main.post { snapshot = update.snapshot } }
                    }
                }.getOrNull()
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            subscription = null
            transport = null
            snapshot = stoppedSnapshot()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = AppStore(this)
        bindService(Intent(this, HydraVpnService::class.java), connection, Context.BIND_AUTO_CREATE)
        setContent {
            HydraApp(state = ScreenProjection.project(readModel()), message = message, actions = actions())
        }
    }

    override fun onDestroy() {
        runCatching { subscription?.close() }
        runCatching { unbindService(connection) }
        io.shutdown()
        super.onDestroy()
    }

    private fun readModel(): AppReadModel {
        revision.let { }
        val settings = store.settings()
        return AppReadModel(
            runtime = snapshot,
            subscriptions = store.summaries(),
            proxies = store.proxies(),
            settings = store.settingsSummary(settings),
            diagnostics = DiagnosticsSummary(
                level = "warn",
                recentEvents = listOfNotNull(
                    "runtime: ${snapshot.state.name.lowercase()}",
                    "transport: ${snapshot.transportHealth.state.name.lowercase()}, lanes ${snapshot.transportHealth.activeLanes}",
                    "core: ${BuildConfig.HYDRACORE_VERSION}",
                    "selected: ${store.selectedTag() ?: "none"}",
                    "generations: c${snapshot.commandGeneration.value} r${snapshot.runtimeGeneration.value} n${snapshot.networkGeneration.value}",
                    snapshot.lastFailure?.let { "last failure: ${it.domain.name.lowercase()} / ${it.code.code}" },
                    store.startFailure()?.let { "start rejected: $it" },
                    store.configPreview()?.take(600)?.let { "config: $it" },
                ),
                exportState = "idle",
            ),
            subscriptionOperation = busy,
            legalAccepted = settings.acceptedLegalAtMillis != null,
        )
    }

    private fun actions() = AppActions(
        onStart = ::prepareAndStart,
        onStop = { send(RuntimeCommand.Stop) },
        onRetry = ::prepareAndStart,
        onAddSubscription = { name, source -> background("Added") { store.addSubscription(name, source) } },
        onRefreshSubscription = { id -> background("Refreshed") { store.refreshSubscription(id) } },
        onRenameSubscription = { id, name -> background(null) { store.renameSubscription(id, name) } },
        onRemoveSubscription = { id -> background(null) { store.removeSubscription(id) } },
        onSelectProxy = { tag ->
            background(null) {
                store.select(tag)
                if (snapshot.state == RuntimeState.RUNNING) main.post { send(RuntimeCommand.SelectOutbound("select", tag)) }
            }
        },
        onAcceptLegal = {
            background(null) {
                store.saveSettings(store.settings().copy(acceptedLegalVersion = "1", acceptedLegalAtMillis = System.currentTimeMillis()))
            }
        },
        onSetMtu = { mtu -> background(null) { store.saveSettings(store.settings().copy(vpnMtu = mtu)) } },
        onSetProxyDns = { value -> background(null) { store.saveSettings(store.settings().copy(dnsProxyResolver = value)) } },
        onSetDirectDns = { value -> background(null) { store.saveSettings(store.settings().copy(dnsDirectResolver = value)) } },
        onSetSplitPackages = { value -> background("Saved") { store.setSplitRoutingPackages(value) } },
        onToggleNotification = {
            background(null) {
                store.saveSettings(store.settings().let { it.copy(statusNotificationEnabled = !it.statusNotificationEnabled) })
            }
        },
        onReload = { send(RuntimeCommand.Reload) },
    )

    private fun background(success: String?, block: () -> Unit) {
        busy = OperationState.Running
        message = null
        io.execute {
            val failure = runCatching(block).exceptionOrNull()
            main.post {
                busy = failure?.let { OperationState.Failed(OperationError(it.message ?: "failed")) } ?: OperationState.Idle
                message = failure?.let { "Failed: ${it.message ?: it::class.simpleName}" } ?: success
                revision += 1
            }
        }
    }

    private fun prepareAndStart() {
        busy = OperationState.Running
        io.execute {
            val ready = runCatching { store.generateConfig() != null }.getOrDefault(false)
            main.post {
                busy = OperationState.Idle
                if (!ready) {
                    message = "Add a working subscription before connecting"
                    return@post
                }
                message = null
                VpnService.prepare(this)?.let(permission::launch) ?: launch()
            }
        }
    }

    private fun launch() {
        message = null
        startForegroundService(Intent(this, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
    }

    private fun send(command: RuntimeCommand) {
        val bound = transport
        if (bound == null) {
            message = "Runtime is not bound yet"
            return
        }
        runCatching { bound.submit(command) }.exceptionOrNull()?.let { message = "Failed: ${it.message}" }
    }

    private fun stoppedSnapshot() = RuntimeSnapshot(
        processEpoch = ProcessEpoch("ui"),
        commandGeneration = CommandGeneration(0),
        runtimeGeneration = RuntimeGeneration(0),
        networkGeneration = NetworkGeneration(0),
        lastEventSequence = EventSequence(0),
        state = RuntimeState.STOPPED,
        mode = RuntimeMode.VPN,
    )
}
