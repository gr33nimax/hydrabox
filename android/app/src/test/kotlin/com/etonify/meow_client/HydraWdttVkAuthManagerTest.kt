package com.etonify.meow_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HydraWdttVkAuthManagerTest {
    @Test
    fun `normalizes VK TURN URLs before the native bridge`() {
        assertEquals(
            "turn.example:3478",
            normalizeHydraWdttTurnAddress("turn:turn.example:3478?transport=udp"),
        )
        assertEquals(
            "[2001:db8::1]:5349",
            normalizeHydraWdttTurnAddress("turns:[2001:db8::1]:5349"),
        )
    }

    @Test
    fun `rejects malformed TURN addresses`() {
        assertNull(normalizeHydraWdttTurnAddress("https://turn.example"))
        assertNull(normalizeHydraWdttTurnAddress("turn:turn.example:0"))
        assertNull(normalizeHydraWdttTurnAddress("turn:turn.example:70000"))
    }
}
