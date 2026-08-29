package io.hydrabox.client.runtime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingSelectionTest {
    @Test
    fun `successful selection becomes pending without changing selected values`() {
        val pending = pendingSelectionsAfterAcceptedSelection(
            emptyMap(),
            groupId = "select",
            outboundId = "new",
            commandGeneration = 4,
        )

        assertEquals(PendingSelection("new", 4), pending["select"])
    }

    @Test
    fun `matching core selection clears pending`() {
        val pending = pendingSelectionsAfterGroups(
            mapOf("select" to PendingSelection("new", 4)),
            mapOf("select" to "new"),
            commandGeneration = 4,
        )

        assertTrue(pending.isEmpty())
    }

    @Test
    fun `newer different selection clears pending without applying it`() {
        val pending = pendingSelectionsAfterGroups(
            mapOf("select" to PendingSelection("old", 4)),
            mapOf("select" to "new"),
            commandGeneration = 5,
        )

        assertTrue(pending.isEmpty())
    }

    @Test
    fun `stale command generation clears pending`() {
        val pending = pendingSelectionsAfterGroups(
            mapOf("select" to PendingSelection("new", 4)),
            emptyMap(),
            commandGeneration = 5,
        )

        assertTrue(pending.isEmpty())
    }
}
