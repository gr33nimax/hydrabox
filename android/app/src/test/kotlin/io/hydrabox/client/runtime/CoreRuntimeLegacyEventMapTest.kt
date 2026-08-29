package io.hydrabox.client.runtime

import com.google.protobuf.ByteString
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Test

class CoreRuntimeLegacyEventMapTest {
    @Test
    fun `event desired runtime map preserves the durable intent`() {
        val snapshot = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder()
            .setDesiredRuntime(
                CoreRuntimeProtocol.DesiredRuntime.newBuilder()
                    .setWantRunning(true)
                    .setMode(CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY)
                    .setConfigSha256(ByteString.copyFromUtf8("a".repeat(64)))
                    .setRecoveryAttempt(2),
            )
            .build()

        assertEquals(
            mapOf(
                "wantRunning" to true,
                "mode" to "proxy",
                "configSha256" to "a".repeat(64),
                "recoveryAttempt" to 2,
            ),
            snapshot.toLegacyDesiredRuntimeMap(),
        )
    }
}
