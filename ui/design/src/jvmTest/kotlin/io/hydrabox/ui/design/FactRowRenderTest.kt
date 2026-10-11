package io.hydrabox.ui.design

import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertTrue

class FactRowRenderTest {
    @Test fun `long automatic route keeps its final words visible on a narrow screen`() {
        val prefix = "Великобритания | Reality VPN | очень длинное название сервера "
        val first = render(prefix + "Лондон", detail = true)
        val second = render(prefix + "Манчестер", detail = true)
        assertDifferent(first, second)
    }

    @Test fun `long manually selected route keeps its final words visible`() {
        val prefix = "Великобритания | Reality VPN | очень длинное название сервера "
        assertDifferent(render(prefix + "Лондон", detail = false), render(prefix + "Манчестер", detail = false))
    }

    private fun assertDifferent(first: BufferedImage, second: BufferedImage) {
        assertTrue(
            (0 until first.height).any { y ->
                (0 until first.width).any { x -> first.getRGB(x, y) != second.getRGB(x, y) }
            },
            "the final words were truncated: different full server names produced identical rows",
        )
    }

    private fun render(name: String, detail: Boolean): BufferedImage {
        val scene = ImageComposeScene(width = 640, height = 1000, density = Density(2f, 1.3f)) {
            HydraTheme(dark = true) {
                FactRow(
                    label = "Маршрут",
                    value = name,
                    flag = "🇬🇧",
                    headerDetail = if (detail) "Автовыбор" else null,
                    headerIcon = HydraIcons.Bolt,
                    detail = "VLESS",
                    secondaryDetail = "137 мс",
                    onClick = {},
                    valueMaxLines = Int.MAX_VALUE,
                    detailMaxLines = Int.MAX_VALUE,
                )
            }
        }
        return try {
            val bytes = requireNotNull(scene.render().encodeToData()).bytes
            ImageIO.read(ByteArrayInputStream(bytes))
        } finally {
            scene.close()
        }
    }
}
