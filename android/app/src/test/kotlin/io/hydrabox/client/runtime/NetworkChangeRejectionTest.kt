package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.nekohasekai.libbox.InterfaceUpdateListener
import org.junit.Assert.assertEquals
import org.junit.Test

class NetworkChangeRejectionTest {
    @Test
    fun `network change during stopping keeps state and reports rejection`() {
        assertRejectedNetworkChange(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING, 6, 5)
    }

    @Test
    fun `stale network change during running keeps state and reports rejection`() {
        assertRejectedNetworkChange(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, 5, 5)
    }

    @Test
    fun `unconfirmed stop remains a failed runtime result`() {
        val released = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING, commandGeneration = 9),
            RuntimeInput.Event.Released(commandGeneration = 9, success = false),
            RuntimeReduceContext(),
        )
        val result = failedCommandResult(
            "stop:9",
            released.state.value,
            9,
            CoreRuntimeProtocol.CoreError.newBuilder().setCode(released.errorCode).build(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED, result.finalState)
        assertEquals("runtime.stop.unconfirmed", result.error.code)
    }

    private fun assertRejectedNetworkChange(
        runtimeState: CoreRuntimeProtocol.RuntimeState,
        networkGeneration: Long,
        appliedNetworkGeneration: Long,
    ) {
        val listeners = mutableListOf<String>()
        val decision = reduce(
            RuntimeMachineState(runtimeState, commandGeneration = 9),
            RuntimeInput.Command.NetworkChanged(
                networkPayload(networkGeneration),
                listeners = listOf(recordingListener(listeners)),
            ),
            RuntimeReduceContext(),
        )

        val rejected = rejectsNetworkChange(decision, networkGeneration, appliedNetworkGeneration, replay = false)

        assertEquals(true, rejected)
        if (!rejected) {
            applyNetworkChangeAction(
                decision.networkChangeAction,
                networkPayload(networkGeneration),
                listOf(recordingListener(listeners)),
                { listeners += "generation:$it" },
                { throw AssertionError(it) },
            )
        }
        val result = failedCommandResult(
            "network:$networkGeneration",
            runtimeState,
            9,
            networkRejectedError("network:$networkGeneration"),
        )

        assertEquals(runtimeState, result.finalState)
        assertEquals(CoreRuntimeProtocol.CommandOutcome.COMMAND_OUTCOME_FAILED, result.outcome)
        assertEquals("runtime.network.rejected", result.error.code)
        assertEquals(emptyList<String>(), listeners)
    }

    private fun networkPayload(networkGeneration: Long) = CoreRuntimeProtocol.NetworkChanged.newBuilder()
        .setNetworkGeneration(networkGeneration)
        .setInterfaceName("wlan0")
        .setInterfaceIndex(7)
        .build()

    private fun recordingListener(calls: MutableList<String>) = object : InterfaceUpdateListener {
        override fun updateDefaultInterface(name: String, index: Int, expensive: Boolean, isVpn: Boolean) {
            calls += "interface:$name:$index"
        }
    }

    private fun networkRejectedError(commandId: String) = CoreRuntimeProtocol.CoreError.newBuilder()
        .setCode("runtime.network.rejected")
        .setStage("network_changed")
        .setCorrelationId(commandId)
        .build()
}
