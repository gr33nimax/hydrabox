package com.etonify.meow_client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CommandClientLifecycleTest {
    @Test
    fun `expected disconnect does not schedule reconnect`() {
        val lifecycle = connectedLifecycle()
        val epoch = lifecycle.currentEpoch()

        val decision = lifecycle.onDisconnected(epoch, shouldConnect = false)

        assertEquals(CommandDisconnectKind.EXPECTED, decision.kind)
        assertFalse(decision.scheduleReconnect)
        assertEquals(CommandConnectionState.DISCONNECTED, lifecycle.state)
    }

    @Test
    fun `callback from invalidated epoch is stale`() {
        val lifecycle = connectedLifecycle()
        val oldEpoch = lifecycle.currentEpoch()
        val disconnectEpoch = lifecycle.beginExpectedDisconnect()

        val decision = lifecycle.onDisconnected(oldEpoch, shouldConnect = true)

        assertNotEquals(oldEpoch, disconnectEpoch)
        assertEquals(CommandDisconnectKind.STALE, decision.kind)
        assertFalse(decision.scheduleReconnect)
    }

    @Test
    fun `unexpected EOF schedules first reconnect delay`() {
        val lifecycle = connectedLifecycle()
        val epoch = lifecycle.currentEpoch()

        val decision = lifecycle.onDisconnected(epoch, shouldConnect = true)

        assertEquals(CommandDisconnectKind.UNEXPECTED, decision.kind)
        assertTrue(decision.scheduleReconnect)
        assertEquals(1, decision.reconnectAttempt)
        assertEquals(250L, decision.reconnectDelayMs)
    }

    @Test
    fun `background cancels pending reconnect`() {
        val lifecycle = connectedLifecycle()
        val epoch = lifecycle.currentEpoch()
        val decision = lifecycle.onDisconnected(epoch, shouldConnect = true)

        assertTrue(decision.scheduleReconnect)
        assertFalse(lifecycle.claimReconnect(epoch, shouldConnect = false))
        assertEquals(0, lifecycle.reconnectAttempt)
        assertEquals(CommandConnectionState.DISCONNECTED, lifecycle.state)
    }

    @Test
    fun `stop invalidates pending reconnect`() {
        val lifecycle = connectedLifecycle()
        val oldEpoch = lifecycle.currentEpoch()
        lifecycle.onDisconnected(oldEpoch, shouldConnect = true)

        val disconnectEpoch = lifecycle.beginExpectedDisconnect()
        lifecycle.finishExpectedDisconnect(disconnectEpoch)

        assertFalse(lifecycle.claimReconnect(oldEpoch, shouldConnect = true))
        assertEquals(CommandConnectionState.DISCONNECTED, lifecycle.state)
        assertEquals(0, lifecycle.reconnectAttempt)
    }

    @Test
    fun `concurrent connection requests create one epoch`() {
        val lifecycle = CommandClientLifecycle()

        val epoch = lifecycle.beginConnect(shouldConnect = true)

        assertTrue(epoch != null)
        assertNull(lifecycle.beginConnect(shouldConnect = true))
        assertTrue(lifecycle.onConnected(epoch!!))
        assertNull(lifecycle.beginConnect(shouldConnect = true))
        assertEquals(CommandConnectionState.CONNECTED, lifecycle.state)
    }

    @Test
    fun `successful connection resets reconnect backoff`() {
        val lifecycle = connectedLifecycle()
        val firstEpoch = lifecycle.currentEpoch()
        val first = lifecycle.onDisconnected(firstEpoch, shouldConnect = true)
        assertEquals(250L, first.reconnectDelayMs)
        assertTrue(lifecycle.claimReconnect(firstEpoch, shouldConnect = true))

        val secondEpoch = lifecycle.beginConnect(shouldConnect = true)!!
        val second = lifecycle.onDisconnected(secondEpoch, shouldConnect = true)
        assertEquals(500L, second.reconnectDelayMs)
        assertTrue(lifecycle.claimReconnect(secondEpoch, shouldConnect = true))

        val recoveredEpoch = lifecycle.beginConnect(shouldConnect = true)!!
        assertTrue(lifecycle.onConnected(recoveredEpoch))
        assertEquals(0, lifecycle.reconnectAttempt)

        val afterRecovery = lifecycle.onDisconnected(
            recoveredEpoch,
            shouldConnect = true,
        )
        assertEquals(1, afterRecovery.reconnectAttempt)
        assertEquals(250L, afterRecovery.reconnectDelayMs)
    }

    @Test
    fun `duplicate disconnect callback cannot enqueue another reconnect`() {
        val lifecycle = connectedLifecycle()
        val epoch = lifecycle.currentEpoch()

        val first = lifecycle.onDisconnected(epoch, shouldConnect = true)
        val duplicate = lifecycle.onDisconnected(epoch, shouldConnect = true)

        assertTrue(first.scheduleReconnect)
        assertEquals(CommandDisconnectKind.DUPLICATE, duplicate.kind)
        assertFalse(duplicate.scheduleReconnect)
        assertEquals(1, lifecycle.reconnectAttempt)
    }

    @Test
    fun `old callback stays duplicate after reconnect timer is claimed`() {
        val lifecycle = connectedLifecycle()
        val epoch = lifecycle.currentEpoch()
        lifecycle.onDisconnected(epoch, shouldConnect = true)
        assertTrue(lifecycle.claimReconnect(epoch, shouldConnect = true))

        val duplicate = lifecycle.onDisconnected(epoch, shouldConnect = true)

        assertEquals(CommandDisconnectKind.DUPLICATE, duplicate.kind)
        assertFalse(duplicate.scheduleReconnect)
        assertEquals(1, lifecycle.reconnectAttempt)
    }

    @Test
    fun `reconnect backoff stays capped at five seconds`() {
        val lifecycle = connectedLifecycle()
        var epoch = lifecycle.currentEpoch()
        val delays = mutableListOf<Long>()

        repeat(7) {
            val decision = lifecycle.onDisconnected(epoch, shouldConnect = true)
            delays += decision.reconnectDelayMs
            assertTrue(lifecycle.claimReconnect(epoch, shouldConnect = true))
            epoch = lifecycle.beginConnect(shouldConnect = true)!!
        }

        assertEquals(
            listOf(250L, 500L, 1_000L, 2_000L, 5_000L, 5_000L, 5_000L),
            delays,
        )
    }

    private fun connectedLifecycle(): CommandClientLifecycle {
        val lifecycle = CommandClientLifecycle()
        val epoch = lifecycle.beginConnect(shouldConnect = true)!!
        assertTrue(lifecycle.onConnected(epoch))
        return lifecycle
    }
}
