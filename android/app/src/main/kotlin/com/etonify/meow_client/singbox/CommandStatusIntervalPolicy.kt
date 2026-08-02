package com.etonify.meow_client.singbox

import java.util.concurrent.TimeUnit

internal object CommandStatusIntervalPolicy {
    private const val STANDARD_INTERVAL_SECONDS = 1L
    private const val ECONOMY_INTERVAL_SECONDS = 2L

    fun intervalNanos(performanceMode: String?): Long {
        val seconds = if (performanceMode == "economy") {
            ECONOMY_INTERVAL_SECONDS
        } else {
            STANDARD_INTERVAL_SECONDS
        }
        return TimeUnit.SECONDS.toNanos(seconds)
    }
}
