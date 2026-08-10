package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IdentityListenerRegistryTest {
    private class EqualListener(private val id: Int) {
        override fun equals(other: Any?): Boolean = other is EqualListener
        override fun hashCode(): Int = 1
        override fun toString(): String = "listener-$id"
    }

    @Test
    fun `equal listeners keep independent lifecycles`() {
        val first = EqualListener(1)
        val second = EqualListener(2)
        val registry = IdentityListenerRegistry<EqualListener>()

        assertTrue(registry.add(first))
        assertTrue(registry.add(second))
        assertEquals(2, registry.size())

        assertTrue(registry.remove(first))
        assertFalse(registry.contains(first))
        assertTrue(registry.contains(second))
        assertEquals(listOf(second), registry.snapshot())
    }
}
