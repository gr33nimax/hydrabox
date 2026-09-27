package io.hydrabox.ui.app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.hydrabox.core.projection.Connection
import io.hydrabox.core.projection.ErrorMessage
import io.hydrabox.core.projection.MANUAL_SOURCE_ID
import io.hydrabox.core.projection.PrimaryAction
import io.hydrabox.core.projection.ScreenState
import io.hydrabox.core.projection.ServerRef
import io.hydrabox.core.projection.SettingsSummary
import io.hydrabox.core.projection.SubscriptionSummary
import io.hydrabox.core.projection.primaryAction
import io.hydrabox.core.projection.server
import io.hydrabox.ui.app.resources.*
import io.hydrabox.ui.app.resources.Res
import io.hydrabox.ui.design.ConnectionControl
import io.hydrabox.ui.design.ConnectionVisualState
import io.hydrabox.ui.design.ControlSignal
import io.hydrabox.ui.design.ControlTone
import io.hydrabox.ui.design.EmptyState
import io.hydrabox.ui.design.FactRow
import io.hydrabox.ui.design.HydraIcons
import io.hydrabox.ui.design.RefreshButton
import io.hydrabox.ui.design.SecondaryAction
import io.hydrabox.ui.design.SectionGroup
import io.hydrabox.ui.design.TonalAction
import io.hydrabox.ui.design.UiTokens
import org.jetbrains.compose.resources.stringResource

/**
 * The cockpit.
 *
 * One instrument in the middle that says what the tunnel is doing and, by the speed of its
 * ring, how much it is carrying; four readings under it, each the shortest true answer to a
 * question a person actually has вЂ” where does this come out, through what, what does the
 * plan still allow, what is left outside the tunnel. The subscription owns the top line
 * because it is the thing that expires.
 *
 * Nothing here repeats itself: a fact appears on this screen once, and the row it appears in
 * opens the screen that holds the rest of it.
 */
@Composable
fun HomeScreen(
    state: ScreenState,
    actions: AppActions,
    onOpenServers: () -> Unit,
    onOpenTraffic: () -> Unit,
    onAddSource: () -> Unit,
    onOpenSources: () -> Unit,
    onOpenMode: () -> Unit,
    width: Dp,
    height: Dp,
) {
    if (state.connection == Connection.NeedsSubscription || state.connection == Connection.NeedsServers) {
        Column(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = height)
                    .padding(horizontal = UiTokens.spacing * 2, vertical = UiTokens.spacing * 2),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(UiTokens.spacing * 2, Alignment.CenterVertically),
        ) {
            if (state.connection == Connection.NeedsSubscription) {
                EmptyState(
                    icon = HydraIcons.Subscription,
                    title = stringResource(Res.string.home_empty_title),
                    body = stringResource(Res.string.home_empty_body),
                    primaryLabel = stringResource(Res.string.action_add_subscription),
                    onPrimary = onAddSource,
                )
            } else {
                EmptyState(
                    icon = HydraIcons.Server,
                    title = stringResource(Res.string.home_no_servers_title),
                    body = stringResource(Res.string.home_no_servers_body),
                    primaryLabel = stringResource(Res.string.action_refresh_subscription),
                    onPrimary = { state.sources.firstOrNull()?.let { actions.onRefreshSource(it.id) } },
                )
            }
        }
        return
    }
    val source = planSourceForHome(state)
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .heightIn(min = height)
                .padding(horizontal = UiTokens.spacing * 2, vertical = UiTokens.spacing * 1.5f),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        source?.let { plan ->
            PlanHeader(
                source = plan,
                busy = state.busy.source,
                onOpen = onOpenSources,
                onRefresh = { actions.onRefreshSource(plan.id) },
            )
        }
        Instrument(state, actions, onOpenServers, onOpenTraffic, source, controlSize(width, height))
        Readings(state, actions, source, onOpenServers, onOpenSources, onOpenMode)
    }
}

/**
 * How big the aperture is allowed to be: a share of the width, capped by a share of the
 * height, so the proportion survives a short screen and a tablet alike. It carries the state
 * words inside it now, which is why it is allowed more of the width than a bare disc was.
 */
internal fun planSourceForHome(state: ScreenState): SubscriptionSummary? {
    val server = state.connection.server ?: return state.sources.firstOrNull()
    if (server.sourceId == MANUAL_SOURCE_ID) return null
    return state.sources.firstOrNull { it.id == server.sourceId } ?: state.sources.firstOrNull()
}

private fun controlSize(
    width: Dp,
    height: Dp,
): Dp = minOf(width * 0.68f, height * 0.36f).coerceIn(168.dp, 268.dp)

/**
 * The plan, on the top line, because it is the only thing on this screen that runs out. The
 * name opens what it is made of; the button beside it asks the provider again and turns while
 * it does.
 */
@Composable
private fun PlanHeader(
    source: SubscriptionSummary?,
    busy: Boolean,
    onOpen: () -> Unit,
    onRefresh: () -> Unit,
) = Row(
    modifier = Modifier.fillMaxWidth(),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(UiTokens.spacing),
) {
    Column(
        modifier = Modifier.weight(1f).clickable(onClick = onOpen).padding(vertical = UiTokens.spacing / 2),
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        Text(
            source?.name ?: stringResource(Res.string.sources_title),
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        source?.updatedAt?.let {
            Text(
                stringResource(Res.string.sources_updated, it),
                style = UiTokens.figures(MaterialTheme.typography.labelMedium),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
        }
    }
    RefreshButton(
        busy = busy,
        contentDescription = stringResource(Res.string.action_refresh_subscription),
        onClick = onRefresh,
    )
}

/** The aperture and the words that belong inside it, and nothing else in the middle. */
@Composable
private fun Instrument(
    state: ScreenState,
    actions: AppActions,
    onOpenServers: () -> Unit,
    onOpenTraffic: () -> Unit,
    source: SubscriptionSummary?,
    size: Dp,
) {
    val connection = state.connection
    val displayedConnection = state.displayedConnection
    val traffic = (displayedConnection as? Connection.Connected)?.traffic?.takeIf { it.available }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(UiTokens.spacing),
        modifier = Modifier.padding(vertical = UiTokens.spacing * 2),
    ) {
        ConnectionControl(
            tone = displayedConnection.tone(),
            visualState = displayedConnection.visualState(),
            enabled = apertureEnabled(connection),
            contentDescription = stringResource(connection.actionLabel()),
            stateDescription = connectionTitle(displayedConnection),
            onClick = { dispatchHomeAction(connection, source?.id, actions, onOpenServers) },
            size = size,
            // The ring is fed the measurements rather than a decorative phase: rates for the
            // speed it turns at, the quota for the arc on its outer track.
            signal =
                ControlSignal(
                    downRate = traffic?.downlinkRate ?: 0L,
                    upRate = traffic?.uplinkRate ?: 0L,
                    quota = source?.quota,
                ),
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        ) {
            Text(
                shortState(displayedConnection),
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        traffic?.let {
            Text(
                stringResource(Res.string.home_rates, it.downlink, it.uplink),
                style = UiTokens.figures(MaterialTheme.typography.bodyMedium),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.clickable(onClick = onOpenTraffic),
            )
        }
        connectionHint(displayedConnection)?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        SecondaryActionRow(connection, actions, onOpenServers)
    }
}

/**
 * The four readings.
 *
 * Each one is the answer to a question and the way to the screen that owns it: where the
 * traffic goes out and through what, what the plan still allows, and what is not in the
 * tunnel at all. A reading is never a fact the aperture already showed.
 */
@Composable
private fun Readings(
    state: ScreenState,
    actions: AppActions,
    source: SubscriptionSummary?,
    onOpenServers: () -> Unit,
    onOpenSources: () -> Unit,
    onOpenMode: () -> Unit,
) {
    val server = state.connection.server
    SectionGroup {
        FactRow(
            label = stringResource(Res.string.home_row_route),
            value = server?.let { serverName(it) } ?: stringResource(Res.string.home_server_none),
            detail = serverSupportingLine(server),
            onClick = onOpenServers,
        )
        FactRow(
            label = stringResource(Res.string.home_row_exit),
            value = exitValue(state),
            detail =
                state.exit.countryCode?.let { code ->
                    listOfNotNull(state.exit.flag, code).joinToString(" ")
                },
            trailingIcon = HydraIcons.Refresh,
            // Asking again is the only thing this row can do that the screen cannot: an address
            // that was true a network ago is worth re-checking.
            onClick = actions.onRefreshExit,
        )
        source?.let { plan ->
            FactRow(
                label = stringResource(Res.string.home_row_plan),
                value = planAllowance(plan),
                detail = planTerm(plan),
                accent = plan.problem?.let { MaterialTheme.colorScheme.error },
                onClick = onOpenSources,
            )
        }
        FactRow(
            label = stringResource(Res.string.home_row_mode),
            value = modeValue(state.settings),
            detail = modeDetail(state.settings),
            onClick = onOpenMode,
        )
    }
}

/** The address the traffic comes out of, or the honest name for not knowing it. */
@Composable
private fun exitValue(state: ScreenState): String {
    val connected = state.connection is Connection.Connected
    return when {
        connected && state.exit.checking && state.exit.address == null -> {
            stringResource(Res.string.home_exit_checking)
        }

        state.exit.address != null && connected -> {
            state.exit.address!!
        }

        else -> {
            stringResource(Res.string.home_exit_unknown)
        }
    }
}

/** Which of the two ways of carrying the traffic is in force: a system tunnel, or a port. */
@Composable
private fun modeValue(settings: SettingsSummary?): String =
    stringResource(
        if (settings?.proxyOnly == true) Res.string.home_mode_proxy else Res.string.home_mode_vpn,
    )

/**
 * What the mode implies, and only when it is not the default. A local proxy is useless without
 * the address to point at, so the row carries it вЂ” which is also why the line under the
 * aperture no longer repeats it. A tunnel with nothing excluded from it has nothing to add:
 * the second line stays empty rather than restating the mode in other words.
 */
@Composable
private fun modeDetail(settings: SettingsSummary?): String? {
    if (settings?.proxyOnly == true) {
        val listen = if (settings.proxyAllowLan) "0.0.0.0" else "127.0.0.1"
        return listen + ":" + settings.proxyPort
    }
    val outside = settings?.appsOutsideTunnel ?: 0
    return outside.takeIf { it > 0 }?.let { stringResource(Res.string.home_mode_outside, it) }
}

/** The state in as few words as fit inside the aperture. The hint under it says what to do. */
@Composable
private fun shortState(connection: Connection): String =
    when (connection) {
        is Connection.Connected -> {
            stringResource(Res.string.state_connected)
        }

        is Connection.Reconnecting -> {
            stringResource(Res.string.state_short_reconnecting)
        }

        is Connection.Stopped -> {
            shortError(connection.presentation.message)
        }

        is Connection.Unreachable -> {
            shortError(connection.presentation.message)
        }

        else -> {
            connectionTitle(connection)
        }
    }

@Composable
private fun shortError(message: ErrorMessage): String =
    stringResource(
        when (message) {
            ErrorMessage.NO_INTERNET -> Res.string.trouble_short_no_internet
            ErrorMessage.SERVER_UNREACHABLE -> Res.string.trouble_short_server_unreachable
            ErrorMessage.SUBSCRIPTION_UNAVAILABLE -> Res.string.trouble_short_subscription
            ErrorMessage.CONFIG_REJECTED -> Res.string.trouble_short_config
            ErrorMessage.PERMISSION_REQUIRED -> Res.string.trouble_short_permission
            ErrorMessage.CONNECTION_LOST -> Res.string.trouble_short_connection_lost
            ErrorMessage.UNKNOWN -> Res.string.trouble_short_unknown
        },
    )

/** The second action, when a state has one. Never two primary buttons on one screen. */
@Composable
private fun SecondaryActionRow(
    connection: Connection,
    actions: AppActions,
    onOpenServers: () -> Unit,
) {
    when {
        connection is Connection.Stopped && connection.presentation.message == ErrorMessage.PERMISSION_REQUIRED -> {
            TonalAction(stringResource(Res.string.action_grant_permission), onClick = actions.onGrantPermission)
        }

        connection.primaryAction == PrimaryAction.CHOOSE_SERVER -> {
            TonalAction(stringResource(Res.string.action_choose_server), onClick = onOpenServers)
        }

        connection is Connection.Connecting || connection is Connection.Reconnecting -> {
            SecondaryAction(stringResource(Res.string.action_cancel), onClick = actions.onDisconnect)
        }

        else -> {
            Unit
        }
    }
}

/**
 * Whether the central control takes a press at all.
 *
 * While a start or a recovery is in flight the same control's own action is Cancel, so the press
 * that asked for the tunnel would take it back if it arrived again a moment later — which is what
 * a person tapping twice does. The aperture is closed for that window, and the cancel below it
 * stays the only way out.
 */
internal fun apertureEnabled(connection: Connection): Boolean =
    when (connection) {
        is Connection.Connecting, is Connection.Reconnecting -> false
        else -> connection.primaryAction != PrimaryAction.NONE
    }

internal fun dispatchHomeAction(
    connection: Connection,
    sourceId: String?,
    actions: AppActions,
    onOpenServers: () -> Unit,
) {
    when (connection.primaryAction) {
        PrimaryAction.CONNECT, PrimaryAction.RETRY -> actions.onConnect()
        PrimaryAction.DISCONNECT, PrimaryAction.CANCEL -> actions.onDisconnect()
        PrimaryAction.CHOOSE_SERVER -> onOpenServers()
        PrimaryAction.REFRESH_SOURCE -> sourceId?.let(actions.onRefreshSource)
        PrimaryAction.ADD_SUBSCRIPTION, PrimaryAction.NONE -> Unit
    }
}

private fun Connection.actionLabel() =
    when (primaryAction) {
        PrimaryAction.CONNECT, PrimaryAction.RETRY -> Res.string.control_connect
        PrimaryAction.DISCONNECT -> Res.string.control_disconnect
        PrimaryAction.CANCEL -> Res.string.action_cancel
        PrimaryAction.CHOOSE_SERVER -> Res.string.action_choose_server
        PrimaryAction.REFRESH_SOURCE -> Res.string.action_refresh_subscription
        PrimaryAction.ADD_SUBSCRIPTION, PrimaryAction.NONE -> Res.string.control_working
    }

private fun Connection.tone(): ControlTone =
    when (this) {
        is Connection.Connected -> ControlTone.ACTIVE
        is Connection.Connecting, is Connection.Reconnecting, Connection.Disconnecting -> ControlTone.BUSY
        is Connection.Stopped -> ControlTone.TROUBLE
        else -> ControlTone.IDLE
    }

private fun Connection.visualState(): ConnectionVisualState =
    when (this) {
        is Connection.Connected -> ConnectionVisualState.CONNECTED
        is Connection.Connecting -> ConnectionVisualState.CONNECTING
        is Connection.Reconnecting -> ConnectionVisualState.RECONNECTING
        Connection.Disconnecting -> ConnectionVisualState.DISCONNECTING
        else -> ConnectionVisualState.DISCONNECTED
    }
