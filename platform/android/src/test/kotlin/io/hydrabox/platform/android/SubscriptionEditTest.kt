package io.hydrabox.platform.android

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * What an edit of a stored subscription amounts to, before anything is fetched or written.
 *
 * This is the rule the atomic replacement rests on: the address is the source's identity, so a
 * changed address has to be fetched and re-identified, while the name is only a name. The case
 * that matters most is the refusal — an address another stored source already uses must not be
 * taken over, because two entries on one address are one subscription that can be refreshed
 * twice and deleted once.
 */
class SubscriptionEditTest {
    private val stored = "https://provider.example/sub/abc"
    private val id = "sub-1a2b3c4d"

    @Test fun `an untouched address is a rename and nothing else`() {
        assertEquals(SubscriptionEdit.RENAME, subscriptionEdit(stored, stored, id, id))
    }

    @Test fun `an emptied field keeps the stored address`() {
        assertEquals(SubscriptionEdit.RENAME, subscriptionEdit(stored, "", null, id))
        assertEquals(SubscriptionEdit.RENAME, subscriptionEdit(stored, "   ", null, id))
    }

    @Test fun `a source with no address at all can only be renamed`() {
        assertEquals(SubscriptionEdit.RENAME, subscriptionEdit(null, "", null, id))
    }

    @Test fun `a new address nobody else uses moves the subscription`() {
        assertEquals(
            SubscriptionEdit.MOVE,
            subscriptionEdit(stored, "https://other.example/sub/xyz", null, id),
        )
    }

    @Test fun `an address another source already owns is refused`() {
        assertEquals(
            SubscriptionEdit.TAKEN,
            subscriptionEdit(stored, "https://other.example/sub/xyz", "sub-9f8e7d6c", id),
        )
    }

    @Test fun `a source that already owns the typed address is not in its own way`() {
        assertEquals(
            SubscriptionEdit.MOVE,
            subscriptionEdit(stored, "https://other.example/sub/xyz", id, id),
        )
    }
}
