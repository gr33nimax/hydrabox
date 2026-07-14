package com.etonify.meow_client

import java.io.File

internal object UpdateApkLocator {
    private const val DIRECTORY_NAME = "updates"

    fun resolveSingleExisting(filesDir: File): File {
        val updatesDirectory = File(filesDir, DIRECTORY_NAME).canonicalFile
        require(updatesDirectory.isDirectory) { "Update directory does not exist." }
        val candidates = updatesDirectory.listFiles()
            ?.filter { candidate ->
                candidate.isFile && candidate.name.endsWith(".apk", ignoreCase = true)
            }
            .orEmpty()
        require(candidates.size == 1) {
            if (candidates.isEmpty()) {
                "APK file does not exist in the update directory."
            } else {
                "Multiple APK files exist in the update directory."
            }
        }
        val file = candidates.single()
        val canonicalFile = file.canonicalFile
        require(canonicalFile.parentFile == updatesDirectory) {
            "APK file resolves outside the update directory."
        }
        return canonicalFile
    }
}
