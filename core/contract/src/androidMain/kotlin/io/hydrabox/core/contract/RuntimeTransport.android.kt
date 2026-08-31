package io.hydrabox.core.contract

actual interface RuntimeTransport {
    actual fun submit(command: RuntimeCommand)
    actual fun snapshot(): RuntimeSnapshot
    actual fun subscribe(listener: (RuntimeEvent) -> Unit): AutoCloseable
}
