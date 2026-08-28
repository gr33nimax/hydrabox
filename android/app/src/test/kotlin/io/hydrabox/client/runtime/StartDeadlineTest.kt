package io.hydrabox.client.runtime

import org.junit.Assert.assertEquals
import org.junit.Test

class StartDeadlineTest {
    @Test
    fun `deadline uses challenge only for an interactive user wait`() {
        assertEquals(45_000L, deadlineFor(interactive = false, waitingUser = false))
        assertEquals(45_000L, deadlineFor(interactive = false, waitingUser = true))
        assertEquals(45_000L, deadlineFor(interactive = true, waitingUser = false))
        assertEquals(120_000L, deadlineFor(interactive = true, waitingUser = true))
    }
}
