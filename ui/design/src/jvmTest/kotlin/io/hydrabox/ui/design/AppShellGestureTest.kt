package io.hydrabox.ui.design

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.unit.dp
import java.io.ByteArrayInputStream
import java.io.File
import javax.imageio.ImageIO
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AppShellGestureTest {
    @Test fun `swipes taps and navigation requests agree without losing vertical scroll`() {
        val selected = mutableStateOf(0)
        val lists = mutableMapOf<Int, LazyListState>()
        var highlight = 0
        val scene = ImageComposeScene(width = 360, height = 640) {
            HydraTheme(dark = true) {
                highlight = MaterialTheme.colorScheme.secondaryContainer.toArgb()
                AppShell(
                    destinations = listOf(
                        ShellDestination("Главное", HydraIcons.Shield),
                        ShellDestination("Серверы", HydraIcons.Server),
                        ShellDestination("Настройки", HydraIcons.Sliders),
                    ),
                    selected = selected.value,
                    onSelect = { selected.value = it },
                    snackbarHostState = SnackbarHostState(),
                ) { page, shell ->
                    val list = rememberLazyListState()
                    lists[page] = list
                    LazyColumn(
                        state = list,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = shell.bottomPadding),
                    ) {
                        items(50) { row -> Text("$page / $row", modifier = Modifier.height(48.dp)) }
                    }
                }
            }
        }
        var clock = 0L
        fun frame() {
            clock += 16L
            scene.render(clock * 1_000_000L).close()
        }
        fun settle() = repeat(120) { frame() }
        fun indicatorCenter(save: Boolean = false): Double {
            clock += 16L
            val bytes = scene.render(clock * 1_000_000L).use { requireNotNull(it.encodeToData()).bytes }
            if (save) {
                val directory = File(System.getProperty("user.dir"), "build/shell-preview").apply { mkdirs() }
                File(directory, "half-swipe.png").writeBytes(bytes)
            }
            val image = ImageIO.read(ByteArrayInputStream(bytes))
            var sum = 0L
            var count = 0L
            for (y in 560 until image.height) for (x in 0 until image.width) {
                if (image.getRGB(x, y) == highlight) { sum += x; count++ }
            }
            assertTrue(count > 200, "the capsule highlight was not drawn")
            return sum.toDouble() / count
        }
        fun gesture(start: Offset, end: Offset) {
            scene.sendPointerEvent(PointerEventType.Press, start, timeMillis = clock, type = PointerType.Touch)
            for (step in 1..12) {
                frame()
                val point = start + (end - start) * (step / 12f)
                scene.sendPointerEvent(PointerEventType.Move, point, timeMillis = clock, type = PointerType.Touch)
            }
            frame()
            scene.sendPointerEvent(PointerEventType.Release, end, timeMillis = clock, type = PointerType.Touch)
            settle()
        }
        try {
            settle()
            gesture(Offset(180f, 500f), Offset(180f, 160f))
            assertEquals(0, selected.value, "a vertical drag switched tabs")
            val home = lists.getValue(0)
            assertTrue(home.firstVisibleItemIndex > 0, "the vertical list did not scroll")
            val position = home.firstVisibleItemIndex to home.firstVisibleItemScrollOffset

            // Hold a swipe midway: the active destination has not settled, but the
            // highlight must already follow the finger. Reverse it before releasing.
            val startCenter = indicatorCenter()
            scene.sendPointerEvent(PointerEventType.Press, Offset(300f, 320f), timeMillis = clock, type = PointerType.Touch)
            for (step in 1..6) {
                frame()
                scene.sendPointerEvent(PointerEventType.Move, Offset(300f - step * 24f, 320f), timeMillis = clock, type = PointerType.Touch)
            }
            frame()
            val heldCenter = indicatorCenter(save = true)
            assertEquals(0, selected.value, "the page settled before the finger was released")
            assertTrue(heldCenter - startCenter in 20.0..65.0, "the highlight did not follow the partial swipe: $startCenter -> $heldCenter")
            for (step in 1..6) {
                frame()
                scene.sendPointerEvent(PointerEventType.Move, Offset(156f + step * 24f, 320f), timeMillis = clock, type = PointerType.Touch)
            }
            frame()
            assertTrue(indicatorCenter() < heldCenter - 20, "the highlight did not follow the reverse drag")
            scene.sendPointerEvent(PointerEventType.Release, Offset(300f, 320f), timeMillis = clock, type = PointerType.Touch)
            settle()
            assertEquals(0, selected.value)

            gesture(Offset(300f, 320f), Offset(40f, 320f))
            assertEquals(1, selected.value)
            gesture(Offset(300f, 320f), Offset(40f, 320f))
            assertEquals(2, selected.value)
            gesture(Offset(40f, 320f), Offset(300f, 320f))
            assertEquals(1, selected.value)
            gesture(Offset(40f, 320f), Offset(300f, 320f))
            assertEquals(0, selected.value)
            assertEquals(position, lists.getValue(0).let { it.firstVisibleItemIndex to it.firstVisibleItemScrollOffset })

            gesture(Offset(275f, 600f), Offset(275f, 600f))
            assertEquals(2, selected.value, "the capsule tap did not change the page")
            selected.value = 0
            settle()
            assertEquals(0, selected.value, "the settled pager overrode a navigation request")
            gesture(Offset(300f, 320f), Offset(40f, 320f))
            assertEquals(1, selected.value, "the pager did not move from the requested page")
        } finally {
            scene.close()
        }
    }

    @Test fun `a delayed selection report must not reverse the next fling`() {
        val selected = mutableStateOf(0)
        val reported = mutableListOf<Int>()
        val pageX = mutableMapOf<Int, Float>()
        val scene = ImageComposeScene(width = 360, height = 640) {
            HydraTheme(dark = true) {
                AppShell(
                    destinations = listOf(
                        ShellDestination("Главное", HydraIcons.Shield),
                        ShellDestination("Серверы", HydraIcons.Server),
                        ShellDestination("Настройки", HydraIcons.Sliders),
                    ),
                    selected = selected.value,
                    // Deliberately delay the parent's acknowledgement until the next
                    // swipe is settling, as can happen between composition frames.
                    onSelect = { reported += it },
                    snackbarHostState = SnackbarHostState(),
                ) { page, _ ->
                    Box(Modifier.fillMaxSize().onGloballyPositioned { pageX[page] = it.positionInRoot().x }) {
                        Text("Page $page")
                    }
                }
            }
        }
        var clock = 0L
        fun frame() {
            clock += 16L
            scene.render(clock * 1_000_000L).close()
        }
        fun settle() = repeat(120) { frame() }
        fun pointer(type: PointerEventType, x: Float) = scene.sendPointerEvent(
            type, Offset(x, 320f), timeMillis = clock, type = PointerType.Touch,
        )
        fun drag(start: Float, end: Float) {
            for (step in 1..6) {
                frame()
                pointer(PointerEventType.Move, start + (end - start) * (step / 6f))
            }
            frame()
        }
        fun delayedEchoSwipe(from: Int, to: Int) {
            assertEquals(from, reported.last())
            val start = if (to > from) 300f else 60f
            val end = if (to > from) 60f else 300f
            val held = start + (end - start) * 0.3f
            pointer(PointerEventType.Press, start)
            drag(start, held)
            val heldPageX = pageX.getValue(from)
            assertTrue(abs(heldPageX) > 35f, "the new drag did not move the actual page")

            pointer(PointerEventType.Release, held)
            repeat(2) { frame() }
            val beforeEchoX = pageX.getValue(from)
            selected.value = from
            repeat(12) { frame() }
            val afterEchoX = pageX.getValue(from)
            assertTrue(
                if (to > from) afterEchoX <= beforeEchoX + 2f else afterEchoX >= beforeEchoX - 2f,
                "acknowledging page $from reversed the new fling: $beforeEchoX -> $afterEchoX",
            )
            settle()
            assertEquals(to, reported.last(), "the swipe was cancelled by its predecessor's acknowledgement")
            assertTrue(abs(pageX.getValue(to)) < 0.5f)
        }
        try {
            settle()
            pointer(PointerEventType.Press, 300f)
            drag(300f, 60f)
            pointer(PointerEventType.Release, 60f)
            settle()
            assertEquals(1, reported.last())
            delayedEchoSwipe(from = 1, to = 2)
            delayedEchoSwipe(from = 2, to = 1)

            // A real external request still wins, including a request that interrupts
            // another programmatic transition and returns to the previous page.
            selected.value = 0
            settle()
            assertTrue(abs(pageX.getValue(0)) < 0.5f)
            selected.value = 2
            repeat(4) { frame() }
            selected.value = 0
            settle()
            assertTrue(abs(pageX.getValue(0)) < 0.5f)
        } finally {
            scene.close()
        }
    }

}
