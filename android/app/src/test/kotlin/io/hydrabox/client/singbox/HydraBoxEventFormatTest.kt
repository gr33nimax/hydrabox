package io.hydrabox.client.singbox

import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HydraBoxEventFormatTest {
    @Test
    fun `event omits null fields and normalizes values`() {
        HydraBoxDiagnostics.event(
            "TEST",
            "text" to "has spaces",
            "missing" to null,
        )

        val line = pendingLine().substringAfter("HB1: ")

        assertTrue(line.startsWith("HB1 "))
        assertTrue(line.contains("text=has_spaces"))
        assertFalse(line.contains("missing="))
        assertFalse(line.split(' ').any { it.contains('=') && it.substringAfter('=').contains(' ') })
    }

    @Test
    fun `event code set contains every constant without duplicates`() {
        val codes = HydraBoxEventCodes::class.java.declaredFields
            .filter { it.type == String::class.java && Modifier.isStatic(it.modifiers) }
            .map { it.get(null) as String }

        assertEquals(codes.toSet(), HydraBoxEventCodes.ALL)
        assertEquals(codes.size, HydraBoxEventCodes.ALL.size)
    }

    private fun pendingLine(): String {
        val field = HydraBoxDiagnostics::class.java.getDeclaredField("pendingLines")
        field.isAccessible = true
        val pendingLines = field.get(null) as StringBuilder
        return synchronized(pendingLines) {
            pendingLines.toString().also { pendingLines.setLength(0) }
        }
    }
}
