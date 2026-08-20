package io.hydrabox.client.singbox

object RuntimeEventCadence {
    const val BACKGROUND_EVENT_INTERVAL_MS = 5_000L
    const val IDLE_EVENT_INTERVAL_MS = 30_000L

    fun intervalMillis(
        uiForeground: Boolean,
        screenInteractive: Boolean,
        performanceMode: String?,
    ): Long {
        if (!uiForeground) {
            return if (screenInteractive) BACKGROUND_EVENT_INTERVAL_MS else IDLE_EVENT_INTERVAL_MS
        }
        return when (performanceMode?.lowercase()) {
            "performance" -> 250L
            "balanced" -> 500L
            else -> 1_000L
        }
    }
}
