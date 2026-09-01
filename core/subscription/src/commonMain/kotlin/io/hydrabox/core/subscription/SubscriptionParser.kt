package io.hydrabox.core.subscription

import io.hydrabox.core.diagnostics.Secret
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

sealed interface ShareLink {
    val server: String
    val port: Int
    val name: String

    data class Vless(override val server: String, override val port: Int, override val name: String, val uuid: Secret) : ShareLink
    data class Trojan(override val server: String, override val port: Int, override val name: String, val password: Secret) : ShareLink
    data class Proxy(override val server: String, override val port: Int, override val name: String, val type: String, val tls: Boolean, val username: Secret?, val password: Secret?) : ShareLink
    data class WireGuard(override val server: String, override val port: Int, override val name: String, val privateKey: Secret, val peerPublicKey: Secret) : ShareLink
}

enum class SubscriptionDocumentFormat { SINGBOX, XRAY, CLASH, SIP008, HYDRA, UNKNOWN }
data class SubscriptionDocument(val format: SubscriptionDocumentFormat)
data class ParsedOutbound(val tag: String, val type: String)
data class ParsedSubscriptionDocument(val format: SubscriptionDocumentFormat, val outbounds: List<ParsedOutbound>) {
    val outboundTags get() = outbounds.map(ParsedOutbound::tag)
}

object SubscriptionParser {
    private val link = Regex("^([A-Za-z0-9+]+)://(?:([^@/?#]+)@)?([^:/?#]+):(\\d+)(?:\\?[^#]*)?(?:#(.*))?$")

    fun parse(value: String): ShareLink {
        if (value.trimStart().startsWith("[Interface]")) return parseWireGuard(value)
        val match = link.matchEntire(value.trim()) ?: error("invalid subscription link")
        val scheme = match.groupValues[1].lowercase()
        val credential = decode(match.groupValues[2])
        val server = decode(match.groupValues[3]).takeIf(String::isNotEmpty) ?: error("missing link server")
        val port = match.groupValues[4].toIntOrNull()?.takeIf { it in 1..65535 } ?: error("invalid link port")
        val name = decode(match.groupValues[5])
        return when (scheme) {
            "vless" -> ShareLink.Vless(server, port, name, Secret.of(credential.takeIf(String::isNotEmpty) ?: error("missing link credential")))
            "trojan" -> ShareLink.Trojan(server, port, name, Secret.of(credential.takeIf(String::isNotEmpty) ?: error("missing link credential")))
            "socks", "socks4", "socks4a", "socks5", "socks5h", "http", "https", "ss", "hysteria", "hy", "hy2", "hysteria2", "naive+https", "naive+quic", "tuic", "anytls" -> proxy(scheme, server, port, name, credential)
            else -> error("unsupported subscription link")
        }
    }

    private fun parseWireGuard(content: String): ShareLink.WireGuard {
        var section = ""
        val values = mutableMapOf<String, String>()
        content.lineSequence().map(String::trim).filter { it.isNotEmpty() && !it.startsWith("#") }.forEach { line ->
            if (line.startsWith("[") && line.endsWith("]")) section = line.removeSurrounding("[", "]")
            else line.split('=', limit = 2).takeIf { it.size == 2 }?.let { values["$section.${it[0].trim()}"] = it[1].trim() }
        }
        val endpoint = values["Peer.Endpoint"] ?: error("missing WireGuard endpoint")
        val divider = endpoint.lastIndexOf(':').takeIf { it > 0 } ?: error("invalid WireGuard endpoint")
        val server = endpoint.substring(0, divider).removeSurrounding("[", "]")
        val port = endpoint.substring(divider + 1).toIntOrNull()?.takeIf { it in 1..65535 } ?: error("invalid WireGuard port")
        return ShareLink.WireGuard(server, port, "WireGuard", Secret.of(values["Interface.PrivateKey"] ?: error("missing WireGuard private key")), Secret.of(values["Peer.PublicKey"] ?: error("missing WireGuard peer key")))
    }

    fun parseAll(content: String): List<ShareLink> = content
        .replace(" -> ", "\n")
        .lineSequence()
        .map(String::trim)
        .filter(String::isNotEmpty)
        .map(::parse)
        .toList()

    fun detectDocument(content: String): SubscriptionDocument {
        val trimmed = content.trim()
        val format = when {
            trimmed.startsWith("proxies:") -> SubscriptionDocumentFormat.CLASH
            trimmed.startsWith("[") && trimmed.contains("\"servers\"") -> SubscriptionDocumentFormat.SIP008
            trimmed.startsWith("{") && trimmed.contains("\"api_version\"") && trimmed.contains("hydra") -> SubscriptionDocumentFormat.HYDRA
            trimmed.startsWith("{") && trimmed.contains("\"protocol\"") -> SubscriptionDocumentFormat.XRAY
            trimmed.startsWith("{") && trimmed.contains("\"outbounds\"") -> SubscriptionDocumentFormat.SINGBOX
            else -> SubscriptionDocumentFormat.UNKNOWN
        }
        return SubscriptionDocument(format)
    }

    fun parseDocument(content: String): ParsedSubscriptionDocument {
        val format = detectDocument(content).format
        val root = runCatching { Json.parseToJsonElement(content) }.getOrNull()
        val jsonOutbounds = (root as? JsonObject)?.get("outbounds") as? JsonArray
        val outbounds = jsonOutbounds.orEmpty().mapNotNull { value ->
            (value as? JsonObject)?.let { object_ ->
                val tag = object_["tag"]?.jsonPrimitive?.contentOrNull
                val type = object_["type"]?.jsonPrimitive?.contentOrNull
                if (tag == null || type == null) null else ParsedOutbound(tag, type)
            }
        }
        val documentOutbounds = when (format) {
            SubscriptionDocumentFormat.SIP008 -> (root as? JsonArray).orEmpty()
                .flatMap { ((it as? JsonObject)?.get("servers") as? JsonArray).orEmpty() }
                .mapNotNull { (it as? JsonObject)?.get("remarks")?.jsonPrimitive?.contentOrNull }
                .map { ParsedOutbound(it, "shadowsocks") }
            SubscriptionDocumentFormat.HYDRA -> ((root as? JsonObject)?.get("profiles") as? JsonArray).orEmpty()
                .mapNotNull { (it as? JsonObject)?.get("id")?.jsonPrimitive?.contentOrNull }
                .map { ParsedOutbound(it, "hydra") }
            SubscriptionDocumentFormat.CLASH -> Regex("(?m)^\\s*-\\s*name:\\s*(.+?)\\s*$")
                .findAll(content)
                .map { ParsedOutbound(it.groupValues[1].trim().removeSurrounding("\""), "clash") }
                .toList()
            else -> outbounds
        }
        return ParsedSubscriptionDocument(format, documentOutbounds)
    }

    private fun proxy(scheme: String, server: String, port: Int, name: String, credential: String): ShareLink.Proxy {
        val parts = credential.split(':', limit = 2)
        val username = parts.firstOrNull()?.takeIf(String::isNotEmpty)?.let(Secret::of)
        val password = parts.getOrNull(1)?.takeIf(String::isNotEmpty)?.let(Secret::of)
        val type = when {
            scheme.startsWith("socks") -> "socks"
            scheme == "ss" -> "shadowsocks"
            scheme == "hy2" || scheme == "hysteria2" -> "hysteria2"
            scheme == "hysteria" || scheme == "hy" -> "hysteria"
            scheme.startsWith("naive+") -> "naive"
            scheme == "tuic" -> "tuic"
            scheme == "anytls" -> "anytls"
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
