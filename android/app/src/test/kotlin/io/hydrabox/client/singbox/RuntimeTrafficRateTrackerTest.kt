package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeTrafficRateTrackerTest {
    @Test
    fun derivesBothRatesFromCumulativeTotals() {
        val tracker = RuntimeTrafficRateTracker()
        tracker.update(0, 0, 100, 200, 1_000)

        val rates = tracker.update(0, 0, 300, 800, 2_000)

        assertEquals(200L, rates.uplink)
        assertEquals(600L, rates.downlink)
    }

    @Test
    fun scalesDeltasByActualElapsedTime() {
        val tracker = RuntimeTrafficRateTracker()
        tracker.update(0, 0, 0, 0, 1_000)

        val rates = tracker.update(0, 0, 250, 500, 1_500)

        assertEquals(500L, rates.uplink)
        assertEquals(1_000L, rates.downlink)
    }

    @Test
    fun keepsNativeRateWhenProvidedAndRejectsCounterRegression() {
        val tracker = RuntimeTrafficRateTracker()
        tracker.update(0, 0, 1_000, 2_000, 1_000)

        val rates = tracker.update(42, 84, 100, 200, 2_000)

        assertEquals(42L, rates.uplink)
        assertEquals(84L, rates.downlink)
    }

    @Test
    fun normalizesNativeIntervalBytesWithCounterTiming() {
        val tracker = RuntimeTrafficRateTracker()
        tracker.update(0, 0, 0, 0, 1_000)

        val rates = tracker.update(250, 500, 250, 500, 1_500)

        assertEquals(500L, rates.uplink)
        assertEquals(1_000L, rates.downlink)
    }

    @Test
    fun resetStartsANewCounterBaseline() {
        val tracker = RuntimeTrafficRateTracker()
        tracker.update(0, 0, 100, 200, 1_000)
        tracker.reset()

        val rates = tracker.update(0, 0, 500, 800, 2_000)

        assertEquals(0L, rates.uplink)
        assertEquals(0L, rates.downlink)
    }
}
