package io.hydrabox.platform.android

import io.hydrabox.core.contract.OutboundLatency
import io.hydrabox.core.contract.TrafficCounters
import io.hydrabox.core.runtime.RuntimeInput
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator

/**
 * Observes the running core: traffic counters and the delay its own latency group measured
 * per outbound. Observation only — it issues no decision, and everything it learns reaches
 * the UI through the snapshot, never directly.
 */
class CoreObserver(
    private val dispatch: (RuntimeInput) -> Unit,
    private val onLog: (String) -> Unit = {},
) {
    private var client: CommandClient? = null

    fun start() {
        if (client != null) return
        val options = CommandClientOptions().apply {
            addCommand(Libbox.CommandStatus)
            addCommand(Libbox.CommandGroup)
            statusInterval = STATUS_INTERVAL_NANOS
        }
        val created = Libbox.newCommandClient(handler, options) ?: return
        client = created
        runCatching { created.connect() }.onFailure { onLog("status stream unavailable: ${it.message}") }
    }

    fun stop() {
        runCatching { client?.disconnect() }
        client = null
        dispatch(RuntimeInput.Traffic(TrafficCounters(available = false)))
    }

    /** Selects inside the running core, so switching server does not restart the tunnel. */
    fun select(group: String, outbound: String): Boolean =
        runCatching { requireNotNull(client).selectOutbound(group, outbound) }.isSuccess

    fun reload(): Boolean = runCatching { requireNotNull(client).serviceReload() }.isSuccess

    /** Measures every member of a group now, instead of waiting for the next interval. */
    fun measure(group: String): Boolean =
        runCatching { requireNotNull(client).startURLTest(group) }.isSuccess

    private val handler = object : CommandClientHandler {
        override fun connected() = Unit

        override fun disconnected(message: String?) {
            dispatch(RuntimeInput.Traffic(TrafficCounters(available = false)))
        }

        override fun clearLogs() = Unit

        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) = Unit

        override fun setDefaultLogLevel(level: Int) = Unit

        override fun updateClashMode(newMode: String?) = Unit

        override fun writeConnectionEvents(events: ConnectionEvents?) = Unit

        override fun writeLogs(messageList: LogIterator?) {
            while (messageList?.hasNext() == true) onLog(messageList.next().message)
        }

        override fun writeStatus(message: StatusMessage?) {
            message ?: return
            dispatch(
                RuntimeInput.Traffic(
                    TrafficCounters(
                        available = message.trafficAvailable,
                        uplink = message.uplink,
                        downlink = message.downlink,
                        uplinkTotal = message.uplinkTotal,
                        downlinkTotal = message.downlinkTotal,
                        connectionsOut = message.connectionsOut,
                    ),
                ),
            )
        }

        override fun writeGroups(message: OutboundGroupIterator?) {
            val collected = mutableListOf<OutboundLatency>()
            while (message?.hasNext() == true) {
                val items = message.next().items
                while (items.hasNext()) {
                    val item = items.next()
                    val status = item.urlTestStatus.orEmpty()
                    if (item.urlTestDelay > 0 || status.isNotEmpty()) {
                        collected += OutboundLatency(item.tag, item.urlTestDelay, status)
                    }
                }
            }
            if (collected.isNotEmpty()) dispatch(RuntimeInput.Latencies(collected))
        }
    }

    private companion object {
        const val STATUS_INTERVAL_NANOS = 1_000_000_000L
    }
}
