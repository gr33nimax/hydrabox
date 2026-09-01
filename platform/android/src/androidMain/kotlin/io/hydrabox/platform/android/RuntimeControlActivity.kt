package io.hydrabox.platform.android

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.VpnService
import android.os.Bundle
import android.os.IBinder
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
import io.hydrabox.core.model.OperationState
import io.hydrabox.core.projection.AppReadModel
import io.hydrabox.core.projection.DiagnosticsSummary
import io.hydrabox.core.projection.ScreenProjection
import io.hydrabox.ui.app.AppActions
import io.hydrabox.ui.app.HydraApp

/**
 * Composition root. Its only job is to combine the read models and hand them to the
 * projection: it holds no phase of its own, no timer, and no branch on runtime state.
 */
class RuntimeControlActivity : ComponentActivity() {
    private lateinit var store: AppStore
    private var transport: BinderRuntimeTransport? = null
    private var subscription: AutoCloseable? = null

    private var snapshot by mutableStateOf(stoppedSnapshot())
    private var revision by mutableStateOf(0)
    private var lastMessage by mutableStateOf<String?>(null)

    private val permission = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK) launch()
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            binder ?: return
            BinderRuntimeTransport(binder).let { bound ->
                transport = bound
                snapshot = runCatching { bound.snapshot() }.getOrElse { stoppedSnapshot() }
                subscription = runCatching {
                    bound.subscribe { event -> (event as? RuntimeEvent.Snapshot)?.let { snapshot = it.snapshot } }
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
            val model = readModel()
            HydraApp(
                state = ScreenProjection.project(model),
                message = lastMessage,
                actions = actions(),
            )
        }
    }

    override fun onDestroy() {
        runCatching { subscription?.close() }
        runCatching { unbindService(connection) }
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
                recentEvents = listOf(
                    "runtime state: ${snapshot.state.name.lowercase()}",
                    "core version: ${BuildConfig.HYDRACORE_VERSION}",
                    "selected outbound: ${store.selectedTag() ?: "none"}",
                ),
                exportState = "idle",
            ),
            subscriptionOperation = OperationState.Idle,
            backupOperation = OperationState.Idle,
            legalAccepted = settings.acceptedLegalAtMillis != null,
        )
    }

    private fun actions() = AppActions(
        onStart = ::prepareAndStart,
        onStop = { send(RuntimeCommand.Stop) },
        onRetry = ::prepareAndStart,
        onAddSubscription = { name, source -> mutate { store.addSubscription(name, source) } },
        onRemoveSubscription = { id -> mutate { store.removeSubscription(id) } },
        onSelectProxy = { tag ->
            mutate {
                store.select(tag)
                if (snapshot.state == RuntimeState.RUNNING) send(RuntimeCommand.SelectOutbound("select", tag))
            }
        },
        onAcceptLegal = {
            mutate { store.saveSettings(store.settings().copy(acceptedLegalVersion = "1", acceptedLegalAtMillis = System.currentTimeMillis())) }
        },
        onSetMtu = { mtu -> mutate { store.saveSettings(store.settings().copy(vpnMtu = mtu)) } },
        onSetProxyDns = { value -> mutate { store.saveSettings(store.settings().copy(dnsProxyResolver = value)) } },
        onSetDirectDns = { value -> mutate { store.saveSettings(store.settings().copy(dnsDirectResolver = value)) } },
        onToggleNotification = {
            mutate { store.saveSettings(store.settings().let { it.copy(statusNotificationEnabled = !it.statusNotificationEnabled) }) }
        },
    )

    private fun mutate(block: () -> Unit) {
        lastMessage = runCatching(block).exceptionOrNull()?.message?.let { "Failed: $it" }
        revision += 1
    }

    private fun prepareAndStart() {
        if (store.generateConfig() == null) {
            lastMessage = "Add a subscription before connecting"
            return
        }
        VpnService.prepare(this)?.let(permission::launch) ?: launch()
    }

    private fun launch() {
        lastMessage = null
        startForegroundService(Intent(this, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
    }

    private fun send(command: RuntimeCommand) {
        val bound = transport
        if (bound == null) {
            lastMessage = "Runtime is not bound yet"
            return
        }
        runCatching { bound.submit(command) }.exceptionOrNull()?.let { lastMessage = "Failed: ${it.message}" }
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
