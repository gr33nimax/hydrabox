package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeEventCadenceTest {
    @Test
    fun `foreground cadence reflects performance modes`() {
        assertEquals(
            250L,
            RuntimeEventCadence.intervalMillis(
                uiForeground = true,
                screenInteractive = true,
                performanceMode = "performance",
            ),
        )
        assertEquals(
            500L,
            RuntimeEventCadence.intervalMillis(
                uiForeground = true,
                screenInteractive = true,
                performanceMode = "balanced",
            ),
        )
        assertEquals(
            1_000L,
            RuntimeEventCadence.intervalMillis(
                uiForeground = true,
                screenInteractive = true,
                performanceMode = "standard",
            ),
        )
        assertEquals(
            1_000L,
            RuntimeEventCadence.intervalMillis(
                uiForeground = true,
                screenInteractive = true,
                performanceMode = null,
            ),
        )
    }

    @Test
    fun `background cadence with interactive screen uses 5000ms regardless of performance mode`() {
        for (mode in listOf("performance", "balanced", "standard", null)) {
            assertEquals(
                5_000L,
                RuntimeEventCadence.intervalMillis(
                    uiForeground = false,
                    screenInteractive = true,
                    performanceMode = mode,
                ),
            )
        }
    }

    @Test
    fun `background cadence with non-interactive screen uses 30000ms regardless of performance mode`() {
        for (mode in listOf("performance", "balanced", "standard", null)) {
            assertEquals(
                30_000L,
                RuntimeEventCadence.intervalMillis(
                    uiForeground = false,
                    screenInteractive = false,
                    performanceMode = mode,
                ),
            )
        }
    }

    @Test
    fun `screen state does not degrade foreground interval when ui is active`() {
        // Even if screenInteractive were transiently reported false while UI is foreground,
        // foreground cadence takes precedence.
        assertEquals(
            250L,
            RuntimeEventCadence.intervalMillis(
                uiForeground = true,
                screenInteractive = false,
                performanceMode = "performance",
            ),
        )
        assertEquals(
            500L,
            RuntimeEventCadence.intervalMillis(
                uiForeground = true,
                screenInteractive = false,
                performanceMode = "balanced",
            ),
        )
        assertEquals(
            1_000L,
            RuntimeEventCadence.intervalMillis(
                uiForeground = true,
                screenInteractive = false,
                performanceMode = "standard",
            ),
        )
    }
}
