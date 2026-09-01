package io.hydrabox.core.subscription

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

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
}
