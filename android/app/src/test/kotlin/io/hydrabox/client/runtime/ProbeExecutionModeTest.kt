package io.hydrabox.client.runtime

import org.junit.Assert.assertEquals
import org.junit.Test

class ProbeExecutionModeTest {
    @Test
    fun `compiled profile always uses isolated runtime even while vpn is running`() {
        assertEquals(
            ProbeExecutionMode.EPHEMERAL,
            selectProbeExecutionMode(runtimeRunning = true, compiledConfigBytes = 1024),
        )
    }

    @Test
    fun `compiled profile can be probed before connecting`() {
        assertEquals(
            ProbeExecutionMode.EPHEMERAL,
            selectProbeExecutionMode(runtimeRunning = false, compiledConfigBytes = 1024),
        )
    }

    @Test
    fun `managed probe requires a running runtime when no plan was supplied`() {
        assertEquals(
            ProbeExecutionMode.MANAGED,
            selectProbeExecutionMode(runtimeRunning = true, compiledConfigBytes = 0),
        )
        assertEquals(
            ProbeExecutionMode.REJECT_MISSING_PLAN,
            selectProbeExecutionMode(runtimeRunning = false, compiledConfigBytes = 0),
        )
    }
}
