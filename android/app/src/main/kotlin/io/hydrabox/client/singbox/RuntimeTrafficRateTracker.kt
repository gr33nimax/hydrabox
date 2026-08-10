package io.hydrabox.client.singbox

internal data class RuntimeTrafficRates(
    val uplink: Long,
    val downlink: Long,
)

/**
 * Converts monotonic traffic totals into bytes per second when a native status
 * source reports totals but leaves its instantaneous rate fields at zero.
 */
internal class RuntimeTrafficRateTracker {
    private var previousUplinkTotal: Long? = null
    private var previousDownlinkTotal: Long? = null
    private var previousObservedAtMillis: Long? = null

    @Synchronized
    fun update(
        nativeUplink: Long,
        nativeDownlink: Long,
        uplinkTotal: Long,
        downlinkTotal: Long,
        observedAtMillis: Long,
    ): RuntimeTrafficRates {
        val previousUplink = previousUplinkTotal
        val previousDownlink = previousDownlinkTotal
        val previousObservedAt = previousObservedAtMillis
        val elapsedMillis = previousObservedAt?.let { observedAtMillis - it } ?: 0L

        val derivedUplink = bytesPerSecond(
            currentTotal = uplinkTotal,
            previousTotal = previousUplink,
            elapsedMillis = elapsedMillis,
        )
        val derivedDownlink = bytesPerSecond(
            currentTotal = downlinkTotal,
            previousTotal = previousDownlink,
            elapsedMillis = elapsedMillis,
        )

        previousUplinkTotal = uplinkTotal
        previousDownlinkTotal = downlinkTotal
        previousObservedAtMillis = observedAtMillis
        return RuntimeTrafficRates(
            uplink = derivedUplink.takeIf { it > 0L } ?: nativeUplink.coerceAtLeast(0L),
            downlink = derivedDownlink.takeIf { it > 0L } ?: nativeDownlink.coerceAtLeast(0L),
        )
    }

    @Synchronized
    fun reset() {
        previousUplinkTotal = null
        previousDownlinkTotal = null
        previousObservedAtMillis = null
    }

    private fun bytesPerSecond(
        currentTotal: Long,
        previousTotal: Long?,
        elapsedMillis: Long,
    ): Long {
        if (previousTotal == null || elapsedMillis <= 0L || currentTotal < previousTotal) {
            return 0L
        }
        val delta = currentTotal - previousTotal
        if (delta <= 0L) return 0L
        return (delta.toDouble() * 1_000.0 / elapsedMillis.toDouble())
            .toLong()
            .coerceAtLeast(0L)
    }
}
