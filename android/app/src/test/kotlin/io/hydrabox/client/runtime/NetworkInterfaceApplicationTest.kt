package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.nekohasekai.libbox.InterfaceUpdateListener
import org.junit.Assert.assertEquals
import org.junit.Test

class NetworkInterfaceApplicationTest {
    @Test
    fun `apply underlying updates default interface without rebind`() {
        val calls = mutableListOf<String>()

        applyNetworkChangeAction(
            NetworkChangeAction.ApplyUnderlying,
            networkPayload(),
            listOf(recordingListener(calls)),
            { calls += "generation:$it" },
            { throw AssertionError(it) },
        )

        assertEquals(listOf("interface:wlan0:7"), calls)
    }

    @Test
    fun `apply underlying and rebind sets generation before interface update`() {
        val calls = mutableListOf<String>()

        applyNetworkChangeAction(
            NetworkChangeAction.ApplyUnderlyingAndRebind,
            networkPayload(),
            listOf(recordingListener(calls)),
            { calls += "generation:$it" },
            { throw AssertionError(it) },
        )

        assertEquals(listOf("generation:5", "interface:wlan0:7"), calls)
    }

    @Test
    fun `starting replay applies default interface to a new listener`() {
        val calls = mutableListOf<String>()
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, 5),
            RuntimeInput.Command.NetworkChanged(networkPayload()),
            RuntimeReduceContext(),
        )

        assertEquals(false, rejectsNetworkChange(decision, 5, 5, replay = true))

        applyNetworkChangeAction(
            decision.networkChangeAction,
            networkPayload(),
            listOf(recordingListener(calls)),
            { calls += "generation:$it" },
            { throw AssertionError(it) },
        )

        assertEquals(listOf("interface:wlan0:7"), calls)
    }

    @Test
    fun `invalid interface index and tun interface are never published`() {
        listOf(
            networkPayload(interfaceIndex = -1),
            networkPayload(interfaceName = "tun0"),
        ).forEach { payload ->
            NetworkChangeAction.entries.forEach { action ->
                val calls = mutableListOf<String>()
                applyNetworkChangeAction(
                    action,
                    payload,
                    listOf(recordingListener(calls)),
                    { calls += "generation:$it" },
                    { throw AssertionError(it) },
                )

                assertEquals(
                    if (action == NetworkChangeAction.ApplyUnderlyingAndRebind) listOf("generation:5") else emptyList(),
                    calls,
                )
            }
        }
    }

    private fun networkPayload(interfaceName: String = "wlan0", interfaceIndex: Int = 7) =
        CoreRuntimeProtocol.NetworkChanged.newBuilder()
            .setNetworkGeneration(5)
            .setInterfaceName(interfaceName)
            .setInterfaceIndex(interfaceIndex)
            .setAvailable(interfaceIndex >= 0)
            .build()

    private fun recordingListener(calls: MutableList<String>) = object : InterfaceUpdateListener {
        override fun updateDefaultInterface(name: String, index: Int, expensive: Boolean, isVpn: Boolean) {
            calls += "interface:$name:$index"
        }
    }
}
