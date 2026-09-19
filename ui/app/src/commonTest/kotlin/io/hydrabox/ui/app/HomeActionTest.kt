package io.hydrabox.ui.app

import io.hydrabox.core.projection.Connection
import io.hydrabox.core.projection.ServerRef
import io.hydrabox.core.projection.TrafficSummary
import io.hydrabox.core.projection.Trouble
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HomeActionTest {
    @Test fun `unreachable server opens server selection`() {
        var opened = 0
        var retried = 0

        dispatchHomeAction(
            Connection.Stopped(Trouble.SERVER_UNREACHABLE, ServerRef("id", "Server"), retryable = true),
            sourceId = null,
            actions = AppActions(onRetry = { retried += 1 }),
            onOpenServers = { opened += 1 },
        )

        assertEquals(1, opened)
        assertEquals(0, retried)
    }

    @Test fun `unavailable subscription refreshes its source`() {
        var refreshed: String? = null
        var retried = 0

        dispatchHomeAction(
            Connection.Stopped(Trouble.SUBSCRIPTION_UNAVAILABLE, server = null, retryable = true),
            sourceId = "subscription-1",
            actions = AppActions(onRefreshSource = { refreshed = it }, onRetry = { retried += 1 }),
            onOpenServers = {},
        )

        assertEquals("subscription-1", refreshed)
        assertEquals(0, retried)
    }

    @Test fun `a press while the tunnel is starting cannot become a stop`() {
        var connects = 0
        var disconnects = 0
        val actions = AppActions(onConnect = { connects += 1 }, onDisconnect = { disconnects += 1 })

        // Four presses in a row, the way they arrive on a phone: the first starts the tunnel,
        // and the state the screen draws turns into Connecting under the remaining three.
        var connection: Connection = Connection.Idle(server = null)
        repeat(4) {
            if (apertureEnabled(connection)) {
                dispatchHomeAction(connection, sourceId = null, actions = actions, onOpenServers = {})
            }
            connection = Connection.Connecting(server = null)
        }

        assertEquals(1, connects)
        assertEquals(0, disconnects, "the button that starts the tunnel turned the next press into a stop")
    }

    @Test fun `the aperture stays open where its press still means something`() {
        assertTrue(apertureEnabled(Connection.Idle(server = null)), "an idle tunnel is started from here")
        assertTrue(
            apertureEnabled(Connection.Connected(server = null, traffic = TrafficSummary(available = false))),
            "a running tunnel is stopped from here",
        )
        assertTrue(
            apertureEnabled(Connection.Stopped(Trouble.UNKNOWN, server = null, retryable = true)),
            "a failure that can be retried is retried from here",
        )
        assertFalse(apertureEnabled(Connection.Connecting(server = null)), "a start in flight has its own cancel below")
        assertFalse(apertureEnabled(Connection.Reconnecting(server = null)), "a recovery in flight is not cancelled here")
    }
}
