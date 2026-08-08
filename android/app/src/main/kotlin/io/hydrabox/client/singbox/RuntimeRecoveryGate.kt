package io.hydrabox.client.singbox

import java.util.concurrent.atomic.AtomicLong

/**
 * Coalesces Android wake signals that commonly arrive as a short burst
 * (for example SCREEN_ON followed by USER_PRESENT).
 */
internal class RuntimeRecoveryGate(
    private val minimumIntervalMillis: Long,
) {
    private val lastAcceptedAtMillis = AtomicLong(NO_TIMESTAMP)

    init {
        require(minimumIntervalMillis >= 0L)
    }

    fun tryAcquire(nowMillis: Long): Boolean {
        while (true) {
            val previous = lastAcceptedAtMillis.get()
            if (
                previous != NO_TIMESTAMP &&
                nowMillis >= previous &&
                nowMillis - previous < minimumIntervalMillis
            ) {
                return false
            }
            if (lastAcceptedAtMillis.compareAndSet(previous, nowMillis)) {
                return true
            }
        }
    }

    fun reset() {
        lastAcceptedAtMillis.set(NO_TIMESTAMP)
    }

    private companion object {
        const val NO_TIMESTAMP = Long.MIN_VALUE
    }
}
