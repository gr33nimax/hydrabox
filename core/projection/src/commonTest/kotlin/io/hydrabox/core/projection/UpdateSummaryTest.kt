package io.hydrabox.core.projection

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * What the update row offers, which is the one thing the screen must not get wrong: checking a
 * channel tells a person what exists, and fetching it has to stay their own decision.
 *
 * The decision lives in [UpdateSummary.action] rather than in the row, so this is the same rule
 * the screen draws and not a second copy of it.
 */
class UpdateSummaryTest {
    @Test fun `a release that was only found is offered for download`() {
        val found = UpdateSummary(availableVersion = "2.0.1", checked = true)
        assertEquals(UpdateAction.DOWNLOAD, found.action)
    }

    @Test fun `a release already on the device is offered for install, not fetched again`() {
        val fetched = UpdateSummary(availableVersion = "2.0.1", checked = true, ready = true)
        assertEquals(UpdateAction.INSTALL, fetched.action)
    }

    @Test fun `a running download is left to the system's own shade`() {
        val running = UpdateSummary(availableVersion = "2.0.1", checked = true, downloading = true)
        assertEquals(UpdateAction.NONE, running.action)
    }

    @Test fun `nothing is offered while a check runs, after it found nothing, or with no answer`() {
        assertEquals(UpdateAction.NONE, UpdateSummary(checking = true).action)
        assertEquals(UpdateAction.NONE, UpdateSummary(checked = true).action)
        assertEquals(UpdateAction.NONE, UpdateSummary().action)
    }

    @Test fun `an install under way offers nothing else`() {
        val installing = UpdateSummary(availableVersion = "2.0.1", ready = true, installing = true)
        assertEquals(UpdateAction.NONE, installing.action)
    }

    @Test fun `a release that could not be asked about is not offered at all`() {
        val unreachable = UpdateSummary(reachable = false, checked = true)
        assertEquals(UpdateAction.NONE, unreachable.action)
    }
}
