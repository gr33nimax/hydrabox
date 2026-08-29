package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class TransportHealthBridgeTest {
    @Test
    fun `old health uses local applicability fallback and internal failure domain`() {
        val health = TransportHealthBridge.parse(
            """{"schema_version":2,"health":{"state":"healthy","active_lanes":1,"total_lanes":8,"failure":{"stage":"dial","kind":"network"}}}""",
            fallbackApplicable = true,
        )

        assertEquals(true, health.applicable)
        assertEquals("INTERNAL", health.failure.failureDomain)
        assertFalse(health.failure.failureTerminal)
    }

    @Test
    fun `new health prefers core applicability and reads additive failure fields`() {
        val health = TransportHealthBridge.parse(
            """{"schema_version":2,"health":{"applicable":true,"state":"degraded","active_lanes":1,"total_lanes":8,"runtime_generation":7,"network_generation":9,"failure":{"domain":"NETWORK","terminal":true}}}""",
            fallbackApplicable = true,
        )

        assertEquals(true, health.applicable)
        assertEquals("NETWORK", health.failure.failureDomain)
        assertEquals(true, health.failure.failureTerminal)
        assertEquals(7L, health.runtimeGeneration)
        assertEquals(9L, health.networkGeneration)
    }
}
