package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RuntimeStateMachineTest {
    @Test
    fun `start from stopped enters starting`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED, commandGeneration = 4),
            RuntimeInput.Command.Start,
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, decision.state.value)
        assertEquals(5L, decision.state.commandGeneration)
        assertEquals(START_DEADLINE_MILLIS, decision.deadlineMillis)
    }

    @Test
    fun `ready health enters running`() {
        val decision = reduce(
            RuntimeMachineState(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
                commandGeneration = 4,
                runtimeGeneration = 9,
            ),
            RuntimeInput.Event.Health(commandGeneration = 4, runtimeGeneration = 9, ready = true),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, decision.state.value)
        assertNull(decision.deadlineMillis)
    }

    @Test
    fun `challenge health retains state and rearms deadline`() {
        val state = RuntimeMachineState(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
            commandGeneration = 4,
            runtimeGeneration = 9,
        )

        val decision = reduce(
            state,
            RuntimeInput.Event.Health(
                commandGeneration = 4,
                runtimeGeneration = 9,
                ready = false,
                challenge = true,
            ),
            RuntimeReduceContext(),
        )

        assertEquals(state, decision.state)
        assertEquals(CHALLENGE_DEADLINE_MILLIS, decision.deadlineMillis)
    }

    @Test
    fun `deadline fails active start`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, commandGeneration = 4),
            RuntimeInput.Event.Deadline(commandGeneration = 4),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED, decision.state.value)
        assertNull(decision.deadlineMillis)
    }

    @Test
    fun `stop during starting enters stopping and released stops`() {
        val stopping = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, commandGeneration = 4),
            RuntimeInput.Command.Stop,
            RuntimeReduceContext(),
        )
        val stopped = reduce(
            stopping.state,
            RuntimeInput.Event.Released(commandGeneration = 5, success = true),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING, stopping.state.value)
        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED, stopped.state.value)
    }

    @Test
    fun `stale launched event is ignored`() {
        val state = RuntimeMachineState(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
            commandGeneration = 4,
        )

        val decision = reduce(
            state,
            RuntimeInput.Event.Launched(commandGeneration = 3, runtimeGeneration = 9),
            RuntimeReduceContext(),
        )

        assertEquals(state, decision.state)
        assertNull(decision.deadlineMillis)
    }

    @Test
    fun `released success stops stopping runtime`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING, commandGeneration = 4),
            RuntimeInput.Event.Released(commandGeneration = 4, success = true),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED, decision.state.value)
    }

    @Test
    fun `released failure follows shutdown deadline path`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING, commandGeneration = 4),
            RuntimeInput.Event.Released(commandGeneration = 4, success = false),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED, decision.state.value)
    }

    @Test
    fun `stale released event is ignored`() {
        val state = RuntimeMachineState(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING,
            commandGeneration = 4,
        )

        val decision = reduce(
            state,
            RuntimeInput.Event.Released(commandGeneration = 3, success = true),
            RuntimeReduceContext(),
        )

        assertEquals(state, decision.state)
    }
}
