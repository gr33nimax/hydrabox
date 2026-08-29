package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeSessionStageTest {
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
