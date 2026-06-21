package com.etonify.meow_client.singbox

import android.util.Log
import com.etonify.meow_client.MeowApplication
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object MeowDiagnostics {
    private const val MAX_LOG_BYTES = 256 * 1024
    private const val KEEP_LOG_BYTES = 160 * 1024
    private val lock = Any()
    private val timestampFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)

    private val diagnosticsFile: File
        get() = File(MeowApplication.application.filesDir, "meow-native-diagnostics.log")

    fun log(tag: String, message: String, error: Throwable? = null) {
        runCatching {
            synchronized(lock) {
                val line = buildString {
                    append('[')
                    append(timestampFormat.format(Date()))
                    append("] ")
                    append(tag)
                    append(": ")
                    append(message)
                    if (error != null) {
                        append('\n')
                        append(Log.getStackTraceString(error).trim())
                    }
                    append('\n')
                }
                val file = diagnosticsFile
                file.parentFile?.mkdirs()
                file.appendText(line)
                trimIfNeeded(file)
            }
        }
    }

    fun readTail(maxBytes: Int = KEEP_LOG_BYTES): String {
        return runCatching {
            synchronized(lock) {
                val file = diagnosticsFile
                if (!file.exists()) {
                    return ""
                }
                val bytes = file.readBytes()
                val start = (bytes.size - maxBytes.coerceAtLeast(0)).coerceAtLeast(0)
                bytes.copyOfRange(start, bytes.size).toString(Charsets.UTF_8).trim()
            }
        }.getOrDefault("")
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

    private fun trimIfNeeded(file: File) {
        if (file.length() <= MAX_LOG_BYTES) {
            return
        }
        val bytes = file.readBytes()
        val start = (bytes.size - KEEP_LOG_BYTES).coerceAtLeast(0)
        file.writeBytes(bytes.copyOfRange(start, bytes.size))
    }
}
