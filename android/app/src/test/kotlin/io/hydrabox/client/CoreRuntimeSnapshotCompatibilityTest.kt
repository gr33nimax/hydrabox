package io.hydrabox.client

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Test

class CoreRuntimeSnapshotCompatibilityTest {
    @Test
    fun `running authoritative snapshot supplies legacy owner evidence`() {
        val snapshot = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder()
            .setState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING)
            .setMode(CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN)
            .setGeneration(7)
            .build()

        val status = snapshot.toLegacyRuntimeMap()

        assertEquals(true, status["running"])
        assertEquals(true, status["recordedServiceAlive"])
        assertEquals(true, status["activeRuntimeOwner"])
        assertEquals(false, status["nativeRecoveryPending"])
        assertEquals(true, status["runtimeSnapshotAuthoritative"])
    }

    @Test
    fun `recovering authoritative snapshot stays pending without claiming running`() {
        val snapshot = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder()
            .setState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING)
            .setMode(CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN)
            .setGeneration(8)
            .build()

        val status = snapshot.toLegacyRuntimeMap()

        assertEquals(false, status["running"])
        assertEquals(true, status["recordedServiceAlive"])
        assertEquals(false, status["activeRuntimeOwner"])
        assertEquals(true, status["nativeRecoveryPending"])
    }
}
