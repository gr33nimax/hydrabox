package io.hydrabox.core.subscription

import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SingleConfigImportTest {
    @Test
    fun `single share link becomes one outbound`() {
        val outbound =
            SingleConfigParser
                .parse(
                    "vless://11111111-2222-3333-4444-555555555555@edge.example:443#Edge",
                ).single()

        assertEquals("Edge", outbound.tag)
        assertEquals("vless", outbound.type)
        assertEquals("edge.example", outbound.json["server"]?.jsonPrimitive?.content)
    }

    @Test
    fun `raw outbound json is preserved`() {
        val source = """{"type":"ssh","tag":"office","server":"host.example","server_port":22,"user":"me"}"""

        val outbound = SingleConfigParser.parse(source).single()

        assertEquals("office", outbound.tag)
        assertEquals("ssh", outbound.type)
        assertEquals("me", outbound.json["user"]?.jsonPrimitive?.content)
    }

    @Test
    fun `raw outbound json can contain url values`() {
        val source = """{"type":"ssh","tag":"office","server":"host.example","server_port":22,"url":"https://probe.example/status"}"""

        val outbound = SingleConfigParser.parse(source).single()

        assertEquals("https://probe.example/status", outbound.json["url"]?.jsonPrimitive?.content)
    }

    @Test
    fun `array of raw outbounds becomes multiple entries`() {
        val source = """[{"type":"vless","tag":"one"},{"type":"mieru","tag":"two"}]"""

        val outbounds = SingleConfigParser.parse(source)

        assertEquals(listOf("one", "two"), outbounds.map(CatalogOutbound::tag))
        assertEquals(listOf("vless", "mieru"), outbounds.map(CatalogOutbound::type))
    }

    @Test
    fun `base64 wrapped share link is detected`() {
        val source = "dmxlc3M6Ly8xMTExMTExMS0yMjIyLTMzMzMtNDQ0NC01NTU1NTU1NTU1NTVAZS5leGFtcGxlOjQ0MyNOb2Rl"

        val outbound = SingleConfigParser.parse(source).single()

        assertEquals("Node", outbound.tag)
    }

    @Test
    fun `subscription document is rejected with guidance`() {
        val failure =
            assertFailsWith<IllegalArgumentException> {
                SingleConfigParser.parse("""{"outbounds":[{"type":"vless","tag":"one"}]}""")
            }

        assertTrue(failure.message.orEmpty().contains("subscription"))
    }

    @Test
    fun `multiple share links become separate outbounds`() {
        val source =
            """vless://11111111-2222-3333-4444-555555555555@one.example:443#One
                |vless://66666666-7777-8888-9999-000000000000@two.example:8443#Two
            """.trimMargin()

        val outbounds = SingleConfigParser.parse(source)

        assertEquals(listOf("One", "Two"), outbounds.map(CatalogOutbound::tag))
        assertEquals(listOf("one.example", "two.example"), outbounds.map { it.json["server"]?.jsonPrimitive?.content })
    }

    @Test
    fun `duplicate names in multiple share links remain unique`() {
        val source =
            """vless://11111111-2222-3333-4444-555555555555@one.example:443#Same
                |vless://66666666-7777-8888-9999-000000000000@two.example:8443#Same
            """.trimMargin()

        val outbounds = SingleConfigParser.parse(source)

        assertEquals(listOf("Same", "Same (1)"), outbounds.map(CatalogOutbound::tag))
    }

    @Test
    fun `singbox subscription document is recognized for routing`() {
        val subscription = """{"outbounds":[{"type":"vless","tag":"One"}]}"""
        val singleConfig = """{"type":"vless","tag":"One"}"""
        val outboundWithMembers = """{"type":"selector","tag":"auto","outbounds":[]}"""

        assertTrue(SingleConfigParser.isSubscriptionDocument(subscription))
        assertFalse(SingleConfigParser.isSubscriptionDocument(singleConfig))
        assertFalse(SingleConfigParser.isSubscriptionDocument(outboundWithMembers))
    }

    @Test
    fun `base64 subscription document is recognized for routing`() {
        val encoded = "eyJvdXRib3VuZHMiOlt7InR5cGUiOiJ2bGVzcyIsInRhZyI6Ik9uZSJ9XX0="

        assertTrue(SingleConfigParser.isSubscriptionDocument(encoded))
    }

    @Test
    fun `garbage is rejected`() {
        assertFailsWith<IllegalArgumentException> {
            SingleConfigParser.parse("not a config")
        }
    }
}
