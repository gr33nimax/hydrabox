package io.hydrabox.client.singbox

object HydraBoxEventCodes {
    const val CONFIG_INVALID_PLAN = "config.invalid_plan"
    const val CONFIG_DIGEST_MISMATCH = "config.digest_mismatch"
    const val CONFIG_QUARANTINED = "config.quarantined"
    const val CONFIG_STALE = "config.stale"
    const val RUNTIME_CANCELLED = "runtime.cancelled"
    const val RUNTIME_SUPERSEDED = "runtime.superseded"
    const val RUNTIME_START_DEADLINE = "runtime.start.deadline"
    const val RUNTIME_STOP_UNCONFIRMED = "runtime.stop.unconfirmed"
    const val RUNTIME_CORE_DIED = "runtime.core_died"
    const val RUNTIME_IPC_LOST = "runtime.ipc.lost"
    const val RUNTIME_IPC_BIND_FAILED = "runtime.ipc.bind_failed"
    const val NETWORK_NO_INTERFACE = "network.no_interface"
    const val NETWORK_LOST = "network.lost"
    const val NETWORK_GENERATION_STALE = "network.generation_stale"
    const val DNS_BOOTSTRAP_TIMEOUT = "dns.bootstrap.timeout"
    const val DNS_UPSTREAM_TIMEOUT = "dns.upstream.timeout"
    const val DNS_UPSTREAM_REFUSED = "dns.upstream.refused"
    const val DNS_NO_ANSWER = "dns.no_answer"
    const val VK_CAPTCHA_REQUIRED = "vk.captcha.required"
    const val VK_CAPTCHA_TIMEOUT = "vk.captcha.timeout"
    const val VK_CAPTCHA_CANCELLED = "vk.captcha.cancelled"
    const val VK_CREDENTIALS_FLOOD = "vk.credentials.flood"
    const val VK_CREDENTIALS_REJECTED = "vk.credentials.rejected"
    const val VK_AUTH_TERMINAL = "vk.auth.terminal"
    const val TURN_ALLOCATE_FAILED = "turn.allocate_failed"
    const val TURN_NO_CANDIDATE = "turn.no_candidate"
    const val DTLS_HANDSHAKE_FAILED = "dtls.handshake_failed"
    const val QUIC_DIAL_FAILED = "quic.dial_failed"
    const val QUIC_NO_PATHS = "quic.no_paths"
    const val TRANSPORT_LANES_LOST = "transport.lanes_lost"
    const val TRANSPORT_RECOVERY_TIMEOUT = "transport.recovery.timeout"
    const val PROBE_INVALID_PLAN = "probe.invalid_plan"
    const val PROBE_REQUIRES_STOPPED_RUNTIME = "probe.requires_stopped_runtime"
    const val PROBE_TIMEOUT = "probe.timeout"
    const val PROBE_CANCELLED = "probe.cancelled"

    val ALL: Set<String> = setOf(
        CONFIG_INVALID_PLAN, CONFIG_DIGEST_MISMATCH, CONFIG_QUARANTINED, CONFIG_STALE,
        RUNTIME_CANCELLED, RUNTIME_SUPERSEDED, RUNTIME_START_DEADLINE, RUNTIME_STOP_UNCONFIRMED,
        RUNTIME_CORE_DIED, RUNTIME_IPC_LOST, RUNTIME_IPC_BIND_FAILED,
        NETWORK_NO_INTERFACE, NETWORK_LOST, NETWORK_GENERATION_STALE,
        DNS_BOOTSTRAP_TIMEOUT, DNS_UPSTREAM_TIMEOUT, DNS_UPSTREAM_REFUSED, DNS_NO_ANSWER,
        VK_CAPTCHA_REQUIRED, VK_CAPTCHA_TIMEOUT, VK_CAPTCHA_CANCELLED, VK_CREDENTIALS_FLOOD,
        VK_CREDENTIALS_REJECTED, VK_AUTH_TERMINAL, TURN_ALLOCATE_FAILED, TURN_NO_CANDIDATE,
        DTLS_HANDSHAKE_FAILED, QUIC_DIAL_FAILED, QUIC_NO_PATHS, TRANSPORT_LANES_LOST,
        TRANSPORT_RECOVERY_TIMEOUT, PROBE_INVALID_PLAN, PROBE_REQUIRES_STOPPED_RUNTIME,
        PROBE_TIMEOUT, PROBE_CANCELLED,
    )
}
