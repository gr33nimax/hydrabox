package io.hydrabox.ui.design

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(androidx.compose.ui.InternalComposeUiApi::class)
class TvNavigationTest {
    @Test fun `remote selects pages activates content and returns to navigation`() {
        val selected = mutableStateOf(0)
        var presses = 0
        val scene = ImageComposeScene(width = 1280, height = 720) {
            TvPresentation(true) {
                HydraTheme(dark = true) {
                    AppShell(
                        destinations = listOf(
                            ShellDestination("Главное", HydraIcons.Shield),
                            ShellDestination("Серверы", HydraIcons.Server),
                            ShellDestination("Настройки", HydraIcons.Sliders),
                        ),
                        selected = selected.value,
                        onSelect = { selected.value = it },
                        snackbarHostState = SnackbarHostState(),
                        modifier = Modifier.fillMaxSize(),
                    ) { _, _ ->
                        HydraRow("Подключиться", onClick = { presses++ })
                    }
                }
            }
        }
        var time = 0L
        fun frames() = repeat(8) { time += 16_000_000; scene.render(time).close() }
        fun key(code: Key) {
            val consumed = scene.sendKeyEvent(KeyEvent(code, KeyEventType.KeyDown))
            println("TV key $code consumed=$consumed selected=${selected.value} presses=$presses")
            scene.sendKeyEvent(KeyEvent(code, KeyEventType.KeyUp))
            frames()
        }
        try {
            frames()
            key(Key.DirectionDown)
            key(Key.Enter)
            assertEquals(1, selected.value, "D-pad Down + OK must select Servers")
            key(Key.DirectionRight)
            key(Key.Enter)
            assertEquals(1, presses, "D-pad Right + OK must activate page content")
            key(Key.DirectionLeft)
            key(Key.DirectionDown)
            key(Key.Enter)
            assertEquals(2, selected.value)
            val directory = File("build/tv-preview").apply { mkdirs() }
            scene.render(time + 16_000_000).use { image ->
                File(directory, "tv-navigation.png").writeBytes(requireNotNull(image.encodeToData()).bytes)
            }
        } finally {
            val directory = File("build/tv-preview").apply { mkdirs() }
            scene.render(time + 32_000_000).use { image ->
                File(directory, "tv-last-frame.png").writeBytes(requireNotNull(image.encodeToData()).bytes)
            }
            scene.close()
        }
    }
}
