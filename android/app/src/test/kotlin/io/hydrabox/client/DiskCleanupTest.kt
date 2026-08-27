package io.hydrabox.client

import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Test

class DiskCleanupTest {
    @Test
    fun `stale core bundle directories exclude runtime data`() {
        val root = createTempDirectory("hydrabox-cleanup").toFile()
        try {
            File(root, "hydracore").mkdir()
            File(root, "core-config-recovery").mkdir()
            File(root, "singbox-config.json").writeText("config")
            File(root, "runtime-desired.txt").writeText("desired")

            assertEquals(listOf("hydracore"), staleCoreBundleDirs(root).map(File::getName))
        } finally {
            root.deleteRecursively()
        }
    }
}
