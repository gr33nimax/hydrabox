package io.hydrabox.client.singbox

/** Process-neutral runtime event target; the core process must not depend on Flutter classes. */
interface RuntimeEventConsumer {
    fun success(event: Any?)

    fun error(code: String, message: String?, details: Any?)

    fun endOfStream()
}
