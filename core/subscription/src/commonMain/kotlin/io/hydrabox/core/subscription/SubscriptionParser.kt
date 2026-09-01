package io.hydrabox.core.subscription

import io.hydrabox.core.diagnostics.Secret

sealed interface ShareLink {
    val server: String
    val port: Int
    val name: String

    data class Vless(override val server: String, override val port: Int, override val name: String, val uuid: Secret) : ShareLink
    data class Trojan(override val server: String, override val port: Int, override val name: String, val password: Secret) : ShareLink
    data class Proxy(override val server: String, override val port: Int, override val name: String, val type: String, val tls: Boolean, val username: Secret?, val password: Secret?) : ShareLink
}

object SubscriptionParser {
    private val link = Regex("^([A-Za-z0-9+]+)://(?:([^@/?#]+)@)?([^:/?#]+):(\\d+)(?:\\?[^#]*)?(?:#(.*))?$")

    fun parse(value: String): ShareLink {
        val match = link.matchEntire(value.trim()) ?: error("invalid subscription link")
        val scheme = match.groupValues[1].lowercase()
        val credential = decode(match.groupValues[2])
        val server = decode(match.groupValues[3]).takeIf(String::isNotEmpty) ?: error("missing link server")
        val port = match.groupValues[4].toIntOrNull()?.takeIf { it in 1..65535 } ?: error("invalid link port")
        val name = decode(match.groupValues[5])
        return when (scheme) {
            "vless" -> ShareLink.Vless(server, port, name, Secret.of(credential.takeIf(String::isNotEmpty) ?: error("missing link credential")))
            "trojan" -> ShareLink.Trojan(server, port, name, Secret.of(credential.takeIf(String::isNotEmpty) ?: error("missing link credential")))
            "socks", "socks4", "socks5", "http", "https", "ss", "hysteria", "hy2", "hysteria2", "naive+https", "naive+quic" -> proxy(scheme, server, port, name, credential)
            else -> error("unsupported subscription link")
        }
    }

    fun parseAll(content: String): List<ShareLink> = content
        .replace(" -> ", "\n")
        .lineSequence()
        .map(String::trim)
        .filter(String::isNotEmpty)
        .map(::parse)
        .toList()

    private fun proxy(scheme: String, server: String, port: Int, name: String, credential: String): ShareLink.Proxy {
        val parts = credential.split(':', limit = 2)
        val username = parts.firstOrNull()?.takeIf(String::isNotEmpty)?.let(Secret::of)
        val password = parts.getOrNull(1)?.takeIf(String::isNotEmpty)?.let(Secret::of)
        val type = when {
            scheme.startsWith("socks") -> "socks"
            scheme == "ss" -> "shadowsocks"
            scheme == "hy2" || scheme == "hysteria2" -> "hysteria2"
            scheme == "hysteria" -> "hysteria"
            scheme.startsWith("naive+") -> "naive"
            else -> "http"
        }
        return ShareLink.Proxy(server, port, name, type, scheme == "https" || scheme == "naive+https", username, password)
    }
}

private fun decode(value: String): String {
    val bytes = ArrayList<Byte>()
    var index = 0
    while (index < value.length) {
        if (value[index] == '%' && index + 2 < value.length) {
            val hex = value.substring(index + 1, index + 3).toIntOrNull(16) ?: error("invalid URL escape")
            bytes += hex.toByte(); index += 3
        } else {
            bytes += value[index++].code.toByte()
        }
    }
    return bytes.toByteArray().decodeToString()
}
