package io.hydrabox.client.runtime

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.json.JSONObject

/** Converts HydraCore's process-local schema-2 transport state into IPC types. */
internal object TransportHealthBridge {
    fun configRequiresHealth(config: ByteArray): Boolean = runCatching {
        val outbounds = JSONObject(config.toString(Charsets.UTF_8)).optJSONArray("outbounds")
            ?: return@runCatching false
        repeat(outbounds.length()) { index ->
            val outbound = outbounds.optJSONObject(index) ?: return@repeat
            // Значение по умолчанию обязано совпадать с ядром и генератором
            // конфигурации ("p2p"): иначе call-outbound без явного mode ждал бы
            // снимок здоровья, который публикует только vk_parasite, и старт
            // падал бы по дедлайну.
            if (outbound.optString("type") == "call" &&
                outbound.optString("mode", "p2p") == "vk_parasite"
            ) {
                return@runCatching true
            }
        }
        false
    }.getOrDefault(false)

    fun parse(raw: String, fallbackApplicable: Boolean): CoreRuntimeProtocol.TransportHealthSnapshot {
        val root = JSONObject(raw)
        require(root.getInt("schema_version") == 2) {
            "HydraCore transport schema is unsupported"
        }
        val health = root.getJSONObject("health")
        val applicable = if (health.has("applicable")) health.optBoolean("applicable") else fallbackApplicable
        val builder = CoreRuntimeProtocol.TransportHealthSnapshot.newBuilder()
            .setApplicable(applicable)
        if (!applicable) return builder.build()
        builder
            .setState(parseState(health.getString("state")))
            .setActiveLanes(health.optInt("active_lanes").coerceAtLeast(0))
            .setTotalLanes(health.optInt("total_lanes").coerceAtLeast(0))
            .setDemand(health.optBoolean("demand"))
            .setLastProgressAtMillis(health.optLong("last_progress_at").coerceAtLeast(0L))
            .setLastAggregateProgressAtMillis(
                health.optLong("last_aggregate_progress_at").coerceAtLeast(0L),
            )
            .setLastInboundAtMillis(health.optLong("last_inbound_at").coerceAtLeast(0L))
            .setObservedAtMillis(health.optLong("observed_at").coerceAtLeast(0L))
            .setRuntimeGeneration(health.optLong("runtime_generation").coerceAtLeast(0L))
            .setNetworkGeneration(health.optLong("network_generation").coerceAtLeast(0L))
        health.optJSONObject("failure")?.let { failure ->
            builder.setFailure(
                CoreRuntimeProtocol.TransportFailure.newBuilder()
                    .setStage(failure.optString("stage"))
                    .setKind(failure.optString("kind"))
                    .setCode(failure.optString("code"))
                    .setRetryAfterMillis(failure.optLong("retry_after_ms").coerceAtLeast(0L))
                    .setChallengeId(failure.optString("challenge_id"))
                    .setFailureDomain(failure.optString("domain", "INTERNAL"))
                    .setFailureTerminal(failure.optBoolean("terminal")),
            )
        }
        root.optJSONObject("challenge")?.let { challenge ->
            builder.setChallenge(
                CoreRuntimeProtocol.RuntimeChallenge.newBuilder()
                    .setChallengeId(challenge.getString("id"))
                    .setKind(challenge.getString("kind"))
                    .setUrl(challenge.getString("url"))
                    .setCreatedAtMillis(challenge.optLong("created_at").coerceAtLeast(0L))
                    .setExpiresAtMillis(challenge.optLong("expires_at").coerceAtLeast(0L)),
            )
        }
        return builder.build()
    }

    private fun parseState(value: String): CoreRuntimeProtocol.TransportHealthState = when (value) {
        "starting" -> CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_STARTING
        "waiting_user" -> CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_WAITING_USER
        "healthy" -> CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_HEALTHY
        "degraded" -> CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_DEGRADED
        "recovering" -> CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_RECOVERING
        "failed" -> CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_FAILED
        else -> throw IllegalArgumentException("Unknown HydraCore transport state")
    }
}

internal fun readTransportHealth(
    readSnapshot: () -> String,
    fallbackApplicable: Boolean,
): CoreRuntimeProtocol.TransportHealthSnapshot = runCatching {
    TransportHealthBridge.parse(readSnapshot(), fallbackApplicable)
}.getOrElse {
    CoreRuntimeProtocol.TransportHealthSnapshot.newBuilder()
        .setApplicable(true)
        .setState(
            CoreRuntimeProtocol.TransportHealthState.TRANSPORT_HEALTH_STATE_FAILED,
        )
        .setObservedAtMillis(System.currentTimeMillis())
        .setFailure(
            CoreRuntimeProtocol.TransportFailure.newBuilder()
                .setStage("transport_snapshot")
                .setKind("runtime")
                .setCode("runtime.transport.snapshot"),
        )
        .build()
}
