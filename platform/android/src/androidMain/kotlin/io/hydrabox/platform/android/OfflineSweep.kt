package io.hydrabox.platform.android

import io.hydrabox.core.contract.OutboundLatency

/**
 * One offline measurement pass: the cheap workerless edge questions first, the sequential
 * standalone HTTP sessions after, each published as its own answer.
 *
 * The rules live here, away from the service, so they are testable without a core, the
 * platform or a device. The pass ends the moment its epoch moves or its sweep is
 * cancelled — a stop, a revoke, or a handover — and nothing it measured is published
 * unless the network it was measured on is still the network the device is on: results
 * collected across a handover are a comparison that only holds within one network.
 */
internal class OfflineSweep(
    private val isCancelled: () -> Boolean,
    private val networkStillCurrent: () -> Boolean,
    private val measureEdge: (String) -> OutboundLatency?,
    private val measureHttp: (String) -> OutboundLatency,
    private val publishEdge: (List<OutboundLatency>) -> Unit,
    private val publishHttp: (List<OutboundLatency>) -> Unit,
    private val reportStopped: (Int) -> Unit = {},
    private val onProgress: (String) -> Unit = {},
    /** The pass's overall budget: after it, the remaining targets are left as they were. */
    private val withinDeadline: () -> Boolean = { true },
    /** How many targets the budget did not reach, so the pass never truncates silently. */
    private val reportSkipped: (Int) -> Unit = {},
) {
    data class Target(
        val id: String,
        val type: String?,
    )

    fun run(targets: List<Target>) {
        // The cheap questions go first, as their own pass: each costs a bounded couple of
        // seconds, while every HTTP session ahead of it builds a whole core instance — and
        // the sessions used to spend the edge pass's entire budget before its turn came,
        // leaving the call rows nothing to show for the press that asked for them.
        var completed = 0
        for (target in targets) {
            if (isCancelled()) break
            if (!target.type.equals("call", ignoreCase = true)) continue
            onProgress(target.id)
            val answer = measureEdge(target.id) ?: continue
            if (isCancelled() || !networkStillCurrent()) break
            publishEdge(listOf(answer))
            completed++
        }
        // ponytail: sessions own a full core instance; parallelize only if sequential sweeps
        // become slower than the flood-control and memory cost of concurrent call transports.
        //
        // Each session costs a core instance, and a refused server costs its whole timeout, so
        // the pass needs a budget: without one it held the single runtime lifecycle thread for
        // minutes on a long list, and start/stop queued behind it — which is exactly what "the
        // app is stuck" turned out to be. Targets the budget does not reach keep the figures
        // they had, and are reported rather than dropped in silence.
        val httpTargets = targets.filterNot { it.type.equals("call", ignoreCase = true) }
        var skipped = 0
        for ((index, target) in httpTargets.withIndex()) {
            if (isCancelled()) {
                reportStopped(completed)
                return
            }
            if (!withinDeadline()) {
                skipped = httpTargets.size - index
                break
            }
            onProgress(target.id)
            val answer = measureHttp(target.id)
            if (isCancelled() || !networkStillCurrent()) {
                reportStopped(completed)
                return
            }
            // Each answer is useful immediately. The reducer replaces only this tag, so rows
            // that are still waiting retain their previous RTT instead of flashing blank.
            publishHttp(listOf(answer))
            completed++
        }
        if (skipped > 0) reportSkipped(skipped)
    }
}
