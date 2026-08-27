package io.hydrabox.client

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class CoreRuntimeSnapshotCompatibilityTest {
    @Test
    fun `running authoritative snapshot omits synthesized owner evidence`() {
        val snapshot = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder()
            .setState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING)
            .setMode(CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN)
            .setGeneration(7)
            .build()

        val status = snapshot.toLegacyRuntimeMap()

        assertEquals(true, status["running"])
        assertFalse(status.containsKey("recordedServiceAlive"))
        assertFalse(status.containsKey("activeRuntimeOwner"))
        assertFalse(status.containsKey("runtimeIntentFresh"))
        assertFalse(status.containsKey("nativeRecoveryPending"))
        assertFalse(status.containsKey("runtimeSnapshotAuthoritative"))
    }

    @Test
    fun `recovering authoritative snapshot reports its state without synthesized fields`() {
        val snapshot = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder()
            .setState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING)
            .setMode(CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN)
            .setGeneration(8)
            .build()

        val status = snapshot.toLegacyRuntimeMap()

        assertEquals(false, status["running"])
        assertEquals("RUNTIME_STATE_RECOVERING", status["state"])
        assertFalse(status.containsKey("recordedServiceAlive"))
        assertFalse(status.containsKey("activeRuntimeOwner"))
        assertFalse(status.containsKey("runtimeIntentFresh"))
        assertFalse(status.containsKey("nativeRecoveryPending"))
        assertFalse(status.containsKey("runtimeSnapshotAuthoritative"))
    }
}
