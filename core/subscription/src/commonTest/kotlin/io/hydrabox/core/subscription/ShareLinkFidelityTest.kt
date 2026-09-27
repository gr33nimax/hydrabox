package io.hydrabox.core.subscription

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The shapes real providers hand out. Each case here is a link that the alpha accepted and
 * turned into an outbound that dials the right host and is refused by it — which is the
 * failure that looks least like a parsing bug from the outside.
 */
class ShareLinkFidelityTest {
    private fun JsonObject.text(key: String) = this[key]?.jsonPrimitive?.contentOrNull

    private fun urlEncode(value: String): String {
        val hex = "0123456789ABCDEF"
        return value.encodeToByteArray().joinToString("") { byte ->
            val code = byte.toInt() and 0xff
            if (code in 'a'.code..'z'.code || code in 'A'.code..'Z'.code || code in '0'.code..'9'.code ||
                code == '-'.code || code == '_'.code || code == '.'.code || code == '~'.code
            ) {
                code.toChar().toString()
            } else {
                "%${hex[code shr 4]}${hex[code and 15]}"
            }
        }
    }

    @OptIn(ExperimentalEncodingApi::class)
    private fun vmessLink(document: String) = "vmess://" + Base64.Default.encode(document.encodeToByteArray())

    @Test fun `a vmess link over websocket keeps its transport and TLS name`() {
        val link =
            vmessLink(
                """
                {"v":"2","ps":"WS node","add":"edge.example","port":"443","id":"6f1a2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
                 "aid":"4","scy":"zero","net":"ws","type":"none","host":"edge.example","path":"/ray?ed=2048",
                 "tls":"tls","sni":"edge.example","alpn":"h2,http/1.1","fp":"chrome"}
                """.trimIndent(),
            )
        val parsed = assertIs<ShareLink.Proxy>(SubscriptionParser.parse(link))
        assertEquals("vmess", parsed.type)
        assertEquals("WS node", parsed.name)
        assertTrue(parsed.tls)
        val outbound = ShareLinkOutbound.toJson(parsed, "tag")
        val transport = assertIs<JsonObject>(outbound["transport"])
        assertEquals("ws", transport.text("type"))
        assertEquals("/ray", transport.text("path"))
        assertEquals(2048, transport["max_early_data"]?.jsonPrimitive?.contentOrNull?.toInt())
        assertEquals("edge.example", transport["headers"]?.jsonObject?.text("Host"))
        val tls = assertIs<JsonObject>(outbound["tls"])
        assertEquals("edge.example", tls.text("server_name"))
        assertEquals(listOf("h2", "http/1.1"), tls["alpn"]?.jsonArray?.map { it.jsonPrimitive.content })
        assertEquals("chrome", tls["utls"]?.jsonObject?.text("fingerprint"))
        // The cipher and the alternative id are part of the server's identity.
        assertEquals("zero", outbound.text("security"))
        assertEquals(4, outbound["alter_id"]?.jsonPrimitive?.contentOrNull?.toInt())
    }

    @Test fun `a vmess link over grpc names the service`() {
        val link =
            vmessLink(
                """{"ps":"gRPC","add":"grpc.example","port":"443","id":"id","net":"grpc","path":"chat","tls":"tls"}""",
            )
        val outbound = ShareLinkOutbound.toJson(SubscriptionParser.parse(link), "tag")
        val transport = assertIs<JsonObject>(outbound["transport"])
        assertEquals("grpc", transport.text("type"))
        assertEquals("chat", transport.text("service_name"))
    }

    @OptIn(ExperimentalEncodingApi::class)
    @Test
    fun `a SIP002 shadowsocks link decodes its method and password`() {
        val userInfo = Base64.Default.encode("aes-256-gcm:hunter2".encodeToByteArray())
        val parsed = assertIs<ShareLink.Proxy>(SubscriptionParser.parse("ss://$userInfo@ss.example:8388#Node"))
        val outbound = ShareLinkOutbound.toJson(parsed, "tag")
        assertEquals("aes-256-gcm", outbound.text("method"))
        assertEquals("hunter2", outbound.text("password"))
        assertEquals("ss.example", outbound.text("server"))
    }

    @OptIn(ExperimentalEncodingApi::class)
    @Test
    fun `a legacy shadowsocks link with the whole body encoded is accepted`() {
        val body = Base64.Default.encode("chacha20-ietf-poly1305:secret@old.example:1234".encodeToByteArray())
        val outbound = ShareLinkOutbound.toJson(SubscriptionParser.parse("ss://$body#Old"), "tag")
        assertEquals("chacha20-ietf-poly1305", outbound.text("method"))
        assertEquals("old.example", outbound.text("server"))
        assertEquals(1234, outbound["server_port"]?.jsonPrimitive?.contentOrNull?.toInt())
    }

    @Test fun `a shadowsocks plugin travels with its options`() {
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse("ss://method:pass@ss.example:8388?plugin=obfs-local;obfs=http#Node"),
                "tag",
            )
        assertEquals("obfs-local", outbound.text("plugin"))
        assertEquals("obfs=http", outbound.text("plugin_opts"))
    }

    @Test fun `a vless link over xhttp keeps the mode the provider asked for`() {
        val parsed =
            SubscriptionParser.parse(
                "vless://6f1a2b3c-4d5e-6f70-8192-a3b4c5d6e7f8@x.example:443" +
                    "?encryption=none&security=tls&sni=x.example&alpn=h2&fp=edge&type=xhttp&host=x.example" +
                    "&path=%2Fxhttp&mode=stream-up#XHTTP",
            )
        val outbound = ShareLinkOutbound.toJson(parsed, "tag")
        val transport = assertIs<JsonObject>(outbound["transport"])
        assertEquals("xhttp", transport.text("type"))
        assertEquals("stream-up", transport.text("mode"))
        assertEquals("/xhttp", transport.text("path"))
        assertEquals("x.example", assertIs<JsonObject>(outbound["tls"]).text("server_name"))
        // A provider that is not Hydra sends a plain `type=xhttp` link with no `extra`, and
        // the core refuses a document whose xhttp transport names no padding range — one
        // such link took the tunnel and every other subscription's servers down with it.
        // The core's own runtime default range is written out so the document decodes.
        assertEquals("100-1000", transport.text("x_padding_bytes"))
    }

    @Test fun `a real xhttp link matches the working transport contract`() {
        val extra =
            """{"sessionIDPlacement":"header","sessionIDKey":"X-Upload-Token","sessionIDTable":"Base62","sessionIDLength":"16-32","noGRPCHeader":false,"xmux":{"maxConnections":"0","cMaxReuseTimes":"1000","hMaxReusableSecs":"100","maxConcurrency":"16-32","hMaxRequestTimes":"600-900"},"futureField":true}"""
        val parsed =
            SubscriptionParser.parse(
                "vless://id@x.example:443?type=xhttp&mode=stream-up" +
                    "&path=%2Fapi%2Fmedia%2Fsession%2F&extra=${urlEncode(extra)}",
            )
        val transport = assertIs<JsonObject>(ShareLinkOutbound.toJson(parsed, "tag")["transport"])
        val expected =
            Json
                .parseToJsonElement(
                    """{"type":"xhttp","mode":"stream-up","path":"/api/media/session","x_padding_bytes":"100-1000","no_grpc_header":false,"session_placement":"header","session_key":"X-Upload-Token","session_id_table":"Base62","session_id_length":"16-32","xmux":{"max_connections":0,"c_max_reuse_times":1000,"h_max_reusable_secs":100,"max_concurrency":"16-32","h_max_request_times":"600-900"}}""",
                ).jsonObject
        assertEquals(expected, transport)
        val xmux = assertIs<JsonObject>(transport["xmux"])
        listOf("max_connections", "c_max_reuse_times", "h_max_reusable_secs").forEach { key ->
            assertEquals(false, xmux.getValue(key).jsonPrimitive.isString)
        }
        assertNull(transport["session_id_placement"])
        assertNull(transport["session_id_key"])
        assertNull(transport["sc_max_buffered_posts"])
        assertNull(transport["future_field"])
    }

    @Test fun `a real vless xhttp link uses every exact hydracore extra key`() {
        val extra =
            """{"xPaddingBytes":"500-2000","headers":{"X-Trace":"enabled"},"domainStrategy":"prefer_ipv4","noGRPCHeader":true,"noSSEHeader":true,"scMaxEachPostBytes":"1000000-2000000","scMinPostsIntervalMs":"30-60","scMaxBufferedPosts":12,"scStreamUpServerSecs":"30-120","serverMaxHeaderBytes":8192,"trustedXForwardedFor":["127.0.0.1"],"xPaddingObfsMode":true,"xPaddingKey":"x_padding","xPaddingHeader":"X-Padding","xPaddingPlacement":"queryInHeader","xPaddingMethod":"repeat-x","uplinkHTTPMethod":"POST","sessionPlacement":"cookie","sessionKey":"x_session","seqPlacement":"header","seqKey":"X-Seq","uplinkDataPlacement":"auto","uplinkDataKey":"X-Data","uplinkChunkSize":"64-128","sessionIDTable":"ABCDEFGHIJKLMNOPQRSTUVWXYZ","sessionIDLength":"16-32","congestionController":"bbr","cwnd":16,"xmux":{"maxConcurrency":"0-0","maxConnections":"2-4","cMaxReuseTimes":"2-4","hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000","hKeepAlivePeriod":30},"download":{"server":"dl.example","server_port":443,"detour":"direct","tls":{"enabled":true,"server_name":"dl.example"}}}"""
        val parsed =
            SubscriptionParser.parse(
                "vless://6f1a2b3c-4d5e-6f70-8192-a3b4c5d6e7f8@x.example:443" +
                    "?security=tls&type=xhttp&mode=stream-up&host=x.example&path=%2Fxhttp&tfo=true" +
                    "&encryption=mlkem768x25519plus.native.1rtt.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&flow=" +
                    "&extra=${urlEncode(extra)}#XHTTP",
            )
        val outbound = ShareLinkOutbound.toJson(parsed, "tag")
        assertEquals("mlkem768x25519plus.native.1rtt.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", outbound.text("encryption"))
        assertEquals(true, outbound["tcp_fast_open"]?.jsonPrimitive?.booleanOrNull)
        assertNull(outbound["flow"])
        val transport = assertIs<JsonObject>(outbound["transport"])
        assertEquals("xhttp", transport.text("type"))
        assertEquals("stream-up", transport.text("mode"))
        assertEquals("500-2000", transport.text("x_padding_bytes"))
        assertEquals("POST", transport.text("uplink_http_method"))
        assertEquals("16-32", transport.text("session_id_length"))
        assertEquals("ABCDEFGHIJKLMNOPQRSTUVWXYZ", transport.text("session_id_table"))
        assertEquals("cookie", transport.text("session_placement"))
        assertEquals("header", transport.text("seq_placement"))
        assertEquals("2-4", transport["xmux"]?.jsonObject?.text("c_max_reuse_times"))
        assertEquals("0-0", transport["xmux"]?.jsonObject?.text("max_concurrency"))
        assertEquals("2-4", transport["xmux"]?.jsonObject?.text("max_connections"))
        assertEquals("600-900", transport["xmux"]?.jsonObject?.text("h_max_request_times"))
        assertEquals("1800-3000", transport["xmux"]?.jsonObject?.text("h_max_reusable_secs"))
        assertEquals("30", transport["xmux"]?.jsonObject?.text("h_keep_alive_period"))
        assertTrue("headers" in transport)
        assertTrue("domain_strategy" in transport)
        assertTrue("no_grpc_header" in transport)
        assertTrue("no_sse_header" in transport)
        assertTrue("sc_max_each_post_bytes" in transport)
        assertTrue("sc_min_posts_interval_ms" in transport)
        assertTrue("sc_max_buffered_posts" in transport)
        assertTrue("sc_stream_up_server_secs" in transport)
        assertTrue("server_max_header_bytes" in transport)
        assertTrue("trusted_x_forwarded_for" in transport)
        assertTrue("x_padding_obfs_mode" in transport)
        assertTrue("x_padding_key" in transport)
        assertTrue("x_padding_header" in transport)
        assertTrue("x_padding_placement" in transport)
        assertTrue("x_padding_method" in transport)
        assertTrue("session_key" in transport)
        assertTrue("seq_key" in transport)
        assertTrue("uplink_data_placement" in transport)
        assertTrue("uplink_data_key" in transport)
        assertTrue("uplink_chunk_size" in transport)
        assertTrue("congestion_controller" in transport)
        assertTrue("cwnd" in transport)
        assertTrue("download" in transport)
        assertNull(transport["uplink_httpmethod"])
        assertNull(transport["session_idlength"])
        assertNull(transport["xPaddingBytes"])
    }

    @OptIn(ExperimentalEncodingApi::class)
    @Test
    fun `base64url xhttp extra is decoded and nested keys are mapped`() {
        val extra =
            """{"xPaddingBytes":"500-2000","uplinkHTTPMethod":"POST","xmux":{"maxConcurrency":"0-0"},"download":{"server":"dl.example","serverPort":443,"detour":"direct","xPaddingBytes":"100-1000","tls":{"enabled":true,"serverName":"dl.example"}}}"""
        val encodedExtra = Base64.UrlSafe.encode(extra.encodeToByteArray()).trimEnd('=')
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse(
                    "vless://id@x.example:443?type=xhttp&security=tls&extra=$encodedExtra",
                ),
                "tag",
            )
        val transport = assertIs<JsonObject>(outbound["transport"])
        assertEquals("500-2000", transport.text("x_padding_bytes"))
        assertEquals("POST", transport.text("uplink_http_method"))
        assertEquals("0-0", transport["xmux"]?.jsonObject?.text("max_concurrency"))
        val download = assertIs<JsonObject>(transport["download"])
        assertEquals("443", download.text("server_port"))
        assertEquals("100-1000", download.text("x_padding_bytes"))
        assertEquals("dl.example", download["tls"]?.jsonObject?.text("server_name"))
    }

    @Test fun `a trojan grpc link keeps the core transport and TLS keys`() {
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse(
                    "trojan://secret@t.example:443?type=grpc&grpc-service-name=trojan-rpc&sni=front.example&alpn=h2#Trojan",
                ),
                "tag",
            )
        assertEquals("secret", outbound.text("password"))
        assertEquals("front.example", assertIs<JsonObject>(outbound["tls"]).text("server_name"))
        val transport = assertIs<JsonObject>(outbound["transport"])
        assertEquals("grpc", transport.text("type"))
        assertEquals("trojan-rpc", transport.text("service_name"))
    }

    @Test fun `an ssr link keeps method protocol and both obfuscation parameters`() {
        val password = Base64.Default.encode("ssr-pass".encodeToByteArray())
        val document =
            "ssr.example:8443:auth_sha1_v4:aes-128-ctr:tls1.2_ticket_auth:$password" +
                "/?obfsparam=${Base64.Default.encode("cdn.example".encodeToByteArray())}" +
                "&protoparam=${Base64.Default.encode("account".encodeToByteArray())}"
        val link = "ssr://${Base64.Default.encode(document.encodeToByteArray())}"
        val outbound = ShareLinkOutbound.toJson(SubscriptionParser.parse(link), "tag")
        assertEquals("shadowsocksr", outbound.text("type"))
        assertEquals("aes-128-ctr", outbound.text("method"))
        assertEquals("ssr-pass", outbound.text("password"))
        assertEquals("auth_sha1_v4", outbound.text("protocol"))
        assertEquals("tls1.2_ticket_auth", outbound.text("obfs"))
        assertEquals("cdn.example", outbound.text("obfs_param"))
        assertEquals("account", outbound.text("protocol_param"))
    }

    @Test fun `hysteria links use their exact auth speed and obfs keys`() {
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse(
                    "hysteria://h.example:443?auth=secret&peer=front.example&up=100%20Mbps&down_mbps=200" +
                        "&obfsParam=obfs-secret&insecure=true#Hysteria",
                ),
                "tag",
            )
        assertEquals("secret", outbound.text("auth_str"))
        assertEquals("100 Mbps", outbound.text("up"))
        assertEquals("200", outbound.text("down_mbps"))
        assertEquals("obfs-secret", outbound.text("obfs"))
        val tls = assertIs<JsonObject>(outbound["tls"])
        assertEquals("front.example", tls.text("server_name"))
        assertEquals(true, tls["insecure"]?.jsonPrimitive?.booleanOrNull)
    }

    @Test fun `hysteria2 links keep password bandwidth obfs and SNI`() {
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse(
                    "hy2://secret@hy2.example:443?up=30&down=80&obfs=salamander&obfs-password=cloak" +
                        "&sni=front.example&insecure=1#Hy2",
                ),
                "tag",
            )
        assertEquals("secret", outbound.text("password"))
        assertEquals("30", outbound.text("up_mbps"))
        assertEquals("80", outbound.text("down_mbps"))
        val obfs = assertIs<JsonObject>(outbound["obfs"])
        assertEquals("salamander", obfs.text("type"))
        assertEquals("cloak", obfs.text("password"))
        val tls = assertIs<JsonObject>(outbound["tls"])
        assertEquals("front.example", tls.text("server_name"))
        assertEquals(true, tls["insecure"]?.jsonPrimitive?.booleanOrNull)
    }

    @Test fun `tuic links keep UUID password and protocol settings`() {
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse(
                    "tuic://uuid-123:secret@tuic.example:443?congestion_control=bbr&udp_relay_mode=native" +
                        "&zero_rtt_handshake=true&heartbeat_interval=10s&sni=front.example&disable_sni=true#TUIC",
                ),
                "tag",
            )
        assertEquals("uuid-123", outbound.text("uuid"))
        assertEquals("secret", outbound.text("password"))
        assertEquals("bbr", outbound.text("congestion_control"))
        assertEquals("native", outbound.text("udp_relay_mode"))
        assertEquals(true, outbound["zero_rtt_handshake"]?.jsonPrimitive?.booleanOrNull)
        assertEquals("10s", outbound.text("heartbeat"))
        val tls = assertIs<JsonObject>(outbound["tls"])
        assertEquals("front.example", tls.text("server_name"))
        assertEquals(true, tls["disable_sni"]?.jsonPrimitive?.booleanOrNull)
    }

    @Test fun `anytls omits TLS and TFO options rejected by the core`() {
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse(
                    "anytls://secret@any.example:443?sni=front.example&tfo=true&insecure=1&alpn=h2&fp=chrome#AnyTLS",
                ),
                "tag",
            )
        assertEquals("secret", outbound.text("password"))
        assertNull(outbound["tcp_fast_open"])
        val tls = assertIs<JsonObject>(outbound["tls"])
        assertEquals("front.example", tls.text("server_name"))
        assertNull(tls["insecure"])
        assertNull(tls["alpn"])
        assertNull(tls["utls"])
    }

    @Test fun `socks4a links preserve the requested core protocol version`() {
        val outbound = ShareLinkOutbound.toJson(SubscriptionParser.parse("socks4a://user:pass@s.example:1080#SOCKS"), "tag")
        assertEquals("socks", outbound.text("type"))
        assertEquals("4a", outbound.text("version"))
        assertEquals("user", outbound.text("username"))
        assertEquals("pass", outbound.text("password"))
    }

    @Test fun `naive quic scheme enables both QUIC and TLS`() {
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse("naive+quic://user:pass@n.example:443?insecure=1&alpn=h3&fp=chrome#Naive"),
                "tag",
            )
        assertEquals("user", outbound.text("username"))
        assertEquals("pass", outbound.text("password"))
        assertEquals(true, outbound["quic"]?.jsonPrimitive?.booleanOrNull)
        val tls = assertIs<JsonObject>(outbound["tls"])
        assertEquals(true, tls["enabled"]?.jsonPrimitive?.booleanOrNull)
        assertNull(tls["insecure"])
        assertNull(tls["alpn"])
        assertNull(tls["utls"])
    }

    @Test fun `https proxy links become HTTP outbounds with TLS`() {
        val outbound =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse("https://user:pass@proxy.example:443?sni=front.example#HTTPS"),
                "tag",
            )
        assertEquals("http", outbound.text("type"))
        assertEquals("user", outbound.text("username"))
        assertEquals("pass", outbound.text("password"))
        assertEquals("front.example", assertIs<JsonObject>(outbound["tls"]).text("server_name"))
    }

    @Test fun `httpupgrade and mkcp transports are mapped`() {
        val upgrade =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse("vless://id@u.example:443?type=httpupgrade&path=%2Fup&host=u.example"),
                "tag",
            )
        assertEquals("httpupgrade", assertIs<JsonObject>(upgrade["transport"]).text("type"))
        val kcp =
            ShareLinkOutbound.toJson(
                SubscriptionParser.parse("vless://id@k.example:443?type=kcp&headerType=wireguard&seed=abc"),
                "tag",
            )
        assertEquals("mkcp", assertIs<JsonObject>(kcp["transport"]).text("type"))
    }

    @Test fun `an AmneziaWG link becomes an endpoint with its obfuscation intact`() {
        val parsed =
            assertIs<ShareLink.WireGuard>(
                SubscriptionParser.parse(
                    "wg://31.77.203.66:52017?private_key=cHJpdmF0ZQ%3D%3D&public_key=cHVibGlj" +
                        "&local_address=10.67.67.3/32&enable_amnezia=true&jc=2&jmin=27&jmax=39" +
                        "&s1=9&s2=6&h1=1945982327&h2=1210256333&h3=125101821&h4=375691454#AWG",
                ),
            )
        assertEquals(52017, parsed.port)
        assertEquals(listOf("10.67.67.3/32"), parsed.localAddresses)
        assertTrue(ShareLinkOutbound.isEndpoint(parsed))
        val endpoint = ShareLinkOutbound.toJson(parsed, "awg")
        assertEquals("wireguard", endpoint.text("type"))
        assertEquals(listOf("10.67.67.3/32"), endpoint["address"]?.jsonArray?.map { it.jsonPrimitive.content })
        val peer = assertIs<JsonArray>(endpoint["peers"]).first().jsonObject
        assertEquals("31.77.203.66", peer.text("address"))
        assertEquals(listOf("0.0.0.0/0", "::/0"), peer["allowed_ips"]?.jsonArray?.map { it.jsonPrimitive.content })
        val amnezia = assertIs<JsonObject>(endpoint["amnezia"])
        assertEquals(2, amnezia["jc"]?.jsonPrimitive?.contentOrNull?.toInt())
        assertEquals(1945982327, amnezia["h1"]?.jsonPrimitive?.contentOrNull?.toLong())
        // A peer never appears as an outbound: the core would refuse the whole document.
        assertNull(endpoint["server"])
    }

    @Test fun `a wireguard link without a peer key is refused rather than half-built`() {
        kotlin.test.assertFails { SubscriptionParser.parse("wg://host.example:51820?private_key=cA%3D%3D") }
    }

    @Test fun `an AmneziaWG 3_1 link keeps the generation fields`() {
        val parsed =
            assertIs<ShareLink.WireGuard>(
                SubscriptionParser.parse(
                    "wg://31.77.203.66:52017?private_key=cHJpdmF0ZQ%3D%3D&public_key=cHVibGlj" +
                        "&local_address=10.67.67.3/32&enable_amnezia=true&jc=2&jmin=27&jmax=39" +
                        "&s1=12&s2=12&h1=1&h2=2&h3=3&h4=4" +
                        "&i1=%3Cb%200xc70000000108%3E&header_protection_key=QUJD" +
                        "&content_padding_addition=50-100&rekey_after_time=100-140" +
                        "&max_handshake_attempts=15-20&random_trailers=true&disable_cookies=false#AWG3",
                ),
            )
        val amnezia = assertIs<JsonObject>(ShareLinkOutbound.toJson(parsed, "awg31")["amnezia"])
        assertEquals("2", amnezia["jc"]?.jsonPrimitive?.contentOrNull)
        assertEquals("1", amnezia["h1"]?.jsonPrimitive?.contentOrNull)
        assertEquals("<b 0xc70000000108>", amnezia["i1"]?.jsonPrimitive?.contentOrNull)
        assertEquals("QUJD", amnezia["header_protection_key"]?.jsonPrimitive?.contentOrNull)
        assertEquals("50-100", amnezia["content_padding_addition"]?.jsonPrimitive?.contentOrNull)
        assertEquals("100-140", amnezia["rekey_after_time"]?.jsonPrimitive?.contentOrNull)
        assertEquals("15-20", amnezia["max_handshake_attempts"]?.jsonPrimitive?.contentOrNull)
        assertEquals(true, amnezia["random_trailers"]?.jsonPrimitive?.booleanOrNull)
        assertEquals(false, amnezia["disable_cookies"]?.jsonPrimitive?.booleanOrNull)
    }

    @Test fun `a snell link becomes an outbound with its generation and obfuscation`() {
        val parsed =
            assertIs<ShareLink.Proxy>(
                SubscriptionParser.parse(
                    "snell://super-secret-psk@snell.example:32489" +
                        "?version=4&obfs-mode=http&obfs-host=cdn.example&udp-relay=true#Snell",
                ),
            )
        assertEquals("snell", parsed.type)

        val outbound = ShareLinkOutbound.toJson(parsed, "tag")
        assertEquals("snell", outbound.text("type"))
        assertEquals("snell.example", outbound.text("server"))
        assertEquals("32489", outbound.text("server_port"))
        assertEquals("super-secret-psk", outbound.text("psk"))
        assertEquals("4", outbound.text("version"))
        assertEquals("http", outbound.text("obfs_mode"))
        assertEquals("cdn.example", outbound.text("obfs_host"))
        assertEquals(listOf("tcp", "udp"), outbound["network"]?.jsonArray?.map { it.jsonPrimitive.content })
        assertNull(outbound.text("password"))
    }

    @Test fun `a sixth-generation snell link carries its mode and no obfuscation`() {
        val parsed =
            assertIs<ShareLink.Proxy>(
                SubscriptionParser.parse("snell://another-psk@snell.example:32489?version=6&mode=unshaped#Snell"),
            )

        val outbound = ShareLinkOutbound.toJson(parsed, "tag")
        assertEquals("6", outbound.text("version"))
        assertEquals("unshaped", outbound.text("mode"))
        assertNull(outbound.text("obfs_mode"))
        assertNull(outbound.text("obfs_host"))
    }
}
