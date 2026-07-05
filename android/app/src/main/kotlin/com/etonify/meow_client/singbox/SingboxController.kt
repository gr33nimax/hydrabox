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
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.nio.channels.SocketChannel
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

object SingboxController {
    private const val TAG = "MeowSingbox"
    private const val STATUS_EVENT_THROTTLE_MS = 1_000L
    private const val GROUPS_EVENT_THROTTLE_COOL_MS = 1_500L
    private const val GROUPS_EVENT_THROTTLE_BALANCED_MS = 750L
    private const val GROUPS_EVENT_THROTTLE_PERFORMANCE_MS = 500L
    private const val TRAFFIC_POLL_STANDARD_INTERVAL_MS = 1_000L
    private const val TRAFFIC_POLL_ECONOMY_INTERVAL_MS = 2_000L
    private const val NO_INTERFACE_REASSERT_THROTTLE_MS = 2_000L
    private const val INTERFACE_DIAL_FAILURE_WINDOW_MS = 8_000L
    private const val INTERFACE_DIAL_FAILURE_THRESHOLD = 4
    private val INTERFACE_DIAL_FAILURE_REGEX =
        Regex(
            """\bdial\s+(?:ccmni|wlan|rmnet|swlan|eth|usb|ap)\w*\s*\(\d+\).*?\b(?:network is unreachable|no route to host)\b""",
            RegexOption.IGNORE_CASE,
        )
    private val mainHandler = Handler(Looper.getMainLooper())
    private val commandExecutor = Executors.newSingleThreadExecutor()
    private val lookupExecutor = Executors.newFixedThreadPool(4)
    private val statusEventScheduled = AtomicBoolean(false)
    private val groupsEventScheduled = AtomicBoolean(false)
    private val runtimeGeneration = AtomicLong(0)
    private val runtimeStartGeneration = AtomicLong(0)
    private val lastNoInterfaceReassertUptimeMs = AtomicLong(0L)
    private val interfaceFailureLock = Any()
    private val interfaceDialFailureUptimes = ArrayDeque<Long>()
    private val stopWaiterLock = Any()
    private val stopWaiters = mutableListOf<(Boolean) -> Unit>()

    @Volatile
    private var eventSink: EventChannel.EventSink? = null
    @Volatile
    private var uiForeground = true
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
                mainHandler.postDelayed(this, trafficPollIntervalMs())
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
            val groups = mutableListOf<Map<String, Any?>>()
            val selectedGroups = mutableListOf<String>()
            var itemCount = 0
            var availableCount = 0
            var unavailableCount = 0
            var maxDelay = 0L
            var maxDelayTag = ""
            while (message.hasNext()) {
                val group = message.next()
                val selected = group.selected
                if (!selected.isNullOrBlank()) {
                    selectedGroups += "${group.tag}=$selected"
                }
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
                    itemCount++
                    if (delay > 0L) {
                        availableCount++
                        if (delay > maxDelay) {
                            maxDelay = delay.toLong()
                            maxDelayTag = item.tag.orEmpty()
                        }
                    }
                    if ((status ?: "").equals("unavailable", ignoreCase = true)) {
                        unavailableCount++
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
            if (itemCount > 0) {
                val summary =
                    "urltest_groups_event groups=${groups.size} items=$itemCount " +
                        "available=$availableCount unavailable=$unavailableCount " +
                        "maxDelayMs=$maxDelay maxDelayTag=$maxDelayTag " +
                        "selected=${selectedGroups.take(6).joinToString(",")}"
                MeowDiagnostics.log(TAG, summary)
                if (maxDelay >= 1000L) {
                    log("warning", "urltest_high_delay $summary")
                }
            }
            emitCoalescedGroups(mapOf("type" to "groups", "groups" to groups))
        }

        override fun writeOutbounds(message: io.nekohasekai.libbox.OutboundGroupItemIterator?) = Unit

        override fun writeLogs(messageList: LogIterator?) {
            if (messageList == null) return
            val logs = mutableListOf<Map<String, Any?>>()
            while (messageList.hasNext()) {
                val entry: LogEntry = messageList.next()
                val message = entry.message ?: ""
                maybeReassertDefaultInterfaceFromCoreLog(message)
                logs += mapOf(
                    "level" to entry.level,
                    "message" to message,
                )
                MeowDiagnostics.log(TAG, "libbox log level=${entry.level} message=$message")
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
        return sorted.map { it.toEventMap() }
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink != null) {
            emitCurrentState()
            emitCurrentStatus()
            if (running && uiForeground && commandClient == null) {
                connectClient()
            }
            if (running && uiForeground) {
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
            if (eventSink != null && uiForeground) {
                connectClient()
                startTrafficPolling()
            }
        } else {
            stopTrafficPolling(reset = true)
            disconnectClient()
        }
    }

    fun setUiForeground(value: Boolean) {
        if (uiForeground == value) return
        uiForeground = value
        MeowDiagnostics.log(TAG, "ui foreground=$value running=$running")
        if (!value) {
            stopTrafficPolling(reset = false)
            disconnectClient()
            return
        }
        if (running && eventSink != null) {
            emitCurrentState()
            emitCurrentStatus()
            connectClient()
            startTrafficPolling()
        }
    }

    fun markServiceStarted(mode: String): Long {
        val generation = runtimeGeneration.incrementAndGet()
        activeRuntimeGeneration = generation
        setRunning(true, mode)
        MeowDiagnostics.log(TAG, "markServiceStarted generation=$generation mode=$mode")
        return generation
    }

    fun nextStartToken(reason: String): Long {
        val token = runtimeStartGeneration.incrementAndGet()
        MeowDiagnostics.log(TAG, "nextStartToken token=$token reason=$reason")
        return token
    }

    fun cancelStartTokens(reason: String): Long {
        val token = runtimeStartGeneration.incrementAndGet()
        MeowDiagnostics.log(TAG, "cancelStartTokens token=$token reason=$reason")
        return token
    }

    fun isStartTokenCurrent(token: Long): Boolean = runtimeStartGeneration.get() == token

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

    fun forceMarkServiceStopped(reason: String) {
        val previousGeneration = activeRuntimeGeneration
        activeRuntimeGeneration = 0
        setRunning(false)
        MeowDiagnostics.log(
            TAG,
            "forceMarkServiceStopped previousGeneration=$previousGeneration reason=$reason",
        )
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

    private fun maybeReassertDefaultInterfaceFromCoreLog(message: String) {
        if (!running) return
        val reason = classifyCoreInterfaceFailure(message) ?: return
        val now = SystemClock.uptimeMillis()
        val failureCount = if (reason == "dial_interface_failure") {
            recordInterfaceDialFailure(now)
        } else {
            clearInterfaceDialFailures()
            1
        }
        if (reason == "dial_interface_failure" && failureCount < INTERFACE_DIAL_FAILURE_THRESHOLD) {
            return
        }
        val last = lastNoInterfaceReassertUptimeMs.get()
        if (now - last < NO_INTERFACE_REASSERT_THROTTLE_MS) return
        if (!lastNoInterfaceReassertUptimeMs.compareAndSet(last, now)) return
        val state = MeowDefaultNetworkMonitor.currentInterfaceState("core_$reason")
        val shortMessage = message.take(180)
        log(
            "warning",
            "core_interface_reassert reason=$reason interface=${state.interfaceName} " +
                "index=${state.interfaceIndex} generation=${state.generation} " +
                "failures=$failureCount message=$shortMessage",
        )
        MeowDefaultNetworkMonitor.reassertDefaultInterface("core_$reason")
    }

    private fun classifyCoreInterfaceFailure(message: String): String? {
        val lower = message.lowercase()
        if (lower.contains("no available network interface")) {
            return "no_available_interface"
        }
        if (lower.contains("no usable network interface") || lower.contains("error=no_interface")) {
            return "no_usable_interface"
        }
        if (INTERFACE_DIAL_FAILURE_REGEX.containsMatchIn(message)) {
            return "dial_interface_failure"
        }
        return null
    }

    private fun recordInterfaceDialFailure(now: Long): Int {
        synchronized(interfaceFailureLock) {
            interfaceDialFailureUptimes.addLast(now)
            while (interfaceDialFailureUptimes.isNotEmpty() &&
                now - interfaceDialFailureUptimes.first > INTERFACE_DIAL_FAILURE_WINDOW_MS
            ) {
                interfaceDialFailureUptimes.removeFirst()
            }
            val count = interfaceDialFailureUptimes.size
            if (count >= INTERFACE_DIAL_FAILURE_THRESHOLD) {
                interfaceDialFailureUptimes.clear()
            }
            return count
        }
    }

    private fun clearInterfaceDialFailures() {
        synchronized(interfaceFailureLock) {
            interfaceDialFailureUptimes.clear()
        }
    }

    fun connectClient() {
        commandExecutor.execute {
            disconnectClientOnExecutor("reconnect")
            runCatching {
                if (!running || eventSink == null || !uiForeground) {
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
        Log.i(TAG, "disconnecting command client reason=$reason")
        MeowDiagnostics.log(TAG, "disconnecting command client reason=$reason")
        runCatching { client.disconnect() }
            .onSuccess {
                if (commandClient === client) {
                    commandClient = null
                }
                MeowDiagnostics.log(TAG, "command client disconnected reason=$reason")
            }
            .onFailure {
                Log.w(TAG, "command client disconnect failed reason=$reason", it)
                MeowDiagnostics.log(TAG, "command client disconnect failed reason=$reason", it)
            }
    }

    private fun startTrafficPolling() {
        if (trafficPollActive || !uiForeground) return
        val rx = TrafficStats.getUidRxBytes(android.os.Process.myUid())
        val tx = TrafficStats.getUidTxBytes(android.os.Process.myUid())
        trafficPollActive = true
        trafficBaselineRx = rx
        trafficBaselineTx = tx
        lastTrafficRx = rx
        lastTrafficTx = tx
        lastTrafficUptimeMs = SystemClock.uptimeMillis()
        mainHandler.removeCallbacks(trafficPollRunnable)
        mainHandler.postDelayed(trafficPollRunnable, trafficPollIntervalMs())
    }

    private fun trafficPollIntervalMs(): Long =
        if (MeowApplication.performanceMode == "economy") {
            TRAFFIC_POLL_ECONOMY_INTERVAL_MS
        } else {
            TRAFFIC_POLL_STANDARD_INTERVAL_MS
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
        if (!running || eventSink == null || !uiForeground) {
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

    fun urlTest(
        groupTag: String,
        targetOutboundTag: String,
        priorityOutboundTag: String,
        excludeOutboundTag: String,
        url: String,
        timeoutMillis: Int,
        concurrency: Int,
        deadlineMillis: Int,
        force: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) {
        log(
            "info",
            "libbox urlTest group=$groupTag target=$targetOutboundTag priority=$priorityOutboundTag " +
                "timeoutMs=$timeoutMillis concurrency=$concurrency deadlineMs=$deadlineMillis",
        )
        commandExecutor.execute {
            val result = runCatching {
                withStandaloneCommandClient { client ->
                    if (url.isBlank()) {
                        client.urlTest(groupTag)
                    } else {
                        client.urlTestWithURL(groupTag, url)
                    }
                }
            }
            result.onFailure {
                log("error", "libbox urlTest failed group=$groupTag error=${it.message}")
            }
            val completion = Runnable { callback(result.map { Unit }) }
            if (result.isSuccess) {
                mainHandler.postDelayed(completion, deadlineMillis.coerceIn(1_000, 30_000).toLong())
            } else {
                mainHandler.post(completion)
            }
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

    fun probeProxyEndpoint(
        tag: String,
        host: String,
        port: Int,
        timeoutMs: Int,
        callback: (Result<Map<String, Any?>>) -> Unit,
    ) {
        val normalizedTag = tag.trim()
        val normalizedHost = host.trim()
        val normalizedTimeout = timeoutMs.coerceIn(500, 10_000)
        lookupExecutor.execute {
            val result = runCatching {
                require(normalizedTag.isNotEmpty()) { "Probe tag is empty" }
                require(normalizedHost.isNotEmpty()) { "Probe host is empty" }
                require(port in 1..65535) { "Probe port is invalid" }
                val checkedAt = System.currentTimeMillis()
                val startedAt = SystemClock.elapsedRealtime()
                val vpnActive = running && serviceMode == "vpn"
                var protectedSocket = false
                var latencyMs: Long? = null
                var errorCode = ""
                SocketChannel.open().use { channel ->
                    val socket = channel.socket()
                    if (vpnActive) {
                        protectedSocket = runCatching {
                            MeowVpnService.protectSocket(socket)
                        }.getOrDefault(false)
                    }
                    if (vpnActive && !protectedSocket) {
                        errorCode = "protect_failed"
                    } else {
                        try {
                            socket.connect(
                                InetSocketAddress(normalizedHost, port),
                                normalizedTimeout,
                            )
                            latencyMs = (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(1L)
                        } catch (error: Throwable) {
                            errorCode = when (error) {
                                is SocketTimeoutException -> "timeout"
                                is UnknownHostException -> "unknown_host"
                                is ConnectException -> "connect_failed"
                                else -> error.javaClass.simpleName.ifBlank { "probe_failed" }
                            }
                        }
                    }
                }
                val reachable = latencyMs != null
                log(
                    if (reachable || errorCode == "protect_failed") "debug" else "warning",
                    "proxy_health_probe_result tag=$normalizedTag reachable=$reachable " +
                        "latencyMs=${latencyMs ?: ""} error=$errorCode " +
                        "protected=$protectedSocket vpnActive=$vpnActive mode=$serviceMode",
                )
                mapOf(
                    "tag" to normalizedTag,
                    "reachable" to reachable,
                    "latencyMs" to latencyMs,
                    "errorCode" to errorCode,
                    "checkedAtMillis" to checkedAt,
                    "protectedSocket" to protectedSocket,
                )
            }
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
        networkGeneration: Long,
    ) {
        emit(
            mapOf(
                "type" to "network",
                "reason" to reason,
                "description" to description,
                "interfaceName" to interfaceName,
                "interfaceIndex" to interfaceIndex,
                "networkGeneration" to networkGeneration,
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
