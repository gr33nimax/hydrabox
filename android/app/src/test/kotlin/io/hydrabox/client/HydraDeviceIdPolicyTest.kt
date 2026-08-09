package io.hydrabox.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HydraDeviceIdPolicyTest {
    @Test
    fun `identity is stable for one canonical origin`() {
        val first = HydraDeviceIdPolicy.derive("com.example.app", "android-id", "HTTPS://EXAMPLE.COM:443/")
        val second = HydraDeviceIdPolicy.derive("com.example.app", "android-id", "https://example.com")

        assertEquals(first, second)
        assertTrue(first.matches(Regex("^hbx1_[A-Za-z0-9_-]{43}$")))
        assertFalse(first.contains("android-id"))
    }

    @Test
    fun `identity differs between provider origins`() {
        val first = HydraDeviceIdPolicy.derive("com.example.app", "android-id", "https://one.example")
        val second = HydraDeviceIdPolicy.derive("com.example.app", "android-id", "https://two.example")

        assertNotEquals(first, second)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `http origin is rejected`() {
        HydraDeviceIdPolicy.derive("com.example.app", "android-id", "http://example.com")
    }
}
