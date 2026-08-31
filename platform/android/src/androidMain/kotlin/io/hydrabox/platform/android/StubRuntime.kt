package io.hydrabox.platform.android

import io.hydrabox.core.contract.CommandGeneration
import io.hydrabox.core.contract.EventSequence
import io.hydrabox.core.contract.NetworkGeneration
import io.hydrabox.core.contract.ProcessEpoch
import io.hydrabox.core.contract.RuntimeCommand
import io.hydrabox.core.contract.RuntimeEvent
import io.hydrabox.core.contract.RuntimeGeneration
import io.hydrabox.core.contract.RuntimeSnapshot
import io.hydrabox.core.contract.RuntimeMode
import io.hydrabox.core.contract.RuntimeState
import io.hydrabox.core.contract.RuntimeTransport
import java.util.UUID

/** Temporary B03 runtime; replace rather than extend it in H2-C04. */
class StubRuntime : RuntimeTransport {
    private val epoch = ProcessEpoch(UUID.randomUUID().toString())
    private var sequence = 0L
    private var generation = 0L
    private var state = RuntimeState.STOPPED
    private var mode: RuntimeMode? = null
    private var snapshot = newSnapshot()
    private val listeners = mutableSetOf<(RuntimeEvent) -> Unit>()

    override fun submit(command: RuntimeCommand) = synchronized(this) {
        when (command) {
            is RuntimeCommand.Start -> {
                generation += 1
                state = RuntimeState.RUNNING
                mode = command.mode
            }
            RuntimeCommand.Stop -> {
                state = RuntimeState.STOPPED
                mode = null
            }
            else -> Unit
        }
        snapshot = newSnapshot()
        val event = RuntimeEvent.Snapshot(EventSequence(sequence), snapshot)
        listeners.toList().forEach { it(event) }
    }

    override fun snapshot(): RuntimeSnapshot = synchronized(this) { snapshot }

    override fun subscribe(listener: (RuntimeEvent) -> Unit): AutoCloseable = synchronized(this) {
        listeners += listener
        listener(RuntimeEvent.Snapshot(EventSequence(sequence), snapshot))
        AutoCloseable { synchronized(this) { listeners -= listener } }
    }

    private fun newSnapshot() = RuntimeSnapshot(
        processEpoch = epoch,
        commandGeneration = CommandGeneration(generation),
        runtimeGeneration = RuntimeGeneration(generation),
        networkGeneration = NetworkGeneration(0),
        lastEventSequence = EventSequence(++sequence),
        state = state,
        mode = mode,
    )
}
