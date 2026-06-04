package com.etonify.meow_client.singbox

import android.util.Log
import com.etonify.meow_client.MeowApplication
import java.io.File

object MeowDiagnostics {
    fun log(tag: String, message: String, error: Throwable? = null) {
        return
    }

    fun pruneLegacyRuntimeFiles() {
        val filesDir = runCatching {
            MeowApplication.application.getExternalFilesDir(null)
        }.getOrNull() ?: MeowApplication.application.filesDir
        val legacyFiles = listOf(
            File(filesDir, "meow-runtime.log"),
            File(filesDir, "meow-runtime.level"),
        )
        runCatching {
            for (file in legacyFiles) {
                if (file.exists()) {
                    file.delete()
                }
            }
        }
    }
}
