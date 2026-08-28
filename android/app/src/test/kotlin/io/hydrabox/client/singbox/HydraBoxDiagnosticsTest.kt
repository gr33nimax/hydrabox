package io.hydrabox.client.singbox

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class HydraBoxDiagnosticsTest {
    private lateinit var originalLogcat: (String, String) -> Unit

    @Before
    fun setUp() {
        originalLogcat = HydraBoxDiagnostics.logcat
    }

    @After
    fun tearDown() {
        HydraBoxDiagnostics.logcat = originalLogcat
    }

    @Test
    fun `sends only redacted message to logcat`() {
        val messages = mutableListOf<Pair<String, String>>()
        HydraBoxDiagnostics.logcat = { tag, message -> messages += tag to message }

        HydraBoxDiagnostics.log("HB1", "token=super-secret")

        val (tag, message) = messages.single()
        assertEquals("HB1", tag)
        assertTrue(message.contains("token=<redacted>"))
        assertFalse(message.contains("super-secret"))
    }
}
