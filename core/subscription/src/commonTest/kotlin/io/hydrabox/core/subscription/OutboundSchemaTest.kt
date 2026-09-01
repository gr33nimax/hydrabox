package io.hydrabox.core.subscription

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertIs

class OutboundSchemaTest {
    private fun valid() = mapOf<String, Any?>(
        "type" to "call", "tag" to "call-vk-out", "platform" to "vk", "mode" to "vk_parasite",
        "server" to "vpn.example", "server_port" to 2443,
        "join_links" to listOf("https://calls.example/join/room-a", "https://calls.example/join/room-b", "https://calls.example/join/room-c", "https://calls.example/join/room-d"),
        "user" to "alice", "password" to "per-user-secret", "obfs_password" to "ooooooooooooooooooooooooooooooooooooooooooo", "worker_connect_timeout" to "12s",
    )

    @Test fun `retains and validates the VK parasite outbound`() {
        val outbound = assertIs<CallVkParasiteOutbound>(OutboundSchema.sanitize(valid()))
        assertEquals("call-vk-out", outbound.tag); assertEquals(4, outbound.joinLinks.size); assertEquals(null, outbound.workers)
    }

    @Test fun `accepts every supported worker count`() {
        listOf(4, 8, 12, 16, 20).forEach { count ->
            assertEquals(count, assertIs<CallVkParasiteOutbound>(OutboundSchema.sanitize(valid() + ("workers" to count))).workers)
        }
    }

    @Test fun `rejects invalid worker counts and configurations`() {
        assertFails { OutboundSchema.sanitize(valid() + ("workers" to 5)) }
        assertFails { OutboundSchema.sanitize(valid() + ("workers" to 18)) }
        assertFails { OutboundSchema.sanitize(valid() + ("join_links" to listOf("a", "b", "c", "d", "e"))) }
        assertFails { OutboundSchema.sanitize(valid() + ("join_links" to listOf("a", "a", "c", "d"))) }
        assertFails { OutboundSchema.sanitize(valid() - "obfs_password") }
        assertFails { OutboundSchema.sanitize(valid() + ("worker_connect_timeout" to "121s")) }
    }

    @Test fun `keeps legacy joiner role contract`() {
        val outbound = assertIs<CallJoinerOutbound>(OutboundSchema.sanitize(mapOf("type" to "call", "tag" to "call-vk-legacy", "platform" to "vk", "mode" to "joiner", "join_link" to "https://calls.example/join/legacy-room")))
        assertEquals("joiner", outbound.mode)
    }
}
