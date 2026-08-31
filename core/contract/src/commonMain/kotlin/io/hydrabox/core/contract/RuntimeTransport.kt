package io.hydrabox.core.contract

expect interface RuntimeTransport {
    fun submit(command: RuntimeCommand)
    fun snapshot(): RuntimeSnapshot
    fun subscribe(listener: (RuntimeEvent) -> Unit): AutoCloseable
}
