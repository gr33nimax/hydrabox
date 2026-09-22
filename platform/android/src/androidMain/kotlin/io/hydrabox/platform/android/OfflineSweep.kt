package io.hydrabox.platform.android

import io.hydrabox.core.contract.OutboundLatency

/**
 * One offline measurement pass: the cheap workerless edge questions first, the standalone
 * HTTP sessions after, each published as its own answer.
 *
 * Isolation is the contract, not the order: a timeout, a refusal or an exception belongs to
 * the server it happened to and to nobody else, so one dead server can never cancel, reset
 * or answer for the rest. The whole pass may be abandoned — a new press, a stop, a revoke or
 * a handover — and nothing measured across that boundary is published: results collected
 * across a handover are a comparison that only holds within one network.
 *
 * How many sessions run at once is an implementation detail and not part of that contract.
 *
 * The rules live here, away from the service, so they are testable without a core, the
 * platform or a device.
 */
internal class OfflineSweep(
    private val isCancelled: () -> Boolean,
    private val networkStillCurrent: () -> Boolean,
    private val measureEdge: (String) -> OutboundLatency?,
    private val measureHttp: (String) -> OutboundLatency,
    private val publishEdge: (List<OutboundLatency>) -> Unit,
    private val publishHttp: (List<OutboundLatency>) -> Unit,
    private val reportStopped: (Int) -> Unit = {},
    /**
     * The servers whose question is still open: the whole set when the pass starts, one fewer
     * after each answer. A row leaves the set the moment its own question closes, so no row is
     * left spinning by another row's failure.
     */
    private val onProgress: (Set<String>) -> Unit = {},
) {
    data class Target(
        val id: String,
        val type: String?,
    )

    fun run(targets: List<Target>) {
        val pending = targets.mapTo(LinkedHashSet()) { it.id }
        // Every server the press asked about is named at once: the rows say they are being
        // asked while their own question is open, instead of holding a figure nobody has
        // confirmed yet.
        onProgress(pending.toSet())
        val answered = mutableListOf<String>()
        // The cheap questions go first, as their own pass: each costs a bounded couple of
        // seconds, while every HTTP session ahead of it builds a whole core instance — and
        // the sessions used to spend the edge pass's entire budget before its turn came,
        // leaving the call rows nothing to show for the press that asked for them.
        for (target in targets) {
            if (isCancelled()) {
                reportStopped(answered.size)
                return
            }
            if (!target.type.equals("call", ignoreCase = true)) continue
            val answer = ask { measureEdge(target.id) }
            if (isCancelled() || !networkStillCurrent()) {
                reportStopped(answered.size)
                return
            }
            if (answer != null) {
                publishEdge(listOf(answer))
                answered += target.id
            }
            pending -= target.id
            onProgress(pending.toSet())
        }
        // Each session costs a core instance, and a refused server costs its whole timeout —
        // which is the price of one row's own question and is never charged to another row.
        for (target in targets) {
            if (target.type.equals("call", ignoreCase = true)) continue
            if (isCancelled()) {
                reportStopped(answered.size)
                return
            }
            val answer = ask { measureHttp(target.id) }
            if (isCancelled() || !networkStillCurrent()) {
                reportStopped(answered.size)
                return
            }
            // Each answer is useful immediately. The reducer replaces only this tag, so rows
            // that are still waiting retain their previous RTT instead of flashing blank.
            if (answer != null) {
                publishHttp(listOf(answer))
                answered += target.id
            }
            pending -= target.id
            onProgress(pending.toSet())
        }
    }

    /**
     * One target's question, isolated: a measurement that throws — a transport refusing the
     * profile, a platform call failing — is that target's outcome and nobody else's, and the
     * pass goes on to the next server with its row closed rather than left spinning.
     */
    private inline fun <T> ask(question: () -> T): T? = runCatching(question).getOrNull()
}
