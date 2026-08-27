package io.hydrabox.client

import io.hydrabox.client.runtime.epochChangedEvent
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Test

class ProcessEpochTest {
    @Test
    fun `two snapshots with different epochs produce exactly one event`() {
        val first = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder().setProcessEpoch("first").build()
        val second = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder().setProcessEpoch("second").build()
        val events = listOfNotNull(
            epochChangedEvent(null, first),
            epochChangedEvent(first.processEpoch, second),
            epochChangedEvent(second.processEpoch, second),
        )

        assertEquals(1, events.size)
        assertEquals("epochChanged", events.single()["type"])
    }
}
