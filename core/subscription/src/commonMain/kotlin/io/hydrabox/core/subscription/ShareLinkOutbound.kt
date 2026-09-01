package io.hydrabox.core.subscription

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/**
 * Builds a core outbound from a share link. A link carries nothing worth preserving
 * verbatim, so here the mapping is explicit — and the query string is honoured, because
 * dropping `security`, `sni` or `type` is what makes a real server refuse the handshake.
 */
object ShareLinkOutbound {
    fun typeOf(link: ShareLink): String = when (link) {
        is ShareLink.Vless -> "vless"
        is ShareLink.Trojan -> "trojan"
        is ShareLink.Proxy -> link.type
        is ShareLink.WireGuard -> "wireguard"
    }

    fun toJson(link: ShareLink, tag: String): JsonObject = when (link) {
        is ShareLink.Vless -> buildJsonObject {
            put("type", "vless")
            put("tag", tag)
            put("server", link.server)
            put("server_port", link.port)
            link.uuid.use { put("uuid", it) }
            link.query["flow"]?.let { put("flow", it) }
            transport(link.query)?.let { put("transport", it) }
            tls(link.query, link.server, secured(link.query))?.let { put("tls", it) }
        }

        is ShareLink.Trojan -> buildJsonObject {
            put("type", "trojan")
            put("tag", tag)
            put("server", link.server)
            put("server_port", link.port)
            link.password.use { put("password", it) }
            transport(link.query)?.let { put("transport", it) }
            tls(link.query, link.server, secured = true)?.let { put("tls", it) }
        }

        is ShareLink.Proxy -> buildJsonObject {
            put("type", link.type)
            put("tag", tag)
            put("server", link.server)
            put("server_port", link.port)
            when (link.type) {
                "shadowsocks", "shadowsocksr" -> {
                    link.username?.use { put("method", it) }
                    link.password?.use { put("password", it) }
                }

                "vmess" -> link.username?.use { put("uuid", it) }

                "hysteria2", "tuic", "anytls" ->
                    link.password?.use { put("password", it) } ?: link.username?.use { put("password", it) }

                else -> {
                    link.username?.use { put("username", it) }
                    link.password?.use { put("password", it) }
                }
            }
            transport(link.query)?.let { put("transport", it) }
            tls(link.query, link.server, link.tls)?.let { put("tls", it) }
        }

        is ShareLink.WireGuard -> buildJsonObject {
            put("type", "wireguard")
            put("tag", tag)
            put("server", link.server)
            put("server_port", link.port)
            link.privateKey.use { put("private_key", it) }
            link.peerPublicKey.use { put("peer_public_key", it) }
        }
    }

    private fun secured(query: Map<String, String>): Boolean =
        query["security"].let { it == "tls" || it == "reality" || it == "xtls" }

    private fun tls(query: Map<String, String>, server: String, secured: Boolean): JsonObject? {
        if (!secured) return null
        return buildJsonObject {
            put("enabled", true)
            put("server_name", query["sni"] ?: query["host"] ?: server)
            query["fp"]?.let { putJsonObject("utls") { put("enabled", true); put("fingerprint", it) } }
            query["alpn"]?.split(',')?.map(String::trim)?.filter(String::isNotEmpty)?.takeIf { it.isNotEmpty() }
                ?.let { values -> putJsonArray("alpn") { values.forEach { add(JsonPrimitive(it)) } } }
            if (query["allowInsecure"] == "1" || query["insecure"] == "1") put("insecure", true)
            query["pbk"]?.let { key ->
                putJsonObject("reality") {
                    put("enabled", true)
                    put("public_key", key)
                    query["sid"]?.let { put("short_id", it) }
                }
            }
        }
    }

    private fun transport(query: Map<String, String>): JsonObject? = when (query["type"]) {
        "ws" -> buildJsonObject {
            put("type", "ws")
            query["path"]?.let { put("path", it) }
            query["host"]?.let { host -> putJsonObject("headers") { put("Host", host) } }
        }

        "grpc" -> buildJsonObject {
            put("type", "grpc")
            query["serviceName"]?.let { put("service_name", it) }
        }

        "http" -> buildJsonObject {
            put("type", "http")
            query["host"]?.let { host -> putJsonArray("host") { add(JsonPrimitive(host)) } }
            query["path"]?.let { put("path", it) }
        }

        else -> null
    }
}
