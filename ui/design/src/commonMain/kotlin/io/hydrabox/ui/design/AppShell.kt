package io.hydrabox.ui.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

enum class WindowClass { COMPACT, MEDIUM, EXPANDED }

fun windowClass(width: Int) = when {
    width < 600 -> WindowClass.COMPACT
    width < 840 -> WindowClass.MEDIUM
    else -> WindowClass.EXPANDED
}

/** One destination of the main navigation: a task, with an icon, and a mark when it needs attention. */
data class ShellDestination(val label: String, val icon: ImageVector, val attention: Boolean = false)

/**
 * What the frame leaves for a screen: how wide the window is, and the exact size of the box
 * the screen was handed after the chrome took its share.
 *
 * The height is the part a screen cannot work out for itself. Inside a scrolling column the
 * available height is unbounded, so a screen that wants to centre one control has nothing to
 * centre it in — which is why the home screen's disc sat pinned to the top with a third of the
 * screen empty below it. It is measured rather than derived from the inset arithmetic, because
 * the arithmetic was off by the difference between a navigation bar's height and its inset.
 */
data class ShellMetrics(val width: WindowClass, val height: Dp, val widthDp: Dp)

/**
 * The frame every screen sits in: navigation that says what else there is, and one place for
 * transient messages.
 *
 * There is deliberately no title bar. The app's own name written above its own home screen
 * told nobody anything, took 64 dp out of a 780 dp screen, and — because a collapsing bar and
 * a scrolling column disagree about who owns the top inset — drew the first row of every list
 * underneath itself. The navigation already says which of the three tasks is open.
 *
 * The information architecture does not change with width — only the navigation chrome moves
 * from the bottom to the side.
 */
@Composable
fun AppShell(
    destinations: List<ShellDestination>,
    selected: Int,
    onSelect: (Int) -> Unit,
    snackbarHostState: SnackbarHostState,
    modifier: Modifier = Modifier,
    content: @Composable (ShellMetrics) -> Unit,
) {
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val width = windowClass(maxWidth.value.toInt())
        Row(modifier = Modifier.fillMaxSize()) {
            if (width != WindowClass.COMPACT) {
                NavigationRail {
                    destinations.forEachIndexed { index, destination ->
                        NavigationRailItem(
                            selected = selected == index,
                            onClick = { onSelect(index) },
                            icon = { DestinationIcon(destination) },
                            label = { NavigationLabel(destination.label) },
                        )
                    }
                }
            }
            Scaffold(
                modifier = Modifier.fillMaxSize(),
                bottomBar = {
                    if (width == WindowClass.COMPACT) {
                        FloatingNavigationBar(destinations, selected, onSelect)
                    }
                },
                snackbarHost = { SnackbarHost(snackbarHostState) },
            ) { padding ->
                // The insets are applied here, once, so a screen is handed a box it can
                // measure: `maxHeight` below is the viewport itself, not an estimate of it.
                BoxWithConstraints(modifier = Modifier.fillMaxSize().padding(padding)) {
                    content(ShellMetrics(width = width, height = maxHeight, widthDp = maxWidth))
                }
            }
        }
    }
}

/** A floating capsule; its measured height includes the system gesture area and the gap. */
@Composable
private fun FloatingNavigationBar(
    destinations: List<ShellDestination>,
    selected: Int,
    onSelect: (Int) -> Unit,
) {
    val shape = RoundedCornerShape(percent = 50)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
            .padding(horizontal = 16.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier.widthIn(max = 480.dp).fillMaxWidth(),
            shape = shape,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f)),
            shadowElevation = 4.dp,
        ) {
            Row(
                modifier = Modifier.selectableGroup().padding(6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                destinations.forEachIndexed { index, destination ->
                    val chosen = selected == index
                    val background by animateColorAsState(
                        targetValue = if (chosen) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent,
                        animationSpec = tween(LocalUiMotion.current.standardMillis),
                    )
                    val foreground by animateColorAsState(
                        targetValue = if (chosen) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
                        animationSpec = tween(LocalUiMotion.current.standardMillis),
                    )
                    CompositionLocalProvider(LocalContentColor provides foreground) {
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .clip(shape)
                                .background(background)
                                .selectable(selected = chosen, role = Role.Tab, onClick = { onSelect(index) })
                                .heightIn(min = 64.dp)
                                .padding(horizontal = 4.dp, vertical = 10.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
                        ) {
                            DestinationIcon(destination)
                            Text(
                                destination.label,
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = if (chosen) FontWeight.SemiBold else FontWeight.Normal,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * A navigation label is one line. Three Russian labels do not all fit their slot at a large
 * font scale, and a wrapped one drags its icon off the row's baseline.
 */
@Composable
private fun NavigationLabel(text: String) = Text(
    text,
    style = MaterialTheme.typography.labelMedium,
    maxLines = 1,
    overflow = TextOverflow.Ellipsis,
)

@Composable
private fun DestinationIcon(destination: ShellDestination) {
    if (destination.attention) {
        BadgedBox(badge = { Badge() }) {
            Icon(destination.icon, contentDescription = null, modifier = Modifier.size(24.dp))
        }
    } else {
        Icon(destination.icon, contentDescription = null, modifier = Modifier.size(24.dp))
    }
}

/**
 * A screen opened from another screen: one title, one way back. Detail screens are how
 * rarely used settings stay out of the main navigation.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailScreen(
    title: String,
    onBack: () -> Unit,
    backLabel: String,
    modifier: Modifier = Modifier,
    actions: @Composable () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(title, style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    androidx.compose.material3.IconButton(onClick = onBack) {
                        Icon(HydraIcons.Back, contentDescription = backLabel)
                    }
                },
                actions = { actions() },
            )
        },
    ) { padding ->
        BoxWithConstraints(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                modifier = if (windowClass(maxWidth.value.toInt()) == WindowClass.COMPACT) {
                    Modifier.fillMaxWidth()
                } else {
                    Modifier.widthIn(max = 720.dp).fillMaxWidth()
                },
                verticalArrangement = Arrangement.spacedBy(UiTokens.spacing),
                content = content,
            )
        }
    }
}
