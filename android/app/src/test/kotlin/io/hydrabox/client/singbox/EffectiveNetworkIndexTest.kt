package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Test

class EffectiveNetworkIndexTest {
    @Test
    fun `live network with unresolved index retries its snapshot`() {
        assertEquals(
            InterfacePublication.RETRY_SNAPSHOT,
            decideInterfacePublication(
                effectiveNetworkPresent = true,
                interfaceIndex = -1,
                consecutiveUnresolvedSnapshots = 1,
            ),
        )
    }

    @Test
    fun `third unresolved snapshot publishes none`() {
        assertEquals(
            InterfacePublication.PUBLISH_NONE,
            decideInterfacePublication(
                effectiveNetworkPresent = true,
                interfaceIndex = -1,
                consecutiveUnresolvedSnapshots = 3,
            ),
        )
    }

    @Test
    fun `missing effective network publishes none immediately`() {
        assertEquals(
            InterfacePublication.PUBLISH_NONE,
            decideInterfacePublication(
                effectiveNetworkPresent = false,
                interfaceIndex = -1,
                consecutiveUnresolvedSnapshots = 0,
            ),
        )
    }
}
