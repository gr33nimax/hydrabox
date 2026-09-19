package io.hydrabox.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import java.awt.Rectangle
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * A server's name has to survive whatever the diagnostics say about it.
 *
 * The figure used to sit beside the name in the trailing slot, so a long answer — "RTT до TURN
 * edge: 14885 мс · устарело" — took the width the name needed and left an ellipsis where the
 * server's own name should be. The row is rendered off-device and the frames are compared:
 * everything a different diagnostic changes has to fall below the line the name is drawn on.
 *
 * Nothing here is measured against a guessed pixel: the line the name occupies is found by
 * rendering the same row with an empty name and diffing it.
 */
class ServerRowRenderTest {
    private val name = "amneziawg-desktop-gr33nima-netherlands"

    /** A short answer and one long enough to have taken the whole line beside the name. */
    private val answered = "VLESS · 35 мс"
    private val stale = "VLESS · RTT до TURN edge: 14885 мс · устарело"

    @Test fun `the diagnostic never draws over the name`() {
        val chrome = render("", "")
        val named = render(name, "")
        val shortAnswer = render(name, answered)
        val longAnswer = render(name, stale)

        // The rectangle the name occupies, found from the two frames that differ only by it:
        // the columns alone are not enough, because the diagnostic is drawn on the same width.
        val nameBox = requireNotNull(differingBox(named, chrome)) { "the name was not drawn at all" }
        // Whatever the diagnostic says, it may not touch that rectangle: a figure beside the
        // name would shorten it (a different ellipsis), and one drawn over it would show up
        // as pixels that changed inside the name's own rectangle.
        val changed =
            (nameBox.y until nameBox.y + nameBox.height).flatMap { y ->
                (nameBox.x until nameBox.x + nameBox.width).filter { x ->
                    shortAnswer.getRGB(x, y) != longAnswer.getRGB(x, y)
                }
            }
        assertTrue(
            changed.isEmpty(),
            "the diagnostic drew over the server's name: ${changed.size} pixels changed inside $nameBox",
        )
    }

    @Test fun `the chosen server is drawn differently from the others`() {
        val plain = render(name, answered, selected = false)
        val chosen = render(name, answered, selected = true)
        assertTrue(
            differingBox(plain, chosen) != null,
            "the chosen server draws exactly like the others",
        )
    }

    /** The rectangle of pixels that is not identical between two frames of the same row. */
    private fun differingBox(
        left: BufferedImage,
        right: BufferedImage,
    ): Rectangle? {
        assertTrue(left.width == right.width && left.height == right.height, "two frames of one row differ in size")
        val columns = (0 until left.width).filter { x -> (0 until left.height).any { y -> left.getRGB(x, y) != right.getRGB(x, y) } }
        val rows = (0 until left.height).filter { y -> (0 until left.width).any { x -> left.getRGB(x, y) != right.getRGB(x, y) } }
        if (columns.isEmpty() || rows.isEmpty()) return null
        return Rectangle(
            columns.first(),
            rows.first(),
            columns.last() - columns.first() + 1,
            rows.last() - rows.first() + 1,
        )
    }

    private fun render(
        title: String,
        detail: String,
        selected: Boolean = false,
    ): BufferedImage {
        val scene =
            ImageComposeScene(width = 720, height = 200, density = Density(2f)) {
                HydraTheme(dark = true) {
                    Column(
                        modifier =
                            Modifier
                                .fillMaxSize()
                                .background(MaterialTheme.colorScheme.surface)
                                .padding(8.dp),
                    ) {
                        ServerRow(
                            name = title,
                            detail = detail,
                            selected = selected,
                            icon = HydraIcons.Server,
                            onClick = {},
                        )
                    }
                }
            }
        val bytes = scene.render().encodeToData()?.bytes ?: ByteArray(0)
        assertTrue(bytes.size > 1_000, "the row rendered nothing")
        return ImageIO.read(ByteArrayInputStream(bytes))
    }
}
