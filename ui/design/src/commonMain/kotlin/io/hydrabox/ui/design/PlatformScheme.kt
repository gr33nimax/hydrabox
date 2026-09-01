package io.hydrabox.ui.design

import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.Composable

/**
 * The platform's own colour source, when it has one. Android hands back Material You;
 * desktop has nothing to offer, so the brand seed stands in. Resolved once, in the theme.
 */
@Composable
expect fun platformColorScheme(dark: Boolean): ColorScheme?
