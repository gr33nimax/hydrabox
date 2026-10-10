package io.hydrabox.platform.android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SelectionRefreshTest {
    private class Fixture(maxAttempts: Int = 8) {
        val tasks = ArrayDeque<Pair<Long, () -> Unit>>()
        var reads = 0
        var read: () -> Boolean = { true }
        val refresh = SelectionRefresh(
            schedule = { delay, action -> tasks.addLast(delay to action) },
            refresh = { reads++; read() },
            maxAttempts = maxAttempts,
        )

        fun tick() = tasks.removeFirst().second()
    }

    @Test fun `a selection committed after its group event is read without measuring`() {
        val fixture = Fixture()
        var coreSelection: String? = null
        var displayedSelection: String? = null
        fixture.read = {
            displayedSelection = coreSelection
            coreSelection != null
        }
        fixture.refresh.request()
        assertEquals(null, displayedSelection)
        // The stream cached the empty group. The core commits the actual choice afterwards
        // and emits no further group event or measurement result.
        coreSelection = "finland"
        fixture.tick()
        assertEquals("finland", displayedSelection)
        assertTrue(fixture.tasks.isEmpty())
    }

    @Test fun `a previously resolved automatic route is checked again after a change`() {
        val fixture = Fixture()
        var coreSelection = "finland"
        var displayedSelection = coreSelection
        fixture.read = { displayedSelection = coreSelection; true }
        fixture.refresh.request()
        coreSelection = "germany"
        fixture.tick()
        assertEquals("germany", displayedSelection)
    }

    @Test fun `an unresolved route retries then stops once the core reports it`() {
        val fixture = Fixture()
        fixture.read = { fixture.reads >= 3 }
        fixture.refresh.request()
        repeat(3) { fixture.tick() }
        assertEquals(3, fixture.reads)
        assertTrue(fixture.tasks.isEmpty())
    }

    @Test fun `bursts of group notifications share one pending snapshot read`() {
        val fixture = Fixture()
        repeat(100) { fixture.refresh.request() }
        assertEquals(1, fixture.tasks.size)
        fixture.tick()
        assertEquals(1, fixture.reads)
        assertTrue(fixture.tasks.isEmpty())
    }

    @Test fun `a group event during a snapshot RPC receives a later read`() {
        val fixture = Fixture()
        fixture.read = {
            if (fixture.reads == 1) fixture.refresh.request()
            true
        }
        fixture.refresh.request()
        fixture.tick()
        assertEquals(1, fixture.tasks.size)
        fixture.tick()
        assertEquals(2, fixture.reads)
        assertTrue(fixture.tasks.isEmpty())
    }

    @Test fun `an unreachable core exhausts a bounded retry budget`() {
        val fixture = Fixture(maxAttempts = 3)
        fixture.read = { error("command socket unavailable") }
        fixture.refresh.request()
        repeat(3) { fixture.tick() }
        assertEquals(3, fixture.reads)
        assertTrue(fixture.tasks.isEmpty())
    }

    @Test fun `a stopped session cannot read or cancel the new sessions pending refresh`() {
        val fixture = Fixture()
        fixture.refresh.request()
        fixture.refresh.cancel()
        fixture.refresh.request()
        fixture.tick()
        assertEquals(0, fixture.reads)
        assertEquals(1, fixture.tasks.size)
        fixture.tick()
        assertEquals(1, fixture.reads)
        assertTrue(fixture.tasks.isEmpty())
    }
}
