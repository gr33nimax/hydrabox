package io.hydrabox.client.singbox

import android.content.pm.ApplicationInfo
import io.hydrabox.client.HydraBoxApplication
import io.hydrabox.client.platform.AndroidProcessIdentity
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.SetupOptions
import java.io.File

/** The only setup entry point allowed to initialize gomobile/libbox. */
object NativeCoreEnvironment {
    @Volatile
    private var ready = false

    fun ensureSetup() {
        if (ready) return
        synchronized(this) {
            if (ready) return
            val app = HydraBoxApplication.application
            val processName = AndroidProcessIdentity.current(app)
            check(processName.endsWith(":core") || processName.endsWith(":core_probe")) {
                "HydraCore cannot be initialized in the Android UI process"
            }
            HydraBoxDiagnostics.log(
                "NativeCoreEnvironment",
                "setup begin pid=${android.os.Process.myPid()} process=$processName",
            )
            val baseDir = File(app.filesDir, "singbox-base").apply { mkdirs() }
            val workingDir = File(
                app.getExternalFilesDir(null) ?: app.filesDir,
                "singbox-work",
            ).apply { mkdirs() }
            val tempDir = File(app.cacheDir, "singbox-tmp").apply { mkdirs() }
            val setupOptions = SetupOptions().apply {
                basePath = baseDir.absolutePath
                workingPath = workingDir.absolutePath
                tempPath = tempDir.absolutePath
                logMaxLines = if (HydraBoxApplication.performanceMode == "performance") 3000 else 800
                debug = (app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            }
            Libbox.setup(setupOptions)
            Libbox.setMemoryLimit(HydraBoxApplication.memoryLimitEnabled)
            ready = true
            HydraBoxDiagnostics.log(
                "NativeCoreEnvironment",
                "setup complete pid=${android.os.Process.myPid()}",
            )
        }
    }
}
