package io.hydrabox.client.runtime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BoundedRebindTest {
    @Test
    fun `only the first three automatic rebind attempts are allowed`() {
        assertTrue(shouldRebind(1))
        assertTrue(shouldRebind(2))
        assertTrue(shouldRebind(3))
        assertFalse(shouldRebind(4))
    }

    @Test
    fun `successful connection resets automatic rebind attempts`() {
        val attempts = RebindAttemptCounter()

        repeat(3) { assertTrue(attempts.next()) }
        assertFalse(attempts.next())
        attempts.reset()

        assertTrue(attempts.next())
    }

    @Test
    fun `explicit user reconnect resets automatic rebind attempts`() {
        val attempts = RebindAttemptCounter()

        repeat(3) { assertTrue(attempts.next()) }
        assertFalse(attempts.next())
        attempts.reset()

        assertTrue(attempts.next())
    }
}
