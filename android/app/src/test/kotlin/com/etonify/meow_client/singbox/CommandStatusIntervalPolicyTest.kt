package com.etonify.meow_client.singbox

import org.junit.Assert.assertEquals
import org.junit.Test

class CommandStatusIntervalPolicyTest {
    @Test
    fun `standard mode requests exactly one second in nanoseconds`() {
        assertEquals(1_000_000_000L, CommandStatusIntervalPolicy.intervalNanos("standard"))
    }

    @Test
    fun `economy mode requests exactly two seconds in nanoseconds`() {
        assertEquals(2_000_000_000L, CommandStatusIntervalPolicy.intervalNanos("economy"))
    }

    @Test
    fun `unknown mode uses safe standard interval`() {
        assertEquals(1_000_000_000L, CommandStatusIntervalPolicy.intervalNanos("unexpected"))
    }
}
