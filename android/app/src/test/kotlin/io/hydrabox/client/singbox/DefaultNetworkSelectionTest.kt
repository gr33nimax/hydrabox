package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultNetworkSelectionTest {
    @Test
    fun `validated network wins`() {
        val selected = selectDefaultNetworkCandidate(
            candidates = listOf(
                candidate("cell", active = true, score = 40),
                candidate("wifi", validated = true, hasInterface = true, score = 130),
            ),
            current = "cell",
        )

        assertEquals("wifi", selected?.value)
    }

    @Test
    fun `falls back to unvalidated current physical interface when no validated network exists`() {
        val selected = selectDefaultNetworkCandidate(
            candidates = listOf(
                candidate("cell", hasInterface = true, score = 10),
            ),
            current = "cell",
        )

        assertEquals("cell", selected?.value)
    }

    @Test
    fun `falls back to unvalidated preferred callback transport when no validated network exists`() {
        val selected = selectDefaultNetworkCandidate(
            candidates = listOf(
                candidate("wifi", hasInterface = true, score = 30),
                candidate("cell", hasInterface = true, score = 10),
            ),
            current = "wifi",
            preferred = "cell",
        )

        assertEquals("cell", selected?.value)
    }

    @Test
    fun `validated candidate takes precedence over unvalidated preferred candidate`() {
        val selected = selectDefaultNetworkCandidate(
            candidates = listOf(
                candidate("wifi", validated = true, hasInterface = true, score = 130),
                candidate("cell", validated = false, hasInterface = true, score = 110),
            ),
            current = "wifi",
            preferred = "cell",
        )

        assertEquals("wifi", selected?.value)
    }

    @Test
    fun `validated callback transport wins over higher scoring stale wifi`() {
        val selected = selectDefaultNetworkCandidate(
            candidates = listOf(
                candidate("wifi", validated = true, hasInterface = true, score = 130),
                candidate("cell", validated = true, hasInterface = true, score = 110),
            ),
            current = "wifi",
            preferred = "cell",
        )

        assertEquals("cell", selected?.value)
    }

    @Test
    fun `retains the validated handover target after callback processing`() {
        val selected = selectDefaultNetworkCandidate(
            candidates = listOf(
                candidate("wifi", validated = true, hasInterface = true, score = 130),
                candidate("cell", validated = true, hasInterface = true, score = 110),
            ),
            current = "cell",
        )

        assertEquals("cell", selected?.value)
    }

    @Test
    fun `falls back to highest scoring unvalidated network with usable interface when current is null`() {
        val selected = selectDefaultNetworkCandidate(
            candidates = listOf(
                candidate("cell", hasInterface = true, score = 10),
                candidate("wifi", hasInterface = true, score = 30),
            ),
            current = null,
        )

        assertEquals("wifi", selected?.value)
    }

    @Test
    fun `rejects candidates without a usable interface`() {
        val selected = selectDefaultNetworkCandidate(
            candidates = listOf(candidate("stale", score = 30)),
            current = "stale",
        )

        assertNull(selected)
    }

    @Test
    fun `targeted monitor initialization is not a network handover`() {
        assertFalse(
            shouldBroadcastNetworkChange(
                duplicate = false,
                targetedInitialization = true,
            ),
        )
        assertFalse(
            shouldBroadcastNetworkChange(
                duplicate = true,
                targetedInitialization = false,
            ),
        )
        assertTrue(
            shouldBroadcastNetworkChange(
                duplicate = false,
                targetedInitialization = false,
            ),
        )
    }

    private fun candidate(
        value: String,
        active: Boolean = false,
        validated: Boolean = false,
        hasInterface: Boolean = false,
        score: Int,
    ) = DefaultNetworkCandidate(
        value = value,
        isActive = active,
        isValidated = validated,
        hasUsableInterface = hasInterface,
        score = score,
    )
}
