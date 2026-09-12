package io.hydrabox.core.config

import io.hydrabox.core.subscription.CatalogOutbound
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * A standalone measurement asks about one server, so its document must carry that server and
 * what it dials through — and nothing else. Every outbound of every subscription in one
 * document is how a single entry the core refuses took every other server's measurement down
 * with it.
 */
class OutboundIsolationTest {
    private fun outbound(tag: String, type: String = "vless", detour: String? = null, members: List<String>? = null) =
        CatalogOutbound(
            tag = tag,
            type = type,
            json = buildJsonObject {
                put("type", type)
                put("tag", tag)
                detour?.let { put("detour", it) }
                members?.let { list -> putJsonArray("outbounds") { list.forEach { add(JsonPrimitive(it)) } } }
            },
        )

    private val catalogue = listOf(
        outbound("edge"),
        outbound("relay", detour = "edge"),
        outbound("sibling"),
    )

    @Test fun `the document carries the server and what it dials through`() {
        val isolated = isolateOutbound(catalogue, "relay")
        assertEquals(listOf("edge", "relay"), isolated.map(CatalogOutbound::tag))
    }

    @Test fun `a chain is followed transitively`() {
        val chain = listOf(outbound("a", detour = "b"), outbound("b", detour = "c"), outbound("c"), outbound("other"))
        assertEquals(listOf("a", "b", "c"), isolateOutbound(chain, "a").map(CatalogOutbound::tag))
    }

    @Test fun `a group keeps the members it names`() {
        val group = listOf(
            outbound("pick", type = "selector", members = listOf("one", "two")),
            outbound("one"),
            outbound("two"),
            outbound("three"),
        )
        assertEquals(listOf("pick", "one", "two"), isolateOutbound(group, "pick").map(CatalogOutbound::tag))
    }

    @Test fun `nothing in the result points outside it`() {
        val isolated = isolateOutbound(catalogue, "relay")
        val tags = isolated.map(CatalogOutbound::tag).toSet()
        isolated.forEach { outbound ->
            outbound.json["detour"]?.jsonPrimitive?.contentOrNull?.let { reference ->
                assertTrue(reference in tags, "${outbound.tag} dials $reference, which was left out")
            }
            outbound.json["outbounds"]?.jsonArray?.forEach { member ->
                assertTrue(member.jsonPrimitive.contentOrNull in tags, "${outbound.tag} holds a member that was left out")
            }
        }
    }

    @Test fun `an unknown tag answers with the whole catalogue rather than nothing`() {
        assertEquals(catalogue, isolateOutbound(catalogue, "missing"))
    }

    @Test fun `a generated session for one server names only that server`() {
        val config = TunnelConfigGenerator.generate(
            TunnelInput(outbounds = isolateOutbound(catalogue, "relay"), selectedTag = "relay"),
        )
        val root = Json.parseToJsonElement(config).jsonObject
        val tags = root["outbounds"]!!.jsonArray.map { it.jsonObject["tag"]!!.jsonPrimitive.content }
        assertTrue("relay" in tags)
        assertTrue("edge" in tags, "the dial chain must survive")
        assertTrue("sibling" !in tags, "a sibling must not be carried into a single-server session")
    }
}
