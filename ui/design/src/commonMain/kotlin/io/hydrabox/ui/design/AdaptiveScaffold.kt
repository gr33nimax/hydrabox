package io.hydrabox.ui.design

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

enum class WindowClass { COMPACT, MEDIUM, EXPANDED }

fun windowClass(width: Int) = when {
    width < 600 -> WindowClass.COMPACT
    width < 840 -> WindowClass.MEDIUM
    else -> WindowClass.EXPANDED
}

/**
 * One layout for every width class: a bottom bar when compact, a rail when there is room.
 * The information architecture does not change with width — only the navigation chrome.
 */
@Composable
fun AdaptiveScaffold(
    title: String,
    destinations: List<String>,
    selected: Int,
    onSelect: (Int) -> Unit,
    content: @Composable (WindowClass) -> Unit,
) {
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val size = windowClass(maxWidth.value.toInt())
            Row(modifier = Modifier.fillMaxSize()) {
                if (size != WindowClass.COMPACT) {
                    NavigationRail {
                        destinations.forEachIndexed { index, label ->
                            NavigationRailItem(
                                selected = selected == index,
                                onClick = { onSelect(index) },
                                icon = {},
                                label = { Text(label, style = MaterialTheme.typography.labelMedium) },
                            )
                        }
                    }
                }
                Column(modifier = Modifier.fillMaxSize()) {
                    Column(
                        modifier = Modifier.weight(1f).fillMaxWidth()
                            .padding(horizontal = UiTokens.spacing * 2)
                            .verticalScroll(rememberScrollState()),
                    ) {
                        Text(
                            title,
                            style = MaterialTheme.typography.headlineSmall,
                            modifier = Modifier.padding(vertical = UiTokens.spacing * 2),
                        )
                        content(size)
                    }
                    if (size == WindowClass.COMPACT) {
                        NavigationBar {
                            destinations.forEachIndexed { index, label ->
                                NavigationBarItem(
                                    selected = selected == index,
                                    onClick = { onSelect(index) },
                                    icon = {},
                                    label = { Text(label, style = MaterialTheme.typography.labelSmall) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
