package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeSessionStageTest {
    @Test
    fun `second close for a released generation is a no-op`() {
        val generation = 7L

        assertFalse(shouldSkipRuntimeClose(generation, hasCommandServer = true, releasedGeneration = 0L))
        assertTrue(shouldSkipRuntimeClose(generation, hasCommandServer = false, releasedGeneration = generation))
    }

    @Test
    fun `close without a preceding start is a no-op`() {
        assertTrue(shouldSkipRuntimeClose(0L, hasCommandServer = false, releasedGeneration = 0L))
    }

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
