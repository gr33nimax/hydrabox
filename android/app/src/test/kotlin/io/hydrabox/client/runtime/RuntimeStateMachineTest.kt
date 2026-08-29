package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RuntimeStateMachineTest {
    private fun start(
        commandId: String,
        digest: String = "a",
        mode: CoreRuntimeProtocol.RuntimeMode = CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN,
    ) = RuntimeInput.Command.Start(
        commandId = commandId,
        configSha256 = digest,
        mode = mode,
    )

    private fun activeStart(vararg commandIds: String) = ActiveCommand(
        kind = CoreRuntimeProtocol.CommandKind.COMMAND_KIND_START,
        configSha256 = "a",
        mode = CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN,
        commandGeneration = 4,
        commandIds = commandIds.toMutableList(),
    )

    @Test
    fun `start stop start leaves no command without a decision`() {
        val starting = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED, 3),
            start("start-1"),
            RuntimeReduceContext(),
        )
        val stopping = reduce(starting.state, RuntimeInput.Command.Stop("stop-1"), RuntimeReduceContext())
        val nextStart = reduce(stopping.state, start("start-2", "b"), RuntimeReduceContext())

        assertEquals(RuntimeCommandDecision.Queue, nextStart.commandDecision)
    }

    @Test
    fun `double stop joins the active stop`() {
        val decision = reduce(
            RuntimeMachineState(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING,
                4,
                activeCommand = ActiveCommand(
                    CoreRuntimeProtocol.CommandKind.COMMAND_KIND_STOP,
                    "",
                    CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_UNSPECIFIED,
                    4,
                    mutableListOf("stop-1"),
                ),
            ),
            RuntimeInput.Command.Stop("stop-2"),
            RuntimeReduceContext(),
        )

        assertEquals(RuntimeCommandDecision.Join, decision.commandDecision)
    }

    @Test
    fun `same digest start during starting joins without another launch`() {
        val decision = reduce(
            RuntimeMachineState(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
                4,
                activeCommand = activeStart("start-1"),
            ),
            start("start-2"),
            RuntimeReduceContext(),
        )

        assertEquals(RuntimeCommandDecision.NoOp, decision.commandDecision)
        assertEquals(activeStart("start-1"), decision.state.activeCommand)
    }

    @Test
    fun `changed profile during starting supersedes the first start`() {
        val decision = reduce(
            RuntimeMachineState(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
                4,
                activeCommand = activeStart("start-1"),
            ),
            start("start-2", "b"),
            RuntimeReduceContext(),
        )

        assertEquals(RuntimeCommandDecision.Supersede, decision.commandDecision)
    }

    @Test
    fun `different mode start during running stops before deferred start`() {
        val decision = reduce(
            RuntimeMachineState(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING,
                4,
                activeCommand = activeStart("start-1"),
            ),
            start("start-2", mode = CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING, decision.state.value)
        assertEquals(5L, decision.state.commandGeneration)
        assertEquals(RuntimeCommandDecision.Supersede, decision.commandDecision)
    }

    @Test
    fun `same mode start during running does not stop`() {
        val decision = reduce(
            RuntimeMachineState(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING,
                4,
                activeCommand = activeStart("start-1"),
            ),
            start("start-2"),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, decision.state.value)
        assertEquals(RuntimeCommandDecision.NoOp, decision.commandDecision)
    }

    @Test
    fun `network change during stopping is rejected`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING, 4),
            RuntimeInput.Command.NetworkChanged(),
            RuntimeReduceContext(),
        )

        assertEquals(RuntimeCommandDecision.Reject, decision.commandDecision)
    }

    @Test
    fun `network change during starting applies underlying without rebind`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, 4),
            RuntimeInput.Command.NetworkChanged(),
            RuntimeReduceContext(),
        )

        assertEquals(NetworkChangeAction.ApplyUnderlying, decision.networkChangeAction)
        assertEquals(4L, decision.state.commandGeneration)
    }

    @Test
    fun `network change during running applies underlying and rebind`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, 4),
            RuntimeInput.Command.NetworkChanged(),
            RuntimeReduceContext(),
        )

        assertEquals(NetworkChangeAction.ApplyUnderlyingAndRebind, decision.networkChangeAction)
        assertEquals(4L, decision.state.commandGeneration)
    }

    @Test
    fun `network change during starting keeps launch generation current`() {
        val afterNetwork = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, 4),
            RuntimeInput.Command.NetworkChanged(),
            RuntimeReduceContext(),
        )
        val launched = reduce(
            afterNetwork.state,
            RuntimeInput.Event.Launched(commandGeneration = 4, runtimeGeneration = 9),
            RuntimeReduceContext(),
        )

        assertEquals(9L, launched.state.runtimeGeneration)
    }

    @Test
    fun `start from stopped enters starting`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED, commandGeneration = 4),
            RuntimeInput.Command.Start(),
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
    fun `inapplicable health before launched does not enter running`() {
        val state = RuntimeMachineState(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
            commandGeneration = 4,
        )

        val decision = reduce(
            state,
            RuntimeInput.Event.Health(commandGeneration = 4, runtimeGeneration = 0, ready = true, applicable = false),
            RuntimeReduceContext(),
        )

        assertEquals(state, decision.state)
    }

    @Test
    fun `inapplicable health enters running after launched`() {
        val launched = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, commandGeneration = 4),
            RuntimeInput.Event.Launched(commandGeneration = 4, runtimeGeneration = 9),
            RuntimeReduceContext(),
        )

        val decision = reduce(
            launched.state,
            RuntimeInput.Event.Health(commandGeneration = 4, runtimeGeneration = 9, ready = true, applicable = false),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, decision.state.value)
    }

    @Test
    fun `applicable health after launched stays starting until ready`() {
        val launched = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, commandGeneration = 4),
            RuntimeInput.Event.Launched(commandGeneration = 4, runtimeGeneration = 9),
            RuntimeReduceContext(),
        )

        val decision = reduce(
            launched.state,
            RuntimeInput.Event.Health(commandGeneration = 4, runtimeGeneration = 9, ready = false, applicable = true),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING, decision.state.value)
    }

    @Test
    fun `health with stale runtime generation is ignored after launched`() {
        val state = RuntimeMachineState(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STARTING,
            commandGeneration = 4,
            runtimeGeneration = 9,
        )

        val decision = reduce(
            state,
            RuntimeInput.Event.Health(commandGeneration = 4, runtimeGeneration = 8, ready = true),
            RuntimeReduceContext(),
        )

        assertEquals(state, decision.state)
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
    fun `running health with active lanes stays running`() {
        val state = RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, 4, 9)
        val decision = reduce(state, RuntimeInput.Event.Health(4, 9, ready = true, activeLanes = 1, applicable = true), RuntimeReduceContext())
        assertEquals(state, decision.state)
    }

    @Test
    fun `running health loss inside grace stays running`() {
        val state = RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, 4, 9)
        val decision = reduce(state, RuntimeInput.Event.Health(4, 9, ready = false, applicable = true, lostForMillis = LOST_GRACE_MILLIS - 1), RuntimeReduceContext())
        assertEquals(state, decision.state)
    }

    @Test
    fun `running health loss after grace enters recovering with recovery deadline`() {
        val state = RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, 4, 9)
        val decision = reduce(state, RuntimeInput.Event.Health(4, 9, ready = false, applicable = true, lostForMillis = LOST_GRACE_MILLIS), RuntimeReduceContext())
        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RECOVERING, decision.state.value)
        assertEquals(RECOVERY_DEADLINE_MILLIS, decision.deadlineMillis)
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
            RuntimeInput.Command.Stop(),
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
    fun `stop without a runtime releases immediately and only once`() {
        val stopping = reduce(
            RuntimeMachineState(
                CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING,
                commandGeneration = 4,
                runtimeGeneration = 0,
            ),
            RuntimeInput.Event.Released(commandGeneration = 4, success = true),
            RuntimeReduceContext(),
        )
        val duplicate = reduce(
            stopping.state,
            RuntimeInput.Event.Released(commandGeneration = 4, success = true),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPED, stopping.state.value)
        assertEquals(stopping.state, duplicate.state)
        assertEquals(true, canReleaseImmediately(runtimeGeneration = 0, hasActiveServices = false))
        assertEquals(false, canReleaseImmediately(runtimeGeneration = 1, hasActiveServices = false))
        assertEquals(false, canReleaseImmediately(runtimeGeneration = 0, hasActiveServices = true))
    }

    @Test
    fun `released outside stopping is ignored`() {
        val state = RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING, commandGeneration = 4)

        val decision = reduce(
            state,
            RuntimeInput.Event.Released(commandGeneration = 4, success = true),
            RuntimeReduceContext(),
        )

        assertEquals(state, decision.state)
    }

    @Test
    fun `released failure follows shutdown deadline path`() {
        val decision = reduce(
            RuntimeMachineState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING, commandGeneration = 4),
            RuntimeInput.Event.Released(commandGeneration = 4, success = false),
            RuntimeReduceContext(),
        )

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED, decision.state.value)
        assertEquals("runtime.stop.unconfirmed", decision.errorCode)
    }

    @Test
    fun `released failure is terminal exactly once`() {
        val stopping = RuntimeMachineState(
            CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_STOPPING,
            commandGeneration = 4,
        )
        val released = RuntimeInput.Event.Released(commandGeneration = 4, success = false)
        val first = reduce(stopping, released, RuntimeReduceContext())
        val duplicate = reduce(first.state, released, RuntimeReduceContext())
        val commandResults = listOf(stopping to first, first.state to duplicate)
            .count { (before, decision) -> decision.state != before }

        assertEquals(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_FAILED, first.state.value)
        assertEquals("runtime.stop.unconfirmed", first.errorCode)
        assertEquals(first.state, duplicate.state)
        assertEquals(1, commandResults)
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
