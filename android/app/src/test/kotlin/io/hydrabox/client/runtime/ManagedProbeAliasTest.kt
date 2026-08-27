package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertTrue
import org.junit.Test

class ManagedProbeAliasTest {
    @Test
    fun `terminal sessions remove all managed aliases`() {
        val aliases = (1..20).associate { "native-$it" to "session-$it" }
        val terminalStates = listOf(
            CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_COMPLETED,
            CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_PARTIAL,
            CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_CANCELLED,
            CoreRuntimeProtocol.ProbeSessionState.PROBE_SESSION_STATE_TIMED_OUT,
        )
        val sessions = (1..20).mapIndexed { index, id ->
            CoreRuntimeProtocol.ProbeSession.newBuilder()
                .setSessionId("session-$id")
                .setState(terminalStates[index % terminalStates.size])
                .build()
        }

        assertTrue(pruneAliases(aliases, sessions).isEmpty())
    }
}
