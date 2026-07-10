package com.etonify.meow_client.singbox

import android.util.Log
import com.etonify.meow_client.MeowApplication
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

object MeowDiagnostics {
    private const val MAX_LOG_BYTES = 256 * 1024
    private const val KEEP_LOG_BYTES = 160 * 1024
    private const val CRASH_LOG_BYTES = 64 * 1024
    private const val FLUSH_DELAY_MS = 250L
    private const val IMMEDIATE_FLUSH_CHARS = 8 * 1024
    private val fileLock = Any()
    private val pendingLock = Any()
    private val pendingLines = StringBuilder()
    private val flushScheduled = AtomicBoolean(false)
    private val writer = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "MeowDiagnosticsWriter").apply { isDaemon = true }
    }
    private val timestampFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)

    private val diagnosticsFile: File
        get() = File(MeowApplication.application.filesDir, "meow-native-diagnostics.log")

    fun log(tag: String, message: String, error: Throwable? = null) {
        runCatching {
            val flushNow = synchronized(pendingLock) {
                val safeMessage = MeowLogSanitizer.redact(message)
                val line = buildString {
                    append('[')
                    append(timestampFormat.format(Date()))
                    append("] ")
                    append(tag)
                    append(": ")
                    append(safeMessage)
                    if (error != null) {
                        append('\n')
                        append(MeowLogSanitizer.redact(Log.getStackTraceString(error).trim()))
                    }
                    append('\n')
                }
                pendingLines.append(line)
                pendingLines.length >= IMMEDIATE_FLUSH_CHARS || error != null
            }
            if (flushNow) {
                writer.execute(::flushPending)
            } else if (flushScheduled.compareAndSet(false, true)) {
                writer.schedule(::flushPending, FLUSH_DELAY_MS, TimeUnit.MILLISECONDS)
            }
        }
    }

    fun readTail(maxBytes: Int = KEEP_LOG_BYTES): String {
        flushPendingBlocking()
        return runCatching {
            synchronized(fileLock) {
                val file = diagnosticsFile
                if (!file.exists()) {
                    return ""
                }
                MeowLogSanitizer.redact(readFileTail(file, maxBytes))
            }
        }.getOrDefault("")
    }

    fun readCrashReportTail(maxBytes: Int = CRASH_LOG_BYTES): String {
        return runCatching {
            synchronized(fileLock) {
                val workingDir = File(
                    MeowApplication.application.getExternalFilesDir(null)
                        ?: MeowApplication.application.filesDir,
                    "singbox-work",
                )
                val report = workingDir.listFiles()
                    ?.filter { it.isFile && it.name.startsWith("CrashReport-") && it.length() > 0L }
                    ?.maxByOrNull { it.lastModified() }
                    ?: return ""
                MeowLogSanitizer.redact(
                    "file=${report.name} modifiedAtMillis=${report.lastModified()}\n" +
                        readFileTail(report, maxBytes),
                )
            }
        }.getOrDefault("")
    }

    fun readLatestOomReportMetadata(): String {
        return runCatching {
            synchronized(fileLock) {
                val workingDir = File(
                    MeowApplication.application.getExternalFilesDir(null)
                        ?: MeowApplication.application.filesDir,
                    "singbox-work/oom_reports",
                )
                val metadata = workingDir.walkTopDown()
                    .filter { it.isFile && it.name == "metadata.json" }
                    .maxByOrNull { it.lastModified() }
                    ?: return ""
                MeowLogSanitizer.redact(metadata.readText().trim())
            }
        }.getOrDefault("")
    }

    private fun flushPendingBlocking() {
        runCatching {
            writer.submit(::flushPending).get(1, TimeUnit.SECONDS)
        }
    }

    private fun flushPending() {
        val payload = synchronized(pendingLock) {
            if (pendingLines.isEmpty()) {
                flushScheduled.set(false)
                return
            }
            pendingLines.toString().also {
                pendingLines.setLength(0)
                flushScheduled.set(false)
            }
        }
        runCatching {
            synchronized(fileLock) {
                val file = diagnosticsFile
                file.parentFile?.mkdirs()
                file.appendText(payload)
                trimIfNeeded(file)
            }
        }
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
        var start = (bytes.size - KEEP_LOG_BYTES).coerceAtLeast(0)
        while (start < bytes.size && start > 0 && bytes[start - 1] != '\n'.code.toByte()) {
            start++
        }
        file.writeBytes(bytes.copyOfRange(start, bytes.size))
    }

    private fun readFileTail(file: File, maxBytes: Int): String {
        val bytes = file.readBytes()
        var start = (bytes.size - maxBytes.coerceAtLeast(0)).coerceAtLeast(0)
        if (start > 0) {
            while (start < bytes.size && bytes[start - 1] != '\n'.code.toByte()) {
                start++
            }
        }
        return bytes.copyOfRange(start, bytes.size).toString(Charsets.UTF_8).trim()
    }
}
