package io.hydrabox.core.diagnostics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import io.hydrabox.core.model.OperationState

class DiagnosticsTest {
    @Test fun `diagnostic events accept only typed public fields`() {
        assertEquals("runtime.started", DiagnosticEvent("runtime.started", listOf(DiagnosticField.Count(1))).code)
    }

    @Test fun `diagnostics state keeps structured events and export state`() {
        val state = DiagnosticsState(events = listOf(DiagnosticEvent("runtime.started")), export = OperationState.Running)
        assertEquals("runtime.started", state.events.single().code)
        assertIs<OperationState.Running>(state.export)
    }
}
