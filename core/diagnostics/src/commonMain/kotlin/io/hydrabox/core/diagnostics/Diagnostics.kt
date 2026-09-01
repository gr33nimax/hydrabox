package io.hydrabox.core.diagnostics

import io.hydrabox.core.model.OperationState

@JvmInline
value class Secret private constructor(private val value: String) {
    companion object {
        fun of(value: String) = Secret(value)
        fun openWith(ciphertext: ByteArray, opener: SecretOpener) = Secret(opener.open(ciphertext))
    }

    fun sealWith(sealer: SecretSealer): ByteArray = sealer.seal(value)

    /**
     * Narrow, deliberate escape hatch for the few producers that must materialise the
     * plaintext: sealing it into storage and writing it into a core configuration.
     * Never call this from a code path that renders text for a human or a log.
     */
    fun <T> use(block: (String) -> T): T = block(value)

    override fun toString(): String = "Secret(redacted)"
}

fun interface SecretSealer {
    fun seal(plaintext: String): ByteArray
}

fun interface SecretOpener {
    fun open(ciphertext: ByteArray): String
}

sealed interface DiagnosticField {
    data class Text(val value: String) : DiagnosticField
    data class Count(val value: Long) : DiagnosticField
}

data class DiagnosticEvent(
    val code: String,
    val fields: List<DiagnosticField> = emptyList(),
)

fun interface DiagnosticSink {
    fun emit(event: DiagnosticEvent)
}

enum class LogLevel { ERROR, WARN, INFO, DEBUG }

data class DiagnosticsState(
    val events: List<DiagnosticEvent> = emptyList(),
    val level: LogLevel = LogLevel.INFO,
    val export: OperationState<String> = OperationState.Idle,
)
