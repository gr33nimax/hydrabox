package io.hydrabox.client.runtime

import org.junit.Assert.assertEquals
import org.junit.Test

class CoreCapabilityContractTest {
    @Test
    fun `bundle API major follows the capability shape`() {
        val reduced = """{"features":{},"protocols":{}}""".toByteArray()
        val legacy =
            """{"features":{"call_vk_worker_hot_swap":true},"protocols":{}}"""
                .toByteArray()

        assertEquals(2, CoreCapabilityContract.bundleApiMajor(reduced))
        assertEquals(1, CoreCapabilityContract.bundleApiMajor(legacy))
    }
}
