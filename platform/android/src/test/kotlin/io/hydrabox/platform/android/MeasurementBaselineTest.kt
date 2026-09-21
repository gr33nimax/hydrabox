package io.hydrabox.platform.android

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Telling an offline sweep's baseline callback apart from a handover, without a device.
 *
 * A service created to measure is born before the first network callback arrives, so the uplink
 * that shows up first is the network the sweep should measure on, not a move away from one. It
 * is told apart from a handover by generation: the sweep records the generation it began from,
 * and the first callback newer than that is the baseline. The caller takes the pending baseline
 * as it asks, so the callback after it is a genuine handover.
 *
 * A boolean carried this before, and it was consumed by whichever callback arrived first: a
 * handover that landed before the uplink was taken for the baseline, and the sweep then ran on
 * across two networks. The generation is what makes the two distinguishable.
 */
class MeasurementBaselineTest {
    @Test
    fun `the first uplink after an offline start is the baseline`() {
        // The sweep began offline at generation 5; the uplink arrives as generation 6.
        assertTrue(isOfflineMeasurementBaseline(callbackGeneration = 6, baselineGeneration = 5))
    }

    @Test
    fun `a callback at the generation the sweep began from is not the baseline`() {
        // A duplicate of the world the sweep already knew is not the uplink it is waiting for.
        assertFalse(isOfflineMeasurementBaseline(callbackGeneration = 5, baselineGeneration = 5))
    }

    @Test
    fun `once the baseline is taken a later callback is a handover`() {
        // The caller has taken the pending baseline, so nothing is pending any more.
        assertFalse(
            isOfflineMeasurementBaseline(
                callbackGeneration = 7,
                baselineGeneration = NO_MEASUREMENT_BASELINE,
            ),
        )
    }

    @Test
    fun `a sweep that began on a network needs no baseline`() {
        // Online at start: no baseline is awaited, so every callback is a handover.
        assertFalse(
            isOfflineMeasurementBaseline(
                callbackGeneration = 9,
                baselineGeneration = NO_MEASUREMENT_BASELINE,
            ),
        )
    }
}
