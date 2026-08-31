package io.hydrabox.core.diagnostics

import kotlin.test.Test
import kotlin.test.assertEquals

class DiagnosticsTest {
    @Test fun `diagnostic events accept only typed public fields`() {
        assertEquals("runtime.started", DiagnosticEvent("runtime.started", listOf(DiagnosticField.Count(1))).code)
    }
}
