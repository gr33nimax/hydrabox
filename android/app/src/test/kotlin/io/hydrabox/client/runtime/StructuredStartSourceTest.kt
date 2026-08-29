package io.hydrabox.client.runtime

import org.junit.Assert.assertEquals
import org.junit.Test

class StructuredStartSourceTest {
    @Test
    fun `empty source defaults to ui`() {
        assertEquals("ui", startSourceFor(recovery = false, requestSource = "", sticky = false))
    }

    @Test
    fun `quick settings tile source is preserved`() {
        assertEquals("tile", startSourceFor(recovery = false, requestSource = "tile", sticky = false))
    }

    @Test
    fun `recovery takes precedence over tile`() {
        assertEquals("recovery", startSourceFor(recovery = true, requestSource = "tile", sticky = false))
    }

    @Test
    fun `sticky takes precedence without recovery`() {
        assertEquals("sticky", startSourceFor(recovery = false, requestSource = "tile", sticky = true))
    }
}
