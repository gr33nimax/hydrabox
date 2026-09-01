package io.hydrabox.core.diagnostics

@JvmInline
value class Secret private constructor(private val value: String) {
    companion object {
        fun of(value: String) = Secret(value)
        fun openWith(ciphertext: ByteArray, opener: SecretOpener) = Secret(opener.open(ciphertext))
    }

    fun sealWith(sealer: SecretSealer): ByteArray = sealer.seal(value)
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
