package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadinessThresholdTest {
    @Test
    fun `readiness requires an active lane unless health is inapplicable`() {
        fun health(
            applicable: Boolean = true,
            state: CoreRuntimeProtocol.TransportHealthState,
            lanes: Int,
        ) = CoreRuntimeProtocol.TransportHealthSnapshot.newBuilder()
            .setApplicable(applicable)
            .setState(state)
            .setActiveLanes(lanes)
            .build()

        assertFalse(isReady(health(state = CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_HEALTHY, lanes = 0)))
        assertTrue(isReady(health(state = CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_HEALTHY, lanes = 1)))
        assertTrue(isReady(health(applicable = false, state = CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_STARTING, lanes = 0)))
        assertFalse(isReady(health(state = CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_WAITING_USER, lanes = 1)))
    }
}
