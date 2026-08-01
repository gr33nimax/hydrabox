package com.etonify.meow_client

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubscriptionTransportPolicyTest {
    @Test
    fun `http loopback policy accepts only literal loopback hosts`() {
        assertTrue(isLiteralLoopbackSubscriptionHost("localhost"))
        assertTrue(isLiteralLoopbackSubscriptionHost("dev.localhost"))
        assertTrue(isLiteralLoopbackSubscriptionHost("127.0.0.1"))
        assertTrue(isLiteralLoopbackSubscriptionHost("127.255.255.254"))
        assertTrue(isLiteralLoopbackSubscriptionHost("[::1]"))

        assertFalse(isLiteralLoopbackSubscriptionHost("example.com"))
        assertFalse(isLiteralLoopbackSubscriptionHost("localhost.example"))
        assertFalse(isLiteralLoopbackSubscriptionHost("127.0.0.01"))
        assertFalse(isLiteralLoopbackSubscriptionHost("0.0.0.0"))
    }

    @Test
    fun `hbx key is recognized in any query spelling`() {
        assertTrue(hasHydraBoxKeyQuery("hbx-key=secret"))
        assertTrue(hasHydraBoxKeyQuery("x=1&hbx%2Dkey=secret"))
        assertTrue(hasHydraBoxKeyQuery("x=1;HBX-KEY"))
        assertFalse(hasHydraBoxKeyQuery("x=1&key=secret"))
        assertFalse(hasHydraBoxKeyQuery(null))
    }
}
