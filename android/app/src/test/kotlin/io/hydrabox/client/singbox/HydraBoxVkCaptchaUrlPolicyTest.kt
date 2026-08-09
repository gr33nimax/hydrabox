package io.hydrabox.client.singbox

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HydraBoxVkCaptchaUrlPolicyTest {
    @Test
    fun acceptsOnlyHttpLoopbackUrlsWithExplicitPorts() {
        assertTrue(
            HydraBoxVkCaptchaUrlPolicy.isSafeLoopbackUrl(
                "http://127.0.0.1:35887/session",
            ),
        )
        assertTrue(HydraBoxVkCaptchaUrlPolicy.isSafeLoopbackUrl("http://localhost:1/"))
        assertFalse(HydraBoxVkCaptchaUrlPolicy.isSafeLoopbackUrl("https://127.0.0.1:35887/"))
        assertFalse(HydraBoxVkCaptchaUrlPolicy.isSafeLoopbackUrl("http://example.com:35887/"))
        assertFalse(HydraBoxVkCaptchaUrlPolicy.isSafeLoopbackUrl("http://127.0.0.1/"))
    }
}
