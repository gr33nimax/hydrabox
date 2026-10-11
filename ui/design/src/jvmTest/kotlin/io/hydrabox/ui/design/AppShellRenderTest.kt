package io.hydrabox.ui.design

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.SnackbarHostState
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.File
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AppShellRenderTest {
    @Test fun `switching the capsule selection leaves the content viewport unchanged`() {
        for ((width, fontScale) in listOf(360 to 1f, 320 to 1.3f)) {
            for (dark in listOf(true, false)) {
                val (home, homeMetrics) = render(width, fontScale, dark, selected = 0)
                val (servers, serverMetrics) = render(width, fontScale, dark, selected = 1)
                assertEquals(homeMetrics, serverMetrics)
                assertEquals(WindowClass.COMPACT, homeMetrics.width)
                assertTrue(homeMetrics.height < 760.dp, "the navigation did not reserve a viewport")
                val changedRows = (0 until home.height).filter { y ->
                    (0 until home.width).any { x -> home.getRGB(x, y) != servers.getRGB(x, y) }
                }
                assertTrue(changedRows.isNotEmpty(), "the selected tab has no visible highlight")
                assertTrue(
                    changedRows.first() >= (homeMetrics.height.value * 2).toInt(),
                    "the navigation selection changed the screen's content",
                )
            }
        }
    }

    private fun render(width: Int, fontScale: Float, dark: Boolean, selected: Int): Pair<BufferedImage, ShellMetrics> {
        var metrics: ShellMetrics? = null
        val scene = ImageComposeScene(width = width * 2, height = 1520, density = Density(2f, fontScale)) {
            HydraTheme(dark = dark) {
                AppShell(
                    destinations = listOf(
                        ShellDestination("Главное", HydraIcons.Shield),
                        ShellDestination("Серверы", HydraIcons.Server, attention = true),
                        ShellDestination("Настройки", HydraIcons.Sliders),
                    ),
                    selected = selected,
                    onSelect = {},
                    snackbarHostState = SnackbarHostState(),
                ) {
                    metrics = it
                    Column(
                        modifier = Modifier.fillMaxSize().padding(16.dp),
                        verticalArrangement = Arrangement.Bottom,
                    ) {
                        SectionGroup {
                            FactRow(
                                label = "Маршрут",
                                value = "Автовыбор",
                                detail = "🇩🇰Дания | Trojan VPN#31",
                                secondaryDetail = "137 мс",
                                detailMaxLines = Int.MAX_VALUE,
                                onClick = {},
                            )
                            FactRow("Внешний IP", "130.49.188.54", {}, detail = "🇩🇰 DK")
                            FactRow("Лимит", "74.1 GiB / ∞", {}, detail = "Осталось 11 дн.")
                            FactRow("Режим подключения", "VPN", {}, detail = "вне туннеля: 40")
                        }
                    }
                }
            }
        }
        return try {
            val bytes = requireNotNull(scene.render().encodeToData()).bytes
            val directory = File(System.getProperty("user.dir"), "build/shell-preview").apply { mkdirs() }
            File(directory, "$width-$fontScale-${if (dark) "dark" else "light"}-$selected.png").writeBytes(bytes)
            ImageIO.read(ByteArrayInputStream(bytes)) to requireNotNull(metrics)
        } finally {
            scene.close()
        }
    }
}
