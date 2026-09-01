package io.hydrabox.platform.android

import io.hydrabox.core.contract.CommandGeneration
import io.hydrabox.core.contract.EventSequence
import io.hydrabox.core.contract.ProcessEpoch
import io.hydrabox.core.contract.RuntimeCommand
import io.hydrabox.core.contract.RuntimeEvent
import io.hydrabox.core.contract.RuntimeGeneration
import io.hydrabox.core.contract.RuntimeSnapshot
import io.hydrabox.core.contract.RuntimeTransport
import io.hydrabox.core.runtime.Effect
import io.hydrabox.core.runtime.RuntimeInput
import io.hydrabox.core.runtime.RuntimeModel
import io.hydrabox.core.runtime.reduce
import java.util.UUID

class AndroidRuntime(private val execute: (Effect) -> Unit) : RuntimeTransport {
    private val epoch = ProcessEpoch(UUID.randomUUID().toString())
    private var model = RuntimeModel()
    private var sequence = 0L
    private val listeners = mutableSetOf<(RuntimeEvent) -> Unit>()

    override fun submit(command: RuntimeCommand) {
        dispatch(when (command) {
        is RuntimeCommand.Start -> RuntimeInput.Start(command.mode)
        RuntimeCommand.Stop -> RuntimeInput.Stop
        RuntimeCommand.Reload -> RuntimeInput.Reload
        is RuntimeCommand.SelectOutbound -> RuntimeInput.SelectOutbound(io.hydrabox.core.contract.OutboundSelection(command.groupId, command.outboundId))
        is RuntimeCommand.NetworkChanged -> RuntimeInput.NetworkChanged(command.generation)
        })
    }

    fun dispatch(input: RuntimeInput) = synchronized(this) {
        reduce(model, input).also { decision ->
            model = decision.state
            decision.effects.forEach(execute)
            sequence += 1
            val event = RuntimeEvent.Snapshot(EventSequence(sequence), snapshot())
            listeners.toList().forEach { it(event) }
        }
    }

    override fun snapshot() = RuntimeSnapshot(epoch, CommandGeneration(model.commandGeneration), RuntimeGeneration(model.runtimeGeneration), model.networkGeneration, EventSequence(sequence), model.state, model.mode, model.selectedOutbounds, model.health, model.failure, model.traffic, model.latencies)

    override fun subscribe(listener: (RuntimeEvent) -> Unit): AutoCloseable = synchronized(this) {
        listeners += listener
        listener(RuntimeEvent.Snapshot(EventSequence(sequence), snapshot()))
        AutoCloseable { synchronized(this) { listeners -= listener } }
    }
}
