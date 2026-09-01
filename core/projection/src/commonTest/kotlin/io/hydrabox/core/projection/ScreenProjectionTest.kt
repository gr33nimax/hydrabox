package io.hydrabox.core.projection

import io.hydrabox.core.contract.*
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ScreenProjectionTest {
    private fun snapshot(state: RuntimeState, failure: RuntimeFailure? = null) = RuntimeSnapshot(ProcessEpoch("p"), CommandGeneration(1), RuntimeGeneration(1), NetworkGeneration(1), EventSequence(1), state, RuntimeMode.VPN, lastFailure = failure)

    @Test fun `projection derives phase and available action without timers`() {
        assertEquals(ScreenPhase.DISCONNECTED, ScreenProjection.project(snapshot(RuntimeState.STOPPED)).phase)
        assertEquals(ScreenPhase.CONNECTING, ScreenProjection.project(snapshot(RuntimeState.STARTING)).phase)
        val running = ScreenProjection.project(snapshot(RuntimeState.RUNNING)); assertEquals(ScreenPhase.CONNECTED, running.phase); assertTrue(running.canStop); assertFalse(running.canStart)
    }

    @Test fun `projection exposes only error code text`() {
        val state = ScreenProjection.project(snapshot(RuntimeState.FAILED, RuntimeFailure(FailureDomain.DNS, HydraCoreErrorCode.DNS_UPSTREAM_TIMEOUT, true)))
        assertEquals("dns.upstream.timeout", state.errorCode); assertTrue(state.canRetry)
    }

    @Test fun `projection exposes selected outbound without a second UI state`() {
        val source = snapshot(RuntimeState.RUNNING).copy(selectedOutbounds = listOf(OutboundSelection("default", "proxy-a")))
        assertEquals("proxy-a", ScreenProjection.project(source).activeOutbound)
    }
}
