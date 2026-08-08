package io.hydrabox.client

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class UpdateApkLocatorTest {
    @Test
    fun `resolves an existing apk only from the private update directory`() {
        withFilesDirectory { filesDir ->
            val updates = filesDir.resolve("updates").apply { mkdirs() }
            val apk = updates.resolve("hydrabox-arm64.apk").apply { writeText("apk") }

            assertEquals(
                apk.canonicalFile,
                UpdateApkLocator.resolveSingleExisting(filesDir),
            )
        }
    }

    @Test
    fun `does not select an apk outside the update directory`() {
        withFilesDirectory { filesDir ->
            filesDir.resolve("updates").mkdirs()
            filesDir.resolve("outside.apk").writeText("apk")

            assertThrows(IllegalArgumentException::class.java) {
                UpdateApkLocator.resolveSingleExisting(filesDir)
            }
        }
    }

    @Test
    fun `rejects non apk files`() {
        withFilesDirectory { filesDir ->
            filesDir.resolve("updates").apply {
                mkdirs()
                resolve("notes.txt").writeText("not an apk")
            }

            assertThrows(IllegalArgumentException::class.java) {
                UpdateApkLocator.resolveSingleExisting(filesDir)
            }
        }
    }

    @Test
    fun `rejects an ambiguous update directory`() {
        withFilesDirectory { filesDir ->
            filesDir.resolve("updates").apply {
                mkdirs()
                resolve("hydrabox-arm64.apk").writeText("apk")
                resolve("hydrabox-universal.apk").writeText("apk")
            }

            assertThrows(IllegalArgumentException::class.java) {
                UpdateApkLocator.resolveSingleExisting(filesDir)
            }
        }
    }

    private fun withFilesDirectory(block: (java.io.File) -> Unit) {
        val root = Files.createTempDirectory("hydrabox-update-apk-test").toFile()
        try {
            block(root.resolve("files").apply { mkdirs() })
        } finally {
            root.deleteRecursively()
        }
    }
}
