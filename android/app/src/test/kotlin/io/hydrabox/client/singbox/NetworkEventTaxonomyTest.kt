package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class NetworkEventTaxonomyTest {
    @Test
    fun `network event branch covers the telemetry dictionary`() {
        assertEquals(
            setOf(
                "changed", "noop", "none", "index_unavailable", "divergence",
                "lost_selectable", "lost_active", "stale_iface",
            ),
            NetworkEventBranch.values().map(NetworkEventBranch::telemetryValue).toSet(),
        )
        assertEquals(NetworkEventBranch.DIVERGENCE, branch(bestPresent = true, bestMatchesCached = false))
        assertEquals(NetworkEventBranch.LOST_SELECTABLE, branch(cachedPresent = true))
        assertEquals(NetworkEventBranch.LOST_ACTIVE, branch(bestPresent = true, cachedPresent = true, activePresent = false))
        assertEquals(NetworkEventBranch.STALE_IFACE, branch(bestPresent = true, cachedPresent = true, cachedInterfaceStale = true))
        assertEquals(NetworkEventBranch.NOOP, branch())
        assertEquals(NetworkEventBranch.CHANGED, branch(changed = true))
        assertEquals(NetworkEventBranch.NONE, branch(none = true))
    }

    @Test
    fun `launch snapshot is noop and non heartbeat inputs never emit tick`() {
        assertEquals(
            NetworkEventBranch.NOOP,
            branch(
                trigger = NetworkEventTrigger.LAUNCH,
                bestPresent = true,
                bestMatchesCached = false,
            ),
        )
        listOf(NetworkEventTrigger.CALLBACK, NetworkEventTrigger.LAUNCH).forEach { trigger ->
            listOf(false, true).forEach { bestPresent ->
                listOf(false, true).forEach { bestMatchesCached ->
                    listOf(false, true).forEach { cachedPresent ->
                        listOf(false, true).forEach { activePresent ->
                            listOf(false, true).forEach { cachedInterfaceStale ->
                                listOf(false, true).forEach { changed ->
                                    listOf(false, true).forEach { none ->
                                        assertNotEquals(
                                            "tick",
                                            branch(
                                                trigger = trigger,
                                                bestPresent = bestPresent,
                                                bestMatchesCached = bestMatchesCached,
                                                cachedPresent = cachedPresent,
                                                activePresent = activePresent,
                                                cachedInterfaceStale = cachedInterfaceStale,
                                                changed = changed,
                                                none = none,
                                            ).telemetryValue,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun branch(
        trigger: NetworkEventTrigger = NetworkEventTrigger.HEARTBEAT,
        bestPresent: Boolean = false,
        bestMatchesCached: Boolean = true,
        cachedPresent: Boolean = false,
        activePresent: Boolean = true,
        cachedInterfaceStale: Boolean = false,
        changed: Boolean = false,
        none: Boolean = false,
    ) = decideNetworkEventBranch(
        trigger = trigger,
        bestNetworkPresent = bestPresent,
        bestMatchesCached = bestMatchesCached,
        cachedNetworkPresent = cachedPresent,
        activeNetworkPresent = activePresent,
        cachedInterfaceStale = cachedInterfaceStale,
        changed = changed,
        none = none,
    )
}
