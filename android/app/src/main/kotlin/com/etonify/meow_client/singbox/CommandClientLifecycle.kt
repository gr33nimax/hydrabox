package com.etonify.meow_client.singbox

internal enum class CommandConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    DISCONNECTING,
}

internal enum class CommandDisconnectKind {
    STALE,
    EXPECTED,
    UNEXPECTED,
    DUPLICATE,
}

internal data class CommandDisconnectDecision(
    val kind: CommandDisconnectKind,
    val epoch: Long,
    val scheduleReconnect: Boolean = false,
    val reconnectAttempt: Int = 0,
    val reconnectDelayMs: Long = 0L,
)

/**
 * Thread-safe state for the long-lived libbox command stream.
 *
 * Each client owns one epoch. Invalidating the epoch before an intentional
 * disconnect makes late EOF callbacks from the old client harmless.
 */
internal class CommandClientLifecycle(
    private val reconnectDelaysMs: LongArray = DEFAULT_RECONNECT_DELAYS_MS,
) {
    init {
        require(reconnectDelaysMs.isNotEmpty())
        require(reconnectDelaysMs.all { it >= 0L })
    }

    private var epoch = 0L
    private var reconnectPendingEpoch: Long? = null

    var state: CommandConnectionState = CommandConnectionState.DISCONNECTED
        @Synchronized get
        private set

    var reconnectAttempt: Int = 0
        @Synchronized get
        private set

    @Synchronized
    fun beginConnect(shouldConnect: Boolean): Long? {
        if (!shouldConnect ||
            reconnectPendingEpoch != null ||
            state != CommandConnectionState.DISCONNECTED
        ) {
            return null
        }
        epoch++
        state = CommandConnectionState.CONNECTING
        return epoch
    }

    @Synchronized
    fun onConnected(callbackEpoch: Long): Boolean {
        if (callbackEpoch != epoch || state != CommandConnectionState.CONNECTING) {
            return false
        }
        state = CommandConnectionState.CONNECTED
        reconnectAttempt = 0
        reconnectPendingEpoch = null
        return true
    }

    @Synchronized
    fun beginExpectedDisconnect(): Long {
        epoch++
        reconnectPendingEpoch = null
        reconnectAttempt = 0
        state = CommandConnectionState.DISCONNECTING
        return epoch
    }

    @Synchronized
    fun finishExpectedDisconnect(disconnectEpoch: Long) {
        if (disconnectEpoch == epoch && state == CommandConnectionState.DISCONNECTING) {
            state = CommandConnectionState.DISCONNECTED
        }
    }

    @Synchronized
    fun onDisconnected(
        callbackEpoch: Long,
        shouldConnect: Boolean,
    ): CommandDisconnectDecision {
        if (callbackEpoch != epoch) {
            return CommandDisconnectDecision(
                kind = CommandDisconnectKind.STALE,
                epoch = callbackEpoch,
            )
        }
        if (!shouldConnect || state == CommandConnectionState.DISCONNECTING) {
            state = CommandConnectionState.DISCONNECTED
            reconnectPendingEpoch = null
            reconnectAttempt = 0
            return CommandDisconnectDecision(
                kind = CommandDisconnectKind.EXPECTED,
                epoch = callbackEpoch,
            )
        }
        if (reconnectPendingEpoch == callbackEpoch ||
            state == CommandConnectionState.DISCONNECTED
        ) {
            return CommandDisconnectDecision(
                kind = CommandDisconnectKind.DUPLICATE,
                epoch = callbackEpoch,
            )
        }

        state = CommandConnectionState.DISCONNECTED
        reconnectAttempt++
        reconnectPendingEpoch = callbackEpoch
        val delayIndex = (reconnectAttempt - 1).coerceAtMost(reconnectDelaysMs.lastIndex)
        return CommandDisconnectDecision(
            kind = CommandDisconnectKind.UNEXPECTED,
            epoch = callbackEpoch,
            scheduleReconnect = true,
            reconnectAttempt = reconnectAttempt,
            reconnectDelayMs = reconnectDelaysMs[delayIndex],
        )
    }

    @Synchronized
    fun claimReconnect(callbackEpoch: Long, shouldConnect: Boolean): Boolean {
        if (reconnectPendingEpoch != callbackEpoch) {
            return false
        }
        reconnectPendingEpoch = null
        if (!shouldConnect) {
            reconnectAttempt = 0
            state = CommandConnectionState.DISCONNECTED
            return false
        }
        return state == CommandConnectionState.DISCONNECTED
    }

    @Synchronized
    fun cancelReconnect(resetAttempts: Boolean = true) {
        reconnectPendingEpoch = null
        if (resetAttempts) {
            reconnectAttempt = 0
        }
    }

    @Synchronized
    fun isCurrent(callbackEpoch: Long): Boolean = callbackEpoch == epoch

    @Synchronized
    fun acceptsEvents(callbackEpoch: Long): Boolean =
        callbackEpoch == epoch && state == CommandConnectionState.CONNECTED

    @Synchronized
    fun currentEpoch(): Long = epoch

    companion object {
        private val DEFAULT_RECONNECT_DELAYS_MS =
            longArrayOf(250L, 500L, 1_000L, 2_000L, 5_000L)
    }
}
