package io.hydrabox.ui.design

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlinx.coroutines.flow.collect

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
 * The height is the full viewport. A compact screen scrolls behind the capsule and uses
 * [ShellMetrics.bottomPadding] at the end of its content to uncover the last item.
 * Inside a scrolling column the
 * available height is unbounded, so a screen that wants to centre one control has nothing to
 * centre it in — which is why the home screen's disc sat pinned to the top with a third of the
 * screen empty below it. It is measured rather than derived from the inset arithmetic, because
 * the arithmetic was off by the difference between a navigation bar's height and its inset.
 */
data class ShellMetrics(val width: WindowClass, val height: Dp, val widthDp: Dp, val bottomPadding: Dp = 0.dp)

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
    content: @Composable (Int, ShellMetrics) -> Unit,
) {
    if (LocalTvMode.current) {
        TvShell(destinations, selected, onSelect, snackbarHostState, modifier, content)
        return
    }
    val pager = rememberPagerState(initialPage = selected, pageCount = { destinations.size })
    val currentSelection by rememberUpdatedState(selected)
    val currentOnSelect by rememberUpdatedState(onSelect)
    var pendingPagerAcknowledgement by remember { mutableStateOf<Int?>(null) }
    val focusManager = LocalFocusManager.current
    val motion = LocalUiMotion.current
    LaunchedEffect(selected) {
        // A parent echo of our own settled-page report is an acknowledgement, not a
        // navigation command. Replaying it would cancel a drag that has already started.
        val acknowledgement = pendingPagerAcknowledgement == selected
        pendingPagerAcknowledgement = null
        focusManager.clearFocus()
        if (!acknowledgement && (pager.settledPage != selected || pager.currentPageOffsetFraction != 0f)) {
            if (motion.standardMillis == 0) pager.scrollToPage(selected) else pager.animateScrollToPage(selected)
        }
    }
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { page ->
            if (page != currentSelection) {
                pendingPagerAcknowledgement = page
                currentOnSelect(page)
            }
        }
    }
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val width = windowClass(maxWidth.value.toInt())
        val density = LocalDensity.current
        var navigationHeight by remember { mutableStateOf(82.dp) }
        val clearance = if (width == WindowClass.COMPACT) navigationHeight else 0.dp
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
                snackbarHost = {
                    SnackbarHost(snackbarHostState, modifier = Modifier.padding(bottom = clearance))
                },
            ) { padding ->
                // The insets are applied here, once, so a screen is handed a box it can
                // measure: `maxHeight` below is the viewport itself, not an estimate of it.
                BoxWithConstraints(modifier = Modifier.fillMaxSize().padding(padding)) {
                    val metrics = ShellMetrics(width, maxHeight, maxWidth, clearance)
                    HorizontalPager(
                        state = pager,
                        modifier = Modifier.fillMaxSize(),
                        beyondViewportPageCount = 1,
                    ) { page -> content(page, metrics) }
                    if (width == WindowClass.COMPACT) {
                        FloatingNavigationBar(
                            destinations,
                            selected,
                            onSelect,
                            pagePosition = { (pager.currentPage + pager.currentPageOffsetFraction).coerceIn(0f, destinations.lastIndex.toFloat()) },
                            modifier = Modifier.align(Alignment.BottomCenter).onSizeChanged {
                                navigationHeight = with(density) { it.height.toDp() }
                            },
                        )
                    }
                }
            }
        }
    }
}

/** Drawn over the pager; system insets belong to the scaffold, not to a separate bottom bar. */
@Composable
private fun FloatingNavigationBar(
    destinations: List<ShellDestination>,
    selected: Int,
    onSelect: (Int) -> Unit,
    pagePosition: () -> Float,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(percent = 50)
    val colors = MaterialTheme.colorScheme
    val layoutDirection = LocalLayoutDirection.current
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier.widthIn(max = 320.dp).fillMaxWidth(),
            shape = shape,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f)),
            shadowElevation = 4.dp,
        ) {
            Row(
                modifier = Modifier.selectableGroup().padding(4.dp).drawBehind {
                    val gap = 2.dp.toPx()
                    val slotWidth = (size.width - gap * (destinations.size - 1)) / destinations.size
                    val logicalX = (slotWidth + gap) * pagePosition()
                    val x = if (layoutDirection == LayoutDirection.Rtl) size.width - slotWidth - logicalX else logicalX
                    drawRoundRect(
                        color = colors.secondaryContainer,
                        topLeft = Offset(x, 0f),
                        size = Size(slotWidth, size.height),
                        cornerRadius = CornerRadius(size.height / 2f),
                    )
                },
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                destinations.forEachIndexed { index, destination ->
                    val chosen = selected == index
                    val foreground = lerp(
                        colors.onSurfaceVariant,
                        colors.onSecondaryContainer,
                        (1f - abs(pagePosition() - index)).coerceIn(0f, 1f),
                    )
                    CompositionLocalProvider(LocalContentColor provides foreground) {
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .clip(shape)
                                .selectable(selected = chosen, role = Role.Tab, onClick = { onSelect(index) })
                                .heightIn(min = 48.dp)
                                .padding(horizontal = 4.dp, vertical = 6.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
                        ) {
                            DestinationIcon(destination, size = 20.dp)
                            Text(
                                destination.label,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Medium,
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
private fun DestinationIcon(destination: ShellDestination, size: Dp = 24.dp) {
    if (destination.attention) {
        BadgedBox(badge = { Badge() }) {
            Icon(destination.icon, contentDescription = null, modifier = Modifier.size(size))
        }
    } else {
        Icon(destination.icon, contentDescription = null, modifier = Modifier.size(size))
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
    TvFocusRoot(title, Modifier.fillMaxSize()) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(title, style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    androidx.compose.material3.IconButton(onClick = onBack, modifier = Modifier.tvFocusOutline()) {
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

}
