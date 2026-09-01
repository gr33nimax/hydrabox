package io.hydrabox.core.subscription

import io.hydrabox.core.diagnostics.Secret

sealed interface Outbound { val tag: String }

data class CallVkParasiteOutbound(
    override val tag: String,
    val server: String,
    val serverPort: Int,
    val joinLinks: List<Secret>,
    val user: Secret,
    val password: Secret,
    val obfsPassword: Secret,
    val workers: Int?,
    val workerConnectTimeoutSeconds: Int?,
) : Outbound

data class CallJoinerOutbound(
    override val tag: String,
    val platform: String,
    val mode: String,
    val joinLink: Secret,
) : Outbound

object OutboundSchema {
    fun sanitize(input: Map<String, Any?>): Outbound {
        require(input["type"]?.toString()?.trim()?.lowercase() == "call") { "unsupported outbound type" }
        val tag = input.string("tag")
        val platform = input.string("platform").lowercase()
        val mode = input["mode"]?.let { require(it is String) { "invalid call mode" }; it.trim().lowercase() } ?: "p2p"
        return if (mode == "vk_parasite") vkParasite(input, tag, platform) else CallJoinerOutbound(tag, platform, mode, Secret.of(input.string("join_link")))
    }

    private fun vkParasite(input: Map<String, Any?>, tag: String, platform: String): CallVkParasiteOutbound {
        require(platform == "vk") { "call vk_parasite mode currently requires platform vk" }
        val server = input.string("server")
        val port = input["server_port"] as? Int
        require(port != null && port in 1..65535) { "missing server_port" }
        val links = input["join_links"] as? List<*> ?: error("call join_links must contain exactly 4 bounded links")
        require(links.size == 4 && links.all { it is String && it.trim().isNotEmpty() && it.trim().encodeToByteArray().size <= 2048 }) { "call join_links must contain exactly 4 bounded links" }
        val normalizedLinks = links.filterIsInstance<String>().map(String::trim)
        require(normalizedLinks.toSet().size == normalizedLinks.size) { "call join_links must be unique" }
        fun credential(key: String, bytes: Int): Secret {
            val value = input[key] as? String
            require(!value.isNullOrEmpty() && value.encodeToByteArray().size <= bytes) { "call $key must contain 1..$bytes bytes" }
            return Secret.of(value)
        }
        val workers = input["workers"]?.let { it as? Int }.also { require(it == null || it in setOf(4, 8, 12, 16, 20)) { "call workers must be 4, 8, 12, 16, or 20" } }
        val timeout = input["worker_connect_timeout"]?.let { durationSeconds(it as? String ?: error("call worker_connect_timeout must be between 1s and 2m")) }.also { require(it == null || it in 1..120) { "call worker_connect_timeout must be between 1s and 2m" } }
        return CallVkParasiteOutbound(tag, server, port, normalizedLinks.map(Secret::of), credential("user", 64), credential("password", 256), credential("obfs_password", 256), workers, timeout)
    }
}

private fun Map<String, Any?>.string(key: String): String = (this[key] as? String)?.trim()?.takeIf(String::isNotEmpty) ?: error("missing call $key")

private fun durationSeconds(raw: String): Int? {
    val matches = Regex("(\\d+)(s|m|h)").findAll(raw.trim()).toList()
    if (matches.isEmpty() || matches.joinToString("") { it.value } != raw.trim()) return null
    return matches.sumOf { it.groupValues[1].toIntOrNull()?.times(when (it.groupValues[2]) { "s" -> 1; "m" -> 60; else -> 3600 }) ?: return null }
}
