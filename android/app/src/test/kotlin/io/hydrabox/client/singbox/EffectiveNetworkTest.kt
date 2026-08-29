package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EffectiveNetworkTest {
    @Test
    fun `identical snapshots do not advance generation or publish`() {
        val wifi = NetworkIdentity("wifi", "wlan0", 1)
        val first = nextNetworkTransition(null, wifi, 0)
        val second = nextNetworkTransition(wifi, wifi, first.generation)

        assertTrue(first.changed)
        assertTrue(first.publishUpdate)
        assertEquals(1, first.generation)
        assertFalse(second.changed)
        assertFalse(second.publishUpdate)
        assertEquals(1, second.generation)
    }

    @Test
    fun `wifi to cellular advances once for one underlying update and rebind`() {
        val transition = nextNetworkTransition(
            NetworkIdentity("wifi", "wlan0", 1),
            NetworkIdentity("cell", "rmnet0", 2),
            4,
        )

        assertTrue(transition.changed)
        assertTrue(transition.publishUpdate)
        assertEquals(5, transition.generation)
    }

    @Test
    fun `wifi none cellular publishes none exactly once`() {
        val wifi = NetworkIdentity("wifi", "wlan0", 1)
        val none = NetworkIdentity(null, "", -1)
        val afterNone = nextNetworkTransition(wifi, none, 3)
        val repeatedNone = nextNetworkTransition(none, none, afterNone.generation)
        val cellular = nextNetworkTransition(none, NetworkIdentity("cell", "rmnet0", 2), afterNone.generation)

        assertTrue(afterNone.changed)
        assertTrue(afterNone.publishUpdate)
        assertFalse(repeatedNone.changed)
        assertFalse(repeatedNone.publishUpdate)
        assertTrue(cellular.changed)
        assertEquals(5, cellular.generation)
    }

    @Test
    fun `listener replay does not advance generation`() {
        val replay = nextNetworkTransition(
            NetworkIdentity("wifi", "wlan0", 1),
            NetworkIdentity("wifi", "wlan0", 1),
            7,
        )

        assertFalse(replay.changed)
        assertEquals(7, replay.generation)
    }
}
