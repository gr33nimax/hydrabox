package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class RuntimeSessionStageTest {
    @Test
    fun `closeService failure makes cleanup incomplete`() {
        var closeCalls = 0
        val complete = runtimeCleanupComplete(
            initiallyComplete = true,
            closeService = {
                closeCalls++
                error("close failed")
            },
            closeServer = { closeCalls++ },
            onFailure = { _, _ -> },
        )

        assertFalse(complete)
        assertEquals(2, closeCalls)
    }

    @Test
    fun `cancellation before every stage is cancelled`() {
        RuntimeSessionStage.entries.forEach { stage ->
            assertEquals(
                RuntimeSessionOutcome.CANCELLED,
                runtimeSessionOutcome(stage, launchGeneration = 7, currentCommandGeneration = 7, cancelled = true),
            )
        }
    }

    @Test
    fun `command generation change interrupts every stage`() {
        RuntimeSessionStage.entries.forEach { stage ->
            assertEquals(
                RuntimeSessionOutcome.CANCELLED,
                runtimeSessionOutcome(stage, launchGeneration = 7, currentCommandGeneration = 8, cancelled = false),
            )
        }
    }
}
