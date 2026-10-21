package io.hydrabox.platform.android

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class UpdateEntryTest {
    @Test fun `checks on entry and return but not on repeated callbacks or rotation`() {
        val entry = UpdateEntry()
        assertTrue(entry.enter())
        assertFalse(entry.enter())
        entry.leave(changingConfigurations = true)
        assertFalse(entry.enter())
        entry.leave(changingConfigurations = false)
        assertTrue(entry.enter())
    }
}
