package io.hydrabox.client.runtime

import com.google.protobuf.ByteString
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UtilityAsyncTest {
    @Test
    fun `utility response completes its matching request`() {
        val registry = UtilityRequestRegistry()
        var result: Result<ByteArray>? = null

        assertTrue(registry.register("request") { result = it })
        assertTrue(registry.complete(response("request", "payload".toByteArray())))

        assertEquals("payload", result!!.getOrThrow().toString(Charsets.UTF_8))
    }

    @Test
    fun `duplicate request id is rejected`() {
        val registry = UtilityRequestRegistry()

        assertTrue(registry.register("request") { })
        assertFalse(registry.register("request") { })
    }

    @Test
    fun `expired request ignores its later response`() {
        val registry = UtilityRequestRegistry()
        var completed = false

        registry.register("request") { completed = true }
        registry.remove("request")

        assertFalse(registry.complete(response("request", "payload".toByteArray())))
        assertFalse(completed)
    }

    private fun response(id: String, payload: ByteArray): CoreRuntimeProtocol.CoreUtilityResponse =
        CoreRuntimeProtocol.CoreUtilityResponse.newBuilder()
            .setRequestId(id)
            .setPayload(ByteString.copyFrom(payload))
            .build()
}
