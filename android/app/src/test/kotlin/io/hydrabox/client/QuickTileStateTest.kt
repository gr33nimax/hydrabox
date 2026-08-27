package io.hydrabox.client

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickTileStateTest {
    @Test
    fun `active tile states are running and transitional states only`() {
        assertTrue(tileActiveFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING))
        assertTrue(tileActiveFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING))
        assertTrue(tileActiveFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING))
        assertFalse(tileActiveFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED))
        assertFalse(tileActiveFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING))
        assertFalse(tileActiveFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED))
        assertFalse(tileActiveFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_PREPARING))
        assertFalse(tileActiveFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_UNSPECIFIED))
    }
}
