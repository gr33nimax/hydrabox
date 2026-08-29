package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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

    @Test
    fun `core inapplicability overrides a locally required transport`() {
        val health = readTransportHealth(
            readSnapshot = { """{"schema_version":2,"health":{"applicable":false}}""" },
            fallbackApplicable = true,
        )

        assertFalse(health.applicable)
        assertTrue(isReady(health))
    }

    @Test
    fun `core applicability still requires an active lane`() {
        val health = readTransportHealth(
            readSnapshot = {
                """{"schema_version":2,"health":{"applicable":true,"state":"healthy","active_lanes":0}}"""
            },
            fallbackApplicable = false,
        )

        assertTrue(health.applicable)
        assertFalse(isReady(health))
    }

    @Test
    fun `missing applicability falls back locally`() {
        val health = readTransportHealth(
            readSnapshot = { """{"schema_version":2,"health":{"state":"healthy","active_lanes":1}}""" },
            fallbackApplicable = true,
        )

        assertTrue(health.applicable)
    }

    @Test
    fun `snapshot read failure is not replaced by local applicability`() {
        val health = readTransportHealth(
            readSnapshot = { throw IllegalStateException("transport unavailable") },
            fallbackApplicable = false,
        )

        assertTrue(health.applicable)
        assertEquals(
            CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_FAILED,
            health.state,
        )
        assertEquals("runtime.transport.snapshot", health.failure.code)
    }
}
