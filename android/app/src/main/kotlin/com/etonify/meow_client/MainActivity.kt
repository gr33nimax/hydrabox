package com.etonify.meow_client

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
// Legacy Happ native crypt5 path is intentionally disabled. Crypt5/5.1 is now
// decrypted in Dart from extracted selector/key tables.
// import com.etonify.meow_client.happcrypto.Crypto5IsolatedService
import com.etonify.meow_client.singbox.MeowBoxService
import com.etonify.meow_client.singbox.MeowDefaultNetworkMonitor
import com.etonify.meow_client.singbox.MeowDiagnostics
import com.etonify.meow_client.singbox.MeowProxyService
import com.etonify.meow_client.singbox.MeowVpnService
import com.etonify.meow_client.singbox.SingboxController
import com.etonify.meow_client.generated.FlutterError as PigeonFlutterError
import com.etonify.meow_client.generated.RuntimeFlagsMessage
import com.etonify.meow_client.generated.SingboxHostApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.Libbox
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
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
        val temp = File.createTempFile(target.nameWithoutExtension, ".tmp", directory)
        try {
            FileOutputStream(temp).use { stream ->
                stream.write(config.toByteArray(Charsets.UTF_8))
                stream.fd.sync()
            }
            runCatching {
                Files.move(
                    temp.toPath(),
                    target.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                    StandardCopyOption.ATOMIC_MOVE,
                )
            }.getOrElse {
                Files.move(
                    temp.toPath(),
                    target.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                )
            }
        } catch (error: Throwable) {
            temp.delete()
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

    private fun runtimeStopTargets(): List<Class<out android.app.Service>> {
        val primary = when (SingboxController.serviceMode) {
            "proxy" -> MeowProxyService::class.java
            else -> MeowVpnService::class.java
        }
        val secondary = if (primary == MeowVpnService::class.java) {
            MeowProxyService::class.java
        } else {
            MeowVpnService::class.java
        }
        return listOf(primary, secondary)
    }

    private fun dispatchStopRuntime(reason: String, onComplete: (Boolean) -> Unit) {
        val targets = runtimeStopTargets()
        MeowDiagnostics.log(
            TAG,
            "dispatchStopRuntime reason=$reason running=${SingboxController.running} " +
                "mode=${SingboxController.serviceMode} targets=${targets.joinToString { it.simpleName }}",
        )
        SingboxController.log(
            "warning",
            "android stop requested reason=$reason running=${SingboxController.running} " +
                "mode=${SingboxController.serviceMode}",
        )
        MeowBoxService.requestStopAll("main_activity_stop:$reason")
        for (serviceClass in targets) {
            runCatching {
                startService(
                    Intent(this, serviceClass)
                        .setAction(MeowBoxService.ACTION_STOP)
                        .putExtra(MeowBoxService.EXTRA_STOP_REASON, reason),
                )
            }.onFailure {
                MeowDiagnostics.log(TAG, "ACTION_STOP failed target=${serviceClass.simpleName}", it)
            }
        }
        mainHandler.postDelayed({
            if (!SingboxController.running) {
                for (serviceClass in targets) {
                    runCatching {
                        stopService(Intent(this, serviceClass))
                    }.onFailure {
                        MeowDiagnostics.log(TAG, "stopService failed target=${serviceClass.simpleName}", it)
                    }
                }
                MeowApplication.clearServiceState()
                MeowQuickSettingsTileService.requestRefresh(this)
                MeowDiagnostics.log(TAG, "dispatchStopRuntime safety stopService completed reason=$reason")
            }
        }, 1_200L)
        if (!SingboxController.running) {
            onComplete(true)
            return
        }
        SingboxController.awaitStopped { stopped ->
            if (!stopped) {
                onComplete(false)
                return@awaitStopped
            }
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
            MeowDiagnostics.log(
                TAG,
                "issuing ACTION_STOP for mode switch currentMode=${SingboxController.serviceMode} targetMode=$targetMode currentService=${currentService.simpleName}",
            )
            startService(
                Intent(this, currentService)
                    .setAction(MeowBoxService.ACTION_STOP)
                    .putExtra(MeowBoxService.EXTRA_STOP_REASON, "mode_switch_to_$targetMode"),
            )
            SingboxController.awaitStopped { stopped ->
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
        val supportedAbis = setOf("arm64-v8a", "armeabi-v7a")
        val matchedAbi = Build.SUPPORTED_ABIS.firstOrNull { it in supportedAbis }
        val supported = matchedAbi != null
        return linkedMapOf(
            "supported" to supported,
            "abi" to (matchedAbi ?: Build.SUPPORTED_ABIS.firstOrNull().orEmpty()),
            "abis" to Build.SUPPORTED_ABIS.toList(),
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
            "serviceState" to MeowApplication.describeRecordedServiceState(),
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
        return installedApps
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
                    "launchable" to (packageManager.getLaunchIntentForPackage(appInfo.packageName) != null),
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

                override fun urlTest(groupTag: String, callback: (Result<Unit>) -> Unit) {
                    SingboxController.urlTest(groupTag.ifBlank { "select" }) { urlTestResult ->
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
                    callback(
                        Result.success(
                            mapOf(
                                "running" to SingboxController.running,
                                "mode" to SingboxController.serviceMode,
                                "uplink" to SingboxController.uplink,
                                "downlink" to SingboxController.downlink,
                                "uplinkTotal" to SingboxController.uplinkTotal,
                                "downlinkTotal" to SingboxController.downlinkTotal,
                            ),
                        ),
                    )
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

                override fun exportLogs(
                    content: String,
                    suggestedName: String,
                    callback: (Result<String?>) -> Unit,
                ) {
                    pendingExportResult = nullableStringResult(callback)
                    pendingExportContent = content
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
                        ),
                    )
                }

                "setRuntimeFlags" -> {
                    val wakeLock = call.argument<Boolean>("wakeLockEnabled")
                    val heartbeat = call.argument<Boolean>("networkHeartbeatEnabled")
                    val heartbeatInterval = call.argument<Int>("networkHeartbeatIntervalSeconds")
                    val performanceMode = call.argument<String>("performanceMode")
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
                    if (heartbeatChanged) {
                        MeowDefaultNetworkMonitor.refreshHeartbeat()
                    }
                    result.success(true)
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
                    SingboxController.urlTest(groupTag) { urlTestResult ->
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
                    result.success(
                        mapOf(
                            "running" to SingboxController.running,
                            "mode" to SingboxController.serviceMode,
                            "uplink" to SingboxController.uplink,
                            "downlink" to SingboxController.downlink,
                            "uplinkTotal" to SingboxController.uplinkTotal,
                            "downlinkTotal" to SingboxController.downlinkTotal,
                        ),
                    )
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

                "exportLogs" -> {
                    val content = call.argument<String>("content") ?: ""
                    val suggestedName = call.argument<String>("suggestedName")
                        ?: "meow-logs-${System.currentTimeMillis()}.txt"
                    pendingExportResult = result
                    pendingExportContent = content
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TITLE, suggestedName)
                    }
                    startActivityForResult(intent, exportDocumentRequestCode)
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
