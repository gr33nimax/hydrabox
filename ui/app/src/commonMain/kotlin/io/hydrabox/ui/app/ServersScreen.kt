package io.hydrabox.ui.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import io.hydrabox.core.projection.Connection
import io.hydrabox.core.projection.ScreenState
import io.hydrabox.core.projection.ServerRef
import io.hydrabox.ui.app.resources.*
import io.hydrabox.ui.app.resources.Res
import io.hydrabox.ui.design.ActionRow
import io.hydrabox.ui.design.EmptyState
import io.hydrabox.ui.design.HydraField
import io.hydrabox.ui.design.HydraIcons
import io.hydrabox.ui.design.LoadingRows
import io.hydrabox.ui.design.SecondaryAction
import io.hydrabox.ui.design.SectionGroup
import io.hydrabox.ui.design.ServerRow
import io.hydrabox.ui.design.UiTokens
import io.hydrabox.ui.design.ValueRow
import io.hydrabox.ui.design.WarningStrip
import org.jetbrains.compose.resources.stringResource

/**
 * Choosing where to connect, and nothing else. Subscriptions are reached from here rather
 * than from the main navigation, because a person picks a server often and manages a
 * subscription almost never.
 */
@Composable
fun ServersScreen(
    state: ScreenState,
    actions: AppActions,
    onOpenSources: () -> Unit,
) {
    if (state.sources.isEmpty() && state.autoServer == null) {
        EmptyState(
            icon = HydraIcons.Server,
            title = stringResource(Res.string.servers_empty_title),
            body = stringResource(Res.string.servers_empty_body),
            primaryLabel = stringResource(Res.string.action_add_subscription),
            onPrimary = onOpenSources,
        )
        return
    }
    var filter by remember { mutableStateOf("") }
    var order by remember { mutableStateOf(ServerOrder.LISTED) }
    // Put away for this visit only: the list really is dated until the source refreshes, so a
    // dismissal that survived a restart would hide a true fact rather than an annoyance.
    var dismissedStale by remember { mutableStateOf<String?>(null) }
    val canMeasure = canMeasure(state.connection)
    val groups =
        remember(state.servers, filter, order) {
            state.servers
                .map { group ->
                    group to
                        order.arrange(
                            group.servers.filter {
                                filter.isBlank() || it.displayName.contains(filter, ignoreCase = true)
                            },
                        )
                }.filter { it.second.isNotEmpty() }
        }
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(UiTokens.spacing),
        modifier = Modifier.fillMaxWidth().padding(horizontal = UiTokens.spacing * 2),
    ) {
        item(key = "controls") {
            Column(verticalArrangement = Arrangement.spacedBy(UiTokens.spacing)) {
                SectionGroup {
                    ValueRow(
                        title = stringResource(Res.string.servers_sources),
                        value = stringResource(Res.string.sources_servers_count, state.serverCount),
                        leading = HydraIcons.Subscription,
                        onClick = onOpenSources,
                    )
                }
                // A failed refresh leaves the servers this source already contributed, so the
                // honest thing to say is that the list is dated — not that the app is broken.
                // The source screen still owns the failure itself.
                state.sources
                    .firstOrNull { it.problem != null && it.id != dismissedStale }
                    ?.let { source ->
                        WarningStrip(
                            text = stringResource(Res.string.servers_stale_list, source.name),
                            actionLabel = stringResource(Res.string.action_refresh),
                            onAction = { actions.onRefreshSource(source.id) },
                            dismissLabel = stringResource(Res.string.action_close),
                            onDismiss = { dismissedStale = source.id },
                        )
                    }
                state.autoServer?.let { auto ->
                    SectionGroup {
                        ServerRow(
                            name = serverName(auto),
                            detail = serverSupportingLine(auto),
                            selected = state.selectedServerId == auto.id || state.selectedServerId == null,
                            icon = HydraIcons.Bolt,
                            onClick = { actions.onSelectServer(auto.id) },
                        )
                    }
                }
                HydraField(
                    value = filter,
                    onValueChange = { filter = it },
                    label = stringResource(Res.string.servers_search),
                )
                // Sorting and measuring belong next to the list, the way every proxy client puts them:
                // a person who opens this screen either knows the name or wants the fastest one.
                ActionRow {
                    ServerOrder.entries.forEach { value ->
                        FilterChip(
                            selected = order == value,
                            onClick = { order = value },
                            label = { Text(stringResource(value.label()), style = MaterialTheme.typography.labelMedium) },
                        )
                    }
                    if (state.serverCount > 0) {
                        SecondaryAction(
                            stringResource(Res.string.servers_measure),
                            enabled = canMeasure,
                            onClick = actions.onMeasure,
                        )
                    }
                }
                if (state.busy.servers && state.serverCount == 0) LoadingRows(4)
            }
        }
        groups.forEach { (group, visible) ->
            item(key = "header:${group.sourceId}") {
                Text(group.sourceName, style = MaterialTheme.typography.titleSmall)
            }
            items(visible, key = { "server:${group.sourceId}:${it.id}" }, contentType = { "server" }) { server ->
                SectionGroup { ServerEntry(server, state.selectedServerId, actions) }
            }
        }
    }
}

internal fun canMeasure(connection: Connection): Boolean =
    connection is Connection.Idle || connection is Connection.Connected || connection is Connection.Stopped

/**
 * How the list is ordered.
 *
 * The list is already grouped by the subscription each server came from, so a chip that
 * claimed to sort "by source" sorted nothing: it is the order the subscription itself lists
 * them in, and it says so now.
 */
private enum class ServerOrder {
    LISTED,
    LATENCY,
    NAME,
    ;

    fun arrange(servers: List<ServerRef>): List<ServerRef> =
        when (this) {
            LISTED -> {
                servers
            }

            // Unknown and stale results sort last: neither is evidence of a fast server.
            LATENCY -> {
                servers.sortedWith(
                    compareBy<ServerRef> { it.latencyStale }.thenBy { it.latencyMillis ?: Int.MAX_VALUE },
                )
            }

            NAME -> {
                servers.sortedBy { it.displayName.lowercase() }
            }
        }

    fun label() =
        when (this) {
            LISTED -> Res.string.servers_order_source
            LATENCY -> Res.string.servers_order_latency
            NAME -> Res.string.servers_order_name
        }
}

@Composable
private fun ServerEntry(
    server: ServerRef,
    selectedId: String?,
    actions: AppActions,
) {
    val mark = serverFlag(server.displayName)
    ServerRow(
        name = mark?.second ?: server.displayName,
        // What it is and what the last measurement said, under the name: a figure long enough to
        // need its own line used to sit beside the name and could hide it entirely.
        detail = serverSupportingLine(server),
        selected = server.id == selectedId,
        icon = HydraIcons.Server,
        flag = mark?.first,
        onClick = { actions.onSelectServer(server.id) },
        measuring = server.measuring,
    )
}

/**
 * The subscription's own mark for a server, split off its name: a leading country flag belongs in
 * the row's leading slot, where a generic glyph was saying nothing about which server this is.
 * Only a real pair of regional indicators counts — and only when a name follows it, because a flag
 * alone is not a row.
 */
internal fun serverFlag(name: String): Pair<String, String>? {
    if (name.length < 5 || !name.isFlagAt(0)) return null
    val rest = name.substring(4).trimStart()
    return if (rest.isEmpty()) null else name.substring(0, 4) to rest
}

private fun String.isFlagAt(index: Int): Boolean =
    this[index] == '\uD83C' && this[index + 1] in '\uDDE6'..'\uDDFF'
