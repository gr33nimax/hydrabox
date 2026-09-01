package io.hydrabox.core.projection

import io.hydrabox.core.contract.RuntimeSnapshot
import io.hydrabox.core.contract.RuntimeState
import io.hydrabox.core.model.OperationState

enum class ScreenPhase { DISCONNECTED, CONNECTING, CONNECTED, DISCONNECTING, ERROR }

/** One stored subscription, as the screens need it. */
data class SubscriptionSummary(
    val id: String,
    val name: String,
    val outboundCount: Int,
    val updatedAtMillis: Long,
)

/**
 * One selectable outbound. The configured half — tag and type — comes from the
 * subscription; [selected] and [latencyMillis] come from the runtime snapshot. The two
 * halves meet here and nowhere else.
 */
data class ProxyEntry(
    val tag: String,
    val type: String,
    val subscriptionId: String,
    val selected: Boolean,
    val latencyMillis: Int? = null,
)

/** Settings as shown, already resolved to display strings by the projection. */
data class SettingsSummary(
    val performanceMode: String,
    val proxyDnsResolver: String,
    val directDnsResolver: String,
    val vpnMtu: Int,
    val splitRoutingPackageCount: Int,
    val statusNotificationEnabled: Boolean,
)

data class DiagnosticsSummary(
    val level: String,
    val recentEvents: List<String>,
    val exportState: String,
)

data class TrafficSummary(
    val available: Boolean,
    val uplink: String = "0 B/s",
    val downlink: String = "0 B/s",
    val uplinkTotal: String = "0 B",
    val downlinkTotal: String = "0 B",
    val connections: Int = 0,
)

/** Bytes as a person reads them. Formatting belongs here, not in a composable. */
internal fun formatBytes(value: Long, suffix: String): String {
    val units = listOf("B", "KiB", "MiB", "GiB", "TiB")
    var amount = value.toDouble()
    var unit = 0
    while (amount >= 1024 && unit < units.lastIndex) {
        amount /= 1024
        unit += 1
    }
    val rendered = if (unit == 0) amount.toLong().toString() else {
        val scaled = (amount * 10).toLong()
        "${scaled / 10}.${scaled % 10}"
    }
    return "$rendered ${units[unit]}$suffix"
}

data class ScreenState(
    val phase: ScreenPhase,
    val canStart: Boolean,
    val canStop: Boolean,
    val canRetry: Boolean,
    val errorCode: String?,
    val activeOutbound: String? = null,
    val subscriptions: List<SubscriptionSummary> = emptyList(),
    val proxies: List<ProxyEntry> = emptyList(),
    val settings: SettingsSummary? = null,
    val diagnostics: DiagnosticsSummary? = null,
    val traffic: TrafficSummary = TrafficSummary(available = false),
    val subscriptionOperation: String? = null,
    val backupOperation: String? = null,
    val legalAccepted: Boolean = true,
    val transport: String = "",
    val busy: Boolean = false,
) {
    val hasProxies get() = proxies.isNotEmpty()
}

/** Everything the projection reads, one field per owning subsystem. */
data class AppReadModel(
    val runtime: RuntimeSnapshot,
    val subscriptions: List<SubscriptionSummary> = emptyList(),
    val proxies: List<ProxyEntry> = emptyList(),
    val settings: SettingsSummary? = null,
    val diagnostics: DiagnosticsSummary? = null,
    val subscriptionOperation: OperationState<Unit> = OperationState.Idle,
    val backupOperation: OperationState<Unit> = OperationState.Idle,
    val legalAccepted: Boolean = true,
)

object ScreenProjection {
    fun project(snapshot: RuntimeSnapshot): ScreenState = project(AppReadModel(runtime = snapshot))

    fun project(model: AppReadModel): ScreenState {
        val snapshot = model.runtime
        val active = snapshot.selectedOutbounds.firstOrNull()?.outboundId
            ?: model.proxies.firstOrNull { it.selected }?.tag
        val latency = snapshot.latencies.associate { it.tag to it.delayMillis.takeIf { value -> value > 0 } }
        val base = when (snapshot.state) {
            RuntimeState.STOPPED -> Triple(ScreenPhase.DISCONNECTED, true, false)
            RuntimeState.STARTING, RuntimeState.RECOVERING -> Triple(ScreenPhase.CONNECTING, false, true)
            RuntimeState.RUNNING -> Triple(ScreenPhase.CONNECTED, false, true)
            RuntimeState.STOPPING -> Triple(ScreenPhase.DISCONNECTING, false, false)
            RuntimeState.FAILED -> Triple(ScreenPhase.ERROR, true, false)
        }
        return ScreenState(
            phase = base.first,
            canStart = base.second && model.legalAccepted,
            canStop = base.third,
            canRetry = snapshot.state == RuntimeState.FAILED && snapshot.lastFailure?.retryable == true,
            errorCode = snapshot.lastFailure?.code?.code.takeIf { snapshot.state == RuntimeState.FAILED },
            activeOutbound = active,
            subscriptions = model.subscriptions,
            proxies = model.proxies.map { entry ->
                entry.copy(latencyMillis = latency[entry.tag] ?: entry.latencyMillis)
            },
            settings = model.settings,
            diagnostics = model.diagnostics,
            traffic = snapshot.traffic.let { counters ->
                TrafficSummary(
                    available = counters.available && snapshot.state == RuntimeState.RUNNING,
                    uplink = formatBytes(counters.uplink, "/s"),
                    downlink = formatBytes(counters.downlink, "/s"),
                    uplinkTotal = formatBytes(counters.uplinkTotal, ""),
                    downlinkTotal = formatBytes(counters.downlinkTotal, ""),
                    connections = counters.connectionsOut,
                )
            },
            subscriptionOperation = label(model.subscriptionOperation),
            backupOperation = label(model.backupOperation),
            legalAccepted = model.legalAccepted,
            transport = snapshot.transportHealth.let { health ->
                if (!health.applicable) "not applicable" else "${health.state.name.lowercase()}, ${health.activeLanes} lanes"
            },
            busy = model.subscriptionOperation == OperationState.Running || model.backupOperation == OperationState.Running,
        )
    }

    private fun label(state: OperationState<*>): String? = when (state) {
        OperationState.Idle -> null
        OperationState.Running -> "in progress"
        is OperationState.Succeeded -> "done"
        is OperationState.Failed -> state.error.code
    }
}
