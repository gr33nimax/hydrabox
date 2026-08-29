package io.hydrabox.client

import io.hydrabox.client.runtime.CoreRuntimeService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.security.MessageDigest

class DesiredStateTest {
    private val initial = DesiredRuntime(
        wantRunning = true,
        mode = "vpn",
        configSha256 = "a".repeat(64),
        recoveryAttempt = 0,
        updatedAtMillis = 1L,
    )

    @Test
    fun `sticky reconciliation does not launch when recovery is not allowed`() {
        assertEquals(DesiredRuntimeDecision.None, desiredRuntimeDecision(initial.copy(wantRunning = false), initial.configSha256))
    }

    @Test
    fun `sticky source marker is consumed once`() {
        CoreRuntimeService.markStickyRestart()

        assertEquals("sticky", CoreRuntimeService.consumeReconcileSource())
        assertEquals("recovery", CoreRuntimeService.consumeReconcileSource())
    }

    @Test
    fun `reconciliation rejects stale config and exhausted recovery`() {
        assertEquals(
            DesiredRuntimeDecision.Failed("config.stale"),
            desiredRuntimeDecision(initial, "b".repeat(64)),
        )
        assertEquals(
            DesiredRuntimeDecision.Failed("runtime.recovery.exhausted"),
            desiredRuntimeDecision(initial.copy(recoveryAttempt = 3), initial.configSha256),
        )
    }

    @Test
    fun `reconciliation compares the config sha256`() {
        val config = "config".toByteArray()
        val sha256 = MessageDigest.getInstance("SHA-256").digest(config).joinToString("") { "%02x".format(it) }
        val desired = initial.copy(configSha256 = sha256)

        assertEquals(DesiredRuntimeDecision.Recover(desired.copy(recoveryAttempt = 1)), desiredRuntimeDecision(desired, sha256))
        assertEquals(DesiredRuntimeDecision.Failed("config.stale"), desiredRuntimeDecision(desired, "b".repeat(64)))
    }

    @Test
    fun `durable state transition table is complete`() {
        val started = desiredRuntimeTransition(initial.copy(wantRunning = false, recoveryAttempt = 2), DesiredRuntimeEvent.USER_START)
        assertEquals(true, started.wantRunning)
        assertEquals(0, started.recoveryAttempt)
        assertEquals(1, desiredRuntimeTransition(started, DesiredRuntimeEvent.AUTOMATIC_RECOVERY).recoveryAttempt)
        assertEquals(0, desiredRuntimeTransition(started.copy(recoveryAttempt = 2), DesiredRuntimeEvent.READY).recoveryAttempt)
        assertEquals(false, desiredRuntimeTransition(started, DesiredRuntimeEvent.USER_STOP).wantRunning)
        assertEquals(false, desiredRuntimeTransition(started, DesiredRuntimeEvent.REVOKED).wantRunning)
        assertEquals(false, desiredRuntimeTransition(started, DesiredRuntimeEvent.FAILED).wantRunning)
        assertEquals(false, desiredRuntimeTransition(started.copy(recoveryAttempt = 3), DesiredRuntimeEvent.RECOVERY_EXHAUSTED).wantRunning)
    }

    @Test
    fun `parser tolerates unknown keys and rejects unsupported schema`() {
        val text = initial.serialize() + "ignored=value\n"
        assertEquals(initial, DesiredRuntime.parse(text))
        assertNull(DesiredRuntime.parse(text.replace("schema=1", "schema=2")))
    }

    @Test
    fun `startup reconciliation is queued before the first command`() {
        val queue = ArrayDeque<() -> String>()
        queue.addLast { "reconcile" }
        queue.addLast { "command" }

        assertEquals("reconcile", queue.removeFirst().invoke())
    }
}
