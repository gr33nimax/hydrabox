package io.hydrabox.core.subscription

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class OutboundCatalogParserTest {
    private val hydra = """
        {
          "api_version": "hydra.io/subscription/v2",
          "kind": "Subscription",
          "default_profile": "p-main",
          "resources": [
            {
              "id": "r1",
              "format": "sing-box-json",
              "document": {
                "outbounds": [
                  {"type": "vless", "tag": "edge", "server": "a.example", "server_port": 443, "uuid": "u"},
                  {"type": "shadowsocks", "tag": "relay", "server": "b.example", "server_port": 8388, "method": "aes-128-gcm", "password": "p", "detour": "edge"},
                  {"type": "direct", "tag": "bypass"},
                  {"type": "selector", "tag": "group"}
                ]
              }
            }
          ],
          "profiles": [
            {"id": "p-main", "resource": "r1", "entrypoint": {"section": "outbounds", "tag": "relay"}}
          ]
        }
    """.trimIndent()

    @Test fun `Hydra document yields its entrypoint and keeps the chain embedded`() {
        val catalog = OutboundCatalogParser.parse(hydra)
        assertEquals(SubscriptionDocumentFormat.HYDRA, catalog.format)
        // The selector is dropped, everything else is embedded so `detour` still resolves.
        assertEquals(listOf("edge", "relay", "bypass"), catalog.outbounds.map(CatalogOutbound::tag))
        // Only the profile entrypoint is offered as a choice.
        assertEquals(listOf("relay"), catalog.selectable.map(CatalogOutbound::tag))
        assertEquals("relay", catalog.defaultTag)
    }

    @Test fun `Hydra outbound survives verbatim including protocol fields`() {
        val relay = OutboundCatalogParser.parse(hydra).outbounds.first { it.tag == "relay" }
        assertEquals("shadowsocks", relay.type)
        assertTrue(relay.json.containsKey("method"))
        assertTrue(relay.json.containsKey("detour"))
    }

    @Test fun `encrypted Hydra document is refused with a clear reason`() {
        val failure = assertFailsWith<IllegalStateException> {
            OutboundCatalogParser.parse("""{"api_version":"hydra.io/subscription/v2","kind":"Subscription","protected":"x"}""")
        }
        assertTrue(failure.message.orEmpty().contains("core"))
    }

    @Test fun `plain sing-box document offers every server and no routing entry`() {
        val catalog = OutboundCatalogParser.parse(
            """{"outbounds":[{"type":"trojan","tag":"t","server":"c.example","server_port":443,"password":"p"},{"type":"block","tag":"b"}]}""",
        )
        assertEquals(SubscriptionDocumentFormat.SINGBOX, catalog.format)
        assertEquals(listOf("t"), catalog.selectable.map(CatalogOutbound::tag))
    }

    @Test fun `share links keep their transport parameters`() {
        val catalog = OutboundCatalogParser.parse(
            "vless://11111111-2222-3333-4444-555555555555@d.example:443?security=tls&sni=front.example&type=ws&path=%2Fws#Edge",
        )
        val outbound = catalog.outbounds.single()
        assertEquals("Edge", outbound.tag)
        assertEquals("front.example", outbound.json["tls"]?.toString()?.let { text ->
            Regex("\"server_name\":\"([^\"]+)\"").find(text)?.groupValues?.get(1)
        })
        assertTrue(outbound.json["transport"].toString().contains("\"ws\""))
    }

    @Test fun `base64 link list is expanded`() {
        val body = "dmxlc3M6Ly8xMTExMTExMS0yMjIyLTMzMzMtNDQ0NC01NTU1NTU1NTU1NTVAZS5leGFtcGxlOjQ0MyNOb2Rl"
        assertEquals(listOf("Node"), OutboundCatalogParser.parse(body).outbounds.map(CatalogOutbound::tag))
    }

    @Test fun `an empty or unusable body is refused`() {
        assertFailsWith<IllegalArgumentException> { OutboundCatalogParser.parse("   ") }
        assertFailsWith<IllegalArgumentException> { OutboundCatalogParser.parse("not a subscription") }
    }
}
