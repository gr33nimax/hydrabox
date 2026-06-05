package com.etonify.meow_client.singbox

import android.os.Handler
import android.os.Looper
import android.net.TrafficStats
import android.os.SystemClock
import android.util.Log
import com.etonify.meow_client.MeowApplication
import io.flutter.plugin.common.EventChannel
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogEntry
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

object SingboxController {
    private const val TAG = "MeowSingbox"
    private const val MAX_GROUP_ITEMS = 160
    private const val STATUS_EVENT_THROTTLE_MS = 1_000L
    private const val GROUPS_EVENT_THROTTLE_COOL_MS = 1_500L
    private const val GROUPS_EVENT_THROTTLE_BALANCED_MS = 750L
    private const val GROUPS_EVENT_THROTTLE_PERFORMANCE_MS = 500L
    private const val TRAFFIC_POLL_INTERVAL_MS = 1_000L
    private val mainHandler = Handler(Looper.getMainLooper())
    private val commandExecutor = Executors.newSingleThreadExecutor()
    private val lookupExecutor = Executors.newFixedThreadPool(4)
    private val statusEventScheduled = AtomicBoolean(false)
    private val groupsEventScheduled = AtomicBoolean(false)
    private val runtimeGeneration = AtomicLong(0)
    private val stopWaiterLock = Any()
    private val stopWaiters = mutableListOf<(Boolean) -> Unit>()

    @Volatile
    private var eventSink: EventChannel.EventSink? = null
    @Volatile
    private var latestStatusPayload: Map<String, Any?>? = null
    @Volatile
    private var latestGroupsPayload: Map<String, Any?>? = null
    @Volatile
    private var lastEmittedStatusPayload: Map<String, Any?>? = null
    @Volatile
    private var lastEmittedGroupsPayload: Map<String, Any?>? = null
    private var lastStatusEventUptimeMs: Long = 0
    private var lastGroupsEventUptimeMs: Long = 0

    @Volatile
    var running: Boolean = false
        private set

    @Volatile
    var serviceMode: String = ""
        private set

    @Volatile
    var activeRuntimeGeneration: Long = 0
        private set

    @Volatile
    var uplink: Long = 0
        private set

    @Volatile
    var downlink: Long = 0
        private set

    @Volatile
    var uplinkTotal: Long = 0
        private set

    @Volatile
    var downlinkTotal: Long = 0
        private set

    private var commandClient: CommandClient? = null
    private var trafficPollActive = false
    private var trafficBaselineRx = TrafficStats.UNSUPPORTED.toLong()
    private var trafficBaselineTx = TrafficStats.UNSUPPORTED.toLong()
    private var lastTrafficRx = TrafficStats.UNSUPPORTED.toLong()
    private var lastTrafficTx = TrafficStats.UNSUPPORTED.toLong()
    private var lastTrafficUptimeMs = 0L
    private val trafficPollRunnable = object : Runnable {
        override fun run() {
            pollAndroidTraffic()
            if (trafficPollActive) {
                mainHandler.postDelayed(this, TRAFFIC_POLL_INTERVAL_MS)
            }
        }
    }
    private val clientHandler = object : CommandClientHandler {
        override fun connected() {
            Log.i(TAG, "command client connected")
            MeowDiagnostics.log(TAG, "command client connected")
            emit(mapOf("type" to "client", "connected" to true))
        }

        override fun disconnected(message: String?) {
            Log.w(TAG, "command client disconnected message=$message")
            MeowDiagnostics.log(TAG, "command client disconnected message=$message")
            emit(mapOf("type" to "client", "connected" to false, "message" to message))
        }

        override fun clearLogs() {
            emit(mapOf("type" to "clearLogs"))
        }

        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) = Unit

        override fun setDefaultLogLevel(level: Int) {
            emit(mapOf("type" to "logLevel", "level" to level))
        }

        override fun updateClashMode(newMode: String?) = Unit

        override fun writeConnectionEvents(events: io.nekohasekai.libbox.ConnectionEvents?) = Unit

        override fun writeGroups(message: OutboundGroupIterator?) {
            if (message == null) return
            if (groupsEventScheduled.get()) return
            val groups = mutableListOf<Map<String, Any?>>()
            while (message.hasNext()) {
                val group = message.next()
                val items = mutableListOf<GroupItemPayload>()
                val iterator = group.items
                while (iterator.hasNext()) {
                    val item = iterator.next()
                    val delay = item.urlTestDelay
                    val time = item.urlTestTime
                    val status = item.urlTestStatus
                    val error = item.urlTestError
                    if (delay <= 0L &&
                        time <= 0L &&
                        status.isNullOrBlank() &&
                        error.isNullOrBlank()
                    ) {
                        continue
                    }
                    items += GroupItemPayload(
                        tag = item.tag,
                        type = item.type,
                        delay = delay.toLong(),
                        time = time,
                        status = status,
                        error = error,
                    )
                }
                groups += mapOf(
                    "tag" to group.tag,
                    "type" to group.type,
                    "selectable" to group.selectable,
                    "selected" to group.selected,
                    "expanded" to group.isExpand,
                    "items" to limitedGroupItems(group.tag, group.selected, items),
                )
            }
            emitCoalescedGroups(mapOf("type" to "groups", "groups" to groups))
        }

        override fun writeOutbounds(message: io.nekohasekai.libbox.OutboundGroupItemIterator?) = Unit

        override fun writeLogs(messageList: LogIterator?) {
            if (messageList == null) return
            val logs = mutableListOf<Map<String, Any?>>()
            while (messageList.hasNext()) {
                val entry: LogEntry = messageList.next()
                logs += mapOf(
                    "level" to entry.level,
                    "message" to entry.message,
                )
                MeowDiagnostics.log(TAG, "libbox log level=${entry.level} message=${entry.message}")
            }
            emit(mapOf("type" to "logs", "logs" to logs))
        }

        override fun writeStatus(message: StatusMessage?) {
            if (message == null) return
            uplink = message.uplink
            downlink = message.downlink
            uplinkTotal = message.uplinkTotal
            downlinkTotal = message.downlinkTotal
            emitCoalescedStatus(
                mapOf(
                    "type" to "status",
                    "uplink" to uplink,
                    "downlink" to downlink,
                    "uplinkTotal" to uplinkTotal,
                    "downlinkTotal" to downlinkTotal,
                    "connectionsIn" to message.connectionsIn,
                    "connectionsOut" to message.connectionsOut,
                    "trafficAvailable" to message.trafficAvailable,
                ),
            )
        }
    }

    private data class GroupItemPayload(
        val tag: String?,
        val type: String?,
        val delay: Long,
        val time: Long,
        val status: String?,
        val error: String?,
    ) {
        fun toEventMap(): Map<String, Any?> = mapOf(
            "tag" to tag,
            "type" to type,
            "delay" to delay,
            "time" to time,
            "status" to status,
            "error" to error,
        )
    }

    private fun limitedGroupItems(
        groupTag: String?,
        selectedTag: String?,
        items: List<GroupItemPayload>,
    ): List<Map<String, Any?>> {
        if (items.isEmpty()) {
            return emptyList()
        }
        if (groupTag == "select") {
            val selected = selectedTag?.trim().orEmpty()
            val selectedItem = items.firstOrNull { it.tag == selected }
            return when {
                selectedItem != null -> listOf(selectedItem.toEventMap())
                items.size == 1 -> items.map { it.toEventMap() }
                else -> emptyList()
            }
        }
        val selected = selectedTag?.trim().orEmpty()
        val sorted = items.sortedWith(
            compareBy<GroupItemPayload> {
                if (it.tag == selected) 0 else 1
            }.thenBy {
                if (it.delay > 0L) 0 else 1
            }.thenBy {
                if ((it.status ?: "").equals("unavailable", ignoreCase = true)) 1 else 0
            }.thenBy {
                if (it.delay > 0L) it.delay else Long.MAX_VALUE
            }.thenByDescending {
                it.time
            },
        )
        return sorted
            .take(MAX_GROUP_ITEMS)
            .map { it.toEventMap() }
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink != null) {
            emitCurrentState()
            emitCurrentStatus()
            if (running && commandClient == null) {
                connectClient()
            }
            if (running) {
                startTrafficPolling()
            }
        } else {
            stopTrafficPolling(reset = false)
            disconnectClient()
        }
    }

    fun setRunning(value: Boolean, mode: String = serviceMode, error: String? = null) {
        running = value
        serviceMode = if (value) mode else ""
        MeowDiagnostics.log(TAG, "setRunning value=$value mode=$serviceMode error=$error")
        if (!value) {
            uplink = 0
            downlink = 0
            uplinkTotal = 0
            downlinkTotal = 0
        }
        emitCurrentState(error)
        emitCurrentStatus()
        if (value) {
            if (eventSink != null) {
                connectClient()
                startTrafficPolling()
            }
        } else {
            stopTrafficPolling(reset = true)
            disconnectClient()
        }
    }

    fun markServiceStarted(mode: String): Long {
        val generation = runtimeGeneration.incrementAndGet()
        activeRuntimeGeneration = generation
        setRunning(true, mode)
        MeowDiagnostics.log(TAG, "markServiceStarted generation=$generation mode=$mode")
        return generation
    }

    fun markServiceStopped(generation: Long, reason: String) {
        val currentGeneration = activeRuntimeGeneration
        if (generation != 0L && generation != currentGeneration) {
            MeowDiagnostics.log(
                TAG,
                "markServiceStopped ignored stale generation=$generation current=$currentGeneration reason=$reason",
            )
            return
        }
        activeRuntimeGeneration = 0
        setRunning(false)
        MeowDiagnostics.log(TAG, "markServiceStopped generation=$generation reason=$reason")
        notifyStopWaiters(true)
    }

    fun awaitStopped(timeoutMs: Long = 5_000L, callback: (Boolean) -> Unit) {
        if (!running) {
            mainHandler.post { callback(true) }
            return
        }
        var fired = false
        lateinit var waiter: (Boolean) -> Unit
        waiter = { success ->
            if (!fired) {
                fired = true
                callback(success)
            }
        }
        synchronized(stopWaiterLock) {
            stopWaiters += waiter
        }
        mainHandler.postDelayed({
            val removed = synchronized(stopWaiterLock) {
                stopWaiters.remove(waiter)
            }
            if (removed) {
                waiter(false)
            }
        }, timeoutMs)
    }

    private fun notifyStopWaiters(success: Boolean) {
        val waiters = synchronized(stopWaiterLock) {
            stopWaiters.toList().also { stopWaiters.clear() }
        }
        for (waiter in waiters) {
            mainHandler.post { waiter(success) }
        }
    }

    fun log(level: String, message: String) {
        when (level.lowercase()) {
            "error" -> Log.e(TAG, message)
            "debug" -> Log.d(TAG, message)
            else -> Log.i(TAG, message)
        }
        MeowDiagnostics.log(TAG, "nativeLog level=$level message=$message")
        emit(mapOf("type" to "nativeLog", "level" to level, "message" to message))
    }

    fun connectClient() {
        commandExecutor.execute {
            disconnectClientOnExecutor("reconnect")
            runCatching {
                if (!running || eventSink == null) {
                    return@runCatching
                }
                MeowApplication.ensureLibboxSetup()
                Log.i(TAG, "connecting command client")
                MeowDiagnostics.log(TAG, "connecting command client")
                val options = CommandClientOptions().apply {
                    addCommand(Libbox.CommandGroup)
                    addCommand(Libbox.CommandLog)
                }
                val client = Libbox.newCommandClient(clientHandler, options)
                client.connect()
                commandClient = client
            }.onFailure {
                MeowDiagnostics.log(TAG, "command client connect failed", it)
                log("error", "command client connect failed: ${it.message}")
            }
        }
    }

    fun disconnectClient() {
        commandExecutor.execute {
            disconnectClientOnExecutor("async")
        }
    }

    fun disconnectClientBlocking(timeoutMs: Long = 1_500L): Boolean {
        val latch = CountDownLatch(1)
        commandExecutor.execute {
            try {
                disconnectClientOnExecutor("blocking")
            } finally {
                latch.countDown()
            }
        }
        return runCatching { latch.await(timeoutMs, TimeUnit.MILLISECONDS) }
            .getOrDefault(false)
    }

    private fun disconnectClientOnExecutor(reason: String) {
        val client = commandClient ?: return
        commandClient = null
        Log.i(TAG, "disconnecting command client reason=$reason")
        MeowDiagnostics.log(TAG, "disconnecting command client reason=$reason")
        runCatching { client.disconnect() }
    }

    private fun startTrafficPolling() {
        if (trafficPollActive) return
        val rx = TrafficStats.getUidRxBytes(android.os.Process.myUid())
        val tx = TrafficStats.getUidTxBytes(android.os.Process.myUid())
        trafficPollActive = true
        trafficBaselineRx = rx
        trafficBaselineTx = tx
        lastTrafficRx = rx
        lastTrafficTx = tx
        lastTrafficUptimeMs = SystemClock.uptimeMillis()
        mainHandler.removeCallbacks(trafficPollRunnable)
        mainHandler.postDelayed(trafficPollRunnable, TRAFFIC_POLL_INTERVAL_MS)
    }

    private fun stopTrafficPolling(reset: Boolean) {
        trafficPollActive = false
        mainHandler.removeCallbacks(trafficPollRunnable)
        trafficBaselineRx = TrafficStats.UNSUPPORTED.toLong()
        trafficBaselineTx = TrafficStats.UNSUPPORTED.toLong()
        lastTrafficRx = TrafficStats.UNSUPPORTED.toLong()
        lastTrafficTx = TrafficStats.UNSUPPORTED.toLong()
        lastTrafficUptimeMs = 0L
        if (reset) {
            uplink = 0
            downlink = 0
            uplinkTotal = 0
            downlinkTotal = 0
            emitCurrentStatus()
        }
    }

    private fun pollAndroidTraffic() {
        if (!running || eventSink == null) {
            stopTrafficPolling(reset = false)
            return
        }
        val rx = TrafficStats.getUidRxBytes(android.os.Process.myUid())
        val tx = TrafficStats.getUidTxBytes(android.os.Process.myUid())
        if (rx == TrafficStats.UNSUPPORTED.toLong() ||
            tx == TrafficStats.UNSUPPORTED.toLong() ||
            trafficBaselineRx == TrafficStats.UNSUPPORTED.toLong() ||
            trafficBaselineTx == TrafficStats.UNSUPPORTED.toLong()
        ) {
            emitCoalescedStatus(
                mapOf(
                    "type" to "status",
                    "uplink" to 0L,
                    "downlink" to 0L,
                    "uplinkTotal" to 0L,
                    "downlinkTotal" to 0L,
                    "connectionsIn" to 0,
                    "connectionsOut" to 0,
                    "trafficAvailable" to false,
                ),
            )
            return
        }
        val now = SystemClock.uptimeMillis()
        val elapsedMs = (now - lastTrafficUptimeMs).coerceAtLeast(1L)
        val rxDelta = (rx - lastTrafficRx).coerceAtLeast(0L)
        val txDelta = (tx - lastTrafficTx).coerceAtLeast(0L)
        downlink = rxDelta * 1000L / elapsedMs
        uplink = txDelta * 1000L / elapsedMs
        downlinkTotal = (rx - trafficBaselineRx).coerceAtLeast(0L)
        uplinkTotal = (tx - trafficBaselineTx).coerceAtLeast(0L)
        lastTrafficRx = rx
        lastTrafficTx = tx
        lastTrafficUptimeMs = now
        emitCoalescedStatus(
            mapOf(
                "type" to "status",
                "uplink" to uplink,
                "downlink" to downlink,
                "uplinkTotal" to uplinkTotal,
                "downlinkTotal" to downlinkTotal,
                "connectionsIn" to 0,
                "connectionsOut" to 0,
                "trafficAvailable" to true,
            ),
        )
    }

    private fun <T> withStandaloneCommandClient(block: (CommandClient) -> T): T {
        MeowApplication.ensureLibboxSetup()
        val client = Libbox.newStandaloneCommandClient()
        try {
            return block(client)
        } finally {
            runCatching { client.disconnect() }.onFailure {
                MeowDiagnostics.log(TAG, "standalone command client disconnect failed", it)
            }
        }
    }

    fun selectOutbound(groupTag: String, outboundTag: String, callback: (Result<Unit>) -> Unit) {
        log("info", "libbox selectOutbound group=$groupTag outbound=$outboundTag")
        commandExecutor.execute {
            val result = runCatching {
                withStandaloneCommandClient { client ->
                    client.selectOutbound(groupTag, outboundTag)
                }
            }
            result.onFailure {
                log("error", "libbox selectOutbound failed group=$groupTag outbound=$outboundTag error=${it.message}")
            }
            mainHandler.post { callback(result.map { Unit }) }
        }
    }

    fun addOutbound(selectorTag: String, outboundJson: String, callback: (Result<Unit>) -> Unit) {
        val tag = runCatching { org.json.JSONObject(outboundJson).optString("tag") }.getOrDefault("")
        val type = runCatching { org.json.JSONObject(outboundJson).optString("type") }.getOrDefault("")
        val detour = runCatching { org.json.JSONObject(outboundJson).optString("detour") }.getOrDefault("")
        log(
            "info",
            "libbox addOutbound selector=$selectorTag tag=$tag type=$type detour=$detour jsonChars=${outboundJson.length}",
        )
        commandExecutor.execute {
            val result = runCatching {
                withStandaloneCommandClient { client ->
                    client.addOutbound(selectorTag, outboundJson)
                }
            }
            result.onFailure {
                log("error", "libbox addOutbound failed selector=$selectorTag tag=$tag error=${it.message}")
            }
            mainHandler.post { callback(result.map { Unit }) }
        }
    }

    fun removeOutbound(selectorTag: String, outboundTag: String, callback: (Result<Unit>) -> Unit) {
        log("info", "libbox removeOutbound selector=$selectorTag outbound=$outboundTag")
        commandExecutor.execute {
            val result = runCatching {
                withStandaloneCommandClient { client ->
                    client.removeOutbound(selectorTag, outboundTag)
                }
            }
            result.onFailure {
                log("error", "libbox removeOutbound failed selector=$selectorTag outbound=$outboundTag error=${it.message}")
            }
            mainHandler.post { callback(result.map { Unit }) }
        }
    }

    fun urlTest(groupTag: String, callback: (Result<Unit>) -> Unit) {
        log("info", "libbox urlTest group=$groupTag")
        commandExecutor.execute {
            val result = runCatching {
                withStandaloneCommandClient { client ->
                    client.urlTest(groupTag)
                }
            }
            result.onFailure {
                log("error", "libbox urlTest failed group=$groupTag error=${it.message}")
            }
            mainHandler.post { callback(result.map { Unit }) }
        }
    }

    fun removeUrlTestOutbounds(groupTag: String, outboundTags: List<String>, callback: (Result<Unit>) -> Unit) {
        log(
            "info",
            "libbox removeURLTestOutbounds group=$groupTag count=${outboundTags.size} tags=${outboundTags.take(12).joinToString(",")}",
        )
        commandExecutor.execute {
            val result = runCatching {
                withStandaloneCommandClient { client ->
                    client.removeURLTestOutbounds(
                        groupTag,
                        outboundTags.joinToString("\n"),
                    )
                }
            }
            result.onFailure {
                log("error", "libbox removeURLTestOutbounds failed group=$groupTag error=${it.message}")
            }
            mainHandler.post { callback(result.map { Unit }) }
        }
    }

    fun lookupOutboundExternalInfo(outboundTag: String, callback: (Result<Map<String, String>>) -> Unit) {
        lookupExecutor.execute {
            val result = runCatching { fetchOutboundExternalInfo(outboundTag) }
            mainHandler.post { callback(result) }
        }
    }

    fun reloadService(callback: (Result<Unit>) -> Unit) {
        commandExecutor.execute {
            val result = runCatching {
                withStandaloneCommandClient { client ->
                    client.serviceReload()
                }
            }
            mainHandler.post { callback(result.map { Unit }) }
        }
    }

    fun emitNetworkChanged(
        reason: String,
        description: String,
        interfaceName: String?,
        interfaceIndex: Int,
    ) {
        emit(
            mapOf(
                "type" to "network",
                "reason" to reason,
                "description" to description,
                "interfaceName" to interfaceName,
                "interfaceIndex" to interfaceIndex,
                "uptimeMs" to SystemClock.uptimeMillis(),
            ),
        )
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun emitCoalescedStatus(payload: Map<String, Any?>) {
        latestStatusPayload = payload
        if (!statusEventScheduled.compareAndSet(false, true)) {
            return
        }
        mainHandler.post { drainStatusEvent() }
    }

    private fun emitCoalescedGroups(payload: Map<String, Any?>) {
        latestGroupsPayload = payload
        if (!groupsEventScheduled.compareAndSet(false, true)) {
            return
        }
        mainHandler.post { drainGroupsEvent() }
    }

    private fun drainStatusEvent() {
        val payload = latestStatusPayload
        if (payload == null || payload == lastEmittedStatusPayload) {
            statusEventScheduled.set(false)
            return
        }
        val now = SystemClock.uptimeMillis()
        val remaining = STATUS_EVENT_THROTTLE_MS - (now - lastStatusEventUptimeMs)
        if (remaining > 0) {
            mainHandler.postDelayed({ drainStatusEvent() }, remaining)
            return
        }
        lastStatusEventUptimeMs = now
        lastEmittedStatusPayload = payload
        statusEventScheduled.set(false)
        eventSink?.success(payload)
    }

    private fun drainGroupsEvent() {
        val payload = latestGroupsPayload
        if (payload == null || payload == lastEmittedGroupsPayload) {
            groupsEventScheduled.set(false)
            return
        }
        val now = SystemClock.uptimeMillis()
        val throttleMs = when (MeowApplication.performanceMode) {
            "performance" -> GROUPS_EVENT_THROTTLE_PERFORMANCE_MS
            "balanced" -> GROUPS_EVENT_THROTTLE_BALANCED_MS
            else -> GROUPS_EVENT_THROTTLE_COOL_MS
        }
        val remaining = throttleMs - (now - lastGroupsEventUptimeMs)
        if (remaining > 0) {
            mainHandler.postDelayed({ drainGroupsEvent() }, remaining)
            return
        }
        lastGroupsEventUptimeMs = now
        lastEmittedGroupsPayload = payload
        groupsEventScheduled.set(false)
        eventSink?.success(payload)
    }

    private fun emitCurrentState(error: String? = null) {
        emit(
            mapOf(
                "type" to "state",
                "running" to running,
                "mode" to serviceMode,
                "error" to error,
            ),
        )
    }

    private fun emitCurrentStatus() {
        emit(
            mapOf(
                "type" to "status",
                "uplink" to uplink,
                "downlink" to downlink,
                "uplinkTotal" to uplinkTotal,
                "downlinkTotal" to downlinkTotal,
                "trafficAvailable" to (uplink != 0L || downlink != 0L || uplinkTotal != 0L || downlinkTotal != 0L),
            ),
        )
    }

    private fun fetchOutboundExternalInfo(outboundTag: String): Map<String, String> {
        val normalizedTag = outboundTag.trim()
        require(normalizedTag.isNotEmpty()) { "Outbound tag is empty" }
        val info = withStandaloneCommandClient { client ->
            val externalInfo = client.lookupOutboundExternalInfo(normalizedTag)
            (externalInfo.ip?.trim().orEmpty()) to (externalInfo.countryCode?.trim().orEmpty())
        }
        return buildMap {
            val ip = info.first
            val countryCode = info.second
            if (ip.isNotEmpty()) {
                put("ip", ip)
            }
            if (countryCode.isNotEmpty()) {
                put("countryCode", countryCode)
            }
        }
    }
}
