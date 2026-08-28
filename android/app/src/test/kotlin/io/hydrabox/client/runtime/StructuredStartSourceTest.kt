package io.hydrabox.client.runtime

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

class StructuredStartSourceTest {
    @Test
    fun `blank source defaults to ui`() {
        assertTrue(coreRuntimeServiceSource().contains("request.source.isNotBlank() -> request.source"))
        assertTrue(coreRuntimeServiceSource().contains("else -> \"ui\""))
    }

    @Test
    fun `tile source reaches event unless recovery takes precedence`() {
        assertTrue(coreRuntimeServiceSource().contains("recovery -> \"recovery\""))
        assertTrue(coreRuntimeServiceSource().contains("\"source\" to when"))
    }

    @Test
    fun `quick settings start supplies tile source`() {
        assertTrue(quickSettingsSource().contains("source = \"tile\""))
    }

    private fun quickSettingsSource(): String {
        return File(repositoryRoot(), "android/app/src/main/kotlin/io/hydrabox/client/HydraBoxQuickSettingsTileService.kt")
            .readText()
    }

    private fun coreRuntimeServiceSource(): String {
        return File(repositoryRoot(), "android/app/src/main/kotlin/io/hydrabox/client/runtime/CoreRuntimeService.kt")
            .readText()
    }

    private fun repositoryRoot(): File {
        var root = File(requireNotNull(System.getProperty("user.dir")))
        while (!File(root, "android/app/src/main/kotlin").isDirectory) {
            root = root.parentFile ?: error("root not found")
        }
        return root
    }
}
