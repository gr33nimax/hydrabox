package io.hydrabox.ui.design

import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp

val LocalTvMode = staticCompositionLocalOf { false }

/** A larger, inset presentation without changing the phone's layout or system font preference. */
@Composable
fun TvPresentation(enabled: Boolean, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    CompositionLocalProvider(
        LocalTvMode provides enabled,
        LocalDensity provides if (enabled) Density(density.density * 1.15f, density.fontScale) else density,
    ) {
        Box(Modifier.fillMaxSize().padding(if (enabled) 24.dp else 0.dp)) { content() }
    }
}

/** Observe the control's own focus; never insert a second focus target around a button. */
@Composable
fun Modifier.tvFocusOutline(): Modifier {
    if (!LocalTvMode.current) return this
    var focused by remember { mutableStateOf(false) }
    val colour = if (focused) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent
    return onFocusChanged { focused = it.hasFocus }
        .border(3.dp, colour, RoundedCornerShape(12.dp))
}

@Composable
fun TvFocusRoot(identity: Any, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val tv = LocalTvMode.current
    val requester = remember { FocusRequester() }
    LaunchedEffect(tv, identity) {
        if (tv) {
            withFrameNanos { }
            // Loading and empty screens may have no focusable descendants yet.
            runCatching { requester.requestFocus() }
        }
    }
    Box(modifier.focusRequester(requester).focusGroup()) { content() }
}
