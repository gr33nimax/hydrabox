package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeStatusProjectionTest {
    @Test
    fun `runtime states project to foreground notification statuses`() {
        assertEquals("Connecting", notificationStatusFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING))
        assertEquals("Connecting", notificationStatusFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING))
        assertEquals("Connected", notificationStatusFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING))
        assertEquals("Disconnecting", notificationStatusFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING))
        assertEquals("Failed", notificationStatusFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED))
        assertEquals(null, notificationStatusFor(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED))
    }
}
