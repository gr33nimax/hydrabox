package io.hydrabox.ui.app

import io.hydrabox.ui.app.resources.*
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import org.jetbrains.compose.resources.StringResource

internal enum class ConfigFieldKind { TEXT, NUMBER, BOOLEAN, CHOICE, MULTI_CHOICE }

internal enum class ConfigValueFormat { STRING, NUMBER, BOOLEAN, COMMA_SEPARATED, NUMBER_OR_RANGE, JSON, OBJECT_PRESENCE }

internal data class ConfigFieldDescriptor(
    val path: List<String>,
    val label: StringResource?,
    val kind: ConfigFieldKind = ConfigFieldKind.TEXT,
    val format: ConfigValueFormat = ConfigValueFormat.STRING,
    val required: Boolean = false,
    val choices: List<String> = emptyList(),
    val aliases: List<List<String>> = emptyList(),
    val visibleWhen: ConfigFieldCondition? = null,
    val defaultValue: String? = null,
)

internal data class ConfigFieldCondition(
    val path: List<String>,
    val value: String? = null,
    val boolean: Boolean? = null,
    val present: Boolean? = null,
    val oneOf: Set<String> = emptySet(),
    val aliases: List<List<String>> = emptyList(),
)

internal data class ConfigFieldSection(
    val title: StringResource,
    val fields: List<ConfigFieldDescriptor>,
)

private fun path(vararg parts: String) = parts.toList()

private fun text(
    path: List<String>,
    label: StringResource?,
    required: Boolean = false,
    format: ConfigValueFormat = ConfigValueFormat.STRING,
    aliases: List<List<String>> = emptyList(),
    visibleWhen: ConfigFieldCondition? = null,
    defaultValue: String? = null,
) = ConfigFieldDescriptor(
    path,
    label,
    ConfigFieldKind.TEXT,
    format,
    required,
    aliases = aliases,
    visibleWhen = visibleWhen,
    defaultValue = defaultValue,
)

private fun number(
    path: List<String>,
    label: StringResource?,
    required: Boolean = false,
    format: ConfigValueFormat = ConfigValueFormat.NUMBER,
    aliases: List<List<String>> = emptyList(),
    visibleWhen: ConfigFieldCondition? = null,
    defaultValue: String? = null,
) = ConfigFieldDescriptor(
    path,
    label,
    ConfigFieldKind.NUMBER,
    format,
    required,
    aliases = aliases,
    visibleWhen = visibleWhen,
    defaultValue = defaultValue,
)

private fun toggle(
    path: List<String>,
    label: StringResource?,
    visibleWhen: ConfigFieldCondition? = null,
    defaultValue: String? = null,
) = ConfigFieldDescriptor(
    path,
    label,
    ConfigFieldKind.BOOLEAN,
    ConfigValueFormat.BOOLEAN,
    visibleWhen = visibleWhen,
    defaultValue = defaultValue,
)

private fun choice(
    path: List<String>,
    label: StringResource?,
    choices: List<String>,
    required: Boolean = false,
    format: ConfigValueFormat = ConfigValueFormat.STRING,
    aliases: List<List<String>> = emptyList(),
    visibleWhen: ConfigFieldCondition? = null,
    defaultValue: String? = null,
) = ConfigFieldDescriptor(
    path,
    label,
    ConfigFieldKind.CHOICE,
    format,
    required,
    choices,
    aliases,
    visibleWhen,
    defaultValue,
)

private fun multiChoice(
    path: List<String>,
    label: StringResource?,
    choices: List<String>,
    visibleWhen: ConfigFieldCondition? = null,
    defaultValue: String? = null,
) = ConfigFieldDescriptor(
    path,
    label,
    ConfigFieldKind.MULTI_CHOICE,
    ConfigValueFormat.COMMA_SEPARATED,
    choices = choices,
    visibleWhen = visibleWhen,
    defaultValue = defaultValue,
)

private fun json(
    path: List<String>,
    label: StringResource?,
    visibleWhen: ConfigFieldCondition? = null,
    defaultValue: String? = null,
) = text(path, label, format = ConfigValueFormat.JSON, visibleWhen = visibleWhen, defaultValue = defaultValue)

private fun objectToggle(
    path: List<String>,
    label: StringResource?,
    visibleWhen: ConfigFieldCondition? = null,
) = ConfigFieldDescriptor(path, label, ConfigFieldKind.BOOLEAN, ConfigValueFormat.OBJECT_PRESENCE, visibleWhen = visibleWhen)

private val tlsEnabled = ConfigFieldCondition(path("tls", "enabled"), boolean = true)
private val utlsEnabled = ConfigFieldCondition(path("tls", "utls", "enabled"), boolean = true)
private val realityEnabled = ConfigFieldCondition(path("tls", "reality", "enabled"), boolean = true)
private val muxEnabled = ConfigFieldCondition(path("multiplex", "enabled"), boolean = true)
private val brutalEnabled = ConfigFieldCondition(path("multiplex", "brutal", "enabled"), boolean = true)
private val xhttpTransport = ConfigFieldCondition(path("transport", "type"), value = "xhttp")
private val realmPresent = ConfigFieldCondition(path("realm"), present = true)
private val realmPortMappingPresent = ConfigFieldCondition(path("realm", "port_mapping"), present = true)
private val amneziaPresent = ConfigFieldCondition(path("amnezia"), present = true)
private val udpOverTcpEnabled = ConfigFieldCondition(path("udp_over_tcp", "enabled"), boolean = true)
private val quicEnabled = ConfigFieldCondition(path("quic"), boolean = true)
private val hysteria2Gecko = ConfigFieldCondition(path("obfs", "type"), value = "gecko")
private val hysteria2ObfsPresent = ConfigFieldCondition(path("obfs"), present = true)
private val hysteria2ObfsEnabled = ConfigFieldCondition(path("obfs", "type"), oneOf = setOf("salamander", "gecko"))
private val snellV4 = ConfigFieldCondition(path("version"), value = "4")
private val snellV6 = ConfigFieldCondition(path("version"), value = "6")
private val transportType = { values: Set<String> ->
    ConfigFieldCondition(path("transport", "type"), oneOf = values)
}
private val shadowsocksMethods =
    listOf(
        "none",
        "aes-128-gcm",
        "aes-256-gcm",
        "chacha20-ietf-poly1305",
        "xchacha20-ietf-poly1305",
        "2022-blake3-aes-128-gcm",
        "2022-blake3-aes-256-gcm",
        "2022-blake3-chacha20-poly1305",
    )

private val basicFields =
    listOf(
        text(path("server"), Res.string.config_parameter_server, aliases = listOf(path("address"))),
        number(path("server_port"), Res.string.config_parameter_port, aliases = listOf(path("port"))),
    )

private val sharedTlsFields =
    listOf(
        toggle(path("tls", "enabled"), Res.string.config_parameter_tls, defaultValue = "false"),
        text(
            path("tls", "server_name"),
            Res.string.config_parameter_sni,
            aliases = listOf(path("sni"), path("server_name")),
            visibleWhen = tlsEnabled,
        ),
        toggle(path("tls", "insecure"), Res.string.config_parameter_insecure, visibleWhen = tlsEnabled, defaultValue = "false"),
        multiChoice(path("tls", "alpn"), Res.string.config_parameter_alpn, listOf("h2", "http/1.1", "h3"), tlsEnabled),
        toggle(path("tls", "utls", "enabled"), Res.string.config_parameter_utls, visibleWhen = tlsEnabled, defaultValue = "false"),
        choice(
            path("tls", "utls", "fingerprint"),
            Res.string.config_parameter_fingerprint,
            listOf(
                "chrome_psk",
                "chrome_psk_shuffle",
                "chrome_padding_psk_shuffle",
                "chrome_pq",
                "chrome_pq_psk",
                "chrome",
                "firefox",
                "edge",
                "safari",
                "360",
                "qq",
                "ios",
                "android",
                "random",
                "randomized",
            ),
            visibleWhen = utlsEnabled,
        ),
        toggle(path("tls", "reality", "enabled"), null, visibleWhen = tlsEnabled, defaultValue = "false"),
        text(path("tls", "reality", "public_key"), null, visibleWhen = realityEnabled),
        text(path("tls", "reality", "short_id"), null, visibleWhen = realityEnabled),
        toggle(path("tls", "reality", "support_x25519mlkem768"), null, visibleWhen = realityEnabled),
    )

private fun tlsFieldsFor(protocol: String): List<ConfigFieldDescriptor> =
    if (protocol != "naive") {
        sharedTlsFields
    } else {
        val naiveTLSPaths =
            setOf(
                path("tls", "enabled"),
                path("tls", "server_name"),
                path("tls", "certificate"),
                path("tls", "certificate_path"),
                path("tls", "ech", "enabled"),
                path("tls", "ech", "config"),
                path("tls", "ech", "config_path"),
                path("tls", "ech", "query_server_name"),
            )
        sharedTlsFields.filter { it.path in naiveTLSPaths }
    }.map { field ->
        if (protocol in mandatoryTlsProtocols &&
            field.path == path("tls", "enabled")
        ) {
            field.copy(required = true, defaultValue = null)
        } else {
            field
        }
    }

private val hysteriaFields =
    listOf(
        text(path("server_ports"), null, format = ConfigValueFormat.COMMA_SEPARATED),
        text(path("hop_interval"), Res.string.config_parameter_hop_interval, defaultValue = "30s"),
        text(path("up"), null),
        number(path("up_mbps"), Res.string.config_parameter_upload_mbps),
        text(path("down"), null),
        number(path("down_mbps"), Res.string.config_parameter_download_mbps),
        text(path("auth"), Res.string.config_parameter_auth_encoded),
        text(path("auth_str"), Res.string.config_parameter_auth, aliases = listOf(path("username"))),
        text(path("obfs"), Res.string.config_parameter_obfs),
        number(path("recv_window_conn"), Res.string.config_parameter_receive_window_connection),
        number(path("recv_window"), Res.string.config_parameter_receive_window),
        toggle(path("disable_mtu_discovery"), Res.string.config_parameter_disable_mtu_discovery),
        multiChoice(path("network"), Res.string.config_parameter_network, listOf("tcp", "udp"), defaultValue = "tcp,udp"),
    )

private val hysteria2Fields =
    listOf(
        text(path("server_ports"), null, format = ConfigValueFormat.COMMA_SEPARATED),
        text(path("hop_interval"), Res.string.config_parameter_hop_interval, defaultValue = "30s"),
        text(path("hop_interval_max"), null, defaultValue = "30s"),
        number(path("up_mbps"), Res.string.config_parameter_upload_mbps),
        number(path("down_mbps"), Res.string.config_parameter_download_mbps),
        text(path("password"), Res.string.config_parameter_password, required = true),
        multiChoice(path("network"), Res.string.config_parameter_network, listOf("tcp", "udp"), defaultValue = "tcp,udp"),
        choice(path("bbr_profile"), null, listOf("standard", "conservative", "aggressive")),
        toggle(path("brutal_debug"), null, defaultValue = "false"),
        toggle(path("disable_chrome_parrot"), null, defaultValue = "false"),
        objectToggle(path("obfs"), Res.string.config_parameter_obfs),
        choice(path("obfs", "type"), null, listOf("salamander", "gecko"), required = true, visibleWhen = hysteria2ObfsPresent),
        text(path("obfs", "password"), Res.string.config_parameter_obfs_password, required = true, visibleWhen = hysteria2ObfsEnabled),
        number(path("obfs", "min_packet_size"), null, visibleWhen = hysteria2Gecko, defaultValue = "512"),
        number(path("obfs", "max_packet_size"), null, visibleWhen = hysteria2Gecko, defaultValue = "1200"),
        objectToggle(path("realm"), null),
        text(path("realm", "server_url"), null, required = true, visibleWhen = realmPresent),
        text(path("realm", "token"), null, visibleWhen = realmPresent),
        text(path("realm", "realm_id"), null, required = true, visibleWhen = realmPresent),
        text(path("realm", "stun_servers"), null, required = true, format = ConfigValueFormat.COMMA_SEPARATED, visibleWhen = realmPresent),
        choice(
            path("realm", "ip_version"),
            null,
            listOf("0", "4", "6"),
            format = ConfigValueFormat.NUMBER,
            visibleWhen = realmPresent,
            defaultValue = "0",
        ),
        objectToggle(path("realm", "port_mapping"), null, visibleWhen = realmPresent),
        toggle(path("realm", "port_mapping", "enabled"), null, visibleWhen = realmPortMappingPresent, defaultValue = "false"),
        text(path("realm", "port_mapping", "timeout"), null, visibleWhen = realmPortMappingPresent),
        text(path("realm", "port_mapping", "lifetime"), null, visibleWhen = realmPortMappingPresent),
        json(path("realm", "http_client"), null, visibleWhen = realmPresent, defaultValue = "{}"),
    )

private val anyTlsFields =
    listOf(
        text(path("password"), Res.string.config_parameter_password, required = true),
        text(path("idle_session_check_interval"), Res.string.config_parameter_idle_check_interval, defaultValue = "30s"),
        text(path("idle_session_timeout"), Res.string.config_parameter_idle_session_timeout, defaultValue = "30s"),
        number(path("min_idle_session"), Res.string.config_parameter_min_idle_session),
        toggle(path("disable_reuse"), null, defaultValue = "false"),
        text(path("client_metadata"), null),
    )

private val naiveFields =
    listOf(
        text(path("username"), Res.string.config_parameter_username, required = true),
        text(path("password"), Res.string.config_parameter_password, required = true),
        number(path("insecure_concurrency"), Res.string.config_parameter_insecure_concurrency, defaultValue = "1"),
        json(path("extra_headers"), null, defaultValue = "{}"),
        text(path("stream_receive_window"), null, defaultValue = "128 MiB"),
        toggle(path("udp_over_tcp", "enabled"), null, defaultValue = "false"),
        choice(path("udp_over_tcp", "version"), null, listOf("1", "2"), format = ConfigValueFormat.NUMBER, visibleWhen = udpOverTcpEnabled),
        toggle(path("quic"), null, defaultValue = "false"),
        choice(path("quic_congestion_control"), null, listOf("bbr", "bbr2", "cubic", "reno"), visibleWhen = quicEnabled),
        text(path("quic_session_receive_window"), null, visibleWhen = quicEnabled, defaultValue = "15 MiB"),
    )

private val snellFields =
    listOf(
        text(path("psk"), Res.string.config_parameter_password, required = true),
        choice(path("version"), Res.string.config_parameter_version, listOf("4", "6"), required = true, format = ConfigValueFormat.NUMBER),
        toggle(path("reuse"), null, defaultValue = "false"),
        multiChoice(path("network"), Res.string.config_parameter_network, listOf("tcp", "udp"), defaultValue = "tcp,udp"),
        choice(
            path("obfs_mode"),
            Res.string.config_parameter_obfs_mode,
            listOf("none", "http", "tls"),
            visibleWhen = snellV4,
            defaultValue = "none",
        ),
        text(path("obfs_host"), Res.string.config_parameter_obfs_host, visibleWhen = snellV4),
        choice(
            path("mode"),
            Res.string.config_parameter_mode,
            listOf("default", "unshaped", "unsafe-raw"),
            visibleWhen = snellV6,
            defaultValue = "default",
        ),
        text(path("userkey"), Res.string.config_parameter_userkey),
    )

private val mieruFields =
    listOf(
        text(path("server_ports"), null, format = ConfigValueFormat.COMMA_SEPARATED),
        choice(path("transport"), null, listOf("TCP", "UDP"), required = true),
        text(path("username"), Res.string.config_parameter_username, required = true),
        text(path("password"), Res.string.config_parameter_password, required = true),
        choice(
            path("multiplexing"),
            null,
            listOf("MULTIPLEXING_DEFAULT", "MULTIPLEXING_OFF", "MULTIPLEXING_LOW", "MULTIPLEXING_MIDDLE", "MULTIPLEXING_HIGH"),
            defaultValue = "MULTIPLEXING_DEFAULT",
        ),
        text(path("traffic_pattern"), null),
        number(path("mtu"), Res.string.config_parameter_mtu, defaultValue = "1400"),
        choice(
            path("handshake_mode"),
            null,
            listOf("HANDSHAKE_DEFAULT", "HANDSHAKE_STANDARD", "HANDSHAKE_NO_WAIT"),
            defaultValue = "HANDSHAKE_DEFAULT",
        ),
    )

private val trustTunnelFields =
    listOf(
        text(path("username"), Res.string.config_parameter_username),
        text(path("password"), Res.string.config_parameter_password),
        multiChoice(path("network"), Res.string.config_parameter_network, listOf("tcp", "udp"), defaultValue = "tcp,udp"),
        toggle(path("health_check"), null, defaultValue = "false"),
        toggle(path("quic"), null, defaultValue = "false"),
        choice(path("congestion_controller"), null, listOf("bbr", "cubic", "reno"), visibleWhen = quicEnabled, defaultValue = "bbr"),
        number(path("cwnd"), null, visibleWhen = quicEnabled, defaultValue = "32"),
    )

private val wireguardFields =
    listOf(
        text(path("address"), Res.string.config_parameter_addresses, required = true, format = ConfigValueFormat.COMMA_SEPARATED),
        text(path("private_key"), Res.string.config_parameter_private_key, required = true),
        toggle(path("system"), null, defaultValue = "false"),
        text(path("name"), null),
        number(path("listen_port"), null),
        number(path("mtu"), Res.string.config_parameter_mtu, defaultValue = "1408"),
        text(path("udp_timeout"), null, defaultValue = "5m"),
        choice(path("udp_mapping"), null, listOf("endpoint_independent", "address_dependent", "address_and_port_dependent")),
        choice(path("udp_filtering"), null, listOf("endpoint_independent", "address_dependent", "address_and_port_dependent")),
        number(path("udp_nat_max"), null),
        number(path("workers"), null),
        number(path("preallocated_buffers_per_pool"), null),
        toggle(path("disable_pauses"), null, defaultValue = "false"),
        json(path("peers"), null, defaultValue = "[]"),
        text(path("peers", "0", "public_key"), Res.string.config_parameter_public_key, required = true),
        text(path("peers", "0", "pre_shared_key"), Res.string.config_parameter_preshared_key),
        text(
            path("peers", "0", "allowed_ips"),
            Res.string.config_parameter_allowed_ips,
            required = true,
            format = ConfigValueFormat.COMMA_SEPARATED,
        ),
        number(path("peers", "0", "persistent_keepalive_interval"), Res.string.config_parameter_keepalive),
        objectToggle(path("amnezia"), null),
        number(path("amnezia", "jc"), null, visibleWhen = amneziaPresent),
        number(path("amnezia", "jmin"), null, visibleWhen = amneziaPresent),
        number(path("amnezia", "jmax"), null, visibleWhen = amneziaPresent),
        number(path("amnezia", "s1"), null, visibleWhen = amneziaPresent),
        number(path("amnezia", "s2"), null, visibleWhen = amneziaPresent),
        number(path("amnezia", "s3"), null, visibleWhen = amneziaPresent),
        number(path("amnezia", "s4"), null, visibleWhen = amneziaPresent),
        text(path("amnezia", "h1"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "h2"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "h3"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "h4"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "content_padding_addition"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "rekey_after_time"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "rekey_timeout"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "reject_after_time"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "keepalive_timeout"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "max_handshake_attempts"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = amneziaPresent),
        text(path("amnezia", "i1"), null, visibleWhen = amneziaPresent),
        text(path("amnezia", "i2"), null, visibleWhen = amneziaPresent),
        text(path("amnezia", "i3"), null, visibleWhen = amneziaPresent),
        text(path("amnezia", "i4"), null, visibleWhen = amneziaPresent),
        text(path("amnezia", "i5"), null, visibleWhen = amneziaPresent),
        text(path("amnezia", "header_protection_key"), null, visibleWhen = amneziaPresent),
        toggle(path("amnezia", "random_trailers"), null, visibleWhen = amneziaPresent),
        toggle(path("amnezia", "disable_cookies"), null, visibleWhen = amneziaPresent),
    )

private val protocolFields =
    mapOf(
        "vless" to
            listOf(
                text(path("uuid"), Res.string.config_parameter_uuid, required = true),
                choice(path("flow"), Res.string.config_parameter_flow, listOf("", "xtls-rprx-vision")),
                text(path("encryption"), Res.string.config_parameter_encryption, defaultValue = "none"),
                multiChoice(path("network"), Res.string.config_parameter_network, listOf("tcp", "udp"), defaultValue = "tcp,udp"),
                choice(path("packet_encoding"), null, listOf("", "packetaddr", "xudp"), defaultValue = "xudp"),
            ),
        "vmess" to
            listOf(
                text(path("uuid"), Res.string.config_parameter_uuid, required = true),
                number(path("alter_id"), Res.string.config_parameter_alter_id),
                choice(
                    path("security"),
                    Res.string.config_parameter_encryption,
                    listOf("auto", "none", "zero", "aes-128-gcm", "chacha20-poly1305"),
                ),
            ),
        "trojan" to listOf(text(path("password"), Res.string.config_parameter_password, required = true)),
        "shadowsocks" to
            listOf(
                choice(path("method"), Res.string.config_parameter_method, shadowsocksMethods, required = true),
                text(path("password"), Res.string.config_parameter_password, required = true),
                text(path("plugin"), Res.string.config_parameter_plugin),
                text(path("plugin_opts"), Res.string.config_parameter_plugin_opts),
            ),
        "shadowsocksr" to
            listOf(
                choice(path("method"), Res.string.config_parameter_method, shadowsocksMethods, required = true),
                text(path("password"), Res.string.config_parameter_password, required = true),
                text(path("protocol"), Res.string.config_parameter_protocol),
                text(path("protocol_param"), Res.string.config_parameter_obfs_protocol_param),
                text(path("obfs"), Res.string.config_parameter_obfs_protocol),
                text(path("obfs_param"), Res.string.config_parameter_obfs_param),
            ),
        "hysteria" to hysteriaFields,
        "hysteria2" to hysteria2Fields,
        "tuic" to
            listOf(
                text(path("uuid"), Res.string.config_parameter_uuid, required = true),
                text(path("password"), Res.string.config_parameter_password, required = true),
                choice(path("congestion_control"), Res.string.config_parameter_congestion_control, listOf("cubic", "new_reno", "bbr")),
                choice(path("udp_relay_mode"), Res.string.config_parameter_udp_relay_mode, listOf("native", "quic")),
                toggle(path("udp_over_stream"), Res.string.config_parameter_udp_over_stream),
                toggle(path("zero_rtt_handshake"), Res.string.config_parameter_zero_rtt),
                text(path("heartbeat"), Res.string.config_parameter_heartbeat),
            ),
        "anytls" to anyTlsFields,
        "snell" to snellFields,
        "naive" to naiveFields,
        "socks" to
            listOf(
                choice(path("version"), Res.string.config_parameter_version, listOf("", "4", "4a", "5")),
                text(path("username"), Res.string.config_parameter_username),
                text(path("password"), Res.string.config_parameter_password),
            ),
        "http" to
            listOf(
                text(path("username"), Res.string.config_parameter_username),
                text(path("password"), Res.string.config_parameter_password),
            ),
        "wireguard" to wireguardFields,
        "mieru" to mieruFields,
        "trusttunnel" to trustTunnelFields,
    )

private val tlsProtocols = setOf("vless", "vmess", "trojan", "hysteria", "hysteria2", "tuic", "anytls", "naive", "trusttunnel")
private val mandatoryTlsProtocols = setOf("hysteria", "hysteria2", "anytls", "naive", "trusttunnel")
private val transportProtocols = setOf("vless", "vmess", "trojan")
private val transportPathTypes = setOf("ws", "http", "httpupgrade", "xhttp")
private val xmuxPresent = ConfigFieldCondition(path("transport", "xmux"), present = true)

private fun transportFields(): List<ConfigFieldDescriptor> {
    val ws = transportType(setOf("ws"))
    val http = transportType(setOf("http"))
    val grpc = transportType(setOf("grpc"))
    val xhttp = xhttpTransport
    val mkcp = transportType(setOf("mkcp"))
    return listOf(
        choice(
            path("transport", "type"),
            Res.string.config_parameter_transport,
            listOf("", "http", "ws", "quic", "grpc", "httpupgrade", "xhttp", "mkcp"),
        ),
        text(
            path("transport", "path"),
            Res.string.config_parameter_path,
            aliases = listOf(path("path")),
            visibleWhen = transportType(transportPathTypes),
        ),
        text(path("transport", "host"), Res.string.config_parameter_host, format = ConfigValueFormat.COMMA_SEPARATED, visibleWhen = http),
        text(
            path("transport", "host"),
            Res.string.config_parameter_host,
            aliases = listOf(path("host")),
            visibleWhen = transportType(setOf("httpupgrade", "xhttp")),
        ),
        json(
            path("transport", "headers"),
            null,
            visibleWhen = transportType(setOf("ws", "http", "httpupgrade", "xhttp")),
            defaultValue = "{}",
        ),
        text(
            path("transport", "headers", "Host"),
            Res.string.config_parameter_host,
            aliases = listOf(path("host")),
            visibleWhen = transportType(setOf("ws")),
        ),
        text(path("transport", "method"), null, visibleWhen = http),
        text(path("transport", "idle_timeout"), null, visibleWhen = transportType(setOf("http", "grpc"))),
        text(path("transport", "ping_timeout"), null, visibleWhen = transportType(setOf("http", "grpc"))),
        number(path("transport", "max_early_data"), null, visibleWhen = ws),
        text(path("transport", "early_data_header_name"), null, visibleWhen = ws),
        text(
            path("transport", "service_name"),
            Res.string.config_parameter_service_name,
            aliases = listOf(path("transport", "serviceName"), path("serviceName")),
            visibleWhen = grpc,
        ),
        toggle(path("transport", "permit_without_stream"), null, visibleWhen = grpc),
        choice(
            path("transport", "mode"),
            null,
            listOf("auto", "packet-up", "stream-up", "stream-one"),
            visibleWhen = xhttp,
            defaultValue = "auto",
        ),
        choice(
            path("transport", "domain_strategy"),
            null,
            listOf("", "prefer_ipv4", "prefer_ipv6", "ipv4_only", "ipv6_only"),
            visibleWhen = xhttp,
        ),
        text(
            path("transport", "x_padding_bytes"),
            null,
            required = true,
            format = ConfigValueFormat.NUMBER_OR_RANGE,
            visibleWhen = xhttp,
            defaultValue = "100-1000",
        ),
        toggle(path("transport", "no_grpc_header"), null, visibleWhen = xhttp),
        toggle(path("transport", "no_sse_header"), null, visibleWhen = xhttp),
        text(
            path("transport", "sc_max_each_post_bytes"),
            null,
            format = ConfigValueFormat.NUMBER_OR_RANGE,
            visibleWhen = xhttp,
            defaultValue = "1000000",
        ),
        text(
            path("transport", "sc_min_posts_interval_ms"),
            null,
            format = ConfigValueFormat.NUMBER_OR_RANGE,
            visibleWhen = xhttp,
            defaultValue = "30",
        ),
        number(path("transport", "sc_max_buffered_posts"), null, visibleWhen = xhttp, defaultValue = "30"),
        text(
            path("transport", "sc_stream_up_server_secs"),
            null,
            format = ConfigValueFormat.NUMBER_OR_RANGE,
            visibleWhen = xhttp,
            defaultValue = "20-80",
        ),
        number(path("transport", "server_max_header_bytes"), null, visibleWhen = xhttp),
        text(path("transport", "trusted_x_forwarded_for"), null, format = ConfigValueFormat.COMMA_SEPARATED, visibleWhen = xhttp),
        toggle(path("transport", "x_padding_obfs_mode"), null, visibleWhen = xhttp),
        text(path("transport", "x_padding_key"), null, visibleWhen = xhttp),
        text(path("transport", "x_padding_header"), null, visibleWhen = xhttp),
        choice(
            path("transport", "x_padding_placement"),
            null,
            listOf("queryInHeader", "cookie", "header", "query"),
            visibleWhen = xhttp,
            defaultValue = "queryInHeader",
        ),
        choice(path("transport", "x_padding_method"), null, listOf("repeat-x", "tokenish"), visibleWhen = xhttp, defaultValue = "repeat-x"),
        choice(path("transport", "uplink_http_method"), null, listOf("POST", "GET"), visibleWhen = xhttp, defaultValue = "POST"),
        choice(
            path("transport", "session_placement"),
            null,
            listOf("path", "query", "header", "cookie"),
            visibleWhen = xhttp,
            defaultValue = "path",
        ),
        text(path("transport", "session_key"), null, visibleWhen = xhttp),
        choice(
            path("transport", "seq_placement"),
            null,
            listOf("path", "query", "header", "cookie"),
            visibleWhen = xhttp,
            defaultValue = "path",
        ),
        text(path("transport", "seq_key"), null, visibleWhen = xhttp),
        choice(
            path("transport", "uplink_data_placement"),
            null,
            listOf("auto", "body", "header", "cookie"),
            visibleWhen = xhttp,
            defaultValue = "auto",
        ),
        text(path("transport", "uplink_data_key"), null, visibleWhen = xhttp),
        text(path("transport", "uplink_chunk_size"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = xhttp),
        text(path("transport", "session_id_table"), null, visibleWhen = xhttp),
        text(path("transport", "session_id_length"), null, format = ConfigValueFormat.NUMBER_OR_RANGE, visibleWhen = xhttp),
        choice(path("transport", "congestion_controller"), null, listOf("cubic", "new_reno", "bbr"), visibleWhen = xhttp),
        number(path("transport", "cwnd"), null, visibleWhen = xhttp),
        json(path("transport", "download"), null, visibleWhen = xhttp, defaultValue = "{}"),
        number(path("transport", "mtu"), null, visibleWhen = mkcp),
        number(path("transport", "tti"), null, visibleWhen = mkcp),
        number(path("transport", "uplink_capacity"), null, visibleWhen = mkcp),
        number(path("transport", "downlink_capacity"), null, visibleWhen = mkcp),
        toggle(path("transport", "congestion"), null, visibleWhen = mkcp),
        number(path("transport", "read_buffer_size"), null, visibleWhen = mkcp),
        number(path("transport", "write_buffer_size"), null, visibleWhen = mkcp),
        text(path("transport", "header_type"), null, visibleWhen = mkcp),
        text(path("transport", "seed"), null, visibleWhen = mkcp),
    )
}

private fun multiplexFields(protocol: String): List<ConfigFieldDescriptor> =
    when (protocol) {
        "trusttunnel" -> {
            listOf(
                toggle(path("multiplex", "enabled"), null, defaultValue = "false"),
                number(path("multiplex", "max_connections"), null, visibleWhen = muxEnabled),
                number(path("multiplex", "min_streams"), null, visibleWhen = muxEnabled),
                number(path("multiplex", "max_streams"), null, visibleWhen = muxEnabled),
            )
        }

        "vless" -> {
            listOf(
                toggle(path("multiplex", "enabled"), null, defaultValue = "false"),
                choice(path("multiplex", "protocol"), null, listOf("h2mux", "smux", "yamux"), visibleWhen = muxEnabled),
                number(path("multiplex", "max_connections"), null, visibleWhen = muxEnabled),
                number(path("multiplex", "min_streams"), null, visibleWhen = muxEnabled),
                number(path("multiplex", "max_streams"), null, visibleWhen = muxEnabled),
                toggle(path("multiplex", "padding"), null, visibleWhen = muxEnabled, defaultValue = "false"),
                toggle(path("multiplex", "brutal", "enabled"), null, visibleWhen = muxEnabled, defaultValue = "false"),
                number(path("multiplex", "brutal", "up_mbps"), Res.string.config_parameter_upload_mbps, visibleWhen = brutalEnabled),
                number(path("multiplex", "brutal", "down_mbps"), Res.string.config_parameter_download_mbps, visibleWhen = brutalEnabled),
                objectToggle(path("transport", "xmux"), null, visibleWhen = xhttpTransport),
                text(
                    path("transport", "xmux", "max_concurrency"),
                    null,
                    format = ConfigValueFormat.NUMBER_OR_RANGE,
                    visibleWhen = xmuxPresent,
                    defaultValue = "1-1",
                ),
                text(
                    path("transport", "xmux", "max_connections"),
                    null,
                    format = ConfigValueFormat.NUMBER_OR_RANGE,
                    visibleWhen = xmuxPresent,
                ),
                text(
                    path("transport", "xmux", "c_max_reuse_times"),
                    null,
                    format = ConfigValueFormat.NUMBER_OR_RANGE,
                    visibleWhen = xmuxPresent,
                ),
                text(
                    path("transport", "xmux", "h_max_request_times"),
                    null,
                    format = ConfigValueFormat.NUMBER_OR_RANGE,
                    visibleWhen = xmuxPresent,
                    defaultValue = "600-900",
                ),
                text(
                    path("transport", "xmux", "h_max_reusable_secs"),
                    null,
                    format = ConfigValueFormat.NUMBER_OR_RANGE,
                    visibleWhen = xmuxPresent,
                    defaultValue = "1800-3000",
                ),
                number(path("transport", "xmux", "h_keep_alive_period"), null, visibleWhen = xmuxPresent),
            )
        }

        else -> {
            emptyList()
        }
    }

internal fun configFieldSections(type: String?): List<ConfigFieldSection> {
    val protocol =
        when (type?.lowercase()) {
            "ss" -> "shadowsocks"
            "ssr" -> "shadowsocksr"
            else -> type?.lowercase()
        }
    val known = protocol?.let(protocolFields::get)
    val basic =
        if (protocol == "wireguard") {
            listOf(
                text(path("peers", "0", "address"), Res.string.config_parameter_server, required = true),
                number(path("peers", "0", "port"), Res.string.config_parameter_port, required = true),
            )
        } else {
            basicFields.map { field ->
                when {
                    known == null -> field
                    protocol == "mieru" && field.path == path("server_port") -> field
                    protocol in setOf("hysteria", "hysteria2") && field.path == path("server_port") -> field
                    protocol == "hysteria2" -> field
                    else -> field.copy(required = true)
                }
            }
        }
    return buildList {
        add(ConfigFieldSection(Res.string.config_section_basic, basic))
        if (protocol in tlsProtocols) add(ConfigFieldSection(Res.string.config_section_tls, tlsFieldsFor(protocol!!)))
        if (protocol in transportProtocols) add(ConfigFieldSection(Res.string.config_section_transport, transportFields()))
        if (protocol == "vless" || protocol == "trusttunnel") {
            add(ConfigFieldSection(Res.string.config_section_multiplex, multiplexFields(protocol)))
        }
        if (known != null) {
            val taggedFields = if (protocol == "wireguard") emptyList() else listOf(text(path("tag"), Res.string.config_parameter_tag))
            add(ConfigFieldSection(Res.string.config_section_protocol, taggedFields + known))
        }
    }
}

internal fun configFieldChoices(
    root: JsonObject,
    field: ConfigFieldDescriptor,
): List<String> {
    val mode = (jsonAt(root, path("transport", "mode")) as? JsonPrimitive)?.contentOrNull ?: "auto"
    return when (field.path) {
        path("transport", "uplink_http_method") -> {
            if (mode == "packet-up") listOf("POST", "GET") else listOf("POST")
        }

        path("transport", "uplink_data_placement") -> {
            if (mode == "packet-up") listOf("auto", "body", "header", "cookie") else listOf("auto", "body")
        }

        else -> {
            field.choices
        }
    }
}

internal fun configFieldDefaultValue(
    root: JsonObject,
    field: ConfigFieldDescriptor,
): String? =
    when (field.path) {
        path("tls", "server_name") -> {
            listOf(path("server"), path("address")).firstNotNullOfOrNull { candidate ->
                (jsonAt(root, candidate) as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
            }
        }

        path("hop_interval_max") -> {
            ((jsonAt(root, path("hop_interval")) as? JsonPrimitive)?.contentOrNull)
                ?: "30s"
        }

        path("obfs_host") -> {
            if ((jsonAt(root, path("version")) as? JsonPrimitive)?.contentOrNull == "4") {
                when ((jsonAt(root, path("obfs_mode")) as? JsonPrimitive)?.contentOrNull) {
                    "http" -> "bing.com"
                    "tls" -> "cloudfront.net"
                    else -> null
                }
            } else {
                null
            }
        }

        else -> {
            field.defaultValue
        }
    }

internal fun configFieldValue(
    root: JsonObject,
    field: ConfigFieldDescriptor,
): String {
    if (field.path == path("udp_over_tcp", "enabled")) {
        (root["udp_over_tcp"] as? JsonPrimitive)?.booleanOrNull?.let { return it.toString() }
    }
    val stored =
        field.storedPath(root)?.let { jsonAt(root, it) }
            ?: return if (field.format == ConfigValueFormat.OBJECT_PRESENCE) "false" else ""
    if (field.format == ConfigValueFormat.OBJECT_PRESENCE) return (stored != JsonNull).toString()
    if (field.format == ConfigValueFormat.JSON) return stored.toString()
    if (field.format == ConfigValueFormat.COMMA_SEPARATED) {
        val values = (stored as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
        if (values != null) return values.joinToString(", ")
    }
    return (stored as? JsonPrimitive)?.contentOrNull.orEmpty()
}

internal fun configFieldVisible(
    root: JsonObject,
    field: ConfigFieldDescriptor,
): Boolean {
    val condition = field.visibleWhen ?: return true
    val value =
        (listOf(condition.path) + condition.aliases).firstNotNullOfOrNull { jsonAt(root, it) }
            ?: if (condition.path == path("udp_over_tcp", "enabled")) {
                (root["udp_over_tcp"] as? JsonPrimitive)?.takeIf { it.booleanOrNull != null }
            } else {
                null
            }
    if (condition.present != null) return (value != null && value != JsonNull) == condition.present
    val primitive = value as? JsonPrimitive ?: return false
    condition.boolean?.let { return primitive.booleanOrNull == it }
    if (condition.oneOf.isNotEmpty()) return primitive.contentOrNull in condition.oneOf
    return primitive.contentOrNull == condition.value
}

internal fun hasRequiredConfigFields(
    root: JsonObject,
    type: String?,
): Boolean {
    val protocol = type?.lowercase()
    val fields = configFieldSections(type).flatMap { it.fields }
    val requiredFieldsPresent =
        fields
            .filter { it.required && configFieldVisible(root, it) }
            .all { configFieldValue(root, it).isNotBlank() }
    val portPresent = hasConfigValue(root, path("server_port"), path("port")) || hasConfigValue(root, path("server_ports"))
    val serverPresent = hasConfigValue(root, path("server"), path("address"))
    val alternateServerFieldsPresent =
        when (protocol) {
            "mieru", "hysteria" -> portPresent
            "hysteria2" -> hasConfigValue(root, path("realm")) || (serverPresent && portPresent)
            else -> true
        }
    val tlsPresent =
        protocol !in mandatoryTlsProtocols || configFieldValue(root, toggle(path("tls", "enabled"), null)) == "true"
    val hysteriaAuthPresent =
        protocol != "hysteria" || hasConfigValue(root, path("auth_str"), path("username")) || hasConfigValue(root, path("auth"))
    return requiredFieldsPresent && alternateServerFieldsPresent && tlsPresent && hysteriaAuthPresent
}

private fun hasConfigValue(
    root: JsonObject,
    vararg paths: List<String>,
): Boolean =
    paths.any { candidate ->
        when (val value = jsonAt(root, candidate)) {
            null, JsonNull -> false
            is JsonPrimitive -> value.contentOrNull?.isNotBlank() == true
            is JsonArray -> value.isNotEmpty()
            is JsonObject -> value.isNotEmpty()
        }
    }

internal fun updateConfigField(
    root: JsonObject,
    field: ConfigFieldDescriptor,
    input: String,
): JsonObject {
    val element =
        when (field.format) {
            ConfigValueFormat.STRING -> {
                input.takeIf(String::isNotEmpty)?.let(::JsonPrimitive)
            }

            ConfigValueFormat.NUMBER -> {
                input.toLongOrNull()?.let(::JsonPrimitive)
            }

            ConfigValueFormat.BOOLEAN -> {
                JsonPrimitive(input.equals("true", ignoreCase = true))
            }

            ConfigValueFormat.COMMA_SEPARATED -> {
                input
                    .split(',')
                    .map(String::trim)
                    .filter(String::isNotEmpty)
                    .takeIf(List<String>::isNotEmpty)
                    ?.map(::JsonPrimitive)
                    ?.let(::JsonArray)
            }

            ConfigValueFormat.NUMBER_OR_RANGE -> {
                input.takeIf(String::isNotEmpty)?.let { value -> value.toLongOrNull()?.let(::JsonPrimitive) ?: JsonPrimitive(value) }
            }

            ConfigValueFormat.JSON -> {
                input.takeIf(String::isNotBlank)?.let { value ->
                    runCatching {
                        kotlinx.serialization.json.Json
                            .parseToJsonElement(value)
                    }.getOrElse { return root }
                }
            }

            ConfigValueFormat.OBJECT_PRESENCE -> {
                if (input.equals("true", ignoreCase = true)) JsonObject(emptyMap()) else null
            }
        }
    val targetRoot = root.withLegacyUdpOverTcp(field)
    val destination = field.storedPath(targetRoot)
    if (element == null && destination == null) return root
    return replaceAt(targetRoot, destination ?: field.path, element) as? JsonObject ?: root
}

private fun JsonObject.withLegacyUdpOverTcp(field: ConfigFieldDescriptor): JsonObject {
    if (field.path.firstOrNull() != "udp_over_tcp" || field.path.size < 2) return this
    val legacyEnabled = (this["udp_over_tcp"] as? JsonPrimitive)?.booleanOrNull ?: return this
    return JsonObject(toMutableMap().apply { this["udp_over_tcp"] = JsonObject(mapOf("enabled" to JsonPrimitive(legacyEnabled))) })
}

private fun ConfigFieldDescriptor.storedPath(root: JsonObject): List<String>? =
    (listOf(path) + aliases).firstOrNull { jsonAt(root, it) != null }

private fun jsonAt(
    root: JsonObject,
    path: List<String>,
): JsonElement? {
    var current: JsonElement? = root
    path.forEach { segment ->
        current =
            when (val node = current) {
                is JsonObject -> node[segment]
                is JsonArray -> segment.toIntOrNull()?.let(node::getOrNull)
                else -> null
            }
    }
    return current
}

private fun replaceAt(
    current: JsonElement,
    path: List<String>,
    replacement: JsonElement?,
): JsonElement? {
    if (path.isEmpty()) return replacement
    val part = path.first()
    val next = path.drop(1)
    val index = part.toIntOrNull()
    if (index != null && index >= 0) {
        val original = (current as? JsonArray)?.toMutableList() ?: mutableListOf()
        while (original.size <= index) original += JsonNull
        val child = original[index].takeUnless { it == JsonNull } ?: emptyContainer(next.firstOrNull())
        val updated = replaceAt(child, next, replacement)
        if (updated == null) original.removeAt(index) else original[index] = updated
        return JsonArray(original)
    }
    val original = (current as? JsonObject)?.toMutableMap() ?: mutableMapOf()
    val child = original[part] ?: emptyContainer(next.firstOrNull())
    val updated = replaceAt(child, next, replacement)
    if (updated == null) original.remove(part) else original[part] = updated
    return JsonObject(original)
}

private fun emptyContainer(next: String?): JsonElement = if (next?.toIntOrNull() != null) JsonArray(emptyList()) else JsonObject(emptyMap())
