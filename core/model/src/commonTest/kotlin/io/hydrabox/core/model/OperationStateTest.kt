package io.hydrabox.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class OperationStateTest {
    @Test fun `operation states preserve terminal result or failure`() {
        val running: OperationState<String> = OperationState.Running
        val succeeded: OperationState<String> = OperationState.Succeeded("backup")
        val failed: OperationState<String> = OperationState.Failed(OperationError("network"))

        assertIs<OperationState.Running>(running)
        assertEquals("backup", assertIs<OperationState.Succeeded<String>>(succeeded).value)
        assertEquals("network", assertIs<OperationState.Failed>(failed).error.code)
    }
}
