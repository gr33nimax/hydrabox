package io.hydrabox.ui.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
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
import io.hydrabox.ui.design.UiAction
import io.hydrabox.ui.design.UiActionRow
import io.hydrabox.ui.design.UiCard
import io.hydrabox.ui.design.UiSection
import io.hydrabox.ui.design.UiTokens

/** Everything the screens can ask the platform to do. No screen performs an action itself. */
data class AppActions(
    val onStart: () -> Unit = {},
    val onStop: () -> Unit = {},
    val onRetry: () -> Unit = {},
    val onReload: () -> Unit = {},
    val onAddSubscription: (String, String) -> Unit = { _, _ -> },
    val onRefreshSubscription: (String) -> Unit = {},
    val onRenameSubscription: (String, String) -> Unit = { _, _ -> },
    val onRemoveSubscription: (String) -> Unit = {},
    val onSelectProxy: (String) -> Unit = {},
    val onAcceptLegal: () -> Unit = {},
    val onSetMtu: (Int) -> Unit = {},
    val onSetProxyDns: (String) -> Unit = {},
    val onSetDirectDns: (String) -> Unit = {},
    val onSetSplitPackages: (String) -> Unit = {},
    val onToggleNotification: () -> Unit = {},
    val onMeasure: () -> Unit = {},
    val onToggleApp: (String) -> Unit = {},
    val onLoadApps: () -> Unit = {},
)

private const val APP_LIST_LIMIT = 120

private enum class Destination(val label: String) {
    CONNECTION("Connect"),
    SUBSCRIPTIONS("Subscriptions"),
    PROXIES("Servers"),
    SETTINGS("Settings"),
    DIAGNOSTICS("Logs"),
}

@Composable
fun HydraApp(state: ScreenState, message: String? = null, actions: AppActions = AppActions()) {
    var destination by remember { mutableStateOf(Destination.CONNECTION) }
    HydraTheme {
        AdaptiveScaffold(
            title = "HydraBox",
            destinations = Destination.entries.map(Destination::label),
            selected = destination.ordinal,
            onSelect = { destination = Destination.entries[it] },
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(UiTokens.spacing * 2),
                modifier = Modifier.fillMaxWidth().padding(bottom = UiTokens.spacing * 3),
            ) {
                if (state.busy) LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                message?.let { Banner(it) }
                if (!state.legalAccepted) LegalGate(actions)
                when (destination) {
                    Destination.CONNECTION -> ConnectionScreen(state, actions) { destination = it }
                    Destination.SUBSCRIPTIONS -> SubscriptionsScreen(state, actions)
                    Destination.PROXIES -> ProxiesScreen(state, actions)
                    Destination.SETTINGS -> SettingsScreen(state, actions)
                    Destination.DIAGNOSTICS -> DiagnosticsScreen(state, actions)
                }
            }
        }
    }
}

@Composable
private fun Banner(text: String) {
    val failed = text.startsWith("Failed") || text.startsWith("VPN permission")
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (failed) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.secondaryContainer,
        ),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = if (failed) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onSecondaryContainer,
            modifier = Modifier.padding(UiTokens.spacing * 2),
        )
    }
}

@Composable
private fun LegalGate(actions: AppActions) = UiSection("Before you start") {
    UiCard("Review and accept the terms", "Connecting stays disabled until you accept.")
    UiActionRow(primary = "Accept", primaryEnabled = true, onPrimary = actions.onAcceptLegal)
}

@Composable
private fun ConnectionScreen(state: ScreenState, actions: AppActions, navigate: (Destination) -> Unit) {
    val label = when (state.phase) {
        ScreenPhase.DISCONNECTED -> "Disconnected"
        ScreenPhase.CONNECTING -> "Connecting"
        ScreenPhase.CONNECTED -> "Connected"
        ScreenPhase.DISCONNECTING -> "Disconnecting"
        ScreenPhase.ERROR -> "Connection failed"
    }
    val tone = when (state.phase) {
        ScreenPhase.CONNECTED -> MaterialTheme.colorScheme.primaryContainer
        ScreenPhase.ERROR -> MaterialTheme.colorScheme.errorContainer
        else -> MaterialTheme.colorScheme.surfaceContainerHigh
    }
    Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = tone)) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(UiTokens.spacing * 3),
            verticalArrangement = Arrangement.spacedBy(UiTokens.spacing),
        ) {
            Text(label, style = MaterialTheme.typography.headlineMedium)
            Text(
                state.errorCode ?: state.activeOutbound ?: "No server selected",
                style = MaterialTheme.typography.bodyLarge,
            )
            state.transport.takeIf(String::isNotEmpty)?.let {
                Text("Transport: $it", style = MaterialTheme.typography.bodySmall)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(UiTokens.spacing), modifier = Modifier.padding(top = UiTokens.spacing)) {
                UiAction(
                    label = if (state.canStop) "Disconnect" else "Connect",
                    enabled = (state.canStop || state.canStart) && !state.busy,
                    onClick = { if (state.canStop) actions.onStop() else actions.onStart() },
                )
                if (state.canRetry) UiAction("Retry", enabled = true, secondary = true, onClick = actions.onRetry)
                if (state.phase == ScreenPhase.CONNECTED) {
                    UiAction("Reload", enabled = true, secondary = true, onClick = actions.onReload)
                }
            }
        }
    }
    UiSection("Route") {
        UiCard(
            state.activeOutbound ?: "Pick a server",
            "${state.proxies.size} available — tap to choose",
            onClick = { navigate(Destination.PROXIES) },
        )
        UiCard(
            state.subscriptions.firstOrNull()?.name ?: "No subscription yet",
            if (state.subscriptions.isEmpty()) "Tap to add one" else "${state.subscriptions.size} stored — tap to manage",
            onClick = { navigate(Destination.SUBSCRIPTIONS) },
        )
    }
    if (state.traffic.available) {
        UiSection("Traffic") {
            UiCard("Download  ${state.traffic.downlink}", "total ${state.traffic.downlinkTotal}")
            UiCard("Upload  ${state.traffic.uplink}", "total ${state.traffic.uplinkTotal}")
            UiCard("Open connections", state.traffic.connections.toString())
        }
    }
}

@Composable
private fun SubscriptionsScreen(state: ScreenState, actions: AppActions) {
    var name by remember { mutableStateOf("") }
    var source by remember { mutableStateOf("") }
    UiSection("Add a subscription") {
        OutlinedTextField(
            value = source,
            onValueChange = { source = it },
            label = { Text("Subscription URL (keep its #hydra-key), links, or a sing-box document") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 3,
        )
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Name (optional)") },
            modifier = Modifier.fillMaxWidth().padding(top = UiTokens.spacing),
            singleLine = true,
        )
        UiActionRow(
            primary = "Add",
            primaryEnabled = source.isNotBlank() && !state.busy,
            onPrimary = {
                actions.onAddSubscription(name, source)
                name = ""
                source = ""
            },
        )
    }
    UiSection("Stored") {
        if (state.subscriptions.isEmpty()) {
            UiCard(
                "Nothing stored yet",
                "A https:// Hydra subscription (encrypted ones included, paste the whole URL with its #hydra-key), a sing-box document, or vless / trojan / ss / socks links.",
            )
        } else {
            state.subscriptions.forEach { subscription ->
                var editing by remember(subscription.id) { mutableStateOf(false) }
                var draft by remember(subscription.id) { mutableStateOf(subscription.name) }
                UiCard(
                    subscription.name,
                    listOfNotNull(
                        "${subscription.outboundCount} servers",
                        "encrypted".takeIf { subscription.encrypted },
                        subscription.expiresAt?.let { "until $it" },
                        subscription.problem,
                    ).joinToString(" · "),
                    onClick = { editing = !editing },
                )
                if (editing) {
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        label = { Text("Name") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(UiTokens.spacing)) {
                        UiAction("Rename", enabled = draft.isNotBlank()) {
                            actions.onRenameSubscription(subscription.id, draft)
                            editing = false
                        }
                        UiAction("Refresh", enabled = !state.busy, secondary = true) {
                            actions.onRefreshSubscription(subscription.id)
                        }
                        UiAction("Remove", enabled = !state.busy, secondary = true) {
                            actions.onRemoveSubscription(subscription.id)
                            editing = false
                        }
                    }
                }
            }
        }
        state.subscriptionOperation?.let { UiCard("Last operation", it) }
    }
}

@Composable
private fun ProxiesScreen(state: ScreenState, actions: AppActions) {
    var filter by remember { mutableStateOf("") }
    UiSection("Servers") {
        if (state.proxies.isEmpty()) {
            UiCard("No servers", "Add a subscription first.")
            return@UiSection
        }
        OutlinedTextField(
            value = filter,
            onValueChange = { filter = it },
            label = { Text("Filter") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
        )
        val visible = state.proxies.filter { filter.isBlank() || it.tag.contains(filter, ignoreCase = true) }
        visible.filter { it.subscriptionId.isEmpty() }.forEach { proxy ->
            UiCard(
                if (proxy.selected) "Automatic  ✓" else "Automatic",
                listOfNotNull("lowest latency", proxy.latencyMillis?.let { "$it ms" }).joinToString(" — "),
                onClick = { actions.onSelectProxy(proxy.tag) },
            )
        }
        UiActionRow(
            primary = "Measure now",
            primaryEnabled = state.canStop,
            onPrimary = actions.onMeasure,
        )
        state.subscriptions.forEach { subscription ->
            val group = visible.filter { it.subscriptionId == subscription.id }
            if (group.isEmpty()) return@forEach
            Text(
                subscription.name,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(top = UiTokens.spacing),
            )
            group.forEach { proxy ->
                UiCard(
                    if (proxy.selected) "${proxy.tag}  ✓" else proxy.tag,
                    listOfNotNull(proxy.type, proxy.latencyMillis?.let { "$it ms" }).joinToString(" — "),
                    onClick = { actions.onSelectProxy(proxy.tag) },
                )
            }
        }
        val orphans = visible.filter { proxy ->
            proxy.subscriptionId.isNotEmpty() && state.subscriptions.none { it.id == proxy.subscriptionId }
        }
        orphans.forEach { proxy ->
            UiCard(proxy.tag, proxy.type, onClick = { actions.onSelectProxy(proxy.tag) })
        }
    }
}

@Composable
private fun SettingsScreen(state: ScreenState, actions: AppActions) {
    val settings = state.settings
    var proxyDns by remember(settings?.proxyDnsResolver) { mutableStateOf(settings?.proxyDnsResolver.orEmpty()) }
    var directDns by remember(settings?.directDnsResolver) { mutableStateOf(settings?.directDnsResolver.orEmpty()) }
    var mtu by remember(settings?.vpnMtu) { mutableStateOf(settings?.vpnMtu?.toString().orEmpty()) }
    var packages by remember { mutableStateOf("") }
    UiSection("General") {
        UiCard("Performance mode", settings?.performanceMode ?: "unknown")
        UiCard(
            "Status notification",
            if (settings?.statusNotificationEnabled == true) "on — tap to turn off" else "off — tap to turn on",
            onClick = actions.onToggleNotification,
        )
    }
    UiSection("DNS") {
        OutlinedTextField(
            value = proxyDns,
            onValueChange = { proxyDns = it },
            label = { Text("Resolver through the tunnel") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
        )
        OutlinedTextField(
            value = directDns,
            onValueChange = { directDns = it },
            label = { Text("Direct resolver") },
            modifier = Modifier.fillMaxWidth().padding(top = UiTokens.spacing),
            singleLine = true,
        )
        UiActionRow(
            primary = "Save resolvers",
            primaryEnabled = proxyDns.isNotBlank() && directDns.isNotBlank(),
            onPrimary = {
                actions.onSetProxyDns(proxyDns.trim())
                actions.onSetDirectDns(directDns.trim())
            },
        )
        UiCard("Until the tunnel is ready DNS refuses rather than answering outside it")
    }
    UiSection("Tunnel") {
        OutlinedTextField(
            value = mtu,
            onValueChange = { mtu = it.filter(Char::isDigit) },
            label = { Text("MTU") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
        )
        UiActionRow(
            primary = "Save MTU",
            primaryEnabled = mtu.toIntOrNull()?.let { it in 1280..9000 } == true,
            onPrimary = { mtu.toIntOrNull()?.let(actions.onSetMtu) },
        )
        UiCard("Outside the tunnel", "${settings?.splitRoutingPackageCount ?: 0} apps")
    }
    UiSection("Apps outside the tunnel") {
        if (state.apps.isEmpty()) {
            UiCard(
                "Choose apps",
                "Tap to list installed apps; the ones you pick bypass the tunnel.",
                onClick = actions.onLoadApps,
            )
        } else {
            OutlinedTextField(
                value = packages,
                onValueChange = { packages = it },
                label = { Text("Filter apps") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            state.apps
                .filter { packages.isBlank() || it.label.contains(packages, ignoreCase = true) || it.packageName.contains(packages, ignoreCase = true) }
                .take(APP_LIST_LIMIT)
                .forEach { app ->
                    UiCard(
                        if (app.excluded) "${app.label}  ✓" else app.label,
                        app.packageName,
                        onClick = { actions.onToggleApp(app.packageName) },
                    )
                }
        }
    }
    UiSection("About") {
        UiCard("HydraBox", "2.0.0 alpha")
        UiCard("Backup", state.backupOperation ?: "versioned schema, export arrives with the next task")
    }
}

@Composable
private fun DiagnosticsScreen(state: ScreenState, actions: AppActions) = UiSection("Diagnostics") {
    val diagnostics = state.diagnostics
    diagnostics?.recentEvents?.forEach { UiCard(it) }
    UiActionRow(primary = "Reload runtime", primaryEnabled = state.canStop, onPrimary = actions.onReload)
    UiCard("Log level", diagnostics?.level ?: "unknown")
    UiCard("Export", diagnostics?.exportState ?: "idle")
}
