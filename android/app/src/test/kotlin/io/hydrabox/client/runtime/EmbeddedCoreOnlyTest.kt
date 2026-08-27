package io.hydrabox.client.runtime

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class EmbeddedCoreOnlyTest {
    @Test
    fun `native source is embedded`() {
        assertEquals("embedded", nativeSourceLabel())
    }

    @Test
    fun `runtime service does not use bundle manager`() {
        assertFalse(runtimeServiceSource().contains("CoreBundleManager"))
    }

    private fun runtimeServiceSource(): String {
        var root = File(requireNotNull(System.getProperty("user.dir")))
        while (!File(root, "android/app/src/main/kotlin").isDirectory) {
            root = root.parentFile ?: error("root not found")
        }
        return File(root, "android/app/src/main/kotlin/io/hydrabox/client/runtime/CoreRuntimeService.kt").readText()
    }
}
