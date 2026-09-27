package io.hydrabox.core.subscription

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/**
 * Builds a core entry from a share link. A link carries nothing worth preserving verbatim,
 * so the mapping is explicit — and the query string is honoured in full, because dropping
 * `security`, `sni`, `type` or `mode` is what makes a real server refuse the handshake.
 */
object ShareLinkOutbound {
    private val json =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

    private val amneziaIntegerFields = listOf("jc", "jmin", "jmax", "s1", "s2", "s3", "s4")

    private val amneziaRangeFields =
        listOf(
            "h1",
            "h2",
            "h3",
            "h4",
            "content_padding_addition",
            "rekey_after_time",
            "rekey_timeout",
            "reject_after_time",
            "keepalive_timeout",
            "max_handshake_attempts",
        )

    private val amneziaStringFields =
        listOf(
            "i1",
            "i2",
            "i3",
            "i4",
            "i5",
            "header_protection_key",
        )

    private val amneziaBooleanFields = listOf("random_trailers", "disable_cookies")

    fun typeOf(link: ShareLink): String =
        when (link) {
            is ShareLink.Vless -> "vless"
            is ShareLink.Trojan -> "trojan"
            is ShareLink.Proxy -> link.type
            is ShareLink.WireGuard -> "wireguard"
        }

    /**
     * True when the core runs this as an endpoint rather than an outbound. WireGuard moved
     * to `endpoints` in the core the app ships, and an endpoint placed in `outbounds` is not
     * a broken server — it is a configuration the core rejects as a whole.
     */
    fun isEndpoint(link: ShareLink): Boolean = link is ShareLink.WireGuard

    fun toJson(
        link: ShareLink,
        tag: String,
    ): JsonObject =
        when (link) {
            is ShareLink.Vless -> {
                buildJsonObject {
                    put("type", "vless")
                    put("tag", tag)
                    put("server", link.server)
                    put("server_port", link.port)
                    link.uuid.use { put("uuid", it) }
                    link.query["flow"]?.takeIf(String::isNotEmpty)?.let { put("flow", it) }
                    link.query["encryption"]?.takeIf { it != "none" }?.let { put("encryption", it) }
                    if (link.query.isEnabled("tfo", "tcp-fast-open", "tcp_fast_open")) put("tcp_fast_open", true)
                    transport(link.query)?.let { put("transport", it) }
                    tls(link.query, link.server, secured(link.query))?.let { put("tls", it) }
                }
            }

            is ShareLink.Trojan -> {
                buildJsonObject {
                    put("type", "trojan")
                    put("tag", tag)
                    put("server", link.server)
                    put("server_port", link.port)
                    link.password.use { put("password", it) }
                    if (link.query.isEnabled("tfo", "tcp-fast-open", "tcp_fast_open")) put("tcp_fast_open", true)
                    transport(link.query)?.let { put("transport", it) }
                    tls(link.query, link.server, secured = true)?.let { put("tls", it) }
                }
            }

            is ShareLink.Proxy -> {
                buildJsonObject {
                    put("type", link.type)
                    put("tag", tag)
                    put("server", link.server)
                    put("server_port", link.port)
                    when (link.type) {
                        "shadowsocks" -> {
                            link.username?.use { put("method", it) }
                            link.password?.use { put("password", it) }
                            link.query["plugin"]?.let { plugin ->
                                put("plugin", plugin.substringBefore(';'))
                                plugin.substringAfter(';', "").takeIf(String::isNotEmpty)?.let { put("plugin_opts", it) }
                            }
                        }

                        "shadowsocksr" -> {
                            link.username?.use { put("method", it) }
                            link.password?.use { put("password", it) }
                            link.query["protocol"]?.let { put("protocol", it) }
                            link.query["obfs"]?.let { put("obfs", it) }
                            link.query["obfs_param"]?.let { put("obfs_param", it) }
                            link.query["protocol_param"]?.let { put("protocol_param", it) }
                        }

                        "vmess" -> {
                            link.username?.use { put("uuid", it) }
                            // `scy=zero` is part of the server identity; dropping it selects `auto`.
                            link.query["scy"]?.let { put("security", it) }
                            link.query["aid"]
                                ?.toIntOrNull()
                                ?.takeIf { it > 0 }
                                ?.let { put("alter_id", it) }
                        }

                        "hysteria" -> {
                            link.query["auth"]?.takeIf(String::isNotEmpty)?.let { put("auth_str", it) }
                                ?: link.username?.use { put("auth_str", it) }
                            link.query["up"]?.takeIf(String::isNotEmpty)?.let { put("up", it) }
                            link.query["down"]?.takeIf(String::isNotEmpty)?.let { put("down", it) }
                            link.query["up_mbps"]?.toIntOrNull()?.let { put("up_mbps", it) }
                            link.query["down_mbps"]?.toIntOrNull()?.let { put("down_mbps", it) }
                            (link.query["obfs"] ?: link.query["obfsParam"])
                                ?.takeIf(String::isNotEmpty)
                                ?.let { put("obfs", it) }
                        }

                        "hysteria2" -> {
                            link.username?.use { put("password", it) }
                            link.query["up"]?.toIntOrNull()?.let { put("up_mbps", it) }
                            link.query["down"]?.toIntOrNull()?.let { put("down_mbps", it) }
                            val obfsType = link.query["obfs"]?.takeIf { it == "salamander" || it == "gecko" }
                            if (obfsType != null) {
                                putJsonObject("obfs") {
                                    put("type", obfsType)
                                    link.query["obfs-password"]?.takeIf(String::isNotEmpty)?.let { put("password", it) }
                                }
                            }
                        }

                        "tuic" -> {
                            link.username?.use { put("uuid", it) }
                            link.password?.use { put("password", it) }
                            link.query["congestion_control"]?.let { put("congestion_control", it) }
                            if (!link.query.isEnabled("udp_over_stream")) {
                                link.query["udp_relay_mode"]?.let { put("udp_relay_mode", it) }
                            }
                            if (link.query.isEnabled("udp_over_stream")) put("udp_over_stream", true)
                            if (link.query.isEnabled("zero_rtt_handshake", "reduce_rtt")) put("zero_rtt_handshake", true)
                            link.query["heartbeat_interval"]?.takeIf(String::isNotEmpty)?.let { put("heartbeat", it) }
                        }

                        "anytls" -> {
                            link.username?.use { put("password", it) }
                        }

                        "snell" -> {
                            // The link's userinfo is the PSK; the generation and its obfuscation or
                            // its traffic mode travel in the query. A fifth-generation server is
                            // answered by a fourth-generation client: the core has no client 5.
                            link.username?.use { put("psk", it) }
                            put("version", link.query["version"]?.toIntOrNull()?.takeIf { it == 4 || it == 6 } ?: 4)
                            // Both spellings occur in Snell links; the core option is `obfs_mode`.
                            (link.query["obfs"] ?: link.query["obfs-mode"])
                                ?.takeIf(String::isNotEmpty)
                                ?.let { put("obfs_mode", it) }
                            link.query["obfs-host"]?.takeIf(String::isNotEmpty)?.let { put("obfs_host", it) }
                            link.query["mode"]?.takeIf(String::isNotEmpty)?.let { put("mode", it) }
                            link.query["userkey"]?.takeIf(String::isNotEmpty)?.let { put("userkey", it) }
                            if (link.query.isEnabled("udp-relay")) {
                                putJsonArray("network") {
                                    add(JsonPrimitive("tcp"))
                                    add(JsonPrimitive("udp"))
                                }
                            }
                        }

                        "socks" -> {
                            link.username?.use { put("username", it) }
                            link.password?.use { put("password", it) }
                            link.query["version"]?.let { put("version", it) }
                        }

                        else -> {
                            link.username?.use { put("username", it) }
                            link.password?.use { put("password", it) }
                            if (link.type == "naive" && link.query.isEnabled("quic")) put("quic", true)
                        }
                    }
                    if (link.type != "naive" && link.type != "anytls" &&
                        link.query.isEnabled("tfo", "tcp-fast-open", "tcp_fast_open")
                    ) {
                        put("tcp_fast_open", true)
                    }
                    if (link.type == "vmess") transport(link.query)?.let { put("transport", it) }
                    val tlsOptions =
                        when (link.type) {
                            "naive" -> naiveTls(link.query, link.server, link.tls)
                            "anytls" -> anyTls(link.query, link.server, link.tls)
                            "socks", "shadowsocks", "shadowsocksr", "snell" -> null
                            else -> tls(link.query, link.server, link.tls)
                        }
                    tlsOptions?.let { put("tls", it) }
                }
            }

            is ShareLink.WireGuard -> {
                endpoint(link, tag)
            }
        }

    /**
     * A WireGuard peer as an endpoint. The AmneziaWG fields are carried through when the
     * provider sent them: a peer configured with junk packets will not complete a plain
     * handshake, so omitting them is the same as having the wrong key.
     */
    private fun endpoint(
        link: ShareLink.WireGuard,
        tag: String,
    ): JsonObject =
        buildJsonObject {
            put("type", "wireguard")
            put("tag", tag)
            putJsonArray("address") {
                link.localAddresses.ifEmpty { listOf("172.16.0.2/32") }.forEach { add(JsonPrimitive(it)) }
            }
            link.privateKey.use { put("private_key", it) }
            link.query["mtu"]
                ?.toIntOrNull()
                ?.takeIf { it in 576..9000 }
                ?.let { put("mtu", it) }
            putJsonArray("peers") {
                add(
                    buildJsonObject {
                        put("address", link.server)
                        put("port", link.port)
                        link.peerPublicKey.use { put("public_key", it) }
                        link.preSharedKey?.use { put("pre_shared_key", it) }
                        putJsonArray("allowed_ips") {
                            val allowed =
                                link.query["allowed_ips"]
                                    ?.split(',')
                                    ?.map(String::trim)
                                    ?.filter(String::isNotEmpty)
                            (allowed ?: listOf("0.0.0.0/0", "::/0")).forEach { add(JsonPrimitive(it)) }
                        }
                        link.query["keepalive"]
                            ?.toIntOrNull()
                            ?.takeIf { it > 0 }
                            ?.let { put("persistent_keepalive_interval", it) }
                    },
                )
            }
            amnezia(link.query)?.let { put("amnezia", it) }
        }

    /**
     * AmneziaWG 3.1 carries more than numbers: ranges, opaque strings (the CPS packets and
     * the header protection key) and two booleans. A range is accepted by the core either as
     * a single number or as an `a-b` string, which is why a non-numeric range keeps its
     * textual form instead of being dropped.
     */
    private fun amnezia(query: Map<String, String>): JsonObject? {
        val document =
            buildJsonObject {
                amneziaIntegerFields.forEach { field ->
                    query[field]?.toLongOrNull()?.let { put(field, it) }
                }
                amneziaRangeFields.forEach { field ->
                    query[field]?.takeIf(String::isNotEmpty)?.let { raw ->
                        raw.toLongOrNull()?.let { put(field, it) } ?: put(field, raw)
                    }
                }
                amneziaStringFields.forEach { field ->
                    query[field]?.takeIf(String::isNotEmpty)?.let { put(field, it) }
                }
                amneziaBooleanFields.forEach { field ->
                    query[field]?.let(::parseAmneziaBoolean)?.let { put(field, it) }
                }
            }
        return document.takeIf(JsonObject::isNotEmpty)
    }

    private fun Map<String, String>.isEnabled(vararg keys: String): Boolean =
        keys.any { this[it] == "1" || this[it].equals("true", ignoreCase = true) }

    private fun parseAmneziaBoolean(raw: String): Boolean? =
        when (raw.trim().lowercase()) {
            "1", "true", "on", "yes" -> true
            "0", "false", "off", "no" -> false
            else -> null
        }

    private fun secured(query: Map<String, String>): Boolean = query["security"].let { it == "tls" || it == "reality" || it == "xtls" }

    private fun tls(
        query: Map<String, String>,
        server: String,
        secured: Boolean,
    ): JsonObject? {
        if (!secured) return null
        return buildJsonObject {
            put("enabled", true)
            put("server_name", query["sni"] ?: query["peer"] ?: query["serviceName"] ?: query["host"] ?: server)
            if (query.isEnabled("disable_sni")) put("disable_sni", true)
            query["fp"]?.let {
                putJsonObject("utls") {
                    put("enabled", true)
                    put("fingerprint", it)
                }
            }
            query["alpn"]
                ?.split(',')
                ?.map(String::trim)
                ?.filter(String::isNotEmpty)
                ?.takeIf { it.isNotEmpty() }
                ?.let { values -> putJsonArray("alpn") { values.forEach { add(JsonPrimitive(it)) } } }
            if (query.isEnabled("allowInsecure", "insecure", "skip-cert-verify", "allow_insecure")) put("insecure", true)
            query["ca"]?.takeIf(String::isNotEmpty)?.let { put("certificate_path", it) }
            query["ca_str"]?.takeIf(String::isNotEmpty)?.let { certificates ->
                putJsonArray("certificate") { certificates.split('\n').forEach { add(JsonPrimitive(it)) } }
            }
            query["pbk"]?.let { key ->
                putJsonObject("reality") {
                    put("enabled", true)
                    put("public_key", key)
                    query["sid"]?.let { put("short_id", it) }
                    (query["spx"] ?: query["spider_x"])?.let { put("spider_x", it) }
                }
            }
        }
    }

    private fun anyTls(
        query: Map<String, String>,
        server: String,
        secured: Boolean,
    ): JsonObject? {
        if (!secured) return null
        return buildJsonObject {
            put("enabled", true)
            put("server_name", query["sni"] ?: server)
            query["ca"]?.takeIf(String::isNotEmpty)?.let { put("certificate_path", it) }
            query["ca_str"]?.takeIf(String::isNotEmpty)?.let { values ->
                putJsonArray("certificate") { values.split('\n').forEach { add(JsonPrimitive(it)) } }
            }
        }
    }

    private fun naiveTls(
        query: Map<String, String>,
        server: String,
        secured: Boolean,
    ): JsonObject? {
        if (!secured) return null
        return buildJsonObject {
            put("enabled", true)
            put("server_name", query["sni"] ?: query["host"] ?: server)
        }
    }

    /**
     * The transport the link asks for, in the core's vocabulary.
     *
     * All six the core carries are mapped, not two of them. `xhttp` in particular is what a
     * current vless provider hands out — the link in the subscription this was tested
     * against is `type=xhttp&mode=stream-up` — and mapping it to nothing produced a plain
     * TCP dial against a server that only speaks xhttp.
     */
    private fun transport(query: Map<String, String>): JsonObject? =
        when (query["type"]?.lowercase()) {
            "ws", "websocket" -> {
                buildJsonObject {
                    put("type", "ws")
                    query["path"]?.let { path ->
                        // v2rayN writes early data into the path as `?ed=2048`, and the core takes
                        // it as two separate fields.
                        put("path", path.substringBefore('?'))
                        path
                            .substringAfter("ed=", "")
                            .takeWhile(Char::isDigit)
                            .toIntOrNull()
                            ?.let {
                                put("max_early_data", it)
                                put("early_data_header_name", "Sec-WebSocket-Protocol")
                            }
                    }
                    query["host"]?.let { host -> putJsonObject("headers") { put("Host", host) } }
                }
            }

            "grpc" -> {
                buildJsonObject {
                    put("type", "grpc")
                    (query["grpc-service-name"] ?: query["serviceName"] ?: query["path"]?.trimStart('/'))
                        ?.let { put("service_name", it) }
                }
            }

            "http", "h2", "h3" -> {
                buildJsonObject {
                    put("type", "http")
                    query["host"]?.let { host ->
                        putJsonArray("host") {
                            host
                                .split(',')
                                .map(String::trim)
                                .filter(String::isNotEmpty)
                                .forEach { add(JsonPrimitive(it)) }
                        }
                    }
                    query["path"]?.let { put("path", it) }
                    query["method"]?.let { put("method", it) }
                }
            }

            "httpupgrade" -> {
                buildJsonObject {
                    put("type", "httpupgrade")
                    query["path"]?.let { put("path", it) }
                    query["host"]?.let { put("host", it) }
                }
            }

            "xhttp", "splithttp" -> {
                buildJsonObject {
                    put("type", "xhttp")
                    put("mode", query["mode"]?.takeIf(String::isNotEmpty) ?: "auto")
                    query["path"]?.let { put("path", normalizeXHTTPPath(it)) }
                    query["host"]?.let { put("host", it) }
                    // The core refuses a document whose xhttp transport names no padding range
                    // (`x_padding_bytes cannot be disabled`), and a provider that is not Hydra hands
                    // out plain `type=xhttp` links with no `extra` — one such link refused the whole
                    // configuration, taking the tunnel and every other subscription's servers down
                    // with it. The range below is the core's own runtime default
                    // (GetNormalizedXPaddingBytes), written out so the document decodes; an `extra`
                    // that carries its own range replaces it below.
                    put("x_padding_bytes", "100-1000")
                    // `extra` is a JSON object the provider appends to an xhttp link, and it is
                    // written in Xray's vocabulary: `xPaddingBytes`, `scStreamUpServerSecs`, `xmux`.
                    // The core reads the same settings under snake_case names, so the keys are
                    // translated rather than copied. Copying them verbatim is not a cosmetic
                    // difference: the core then sees no padding range at all and refuses the whole
                    // configuration with `x_padding_bytes cannot be disabled`.
                    query["extra"]?.let { extra ->
                        val fields =
                            runCatching { json.parseToJsonElement(extra) as? JsonObject }.getOrNull()
                                ?: decodeBase64(extra)?.let { decoded ->
                                    runCatching { json.parseToJsonElement(decoded) as? JsonObject }.getOrNull()
                                }
                        fields?.forEach { (key, value) ->
                            val name = xhttpExtras[key] ?: return@forEach
                            xhttpValue(value, name)?.let { put(name, it) }
                        }
                    }
                }
            }

            "quic" -> {
                buildJsonObject { put("type", "quic") }
            }

            "kcp", "mkcp" -> {
                buildJsonObject {
                    put("type", "mkcp")
                    query["headerType"]?.let { put("header_type", it) }
                    query["seed"]?.let { put("seed", it) }
                }
            }

            else -> {
                null
            }
        }

    /** Xray extra names mapped to fields tagged by V2RayXHTTPBaseOptions. */
    private val xhttpBaseExtras =
        mapOf(
            "host" to "host",
            "path" to "path",
            "headers" to "headers",
            "domainStrategy" to "domain_strategy",
            "domain_strategy" to "domain_strategy",
            "xPaddingBytes" to "x_padding_bytes",
            "x_padding_bytes" to "x_padding_bytes",
            "noGRPCHeader" to "no_grpc_header",
            "no_grpc_header" to "no_grpc_header",
            "noSSEHeader" to "no_sse_header",
            "no_sse_header" to "no_sse_header",
            "scMaxEachPostBytes" to "sc_max_each_post_bytes",
            "sc_max_each_post_bytes" to "sc_max_each_post_bytes",
            "scMinPostsIntervalMs" to "sc_min_posts_interval_ms",
            "sc_min_posts_interval_ms" to "sc_min_posts_interval_ms",
            "scMaxBufferedPosts" to "sc_max_buffered_posts",
            "sc_max_buffered_posts" to "sc_max_buffered_posts",
            "scStreamUpServerSecs" to "sc_stream_up_server_secs",
            "sc_stream_up_server_secs" to "sc_stream_up_server_secs",
            "serverMaxHeaderBytes" to "server_max_header_bytes",
            "server_max_header_bytes" to "server_max_header_bytes",
            "trustedXForwardedFor" to "trusted_x_forwarded_for",
            "trusted_x_forwarded_for" to "trusted_x_forwarded_for",
            "xmux" to "xmux",
            "xPaddingObfsMode" to "x_padding_obfs_mode",
            "x_padding_obfs_mode" to "x_padding_obfs_mode",
            "xPaddingKey" to "x_padding_key",
            "x_padding_key" to "x_padding_key",
            "xPaddingHeader" to "x_padding_header",
            "x_padding_header" to "x_padding_header",
            "xPaddingPlacement" to "x_padding_placement",
            "x_padding_placement" to "x_padding_placement",
            "xPaddingMethod" to "x_padding_method",
            "x_padding_method" to "x_padding_method",
            "uplinkHTTPMethod" to "uplink_http_method",
            "uplink_http_method" to "uplink_http_method",
            "sessionIDPlacement" to "session_placement",
            "sessionPlacement" to "session_placement",
            "session_placement" to "session_placement",
            "sessionIDKey" to "session_key",
            "sessionKey" to "session_key",
            "session_key" to "session_key",
            "seqPlacement" to "seq_placement",
            "seq_placement" to "seq_placement",
            "seqKey" to "seq_key",
            "seq_key" to "seq_key",
            "uplinkDataPlacement" to "uplink_data_placement",
            "uplink_data_placement" to "uplink_data_placement",
            "uplinkDataKey" to "uplink_data_key",
            "uplink_data_key" to "uplink_data_key",
            "uplinkChunkSize" to "uplink_chunk_size",
            "uplink_chunk_size" to "uplink_chunk_size",
            "sessionIDTable" to "session_id_table",
            "session_id_table" to "session_id_table",
            "sessionIDLength" to "session_id_length",
            "session_id_length" to "session_id_length",
            "congestionController" to "congestion_controller",
            "congestion_controller" to "congestion_controller",
            "cwnd" to "cwnd",
        )

    private val xhttpExtras = xhttpBaseExtras + ("download" to "download")

    /** V2RayXHTTPDownloadOptions embeds the base options, server, TLS, and detour. */
    private val xhttpDownloadExtras =
        xhttpBaseExtras +
            mapOf(
                "server" to "server",
                "serverPort" to "server_port",
                "server_port" to "server_port",
                "tls" to "tls",
                "detour" to "detour",
            )

    private val xmuxFields =
        mapOf(
            "maxConcurrency" to "max_concurrency",
            "max_concurrency" to "max_concurrency",
            "maxConnections" to "max_connections",
            "max_connections" to "max_connections",
            "cMaxReuseTimes" to "c_max_reuse_times",
            "c_max_reuse_times" to "c_max_reuse_times",
            "hMaxRequestTimes" to "h_max_request_times",
            "h_max_request_times" to "h_max_request_times",
            "hMaxReusableSecs" to "h_max_reusable_secs",
            "h_max_reusable_secs" to "h_max_reusable_secs",
            "hKeepAlivePeriod" to "h_keep_alive_period",
            "h_keep_alive_period" to "h_keep_alive_period",
        )

    private val xhttpTlsFields =
        mapOf(
            "enabled" to "enabled",
            "engine" to "engine",
            "disableSNI" to "disable_sni",
            "disable_sni" to "disable_sni",
            "serverName" to "server_name",
            "server_name" to "server_name",
            "insecure" to "insecure",
            "alpn" to "alpn",
            "minVersion" to "min_version",
            "min_version" to "min_version",
            "maxVersion" to "max_version",
            "max_version" to "max_version",
            "cipherSuites" to "cipher_suites",
            "cipher_suites" to "cipher_suites",
            "curvePreferences" to "curve_preferences",
            "curve_preferences" to "curve_preferences",
            "certificate" to "certificate",
            "certificatePath" to "certificate_path",
            "certificate_path" to "certificate_path",
            "certificatePublicKeySHA256" to "certificate_public_key_sha256",
            "certificate_public_key_sha256" to "certificate_public_key_sha256",
            "clientCertificate" to "client_certificate",
            "client_certificate" to "client_certificate",
            "clientCertificatePath" to "client_certificate_path",
            "client_certificate_path" to "client_certificate_path",
            "clientKey" to "client_key",
            "client_key" to "client_key",
            "clientKeyPath" to "client_key_path",
            "client_key_path" to "client_key_path",
            "fragment" to "fragment",
            "fragmentFallbackDelay" to "fragment_fallback_delay",
            "fragment_fallback_delay" to "fragment_fallback_delay",
            "recordFragment" to "record_fragment",
            "record_fragment" to "record_fragment",
            "spoof" to "spoof",
            "spoofMethod" to "spoof_method",
            "spoof_method" to "spoof_method",
            "kernelTx" to "kernel_tx",
            "kernel_tx" to "kernel_tx",
            "kernelRx" to "kernel_rx",
            "kernel_rx" to "kernel_rx",
            "handshakeTimeout" to "handshake_timeout",
            "handshake_timeout" to "handshake_timeout",
            "ech" to "ech",
            "utls" to "utls",
            "reality" to "reality",
        )

    private val xhttpEchFields =
        mapOf(
            "enabled" to "enabled",
            "config" to "config",
            "configPath" to "config_path",
            "config_path" to "config_path",
            "queryServerName" to "query_server_name",
            "query_server_name" to "query_server_name",
            "pqSignatureSchemesEnabled" to "pq_signature_schemes_enabled",
            "pq_signature_schemes_enabled" to "pq_signature_schemes_enabled",
            "dynamicRecordSizingDisabled" to "dynamic_record_sizing_disabled",
            "dynamic_record_sizing_disabled" to "dynamic_record_sizing_disabled",
        )

    private val xhttpUTlsFields =
        mapOf(
            "enabled" to "enabled",
            "fingerprint" to "fingerprint",
        )

    private val xhttpRealityFields =
        mapOf(
            "enabled" to "enabled",
            "publicKey" to "public_key",
            "public_key" to "public_key",
            "shortId" to "short_id",
            "short_id" to "short_id",
            "spiderX" to "spider_x",
            "spider_x" to "spider_x",
            "supportX25519MLKEM768" to "support_x25519mlkem768",
            "support_x25519mlkem768" to "support_x25519mlkem768",
        )

    private val xhttpRangeFields =
        setOf(
            "x_padding_bytes",
            "sc_max_each_post_bytes",
            "sc_min_posts_interval_ms",
            "sc_stream_up_server_secs",
            "uplink_chunk_size",
            "session_id_length",
            "max_concurrency",
            "max_connections",
            "c_max_reuse_times",
            "h_max_request_times",
            "h_max_reusable_secs",
        )

    private val xhttpIntegerFields =
        setOf(
            "sc_max_buffered_posts",
            "server_max_header_bytes",
            "cwnd",
            "h_keep_alive_period",
            "server_port",
        )

    private fun xhttpValue(
        value: JsonElement,
        name: String,
    ): JsonElement? =
        when (name) {
            "headers" -> {
                value
            }

            "xmux" -> {
                xhttpObject(value, xmuxFields)
            }

            "download" -> {
                xhttpObject(value, xhttpDownloadExtras)
            }

            "tls" -> {
                xhttpObject(value, xhttpTlsFields)
            }

            "ech" -> {
                xhttpObject(value, xhttpEchFields)
            }

            "utls" -> {
                xhttpObject(value, xhttpUTlsFields)
            }

            "reality" -> {
                xhttpObject(value, xhttpRealityFields)
            }

            "path" -> {
                (value as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.let { JsonPrimitive(normalizeXHTTPPath(it.content)) }
            }

            else -> {
                if (value is JsonObject) return null
                if (value is JsonPrimitive && value.isString && (name in xhttpRangeFields || name in xhttpIntegerFields)) {
                    value.content.toLongOrNull()?.let(::JsonPrimitive) ?: value
                } else {
                    value
                }
            }
        }

    private fun xhttpObject(
        value: JsonElement,
        fields: Map<String, String>,
    ): JsonObject? {
        val objectValue = value as? JsonObject ?: return null
        return buildJsonObject {
            objectValue.forEach { (key, child) ->
                val name = fields[key] ?: return@forEach
                xhttpValue(child, name)?.let { put(name, it) }
            }
        }
    }

    private fun normalizeXHTTPPath(path: String): String {
        val queryStart = path.indexOf('?')
        val pathPart = if (queryStart < 0) path else path.substring(0, queryStart)
        val queryPart = if (queryStart < 0) "" else path.substring(queryStart)
        val normalizedPath = pathPart.trimEnd('/').ifEmpty { if (pathPart.isEmpty()) "" else "/" }
        return normalizedPath + queryPart
    }
}
