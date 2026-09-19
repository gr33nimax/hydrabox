package io.hydrabox.platform.android

import io.hydrabox.core.contract.EdgeLatencyStatus
import io.hydrabox.core.contract.OutboundLatency
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The offline pass's rules, without a core, the platform or a device: what it measures, what a
 * failure is allowed to touch, and what may still be published after a handover or a stop.
 *
 * Isolation is the contract. A timeout, a refusal or a thrown exception belongs to the server it
 * happened to: the servers around it keep their own figures, and no row is left spinning by
 * another row's outcome. The pass used to share one budget and one verdict, so a single dead
 * server ended the pass and the whole list read as unanswered.
 */
class OfflineSweepTest {
    /** A pass wired to record everything it did, so a test can read the run back. */
    private fun pass(
        moved: () -> Boolean,
        measured: MutableList<String>,
        published: MutableList<String>,
        progress: MutableList<Set<String>> = mutableListOf(),
        stopped: MutableList<Int> = mutableListOf(),
        onEdge: (String) -> OutboundLatency? = { null },
        onHttp: (String) -> OutboundLatency = { OutboundLatency(it, 40, "available") },
    ) = OfflineSweep(
        isCancelled = moved,
        networkStillCurrent = { !moved() },
        measureEdge = { tag ->
            measured += "edge:$tag"
            onEdge(tag)
        },
        measureHttp = { tag ->
            measured += "http:$tag"
            onHttp(tag)
        },
        publishEdge = { answers -> published += "edge:" + answers.joinToString(",") { it.tag } },
        publishHttp = { answers -> published += "http:" + answers.joinToString(",") { it.tag } },
        onProgress = { tags -> progress += tags },
        reportStopped = { count -> stopped += count },
    )

    @Test fun `every server the press asked about is named before the first question`() {
        val progress = mutableListOf<Set<String>>()
        pass(
            moved = { false },
            measured = mutableListOf(),
            published = mutableListOf(),
            progress = progress,
        ).run(
            listOf(
                OfflineSweep.Target("amsterdam", "vless"),
                OfflineSweep.Target("vk", "call"),
                OfflineSweep.Target("tokyo", "vless"),
            ),
        )
        // A press names the whole list at once: a row spins while its own question is open
        // instead of holding a figure nobody has confirmed for it yet.
        assertEquals(setOf("amsterdam", "vk", "tokyo"), progress.first())
        assertTrue(progress.last().isEmpty(), "a finished pass left a row named as measuring")
    }

    @Test fun `an answer closes only its own row whatever the server next to it did`() {
        val measured = mutableListOf<String>()
        val published = mutableListOf<String>()
        val progress = mutableListOf<Set<String>>()
        pass(
            moved = { false },
            measured = measured,
            published = published,
            progress = progress,
            onHttp = { tag ->
                when (tag) {
                    // The refused server is one row's verdict; the other two answer around it.
                    "b" -> OutboundLatency(tag, 0, "unavailable")

                    "a" -> OutboundLatency(tag, 35, "available")

                    else -> OutboundLatency(tag, 58, "available")
                }
            },
        ).run(
            listOf(
                OfflineSweep.Target("a", "vless"),
                OfflineSweep.Target("b", "vless"),
                OfflineSweep.Target("c", "vless"),
            ),
        )
        assertEquals(
            listOf(setOf("a", "b", "c"), setOf("b", "c"), setOf("c"), emptySet<String>()),
            progress,
            "the open questions were not closed one server at a time",
        )
        assertEquals(listOf("http:a", "http:b", "http:c"), measured)
        assertEquals(listOf("http:a", "http:b", "http:c"), published)
    }

    @Test fun `a server whose measurement throws is that server's outcome alone`() {
        val measured = mutableListOf<String>()
        val published = mutableListOf<String>()
        val progress = mutableListOf<Set<String>>()
        val stopped = mutableListOf<Int>()
        pass(
            moved = { false },
            measured = measured,
            published = published,
            progress = progress,
            stopped = stopped,
            onHttp = { tag ->
                if (tag == "b") error("the transport refused the profile")
                OutboundLatency(tag, 40, "available")
            },
        ).run(
            listOf(
                OfflineSweep.Target("a", "vless"),
                OfflineSweep.Target("b", "vless"),
                OfflineSweep.Target("c", "vless"),
            ),
        )
        assertEquals(listOf("http:a", "http:b", "http:c"), measured, "a thrown measurement ended the pass")
        assertEquals(listOf("http:a", "http:c"), published, "a thrown measurement published a verdict for its server")
        assertEquals(setOf("c"), progress[2], "the server that threw stayed named as measuring")
        assertTrue(progress.last().isEmpty(), "the pass left a row spinning")
        assertTrue(stopped.isEmpty(), "a thrown measurement was reported as a stopped pass")
    }

    @Test fun `a stop mid-question asks nobody else and publishes nothing`() {
        val measured = mutableListOf<String>()
        val published = mutableListOf<String>()
        var stopped = false
        pass(
            moved = { stopped },
            measured = measured,
            published = published,
            onHttp = { tag ->
                stopped = true
                OutboundLatency(tag, 40, "available")
            },
        ).run(
            listOf(
                OfflineSweep.Target("amsterdam", "vless"),
                OfflineSweep.Target("tokyo", "vless"),
            ),
        )
        assertEquals(listOf("http:amsterdam"), measured, "a server after the stop was measured anyway")
        assertTrue(published.isEmpty(), "an answer measured across the stop was published")
    }

    @Test fun `a handover between two servers ends the pass and publishes nothing`() {
        val measured = mutableListOf<String>()
        val published = mutableListOf<String>()
        var moved = false
        pass(
            moved = { moved },
            measured = measured,
            published = published,
            onHttp = { tag ->
                if (tag == "amsterdam") moved = true
                OutboundLatency(tag, 40, "available")
            },
        ).run(
            listOf(
                OfflineSweep.Target("amsterdam", "vless"),
                OfflineSweep.Target("tokyo", "vless"),
            ),
        )
        assertEquals(listOf("http:amsterdam"), measured, "the server after the handover was measured anyway")
        assertTrue(published.isEmpty(), "answers measured across a handover were published")
    }

    @Test fun `a handover during the edge pass ends both passes`() {
        val measured = mutableListOf<String>()
        val published = mutableListOf<String>()
        var moved = false
        pass(
            moved = { moved },
            measured = measured,
            published = published,
            onEdge = { tag ->
                moved = true
                OutboundLatency(tag, 0, EdgeLatencyStatus.NO_EDGE)
            },
        ).run(
            listOf(
                OfflineSweep.Target("vk", "call"),
                OfflineSweep.Target("vk-two", "call"),
                OfflineSweep.Target("amsterdam", "vless"),
            ),
        )
        assertEquals(listOf("edge:vk"), measured, "a question after the handover was asked anyway")
        assertTrue(published.isEmpty(), "an answer from before the handover was published as current")
    }

    @Test fun `an undisturbed pass publishes each completed answer without waiting for its kind`() {
        val measured = mutableListOf<String>()
        val published = mutableListOf<String>()
        pass(
            moved = { false },
            measured = measured,
            published = published,
            onEdge = { tag -> OutboundLatency(tag, 0, EdgeLatencyStatus.ANSWERED) },
        ).run(
            listOf(
                OfflineSweep.Target("vk", "call"),
                OfflineSweep.Target("vk-two", "call"),
                OfflineSweep.Target("amsterdam", "vless"),
                OfflineSweep.Target("tokyo", "vless"),
            ),
        )
        assertEquals(listOf("edge:vk", "edge:vk-two", "http:amsterdam", "http:tokyo"), measured)
        assertEquals(listOf("edge:vk", "edge:vk-two", "http:amsterdam", "http:tokyo"), published)
    }

    @Test fun `edge answers published before a later handover in the http pass survive it`() {
        val measured = mutableListOf<String>()
        val published = mutableListOf<String>()
        var moved = false
        pass(
            moved = { moved },
            measured = measured,
            published = published,
            onEdge = { tag -> OutboundLatency(tag, 0, EdgeLatencyStatus.ANSWERED) },
            onHttp = { tag ->
                moved = true
                OutboundLatency(tag, 40, "available")
            },
        ).run(
            listOf(
                OfflineSweep.Target("vk", "call"),
                OfflineSweep.Target("amsterdam", "vless"),
                OfflineSweep.Target("tokyo", "vless"),
            ),
        )
        assertEquals(listOf("edge:vk", "http:amsterdam"), measured)
        // The edge answers were current when they were published, before the move; only
        // the http answers, measured across it, are dropped.
        assertEquals(listOf("edge:vk"), published)
    }
}
