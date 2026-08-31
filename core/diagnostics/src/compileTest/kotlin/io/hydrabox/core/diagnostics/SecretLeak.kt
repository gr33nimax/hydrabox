package io.hydrabox.core.diagnostics

fun leak(sink: DiagnosticSink) {
    sink.emit(Secret.of("must not compile"))
}
