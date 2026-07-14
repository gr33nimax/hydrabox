package com.etonify.meow_client

import java.io.File
import java.util.Locale

internal object UpdateApkLocator {
    private const val DIRECTORY_NAME = "updates"

    fun resolveExisting(filesDir: File, requestedFileName: String): File {
        val fileName = requestedFileName.trim()
        require(fileName.isNotEmpty()) { "APK file name is empty." }
        require(
            fileName == File(fileName).name &&
                !fileName.contains('/') &&
                !fileName.contains('\\'),
        ) { "APK file name must not contain a path." }
        require(fileName.lowercase(Locale.ROOT).endsWith(".apk")) {
            "File is not an APK."
        }

        val updatesDirectory = File(filesDir, DIRECTORY_NAME).canonicalFile
        require(updatesDirectory.isDirectory) { "Update directory does not exist." }
        val file = updatesDirectory.listFiles()?.firstOrNull { candidate ->
            candidate.name == fileName && candidate.isFile
        } ?: throw IllegalArgumentException("APK file does not exist in the update directory.")
        val canonicalFile = file.canonicalFile
        require(canonicalFile.parentFile == updatesDirectory) {
            "APK file resolves outside the update directory."
        }
        return canonicalFile
    }
}
