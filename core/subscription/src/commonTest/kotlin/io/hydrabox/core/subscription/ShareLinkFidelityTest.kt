package io.hydrabox.core.subscription

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

    @Test fun `the xhttp extras arrive under the names the core reads`() {
        val extra = """{"scStreamUpServerSecs":"30-120","xPaddingBytes":"500-2000","xmux":{"maxConcurrency":"16-32"}}"""
        val parsed =
            SubscriptionParser.parse(
                "vless://id@x.example:443?security=tls&type=xhttp&mode=stream-up&path=%2Fxhttp" +
                    "&extra=" + extra.replace("{", "%7B").replace("}", "%7D").replace("\"", "%22"),
            )
        val transport = assertIs<JsonObject>(ShareLinkOutbound.toJson(parsed, "tag")["transport"])
        // Copied verbatim, the core sees no padding range and refuses the whole document with
        // "x_padding_bytes cannot be disabled" — which takes every other server down with it.
        assertEquals("500-2000", transport.text("x_padding_bytes"))
        assertEquals("30-120", transport.text("sc_stream_up_server_secs"))
        assertEquals("16-32", transport["xmux"]?.jsonObject?.text("max_concurrency"))
        assertNull(transport["xPaddingBytes"])
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
