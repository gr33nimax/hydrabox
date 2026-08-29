package io.hydrabox.client

import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProbeIsolationTest {
    @Test
    fun `probe error is separate from runtime state and error`() {
        val snapshot = CoreRuntimeProtocol.RuntimeSnapshot.newBuilder()
            .setState(CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING)
            .setLastError(error("runtime.failed", "Runtime failure"))
            .setProbeLastError(error("probe.start.failed", "Probe failure"))
            .build()

        val status = snapshot.toLegacyRuntimeMap()

        assertEquals("RUNTIME_STATE_RUNNING", status["state"])
        assertEquals("Runtime failure", status["lastError"])
        assertEquals("Probe failure", status["probeLastError"])
        assertEquals("probe.start.failed", status["probeErrorCode"])
    }

    @Test
    fun `selector failure does not use runtime failure path`() {
        val source = runtimeServiceSource()
        val selector = source.substringAfter("private fun selectOutbound(").substringBefore("private fun startProbe(")

        assertTrue(selector.contains("failCommand("))
        assertFalse(selector.contains("failRuntime("))
    }

    private fun error(code: String, message: String): CoreRuntimeProtocol.CoreError =
        CoreRuntimeProtocol.CoreError.newBuilder().setCode(code).setSafeMessage(message).build()

    private fun runtimeServiceSource(): String {
        var root = File(requireNotNull(System.getProperty("user.dir")))
        while (!File(root, "android/app/src/main/kotlin").isDirectory) {
            root = root.parentFile ?: error("root not found")
        }
        return File(root, "android/app/src/main/kotlin/io/hydrabox/client/runtime/CoreRuntimeService.kt").readText()
    }
}
