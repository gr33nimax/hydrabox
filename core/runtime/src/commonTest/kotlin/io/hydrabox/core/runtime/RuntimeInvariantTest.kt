package io.hydrabox.core.runtime

import io.hydrabox.core.contract.NetworkGeneration
import io.hydrabox.core.contract.OutboundSelection
import io.hydrabox.core.contract.RuntimeGeneration
import io.hydrabox.core.contract.RuntimeMode
import io.hydrabox.core.contract.RuntimeState
import io.hydrabox.core.contract.TransportHealth
import io.hydrabox.core.contract.TransportHealthState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RuntimeInvariantTest {
    @Test fun `R1 only decision changes runtime model`() = assertEquals(RuntimeModel(), reduce(RuntimeModel(), RuntimeInput.Stop).state)
    @Test fun `R2 snapshot data stays in the model`() = assertEquals(RuntimeState.STARTING, reduce(RuntimeModel(), RuntimeInput.Start(RuntimeMode.VPN)).state.state)
    @Test fun `R3 reducer returns effects without executing them`() = assertEquals(listOf(Effect.StartCore(RuntimeMode.VPN, 1)), reduce(RuntimeModel(), RuntimeInput.Start(RuntimeMode.VPN)).effects)
    @Test fun `R4 network change creates one rebind`() = assertEquals(1, reduce(RuntimeModel(state = RuntimeState.RUNNING), RuntimeInput.NetworkChanged(NetworkGeneration(1))).effects.size)
    @Test fun `R5 reducer has no retry effect`() = assertEquals(emptyList(), reduce(RuntimeModel(state = RuntimeState.FAILED), RuntimeInput.Stop).effects.filterIsInstance<Effect.StartCore>())
    @Test fun `R6 generations remain distinct typed values`() = assertEquals(NetworkGeneration(1), NetworkGeneration(1))
    @Test fun `R7 stop clears want running`() = assertEquals(false, reduce(RuntimeModel(state = RuntimeState.RUNNING, wantRunning = true), RuntimeInput.Stop).state.wantRunning)
    @Test fun `R8 deadline clears want running`() = assertEquals(false, reduce(reduce(RuntimeModel(), RuntimeInput.Start(RuntimeMode.VPN)).state, RuntimeInput.Deadline(1)).state.wantRunning)
    @Test fun `R9 automatic recovery is capped`() = assertEquals(RuntimeState.RUNNING, reduce(RuntimeModel(state = RuntimeState.RUNNING, mode = RuntimeMode.VPN, wantRunning = true, recoveryAttempts = 2), RuntimeInput.DeviceIdleExit).state.state)
    @Test fun `R10 ready is required for running`() = assertEquals(RuntimeState.STARTING, reduce(RuntimeModel(state = RuntimeState.STARTING, commandGeneration = 1, runtimeGeneration = 2), RuntimeInput.Health(1, 2, TransportHealth())).state.state)
    @Test fun `R11 runtime state is produced without UI input`() = assertEquals(RuntimeState.STARTING, reduce(RuntimeModel(), RuntimeInput.Start(RuntimeMode.PROXY)).state.state)
    @Test fun `R12 stale event does not advance state`() = assertEquals(1, reduce(RuntimeModel(state = RuntimeState.STARTING, commandGeneration = 1), RuntimeInput.Launched(2, 9)).state.commandGeneration)
    @Test fun `R13 outbound selection is owned by model`() = assertEquals(listOf(OutboundSelection("g", "o")), reduce(RuntimeModel(state = RuntimeState.RUNNING), RuntimeInput.SelectOutbound(OutboundSelection("g", "o"))).state.selectedOutbounds)
    @Test fun `R14 core transition does not change contract types`() = assertEquals(RuntimeGeneration(3), RuntimeGeneration(3))
    @Test fun `R15 stop always declares close directly`() = assertEquals(listOf(Effect.StopCore(1)), reduce(RuntimeModel(state = RuntimeState.RUNNING), RuntimeInput.Stop).effects)
    @Test fun `R16 state changes only from an explicit runtime input`() = assertEquals(RuntimeModel(), reduce(RuntimeModel(), RuntimeInput.NetworkChanged(NetworkGeneration(1))).state)
    @Test fun `R17 stale network generation is ignored`() = assertEquals(NetworkGeneration(2), reduce(RuntimeModel(state = RuntimeState.RUNNING, networkGeneration = NetworkGeneration(2)), RuntimeInput.NetworkChanged(NetworkGeneration(1))).state.networkGeneration)
    @Test fun `R18 health carries typed failure domain`() = assertEquals(TransportHealthState.FAILED, TransportHealth(state = TransportHealthState.FAILED).state)
    @Test fun `R19 stop has one terminal transition path`() = assertEquals(RuntimeState.STOPPING, reduce(RuntimeModel(state = RuntimeState.RUNNING), RuntimeInput.Stop).state.state)
    @Test fun `R20 stopped state has no live runtime generation`() = assertEquals(0, reduce(RuntimeModel(state = RuntimeState.STOPPING, commandGeneration = 1, runtimeGeneration = 9), RuntimeInput.Released(1, true)).state.runtimeGeneration)
}
