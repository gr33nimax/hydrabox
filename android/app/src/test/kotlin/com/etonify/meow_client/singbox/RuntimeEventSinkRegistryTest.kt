package com.etonify.meow_client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeEventSinkRegistryTest {
    @Test
    fun `late cancel from replaced Flutter engine cannot clear current sink`() {
        val registry = RuntimeEventSinkRegistry<String>()
        val oldRegistration = registry.register("old")
        val currentRegistration = registry.register("current")

        assertFalse(registry.clear(oldRegistration))
        assertEquals("current", registry.current())
        assertTrue(registry.canControl(currentRegistration))
        assertFalse(registry.canControl(oldRegistration))
    }

    @Test
    fun `current engine can detach and unowned lifecycle update is then accepted`() {
        val registry = RuntimeEventSinkRegistry<String>()
        val registration = registry.register("current")

        assertTrue(registry.clear(registration))
        assertNull(registry.current())
        assertFalse(registry.hasActiveRegistration())
        assertTrue(registry.canControl(0L))
    }

    @Test
    fun `unowned stale lifecycle update cannot override attached engine`() {
        val registry = RuntimeEventSinkRegistry<String>()
        registry.register("current")

        assertFalse(registry.canControl(0L))
    }
}
