package io.hydrabox.client.singbox

import org.junit.Assert.assertEquals
import org.junit.Test

class NetworkCallbackTimestampTest {
    @Test fun `missing callback is reported as minus one`() = assertEquals(-1L, msSinceLastCallback(10L, -1L))
    @Test fun `callback age is monotonic`() = assertEquals(7L, msSinceLastCallback(10L, 3L))
    @Test fun `clock anomalies clamp to zero`() = assertEquals(0L, msSinceLastCallback(3L, 10L))
}
