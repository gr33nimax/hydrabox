package io.hydrabox.client.runtime

import org.json.JSONArray
import org.json.JSONObject

/** Reduces HydraCore's signed capability document to the typed IPC surface. */
internal object CoreCapabilityContract {
    private const val MAX_CAPABILITIES_BYTES = 1024 * 1024
    private const val EXPECTED_CORE_ID = "io.hydrabox.hydracore"
    private const val EXPECTED_CORE_NAME = "HydraCore"
    private val requiredCallFeatures = listOf(
        "call_vk_parasite",
        "call_vk_parasite_client",
        "vk_auth_challenges",
    )
    private val legacyFeatureNames = setOf(
        "call_vk_eight_lane_kcp",
        "call_vk_four_lane_kcp",
        "call_vk_pre_kcp_admission",
        "call_vk_relay_flow_control",
        "call_vk_worker_hot_swap",
        "call_vk_flow_migration",
        "call_vk_turn_tcp_fallback",
        "call_vk_transport_health",
    )
    private val protocolIdPattern = Regex("^[a-z0-9][a-z0-9._-]{0,63}$")

    fun bundleApiMajor(capabilities: ByteArray): Int {
        val root = JSONObject(capabilities.toString(Charsets.UTF_8))
        val features = root.getJSONObject("features")
        val protocols = root.getJSONObject("protocols")
        return if (
            protocols.has("call_vk_parasite_wire") ||
            legacyFeatureNames.any(features::has)
        ) 1 else 2
    }

    fun supportedProtocolIds(capabilities: ByteArray): List<String> {
        require(capabilities.isNotEmpty() && capabilities.size <= MAX_CAPABILITIES_BYTES) {
            "HydraCore capabilities have an invalid size"
        }
        val root = JSONObject(capabilities.toString(Charsets.UTF_8))
        require(root.getInt("api_version") == 2) {
            "HydraCore capability API is unsupported"
        }
        val identity = root.getJSONObject("identity")
        require(
            identity.getString("core_id") == EXPECTED_CORE_ID &&
                identity.getString("core_name") == EXPECTED_CORE_NAME &&
                identity.getString("role") == "client",
        ) {
            "HydraCore capability identity is invalid"
        }
        val features = root.getJSONObject("features")
        require(requiredCallFeatures.all(features::getBoolean)) {
            "HydraCore recovery capability contract is incomplete"
        }
        require(
            !features.optBoolean("call_vk_parasite_server", false),
        ) { "HydraCore Calls role is invalid" }
        val protocols = root.getJSONObject("protocols")
        val modes = protocols.getJSONArray("call_modes")
        require(
            modes.length() == 1 && modes.getString(0) == "vk_parasite",
        ) { "HydraCore Calls mode contract is incompatible" }
        val runtime = root.getJSONObject("runtime")
        require(
            runtime.getInt("version") == 2 &&
                runtime.getInt("snapshot_schema_version") == 2,
        ) { "HydraCore runtime schema is incompatible" }
        val supported = linkedSetOf<String>()
        listOf("inbounds", "outbounds", "endpoints").forEach { kind ->
            val advertised = protocols.opt(kind)
            if (advertised == null || advertised === JSONObject.NULL) return@forEach
            require(advertised is JSONArray) {
                "HydraCore protocol registry is not an array"
            }
            val values = advertised
            repeat(values.length()) { index ->
                val raw = values.get(index)
                require(raw is String) { "HydraCore protocol identifier is not a string" }
                val protocolId = raw.trim().lowercase()
                require(protocolIdPattern.matches(protocolId)) {
                    "HydraCore protocol identifier is invalid"
                }
                supported += protocolId
            }
        }
        require(supported.isNotEmpty()) { "HydraCore advertises no supported protocols" }
        return supported.sorted()
    }
}
