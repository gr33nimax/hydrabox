package io.hydrabox.core.projection

import io.hydrabox.core.contract.HydraCoreErrorCode
import io.hydrabox.core.contract.RuntimeFailure

/** Stable id of the group holding individually imported configs ("Свои конфиги"). */
const val MANUAL_SOURCE_ID = "manual"

/**
 * What the last measurement of a server said.
 *
 * A server with no figure and a server that was asked and did not answer are not the same
 * thing, and the difference is what a person needs to pick one: an empty column read as
 * "not measured yet" for servers the core had already given up on. The edge question adds
 * its own non-answers — no recorded edge, an edge a datagram cannot reach, a question the
 * budget never reached — each a different thing for a person to know.
 */
enum class ProbeState {
    /** No measurement has produced a result for this server at all. */
    UNKNOWN,

    /** A figure came back. */
    ANSWERING,

    /** Asked, and stayed silent for the whole budget. */
    SILENT,

    /** The edge question could not be asked: this profile's transport never recorded an edge. */
    NO_EDGE,

    /** The recorded edge does not answer a datagram — TCP or TLS only. */
    EDGE_UNSUPPORTED,

    /** The sweep's budget ran out before this server's question was asked. */
    NOT_MEASURED,
}

/**
 * One server as a person picks it. [auto] is the automatic choice by latency; its
 * [resolvedTag] says which outbound the automatic choice is actually using, and [resolvedLabel]
 * is the catalogue's own name for that server — because "auto" alone answers none of the three
 * questions the home screen has to answer, and a core's tag answers none of them either.
 */
data class ServerRef(
    val id: String,
    val displayName: String,
    val auto: Boolean = false,
    /**
     * The core's own name for the outbound carrying traffic. It is a key — measurements are
     * recorded under it — never text to put in front of a person.
     */
    val resolvedTag: String? = null,
    /** What the catalogue calls the server behind [resolvedTag], when it knows it. */
    val resolvedLabel: String? = null,
    val latencyMillis: Int? = null,
    val sourceId: String = "",
    /** The protocol this server speaks, as the subscription described it. */
    val type: String? = null,
    val endpoint: Boolean = false,
    val selectable: Boolean = true,
    /** The outbound object projected as text, so an inspector needs no second platform read. */
    val configJson: String? = null,
    /** What the last measurement said, when there was one. */
    val probe: ProbeState = ProbeState.UNKNOWN,
    val latencyStale: Boolean = false,
    val quicRttMillis: Int? = null,
    /**
     * The figure is the round trip to the VK transport's TURN edge — one STUN Binding, not a
     * measurement of the tunnel. It says so next to the number, because it proves the edge
     * and nothing behind it.
     */
    val latencyIsEdgeRtt: Boolean = false,
    /** An offline measurement sweep is asking this server right now; the row shows a spinner. */
    val measuring: Boolean = false,
)

/** One user-facing error vocabulary for the connection and diagnostics surfaces. */
enum class ErrorMessage {
    NO_INTERNET,
    SERVER_UNREACHABLE,
    SUBSCRIPTION_UNAVAILABLE,
    CONFIG_REJECTED,
    PERMISSION_REQUIRED,
    CONNECTION_LOST,
    UNKNOWN,
    ;

    val primaryAction: PrimaryAction
        get() =
            when (this) {
                SERVER_UNREACHABLE -> PrimaryAction.CHOOSE_SERVER
                SUBSCRIPTION_UNAVAILABLE -> PrimaryAction.REFRESH_SOURCE
                else -> PrimaryAction.RETRY
            }

    companion object {
        fun of(failure: RuntimeFailure?): ErrorMessage =
            when (failure?.code) {
                null -> UNKNOWN

                HydraCoreErrorCode.NETWORK_NO_INTERFACE,
                HydraCoreErrorCode.NETWORK_LOST,
                HydraCoreErrorCode.NETWORK_GENERATION_STALE,
                HydraCoreErrorCode.DNS_BOOTSTRAP_TIMEOUT,
                -> NO_INTERNET

                HydraCoreErrorCode.RUNTIME_CORE_DIED,
                HydraCoreErrorCode.RUNTIME_IPC_LOST,
                HydraCoreErrorCode.RUNTIME_IPC_BIND_FAILED,
                -> CONNECTION_LOST

                HydraCoreErrorCode.QUIC_DIAL_FAILED,
                HydraCoreErrorCode.QUIC_NO_PATHS,
                HydraCoreErrorCode.TURN_ALLOCATE_FAILED,
                HydraCoreErrorCode.TURN_NO_CANDIDATE,
                HydraCoreErrorCode.DTLS_HANDSHAKE_FAILED,
                HydraCoreErrorCode.TRANSPORT_LANES_LOST,
                HydraCoreErrorCode.TRANSPORT_RECOVERY_TIMEOUT,
                HydraCoreErrorCode.RUNTIME_START_DEADLINE,
                HydraCoreErrorCode.DNS_UPSTREAM_TIMEOUT,
                HydraCoreErrorCode.DNS_UPSTREAM_REFUSED,
                HydraCoreErrorCode.DNS_NO_ANSWER,
                HydraCoreErrorCode.PROBE_TIMEOUT,
                HydraCoreErrorCode.VK_CREDENTIALS_REJECTED,
                HydraCoreErrorCode.VK_CREDENTIALS_FLOOD,
                HydraCoreErrorCode.VK_AUTH_TERMINAL,
                HydraCoreErrorCode.VK_CAPTCHA_REQUIRED,
                HydraCoreErrorCode.VK_CAPTCHA_TIMEOUT,
                HydraCoreErrorCode.VK_CAPTCHA_CANCELLED,
                -> SERVER_UNREACHABLE

                HydraCoreErrorCode.CONFIG_INVALID_PLAN,
                HydraCoreErrorCode.CONFIG_DIGEST_MISMATCH,
                HydraCoreErrorCode.CONFIG_QUARANTINED,
                HydraCoreErrorCode.CONFIG_STALE,
                HydraCoreErrorCode.PROBE_INVALID_PLAN,
                -> CONFIG_REJECTED

                else -> UNKNOWN
            }
    }
}

/** Kept as a source-compatible name for existing callers; errors now use [ErrorMessage]. */
typealias Trouble = ErrorMessage

data class ErrorPresentation(
    val message: ErrorMessage,
    val detail: String? = null,
) {
    val primaryAction: PrimaryAction get() = message.primaryAction

    companion object {
        fun of(failure: RuntimeFailure?): ErrorPresentation =
            ErrorPresentation(
                message = ErrorMessage.of(failure),
                detail = failure?.let { "${it.domain.name.lowercase()} / ${it.code.code}" },
            )
    }
}

/**
 * What the product says about the tunnel. A runtime phase is not a product state:
 * `STARTING` and `RECOVERING` are both "the tunnel is not carrying traffic yet", but only
 * one of them was asked for by the person looking at the screen, so they are different
 * states here.
 */
sealed interface Connection {
    /** Nothing to connect to yet: the very first run, or every source was removed. */
    data object NeedsSubscription : Connection

    /** A source exists but holds no server. Its own problem, its own single action. */
    data object NeedsServers : Connection

    data class Idle(
        val server: ServerRef?,
    ) : Connection

    /** Asked for by the person: they pressed connect. */
    data class Connecting(
        val server: ServerRef?,
    ) : Connection

    data class Connected(
        val server: ServerRef?,
        val traffic: TrafficSummary,
    ) : Connection

    /** Not asked for: the network moved under us and the runtime is recovering. */
    data class Reconnecting(
        val server: ServerRef?,
    ) : Connection

    data object Disconnecting : Connection

    data class Stopped(
        val presentation: ErrorPresentation,
        val server: ServerRef?,
        val retryable: Boolean,
    ) : Connection {
        constructor(cause: Trouble, server: ServerRef?, retryable: Boolean) :
            this(ErrorPresentation(cause), server, retryable)

        val cause: Trouble get() = presentation.message
    }

    data class Unreachable(
        val presentation: ErrorPresentation,
        val server: ServerRef?,
        val retryable: Boolean,
    ) : Connection
}

/** Holds transient connection labels for 700 ms; stable and terminal states pass immediately. */
class ConnectionStatusThrottle(
    private val delayMillis: Long = 700,
) {
    var nextTransitionAtMillis: Long? = null
        private set

    private var displayed: Connection? = null
    private var candidate: Connection? = null

    fun update(
        connection: Connection,
        nowMillis: Long,
    ): Connection {
        val current = displayed
        if (current == null || !connection.isTransient()) {
            displayed = connection
            candidate = null
            nextTransitionAtMillis = null
            return connection
        }
        if (connection == current) {
            candidate = null
            nextTransitionAtMillis = null
            return current
        }
        if (candidate != connection) {
            candidate = connection
            nextTransitionAtMillis =
                if (nowMillis > Long.MAX_VALUE - delayMillis) Long.MAX_VALUE else nowMillis + delayMillis
        }
        if (nowMillis >= (nextTransitionAtMillis ?: Long.MAX_VALUE)) {
            displayed = connection
            candidate = null
            nextTransitionAtMillis = null
            return connection
        }
        return current
    }

    private fun Connection.isTransient() =
        this is Connection.Connecting || this is Connection.Reconnecting || this == Connection.Disconnecting
}

/** The single action the connection state offers. One state, one primary action. */
enum class PrimaryAction { CONNECT, CANCEL, DISCONNECT, RETRY, ADD_SUBSCRIPTION, REFRESH_SOURCE, CHOOSE_SERVER, NONE }

val Connection.primaryAction: PrimaryAction
    get() =
        when (this) {
            Connection.NeedsSubscription -> {
                PrimaryAction.ADD_SUBSCRIPTION
            }

            Connection.NeedsServers -> {
                PrimaryAction.REFRESH_SOURCE
            }

            is Connection.Idle -> {
                PrimaryAction.CONNECT
            }

            is Connection.Connecting -> {
                PrimaryAction.CANCEL
            }

            is Connection.Connected -> {
                PrimaryAction.DISCONNECT
            }

            is Connection.Reconnecting -> {
                PrimaryAction.CANCEL
            }

            Connection.Disconnecting -> {
                PrimaryAction.NONE
            }

            is Connection.Stopped -> {
                presentation.primaryAction
            }

            is Connection.Unreachable -> {
                presentation.primaryAction
            }
        }

/** The server the state is about, so the screen does not unpack the state to find it. */
val Connection.server: ServerRef?
    get() =
        when (this) {
            is Connection.Idle -> server
            is Connection.Connecting -> server
            is Connection.Connected -> server
            is Connection.Reconnecting -> server
            is Connection.Stopped -> server
            is Connection.Unreachable -> server
            else -> null
        }

/** True while traffic is actually flowing through the tunnel. */
val Connection.protecting: Boolean get() = this is Connection.Connected
