package io.hydrabox.platform.android

/**
 * No offline sweep is waiting for a baseline. Used as the resting value of the generation a
 * sweep would otherwise be waiting on.
 */
internal const val NO_MEASUREMENT_BASELINE = -1L

/**
 * Whether a network callback is the baseline a just-started offline sweep was waiting for,
 * rather than a handover that ends it.
 *
 * A service created to measure is born before `ConnectivityManager` has delivered its first
 * callback, so the uplink that arrives first is the network the sweep should measure on, not a
 * move away from one. That first callback has to be told apart from a handover, and the
 * generation does it: the sweep records the generation it began from, and the baseline is the
 * first callback *newer* than it.
 *
 * True only while a baseline is pending ([baselineGeneration] is not
 * [NO_MEASUREMENT_BASELINE]) and the callback is newer than the generation the sweep started
 * from. The caller takes the pending baseline as it asks, so the next callback — a genuine
 * handover — is no longer a baseline and ends the sweep.
 */
internal fun isOfflineMeasurementBaseline(
    callbackGeneration: Long,
    baselineGeneration: Long,
): Boolean = baselineGeneration != NO_MEASUREMENT_BASELINE && callbackGeneration > baselineGeneration
