package io.hydrabox.core.subscription

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HydraSubscriptionUriTest {
    private val key = "A".repeat(43)

    @Test fun `key is read from the fragment and stripped from the request`() {
        val url = "https://example.test/sub?token=1#hydra-key=$key"
        assertEquals(key, HydraSubscriptionUri.keyOf(url))
        assertEquals("https://example.test/sub?token=1", HydraSubscriptionUri.withoutSecretFragment(url))
    }

    @Test fun `a key in the query is detected so it can be refused`() {
        assertTrue(HydraSubscriptionUri.hasKeyQueryParameter("https://example.test/sub?hydra-key=$key"))
        assertFalse(HydraSubscriptionUri.hasKeyQueryParameter("https://example.test/sub#hydra-key=$key"))
    }

    @Test fun `a malformed or duplicated key is not accepted`() {
        assertNull(HydraSubscriptionUri.keyOf("https://example.test/sub#hydra-key=short"))
        assertNull(HydraSubscriptionUri.keyOf("https://example.test/sub#hydra-key=$key&hydra-key=$key"))
        assertNull(HydraSubscriptionUri.keyOf("https://example.test/sub"))
    }

    @Test fun `a source without a fragment is left alone`() {
        assertEquals("https://example.test/sub", HydraSubscriptionUri.withoutSecretFragment("https://example.test/sub"))
        assertFalse(HydraSubscriptionUri.hasKeyFragment("https://example.test/sub"))
    }
}
