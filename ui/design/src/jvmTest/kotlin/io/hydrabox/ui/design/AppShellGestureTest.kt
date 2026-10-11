package io.hydrabox.ui.design

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AppShellGestureTest {
    @Test fun `swipes taps and navigation requests agree without losing vertical scroll`() {
        val selected = mutableStateOf(0)
        val lists = mutableMapOf<Int, LazyListState>()
        val scene = ImageComposeScene(width = 360, height = 640) {
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
}
