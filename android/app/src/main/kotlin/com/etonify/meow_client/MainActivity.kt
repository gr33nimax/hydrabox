package com.etonify.meow_client

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.AtomicFile
import android.util.Log
import androidx.core.content.FileProvider
// Legacy Happ native crypt5 path is intentionally disabled. Crypt5/5.1 is now
// decrypted in Dart from extracted selector/key tables.
// import com.etonify.meow_client.happcrypto.Crypto5IsolatedService
import com.etonify.meow_client.singbox.MeowBoxService
import com.etonify.meow_client.singbox.MeowDefaultNetworkMonitor
import com.etonify.meow_client.singbox.MeowDiagnostics
import com.etonify.meow_client.singbox.MeowProxyService
import com.etonify.meow_client.singbox.MeowVpnPlatformInterface
import com.etonify.meow_client.singbox.MeowVpnService
import com.etonify.meow_client.singbox.SingboxController
import com.etonify.meow_client.generated.EndpointProbeRequestMessage
import com.etonify.meow_client.generated.EndpointProbeResultMessage
import com.etonify.meow_client.generated.FlutterError as PigeonFlutterError
import com.etonify.meow_client.generated.NetworkInterfaceStateMessage
import com.etonify.meow_client.generated.RuntimeFlagsMessage
import com.etonify.meow_client.generated.SingboxHostApi
import com.etonify.meow_client.generated.UrlTestRequestMessage
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.Libbox
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MeowMainActivity"
        private const val QUICK_TILE_LABEL_FILE = "quick_tile_label.txt"
    }
    private val vpnPrepareRequestCode = 2048
    private val exportDocumentRequestCode = 2049
    private val methodChannelName = "meow_client/singbox"
    private val eventChannelName = "meow_client/singbox_events"
    private val deepLinkMethodChannelName = "meow_client/deep_links"
    private val deepLinkEventChannelName = "meow_client/deep_link_events"
    // private val happCryptoMethodChannelName = "meow_client/happ_crypto"
    private var pendingPrepareResult: MethodChannel.Result? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportContent: String? = null
    private var deepLinkEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val subscriptionNetworkExecutor = Executors.newFixedThreadPool(2)
    private val appIconExecutor = Executors.newFixedThreadPool(3)

    private class PigeonMethodResult<T>(
        private val callback: (Result<T>) -> Unit,
        private val transform: (Any?) -> T,
    ) : MethodChannel.Result {
        override fun success(result: Any?) {
            runCatching { transform(result) }
                .onSuccess { callback(Result.success(it)) }
                .onFailure { callback(Result.failure(it)) }
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            callback(Result.failure(PigeonFlutterError(errorCode, errorMessage, errorDetails)))
        }

        override fun notImplemented() {
            callback(
                Result.failure(
                    PigeonFlutterError(
                        "not_implemented",
                        "Android host method is not implemented.",
                        null,
                    ),
                ),
            )
        }
    }

    private fun unitResult(callback: (Result<Unit>) -> Unit): MethodChannel.Result =
        PigeonMethodResult(callback) { Unit }

    private fun boolResult(callback: (Result<Boolean>) -> Unit): MethodChannel.Result =
        PigeonMethodResult(callback) { result -> result == true }

    private fun nullableStringResult(callback: (Result<String?>) -> Unit): MethodChannel.Result =
        PigeonMethodResult(callback) { result -> result as String? }

    private fun errorResult(
        code: String,
        message: String?,
        details: Any? = null,
    ): Result<Nothing> = Result.failure(PigeonFlutterError(code, message, details))

    private fun pigeonMap(source: Map<*, *>): Map<String?, Any?> =
        source.entries.associate { entry -> entry.key?.toString() to entry.value }

    private fun pigeonMapList(source: List<Map<String, Any>>): List<Map<String?, Any?>?> =
        source.map { entry -> pigeonMap(entry) }

    private fun getOwnPackageInfoCompat(): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }

    private fun getAppVersionInfo(): Map<String, Any> {
        val info = getOwnPackageInfoCompat()
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return linkedMapOf(
            "packageName" to packageName,
            "versionName" to (info.versionName ?: ""),
            "versionCode" to versionCode,
        )
    }

    private fun canRequestApkInstalls(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openApkInstallSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun installDownloadedApk(path: String) {
        val file = File(path)
        require(file.exists() && file.isFile) { "APK file does not exist." }
        require(file.name.lowercase().endsWith(".apk")) { "File is not an APK." }
        if (!canRequestApkInstalls()) {
            openApkInstallSettings()
            throw IllegalStateException("APK install permission is not granted.")
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
        }
        startActivity(intent)
    }

    private fun inspectDownloadedApk(path: String): Map<String, Any> {
        val file = File(path)
        require(file.exists() && file.isFile) { "APK file does not exist." }
        require(file.name.lowercase().endsWith(".apk")) { "File is not an APK." }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        val archiveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                file.absolutePath,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(file.absolutePath, flags)
        } ?: return linkedMapOf("valid" to false)
        archiveInfo.applicationInfo?.apply {
            sourceDir = file.absolutePath
            publicSourceDir = file.absolutePath
        }
        val installedInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, flags)
        }
        val archiveVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            archiveInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            archiveInfo.versionCode.toLong()
        }
        return linkedMapOf(
            "valid" to true,
            "packageName" to archiveInfo.packageName,
            "installedPackageName" to packageName,
            "versionName" to (archiveInfo.versionName ?: ""),
            "versionCode" to archiveVersionCode,
            "minSdk" to (archiveInfo.applicationInfo?.minSdkVersion ?: 0),
            "targetSdk" to (archiveInfo.applicationInfo?.targetSdkVersion ?: 0),
            "deviceSdk" to Build.VERSION.SDK_INT,
            "signingCertificateSha256" to signingCertificateDigests(archiveInfo),
            "installedCertificateSha256" to signingCertificateDigests(installedInfo),
        )
    }

    private fun signingCertificateDigests(info: PackageInfo): List<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptyList()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures
        }
        return signatures
            .orEmpty()
            .map { signature ->
                MessageDigest.getInstance("SHA-256")
                    .digest(signature.toByteArray())
                    .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
            }
            .distinct()
    }

    private fun fetchUrlOnUnderlyingNetwork(
        rawUrl: String,
        headers: Map<String, String>,
        maxBytes: Int,
        timeoutMs: Int,
    ): Map<String, Any> {
        val url = URL(rawUrl)
        require(url.protocol == "http" || url.protocol == "https") {
            "Only HTTP and HTTPS URLs are supported."
        }
        val network = MeowDefaultNetworkMonitor.require()
        val connection = network.openConnection(url) as HttpURLConnection
        val boundedTimeout = timeoutMs.coerceIn(3_000, 60_000)
        val abortOnDeadline = Runnable { connection.disconnect() }
        mainHandler.postDelayed(abortOnDeadline, boundedTimeout.toLong())
        return try {
            connection.requestMethod = "GET"
            connection.instanceFollowRedirects = true
            connection.connectTimeout = boundedTimeout
            connection.readTimeout = boundedTimeout
            connection.useCaches = false
            for ((name, value) in headers) {
                if (name.isBlank() || name.any { it == '\r' || it == '\n' }) continue
                if (value.any { it == '\r' || it == '\n' }) continue
                connection.setRequestProperty(name, value)
            }
            val statusCode = connection.responseCode
            val declaredLength = connection.contentLengthLong
            require(declaredLength <= maxBytes || declaredLength < 0) {
                "Response is larger than $maxBytes bytes."
            }
            val stream = if (statusCode in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
            }
            val output = ByteArrayOutputStream(
                declaredLength.coerceIn(0, maxBytes.toLong()).toInt(),
            )
            stream?.use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var total = 0
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                    require(total <= maxBytes) { "Response is larger than $maxBytes bytes." }
                    output.write(buffer, 0, read)
                }
            }
            val responseHeaders = linkedMapOf<String, String>()
            for ((name, values) in connection.headerFields) {
                if (name == null || values.isNullOrEmpty()) continue
                responseHeaders[name.lowercase()] = values.joinToString(", ")
            }
            linkedMapOf(
                "statusCode" to statusCode,
                "body" to output.toString(Charsets.UTF_8.name()),
                "headers" to responseHeaders,
                "finalUrl" to connection.url.toString(),
                "network" to MeowDefaultNetworkMonitor.describeNetwork(network),
            )
        } finally {
            mainHandler.removeCallbacks(abortOnDeadline)
            connection.disconnect()
        }
    }

    private fun buildImportDeepLinkPayload(uri: Uri?): Map<String, Any?>? {
        if (uri == null) {
            return null
        }
        val scheme = uri.scheme?.lowercase() ?: return null
        fun importPayload(sourceType: String, url: String, name: String = ""): Map<String, Any?> =
            linkedMapOf(
                "scheme" to scheme,
                "sourceType" to sourceType,
                "url" to url,
                "name" to name,
            )

        if (scheme == "happ") {
            val host = uri.host?.lowercase().orEmpty()
            val path = uri.path.orEmpty().trim('/').lowercase()
            if (
                host == "routing" ||
                path == "routing" ||
                path.startsWith("routing/")
            ) {
                return null
            }
            val importUrl = uri.getQueryParameter("url")?.trim().orEmpty()
            val name = uri.getQueryParameter("name")?.trim().orEmpty()
            val sourceType = when {
                host == "add" || path == "add" || path.startsWith("add/") -> "happAdd"
                host == "crypt" || host == "crypt2" || host == "crypt3" ||
                    host == "crypt4" || host == "crypt5" ||
                    path == "crypt" || path == "crypt2" || path == "crypt3" ||
                    path == "crypt4" || path == "crypt5" ||
                    path.startsWith("crypt/") || path.startsWith("crypt2/") ||
                    path.startsWith("crypt3/") || path.startsWith("crypt4/") ||
                    path.startsWith("crypt5/") -> "happCrypto"
                else -> "happAdd"
            }
            return importPayload(
                sourceType,
                if (importUrl.isNotBlank()) importUrl else uri.toString(),
                name,
            )
        }
        if (scheme == "sing-box") {
            val host = uri.host?.lowercase().orEmpty()
            val path = uri.path.orEmpty().trim('/').lowercase()
            if (host != "import-remote-profile" && path != "import-remote-profile") {
                return null
            }
            val url = uri.getQueryParameter("url")?.trim().orEmpty()
            if (url.isBlank()) {
                return null
            }
            val name = uri.getQueryParameter("name")?.trim().orEmpty()
            return importPayload("singBoxRemoteProfile", url, name)
        }
        if (scheme != "etonify" && scheme != "meowvpn") {
            return null
        }
        val host = uri.host?.lowercase().orEmpty()
        val path = uri.path.orEmpty().trim('/').lowercase()
        if (host != "import" && path != "import") {
            return null
        }
        val url = uri.getQueryParameter("url")?.trim().orEmpty()
        if (url.isBlank()) {
            return null
        }
        val name = uri.getQueryParameter("name")?.trim().orEmpty()
        return importPayload("etonifyImport", url, name)
    }

    private fun dispatchImportDeepLink(intent: Intent?) {
        val payload = buildImportDeepLinkPayload(intent?.data) ?: return
        mainHandler.post {
            deepLinkEventSink?.success(payload)
        }
    }

    private fun writeConfigAtomically(config: String) {
        val target = MeowApplication.configFile
        val directory = target.parentFile ?: throw IllegalStateException("Config directory missing")
        directory.mkdirs()
        val atomicFile = AtomicFile(target)
        var output: FileOutputStream? = null
        try {
            output = atomicFile.startWrite()
            output.write(config.toByteArray(Charsets.UTF_8))
            atomicFile.finishWrite(output)
        } catch (error: Throwable) {
            output?.let(atomicFile::failWrite)
            throw error
        }
    }

    private fun writeConfigAndDispatch(
        config: String,
        result: MethodChannel.Result,
        onSuccess: () -> Unit,
    ) {
        ioExecutor.execute {
            val error = runCatching {
                writeConfigAtomically(config)
            }.exceptionOrNull()
            mainHandler.post {
                if (error != null) {
                    result.error("write_config_failed", error.message, null)
                    return@post
                }
                onSuccess()
            }
        }
    }

    private fun withPreparedConfig(
        result: MethodChannel.Result,
        onSuccess: () -> Unit,
    ) {
        ioExecutor.execute {
            val error = runCatching {
                val target = MeowApplication.configFile
                if (!target.exists() || target.length() <= 0L) {
                    error("Config is empty")
                }
            }.exceptionOrNull()
            mainHandler.post {
                if (error != null) {
                    result.error("empty_config", error.message, null)
                    return@post
                }
                onSuccess()
            }
        }
    }

    private fun startServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun currentRuntimeModeForStop(): String {
        val controllerMode = SingboxController.serviceMode.trim().lowercase()
        if (controllerMode == "vpn" || controllerMode == "proxy") {
            return controllerMode
        }
        val recordedMode = MeowApplication.readServiceState()?.mode?.trim()?.lowercase().orEmpty()
        return if (recordedMode == "proxy") "proxy" else "vpn"
    }

    private fun runtimeStopTargetForMode(mode: String): Class<out android.app.Service> {
        return when (mode) {
            "proxy" -> MeowProxyService::class.java
            else -> MeowVpnService::class.java
        }
    }

    private fun runtimeCleanupTargets(
        primary: Class<out android.app.Service>,
    ): List<Class<out android.app.Service>> {
        val secondary = if (primary == MeowVpnService::class.java) {
            MeowProxyService::class.java
        } else {
            MeowVpnService::class.java
        }
        return listOf(primary, secondary)
    }

    private fun cleanupStoppedRuntimeState(
        reason: String,
        source: String,
        stopRequestedAtMillis: Long,
        targets: List<Class<out android.app.Service>>,
        force: Boolean,
    ): Boolean {
        val runtimeIntent = MeowApplication.readRuntimeIntent()
        val freshStartAfterStop =
            runtimeIntent != null &&
                runtimeIntent.updatedAtMillis > stopRequestedAtMillis &&
                MeowApplication.isRuntimeIntentFresh(runtimeIntent.mode)
        if (freshStartAfterStop) {
            MeowDiagnostics.log(
                TAG,
                "cleanupStoppedRuntimeState skipped fresh start reason=$reason source=$source " +
                    "intent=${MeowApplication.describeRuntimeIntent()}",
            )
            return false
        }
        if (force) {
            SingboxController.log(
                "warning",
                "force runtime cleanup reason=$reason source=$source " +
                    "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                    "activeOwner=${MeowBoxService.hasActiveRuntimeOwner(SingboxController.serviceMode)}",
            )
            MeowBoxService.requestStopAll("force_cleanup:$reason:$source")
            MeowDefaultNetworkMonitor.stop()
            SingboxController.forceMarkServiceStopped("force_cleanup:$reason:$source")
        }
        for (serviceClass in targets) {
            runCatching {
                stopService(Intent(this, serviceClass))
            }.onFailure {
                MeowDiagnostics.log(TAG, "stopService failed target=${serviceClass.simpleName}", it)
            }
        }
        MeowApplication.clearServiceState()
        MeowApplication.clearRuntimeIntent()
        MeowQuickSettingsTileService.requestRefresh(this)
        MeowDiagnostics.log(
            TAG,
            "cleanupStoppedRuntimeState completed reason=$reason source=$source force=$force " +
                "targets=${targets.joinToString { it.simpleName }}",
        )
        return true
    }

    private fun dispatchStopRuntime(reason: String, onComplete: (Boolean) -> Unit) {
        val modeAtRequest = currentRuntimeModeForStop()
        val primaryTarget = runtimeStopTargetForMode(modeAtRequest)
        val cleanupTargets = runtimeCleanupTargets(primaryTarget)
        val stopRequestedAtMillis = System.currentTimeMillis()
        MeowDiagnostics.log(
            TAG,
            "dispatchStopRuntime reason=$reason running=${SingboxController.running} " +
                "mode=${SingboxController.serviceMode} requestedMode=$modeAtRequest " +
                "primary=${primaryTarget.simpleName} cleanup=${cleanupTargets.joinToString { it.simpleName }}",
        )
        SingboxController.log(
            "warning",
            "android stop requested reason=$reason running=${SingboxController.running} " +
                "mode=${SingboxController.serviceMode}",
        )
        // Persist the user's stop intent before native cleanup. If Android
        // kills the process during cleanup, START_STICKY must not resurrect a
        // VPN the user has just stopped.
        MeowApplication.clearRuntimeIntent()
        MeowBoxService.requestStopForMode(modeAtRequest, "main_activity_stop:$reason")
        runCatching {
            startService(
                Intent(this, primaryTarget)
                    .setAction(MeowBoxService.ACTION_STOP)
                    .putExtra(MeowBoxService.EXTRA_STOP_REASON, reason),
            )
        }.onFailure {
            MeowDiagnostics.log(TAG, "ACTION_STOP failed target=${primaryTarget.simpleName}", it)
        }
        mainHandler.postDelayed({
            if (!SingboxController.running) {
                cleanupStoppedRuntimeState(
                    reason = reason,
                    source = "safety_delay",
                    stopRequestedAtMillis = stopRequestedAtMillis,
                    targets = cleanupTargets,
                    force = false,
                )
            } else {
                MeowDiagnostics.log(
                    TAG,
                    "dispatchStopRuntime safety stopService skipped reason=$reason " +
                        "running=${SingboxController.running} " +
                        "activeOwner=${MeowBoxService.hasActiveRuntimeOwner(modeAtRequest)} " +
                        "intent=${MeowApplication.describeRuntimeIntent()}",
                )
            }
        }, 1_200L)
        if (!SingboxController.running) {
            cleanupStoppedRuntimeState(
                reason = reason,
                source = "already_stopped",
                stopRequestedAtMillis = stopRequestedAtMillis,
                targets = cleanupTargets,
                force = false,
            )
            onComplete(true)
            return
        }
        SingboxController.awaitStopped { stopped ->
            if (!stopped) {
                val cleaned = cleanupStoppedRuntimeState(
                    reason = reason,
                    source = "await_timeout",
                    stopRequestedAtMillis = stopRequestedAtMillis,
                    targets = cleanupTargets,
                    force = true,
                )
                onComplete(cleaned || !SingboxController.running)
                return@awaitStopped
            }
            cleanupStoppedRuntimeState(
                reason = reason,
                source = "await_stopped",
                stopRequestedAtMillis = stopRequestedAtMillis,
                targets = cleanupTargets,
                force = false,
            )
            onComplete(true)
        }
    }

    private fun dispatchStartAfterConfigWrite(useVpn: Boolean, result: MethodChannel.Result) {
        Log.i(TAG, "start requested useVpn=$useVpn running=${SingboxController.running} mode=${SingboxController.serviceMode}")
        SingboxController.log(
            "info",
            "android start requested useVpn=$useVpn running=${SingboxController.running} mode=${SingboxController.serviceMode}",
        )
        MeowDiagnostics.log(
            TAG,
            "start requested useVpn=$useVpn running=${SingboxController.running} mode=${SingboxController.serviceMode}",
        )
        val targetMode = if (useVpn) "vpn" else "proxy"
        val targetService = if (useVpn) {
            MeowVpnService::class.java
        } else {
            MeowProxyService::class.java
        }
        if (SingboxController.running && SingboxController.serviceMode == targetMode) {
            val serviceIntent = Intent(this, targetService).setAction(MeowBoxService.ACTION_START)
            Log.i(TAG, "start forwarding idempotent ACTION_START mode=$targetMode")
            MeowDiagnostics.log(TAG, "start forwarding idempotent ACTION_START mode=$targetMode")
            startServiceCompat(serviceIntent)
            result.success(true)
            return
        }
        if (SingboxController.running && SingboxController.serviceMode != targetMode) {
            val currentService = if (SingboxController.serviceMode == "proxy") {
                MeowProxyService::class.java
            } else {
                MeowVpnService::class.java
            }
            val stopRequestedAtMillis = System.currentTimeMillis()
            val cleanupTargets = runtimeCleanupTargets(currentService)
            MeowDiagnostics.log(
                TAG,
                "issuing ACTION_STOP for mode switch currentMode=${SingboxController.serviceMode} targetMode=$targetMode currentService=${currentService.simpleName}",
            )
            MeowBoxService.requestStopForMode(
                SingboxController.serviceMode,
                "mode_switch_to_$targetMode",
            )
            startService(
                Intent(this, currentService)
                    .setAction(MeowBoxService.ACTION_STOP)
                    .putExtra(MeowBoxService.EXTRA_STOP_REASON, "mode_switch_to_$targetMode"),
            )
            SingboxController.awaitStopped { stopped ->
                if (!stopped) {
                    cleanupStoppedRuntimeState(
                        reason = "mode_switch_to_$targetMode",
                        source = "await_timeout",
                        stopRequestedAtMillis = stopRequestedAtMillis,
                        targets = cleanupTargets,
                        force = true,
                    )
                }
                val serviceIntent = Intent(this, targetService).setAction(MeowBoxService.ACTION_START)
                Log.i(TAG, "starting target service after mode switch target=${targetService.simpleName} stopped=$stopped")
                MeowDiagnostics.log(
                    TAG,
                    "starting target service after mode switch target=${targetService.simpleName} stopped=$stopped",
                )
                startServiceCompat(serviceIntent)
            }
        } else {
            val serviceIntent = Intent(this, targetService).setAction(MeowBoxService.ACTION_START)
            Log.i(TAG, "starting target service target=${targetService.simpleName}")
            MeowDiagnostics.log(TAG, "starting target service target=${targetService.simpleName}")
            startServiceCompat(serviceIntent)
        }
        result.success(true)
    }

    private fun dispatchApplyConfigAfterConfigWrite(
        useVpn: Boolean,
        restartCore: Boolean,
        result: MethodChannel.Result,
    ) {
        val targetMode = if (useVpn) "vpn" else "proxy"
        val serviceClass = if (useVpn) MeowVpnService::class.java else MeowProxyService::class.java
        Log.i(
            TAG,
            "applyConfig useVpn=$useVpn restartCore=$restartCore running=${SingboxController.running} mode=${SingboxController.serviceMode} target=${serviceClass.simpleName}",
        )
        SingboxController.log(
            "info",
            "android applyConfig requested useVpn=$useVpn restartCore=$restartCore " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode}",
        )
        MeowDiagnostics.log(
            TAG,
            "applyConfig useVpn=$useVpn restartCore=$restartCore running=${SingboxController.running} mode=${SingboxController.serviceMode} target=${serviceClass.simpleName}",
        )
        if (SingboxController.running && SingboxController.serviceMode == targetMode) {
            if (restartCore) {
                startService(Intent(this, serviceClass).setAction(MeowBoxService.ACTION_RESTART_CORE))
                result.success(true)
            } else {
                SingboxController.reloadService { reloadResult ->
                    reloadResult.onSuccess {
                        result.success(true)
                    }.onFailure {
                        result.error("reload_failed", it.message, null)
                    }
                }
            }
        } else {
            val serviceIntent = Intent(this, serviceClass).setAction(MeowBoxService.ACTION_START)
            startServiceCompat(serviceIntent)
            result.success(true)
        }
    }

    private fun writeQuickSettingsTileLabel(label: String?) {
        val normalized = label?.trim().orEmpty()
        val target = File(filesDir, QUICK_TILE_LABEL_FILE)
        runCatching {
            if (normalized.isEmpty()) {
                if (target.exists() && !target.delete()) {
                    Log.w(TAG, "failed to clear quick tile label ${target.absolutePath}")
                }
            } else {
                target.writeText(normalized, Charsets.UTF_8)
            }
            MeowQuickSettingsTileService.requestRefresh(this)
        }.onFailure { error ->
            Log.w(TAG, "failed to write quick tile label", error)
        }
    }

    private fun getHappCrypt5Support(): Map<String, Any> {
        val requiredAssets = listOf(
            "assets/happ_crypto/selectors.json",
            "assets/happ_crypto/expanded_rsa_keys.json",
            "assets/happ_crypto/crypt51_rsa_keys.json",
            "assets/happ_crypto/native_rsa_keys.json",
        )
        val missingAssets = requiredAssets.filterNot { assetPath ->
            runCatching {
                assets.open("flutter_assets/$assetPath").use { input ->
                    input.read() != -1
                }
            }.getOrDefault(false)
        }
        val supported = missingAssets.isEmpty()
        return linkedMapOf(
            "supported" to supported,
            "detail" to if (supported) {
                "Happ crypt5 compatibility assets are bundled."
            } else {
                "Happ crypt5 compatibility assets are unavailable in this build."
            },
            "abi" to Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "missingAssets" to missingAssets,
        )
    }

    private fun buildPerformanceSnapshot(): Map<String, Any?> {
        val memoryInfo = ActivityManager.MemoryInfo()
        val activityManager = getSystemService(ActivityManager::class.java)
        activityManager.getMemoryInfo(memoryInfo)
        val processMemory = activityManager.getProcessMemoryInfo(
            intArrayOf(android.os.Process.myPid()),
        ).firstOrNull()
        val runtime = Runtime.getRuntime()
        val batteryIntent = registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        val batteryTemperatureTenths = batteryIntent
            ?.getIntExtra("temperature", Int.MIN_VALUE)
            ?: Int.MIN_VALUE
        return linkedMapOf(
            "pid" to android.os.Process.myPid(),
            "runtimeMode" to MeowApplication.performanceMode,
            "wakeLockEnabled" to MeowApplication.wakeLockEnabled,
            "networkHeartbeatEnabled" to MeowApplication.networkHeartbeatEnabled,
            "networkHeartbeatIntervalSeconds" to MeowApplication.networkHeartbeatIntervalSeconds,
            "memoryLimitEnabled" to MeowApplication.memoryLimitEnabled,
            "serviceState" to MeowApplication.describeRecordedServiceState(),
            "runtimeIntent" to MeowApplication.describeRuntimeIntent(),
            "totalPssKb" to processMemory?.totalPss,
            "totalPrivateDirtyKb" to processMemory?.totalPrivateDirty,
            "nativeHeapAllocatedKb" to (Debug.getNativeHeapAllocatedSize() / 1024L),
            "nativeHeapSizeKb" to (Debug.getNativeHeapSize() / 1024L),
            "javaHeapUsedKb" to ((runtime.totalMemory() - runtime.freeMemory()) / 1024L),
            "javaHeapMaxKb" to (runtime.maxMemory() / 1024L),
            "systemAvailMemKb" to (memoryInfo.availMem / 1024L),
            "systemLowMemory" to memoryInfo.lowMemory,
            "batteryTemperatureC" to if (batteryTemperatureTenths == Int.MIN_VALUE) {
                null
            } else {
                batteryTemperatureTenths / 10.0
            },
        )
    }

    private fun cleanupStaleRuntimeStateIfNeeded(reason: String): Boolean {
        if (!SingboxController.running) {
            return false
        }
        val mode = currentRuntimeModeForStop()
        if (MeowBoxService.hasActiveRuntimeOwner(mode)) {
            return false
        }
        MeowDiagnostics.log(
            TAG,
            "cleanupStaleRuntimeStateIfNeeded reason=$reason mode=$mode " +
                "controllerMode=${SingboxController.serviceMode} " +
                "service=${MeowApplication.describeRecordedServiceState()} " +
                "intent=${MeowApplication.describeRuntimeIntent()}",
        )
        val primary = runtimeStopTargetForMode(mode)
        return cleanupStoppedRuntimeState(
            reason = "stale_runtime_$reason",
            source = "status",
            stopRequestedAtMillis = System.currentTimeMillis(),
            targets = runtimeCleanupTargets(primary),
            force = true,
        )
    }

    private fun runtimeStatusMap(): Map<String?, Any?> {
        val staleRuntimeStateCleaned = cleanupStaleRuntimeStateIfNeeded("status")
        val recordedState = MeowApplication.readServiceState()
        val runtimeIntent = MeowApplication.readRuntimeIntent()
        val recordedServiceAlive = MeowApplication.isRecordedServiceAlive()
        val activeRuntimeOwner = MeowBoxService.hasActiveRuntimeOwner(
            SingboxController.serviceMode.takeIf { it.isNotBlank() },
        )
        val nativeRecoveryPending =
            !SingboxController.running && (recordedServiceAlive || activeRuntimeOwner)
        return mapOf(
            "running" to SingboxController.running,
            "mode" to SingboxController.serviceMode,
            "uplink" to SingboxController.uplink,
            "downlink" to SingboxController.downlink,
            "uplinkTotal" to SingboxController.uplinkTotal,
            "downlinkTotal" to SingboxController.downlinkTotal,
            "recordedServiceAlive" to recordedServiceAlive,
            "recordedServiceMode" to recordedState?.mode,
            "recordedServicePid" to recordedState?.pid,
            "recordedServiceUpdatedAtMillis" to recordedState?.updatedAtMillis,
            "recordedServiceState" to MeowApplication.describeRecordedServiceState(),
            "activeRuntimeOwner" to activeRuntimeOwner,
            "nativeRecoveryPending" to nativeRecoveryPending,
            "staleRuntimeStateCleaned" to staleRuntimeStateCleaned,
            "runtimeIntentFresh" to MeowApplication.isRuntimeIntentFresh(),
            "runtimeIntentMode" to runtimeIntent?.mode,
            "runtimeIntentReason" to runtimeIntent?.reason,
            "runtimeIntentPid" to runtimeIntent?.pid,
            "runtimeIntentUpdatedAtMillis" to runtimeIntent?.updatedAtMillis,
            "runtimeIntentState" to MeowApplication.describeRuntimeIntent(),
        )
    }

    private fun logsWithNativeDiagnostics(content: String): String {
        val nativeDiagnostics = MeowDiagnostics.readTail()
        val crashReport = MeowDiagnostics.readCrashReportTail()
        val oomReport = MeowDiagnostics.readLatestOomReportMetadata()
        val runtimeSnapshot = runCatching { runtimeStatusMap().toString() }.getOrDefault("unavailable")
        val splitSnapshot = MeowVpnPlatformInterface.describeLastTunPackages()
        return buildString {
            append(content)
            if (content.isNotBlank()) {
                append("\n\n")
            }
            append("# Runtime snapshot\n")
            append(runtimeSnapshot)
            append("\n# Split tunnel snapshot\n")
            append(splitSnapshot)
            if (nativeDiagnostics.isNotBlank()) {
                append("\n# Native diagnostics\n")
                append(nativeDiagnostics)
            }
            if (crashReport.isNotBlank()) {
                append("\n# Native crash report\n")
                append(crashReport)
            }
            if (oomReport.isNotBlank()) {
                append("\n# Latest OOM report\n")
                append(oomReport)
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val packageManager = packageManager
        val installedApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getInstalledApplications(
                android.content.pm.PackageManager.ApplicationInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledApplications(0)
        }
        val launchIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val launcherApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launchIntent,
                android.content.pm.PackageManager.ResolveInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launchIntent, 0)
        }
        val launchablePackages = launcherApps
            .mapNotNull { it.activityInfo?.packageName }
            .toMutableSet()
        val appsByPackage = linkedMapOf<String, ApplicationInfo>()
        for (appInfo in installedApps) {
            appsByPackage[appInfo.packageName] = appInfo
        }
        for (packageName in launchablePackages) {
            if (appsByPackage.containsKey(packageName)) {
                continue
            }
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getApplicationInfo(
                        packageName,
                        android.content.pm.PackageManager.ApplicationInfoFlags.of(0),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getApplicationInfo(packageName, 0)
                }
            }.onSuccess { appInfo ->
                appsByPackage[appInfo.packageName] = appInfo
            }
        }
        return appsByPackage.values
            .asSequence()
            .filterNot { it.packageName == packageName }
            .map { appInfo ->
                val label = runCatching {
                    packageManager.getApplicationLabel(appInfo).toString().trim()
                }.getOrDefault(appInfo.packageName)
                val isSystem =
                    (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                        (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                linkedMapOf(
                    "packageName" to appInfo.packageName,
                    "label" to if (label.isNotEmpty()) label else appInfo.packageName,
                    "system" to isSystem,
                    "launchable" to (appInfo.packageName in launchablePackages),
                )
            }
            .sortedWith(
                compareByDescending<Map<String, Any>> { it["launchable"] == true }
                    .thenBy<Map<String, Any>> { it["system"] == true }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it["label"]?.toString().orEmpty() }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it["packageName"]?.toString().orEmpty() },
            )
            .toList()
    }

    private fun getInstalledAppIcon(packageName: String?, sizePx: Int?): ByteArray? {
        val normalizedPackage = packageName?.trim().orEmpty()
        if (!isAndroidPackageName(normalizedPackage) || normalizedPackage == this.packageName) {
            return null
        }
        val size = (sizePx ?: 48).coerceIn(24, 96)
        val icon = runCatching {
            packageManager.getApplicationIcon(normalizedPackage)
        }.getOrNull() ?: return null
        return renderDrawableToPng(icon, size)
    }

    private fun renderDrawableToPng(drawable: Drawable, size: Int): ByteArray? {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        return try {
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
            stream.toByteArray()
        } catch (error: Throwable) {
            MeowDiagnostics.log(TAG, "failed to render installed app icon", error)
            null
        } finally {
            bitmap.recycle()
        }
    }

    private fun isAndroidPackageName(value: String): Boolean =
        value.length <= 255 &&
            Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$").matches(value)

    /*
    private fun decodeHappCrypt5(link: String?, result: MethodChannel.Result) {
        val input = link?.trim().orEmpty()
        if (input.isBlank()) {
            result.error("empty_input", "Happ crypt5 link is empty", null)
            return
        }

        val serviceIntent = Intent(this, Crypto5IsolatedService::class.java).apply {
            putExtra(Crypto5IsolatedService.EXTRA_INPUT, input)
            putExtra(
                Crypto5IsolatedService.EXTRA_RECEIVER,
                object : ResultReceiver(mainHandler) {
                    override fun onReceiveResult(resultCode: Int, resultData: Bundle) {
                        if (resultCode == Crypto5IsolatedService.RESULT_SUCCESS) {
                            result.success(
                                resultData.getString(Crypto5IsolatedService.EXTRA_DECODED).orEmpty(),
                            )
                            return
                        }
                        result.error(
                            "decode_failed",
                            resultData.getString(Crypto5IsolatedService.EXTRA_ERROR)
                                ?: "Failed to decode Happ crypt5 link",
                            null,
                        )
                    }
                },
            )
        }

        try {
            val started = startService(serviceIntent)
            if (started == null) {
                result.error(
                    "service_unavailable",
                    "Happ crypt5 isolated service is unavailable",
                    null,
                )
            }
        } catch (error: Throwable) {
            result.error(
                "service_start_failed",
                error.message ?: error.toString(),
                null,
            )
        }
    }
    */

    private fun setupSingboxHostApi(binaryMessenger: BinaryMessenger) {
        SingboxHostApi.setUp(
            binaryMessenger,
            object : SingboxHostApi {
                override fun prepareVpn(
                    requiresVpn: Boolean,
                    callback: (Result<Boolean>) -> Unit,
                ) {
                    if (!requiresVpn) {
                        callback(Result.success(true))
                        return
                    }
                    val intent = VpnService.prepare(this@MainActivity)
                    Log.i(TAG, "prepareVpn requiresVpn=$requiresVpn granted=${intent == null}")
                    if (intent == null) {
                        callback(Result.success(true))
                    } else {
                        pendingPrepareResult = boolResult(callback)
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, vpnPrepareRequestCode)
                    }
                }

                override fun vpnPermissionStatus(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(Result.success(mapOf("granted" to (VpnService.prepare(this@MainActivity) == null))))
                }

                override fun start(config: String, useVpn: Boolean, callback: (Result<Unit>) -> Unit) {
                    if (config.isBlank()) {
                        callback(errorResult("empty_config", "Config is empty"))
                        return
                    }
                    val result = unitResult(callback)
                    writeConfigAndDispatch(config, result) {
                        dispatchStartAfterConfigWrite(useVpn, result)
                    }
                }

                override fun startPrepared(useVpn: Boolean, callback: (Result<Unit>) -> Unit) {
                    val result = unitResult(callback)
                    withPreparedConfig(result) {
                        dispatchStartAfterConfigWrite(useVpn, result)
                    }
                }

                override fun applyConfig(
                    config: String,
                    useVpn: Boolean,
                    restartCore: Boolean,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    if (config.isBlank()) {
                        callback(errorResult("empty_config", "Config is empty"))
                        return
                    }
                    val result = unitResult(callback)
                    writeConfigAndDispatch(config, result) {
                        dispatchApplyConfigAfterConfigWrite(useVpn, restartCore, result)
                    }
                }

                override fun applyPreparedConfig(
                    useVpn: Boolean,
                    restartCore: Boolean,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    val result = unitResult(callback)
                    withPreparedConfig(result) {
                        dispatchApplyConfigAfterConfigWrite(useVpn, restartCore, result)
                    }
                }

                override fun getConfigPath(callback: (Result<String>) -> Unit) {
                    callback(Result.success(MeowApplication.configFile.absolutePath))
                }

                override fun getRuntimeFlags(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(
                        Result.success(
                            mapOf(
                                "wakeLockEnabled" to MeowApplication.wakeLockEnabled,
                                "networkHeartbeatEnabled" to MeowApplication.networkHeartbeatEnabled,
                                "networkHeartbeatIntervalSeconds" to MeowApplication.networkHeartbeatIntervalSeconds,
                                "performanceMode" to MeowApplication.performanceMode,
                                "memoryLimitEnabled" to MeowApplication.memoryLimitEnabled,
                            ),
                        ),
                    )
                }

                override fun setRuntimeFlags(
                    flags: RuntimeFlagsMessage,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    var heartbeatChanged = false
                    flags.wakeLockEnabled?.let { MeowApplication.wakeLockEnabled = it }
                    flags.networkHeartbeatEnabled?.let {
                        MeowApplication.networkHeartbeatEnabled = it
                        heartbeatChanged = true
                    }
                    flags.networkHeartbeatIntervalSeconds?.let {
                        MeowApplication.networkHeartbeatIntervalSeconds = it
                        heartbeatChanged = true
                    }
                    flags.performanceMode?.let { MeowApplication.performanceMode = it }
                    flags.memoryLimitEnabled?.let { MeowApplication.memoryLimitEnabled = it }
                    if (heartbeatChanged) {
                        MeowDefaultNetworkMonitor.refreshHeartbeat()
                    }
                    callback(Result.success(Unit))
                }

                override fun reload(callback: (Result<Unit>) -> Unit) {
                    val serviceClass = when (SingboxController.serviceMode) {
                        "proxy" -> MeowProxyService::class.java
                        else -> MeowVpnService::class.java
                    }
                    startService(Intent(this@MainActivity, serviceClass).setAction(MeowBoxService.ACTION_RELOAD))
                    callback(Result.success(Unit))
                }

                override fun stop(reason: String, callback: (Result<Unit>) -> Unit) {
                    dispatchStopRuntime(reason) { stopped ->
                        if (stopped) {
                            callback(Result.success(Unit))
                        } else {
                            callback(errorResult("stop_timeout", "Native service stop timed out"))
                        }
                    }
                }

                override fun selectOutbound(
                    groupTag: String,
                    outboundTag: String,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    val normalizedTag = outboundTag.trim()
                    if (normalizedTag.isEmpty()) {
                        callback(errorResult("missing_outbound", "Outbound tag is empty"))
                        return
                    }
                    SingboxController.selectOutbound(groupTag.ifBlank { "select" }, normalizedTag) { selectionResult ->
                        selectionResult
                            .onSuccess { callback(Result.success(Unit)) }
                            .onFailure { callback(errorResult("select_failed", it.message)) }
                    }
                }

                override fun addOutbound(
                    selectorTag: String,
                    outboundJson: String,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    if (outboundJson.isBlank()) {
                        callback(errorResult("missing_outbound", "Outbound JSON is empty"))
                        return
                    }
                    SingboxController.addOutbound(selectorTag.ifBlank { "select" }, outboundJson) { addResult ->
                        addResult
                            .onSuccess { callback(Result.success(Unit)) }
                            .onFailure { callback(errorResult("add_outbound_failed", it.message)) }
                    }
                }

                override fun removeOutbound(
                    selectorTag: String,
                    outboundTag: String,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    val normalizedTag = outboundTag.trim()
                    if (normalizedTag.isEmpty()) {
                        callback(errorResult("missing_outbound", "Outbound tag is empty"))
                        return
                    }
                    SingboxController.removeOutbound(selectorTag.ifBlank { "select" }, normalizedTag) { removeResult ->
                        removeResult
                            .onSuccess { callback(Result.success(Unit)) }
                            .onFailure { callback(errorResult("remove_outbound_failed", it.message)) }
                    }
                }

                override fun urlTest(request: UrlTestRequestMessage, callback: (Result<Unit>) -> Unit) {
                    SingboxController.urlTest(
                        groupTag = request.groupTag.ifBlank { "select" },
                        targetOutboundTag = request.targetOutboundTag,
                        priorityOutboundTag = request.priorityOutboundTag,
                        excludeOutboundTag = request.excludeOutboundTag,
                        url = request.url,
                        timeoutMillis = request.timeoutMillis.toInt(),
                        concurrency = request.concurrency.toInt(),
                        deadlineMillis = request.deadlineMillis.toInt(),
                        force = request.force,
                    ) { urlTestResult ->
                        urlTestResult
                            .onSuccess { callback(Result.success(Unit)) }
                            .onFailure { callback(errorResult("urltest_failed", it.message)) }
                    }
                }

                override fun removeUrlTestOutbounds(
                    groupTag: String,
                    outboundTags: List<String?>,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    val normalizedGroupTag = groupTag.trim()
                    val normalizedTags = outboundTags.mapNotNull { it?.trim() }.filter { it.isNotEmpty() }
                    if (normalizedGroupTag.isEmpty()) {
                        callback(errorResult("missing_group", "Group tag is empty"))
                        return
                    }
                    if (normalizedTags.isEmpty()) {
                        callback(Result.success(Unit))
                        return
                    }
                    SingboxController.removeUrlTestOutbounds(normalizedGroupTag, normalizedTags) { updateResult ->
                        updateResult
                            .onSuccess { callback(Result.success(Unit)) }
                            .onFailure { callback(errorResult("remove_urltest_outbounds_failed", it.message)) }
                    }
                }

                override fun status(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(Result.success(runtimeStatusMap()))
                }

                override fun lookupOutboundExternalInfo(
                    outboundTag: String,
                    callback: (Result<Map<String?, Any?>>) -> Unit,
                ) {
                    val normalizedTag = outboundTag.trim()
                    if (normalizedTag.isEmpty()) {
                        callback(errorResult("lookup_outbound_external_info_failed", "Outbound tag is empty"))
                        return
                    }
                    SingboxController.lookupOutboundExternalInfo(normalizedTag) { lookupResult ->
                        lookupResult
                            .onSuccess { callback(Result.success(pigeonMap(it))) }
                            .onFailure { callback(errorResult("lookup_outbound_external_info_failed", it.message)) }
                    }
                }

                override fun getNetworkInterfaceState(
                    callback: (Result<NetworkInterfaceStateMessage>) -> Unit,
                ) {
                    val state = MeowDefaultNetworkMonitor.currentInterfaceState("host_api")
                    callback(
                        Result.success(
                            NetworkInterfaceStateMessage(
                                available = state.available,
                                interfaceName = state.interfaceName.ifBlank { null },
                                interfaceIndex = state.interfaceIndex.toLong(),
                                generation = state.generation,
                                reason = state.reason,
                                updatedAtMillis = state.updatedAtMillis,
                            ),
                        ),
                    )
                }

                override fun probeProxyEndpoint(
                    request: EndpointProbeRequestMessage,
                    callback: (Result<EndpointProbeResultMessage>) -> Unit,
                ) {
                    SingboxController.probeProxyEndpoint(
                        tag = request.tag,
                        host = request.host,
                        port = request.port.toInt(),
                        timeoutMs = request.timeoutMs.toInt(),
                    ) { probeResult ->
                        probeResult
                            .onSuccess { value ->
                                callback(
                                    Result.success(
                                        EndpointProbeResultMessage(
                                            tag = value["tag"]?.toString().orEmpty(),
                                            reachable = value["reachable"] == true,
                                            latencyMs = (value["latencyMs"] as? Number)?.toLong(),
                                            errorCode = value["errorCode"]?.toString()?.takeIf { it.isNotBlank() },
                                            checkedAtMillis =
                                                (value["checkedAtMillis"] as? Number)?.toLong()
                                                    ?: System.currentTimeMillis(),
                                            protectedSocket = value["protectedSocket"] == true,
                                        ),
                                    ),
                                )
                            }
                            .onFailure { callback(errorResult("probe_endpoint_failed", it.message)) }
                    }
                }

                override fun exportLogs(
                    content: String,
                    suggestedName: String,
                    callback: (Result<String?>) -> Unit,
                ) {
                    pendingExportResult = nullableStringResult(callback)
                    pendingExportContent = logsWithNativeDiagnostics(content)
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TITLE, suggestedName.ifBlank { "meow-logs-${System.currentTimeMillis()}.txt" })
                    }
                    startActivityForResult(intent, exportDocumentRequestCode)
                }

                override fun getAndroidId(callback: (Result<String>) -> Unit) {
                    callback(
                        Result.success(
                            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "",
                        ),
                    )
                }

                override fun getSubscriptionRequestDeviceInfo(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    val locale = resources.configuration.locales?.get(0)?.language
                        ?: java.util.Locale.getDefault().language
                    callback(
                        Result.success(
                            mapOf(
                                "locale" to locale,
                                "os" to "Android",
                                "osVersion" to Build.VERSION.RELEASE,
                                "model" to Build.MODEL,
                                "androidId" to (Settings.Secure.getString(
                                    contentResolver,
                                    Settings.Secure.ANDROID_ID,
                                ) ?: ""),
                            ),
                        ),
                    )
                }

                override fun getPlatformDeviceInfo(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(
                        Result.success(
                            mapOf(
                                "manufacturer" to Build.MANUFACTURER,
                                "brand" to Build.BRAND,
                                "model" to Build.MODEL,
                                "sdkInt" to Build.VERSION.SDK_INT,
                                "release" to Build.VERSION.RELEASE,
                                "abi" to Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
                                "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                            ),
                        ),
                    )
                }

                override fun getAppVersionInfo(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(Result.success(pigeonMap(getAppVersionInfo())))
                }

                override fun getCoreVersion(callback: (Result<String>) -> Unit) {
                    callback(Result.success(Libbox.version()))
                }

                override fun getPerformanceSnapshot(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(Result.success(pigeonMap(buildPerformanceSnapshot())))
                }

                override fun getHappCrypt5Support(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(Result.success(pigeonMap(getHappCrypt5Support())))
                }

                override fun getInstalledApps(callback: (Result<List<Map<String?, Any?>?>>) -> Unit) {
                    Thread {
                        runCatching { getInstalledApps() }
                            .onSuccess { apps ->
                                mainHandler.post {
                                    callback(Result.success(pigeonMapList(apps)))
                                }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    callback(errorResult("get_installed_apps_failed", error.message ?: error.toString()))
                                }
                            }
                    }.start()
                }

                override fun setQuickSettingsTileLabel(label: String, callback: (Result<Unit>) -> Unit) {
                    writeQuickSettingsTileLabel(label)
                    callback(Result.success(Unit))
                }
            },
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupSingboxHostApi(flutterEngine.dartExecutor.binaryMessenger)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SingboxController.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    SingboxController.setEventSink(null)
                }
            },
        )

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepLinkEventChannelName,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    deepLinkEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    deepLinkEventSink = null
                }
            },
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepLinkMethodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialImportRequest" -> {
                    result.success(buildImportDeepLinkPayload(intent?.data))
                }
                else -> result.notImplemented()
            }
        }

        /*
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            happCryptoMethodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeCrypt5" -> decodeHappCrypt5(call.argument("link"), result)
                else -> result.notImplemented()
            }
        }
        */

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareVpn" -> {
                    val requiresVpn = call.argument<Boolean>("requiresVpn") ?: true
                    if (!requiresVpn) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    val intent = VpnService.prepare(this)
                    Log.i(TAG, "prepareVpn requiresVpn=$requiresVpn granted=${intent == null}")
                    if (intent == null) {
                        result.success(true)
                    } else {
                        pendingPrepareResult = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, vpnPrepareRequestCode)
                    }
                }

                "vpnPermissionStatus" -> {
                    result.success(
                        mapOf(
                            "granted" to (VpnService.prepare(this) == null),
                        ),
                    )
                }

                "getPlatformDeviceInfo" -> {
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "brand" to Build.BRAND,
                            "model" to Build.MODEL,
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "release" to Build.VERSION.RELEASE,
                            "abi" to Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
                            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                        ),
                    )
                }

                "getAppVersionInfo" -> {
                    result.success(getAppVersionInfo())
                }

                "getCoreVersion" -> {
                    result.success(Libbox.version())
                }

                "getConfigPath" -> {
                    result.success(MeowApplication.configFile.absolutePath)
                }

                "getRuntimeFlags" -> {
                    result.success(
                        mapOf(
                            "wakeLockEnabled" to MeowApplication.wakeLockEnabled,
                            "networkHeartbeatEnabled" to MeowApplication.networkHeartbeatEnabled,
                            "networkHeartbeatIntervalSeconds" to MeowApplication.networkHeartbeatIntervalSeconds,
                            "performanceMode" to MeowApplication.performanceMode,
                            "memoryLimitEnabled" to MeowApplication.memoryLimitEnabled,
                        ),
                    )
                }

                "setRuntimeFlags" -> {
                    val wakeLock = call.argument<Boolean>("wakeLockEnabled")
                    val heartbeat = call.argument<Boolean>("networkHeartbeatEnabled")
                    val heartbeatInterval = call.argument<Int>("networkHeartbeatIntervalSeconds")
                    val performanceMode = call.argument<String>("performanceMode")
                    val memoryLimitEnabled = call.argument<Boolean>("memoryLimitEnabled")
                    var heartbeatChanged = false
                    if (wakeLock != null) {
                        MeowApplication.wakeLockEnabled = wakeLock
                    }
                    if (heartbeat != null) {
                        MeowApplication.networkHeartbeatEnabled = heartbeat
                        heartbeatChanged = true
                    }
                    if (heartbeatInterval != null) {
                        MeowApplication.networkHeartbeatIntervalSeconds = heartbeatInterval.toLong()
                        heartbeatChanged = true
                    }
                    if (performanceMode != null) {
                        MeowApplication.performanceMode = performanceMode
                    }
                    if (memoryLimitEnabled != null) {
                        MeowApplication.memoryLimitEnabled = memoryLimitEnabled
                    }
                    if (heartbeatChanged) {
                        MeowDefaultNetworkMonitor.refreshHeartbeat()
                    }
                    result.success(true)
                }

                "setRuntimeUiForeground" -> {
                    val foreground = call.argument<Boolean>("foreground")
                    if (foreground == null) {
                        result.error("missing_foreground", "Foreground state is missing", null)
                    } else {
                        SingboxController.setUiForeground(foreground)
                        result.success(true)
                    }
                }

                "getPerformanceSnapshot" -> {
                    result.success(buildPerformanceSnapshot())
                }

                "start" -> {
                    val config = call.argument<String>("config")
                    val useVpn = call.argument<Boolean>("useVpn") ?: true
                    if (config.isNullOrBlank()) {
                        result.error("empty_config", "Config is empty", null)
                        return@setMethodCallHandler
                    }
                    writeConfigAndDispatch(config, result) {
                        dispatchStartAfterConfigWrite(useVpn, result)
                    }
                }

                "startPrepared" -> {
                    val useVpn = call.argument<Boolean>("useVpn") ?: true
                    withPreparedConfig(result) {
                        dispatchStartAfterConfigWrite(useVpn, result)
                    }
                }

                "applyConfig" -> {
                    val config = call.argument<String>("config")
                    val useVpn = call.argument<Boolean>("useVpn") ?: true
                    val restartCore = call.argument<Boolean>("restartCore") ?: false
                    if (config.isNullOrBlank()) {
                        result.error("empty_config", "Config is empty", null)
                        return@setMethodCallHandler
                    }
                    writeConfigAndDispatch(config, result) {
                        dispatchApplyConfigAfterConfigWrite(useVpn, restartCore, result)
                    }
                }

                "applyPreparedConfig" -> {
                    val useVpn = call.argument<Boolean>("useVpn") ?: true
                    val restartCore = call.argument<Boolean>("restartCore") ?: false
                    withPreparedConfig(result) {
                        dispatchApplyConfigAfterConfigWrite(useVpn, restartCore, result)
                    }
                }

                "setQuickSettingsTileLabel" -> {
                    writeQuickSettingsTileLabel(call.argument("label"))
                    result.success(true)
                }

                "stop" -> {
                    val reason = call.argument<String>("reason") ?: "unspecified"
                    dispatchStopRuntime(reason) { stopped ->
                        if (stopped) {
                            result.success(true)
                        } else {
                            result.error("stop_timeout", "Native service stop timed out", null)
                        }
                    }
                }

                "reload" -> {
                    val serviceClass = when (SingboxController.serviceMode) {
                        "proxy" -> MeowProxyService::class.java
                        else -> MeowVpnService::class.java
                    }
                    startService(Intent(this, serviceClass).setAction(MeowBoxService.ACTION_RELOAD))
                    result.success(true)
                }

                "selectOutbound" -> {
                    val groupTag = call.argument<String>("groupTag") ?: "select"
                    val outboundTag = call.argument<String>("outboundTag")
                    if (outboundTag.isNullOrBlank()) {
                        result.error("missing_outbound", "Outbound tag is empty", null)
                        return@setMethodCallHandler
                    }
                    SingboxController.selectOutbound(groupTag, outboundTag) { selectionResult ->
                        selectionResult.onSuccess {
                            result.success(true)
                        }.onFailure {
                            result.error("select_failed", it.message, null)
                        }
                    }
                }

                "addOutbound" -> {
                    val selectorTag = call.argument<String>("selectorTag") ?: "select"
                    val outboundJson = call.argument<String>("outboundJson")
                    if (outboundJson.isNullOrBlank()) {
                        result.error("missing_outbound", "Outbound JSON is empty", null)
                        return@setMethodCallHandler
                    }
                    SingboxController.addOutbound(selectorTag, outboundJson) { addResult ->
                        addResult.onSuccess {
                            result.success(true)
                        }.onFailure {
                            result.error("add_outbound_failed", it.message, null)
                        }
                    }
                }

                "removeOutbound" -> {
                    val selectorTag = call.argument<String>("selectorTag") ?: "select"
                    val outboundTag = call.argument<String>("outboundTag")
                    if (outboundTag.isNullOrBlank()) {
                        result.error("missing_outbound", "Outbound tag is empty", null)
                        return@setMethodCallHandler
                    }
                    SingboxController.removeOutbound(selectorTag, outboundTag) { removeResult ->
                        removeResult.onSuccess {
                            result.success(true)
                        }.onFailure {
                            result.error("remove_outbound_failed", it.message, null)
                        }
                    }
                }

                "urlTest" -> {
                    val groupTag = call.argument<String>("groupTag") ?: "select"
                    SingboxController.urlTest(
                        groupTag = groupTag,
                        targetOutboundTag = call.argument<String>("targetOutboundTag").orEmpty(),
                        priorityOutboundTag = call.argument<String>("priorityOutboundTag").orEmpty(),
                        excludeOutboundTag = call.argument<String>("excludeOutboundTag").orEmpty(),
                        url = call.argument<String>("url").orEmpty(),
                        timeoutMillis = call.argument<Number>("timeoutMillis")?.toInt() ?: 3_000,
                        concurrency = call.argument<Number>("concurrency")?.toInt() ?: 0,
                        deadlineMillis = call.argument<Number>("deadlineMillis")?.toInt() ?: 10_000,
                        force = call.argument<Boolean>("force") ?: true,
                    ) { urlTestResult ->
                        urlTestResult.onSuccess {
                            result.success(true)
                        }.onFailure {
                            result.error("urltest_failed", it.message, null)
                        }
                    }
                }

                "removeUrlTestOutbounds" -> {
                    val groupTag = call.argument<String>("groupTag")?.trim().orEmpty()
                    val outboundTags = call.argument<List<*>>("outboundTags").orEmpty()
                        .mapNotNull { it?.toString()?.trim() }
                        .filter { it.isNotEmpty() }
                    if (groupTag.isEmpty()) {
                        result.error("missing_group", "Group tag is empty", null)
                        return@setMethodCallHandler
                    }
                    if (outboundTags.isEmpty()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    SingboxController.removeUrlTestOutbounds(groupTag, outboundTags) { updateResult ->
                        updateResult.onSuccess {
                            result.success(true)
                        }.onFailure {
                            result.error("remove_urltest_outbounds_failed", it.message, null)
                        }
                    }
                }

                "status" -> {
                    result.success(runtimeStatusMap())
                }

                "lookupOutboundExternalInfo" -> {
                    val outboundTag = call.argument<String>("outboundTag")?.trim().orEmpty()
                    if (outboundTag.isEmpty()) {
                        result.error("lookup_outbound_external_info_failed", "Outbound tag is empty", null)
                        return@setMethodCallHandler
                    }
                    SingboxController.lookupOutboundExternalInfo(outboundTag) { lookupResult ->
                        lookupResult.onSuccess {
                            result.success(it)
                        }.onFailure {
                            result.error("lookup_outbound_external_info_failed", it.message, null)
                        }
                    }
                }

                "getNetworkInterfaceState" -> {
                    val state = MeowDefaultNetworkMonitor.currentInterfaceState("method_channel")
                    result.success(
                        mapOf(
                            "available" to state.available,
                            "interfaceName" to state.interfaceName,
                            "interfaceIndex" to state.interfaceIndex,
                            "generation" to state.generation,
                            "reason" to state.reason,
                            "updatedAtMillis" to state.updatedAtMillis,
                        ),
                    )
                }

                "probeProxyEndpoint" -> {
                    val tag = call.argument<String>("tag")?.trim().orEmpty()
                    val host = call.argument<String>("host")?.trim().orEmpty()
                    val port = call.argument<Number>("port")?.toInt() ?: 0
                    val timeoutMs = call.argument<Number>("timeoutMs")?.toInt() ?: 3_000
                    SingboxController.probeProxyEndpoint(tag, host, port, timeoutMs) { probeResult ->
                        probeResult.onSuccess {
                            result.success(it)
                        }.onFailure {
                            result.error("probe_endpoint_failed", it.message, null)
                        }
                    }
                }

                "exportLogs" -> {
                    val content = call.argument<String>("content") ?: ""
                    val suggestedName = call.argument<String>("suggestedName")
                        ?: "meow-logs-${System.currentTimeMillis()}.txt"
                    pendingExportResult = result
                    pendingExportContent = logsWithNativeDiagnostics(content)
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TITLE, suggestedName)
                    }
                    startActivityForResult(intent, exportDocumentRequestCode)
                }

                "canInstallApks" -> {
                    result.success(canRequestApkInstalls())
                }

                "openApkInstallSettings" -> {
                    runCatching { openApkInstallSettings() }
                        .onSuccess { result.success(true) }
                        .onFailure { result.error("open_install_settings_failed", it.message, null) }
                }

                "installDownloadedApk" -> {
                    val path = call.argument<String>("path")?.trim().orEmpty()
                    if (path.isEmpty()) {
                        result.error("missing_apk_path", "APK path is empty", null)
                        return@setMethodCallHandler
                    }
                    runCatching { installDownloadedApk(path) }
                        .onSuccess { result.success(true) }
                        .onFailure { result.error("install_apk_failed", it.message, null) }
                }

                "inspectDownloadedApk" -> {
                    val path = call.argument<String>("path")?.trim().orEmpty()
                    if (path.isEmpty()) {
                        result.error("missing_apk_path", "APK path is empty", null)
                        return@setMethodCallHandler
                    }
                    ioExecutor.execute {
                        runCatching { inspectDownloadedApk(path) }
                            .onSuccess { inspection ->
                                mainHandler.post { result.success(inspection) }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    result.error("inspect_apk_failed", error.message, null)
                                }
                            }
                    }
                }

                "fetchUrlOnUnderlyingNetwork" -> {
                    val url = call.argument<String>("url")?.trim().orEmpty()
                    if (url.isEmpty()) {
                        result.error("missing_url", "URL is empty", null)
                        return@setMethodCallHandler
                    }
                    val rawHeaders = call.argument<Map<*, *>>("headers").orEmpty()
                    val headers = rawHeaders.entries
                        .mapNotNull { (key, value) ->
                            val name = key?.toString()?.trim().orEmpty()
                            val headerValue = value?.toString().orEmpty()
                            if (name.isEmpty()) null else name to headerValue
                        }
                        .toMap()
                    val maxBytes = (call.argument<Number>("maxBytes")?.toInt()
                        ?: 16 * 1024 * 1024).coerceIn(1, 32 * 1024 * 1024)
                    val timeoutMs = call.argument<Number>("timeoutMs")?.toInt() ?: 20_000
                    subscriptionNetworkExecutor.execute {
                        runCatching {
                            fetchUrlOnUnderlyingNetwork(url, headers, maxBytes, timeoutMs)
                        }.onSuccess { response ->
                            mainHandler.post { result.success(response) }
                        }.onFailure { error ->
                            mainHandler.post {
                                result.error("underlying_http_failed", error.message, null)
                            }
                        }
                    }
                }

                "getAndroidId" -> {
                    result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "",
                    )
                }

                "getSubscriptionRequestDeviceInfo" -> {
                    val locale = resources.configuration.locales?.get(0)?.language
                        ?: java.util.Locale.getDefault().language
                    result.success(
                        mapOf(
                            "locale" to locale,
                            "os" to "Android",
                            "osVersion" to Build.VERSION.RELEASE,
                            "model" to Build.MODEL,
                            "androidId" to (Settings.Secure.getString(
                                contentResolver,
                                Settings.Secure.ANDROID_ID,
                            ) ?: ""),
                        ),
                    )
                }

                "getHappCrypt5Support" -> {
                    result.success(getHappCrypt5Support())
                }

                "getInstalledApps" -> {
                    Thread {
                        runCatching { getInstalledApps() }
                            .onSuccess { apps ->
                                mainHandler.post {
                                    result.success(apps)
                                }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    result.error(
                                        "get_installed_apps_failed",
                                        error.message ?: error.toString(),
                                        null,
                                    )
                                }
                            }
                    }.start()
                }

                "getInstalledAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                    val sizePx = call.argument<Int>("sizePx")
                    appIconExecutor.execute {
                        val iconBytes = getInstalledAppIcon(packageName, sizePx)
                        mainHandler.post {
                            result.success(iconBytes)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Used for VPN permission callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnPrepareRequestCode) {
            val result = pendingPrepareResult
            pendingPrepareResult = null
            result?.success(VpnService.prepare(this) == null)
            return
        }
        if (requestCode == exportDocumentRequestCode) {
            val result = pendingExportResult
            val content = pendingExportContent
            pendingExportResult = null
            pendingExportContent = null
            if (resultCode != Activity.RESULT_OK || data?.data == null || content == null) {
                result?.success(null)
                return
            }
            val uri = data.data!!
            runCatching {
                contentResolver.openOutputStream(uri)?.use { stream ->
                    stream.write(content.toByteArray(Charsets.UTF_8))
                    stream.flush()
                } ?: error("Failed to open output stream")
            }.onSuccess {
                result?.success(uri.toString())
            }.onFailure {
                result?.error("export_logs_failed", it.message, null)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchImportDeepLink(intent)
    }
}
