package io.hydrabox.ui.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import io.hydrabox.core.projection.ScreenPhase
import io.hydrabox.core.projection.ScreenState
import io.hydrabox.ui.design.AdaptiveScaffold
import io.hydrabox.ui.design.HydraTheme
import io.hydrabox.ui.design.UiActionRow
import io.hydrabox.ui.design.UiCard
import io.hydrabox.ui.design.UiSection
import io.hydrabox.ui.design.UiTokens

/** Everything the screens can ask the platform to do. No screen performs an action itself. */
data class AppActions(
    val onStart: () -> Unit = {},
    val onStop: () -> Unit = {},
    val onRetry: () -> Unit = {},
    val onAddSubscription: (String, String) -> Unit = { _, _ -> },
    val onRemoveSubscription: (String) -> Unit = {},
    val onSelectProxy: (String) -> Unit = {},
    val onAcceptLegal: () -> Unit = {},
    val onSetMtu: (Int) -> Unit = {},
    val onSetProxyDns: (String) -> Unit = {},
    val onSetDirectDns: (String) -> Unit = {},
    val onToggleNotification: () -> Unit = {},
)

private enum class Destination(val label: String) {
    CONNECTION("Connect"),
    TRAFFIC("Traffic"),
    SUBSCRIPTIONS("Subs"),
    PROXIES("Proxies"),
    SETTINGS("Settings"),
    DIAGNOSTICS("Logs"),
}

@Composable
fun HydraApp(
    state: ScreenState,
    message: String? = null,
    actions: AppActions = AppActions(),
) {
    var destination by remember { mutableStateOf(Destination.CONNECTION) }
    HydraTheme {
        AdaptiveScaffold(
            title = "HydraBox",
            destinations = Destination.entries.map(Destination::label),
            selected = destination.ordinal,
            onSelect = { destination = Destination.entries[it] },
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(UiTokens.spacing * 2), modifier = Modifier.fillMaxWidth()) {
                message?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error) }
                if (!state.legalAccepted) LegalGate(actions)
                when (destination) {
                    Destination.CONNECTION -> ConnectionScreen(state, actions)
                    Destination.TRAFFIC -> TrafficScreen(state)
                    Destination.SUBSCRIPTIONS -> SubscriptionsScreen(state, actions)
                    Destination.PROXIES -> ProxiesScreen(state, actions)
                    Destination.SETTINGS -> SettingsScreen(state, actions)
                    Destination.DIAGNOSTICS -> DiagnosticsScreen(state)
                }
            }
        }
    }
}

@Composable
private fun LegalGate(actions: AppActions) = UiSection("Before you start") {
    UiCard("Review and accept the terms", "Connecting stays disabled until you accept.")
    UiActionRow(primary = "Accept", primaryEnabled = true, onPrimary = actions.onAcceptLegal)
}

@Composable
private fun ConnectionScreen(state: ScreenState, actions: AppActions) {
    val label = when (state.phase) {
        ScreenPhase.DISCONNECTED -> "Disconnected"
        ScreenPhase.CONNECTING -> "Connecting"
        ScreenPhase.CONNECTED -> "Connected"
        ScreenPhase.DISCONNECTING -> "Disconnecting"
        ScreenPhase.ERROR -> "Connection failed"
    }
    UiSection("Connection") {
        UiCard(label, state.errorCode)
        UiActionRow(
            primary = if (state.canStop) "Disconnect" else "Connect",
            primaryEnabled = state.canStop || state.canStart,
            secondary = if (state.canRetry) "Retry" else null,
            onPrimary = { if (state.canStop) actions.onStop() else actions.onStart() },
            onSecondary = actions.onRetry,
        )
    }
    UiSection("Active route") {
        UiCard(state.activeOutbound ?: "No proxy selected", "${state.proxies.size} available")
        UiCard(
            state.subscriptions.firstOrNull()?.name ?: "No subscription",
            state.subscriptions.size.takeIf { it > 1 }?.let { "$it subscriptions stored" },
        )
    }
}

@Composable
private fun TrafficScreen(state: ScreenState) = UiSection("Traffic dashboard") {
    if (state.traffic.available) {
        UiCard("Uplink", "${state.traffic.uplinkBytes} bytes")
        UiCard("Downlink", "${state.traffic.downlinkBytes} bytes")
        UiCard("Counters arrive from the core once it publishes them")
    } else {
        UiCard("Connect to view traffic")
    }
}

@Composable
private fun SubscriptionsScreen(state: ScreenState, actions: AppActions) {
    var name by remember { mutableStateOf("") }
    var source by remember { mutableStateOf("") }
    UiSection("Add a subscription") {
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Name (optional)") },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = source,
            onValueChange = { source = it },
            label = { Text("Share links, one per line") },
            modifier = Modifier.fillMaxWidth().padding(top = UiTokens.spacing),
            minLines = 3,
        )
        UiActionRow(
            primary = "Add",
            primaryEnabled = source.isNotBlank(),
            onPrimary = {
                actions.onAddSubscription(name, source)
                name = ""
                source = ""
            },
        )
    }
    UiSection("Stored subscriptions") {
        if (state.subscriptions.isEmpty()) {
            UiCard("No subscriptions", "Paste a vless://, trojan://, ss:// or socks:// link above.")
        } else {
            state.subscriptions.forEach { subscription ->
                UiCard(
                    subscription.name,
                    "${subscription.outboundCount} outbounds — tap to remove",
                    onClick = { actions.onRemoveSubscription(subscription.id) },
                )
            }
        }
        state.subscriptionOperation?.let { UiCard("Refresh", it) }
    }
}

@Composable
private fun ProxiesScreen(state: ScreenState, actions: AppActions) = UiSection("Proxies") {
    if (state.proxies.isEmpty()) {
        UiCard("No proxies", "Add a subscription first.")
    } else {
        state.proxies.forEach { proxy ->
            UiCard(
                proxy.tag,
                listOfNotNull(proxy.type, "selected".takeIf { proxy.selected }, proxy.latencyMillis?.let { "$it ms" })
                    .joinToString(" — "),
                onClick = { actions.onSelectProxy(proxy.tag) },
            )
        }
    }
}

@Composable
private fun SettingsScreen(state: ScreenState, actions: AppActions) {
    val settings = state.settings
    var proxyDns by remember(settings?.proxyDnsResolver) { mutableStateOf(settings?.proxyDnsResolver.orEmpty()) }
    var directDns by remember(settings?.directDnsResolver) { mutableStateOf(settings?.directDnsResolver.orEmpty()) }
    var mtu by remember(settings?.vpnMtu) { mutableStateOf(settings?.vpnMtu?.toString().orEmpty()) }
    UiSection("General") {
        UiCard("Performance mode", settings?.performanceMode ?: "unknown")
        UiCard(
            "Status notification",
            if (settings?.statusNotificationEnabled == true) "enabled — tap to disable" else "disabled — tap to enable",
            onClick = actions.onToggleNotification,
        )
    }
    UiSection("DNS") {
        OutlinedTextField(
            value = proxyDns,
            onValueChange = { proxyDns = it },
            label = { Text("Proxy resolver") },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = directDns,
            onValueChange = { directDns = it },
            label = { Text("Direct resolver") },
            modifier = Modifier.fillMaxWidth().padding(top = UiTokens.spacing),
        )
        UiActionRow(
            primary = "Save resolvers",
            primaryEnabled = proxyDns.isNotBlank() && directDns.isNotBlank(),
            onPrimary = {
                actions.onSetProxyDns(proxyDns.trim())
                actions.onSetDirectDns(directDns.trim())
            },
        )
        UiCard("Before the tunnel is ready DNS refuses rather than answering outside it")
    }
    UiSection("Inbound") {
        OutlinedTextField(
            value = mtu,
            onValueChange = { mtu = it.filter(Char::isDigit) },
            label = { Text("Tunnel MTU") },
            modifier = Modifier.fillMaxWidth(),
        )
        UiActionRow(
            primary = "Save MTU",
            primaryEnabled = mtu.toIntOrNull()?.let { it in 1280..9000 } == true,
            onPrimary = { mtu.toIntOrNull()?.let(actions.onSetMtu) },
        )
        UiCard("Split tunneling", "${settings?.splitRoutingPackageCount ?: 0} packages excluded")
    }
    UiSection("Backup and about") {
        UiCard("Export backup", state.backupOperation ?: "versioned schema")
        UiCard("About HydraBox", "2.0.0 alpha")
    }
}

@Composable
private fun DiagnosticsScreen(state: ScreenState) = UiSection("Logs and diagnostics") {
    val diagnostics = state.diagnostics
    UiCard("Level", diagnostics?.level ?: "unknown")
    diagnostics?.recentEvents?.forEach { UiCard(it) }
    UiCard("Export", diagnostics?.exportState ?: "idle")
}
