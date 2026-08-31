package io.hydrabox.core.diagnostics

@JvmInline
value class Secret private constructor(private val value: String) {
    companion object { fun of(value: String) = Secret(value) }
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
