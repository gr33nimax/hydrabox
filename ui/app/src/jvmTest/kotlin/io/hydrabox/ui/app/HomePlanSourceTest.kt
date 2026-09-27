package io.hydrabox.ui.app

import io.hydrabox.core.projection.Connection
import io.hydrabox.core.projection.MANUAL_SOURCE_ID
import io.hydrabox.core.projection.ScreenState
import io.hydrabox.core.projection.ServerRef
import io.hydrabox.core.projection.SubscriptionSummary
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class HomePlanSourceTest {
    private val first = SubscriptionSummary("first", "First", 1, 0)
    private val second = SubscriptionSummary("second", "Second", 1, 0)

    @Test
    fun `manual server has no subscription plan source`() {
        val state =
            ScreenState(
                connection = Connection.Idle(ServerRef("manual-1", "Manual", sourceId = MANUAL_SOURCE_ID)),
                sources = listOf(first),
            )

        assertNull(planSourceForHome(state))
    }

    @Test
    fun `selected subscription server uses its own plan source`() {
        val state =
            ScreenState(
                connection = Connection.Idle(ServerRef("second-server", "Second", sourceId = second.id)),
                sources = listOf(first, second),
            )

        assertEquals(second, planSourceForHome(state))
    }
}
