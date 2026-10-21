package io.hydrabox.ui.design

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.KeyEvent
import java.awt.Canvas
import java.awt.event.KeyEvent as AwtKeyEvent
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

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
        fun key(code: Int) {
            val source = Canvas()
            scene.sendKeyEvent(KeyEvent(AwtKeyEvent(source, AwtKeyEvent.KEY_PRESSED, 0L, 0, code, AwtKeyEvent.CHAR_UNDEFINED)))
            scene.sendKeyEvent(KeyEvent(AwtKeyEvent(source, AwtKeyEvent.KEY_RELEASED, 0L, 0, code, AwtKeyEvent.CHAR_UNDEFINED)))
            frames()
        }
        try {
            frames()
            key(AwtKeyEvent.VK_DOWN)
            key(AwtKeyEvent.VK_ENTER)
            assertEquals(1, selected.value)
            key(AwtKeyEvent.VK_RIGHT)
            key(AwtKeyEvent.VK_ENTER)
            assertEquals(1, presses)
            key(AwtKeyEvent.VK_LEFT)
            key(AwtKeyEvent.VK_DOWN)
            key(AwtKeyEvent.VK_ENTER)
            assertEquals(2, selected.value)
            val directory = File("build/tv-preview").apply { mkdirs() }
            scene.render(time + 16_000_000).use { image ->
                File(directory, "tv-navigation.png").writeBytes(requireNotNull(image.encodeToData()).bytes)
            }
        } finally {
            scene.close()
        }
    }
}
