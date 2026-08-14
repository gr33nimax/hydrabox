package io.hydrabox.client.runtime

import org.json.JSONObject

/** Reduces HydraCore's signed capability document to the typed IPC surface. */
internal object CoreCapabilityContract {
    private const val MAX_CAPABILITIES_BYTES = 1024 * 1024
    private const val EXPECTED_CORE_ID = "io.hydrabox.hydracore"
    private val protocolIdPattern = Regex("^[a-z0-9][a-z0-9._-]{0,63}$")

    fun supportedProtocolIds(capabilities: ByteArray): List<String> {
        require(capabilities.isNotEmpty() && capabilities.size <= MAX_CAPABILITIES_BYTES) {
            "HydraCore capabilities have an invalid size"
        }
        val root = JSONObject(capabilities.toString(Charsets.UTF_8))
        require(root.getInt("api_version") >= 2) {
            "HydraCore capability API is unsupported"
        }
        require(root.getJSONObject("identity").getString("core_id") == EXPECTED_CORE_ID) {
            "HydraCore capability identity is invalid"
        }
        val protocols = root.getJSONObject("protocols")
        val supported = linkedSetOf<String>()
        listOf("inbounds", "outbounds", "endpoints").forEach { kind ->
            val values = protocols.getJSONArray(kind)
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
