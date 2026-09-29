package io.hydrabox.ui.app

import io.hydrabox.core.projection.Connection
import io.hydrabox.core.projection.ScreenState
import io.hydrabox.core.projection.ServerGroup
import io.hydrabox.core.projection.ServerRef
import io.hydrabox.core.projection.SubscriptionSummary
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Which subscription the home screen is describing.
 *
 * The bug this pins: with two subscriptions, choosing a server from the second left the first
 * subscription's name, limit and expiry on the screen. Every reading there was fed the head of
 * the stored list instead of the source the chosen server actually came from — and the stored
 * list is ordered by id, so "first" was not even "first added".
 */
class HomeSourceTest {
    private fun source(
        id: String,
        name: String,
        totalBytes: Long,
    ) = SubscriptionSummary(
        id = id,
        name = name,
        serverCount = 1,
        updatedAtMillis = 0,
        usedBytes = totalBytes / 4,
        totalBytes = totalBytes,
    )

    private fun group(
        id: String,
        name: String,
        vararg servers: ServerRef,
    ) = ServerGroup(sourceId = id, sourceName = name, servers = servers.toList())

    private fun state(
        connection: Connection,
        sources: List<SubscriptionSummary>,
        servers: List<ServerGroup>,
    ) = ScreenState(
        connection = connection,
        sources = sources,
        servers = servers,
        hasSources = sources.isNotEmpty(),
    )

    private val first = source("s1", "First", 10L)
    private val second = source("s2", "Second", 100L)
    private val twoSources =
        listOf(
            group("s1", "First", ServerRef("oslo", "Oslo", sourceId = "s1")),
            group("s2", "Second", ServerRef("helsinki", "Helsinki", sourceId = "s2")),
        )

    @Test fun `the plan belongs to the chosen server not the first source`() {
        val chosen = ServerRef("helsinki", "Helsinki", sourceId = "s2")

        assertEquals(
            "s2",
            homeSource(state(Connection.Idle(chosen), listOf(first, second), twoSources))?.id,
        )
    }

    @Test fun `a single source is still the plan of its chosen server`() {
        val chosen = ServerRef("oslo", "Oslo", sourceId = "s1")

        assertEquals(
            "s1",
            homeSource(state(Connection.Idle(chosen), listOf(first), listOf(twoSources.first())))?.id,
        )
    }

    @Test fun `a reordered stored list does not move the plan`() {
        val chosen = ServerRef("oslo", "Oslo", sourceId = "s1")

        assertEquals(
            "s1",
            homeSource(state(Connection.Idle(chosen), listOf(second, first), twoSources))?.id,
        )
    }

    @Test fun `two sources with one name are told apart by id`() {
        val named = source("s2", "First", 100L)
        val chosen = ServerRef("helsinki", "Helsinki", sourceId = "s2")

        assertEquals(
            "s2",
            homeSource(state(Connection.Idle(chosen), listOf(first, named), twoSources))?.id,
        )
    }

    @Test fun `a chosen server whose source is gone has no plan`() {
        val chosen = ServerRef("helsinki", "Helsinki", sourceId = "s9")

        assertNull(homeSource(state(Connection.Idle(chosen), listOf(first, second), twoSources)))
    }

    @Test fun `a screen with no chosen server has no plan`() {
        assertNull(homeSource(state(Connection.Idle(null), listOf(first, second), twoSources)))
    }

    @Test fun `an automatic choice takes the plan of the server the core landed on`() {
        val auto = ServerRef(id = "auto", displayName = "auto", auto = true, resolvedTag = "helsinki")

        assertEquals(
            "s2",
            homeSource(state(Connection.Idle(auto), listOf(first, second), twoSources))?.id,
        )
    }

    @Test fun `an automatic choice before the core names a leaf has no plan`() {
        val auto = ServerRef(id = "auto", displayName = "auto", auto = true)

        assertNull(homeSource(state(Connection.Idle(auto), listOf(first, second), twoSources)))
    }

    @Test fun `a lone source is the plan before the automatic choice names a leaf`() {
        val auto = ServerRef(id = "auto", displayName = "auto", auto = true)
        val lone = listOf(twoSources.first())

        assertEquals(
            "s1",
            homeSource(state(Connection.Idle(auto), listOf(first), lone))?.id,
        )
        assertEquals(
            "s1",
            homeSource(state(Connection.Idle(null), listOf(first), lone))?.id,
        )
    }

    @Test fun `an automatic choice naming a server that is gone has no plan`() {
        val auto = ServerRef(id = "auto", displayName = "auto", auto = true, resolvedTag = "vanished")

        assertNull(homeSource(state(Connection.Idle(auto), listOf(first, second), twoSources)))
    }
}
