package io.hydrabox.ui.design

import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/** Desktop has no Android package inventory. */
@Composable
actual fun InstalledAppIcon(packageName: String, modifier: Modifier) {
    Icon(HydraIcons.Apps, contentDescription = null, modifier = modifier)
}
