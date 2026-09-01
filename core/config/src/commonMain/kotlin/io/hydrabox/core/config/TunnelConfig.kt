package io.hydrabox.core.config

import io.hydrabox.core.subscription.ShareLink
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/** Everything the generator needs that does not come from the selected outbounds. */
data class TunnelInput(
    val links: List<ShareLink>,
    val selectedTag: String?,
    val proxyDnsResolver: String = "https://dns.cloudflare.com/dns-query",
    val directDnsResolver: String = "1.1.1.1",
    val mtu: Int = 9000,
    val includePackages: List<String> = emptyList(),
    val excludePackages: List<String> = emptyList(),
    val logLevel: String = "warn",
)

const val SELECTOR_TAG = "select"
const val DIRECT_TAG = "direct"

/**
 * Builds a complete core configuration: a tun inbound, one outbound per selected share
 * link, a selector over them, and the DNS layout fixed by the plan — the proxy resolver
 * bootstraps through the local resolver and never routes application queries outside the
 * tunnel.
 */
object TunnelConfigGenerator {
    private val json = Json { prettyPrint = false }

    fun generate(input: TunnelInput): String = json.encodeToString(JsonObject.serializer(), build(input))

    fun build(input: TunnelInput): JsonObject {
        val outbounds = input.links.mapIndexed { index, link -> outbound(link, tagFor(link, index)) }
        val tags = outbounds.map { it.tag }
        val hasProxies = tags.isNotEmpty()
        val selected = input.selectedTag?.takeIf(tags::contains) ?: tags.firstOrNull()
        return buildJsonObject {
            putJsonObject("log") { put("level", input.logLevel) }
            put("dns", dns(input, hasProxies))
            putJsonArray("inbounds") { add(tun(input)) }
            putJsonArray("outbounds") {
                outbounds.forEach { add(it.value) }
                add(buildJsonObject { put("type", "direct"); put("tag", DIRECT_TAG) })
                if (hasProxies) {
                    add(
                        buildJsonObject {
                            put("type", "selector")
                            put("tag", SELECTOR_TAG)
                            putJsonArray("outbounds") { tags.forEach { add(JsonPrimitive(it)) } }
                            selected?.let { put("default", it) }
                        },
                    )
                }
            }
            put("route", route(input, hasProxies))
        }
    }

    private fun dns(input: TunnelInput, hasProxies: Boolean) = buildJsonObject {
        putJsonArray("servers") {
            add(buildJsonObject { put("type", "local"); put("tag", "dns-local") })
            add(
                buildJsonObject {
                    put("type", "udp")
                    put("tag", "dns-direct")
                    put("server", input.directDnsResolver)
                    put("detour", DIRECT_TAG)
                },
            )
            if (hasProxies) {
                add(
                    buildJsonObject {
                        put("type", "https")
                        put("tag", "dns-proxy")
                        put("server", host(input.proxyDnsResolver))
                        put("detour", SELECTOR_TAG)
                        // A resolver cannot resolve its own hostname through itself.
                        put("domain_resolver", "dns-local")
                    },
                )
            }
        }
        // Before readiness the proxy resolver refuses rather than answering outside the
        // tunnel: routing queries to a direct resolver would leak them on every start.
        put("final", if (hasProxies) "dns-proxy" else "dns-direct")
    }

    private fun tun(input: TunnelInput) = buildJsonObject {
        put("type", "tun")
        put("tag", "tun-in")
        putJsonArray("address") { add(JsonPrimitive("172.19.0.1/30")); add(JsonPrimitive("fdfe:dcba:9876::1/126")) }
        put("mtu", input.mtu)
        put("auto_route", true)
        put("strict_route", false)
        put("stack", "mixed")
        if (input.includePackages.isNotEmpty()) {
            putJsonArray("include_package") { input.includePackages.forEach { add(JsonPrimitive(it)) } }
        }
        if (input.excludePackages.isNotEmpty()) {
            putJsonArray("exclude_package") { input.excludePackages.forEach { add(JsonPrimitive(it)) } }
        }
    }

    private fun route(input: TunnelInput, hasProxies: Boolean) = buildJsonObject {
        put("default_domain_resolver", "dns-local")
        put("auto_detect_interface", true)
        put("final", if (hasProxies) SELECTOR_TAG else DIRECT_TAG)
        putJsonArray("rules") {
            add(buildJsonObject { put("action", "sniff") })
            add(buildJsonObject { put("protocol", "dns"); put("action", "hijack-dns") })
        }
    }

    private fun tagFor(link: ShareLink, index: Int): String =
        link.name.trim().takeIf(String::isNotEmpty) ?: "${link.server}-${link.port}-$index"

    private data class Outbound(val tag: String, val value: JsonObject)

    private fun outbound(link: ShareLink, tag: String): Outbound = Outbound(
        tag,
        when (link) {
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

            is ShareLink.Proxy -> proxyOutbound(link, tag)

            is ShareLink.WireGuard -> buildJsonObject {
                put("type", "wireguard")
                put("tag", tag)
                put("server", link.server)
                put("server_port", link.port)
                link.privateKey.use { put("private_key", it) }
                link.peerPublicKey.use { put("peer_public_key", it) }
            }
        },
    )

    private fun proxyOutbound(link: ShareLink.Proxy, tag: String): JsonObject = buildJsonObject {
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

            "hysteria2", "tuic", "anytls" -> link.password?.use { put("password", it) }
                ?: link.username?.use { put("password", it) }

            else -> {
                link.username?.use { put("username", it) }
                link.password?.use { put("password", it) }
            }
        }
        transport(link.query)?.let { put("transport", it) }
        tls(link.query, link.server, link.tls)?.let { put("tls", it) }
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

    private fun host(resolver: String): String = resolver
        .substringAfter("://", resolver)
        .substringBefore('/')
        .substringBefore('?')
        .takeIf(String::isNotEmpty) ?: resolver
}
