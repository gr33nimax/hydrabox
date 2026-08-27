package io.hydrabox.client

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.util.AtomicFile
import androidx.work.Configuration
import io.hydrabox.client.background.SubscriptionRefreshScheduler
import io.hydrabox.client.platform.AndroidProcessIdentity
import io.hydrabox.client.singbox.HydraBoxDiagnostics
import java.io.File
import java.io.FileOutputStream
import kotlin.system.exitProcess

internal fun staleCoreBundleDirs(root: File): List<File> =
    root.listFiles()?.filter { it.isDirectory && it.name == "hydracore" }.orEmpty()

class HydraBoxApplication : Application(), Configuration.Provider {
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().build()

    override fun onCreate() {
        super.onCreate()
        application = this
        val processName = AndroidProcessIdentity.current(this)
        if (processName == packageName) {
            SubscriptionRefreshScheduler.ensureScheduled(this)
            val preferences = getSharedPreferences("hydracore_bundle_cleanup_v1", Context.MODE_PRIVATE)
            if (!preferences.getBoolean("completed", false)) {
                staleCoreBundleDirs(noBackupFilesDir).forEach(File::deleteRecursively)
                preferences.edit().putBoolean("completed", true).apply()
            }
        }
        installUncaughtExceptionLogger()
        // Legacy native Happ crypt5 used an isolated process:
        // if (!processName.endsWith(":happ_crypto5_isolated")) {
        //     HydraBoxDiagnostics.pruneLegacyRuntimeFiles()
        // }
        // That bridge is excluded from build; the pure Dart crypt5 path has no extra process.
        HydraBoxDiagnostics.pruneLegacyRuntimeFiles()
        HydraBoxDiagnostics.log(
            "Application",
            "onCreate pid=${android.os.Process.myPid()} process=$processName",
        )
    }

    companion object {
        data class ServiceState(
            val pid: Int,
            val mode: String,
            val updatedAtMillis: Long,
        )

        data class RuntimeIntentState(
            val pid: Int,
            val mode: String,
            val reason: String,
            val updatedAtMillis: Long,
        )

        private const val RUNTIME_FLAGS_PREF = "hydrabox_runtime_flags"
        private const val FLAG_WAKE_LOCK = "wake_lock_enabled"
        private const val FLAG_HEARTBEAT = "network_heartbeat_enabled"
        private const val FLAG_HEARTBEAT_INTERVAL_SECONDS = "network_heartbeat_interval_seconds"
        private const val FLAG_PERFORMANCE_MODE = "performance_mode"
        private const val FLAG_MEMORY_LIMIT_ENABLED = "memory_limit_enabled"
        @Volatile
        private var uncaughtExceptionLoggerInstalled = false

        lateinit var application: HydraBoxApplication
        val connectivity: ConnectivityManager
            get() = application.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val configFile: File
            get() = File(application.filesDir, "singbox-config.json")
        val serviceStateFile: File
            get() = File(application.filesDir, "singbox-service-state.txt")
        val runtimeIntentFile: File
            get() = File(application.filesDir, "singbox-runtime-intent.txt")

        private val runtimeFlagsPrefs
            get() = application.getSharedPreferences(
                RUNTIME_FLAGS_PREF,
                Context.MODE_PRIVATE,
            )

        var wakeLockEnabled: Boolean
            get() = runtimeFlagsPrefs.getBoolean(FLAG_WAKE_LOCK, false)
            set(value) {
                runtimeFlagsPrefs.edit().putBoolean(FLAG_WAKE_LOCK, value).apply()
            }

        var networkHeartbeatEnabled: Boolean
            get() = runtimeFlagsPrefs.getBoolean(FLAG_HEARTBEAT, true)
            set(value) {
                runtimeFlagsPrefs.edit().putBoolean(FLAG_HEARTBEAT, value).apply()
            }

        var networkHeartbeatIntervalSeconds: Long
            get() = runtimeFlagsPrefs
                .getLong(FLAG_HEARTBEAT_INTERVAL_SECONDS, 180L)
                .coerceIn(15L, 300L)
            set(value) {
                runtimeFlagsPrefs.edit()
                    .putLong(FLAG_HEARTBEAT_INTERVAL_SECONDS, value.coerceIn(15L, 300L))
                    .apply()
            }

        var performanceMode: String
            get() {
                return when (runtimeFlagsPrefs.getString(FLAG_PERFORMANCE_MODE, "standard") ?: "standard") {
                    "cool" -> "standard"
                    "economy" -> "economy"
                    "balanced", "performance" -> "standard"
                    else -> "standard"
                }
            }
            set(value) {
                val normalized = when (value) {
                    "cool", "standard" -> "standard"
                    "economy" -> "economy"
                    "performance", "balanced" -> "standard"
                    else -> "standard"
                }
                runtimeFlagsPrefs.edit()
                    .putString(FLAG_PERFORMANCE_MODE, normalized)
                    .apply()
            }

        var memoryLimitEnabled: Boolean
            get() = runtimeFlagsPrefs.getBoolean(FLAG_MEMORY_LIMIT_ENABLED, true)
            set(value) {
                runtimeFlagsPrefs.edit()
                    .putBoolean(FLAG_MEMORY_LIMIT_ENABLED, value)
                    .apply()
            }

        private fun installUncaughtExceptionLogger() {
            if (uncaughtExceptionLoggerInstalled) return
            synchronized(this) {
                if (uncaughtExceptionLoggerInstalled) return
                val previous = Thread.getDefaultUncaughtExceptionHandler()
                Thread.setDefaultUncaughtExceptionHandler { thread, error ->
                    runCatching {
                        HydraBoxDiagnostics.log(
                            "UncaughtException",
                            "thread=${thread.name} pid=${android.os.Process.myPid()}",
                            error,
                        )
                    }
                    if (previous != null) {
                        previous.uncaughtException(thread, error)
                    } else {
                        android.os.Process.killProcess(android.os.Process.myPid())
                        exitProcess(10)
                    }
                }
                uncaughtExceptionLoggerInstalled = true
            }
        }

        fun writeServiceState(mode: String) {
            val pid = android.os.Process.myPid()
            val updatedAtMillis = System.currentTimeMillis()
            writeAtomicText(
                serviceStateFile,
                buildString {
                    append("pid=")
                    append(pid)
                    append('\n')
                    append("mode=")
                    append(mode)
                    append('\n')
                    append("updatedAtMillis=")
                    append(updatedAtMillis)
                    append('\n')
                },
            )
            HydraBoxDiagnostics.log(
                "Application",
                "writeServiceState pid=$pid mode=$mode updatedAtMillis=$updatedAtMillis",
            )
        }

        fun writeRuntimeIntent(mode: String, reason: String) {
            val pid = android.os.Process.myPid()
            val updatedAtMillis = System.currentTimeMillis()
            writeAtomicText(
                runtimeIntentFile,
                buildString {
                    append("pid=")
                    append(pid)
                    append('\n')
                    append("mode=")
                    append(mode)
                    append('\n')
                    append("reason=")
                    append(reason)
                    append('\n')
                    append("updatedAtMillis=")
                    append(updatedAtMillis)
                    append('\n')
                },
            )
            HydraBoxDiagnostics.log(
                "Application",
                "writeRuntimeIntent pid=$pid mode=$mode reason=$reason updatedAtMillis=$updatedAtMillis",
            )
        }

        fun clearServiceState() {
            val deleted = runCatching {
                !serviceStateFile.exists() || serviceStateFile.delete()
            }.getOrDefault(false)
            HydraBoxDiagnostics.log("Application", "clearServiceState deleted=$deleted")
        }

        fun clearRuntimeIntent() {
            val deleted = runCatching {
                !runtimeIntentFile.exists() || runtimeIntentFile.delete()
            }.getOrDefault(false)
            HydraBoxDiagnostics.log("Application", "clearRuntimeIntent deleted=$deleted")
        }

        fun readServiceState(): ServiceState? {
            return runCatching {
                if (!serviceStateFile.exists()) {
                    return null
                }
                var pid = -1
                var mode = ""
                var updatedAtMillis = 0L
                for (line in serviceStateFile.readLines()) {
                    val index = line.indexOf('=')
                    if (index <= 0) continue
                    val key = line.substring(0, index)
                    val value = line.substring(index + 1)
                    when (key) {
                        "pid" -> pid = value.toIntOrNull() ?: -1
                        "mode" -> mode = value
                        "updatedAtMillis" -> updatedAtMillis = value.toLongOrNull() ?: 0L
                    }
                }
                if (pid <= 0 || mode.isBlank()) {
                    null
                } else {
                    ServiceState(pid = pid, mode = mode, updatedAtMillis = updatedAtMillis)
                }
            }.getOrNull()
        }

        fun readRuntimeIntent(): RuntimeIntentState? {
            return runCatching {
                if (!runtimeIntentFile.exists()) {
                    return null
                }
                var pid = -1
                var mode = ""
                var reason = ""
                var updatedAtMillis = 0L
                for (line in runtimeIntentFile.readLines()) {
                    val index = line.indexOf('=')
                    if (index <= 0) continue
                    val key = line.substring(0, index)
                    val value = line.substring(index + 1)
                    when (key) {
                        "pid" -> pid = value.toIntOrNull() ?: -1
                        "mode" -> mode = value
                        "reason" -> reason = value
                        "updatedAtMillis" -> updatedAtMillis = value.toLongOrNull() ?: 0L
                    }
                }
                if (pid <= 0 || mode.isBlank()) {
                    null
                } else {
                    RuntimeIntentState(
                        pid = pid,
                        mode = mode,
                        reason = reason,
                        updatedAtMillis = updatedAtMillis,
                    )
                }
            }.getOrNull()
        }

        fun describeRecordedServiceState(): String {
            val state = readServiceState()
            if (state == null) {
                return "state=missing"
            }
            val cmdline = runCatching {
                File("/proc/${state.pid}/cmdline")
                    .readText()
                    .replace('\u0000', ' ')
                    .trim()
            }.getOrDefault("")
            val alive = cmdline.contains(application.packageName)
            return buildString {
                append("statePid=")
                append(state.pid)
                append(" mode=")
                append(state.mode)
                append(" updatedAtMillis=")
                append(state.updatedAtMillis)
                append(" alive=")
                append(alive)
                if (cmdline.isNotEmpty()) {
                    append(" cmdline=")
                    append(cmdline)
                }
            }
        }

        fun describeRuntimeIntent(): String {
            val state = readRuntimeIntent()
            if (state == null) {
                return "intent=missing"
            }
            val ageMs = System.currentTimeMillis() - state.updatedAtMillis
            return buildString {
                append("intentPid=")
                append(state.pid)
                append(" mode=")
                append(state.mode)
                append(" reason=")
                append(state.reason)
                append(" updatedAtMillis=")
                append(state.updatedAtMillis)
                append(" ageMs=")
                append(ageMs)
                append(" fresh=")
                append(ageMs >= 0L)
            }
        }

        fun isRecordedServiceAlive(mode: String? = null): Boolean {
            val state = readServiceState() ?: return false
            if (mode != null && state.mode != mode) {
                return false
            }
            val cmdline = runCatching {
                File("/proc/${state.pid}/cmdline")
                    .readText()
                    .replace('\u0000', ' ')
                    .trim()
            }.getOrDefault("")
            return cmdline.contains(application.packageName)
        }

        fun isRuntimeIntentFresh(mode: String? = null): Boolean {
            val state = readRuntimeIntent() ?: return false
            if (mode != null && state.mode != mode) {
                return false
            }
            // The file represents the user's desired runtime state, not a
            // short retry token. It remains valid until an explicit stop
            // clears it, allowing START_STICKY to recover after an overnight
            // low-memory or OEM process kill.
            return System.currentTimeMillis() >= state.updatedAtMillis
        }

        private fun writeAtomicText(file: File, content: String) {
            require(file.parentFile?.let { it.mkdirs() || it.isDirectory } != false)
            val atomic = AtomicFile(file)
            var output: FileOutputStream? = null
            try {
                output = atomic.startWrite()
                output.write(content.toByteArray(Charsets.UTF_8))
                atomic.finishWrite(output)
            } catch (error: Throwable) {
                output?.let(atomic::failWrite)
                throw error
            }
        }
    }
}
