package io.hydrabox.client.singbox

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HydraBoxLogSanitizerTest {
    @Test
    fun `redacts proxy credentials urls identifiers and addresses`() {
        val raw = """
            vless://00000000-0000-4000-8000-000000000001@example.com:443?security=reality
            GET https://subscriptions.example/client/secret-token?token=abc
            password=secret X-HWID: device-id
            dial 203.0.113.7:443 and [2001:db8::1]:443
        """.trimIndent() + "\u001B[37mcolored\u001B[0m"

        val sanitized = HydraBoxLogSanitizer.redact(raw)

        assertFalse(sanitized.contains("secret-token"))
        assertFalse(sanitized.contains("device-id"))
        assertFalse(sanitized.contains("203.0.113.7"))
        assertFalse(sanitized.contains("2001:db8::1"))
        assertFalse(sanitized.contains("00000000-0000-4000-8000-000000000001"))
        assertFalse(sanitized.contains("\u001B"))
        assertTrue(sanitized.contains("vless://<redacted>"))
        assertTrue(sanitized.contains("https://subscriptions.example/<redacted>"))
    }
}
