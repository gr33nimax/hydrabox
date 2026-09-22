package io.hydrabox.core.projection

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * What a subscription detail may say about the device, and — more to the point — what it may not.
 *
 * The rule exists because the screen is the one place a value could be invented: an identifier
 * that is not transmitted must not appear, and a value that could not be derived must not be
 * filled in with a guess. Both are silent failures on a screen, which is why they are pinned here.
 */
class SubscriptionIdentifiersTest {
    @Test fun `a source that is told nothing about the device shows nothing`() {
        assertEquals(emptyList(), subscriptionIdentifiers(hydraKey = false, hardwareId = "hbx1_abc"))
    }

    @Test fun `a source that receives the identifier shows it under its own name`() {
        assertEquals(
            listOf(SubscriptionIdentifier(label = "HWID", value = "hbx1_abc")),
            subscriptionIdentifiers(hydraKey = true, hardwareId = "hbx1_abc"),
        )
    }

    @Test fun `a value that could not be derived is left out rather than guessed`() {
        assertEquals(emptyList(), subscriptionIdentifiers(hydraKey = true, hardwareId = null))
        assertEquals(emptyList(), subscriptionIdentifiers(hydraKey = true, hardwareId = "  "))
    }

    @Test fun `nothing in the list is a credential`() {
        val shown = subscriptionIdentifiers(hydraKey = true, hardwareId = "hbx1_abc")
        assertTrue(
            shown.all { it.value.startsWith("hbx1_") },
            "a value that is not the device's own pseudonym was offered as an identifier",
        )
    }
}
