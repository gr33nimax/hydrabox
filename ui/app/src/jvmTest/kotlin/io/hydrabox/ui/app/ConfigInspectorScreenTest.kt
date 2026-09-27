package io.hydrabox.ui.app

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ConfigInspectorScreenTest {
    @Test
    fun `descriptor edits preserve unknown json values`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"vless","server":"vpn.example","server_port":443,"uuid":"old","bind_interface":"eth0","tcp_fast_open":true,"domain_strategy":"prefer_ipv4","extension":{"enabled":true,"items":[1,"x"]},"tls":{"enabled":true,"vendor_option":"kept"}}""",
                ).jsonObject

        val updated = original.edit("vless", listOf("uuid"), "new")

        assertEquals(original["bind_interface"], updated["bind_interface"])
        assertEquals(original["tcp_fast_open"], updated["tcp_fast_open"])
        assertEquals(original["domain_strategy"], updated["domain_strategy"])
        assertEquals(original["extension"], updated["extension"])
        assertEquals(original["tls"], updated["tls"])
        assertEquals(Json.parseToJsonElement("\"new\""), updated["uuid"])
    }

    @Test
    fun `vless tls and websocket edits assemble valid json`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"vless","server":"vpn.example","server_port":443,"uuid":"old","tls":{"enabled":true,"server_name":"old.example"},"transport":{"type":"ws","path":"/old","headers":{"Host":"old.example"}}}""",
                ).jsonObject

        val updated =
            original
                .edit("vless", listOf("uuid"), "new-id")
                .edit("vless", listOf("tls", "server_name"), "cdn.example")
                .edit("vless", listOf("transport", "path"), "/tunnel")
                .edit("vless", listOf("transport", "headers", "Host"), "edge.example")

        assertEquals(
            Json.parseToJsonElement(
                """{"type":"vless","server":"vpn.example","server_port":443,"uuid":"new-id","tls":{"enabled":true,"server_name":"cdn.example"},"transport":{"type":"ws","path":"/tunnel","headers":{"Host":"edge.example"}}}""",
            ),
            updated,
        )
    }

    @Test
    fun `shadowsocks credentials and method remain typed json`() {
        val original = Json.parseToJsonElement("""{"type":"shadowsocks","server":"ss.example","server_port":8388}""").jsonObject
        val updated =
            original
                .edit("shadowsocks", listOf("method"), "2022-blake3-aes-128-gcm")
                .edit("shadowsocks", listOf("password"), "secret")

        assertEquals(
            Json.parseToJsonElement(
                """{"type":"shadowsocks","server":"ss.example","server_port":8388,"method":"2022-blake3-aes-128-gcm","password":"secret"}""",
            ),
            updated,
        )
    }

    @Test
    fun `wireguard and amnezia edits preserve endpoint shapes`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"wireguard","address":["10.0.0.2/32"],"private_key":"private","peers":[{"address":"wg.example","port":51820,"public_key":"peer","allowed_ips":["0.0.0.0/0"]}],"amnezia":{"jc":3,"unknown":"kept"}}""",
                ).jsonObject

        val updated =
            original
                .edit("wireguard", listOf("peers", "0", "port"), "443")
                .edit("wireguard", listOf("amnezia", "jc"), "7")

        assertEquals(
            Json.parseToJsonElement(
                """{"type":"wireguard","address":["10.0.0.2/32"],"private_key":"private","peers":[{"address":"wg.example","port":443,"public_key":"peer","allowed_ips":["0.0.0.0/0"]}],"amnezia":{"jc":7,"unknown":"kept"}}""",
            ),
            updated,
        )
    }

    @Test
    fun `hysteria2 password and obfuscation edits assemble nested json`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"hysteria2","server":"hy2.example","server_port":443,"password":"old","tls":{"enabled":true},"obfs":{"type":"salamander","password":"old-obfs"}}""",
                ).jsonObject

        val updated =
            original
                .edit("hysteria2", listOf("password"), "new")
                .edit("hysteria2", listOf("obfs", "password"), "new-obfs")

        assertEquals(
            Json.parseToJsonElement(
                """{"type":"hysteria2","server":"hy2.example","server_port":443,"password":"new","tls":{"enabled":true},"obfs":{"type":"salamander","password":"new-obfs"}}""",
            ),
            updated,
        )
    }

    @Test
    fun `vless xhttp and multiplex fields use spec keys and retain unknown values`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"vless","server":"vpn.example","server_port":443,"uuid":"id","transport":{"type":"xhttp","future_transport":{"mode":"keep"},"xmux":{"h_max_request_times":"600-900"}},"future":{"enabled":true}}""",
                ).jsonObject

        val updated =
            original
                .edit("vless", listOf("packet_encoding"), "packetaddr")
                .edit("vless", listOf("transport", "x_padding_bytes"), "150-900")
                .edit("vless", listOf("transport", "xmux", "h_keep_alive_period"), "12")
                .edit("vless", listOf("multiplex", "protocol"), "yamux")

        assertEquals(
            Json.parseToJsonElement(
                """{"type":"vless","server":"vpn.example","server_port":443,"uuid":"id","packet_encoding":"packetaddr","transport":{"type":"xhttp","future_transport":{"mode":"keep"},"x_padding_bytes":"150-900","xmux":{"h_max_request_times":"600-900","h_keep_alive_period":12}},"multiplex":{"protocol":"yamux"},"future":{"enabled":true}}""",
            ),
            updated,
        )
    }

    @Test
    fun `hysteria2 gecko fields use spec keys and retain unknown values`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"hysteria2","server":"hy2.example","server_port":443,"password":"secret","tls":{"enabled":true,"future_tls":1},"obfs":{"type":"gecko","password":"secret","future_obfs":true},"future":7}""",
                ).jsonObject

        val updated =
            original
                .edit("hysteria2", listOf("bbr_profile"), "aggressive")
                .edit("hysteria2", listOf("obfs", "min_packet_size"), "600")

        assertEquals(
            Json.parseToJsonElement(
                """{"type":"hysteria2","server":"hy2.example","server_port":443,"password":"secret","tls":{"enabled":true,"future_tls":1},"obfs":{"type":"gecko","password":"secret","future_obfs":true,"min_packet_size":600},"future":7,"bbr_profile":"aggressive"}""",
            ),
            updated,
        )
    }

    @Test
    fun `mieru transport and multiplexing edits use spec enums and retain unknown values`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"mieru","server":"mieru.example","server_port":443,"username":"user","password":"secret","future":{"x":1}}""",
                ).jsonObject

        val updated =
            original
                .edit("mieru", listOf("transport"), "UDP")
                .edit("mieru", listOf("multiplexing"), "MULTIPLEXING_HIGH")
                .edit("mieru", listOf("handshake_mode"), "HANDSHAKE_NO_WAIT")

        assertEquals(
            Json.parseToJsonElement(
                """{"type":"mieru","server":"mieru.example","server_port":443,"username":"user","password":"secret","future":{"x":1},"transport":"UDP","multiplexing":"MULTIPLEXING_HIGH","handshake_mode":"HANDSHAKE_NO_WAIT"}""",
            ),
            updated,
        )
    }

    @Test
    fun `typed sections include only applicable TLS and transport fields`() {
        val tlsProtocols = setOf("vless", "vmess", "trojan", "hysteria", "hysteria2", "tuic", "anytls", "naive", "trusttunnel")
        val transportProtocols = setOf("vless", "vmess", "trojan")
        val protocols =
            listOf(
                "vless",
                "vmess",
                "trojan",
                "shadowsocks",
                "shadowsocksr",
                "hysteria",
                "hysteria2",
                "tuic",
                "anytls",
                "snell",
                "naive",
                "socks",
                "http",
                "wireguard",
                "mieru",
                "trusttunnel",
            )

        protocols.forEach { type ->
            val sections = configFieldSections(type)
            val fields = sections.flatMap { it.fields }
            val commonDialerFields =
                paths(
                    """
                    detour bind_interface inet4_bind_address inet6_bind_address bind_address_no_port protect_path routing_mark
                    reuse_addr netns connect_timeout tcp_fast_open tcp_multi_path disable_tcp_keep_alive tcp_keep_alive
                    tcp_keep_alive_interval udp_fragment domain_resolver network_strategy network_type fallback_network_type
                    fallback_delay domain_strategy
                    """,
                )

            assertFalse(fields.any { it.path in commonDialerFields }, "Common dialer fields leaked into $type form")
            assertFalse(hasRequiredConfigFields(JsonObject(emptyMap()), type), "Missing typed descriptor for $type")
            assertEquals(type in tlsProtocols, fields.any { it.path == listOf("tls", "enabled") }, "Unexpected TLS fields for $type")
            assertEquals(
                type in transportProtocols,
                fields.any { it.path == listOf("transport", "type") },
                "Unexpected transport fields for $type",
            )
        }
    }

    @Test
    fun `target descriptors include every specified protocol field`() {
        val tls =
            paths(
                """
            tls.enabled tls.server_name tls.insecure tls.alpn tls.utls.enabled tls.utls.fingerprint
            tls.reality.enabled tls.reality.public_key tls.reality.short_id tls.reality.support_x25519mlkem768
        """,
            )
        val transport =
            paths(
                """
            transport.type transport.path transport.host transport.headers transport.headers.Host transport.method
            transport.idle_timeout transport.ping_timeout transport.max_early_data transport.early_data_header_name
            transport.service_name transport.permit_without_stream transport.mode transport.domain_strategy
            transport.x_padding_bytes transport.no_grpc_header transport.no_sse_header transport.sc_max_each_post_bytes
            transport.sc_min_posts_interval_ms transport.sc_max_buffered_posts transport.sc_stream_up_server_secs
            transport.server_max_header_bytes transport.trusted_x_forwarded_for transport.x_padding_obfs_mode
            transport.x_padding_key transport.x_padding_header transport.x_padding_placement transport.x_padding_method
            transport.uplink_http_method transport.session_placement transport.session_key transport.seq_placement
            transport.seq_key transport.uplink_data_placement transport.uplink_data_key transport.uplink_chunk_size
            transport.session_id_table transport.session_id_length transport.congestion_controller transport.cwnd
            transport.download transport.mtu transport.tti transport.uplink_capacity transport.downlink_capacity
            transport.congestion transport.read_buffer_size transport.write_buffer_size transport.header_type transport.seed
        """,
            )
        val multiplex =
            paths(
                """
            multiplex.enabled multiplex.protocol multiplex.max_connections multiplex.min_streams multiplex.max_streams
            multiplex.padding multiplex.brutal.enabled multiplex.brutal.up_mbps multiplex.brutal.down_mbps
            transport.xmux transport.xmux.max_concurrency transport.xmux.max_connections
            transport.xmux.c_max_reuse_times transport.xmux.h_max_request_times transport.xmux.h_max_reusable_secs
            transport.xmux.h_keep_alive_period
        """,
            )
        val protocolFields =
            mapOf(
                "vless" to paths("uuid flow encryption network packet_encoding tag"),
                "hysteria" to
                    paths(
                        "server_ports hop_interval up up_mbps down down_mbps auth auth_str obfs recv_window_conn recv_window disable_mtu_discovery network tag",
                    ),
                "hysteria2" to
                    paths(
                        "server_ports hop_interval hop_interval_max up_mbps down_mbps password network bbr_profile brutal_debug disable_chrome_parrot obfs obfs.type obfs.password obfs.min_packet_size obfs.max_packet_size realm realm.server_url realm.token realm.realm_id realm.stun_servers realm.ip_version realm.port_mapping realm.port_mapping.enabled realm.port_mapping.timeout realm.port_mapping.lifetime realm.http_client tag",
                    ),
                "anytls" to
                    paths("password idle_session_check_interval idle_session_timeout min_idle_session disable_reuse client_metadata tag"),
                "naive" to
                    paths(
                        "username password insecure_concurrency extra_headers stream_receive_window udp_over_tcp.enabled udp_over_tcp.version quic quic_congestion_control quic_session_receive_window tag",
                    ),
                "snell" to paths("psk version reuse network obfs_mode obfs_host mode userkey tag"),
                "wireguard" to
                    paths(
                        "address private_key system name listen_port mtu udp_timeout udp_mapping udp_filtering udp_nat_max workers preallocated_buffers_per_pool disable_pauses peers peers.0.address peers.0.port peers.0.public_key peers.0.pre_shared_key peers.0.allowed_ips peers.0.persistent_keepalive_interval amnezia amnezia.jc amnezia.jmin amnezia.jmax amnezia.s1 amnezia.s2 amnezia.s3 amnezia.s4 amnezia.h1 amnezia.h2 amnezia.h3 amnezia.h4 amnezia.content_padding_addition amnezia.rekey_after_time amnezia.rekey_timeout amnezia.reject_after_time amnezia.keepalive_timeout amnezia.max_handshake_attempts amnezia.i1 amnezia.i2 amnezia.i3 amnezia.i4 amnezia.i5 amnezia.header_protection_key amnezia.random_trailers amnezia.disable_cookies",
                    ),
                "mieru" to paths("server_ports transport username password multiplexing traffic_pattern mtu handshake_mode tag"),
                "trusttunnel" to
                    paths(
                        "username password network health_check quic congestion_controller cwnd tag multiplex.enabled multiplex.max_connections multiplex.min_streams multiplex.max_streams",
                    ),
            )
        protocolFields.forEach { (type, expected) ->
            val actual = configFieldSections(type).flatMap { it.fields }.map(ConfigFieldDescriptor::path).toSet()
            assertTrue(actual.containsAll(expected), "$type is missing protocol fields: ${expected - actual}")
            if (type in setOf("vless", "hysteria", "hysteria2", "anytls", "naive", "trusttunnel")) {
                val expectedTls =
                    if (type ==
                        "naive"
                    ) {
                        paths(
                            "tls.enabled tls.server_name",
                        )
                    } else {
                        tls
                    }
                assertTrue(actual.containsAll(expectedTls), "$type is missing TLS fields")
            }
            if (type == "vless") assertTrue(actual.containsAll(multiplex), "$type is missing multiplex fields")
            if (type == "trusttunnel") {
                val trustMultiplex = paths("multiplex.enabled multiplex.max_connections multiplex.min_streams multiplex.max_streams")
                assertTrue(actual.containsAll(trustMultiplex), "$type is missing custom multiplex fields")
            }
        }
        assertTrue(
            configFieldSections("vless")
                .flatMap { it.fields }
                .map(ConfigFieldDescriptor::path)
                .toSet()
                .containsAll(transport),
        )
        assertTrue(
            configFieldSections("vmess")
                .flatMap { it.fields }
                .map(ConfigFieldDescriptor::path)
                .toSet()
                .containsAll(transport),
        )
        assertTrue(
            configFieldSections("trojan")
                .flatMap { it.fields }
                .map(ConfigFieldDescriptor::path)
                .toSet()
                .containsAll(transport),
        )
    }

    @Test
    fun `xhttp choices only expose values valid for the selected mode`() {
        val base = Json.parseToJsonElement("""{"type":"vless","transport":{"type":"xhttp","mode":"auto"}}""").jsonObject
        val method = field("vless", listOf("transport", "uplink_http_method"))
        val placement = field("vless", listOf("transport", "uplink_data_placement"))

        assertEquals(listOf("POST"), configFieldChoices(base, method))
        assertEquals(listOf("auto", "body"), configFieldChoices(base, placement))

        val packetUp = base.edit("vless", listOf("transport", "mode"), "packet-up")
        assertEquals(listOf("POST", "GET"), configFieldChoices(packetUp, method))
        assertEquals(listOf("auto", "body", "header", "cookie"), configFieldChoices(packetUp, placement))
        assertEquals(ConfigFieldKind.CHOICE, field("vless", listOf("transport", "x_padding_placement")).kind)
        assertEquals(ConfigFieldKind.CHOICE, field("vless", listOf("transport", "x_padding_method")).kind)
    }

    @Test
    fun `protocol default hints and required fields match core options`() {
        val config = Json.parseToJsonElement("""{"server":"vpn.example"}""").jsonObject
        assertEquals("vpn.example", configFieldDefaultValue(config, field("vless", listOf("tls", "server_name"))))
        assertEquals("tcp,udp", field("hysteria", listOf("network")).defaultValue)
        assertEquals("30s", field("hysteria2", listOf("hop_interval")).defaultValue)
        assertEquals("512", field("hysteria2", listOf("obfs", "min_packet_size")).defaultValue)
        assertEquals("1200", field("hysteria2", listOf("obfs", "max_packet_size")).defaultValue)
        assertTrue(field("hysteria2", listOf("obfs", "password")).required)
        assertNull(field("hysteria2", listOf("bbr_profile")).defaultValue)
        assertNull(field("hysteria2", listOf("tls", "enabled")).defaultValue)
        assertEquals("1408", field("wireguard", listOf("mtu")).defaultValue)
        assertTrue(field("wireguard", listOf("peers", "0", "allowed_ips")).required)
    }

    @Test
    fun `JSON fields reject malformed drafts and object toggles add and remove optional objects`() {
        val original = Json.parseToJsonElement("""{"type":"naive"}""").jsonObject
        val field = field("naive", listOf("extra_headers"))
        val updated = updateConfigField(original, field, """{"X-Test":"yes"}""")
        assertEquals(Json.parseToJsonElement("""{"type":"naive","extra_headers":{"X-Test":"yes"}}"""), updated)
        assertEquals(updated, updateConfigField(updated, field, "{"))

        val wireguard = Json.parseToJsonElement("""{"type":"wireguard"}""").jsonObject
        val amnezia = field("wireguard", listOf("amnezia"))
        val enabled = updateConfigField(wireguard, amnezia, "true")
        assertTrue(configFieldVisible(enabled, field("wireguard", listOf("amnezia", "jc"))))
        assertEquals(wireguard, updateConfigField(enabled, amnezia, "false"))
    }

    @Test
    fun `naive legacy udp over tcp boolean remains editable as an object`() {
        val original = Json.parseToJsonElement("""{"type":"naive","udp_over_tcp":true}""").jsonObject
        val enabled = field("naive", listOf("udp_over_tcp", "enabled"))
        val version = field("naive", listOf("udp_over_tcp", "version"))

        assertEquals("true", configFieldValue(original, enabled))
        assertTrue(configFieldVisible(original, version))
        assertEquals(
            Json.parseToJsonElement("""{"type":"naive","udp_over_tcp":{"enabled":true,"version":2}}"""),
            updateConfigField(original, version, "2"),
        )
    }

    @Test
    fun `trusttunnel form edits its custom multiplex fields and preserves unknown data`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"trusttunnel","server":"tt.example","server_port":443,"tls":{"enabled":true},"future":true}""",
                ).jsonObject

        val updated =
            original
                .edit("trusttunnel", listOf("network"), "tcp")
                .edit("trusttunnel", listOf("multiplex", "enabled"), "true")
                .edit("trusttunnel", listOf("multiplex", "max_streams"), "24")

        assertEquals(
            Json.parseToJsonElement(
                """{"type":"trusttunnel","server":"tt.example","server_port":443,"tls":{"enabled":true},"future":true,"network":["tcp"],"multiplex":{"enabled":true,"max_streams":24}}""",
            ),
            updated,
        )
    }

    @Test
    fun `clearing an absent nested choice does not create empty json`() {
        val original =
            Json
                .parseToJsonElement(
                    """{"type":"hysteria2","server":"hy2.example","server_port":443,"password":"secret"}""",
                ).jsonObject

        val updated = original.edit("hysteria2", listOf("obfs", "type"), "")

        assertEquals(original, updated)
    }

    @Test
    fun `unknown outbound still gets basic fields`() {
        val sections = configFieldSections("future-protocol")
        assertEquals(listOf("server", "server_port"), sections.single().fields.map { it.path.single() })
    }

    private fun paths(value: String): Set<List<String>> =
        value
            .trimIndent()
            .split(Regex("\\s+"))
            .filter(String::isNotBlank)
            .map { it.split('.') }
            .toSet()

    private fun JsonObject.edit(
        type: String,
        path: List<String>,
        value: String,
    ): JsonObject = updateConfigField(this, field(type, path), value)

    private fun field(
        type: String,
        path: List<String>,
    ): ConfigFieldDescriptor = configFieldSections(type).flatMap { it.fields }.single { it.path == path }
}
