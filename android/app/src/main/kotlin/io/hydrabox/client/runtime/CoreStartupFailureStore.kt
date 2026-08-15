package io.hydrabox.client.runtime

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.FileOutputStream

/**
 * Small process-independent marker for failures that happen before the core
 * binder becomes reachable. It intentionally contains no exception text,
 * configuration, paths, endpoints, or other user data.
 */
data class CoreStartupFailure(
    val code: String,
    val stage: String,
    val loadedSource: String,
    val occurredAtMillis: Long,
) {
    val safeMessage: String
        get() = when (stage) {
            "native_setup" -> "HydraCore could not initialize its native runtime."
            "contract" -> "HydraCore did not provide a compatible runtime contract."
            "controller" -> "HydraCore could not initialize its runtime controller."
            "config_recovery" -> "HydraCore could not recover the previous runtime configuration."
            "snapshot" -> "HydraCore could not create its initial runtime snapshot."
            else -> "HydraCore could not finish starting."
        }

    fun toException(): CoreRuntimeException = CoreRuntimeException(
        code = code,
        stage = stage,
        retryable = false,
        message = safeMessage,
    )
}

class CoreStartupFailureStore(context: Context) {
    private val marker = File(
        File(context.noBackupFilesDir, "hydracore").apply { mkdirs() },
        MARKER_NAME,
    )

    /**
     * Written before each unsafe startup stage. A native abort or an OEM kill
     * cannot run a catch block, so the pending stage itself is the crash marker.
     */
    fun markStage(
        stage: String,
        loadedSource: String,
        nowMillis: Long = System.currentTimeMillis(),
    ) {
        val normalizedStage = normalizeStage(stage)
        write(
            CoreStartupFailure(
                code = "core.startup.$normalizedStage",
                stage = normalizedStage,
                loadedSource = normalizeSource(loadedSource),
                occurredAtMillis = nowMillis,
            ),
        )
    }

    fun readFresh(
        nowMillis: Long = System.currentTimeMillis(),
        maxAgeMillis: Long = MAX_AGE_MILLIS,
    ): CoreStartupFailure? = runCatching {
        if (!marker.isFile) return null
        val fields = marker.readLines()
            .mapNotNull { line ->
                val separator = line.indexOf('=')
                if (separator <= 0) null
                else line.substring(0, separator) to line.substring(separator + 1)
            }
            .toMap()
        if (fields["schema"] != SCHEMA_VERSION.toString()) return null
        val stage = normalizeStage(fields["stage"].orEmpty())
        val occurredAtMillis = fields["occurredAtMillis"]?.toLongOrNull() ?: return null
        val age = nowMillis - occurredAtMillis
        if (age !in 0..maxAgeMillis) return null
        CoreStartupFailure(
            code = "core.startup.$stage",
            stage = stage,
            loadedSource = normalizeSource(fields["loadedSource"].orEmpty()),
            occurredAtMillis = occurredAtMillis,
        )
    }.getOrNull()

    fun clear() {
        runCatching { if (marker.exists()) marker.delete() }
    }

    private fun write(failure: CoreStartupFailure) {
        marker.parentFile?.let { require(it.mkdirs() || it.isDirectory) }
        val atomic = AtomicFile(marker)
        var output: FileOutputStream? = null
        try {
            output = atomic.startWrite()
            output.write(
                buildString {
                    append("schema=").append(SCHEMA_VERSION).append('\n')
                    append("stage=").append(failure.stage).append('\n')
                    append("loadedSource=").append(failure.loadedSource).append('\n')
                    append("occurredAtMillis=").append(failure.occurredAtMillis).append('\n')
                }.toByteArray(Charsets.UTF_8),
            )
            atomic.finishWrite(output)
        } catch (error: Throwable) {
            output?.let(atomic::failWrite)
            throw error
        }
    }

    companion object {
        private const val SCHEMA_VERSION = 1
        private const val MARKER_NAME = "startup-failure-v1.txt"
        private const val MAX_AGE_MILLIS = 5 * 60 * 1000L
        private val ALLOWED_STAGES = setOf(
            "native_setup",
            "contract",
            "controller",
            "config_recovery",
            "snapshot",
        )
        private val ALLOWED_SOURCES = setOf("none", "active", "embedded")

        private fun normalizeStage(value: String): String =
            value.trim().lowercase().takeIf(ALLOWED_STAGES::contains) ?: "unknown"

        private fun normalizeSource(value: String): String =
            value.trim().lowercase().takeIf(ALLOWED_SOURCES::contains) ?: "none"
    }
}
