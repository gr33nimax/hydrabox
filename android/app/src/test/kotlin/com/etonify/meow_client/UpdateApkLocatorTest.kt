package com.etonify.meow_client

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class UpdateApkLocatorTest {
    @Test
    fun `resolves an existing apk only from the private update directory`() {
        withFilesDirectory { filesDir ->
            val updates = filesDir.resolve("updates").apply { mkdirs() }
            val apk = updates.resolve("etonify-arm64.apk").apply { writeText("apk") }

            assertEquals(
                apk.canonicalFile,
                UpdateApkLocator.resolveExisting(filesDir, apk.name),
            )
        }
    }

    @Test
    fun `rejects traversal and files outside the update directory`() {
        withFilesDirectory { filesDir ->
            filesDir.resolve("updates").mkdirs()
            filesDir.resolve("outside.apk").writeText("apk")

            assertThrows(IllegalArgumentException::class.java) {
                UpdateApkLocator.resolveExisting(filesDir, "../outside.apk")
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
                UpdateApkLocator.resolveExisting(filesDir, "notes.txt")
            }
        }
    }

    private fun withFilesDirectory(block: (java.io.File) -> Unit) {
        val root = Files.createTempDirectory("etonify-update-apk-test").toFile()
        try {
            block(root.resolve("files").apply { mkdirs() })
        } finally {
            root.deleteRecursively()
        }
    }
}
