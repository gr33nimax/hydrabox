package io.hydrabox.core.subscription

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

class SubscriptionTest {
    @Test fun `parses VLESS and Trojan share links`() {
        val vless = assertIs<ShareLink.Vless>(SubscriptionParser.parse("vless://7c6a5b3e-4f1a-4d2b-8c9e-1a2b3c4d5e6f@server.com:443?security=tls#My%20Server"))
        assertEquals("server.com", vless.server); assertEquals(443, vless.port); assertEquals("My Server", vless.name)
        val trojan = assertIs<ShareLink.Trojan>(SubscriptionParser.parse("trojan://password@trojan.server.com:443?security=tls#Trojan%20Node"))
        assertEquals("trojan.server.com", trojan.server); assertEquals(443, trojan.port); assertEquals("Trojan Node", trojan.name)
    }

    @Test fun `rejects malformed and unsupported subscription links`() {
        kotlin.test.assertFails { SubscriptionParser.parse("vless://missing-port") }
        kotlin.test.assertFails { SubscriptionParser.parse("unknown://server.example:443") }
    }

    @Test fun `parses SOCKS and HTTP proxy links`() {
        val socks = assertIs<ShareLink.Proxy>(SubscriptionParser.parse("socks5://user:p%40ss@socks.server.com:1080#SOCKS%20Node"))
        assertEquals("socks", socks.type); assertEquals("socks.server.com", socks.server); assertEquals(1080, socks.port); assertEquals(false, socks.tls)
        val http = assertIs<ShareLink.Proxy>(SubscriptionParser.parse("https://secure.proxy.com:443#HTTPS%20Proxy"))
        assertEquals("http", http.type); assertEquals(true, http.tls); assertEquals("HTTPS Proxy", http.name)
    }

    @Test fun `imports each link in a raw subscription body`() {
        val links = SubscriptionParser.parseAll("vless://id@one.example:443#One\ntrojan://pass@two.example:443#Two")
        assertEquals(2, links.size); assertEquals("one.example", links[0].server); assertEquals("two.example", links[1].server)
    }

    @Test fun `parses Shadowsocks Hysteria and Naive links`() {
        assertEquals("shadowsocks", assertIs<ShareLink.Proxy>(SubscriptionParser.parse("ss://cipher:password@ss.example:8388#SS")).type)
        assertEquals("hysteria2", assertIs<ShareLink.Proxy>(SubscriptionParser.parse("hy2://auth@hy2.example:443#Hy2")).type)
        assertEquals("hysteria", assertIs<ShareLink.Proxy>(SubscriptionParser.parse("hysteria://auth@hy.example:443#Hy")).type)
        assertEquals("naive", assertIs<ShareLink.Proxy>(SubscriptionParser.parse("naive+https://user:pass@naive.example:443#Naive")).type)
    }

    @Test fun `parses remaining supported link schemes`() {
        assertEquals("tuic", assertIs<ShareLink.Proxy>(SubscriptionParser.parse("tuic://id:password@tuic.example:443#TUIC")).type)
        assertEquals("anytls", assertIs<ShareLink.Proxy>(SubscriptionParser.parse("anytls://password@anytls.example:443#AnyTLS")).type)
        assertEquals("hysteria", assertIs<ShareLink.Proxy>(SubscriptionParser.parse("hy://auth@hy.example:443#Hy")).type)
        assertEquals("socks", assertIs<ShareLink.Proxy>(SubscriptionParser.parse("socks4a://socks.example:1080#SOCKS")).type)
    }

    @OptIn(ExperimentalEncodingApi::class)
    @Test fun `parses base64 VMess and SSR links`() {
        val vmess = Base64.Default.encode("{\"ps\":\"VMess\",\"add\":\"vmess.example\",\"port\":\"443\",\"id\":\"uuid\",\"tls\":\"tls\"}".encodeToByteArray())
        val parsedVmess = assertIs<ShareLink.Proxy>(SubscriptionParser.parse("vmess://$vmess"))
        assertEquals("vmess", parsedVmess.type); assertEquals("vmess.example", parsedVmess.server); assertEquals(true, parsedVmess.tls)
        val ssr = Base64.Default.encode("ssr.example:8388:auth:aes-256-cfb:obfs:cGFzcw==".encodeToByteArray())
        val parsedSsr = assertIs<ShareLink.Proxy>(SubscriptionParser.parse("ssr://$ssr"))
        assertEquals("shadowsocksr", parsedSsr.type); assertEquals("ssr.example", parsedSsr.server)
    }

    @Test fun `parses a WireGuard config`() {
        val link = assertIs<ShareLink.WireGuard>(SubscriptionParser.parse("""
            [Interface]
            PrivateKey = interface-key
            Address = 10.0.0.2/32
            [Peer]
            PublicKey = peer-key
            Endpoint = wg.example:51820
        """.trimIndent()))
        assertEquals("wg.example", link.server); assertEquals(51820, link.port); assertEquals("WireGuard", link.name)
    }

    @Test fun `recognizes supported config documents without exposing payload`() {
        assertEquals(SubscriptionDocumentFormat.SINGBOX, SubscriptionParser.detectDocument("{\"outbounds\":[]}").format)
        assertEquals(SubscriptionDocumentFormat.XRAY, SubscriptionParser.detectDocument("{\"outbounds\":[{\"protocol\":\"vless\"}]}" ).format)
        assertEquals(SubscriptionDocumentFormat.CLASH, SubscriptionParser.detectDocument("proxies:\n  - name: node").format)
        assertEquals(SubscriptionDocumentFormat.SIP008, SubscriptionParser.detectDocument("[{\"servers\":[]}]").format)
        assertEquals(SubscriptionDocumentFormat.HYDRA, SubscriptionParser.detectDocument("{\"api_version\":\"hydra.io/subscription/v2\"}").format)
        assertEquals(SubscriptionDocumentFormat.UNKNOWN, SubscriptionParser.detectDocument("not a subscription").format)
    }

    @Test fun `parses structural outbound identifiers from JSON documents`() {
        val document = SubscriptionParser.parseDocument("{\"outbounds\":[{\"type\":\"vless\",\"tag\":\"node-a\"},{\"type\":\"trojan\",\"tag\":\"node-b\"}]}")
        assertEquals(SubscriptionDocumentFormat.SINGBOX, document.format)
        assertEquals(listOf("node-a", "node-b"), document.outboundTags)
        assertEquals(listOf("vless", "trojan"), document.outbounds.map(ParsedOutbound::type))
    }

    @Test fun `parses SIP008 and Hydra profile identifiers`() {
        assertEquals(listOf("sip-node"), SubscriptionParser.parseDocument("[{\"servers\":[{\"remarks\":\"sip-node\"}]}]").outboundTags)
        assertEquals(listOf("hydra-profile"), SubscriptionParser.parseDocument("{\"api_version\":\"hydra.io/subscription/v2\",\"profiles\":[{\"id\":\"hydra-profile\"}]}" ).outboundTags)
    }

    @Test fun `parses Clash proxy names structurally`() {
        val document = SubscriptionParser.parseDocument("""
            proxies:
              - name: first-node
                type: vless
              - name: second-node
                type: ss
        """.trimIndent())
        assertEquals(listOf("first-node", "second-node"), document.outboundTags)
        assertEquals(listOf("vless", "ss"), document.outbounds.map(ParsedOutbound::type))
    }

    @Test fun `uses Xray protocol as outbound type`() {
        val document = SubscriptionParser.parseDocument("{\"outbounds\":[{\"tag\":\"xray-node\",\"protocol\":\"trojan\"}]}")
        assertEquals(SubscriptionDocumentFormat.XRAY, document.format)
        assertEquals(listOf(ParsedOutbound("xray-node", "trojan")), document.outbounds)
    }
}
