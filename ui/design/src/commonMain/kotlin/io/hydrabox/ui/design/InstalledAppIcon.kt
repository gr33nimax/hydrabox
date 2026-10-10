package io.hydrabox.ui.design

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/** The platform supplies installed application artwork without leaking package APIs into UI. */
@Composable
expect fun InstalledAppIcon(packageName: String, modifier: Modifier = Modifier)
