package io.hydrabox.ui.design

import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.unit.dp

/** TV pages are selected with the remote; they do not share the phone's swipe pager. */
@Composable
internal fun TvShell(
    destinations: List<ShellDestination>,
    selected: Int,
    onSelect: (Int) -> Unit,
    snackbar: SnackbarHostState,
    modifier: Modifier,
    content: @Composable (Int, ShellMetrics) -> Unit,
) {
    val navigation = remember(destinations.size) { List(destinations.size) { FocusRequester() } }
    val page = remember { FocusRequester() }
    val input = LocalInputModeManager.current
    LaunchedEffect(Unit) {
        input.requestInputMode(InputMode.Keyboard)
        withFrameNanos { }
        navigation[selected].requestFocus()
    }
    Row(modifier.fillMaxSize()) {
        Column(
            Modifier.width(208.dp).fillMaxHeight().focusGroup().padding(end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            destinations.forEachIndexed { index, destination ->
                Surface(
                    onClick = { onSelect(index) },
                    color = if (selected == index) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.fillMaxWidth().focusRequester(navigation[index]).focusProperties {
                        canFocus = true
                        up = navigation[(index - 1).coerceAtLeast(0)]
                        down = navigation[(index + 1).coerceAtMost(destinations.lastIndex)]
                        right = page
                    }.tvFocusOutline(),
                ) {
                    Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(destination.icon, contentDescription = null)
                        Text(destination.label, style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
        }
        Scaffold(Modifier.weight(1f), snackbarHost = { SnackbarHost(snackbar) }) { padding ->
            BoxWithConstraints(
                Modifier.fillMaxSize().padding(padding).focusRequester(page).focusProperties { left = navigation[selected] }.focusGroup(),
            ) {
                content(selected, ShellMetrics(WindowClass.EXPANDED, maxHeight, maxWidth))
            }
        }
    }
}
