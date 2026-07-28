package com.etonify.meow_client.singbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnServiceLifecyclePolicyTest {
    @Test
    fun `active VPN runtime survives task removal`() {
        assertEquals(
            VpnTaskRemovalAction.RECOVER_RUNTIME_AND_ARM_RESTART,
            VpnServiceLifecyclePolicy.taskRemovalAction(
                runtimeRunning = true,
                activeRuntimeOwner = true,
            ),
        )
    }

    @Test
    fun `stale service stops when native runtime is not running`() {
        assertEquals(
            VpnTaskRemovalAction.STOP_LINGERING_SERVICE,
            VpnServiceLifecyclePolicy.taskRemovalAction(
                runtimeRunning = false,
                activeRuntimeOwner = true,
            ),
        )
    }

    @Test
    fun `service without VPN runtime ownership stops on task removal`() {
        assertEquals(
            VpnTaskRemovalAction.STOP_LINGERING_SERVICE,
            VpnServiceLifecyclePolicy.taskRemovalAction(
                runtimeRunning = true,
                activeRuntimeOwner = false,
            ),
        )
    }

    @Test
    fun `destroy cancels restart only after runtime stopped`() {
        assertTrue(
            VpnServiceLifecyclePolicy.shouldCancelScheduledRestartOnDestroy(
                runtimeRunning = false,
            ),
        )
        assertFalse(
            VpnServiceLifecyclePolicy.shouldCancelScheduledRestartOnDestroy(
                runtimeRunning = true,
            ),
        )
    }
}
