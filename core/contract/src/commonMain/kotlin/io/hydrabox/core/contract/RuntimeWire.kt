package io.hydrabox.core.contract

/**
 * Platform-neutral wire schema shared by Android Binder and the future desktop pipe.
 *
 * This deliberately uses only common Kotlin so transport implementations, rather
 * than the contract, own their platform serialization APIs.
 */
object RuntimeWire {
    private const val SCHEMA = "1"

    fun encode(command: RuntimeCommand): ByteArray = when (command) {
        is RuntimeCommand.Start -> pack("command", "start", command.mode.name)
        RuntimeCommand.Stop -> pack("command", "stop")
        RuntimeCommand.Reload -> pack("command", "reload")
        is RuntimeCommand.SelectOutbound -> pack("command", "select", text(command.groupId), text(command.outboundId))
        is RuntimeCommand.NetworkChanged -> pack("command", "network", command.generation.value.toString())
    }.encodeToByteArray()

    fun decodeCommand(bytes: ByteArray): RuntimeCommand {
        val fields = unpack(bytes.decodeToString(), "command")
        return when (fields.removeFirst()) {
            "start" -> RuntimeCommand.Start(RuntimeMode.valueOf(fields.single()))
            "stop" -> RuntimeCommand.Stop.also { check(fields.isEmpty()) }
            "reload" -> RuntimeCommand.Reload.also { check(fields.isEmpty()) }
            "select" -> RuntimeCommand.SelectOutbound(readText(fields.removeFirst()), readText(fields.removeFirst())).also { check(fields.isEmpty()) }
            "network" -> RuntimeCommand.NetworkChanged(NetworkGeneration(fields.single().toLong()))
            else -> error("Unknown runtime command")
        }
    }

    fun encode(snapshot: RuntimeSnapshot): ByteArray = pack(
        "snapshot",
        text(snapshot.processEpoch.value),
        snapshot.commandGeneration.value.toString(),
        snapshot.runtimeGeneration.value.toString(),
        snapshot.networkGeneration.value.toString(),
        snapshot.lastEventSequence.value.toString(),
        snapshot.state.name,
        snapshot.mode?.name ?: "",
        snapshot.selectedOutbounds.size.toString(),
        *snapshot.selectedOutbounds.flatMap { listOf(text(it.groupId), text(it.outboundId)) }.toTypedArray(),
        snapshot.transportHealth.state.name,
        snapshot.transportHealth.activeLanes.toString(),
        snapshot.transportHealth.applicable.toString(),
        snapshot.transportHealth.runtimeGeneration.value.toString(),
        snapshot.transportHealth.networkGeneration.value.toString(),
        failure(snapshot.transportHealth.failure),
        failure(snapshot.lastFailure),
    ).encodeToByteArray()

    fun decodeSnapshot(bytes: ByteArray): RuntimeSnapshot {
        val fields = unpack(bytes.decodeToString(), "snapshot")
        val processEpoch = ProcessEpoch(readText(fields.removeFirst()))
        val commandGeneration = CommandGeneration(fields.removeFirst().toLong())
        val runtimeGeneration = RuntimeGeneration(fields.removeFirst().toLong())
        val networkGeneration = NetworkGeneration(fields.removeFirst().toLong())
        val eventSequence = EventSequence(fields.removeFirst().toLong())
        val state = RuntimeState.valueOf(fields.removeFirst())
        val mode = fields.removeFirst().ifEmpty { null }?.let(RuntimeMode::valueOf)
        val outbounds = List(fields.removeFirst().toInt()) {
            OutboundSelection(readText(fields.removeFirst()), readText(fields.removeFirst()))
        }
        val health = TransportHealth(
            state = TransportHealthState.valueOf(fields.removeFirst()),
            activeLanes = fields.removeFirst().toInt(),
            applicable = fields.removeFirst().toBooleanStrict(),
            runtimeGeneration = RuntimeGeneration(fields.removeFirst().toLong()),
            networkGeneration = NetworkGeneration(fields.removeFirst().toLong()),
            failure = readFailure(fields.removeFirst()),
        )
        val lastFailure = readFailure(fields.removeFirst())
        check(fields.isEmpty())
        return RuntimeSnapshot(processEpoch, commandGeneration, runtimeGeneration, networkGeneration, eventSequence, state, mode, outbounds, health, lastFailure)
    }

    private fun failure(value: RuntimeFailure?): String = value?.let { "${it.domain.name},${it.code.name},${it.retryable}" } ?: ""

    private fun readFailure(value: String): RuntimeFailure? = value.ifEmpty { return null }.split(',').let {
        check(it.size == 3)
        RuntimeFailure(FailureDomain.valueOf(it[0]), HydraCoreErrorCode.valueOf(it[1]), it[2].toBooleanStrict())
    }

    private fun pack(type: String, vararg fields: String): String = listOf(SCHEMA, type, *fields).joinToString("|")

    private fun unpack(value: String, type: String): MutableList<String> = value.split('|').toMutableList().also {
        check(it.removeFirst() == SCHEMA && it.removeFirst() == type) { "Unsupported runtime wire message" }
    }

    private fun text(value: String): String = value.map { it.code.toString(16).padStart(4, '0') }.joinToString("")

    private fun readText(value: String): String {
        check(value.length % 4 == 0)
        return buildString { value.chunked(4).forEach { append(it.toInt(16).toChar()) } }
    }
}
