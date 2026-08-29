package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeSessionStageTest {
    @Test
    fun `cancellation before every stage is cancelled`() {
        RuntimeSessionStage.entries.forEach { stage ->
            assertEquals(RuntimeSessionOutcome.CANCELLED, runtimeSessionOutcome(stage, cancelled = true))
        }
    }
}
