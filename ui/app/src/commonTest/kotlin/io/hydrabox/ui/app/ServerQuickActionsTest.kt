package io.hydrabox.ui.app

import io.hydrabox.core.projection.MANUAL_SOURCE_ID
import io.hydrabox.core.projection.ServerRef
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ServerQuickActionsTest {
    @Test fun `quick actions are limited to manually added configs`() {
        assertTrue(serverSupportsQuickActions(ServerRef(id = "manual", displayName = "Manual", sourceId = MANUAL_SOURCE_ID)))
        assertFalse(serverSupportsQuickActions(ServerRef(id = "remote", displayName = "Remote", sourceId = "subscription")))
    }
}
