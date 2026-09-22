package io.hydrabox.ui.design

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

enum class ComponentLevel { EXPRESSIVE, STANDARD }

enum class MotionScheme { SPRING, DURATION }

data class UiCapabilities(
    val components: ComponentLevel,
    val motion: MotionScheme,
    val reducedMotion: Boolean = false,
)

data class UiMotion(
    val largeTransitionMillis: Int,
    val enterMillis: Int,
    val exitMillis: Int,
    val standardMillis: Int,
    val enterEasing: Easing,
    val exitEasing: Easing,
)

object UiTokens {
    val spacing: Dp = 8.dp
    val rowRadius: Dp = 12.dp
    val sectionRadius: Dp = 16.dp
    val objectRadius: Dp = 20.dp
    val heroRadius: Dp = 28.dp

    /**
     * Numbers that do not dance. A speed or a quota redrawn every second changes width with
     * every digit unless the figures are tabular, and a jittering line reads as motion the
     * screen did not intend.
     */
    fun figures(style: TextStyle): TextStyle = style.copy(fontFeatureSettings = "tnum")

    val radii: List<Dp> = listOf(0.dp, 4.dp, 8.dp, 12.dp, 16.dp, 20.dp, 24.dp, 28.dp, 32.dp)

    /** Small controls, rows, grouped sections, standalone objects, and hero surfaces. */
    val shapes =
        Shapes(
            extraSmall = RoundedCornerShape(radii[2]),
            small = RoundedCornerShape(rowRadius),
            medium = RoundedCornerShape(sectionRadius),
            large = RoundedCornerShape(objectRadius),
            extraLarge = RoundedCornerShape(heroRadius),
        )
}

private val StandardCapabilities = UiCapabilities(ComponentLevel.STANDARD, MotionScheme.DURATION)

val LocalUiCapabilities = staticCompositionLocalOf { StandardCapabilities }
val LocalUiMotion = staticCompositionLocalOf { durationMotion(false) }

@Composable
fun HydraTheme(
    dark: Boolean = isSystemInDarkTheme(),
    capabilities: UiCapabilities = uiCapabilities(),
    /**
     * Whether the scheme comes from the phone's own palette. It is offered as one of the three
     * appearance choices, and the interface no longer carries a palette of its own: the fixed
     * schemes are the standard Material ones, so nothing here competes with the wallpaper.
     */
    platformColours: Boolean = false,
    content: @Composable () -> Unit,
) {
    // A phone whose wallpaper is dark olive produces a scheme where `primary` and `surface` are
    // two shades of the same grey-green, which is why the platform's palette is a choice and not
    // the only answer. Where the phone has none — or has one this build cannot read — the
    // standard Material scheme is what is left, and it is the same one the fixed choices use.
    val scheme =
        platformColours.takeIf { it }?.let { platformColorScheme(dark) }
            ?: if (dark) darkColorScheme() else lightColorScheme()
    CompositionLocalProvider(
        LocalUiCapabilities provides capabilities,
        LocalUiMotion provides
            if (capabilities.motion ==
                MotionScheme.SPRING
            ) {
                springMotion(capabilities.reducedMotion)
            } else {
                durationMotion(capabilities.reducedMotion)
            },
    ) {
        // `MaterialExpressiveTheme` is internal in Compose Multiplatform 1.8.2, so the
        // expressive language is carried by our own tokens: shape scale, tonal surfaces,
        // typography roles and the spring motion above. Recorded in the substitution table.
        MaterialTheme(colorScheme = scheme, shapes = UiTokens.shapes, content = content)
    }
}

private fun springMotion(reduced: Boolean) =
    if (reduced) {
        durationMotion(true)
    } else {
        UiMotion(
            largeTransitionMillis = 500,
            enterMillis = 400,
            exitMillis = 200,
            standardMillis = 300,
            enterEasing = CubicBezierEasing(0.2f, 0f, 0f, 1f),
            exitEasing = CubicBezierEasing(0.4f, 0f, 1f, 1f),
        )
    }

private fun durationMotion(reduced: Boolean) =
    UiMotion(
        largeTransitionMillis = if (reduced) 0 else 500,
        enterMillis = if (reduced) 0 else 400,
        exitMillis = if (reduced) 0 else 200,
        standardMillis = if (reduced) 0 else 300,
        enterEasing = CubicBezierEasing(0.2f, 0f, 0f, 1f),
        exitEasing = CubicBezierEasing(0.4f, 0f, 1f, 1f),
    )

internal fun isReducedMotion(animationScale: Float) = animationScale == 0f

@Composable
expect fun uiCapabilities(): UiCapabilities
