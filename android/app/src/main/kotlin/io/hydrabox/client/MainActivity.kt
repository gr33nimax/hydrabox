package io.hydrabox.client

import android.app.ActivityManager
import android.Manifest
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
import android.os.SystemClock
import android.provider.Settings
import android.util.AtomicFile
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.hydrabox.client.core.CoreManagerHostApiHandler
import io.hydrabox.client.generated.CoreManagerHostApi
import io.hydrabox.client.generated.DownloadedApkInspectionMessage
import io.hydrabox.client.generated.InstalledAppMessage
import io.hydrabox.client.generated.NotificationPresentationMessage
import io.hydrabox.client.generated.UnderlyingHttpRequestMessage
import io.hydrabox.client.generated.UnderlyingHttpResponseMessage
import io.hydrabox.client.singbox.HydraBoxService
import io.hydrabox.client.singbox.HydraBoxDefaultNetworkMonitor
import io.hydrabox.client.singbox.HydraBoxDiagnostics
import io.hydrabox.client.singbox.HydraBoxForegroundNotification
import io.hydrabox.client.singbox.HydraBoxLogSanitizer
import io.hydrabox.client.singbox.HydraBoxProxyService
import io.hydrabox.client.singbox.HydraBoxVpnPlatformInterface
import io.hydrabox.client.singbox.HydraBoxVpnService
import io.hydrabox.client.singbox.SingboxController
import io.hydrabox.client.singbox.RuntimeEventConsumer
import io.hydrabox.client.runtime.CoreRuntimeClient
import io.hydrabox.client.runtime.CoreRuntimeException
import io.hydrabox.client.runtime.CoreRuntimeService
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.hydrabox.client.storage.DomainCrypto
import io.hydrabox.client.storage.HydraDatabase
import io.hydrabox.client.storage.IncidentRepository
import io.hydrabox.client.update.AppUpdateManifestVerifier
import io.hydrabox.client.generated.FlutterError as PigeonFlutterError
import io.hydrabox.client.generated.NetworkInterfaceStateMessage
import io.hydrabox.client.generated.PreconnectUrlTestRequestMessage
import io.hydrabox.client.generated.PreconnectUrlTestResultMessage
import io.hydrabox.client.generated.RuntimeFlagsMessage
import io.hydrabox.client.generated.SingboxHostApi
import io.hydrabox.client.generated.UrlTestRequestMessage
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import java.net.URLDecoder
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import kotlinx.coroutines.runBlocking

internal fun isLiteralLoopbackSubscriptionHost(rawHost: String): Boolean {
    val host = rawHost.trim().removePrefix("[").removeSuffix("]").lowercase()
    if (host == "localhost" || host.endsWith(".localhost")) return true

    val ipv4 = host.split('.')
    if (ipv4.size == 4 && ipv4.all { part ->
            part.isNotEmpty() &&
                part.all(Char::isDigit) &&
                (part.length == 1 || !part.startsWith('0')) &&
                part.toIntOrNull() in 0..255
        }
    ) {
        return ipv4.first().toInt() == 127
    }

    // Invoke the platform parser only for an IPv6 literal. Never resolve an
    // arbitrary hostname here: DNS resolution must not turn remote HTTP into
    // an accepted loopback request (or vice versa).
    if (!host.contains(':') || !Regex("^[0-9a-f:.]+$").matches(host)) {
        return false
    }
    return runCatching { InetAddress.getByName(host).isLoopbackAddress }
        .getOrDefault(false)
}

internal fun hasHydraKeyQuery(rawQuery: String?): Boolean =
    rawQuery.orEmpty().split('&', ';').any { member ->
        val rawName = member.substringBefore('=')
        val decodedName = runCatching {
            URLDecoder.decode(rawName, StandardCharsets.UTF_8.name())
        }.getOrDefault(rawName)
        decodedName.equals("hydra-key", ignoreCase = true)
    }

private fun CoreRuntimeProtocol.RuntimeSnapshot.toLegacyRuntimeMap(): Map<String?, Any?> = mapOf(
    "running" to (state == CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING),
    "state" to state.name,
    "mode" to when (mode) {
        CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_VPN -> "vpn"
        CoreRuntimeProtocol.RuntimeMode.RUNTIME_MODE_PROXY -> "proxy"
        else -> ""
    },
    "runtimeGeneration" to generation,
    "uplink" to traffic.uplinkBytesPerSecond,
    "downlink" to traffic.downlinkBytesPerSecond,
    "uplinkTotal" to traffic.uplinkTotalBytes,
    "downlinkTotal" to traffic.downlinkTotalBytes,
    "lastError" to lastError.safeMessage,
    "errorCode" to lastError.code,
    "processEpoch" to processEpoch,
    "sequence" to lastSequence,
    "groups" to outboundGroupsList.map { group ->
        mapOf(
            "tag" to group.groupId,
            "selected" to group.selectedOutboundId,
            "items" to group.outboundsList.map { item ->
                mapOf(
                    "tag" to item.outboundId,
                    "delayMillis" to item.delayMillis,
                    "delay" to item.delayMillis,
                    "observedAt" to item.measuredAtMillis,
                    "time" to item.measuredAtMillis,
                    "status" to item.status,
                    "errorCode" to item.error.code,
                    "errorMessage" to item.error.safeMessage,
                    "error" to item.error.safeMessage,
                )
            },
        )
    },
    "urlTestSessions" to probeSessionsList.map { session ->
        mapOf(
            "id" to session.sessionId,
            "state" to session.state.name,
            "startedAt" to session.startedAtMillis,
            "completedAt" to session.finishedAtMillis,
            "total" to session.requestedCount,
            "completed" to session.completedCount,
        )
    },
)

private data class InstalledAppInfo(
    val packageName: String,
    val label: String,
    val system: Boolean,
    val launchable: Boolean,
)

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "HydraBoxMainActivity"
        private const val QUICK_TILE_LABEL_FILE = "quick_tile_label.txt"
        private const val MAX_SUBSCRIPTION_REDIRECTS = 5
        private const val CORE_PROCESS_EXIT_DEADLINE_MILLIS = 5_000L
        private const val CORE_PROCESS_EXIT_POLL_MILLIS = 50L
        private val SUBSCRIPTION_REDIRECT_CODES = setOf(301, 302, 303, 307, 308)
        private val SENSITIVE_SUBSCRIPTION_HEADERS = setOf(
            "authorization",
            "proxy-authorization",
            "cookie",
            "x-hwid",
        )
        private val SENSITIVE_SUBSCRIPTION_HEADER_PARTS = setOf(
            "token",
            "secret",
            "password",
            "api-key",
            "apikey",
            "hwid",
        )
        private val SENSITIVE_SUBSCRIPTION_QUERY = Regex(
            "(?:^|&)(?:token|access_token|password|passwd|key|secret|uuid|auth|authorization|sub|url)=",
            RegexOption.IGNORE_CASE,
        )
    }
    private val methodChannelName = "io.hydrabox.client/singbox"
    private val eventChannelName = "io.hydrabox.client/singbox_events"
    private val deepLinkMethodChannelName = "io.hydrabox.client/deep_links"
    private val deepLinkEventChannelName = "io.hydrabox.client/deep_link_events"
    private val secureStorageMethodChannelName = "io.hydrabox.client/secure_storage"
    private var pendingPrepareResult: MethodChannel.Result? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportContent: String? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var deepLinkEventSink: EventChannel.EventSink? = null
    private var mutableCoreRuntimeClient: CoreRuntimeClient? = null
    private val coreRuntimeClient: CoreRuntimeClient
        get() = mutableCoreRuntimeClient
            ?: CoreRuntimeClient(applicationContext).also { mutableCoreRuntimeClient = it }
    private var coreManagerHostApiHandler: CoreManagerHostApiHandler? = null
    @Volatile
    private var activityDestroyed = false
    private var singboxEventConsumer: RuntimeEventConsumer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val subscriptionNetworkExecutor = Executors.newFixedThreadPool(2)
    private val endpointDnsExecutor = Executors.newFixedThreadPool(2)
    private val appIconExecutor = Executors.newFixedThreadPool(3)

    private val vpnPermissionLauncher: ActivityResultLauncher<Intent> =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            val result = pendingPrepareResult
            pendingPrepareResult = null
            result?.success(VpnService.prepare(this) == null)
        }

    private val exportDocumentLauncher: ActivityResultLauncher<String> =
        registerForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
            completeLogExport(uri)
        }

    private val notificationPermissionLauncher: ActivityResultLauncher<String> =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val result = pendingNotificationPermissionResult
            pendingNotificationPermissionResult = null
            result?.success(granted)
        }

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

    private fun coreUtilityKind(name: String): CoreRuntimeProtocol.CoreUtilityKind = when (name) {
        "hydraCoreCapabilities" ->
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_CAPABILITIES
        "hydraCoreBuildInfo" ->
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_BUILD_INFO
        "hydraCoreValidateConfig" ->
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VALIDATE_CONFIG
        "hydraCoreValidateSubscription" ->
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VALIDATE_SUBSCRIPTION
        "hydraCoreInspectSubscription" ->
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_INSPECT_SUBSCRIPTION
        "hydraCoreOpenSubscriptionJWE" ->
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_OPEN_SUBSCRIPTION_JWE
        "hydraCoreValidateSubscriptionJWE" ->
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VALIDATE_SUBSCRIPTION_JWE
        "hydraCoreInspectSubscriptionJWE" ->
            CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_INSPECT_SUBSCRIPTION_JWE
        else -> throw IllegalArgumentException("Unsupported HydraCore utility operation")
    }

    private fun runHydraCoreApi(
        callback: (Result<String>) -> Unit,
        name: String,
        vararg arguments: String,
    ) {
        coreRuntimeClient.coreString(coreUtilityKind(name), arguments.toList()) { result ->
            callback(
                result.fold(
                    onSuccess = { Result.success(it) },
                    onFailure = { error ->
                        val coreError = error as? CoreRuntimeException
                        if (coreError == null) {
                            Result.failure(error)
                        } else {
                            Result.failure(
                                PigeonFlutterError(
                                    code = coreError.code,
                                    message = coreError.message,
                                    details = mapOf(
                                        "stage" to coreError.stage,
                                        "retryable" to coreError.retryable,
                                    ),
                                ),
                            )
                        }
                    },
                ),
            )
        }
    }

    private fun runHydraCoreMethodCall(
        result: MethodChannel.Result,
        name: String,
        vararg arguments: String,
    ) {
        coreRuntimeClient.coreString(coreUtilityKind(name), arguments.toList()) { utilityResult ->
            utilityResult.onSuccess(result::success)
                .onFailure { error -> result.error("hydracore_api_failed", error.message, null) }
        }
    }

    private fun notificationsGranted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (notificationsGranted()) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error(
                "notification_permission_in_progress",
                "A notification permission request is already active.",
                null,
            )
            return
        }
        pendingNotificationPermissionResult = result
        runCatching {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }.onFailure { error ->
            pendingNotificationPermissionResult = null
            result.error("notification_permission_launch_failed", error.message, null)
        }
    }

    private fun launchVpnPermission(intent: Intent, result: MethodChannel.Result) {
        if (pendingPrepareResult != null) {
            result.error(
                "vpn_permission_in_progress",
                "A VPN permission request is already active.",
                null,
            )
            return
        }
        pendingPrepareResult = result
        runCatching { vpnPermissionLauncher.launch(intent) }
            .onFailure { error ->
                pendingPrepareResult = null
                result.error("vpn_permission_launch_failed", error.message, null)
            }
    }

    private fun launchLogExport(
        content: String,
        suggestedName: String,
        result: MethodChannel.Result,
    ) {
        if (pendingExportResult != null) {
            result.error("export_in_progress", "A log export is already active.", null)
            return
        }
        pendingExportResult = result
        pendingExportContent = logsWithNativeDiagnostics(content)
        runCatching {
            exportDocumentLauncher.launch(
                suggestedName.ifBlank { "hydrabox-logs-${System.currentTimeMillis()}.txt" },
            )
        }.onFailure { error ->
            pendingExportResult = null
            pendingExportContent = null
            result.error("export_logs_failed", error.message, null)
        }
    }

    private fun completeLogExport(uri: Uri?) {
        val result = pendingExportResult
        val content = pendingExportContent
        pendingExportResult = null
        pendingExportContent = null
        if (uri == null || content == null) {
            result?.success(null)
            return
        }
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

    private fun resolveHostOnUnderlyingNetwork(rawHost: String): List<String> {
        val host = rawHost.trim().removePrefix("[").removeSuffix("]")
        require(host.isNotEmpty()) { "Host is empty." }
        require(host.length <= 253) { "Host is too long." }
        val network = HydraBoxDefaultNetworkMonitor.require()
        val addresses = network.getAllByName(host)
            .mapNotNull { address -> address.hostAddress?.trim() }
            .filter { address -> address.isNotEmpty() }
            .distinct()
        require(addresses.isNotEmpty()) { "Host did not resolve to an IP address." }
        return addresses
    }

    private fun fetchUrlOnUnderlyingNetwork(
        rawUrl: String,
        headers: Map<String, String>,
        maxBytes: Int,
        timeoutMs: Int,
    ): Map<String, Any> {
        val network = HydraBoxDefaultNetworkMonitor.require()
        val boundedTimeout = timeoutMs.coerceIn(3_000, 60_000)
        val deadline = SystemClock.elapsedRealtime() + boundedTimeout
        var url = URL(rawUrl)
        var requestHeaders = headers.toMap()
        var redirectCount = 0
        while (true) {
            validateSubscriptionRequest(url, requestHeaders)
            val remaining = deadline - SystemClock.elapsedRealtime()
            require(remaining > 0L) { "Subscription request timed out." }
            val connection = network.openConnection(url) as HttpURLConnection
            val requestTimeout = remaining.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            val abortOnDeadline = Runnable { connection.disconnect() }
            mainHandler.postDelayed(abortOnDeadline, remaining)
            try {
                connection.requestMethod = "GET"
                connection.instanceFollowRedirects = false
                connection.connectTimeout = requestTimeout
                connection.readTimeout = requestTimeout
                connection.useCaches = false
                for ((name, value) in requestHeaders) {
                    if (name.isBlank() || name.any { it == '\r' || it == '\n' }) continue
                    if (value.any { it == '\r' || it == '\n' }) continue
                    connection.setRequestProperty(name, value)
                }
                val statusCode = connection.responseCode
                if (statusCode in SUBSCRIPTION_REDIRECT_CODES) {
                    require(redirectCount < MAX_SUBSCRIPTION_REDIRECTS) {
                        "Too many subscription redirects."
                    }
                    val location = connection.getHeaderField("Location")?.trim().orEmpty()
                    require(location.isNotEmpty()) { "Subscription redirect has no Location header." }
                    val redirectedUrl = URL(url, location)
                    require(!(url.protocol == "https" && redirectedUrl.protocol == "http")) {
                        "HTTPS to HTTP subscription redirect is not allowed."
                    }
                    if (!sameOrigin(url, redirectedUrl)) {
                        requestHeaders = requestHeaders.filterKeys(::isSafeCrossOriginHeader)
                    }
                    url = redirectedUrl
                    redirectCount++
                    continue
                }
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
                val body = Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(output.toByteArray()))
                    .toString()
                return linkedMapOf(
                    "statusCode" to statusCode,
                    "body" to body,
                    "headers" to responseHeaders,
                    "finalUrl" to url.toString(),
                    "network" to HydraBoxDefaultNetworkMonitor.describeNetwork(network),
                )
            } finally {
                mainHandler.removeCallbacks(abortOnDeadline)
                connection.disconnect()
            }
        }
    }

    private fun validateSubscriptionRequest(url: URL, headers: Map<String, String>) {
        require(url.protocol == "http" || url.protocol == "https") {
            "Only HTTP and HTTPS URLs are supported."
        }
        require(!hasHydraKeyQuery(url.query)) {
            "Hydra hydra-key is allowed only in the URI fragment."
        }
        if (url.protocol == "https") return
        require(isLiteralLoopbackSubscriptionHost(url.host)) {
            "Remote subscription URLs require HTTPS."
        }
        val hasSensitiveHeader = headers.keys.any(::isSensitiveSubscriptionHeader)
        val hasSensitiveUrl = !url.userInfo.isNullOrBlank() ||
            SENSITIVE_SUBSCRIPTION_QUERY.containsMatchIn(url.query.orEmpty())
        require(!hasSensitiveHeader && !hasSensitiveUrl) {
            "Sensitive subscription credentials require HTTPS."
        }
    }

    private fun isSensitiveSubscriptionHeader(name: String): Boolean {
        val normalized = name.trim().lowercase()
        return normalized in SENSITIVE_SUBSCRIPTION_HEADERS ||
            SENSITIVE_SUBSCRIPTION_HEADER_PARTS.any(normalized::contains)
    }

    private fun isSafeCrossOriginHeader(name: String): Boolean =
        name.equals("User-Agent", ignoreCase = true) ||
            name.equals("Accept", ignoreCase = true)

    private fun sameOrigin(first: URL, second: URL): Boolean =
        first.protocol.equals(second.protocol, ignoreCase = true) &&
            first.host.equals(second.host, ignoreCase = true) &&
            effectivePort(first) == effectivePort(second)

    private fun effectivePort(url: URL): Int = when {
        url.port >= 0 -> url.port
        url.protocol == "https" -> 443
        else -> 80
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
        if (scheme != "hydrabox") {
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
        return importPayload("hydraboxImport", url, name)
    }

    private fun dispatchImportDeepLink(intent: Intent?) {
        val payload = buildImportDeepLinkPayload(intent?.data) ?: return
        mainHandler.post {
            deepLinkEventSink?.success(payload)
        }
    }

    private fun writeConfigAtomically(config: String) {
        val target = HydraBoxApplication.configFile
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
                val target = HydraBoxApplication.configFile
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

    private fun currentRuntimeModeForStop(): String {
        val controllerMode = SingboxController.serviceMode.trim().lowercase()
        if (controllerMode == "vpn" || controllerMode == "proxy") {
            return controllerMode
        }
        val recordedMode = HydraBoxApplication.readServiceState()?.mode?.trim()?.lowercase().orEmpty()
        return if (recordedMode == "proxy") "proxy" else "vpn"
    }

    private fun runtimeStopTargetForMode(mode: String): Class<out android.app.Service> {
        return when (mode) {
            "proxy" -> HydraBoxProxyService::class.java
            else -> HydraBoxVpnService::class.java
        }
    }

    private fun runtimeCleanupTargets(
        primary: Class<out android.app.Service>,
    ): List<Class<out android.app.Service>> {
        val secondary = if (primary == HydraBoxVpnService::class.java) {
            HydraBoxProxyService::class.java
        } else {
            HydraBoxVpnService::class.java
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
        val runtimeIntent = HydraBoxApplication.readRuntimeIntent()
        val freshStartAfterStop =
            runtimeIntent != null &&
                runtimeIntent.updatedAtMillis > stopRequestedAtMillis &&
                HydraBoxApplication.isRuntimeIntentFresh(runtimeIntent.mode)
        if (freshStartAfterStop) {
            HydraBoxDiagnostics.log(
                TAG,
                "cleanupStoppedRuntimeState skipped fresh start reason=$reason source=$source " +
                    "intent=${HydraBoxApplication.describeRuntimeIntent()}",
            )
            return false
        }
        if (force) {
            SingboxController.log(
                "warning",
                "force runtime cleanup reason=$reason source=$source " +
                    "running=${SingboxController.running} mode=${SingboxController.serviceMode} " +
                    "activeOwner=${HydraBoxService.hasActiveRuntimeOwner(SingboxController.serviceMode)}",
            )
            HydraBoxService.requestStopAll("force_cleanup:$reason:$source")
            HydraBoxDefaultNetworkMonitor.stop()
        }
        for (serviceClass in targets) {
            runCatching {
                stopService(Intent(this, serviceClass))
            }.onFailure {
                HydraBoxDiagnostics.log(TAG, "stopService failed target=${serviceClass.simpleName}", it)
            }
        }
        HydraBoxApplication.clearServiceState()
        HydraBoxApplication.clearRuntimeIntent()
        HydraBoxQuickSettingsTileService.requestRefresh(this)
        val stopped =
            !SingboxController.running &&
                !HydraBoxService.hasActiveRuntimeOwner()
        HydraBoxDiagnostics.log(
            TAG,
            "cleanupStoppedRuntimeState completed reason=$reason source=$source force=$force " +
                "stopped=$stopped targets=${targets.joinToString { it.simpleName }}",
        )
        return stopped
    }

    private fun dispatchStopRuntime(reason: String, onComplete: (Boolean) -> Unit) {
        val modeAtRequest = currentRuntimeModeForStop()
        val primaryTarget = runtimeStopTargetForMode(modeAtRequest)
        val cleanupTargets = runtimeCleanupTargets(primaryTarget)
        val stopRequestedAtMillis = System.currentTimeMillis()
        HydraBoxDiagnostics.log(
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
        HydraBoxApplication.clearRuntimeIntent()

        val stopRequestedDirectly = HydraBoxService.requestStopForMode(
            modeAtRequest,
            "main_activity_stop:$reason",
        )

        if (!stopRequestedDirectly) {
            runCatching {
                startService(
                    Intent(this, primaryTarget)
                        .setAction(HydraBoxService.ACTION_STOP)
                        .putExtra(HydraBoxService.EXTRA_STOP_REASON, reason),
                )
            }.onFailure {
                HydraBoxDiagnostics.log(
                    TAG,
                    "ACTION_STOP failed target=${primaryTarget.simpleName}",
                    it,
                )
            }
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
                HydraBoxDiagnostics.log(
                    TAG,
                    "dispatchStopRuntime safety stopService skipped reason=$reason " +
                        "running=${SingboxController.running} " +
                        "activeOwner=${HydraBoxService.hasActiveRuntimeOwner(modeAtRequest)} " +
                        "intent=${HydraBoxApplication.describeRuntimeIntent()}",
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
                cleanupStoppedRuntimeState(
                    reason = reason,
                    source = "await_timeout",
                    stopRequestedAtMillis = stopRequestedAtMillis,
                    targets = cleanupTargets,
                    force = true,
                )
                // Give Service.onDestroy() and the native cleanup worker a short
                // final window, but never turn a timeout into a fake success.
                mainHandler.postDelayed({
                    val verifiedStopped =
                        !SingboxController.running &&
                            !HydraBoxService.hasActiveRuntimeOwner()
                    HydraBoxDiagnostics.log(
                        TAG,
                        "dispatchStopRuntime timeout verification reason=$reason " +
                            "stopped=$verifiedStopped running=${SingboxController.running} " +
                            "activeOwner=${HydraBoxService.hasActiveRuntimeOwner()}",
                    )
                    onComplete(verifiedStopped)
                }, 750L)
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
        SingboxController.cancelPreconnectUrlTest("connect_requested") { cancellation ->
            cancellation.onSuccess {
                dispatchStartAfterPreconnectCleanup(useVpn, result)
            }.onFailure {
                result.error("preconnect_cleanup_failed", it.message, null)
            }
        }
    }

    private fun dispatchStartAfterPreconnectCleanup(useVpn: Boolean, result: MethodChannel.Result) {
        SingboxController.clearRuntimeError()
        Log.i(TAG, "start requested useVpn=$useVpn running=${SingboxController.running} mode=${SingboxController.serviceMode}")
        SingboxController.log(
            "info",
            "android start requested useVpn=$useVpn running=${SingboxController.running} mode=${SingboxController.serviceMode}",
        )
        HydraBoxDiagnostics.log(
            TAG,
            "start requested useVpn=$useVpn running=${SingboxController.running} mode=${SingboxController.serviceMode}",
        )
        val targetMode = if (useVpn) "vpn" else "proxy"
        val targetService = if (useVpn) {
            HydraBoxVpnService::class.java
        } else {
            HydraBoxProxyService::class.java
        }
        if (SingboxController.running && SingboxController.serviceMode == targetMode) {
            val serviceIntent = Intent(this, targetService).setAction(HydraBoxService.ACTION_START)
            Log.i(TAG, "start forwarding idempotent ACTION_START mode=$targetMode")
            HydraBoxDiagnostics.log(TAG, "start forwarding idempotent ACTION_START mode=$targetMode")
            startForegroundService(serviceIntent)
            result.success(true)
            return
        }
        if (SingboxController.running && SingboxController.serviceMode != targetMode) {
            val currentService = if (SingboxController.serviceMode == "proxy") {
                HydraBoxProxyService::class.java
            } else {
                HydraBoxVpnService::class.java
            }
            val stopRequestedAtMillis = System.currentTimeMillis()
            val cleanupTargets = runtimeCleanupTargets(currentService)
            HydraBoxDiagnostics.log(
                TAG,
                "issuing ACTION_STOP for mode switch currentMode=${SingboxController.serviceMode} targetMode=$targetMode currentService=${currentService.simpleName}",
            )
            HydraBoxService.requestStopForMode(
                SingboxController.serviceMode,
                "mode_switch_to_$targetMode",
            )
            startService(
                Intent(this, currentService)
                    .setAction(HydraBoxService.ACTION_STOP)
                    .putExtra(HydraBoxService.EXTRA_STOP_REASON, "mode_switch_to_$targetMode"),
            )
            SingboxController.awaitStopped { stopped ->
                if (!stopped) {
                    val cleaned = cleanupStoppedRuntimeState(
                        reason = "mode_switch_to_$targetMode",
                        source = "await_timeout",
                        stopRequestedAtMillis = stopRequestedAtMillis,
                        targets = cleanupTargets,
                        force = true,
                    )
                    if (!cleaned) {
                        SingboxController.log(
                            "error",
                            "mode switch aborted: previous VPN stop was not confirmed target=$targetMode",
                        )
                        HydraBoxDiagnostics.log(
                            TAG,
                            "mode switch start blocked target=$targetMode running=${SingboxController.running} " +
                                "activeOwner=${HydraBoxService.hasActiveRuntimeOwner()}",
                        )
                        return@awaitStopped
                    }
                }
                val serviceIntent = Intent(this, targetService).setAction(HydraBoxService.ACTION_START)
                Log.i(TAG, "starting target service after mode switch target=${targetService.simpleName} stopped=$stopped")
                HydraBoxDiagnostics.log(
                    TAG,
                    "starting target service after mode switch target=${targetService.simpleName} stopped=$stopped",
                )
                startForegroundService(serviceIntent)
            }
        } else {
            val serviceIntent = Intent(this, targetService).setAction(HydraBoxService.ACTION_START)
            Log.i(TAG, "starting target service target=${targetService.simpleName}")
            HydraBoxDiagnostics.log(TAG, "starting target service target=${targetService.simpleName}")
            startForegroundService(serviceIntent)
        }
        result.success(true)
    }

    private fun dispatchApplyConfigAfterConfigWrite(
        useVpn: Boolean,
        restartCore: Boolean,
        result: MethodChannel.Result,
    ) {
        SingboxController.cancelPreconnectUrlTest("config_changed") { cancellation ->
            cancellation.onSuccess {
                dispatchApplyConfigAfterPreconnectCleanup(useVpn, restartCore, result)
            }.onFailure {
                result.error("preconnect_cleanup_failed", it.message, null)
            }
        }
    }

    private fun dispatchApplyConfigAfterPreconnectCleanup(
        useVpn: Boolean,
        restartCore: Boolean,
        result: MethodChannel.Result,
    ) {
        val targetMode = if (useVpn) "vpn" else "proxy"
        val serviceClass = if (useVpn) HydraBoxVpnService::class.java else HydraBoxProxyService::class.java
        Log.i(
            TAG,
            "applyConfig useVpn=$useVpn restartCore=$restartCore running=${SingboxController.running} mode=${SingboxController.serviceMode} target=${serviceClass.simpleName}",
        )
        SingboxController.log(
            "info",
            "android applyConfig requested useVpn=$useVpn restartCore=$restartCore " +
                "running=${SingboxController.running} mode=${SingboxController.serviceMode}",
        )
        HydraBoxDiagnostics.log(
            TAG,
            "applyConfig useVpn=$useVpn restartCore=$restartCore running=${SingboxController.running} mode=${SingboxController.serviceMode} target=${serviceClass.simpleName}",
        )
        if (SingboxController.running && SingboxController.serviceMode == targetMode) {
            if (restartCore) {
                startService(Intent(this, serviceClass).setAction(HydraBoxService.ACTION_RESTART_CORE))
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
            val serviceIntent = Intent(this, serviceClass).setAction(HydraBoxService.ACTION_START)
            startForegroundService(serviceIntent)
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
            HydraBoxQuickSettingsTileService.requestRefresh(this)
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
        fun memoryStatKb(name: String): Long? {
            return processMemory?.getMemoryStat(name)?.toLongOrNull()
        }
        return linkedMapOf(
            "pid" to android.os.Process.myPid(),
            "runtimeMode" to HydraBoxApplication.performanceMode,
            "wakeLockEnabled" to HydraBoxApplication.wakeLockEnabled,
            "networkHeartbeatEnabled" to HydraBoxApplication.networkHeartbeatEnabled,
            "networkHeartbeatIntervalSeconds" to HydraBoxApplication.networkHeartbeatIntervalSeconds,
            "memoryLimitEnabled" to HydraBoxApplication.memoryLimitEnabled,
            "serviceState" to HydraBoxApplication.describeRecordedServiceState(),
            "runtimeIntent" to HydraBoxApplication.describeRuntimeIntent(),
            "totalPssKb" to processMemory?.totalPss,
            "totalPrivateDirtyKb" to processMemory?.totalPrivateDirty,
            "dalvikPssKb" to processMemory?.dalvikPss,
            "nativePssKb" to processMemory?.nativePss,
            "otherPssKb" to processMemory?.otherPss,
            "graphicsPssKb" to memoryStatKb("summary.graphics"),
            "codePssKb" to memoryStatKb("summary.code"),
            "stackPssKb" to memoryStatKb("summary.stack"),
            "privateOtherPssKb" to memoryStatKb("summary.private-other"),
            "systemPssKb" to memoryStatKb("summary.system"),
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
        ).apply {
            putAll(SingboxController.performanceCounters())
            put("notificationUpdateCount", HydraBoxForegroundNotification.updateCount())
        }
    }

    private fun runtimeStatusMap(): Map<String?, Any?> {
        val recordedState = HydraBoxApplication.readServiceState()
        val runtimeIntent = HydraBoxApplication.readRuntimeIntent()
        val recordedServiceAlive = HydraBoxApplication.isRecordedServiceAlive()
        val activeRuntimeOwner = HydraBoxService.hasActiveRuntimeOwner(
            SingboxController.serviceMode.takeIf { it.isNotBlank() },
        )
        val nativeRecoveryPending =
            !SingboxController.running && (recordedServiceAlive || activeRuntimeOwner)
        return mapOf(
            "running" to SingboxController.running,
            "mode" to SingboxController.serviceMode,
            "runtimeGeneration" to SingboxController.activeRuntimeGeneration,
            "uplink" to SingboxController.uplink,
            "downlink" to SingboxController.downlink,
            "uplinkTotal" to SingboxController.uplinkTotal,
            "downlinkTotal" to SingboxController.downlinkTotal,
            "recordedServiceAlive" to recordedServiceAlive,
            "recordedServiceMode" to recordedState?.mode,
            "recordedServicePid" to recordedState?.pid,
            "recordedServiceUpdatedAtMillis" to recordedState?.updatedAtMillis,
            "recordedServiceState" to HydraBoxApplication.describeRecordedServiceState(),
            "activeRuntimeOwner" to activeRuntimeOwner,
            "nativeRecoveryPending" to nativeRecoveryPending,
            // Status is intentionally read-only. Recovery belongs to explicit
            // stop/timeout paths so polling cannot interrupt a normal restart.
            "staleRuntimeStateCleaned" to false,
            "runtimeIntentFresh" to HydraBoxApplication.isRuntimeIntentFresh(),
            "runtimeIntentMode" to runtimeIntent?.mode,
            "runtimeIntentReason" to runtimeIntent?.reason,
            "runtimeIntentPid" to runtimeIntent?.pid,
            "runtimeIntentUpdatedAtMillis" to runtimeIntent?.updatedAtMillis,
            "runtimeIntentState" to HydraBoxApplication.describeRuntimeIntent(),
            "lastError" to SingboxController.lastRuntimeError,
        )
    }

    private fun logsWithNativeDiagnostics(content: String): String {
        val nativeDiagnostics = HydraBoxDiagnostics.readTail()
        val crashReport = HydraBoxDiagnostics.readCrashReportTail()
        val oomReport = HydraBoxDiagnostics.readLatestOomReportMetadata()
        val runtimeSnapshot = runCatching { runtimeStatusMap().toString() }.getOrDefault("unavailable")
        val splitSnapshot = HydraBoxVpnPlatformInterface.describeLastTunPackages()
        return HydraBoxLogSanitizer.redact(buildString {
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
        })
    }

    private fun getInstalledApps(): List<InstalledAppInfo> {
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
                InstalledAppInfo(
                    packageName = appInfo.packageName,
                    label = if (label.isNotEmpty()) label else appInfo.packageName,
                    system = isSystem,
                    launchable = appInfo.packageName in launchablePackages,
                )
            }
            .sortedWith(
                compareByDescending<InstalledAppInfo> { it.launchable }
                    .thenBy<InstalledAppInfo> { it.system }
                    .thenBy(String.CASE_INSENSITIVE_ORDER, InstalledAppInfo::label)
                    .thenBy(String.CASE_INSENSITIVE_ORDER, InstalledAppInfo::packageName),
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
            HydraBoxDiagnostics.log(TAG, "failed to render installed app icon", error)
            null
        } finally {
            bitmap.recycle()
        }
    }

    private fun isAndroidPackageName(value: String): Boolean =
        value.length <= 255 &&
            Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$").matches(value)

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
                        launchVpnPermission(intent, boolResult(callback))
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
                    coreRuntimeClient.start(
                        config = config.toByteArray(Charsets.UTF_8),
                        useVpn = useVpn,
                        callback = callback,
                    )
                }

                override fun startPrepared(useVpn: Boolean, callback: (Result<Unit>) -> Unit) {
                    ioExecutor.execute {
                        runCatching { HydraBoxApplication.configFile.readBytes() }
                            .onSuccess { config ->
                                mainHandler.post {
                                    coreRuntimeClient.start(config, useVpn, callback = callback)
                                }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    callback(errorResult("empty_config", error.message))
                                }
                            }
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
                    coreRuntimeClient.start(
                        config = config.toByteArray(Charsets.UTF_8),
                        useVpn = useVpn,
                        restartCore = restartCore,
                        applyConfig = true,
                        callback = callback,
                    )
                }

                override fun applyPreparedConfig(
                    useVpn: Boolean,
                    restartCore: Boolean,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    ioExecutor.execute {
                        runCatching { HydraBoxApplication.configFile.readBytes() }
                            .onSuccess { config ->
                                mainHandler.post {
                                    coreRuntimeClient.start(
                                        config = config,
                                        useVpn = useVpn,
                                        restartCore = restartCore,
                                        applyConfig = true,
                                        callback = callback,
                                    )
                                }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    callback(errorResult("empty_config", error.message))
                                }
                            }
                    }
                }

                override fun getConfigPath(callback: (Result<String>) -> Unit) {
                    callback(Result.success(HydraBoxApplication.configFile.absolutePath))
                }

                override fun getRuntimeFlags(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(
                        Result.success(
                            mapOf(
                                "wakeLockEnabled" to HydraBoxApplication.wakeLockEnabled,
                                "networkHeartbeatEnabled" to HydraBoxApplication.networkHeartbeatEnabled,
                                "networkHeartbeatIntervalSeconds" to HydraBoxApplication.networkHeartbeatIntervalSeconds,
                                "performanceMode" to HydraBoxApplication.performanceMode,
                                "memoryLimitEnabled" to HydraBoxApplication.memoryLimitEnabled,
                            ),
                        ),
                    )
                }

                override fun setRuntimeFlags(
                    flags: RuntimeFlagsMessage,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    var heartbeatChanged = false
                    flags.wakeLockEnabled?.let { HydraBoxApplication.wakeLockEnabled = it }
                    flags.networkHeartbeatEnabled?.let {
                        HydraBoxApplication.networkHeartbeatEnabled = it
                        heartbeatChanged = true
                    }
                    flags.networkHeartbeatIntervalSeconds?.let {
                        HydraBoxApplication.networkHeartbeatIntervalSeconds = it
                        heartbeatChanged = true
                    }
                    flags.performanceMode?.let { HydraBoxApplication.performanceMode = it }
                    flags.memoryLimitEnabled?.let { HydraBoxApplication.memoryLimitEnabled = it }
                    if (heartbeatChanged) {
                        coreRuntimeClient.refreshRuntimeFlags()
                    }
                    callback(Result.success(Unit))
                }

                override fun reload(callback: (Result<Unit>) -> Unit) {
                    coreRuntimeClient.reload(callback)
                }

                override fun setRuntimeUiForeground(
                    foreground: Boolean,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    // Runtime event cadence is core-owned in 1.0.
                    callback(Result.success(Unit))
                }

                override fun ensureNotificationPermission(callback: (Result<Boolean>) -> Unit) {
                    ensureNotificationPermission(boolResult(callback))
                }

                override fun updateVpnNotificationPresentation(
                    presentation: NotificationPresentationMessage,
                    callback: (Result<Unit>) -> Unit,
                ) {
                    val value = CoreRuntimeProtocol.NotificationPresentation.newBuilder()
                        .setDetailed(presentation.detailed)
                        .setTrafficDisplayMode(presentation.trafficDisplayMode)
                        .setTitle(presentation.title)
                        .setGroupId(presentation.groupTag)
                        .setTargetOutboundId(presentation.targetOutboundTag)
                        .setPriorityOutboundId(presentation.priorityOutboundTag)
                        .setExcludedOutboundId(presentation.excludeOutboundTag)
                        .setUrl(presentation.url)
                        .setTimeoutMillis(presentation.timeoutMillis.coerceAtLeast(0).toInt())
                        .setConcurrency(presentation.concurrency.coerceAtLeast(0).toInt())
                        .setDeadlineMillis(presentation.deadlineMillis.coerceAtLeast(0).toInt())
                        .setConnectedText(presentation.connectedText)
                        .setCheckingText(presentation.checkingText)
                        .setUnavailableText(presentation.unavailableText)
                        .setRefreshLabel(presentation.refreshLabel)
                        .setStopLabel(presentation.stopLabel)
                    presentation.latencyMillis?.let(value::setLatencyMillis)
                    coreRuntimeClient.updateNotificationPresentation(value.build(), callback)
                }

                override fun stop(reason: String, callback: (Result<Unit>) -> Unit) {
                    coreRuntimeClient.stop(reason, callback)
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
                    coreRuntimeClient.selectOutbound(
                        groupTag.ifBlank { "select" },
                        normalizedTag,
                        callback,
                    )
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
                    callback(
                        errorResult(
                            "add_outbound_unsupported",
                            "Rebuild and apply the compiled runtime plan to add an outbound.",
                        ),
                    )
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
                    callback(
                        errorResult(
                            "remove_outbound_unsupported",
                            "Rebuild and apply the compiled runtime plan to remove an outbound.",
                        ),
                    )
                }

                override fun urlTest(request: UrlTestRequestMessage, callback: (Result<Unit>) -> Unit) {
                    val targets = request.targetOutboundTag.trim()
                        .takeIf(String::isNotEmpty)?.let(::listOf).orEmpty()
                    coreRuntimeClient.startProbe(
                        groupId = request.groupTag.ifBlank { "select" },
                        outboundIds = targets,
                        url = request.url,
                        timeoutMillis = request.timeoutMillis.toInt(),
                        concurrency = request.concurrency.toInt(),
                        deadlineMillis = request.deadlineMillis.toInt(),
                    ) { result ->
                        callback(result.map { Unit })
                    }
                }

                override fun startManagedUrlTest(
                    request: UrlTestRequestMessage,
                    callback: (Result<Map<String?, Any?>>) -> Unit,
                ) {
                    val targets = request.targetOutboundTag.trim()
                        .takeIf(String::isNotEmpty)?.let(::listOf).orEmpty()
                    coreRuntimeClient.startProbe(
                        groupId = request.groupTag.ifBlank { "select" },
                        outboundIds = targets,
                        url = request.url,
                        timeoutMillis = request.timeoutMillis.toInt(),
                        concurrency = request.concurrency.toInt(),
                        deadlineMillis = request.deadlineMillis.toInt(),
                    ) { result -> callback(result.map(::pigeonMap)) }
                }

                override fun getManagedUrlTestSession(
                    sessionId: String,
                    callback: (Result<Map<String?, Any?>>) -> Unit,
                ) {
                    coreRuntimeClient.getProbeSession(sessionId) { result ->
                        callback(result.map(::pigeonMap))
                    }
                }

                override fun cancelManagedUrlTest(
                    sessionId: String,
                    callback: (Result<Map<String?, Any?>>) -> Unit,
                ) {
                    coreRuntimeClient.cancelProbe(sessionId) { result ->
                        callback(result.map(::pigeonMap))
                    }
                }

                override fun getRuntimeSnapshot(
                    callback: (Result<Map<String?, Any?>>) -> Unit,
                ) {
                    coreRuntimeClient.snapshot { snapshotResult ->
                        snapshotResult.onSuccess { snapshot ->
                            callback(Result.success(snapshot.toLegacyRuntimeMap()))
                        }.onFailure {
                            callback(errorResult("runtime_snapshot_failed", it.message))
                        }
                    }
                }

                override fun preconnectUrlTest(
                    request: PreconnectUrlTestRequestMessage,
                    callback: (Result<PreconnectUrlTestResultMessage>) -> Unit,
                ) {
                    coreRuntimeClient.preconnectProbe(
                        config = request.config.toByteArray(Charsets.UTF_8),
                        groupId = request.groupTag,
                        outboundId = request.targetOutboundTag,
                        url = request.url,
                        timeoutMillis = request.timeoutMillis.toInt(),
                        deadlineMillis = request.deadlineMillis.toInt(),
                    ) { probeResult ->
                        probeResult.onSuccess { value ->
                            callback(
                                Result.success(
                                    PreconnectUrlTestResultMessage(
                                        tag = value.outboundId,
                                        delayMillis = value.delayMillis,
                                        timeSeconds = value.measuredAtMillis / 1000L,
                                        status = if (value.delayMillis > 0L) "available" else "unavailable",
                                        error = value.error.safeMessage,
                                        errorCode = value.error.code,
                                    ),
                                ),
                            )
                        }.onFailure { callback(errorResult("preconnect_urltest_failed", it.message)) }
                    }
                }

                override fun cancelPreconnectUrlTest(callback: (Result<Unit>) -> Unit) {
                    coreRuntimeClient.cancelPreconnectProbe(callback)
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
                    callback(
                        errorResult(
                            "remove_urltest_outbounds_unsupported",
                            "Rebuild and apply the compiled runtime plan to change probe outbounds.",
                        ),
                    )
                }

                override fun status(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    coreRuntimeClient.snapshot { snapshotResult ->
                        snapshotResult.onSuccess { snapshot ->
                            callback(Result.success(snapshot.toLegacyRuntimeMap()))
                        }.onFailure {
                            callback(errorResult("runtime_snapshot_failed", it.message))
                        }
                    }
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
                    coreRuntimeClient.lookupOutboundExternalInfo(normalizedTag) { lookupResult ->
                        lookupResult
                            .onSuccess { callback(Result.success(pigeonMap(it))) }
                            .onFailure { callback(errorResult("lookup_outbound_external_info_failed", it.message)) }
                    }
                }

                override fun getNetworkInterfaceState(
                    callback: (Result<NetworkInterfaceStateMessage>) -> Unit,
                ) {
                    coreRuntimeClient.snapshot { result ->
                        result.onSuccess { snapshot ->
                            val network = snapshot.network
                            callback(
                                Result.success(
                                    NetworkInterfaceStateMessage(
                                        available = network.available,
                                        interfaceName = network.interfaceName.ifBlank { null },
                                        interfaceIndex = network.interfaceIndex.toLong(),
                                        generation = network.generation,
                                        reason = if (network.available) "core_snapshot" else "unavailable",
                                        updatedAtMillis = network.updatedAtMillis,
                                    ),
                                ),
                            )
                        }.onFailure {
                            callback(errorResult("network_snapshot_failed", it.message))
                        }
                    }
                }

                override fun exportLogs(
                    content: String,
                    suggestedName: String,
                    callback: (Result<String?>) -> Unit,
                ) {
                    launchLogExport(
                        content,
                        suggestedName,
                        nullableStringResult(callback),
                    )
                }

                override fun canInstallApks(callback: (Result<Boolean>) -> Unit) {
                    callback(Result.success(false))
                }

                override fun openApkInstallSettings(callback: (Result<Boolean>) -> Unit) {
                    callback(
                        errorResult(
                            "apk.install.external_only",
                            "HydraBox updates are installed from the verified GitHub release.",
                        ),
                    )
                }

                override fun installDownloadedApk(callback: (Result<Boolean>) -> Unit) {
                    callback(
                        errorResult(
                            "apk.install.external_only",
                            "HydraBox updates are installed from the verified GitHub release.",
                        ),
                    )
                }

                override fun verifyAppUpdateManifest(
                    manifest: ByteArray,
                    signature: ByteArray,
                    callback: (Result<Long>) -> Unit,
                ) {
                    ioExecutor.execute {
                        runCatching {
                            AppUpdateManifestVerifier(applicationContext)
                                .verifyAndRecord(manifest, signature)
                        }.onSuccess { releaseSequence ->
                            mainHandler.post { callback(Result.success(releaseSequence)) }
                        }.onFailure { error ->
                            mainHandler.post {
                                callback(errorResult("app_update_manifest_untrusted", error.message))
                            }
                        }
                    }
                }

                override fun recordIncident(
                    category: String,
                    code: String,
                    safePayload: String,
                    callback: (Result<String>) -> Unit,
                ) {
                    ioExecutor.execute {
                        val correlationId = UUID.randomUUID().toString()
                        runCatching {
                            val redacted = HydraBoxLogSanitizer.redact(safePayload)
                                .toByteArray(Charsets.UTF_8)
                                .let { bytes ->
                                    if (bytes.size <= 64 * 1024) bytes else bytes.copyOf(64 * 1024)
                                }
                            runBlocking {
                                val database = HydraDatabase.open(applicationContext)
                                IncidentRepository(
                                    database.incidents(),
                                    DomainCrypto(applicationContext),
                                ).record(
                                    category = category,
                                    code = code,
                                    correlationId = correlationId,
                                    safePayload = redacted,
                                )
                            }
                            correlationId
                        }.onSuccess { id ->
                            mainHandler.post { callback(Result.success(id)) }
                        }.onFailure { error ->
                            mainHandler.post {
                                callback(errorResult("incident_persistence_failed", error.message))
                            }
                        }
                    }
                }

                override fun inspectDownloadedApk(
                    path: String,
                    callback: (Result<DownloadedApkInspectionMessage>) -> Unit,
                ) {
                    val normalizedPath = path.trim()
                    if (normalizedPath.isEmpty()) {
                        callback(errorResult("missing_apk_path", "APK path is empty"))
                        return
                    }
                    ioExecutor.execute {
                        runCatching { inspectDownloadedApk(normalizedPath) }
                            .onSuccess { inspection ->
                                val message = DownloadedApkInspectionMessage(
                                    valid = inspection["valid"] == true,
                                    packageName = inspection["packageName"]?.toString().orEmpty(),
                                    installedPackageName = inspection["installedPackageName"]?.toString().orEmpty(),
                                    versionName = inspection["versionName"]?.toString().orEmpty(),
                                    versionCode = (inspection["versionCode"] as? Number)?.toLong() ?: 0L,
                                    minSdk = (inspection["minSdk"] as? Number)?.toLong() ?: 0L,
                                    targetSdk = (inspection["targetSdk"] as? Number)?.toLong() ?: 0L,
                                    deviceSdk = (inspection["deviceSdk"] as? Number)?.toLong() ?: 0L,
                                    signingCertificateSha256 =
                                        (inspection["signingCertificateSha256"] as? Iterable<*>)
                                            ?.map { it?.toString() }.orEmpty(),
                                    installedCertificateSha256 =
                                        (inspection["installedCertificateSha256"] as? Iterable<*>)
                                            ?.map { it?.toString() }.orEmpty(),
                                )
                                mainHandler.post { callback(Result.success(message)) }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    callback(errorResult("inspect_apk_failed", error.message))
                                }
                            }
                    }
                }

                override fun fetchUrlOnUnderlyingNetwork(
                    request: UnderlyingHttpRequestMessage,
                    callback: (Result<UnderlyingHttpResponseMessage>) -> Unit,
                ) {
                    val url = request.url.trim()
                    if (url.isEmpty()) {
                        callback(errorResult("missing_url", "URL is empty"))
                        return
                    }
                    val headers = request.headers.entries.mapNotNull { (name, value) ->
                        name?.trim()?.takeIf(String::isNotEmpty)?.let { it to value.orEmpty() }
                    }.toMap()
                    subscriptionNetworkExecutor.execute {
                        runCatching {
                            fetchUrlOnUnderlyingNetwork(
                                url,
                                headers,
                                request.maxBytes.toInt().coerceIn(1, 32 * 1024 * 1024),
                                request.timeoutMillis.toInt(),
                            )
                        }.onSuccess { response ->
                            val responseHeaders = (response["headers"] as? Map<*, *>)
                                .orEmpty()
                                .entries
                                .associate { (name, value) -> name?.toString() to value?.toString() }
                            val message = UnderlyingHttpResponseMessage(
                                statusCode = (response["statusCode"] as? Number)?.toLong() ?: 0L,
                                body = response["body"]?.toString().orEmpty(),
                                headers = responseHeaders,
                                finalUrl = response["finalUrl"]?.toString().orEmpty(),
                                network = response["network"]?.toString().orEmpty(),
                            )
                            mainHandler.post { callback(Result.success(message)) }
                        }.onFailure { error ->
                            mainHandler.post {
                                callback(errorResult("underlying_http_failed", error.message))
                            }
                        }
                    }
                }

                override fun resolveHostOnUnderlyingNetwork(
                    host: String,
                    callback: (Result<List<String?>>) -> Unit,
                ) {
                    val normalizedHost = host.trim()
                    if (normalizedHost.isEmpty()) {
                        callback(errorResult("missing_host", "Host is empty"))
                        return
                    }
                    endpointDnsExecutor.execute {
                        runCatching { resolveHostOnUnderlyingNetwork(normalizedHost) }
                            .onSuccess { addresses ->
                                mainHandler.post { callback(Result.success(addresses)) }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    callback(errorResult("underlying_dns_failed", error.message))
                                }
                            }
                    }
                }

                override fun getAndroidId(callback: (Result<String>) -> Unit) {
                    callback(
                        Result.success(
                            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "",
                        ),
                    )
                }

                override fun getHydraDeviceId(
                    canonicalOrigin: String,
                    callback: (Result<String>) -> Unit,
                ) {
                    callback(
                        runCatching {
                            HydraDeviceIdentity.forOrigin(
                                applicationContext,
                                canonicalOrigin,
                            )
                        },
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
                    coreRuntimeClient.coreString(
                        CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VERSION,
                        callback = callback,
                    )
                }

                override fun getCoreCapabilities(callback: (Result<String>) -> Unit) {
                    Log.i(TAG, "platform_bridge_call name=getCoreCapabilities")
                    runHydraCoreApi(
                        { result ->
                            Log.i(
                                TAG,
                                "platform_bridge_result name=getCoreCapabilities success=${result.isSuccess}",
                            )
                            callback(result)
                        },
                        "hydraCoreCapabilities",
                    )
                }

                override fun getHydraCoreBuildInfo(callback: (Result<String>) -> Unit) {
                    runHydraCoreApi(callback, "hydraCoreBuildInfo")
                }

                override fun validateHydraConfig(
                    content: String,
                    profile: String,
                    callback: (Result<String>) -> Unit,
                ) {
                    runHydraCoreApi(callback, "hydraCoreValidateConfig", content, profile)
                }

                override fun validateHydraSubscription(
                    content: String,
                    callback: (Result<String>) -> Unit,
                ) {
                    runHydraCoreApi(callback, "hydraCoreValidateSubscription", content)
                }

                override fun inspectHydraSubscription(
                    content: String,
                    callback: (Result<String>) -> Unit,
                ) {
                    runHydraCoreApi(callback, "hydraCoreInspectSubscription", content)
                }

                override fun openHydraSubscriptionJwe(
                    envelope: String,
                    keyBase64Url: String,
                    callback: (Result<String>) -> Unit,
                ) {
                    runHydraCoreApi(
                        callback,
                        "hydraCoreOpenSubscriptionJWE",
                        envelope,
                        keyBase64Url,
                    )
                }

                override fun validateHydraSubscriptionJwe(
                    envelope: String,
                    keyBase64Url: String,
                    callback: (Result<String>) -> Unit,
                ) {
                    runHydraCoreApi(
                        callback,
                        "hydraCoreValidateSubscriptionJWE",
                        envelope,
                        keyBase64Url,
                    )
                }

                override fun inspectHydraSubscriptionJwe(
                    envelope: String,
                    keyBase64Url: String,
                    callback: (Result<String>) -> Unit,
                ) {
                    runHydraCoreApi(
                        callback,
                        "hydraCoreInspectSubscriptionJWE",
                        envelope,
                        keyBase64Url,
                    )
                }

                override fun checkConfig(config: String, callback: (Result<Unit>) -> Unit) {
                    coreRuntimeClient.checkConfig(config, callback)
                }

                override fun getPerformanceSnapshot(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(Result.success(pigeonMap(buildPerformanceSnapshot())))
                }

                override fun getHappCrypt5Support(callback: (Result<Map<String?, Any?>>) -> Unit) {
                    callback(Result.success(pigeonMap(getHappCrypt5Support())))
                }

                override fun getInstalledApps(callback: (Result<List<InstalledAppMessage?>>) -> Unit) {
                    Thread {
                        runCatching { getInstalledApps() }
                            .onSuccess { apps ->
                                mainHandler.post {
                                    callback(
                                        Result.success(
                                            apps.map { app ->
                                                InstalledAppMessage(
                                                    packageName = app.packageName,
                                                    label = app.label,
                                                    system = app.system,
                                                    launchable = app.launchable,
                                                )
                                            },
                                        ),
                                    )
                                }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    callback(errorResult("get_installed_apps_failed", error.message ?: error.toString()))
                                }
                            }
                    }.start()
                }

                override fun getInstalledAppIcon(
                    packageName: String,
                    sizePx: Long,
                    callback: (Result<ByteArray?>) -> Unit,
                ) {
                    appIconExecutor.execute {
                        val icon = getInstalledAppIcon(packageName, sizePx.toInt())
                        mainHandler.post { callback(Result.success(icon)) }
                    }
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
        val binaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        // Core recovery is the emergency control plane. Register it before the
        // runtime API and before attempting to bind :core so a failed native
        // process can never make its own repair action unreachable.
        coreManagerHostApiHandler = CoreManagerHostApiHandler(
            context = applicationContext,
            runtimeClient = { coreRuntimeClient },
            cycleCoreProcess = ::cycleCoreProcessForBundleChange,
        ).also { handler ->
            CoreManagerHostApi.setUp(binaryMessenger, handler)
        }
        Log.i(TAG, "platform_bridge_ready name=core_manager")

        setupSingboxHostApi(binaryMessenger)
        Log.i(TAG, "platform_bridge_ready name=singbox")

        // Binding is deliberately last. bindService() may fail synchronously
        // on OEM builds or when security software blocks the service process;
        // platform and recovery APIs must remain usable in either case.
        coreRuntimeClient.connect()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            secureStorageMethodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getOrCreateHiveDataKey" -> runCatching {
                    SecureHiveKeyProvider.getOrCreateDataKey(applicationContext)
                }.onSuccess(result::success).onFailure { error ->
                    result.error(
                        "secure_storage_key_failed",
                        error.message ?: error.toString(),
                        null,
                    )
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) {
                        return
                    }
                    singboxEventConsumer?.let(coreRuntimeClient::unregisterEventConsumer)
                    val consumer = object : RuntimeEventConsumer {
                        override fun success(event: Any?) = events.success(event)

                        override fun error(code: String, message: String?, details: Any?) =
                            events.error(code, message, details)

                        override fun endOfStream() = events.endOfStream()
                    }
                    singboxEventConsumer = consumer
                    coreRuntimeClient.registerEventConsumer(consumer)
                }

                override fun onCancel(arguments: Any?) {
                    singboxEventConsumer?.let(coreRuntimeClient::unregisterEventConsumer)
                    singboxEventConsumer = null
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
                        launchVpnPermission(intent, result)
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
                    coreRuntimeClient.coreString(
                        CoreRuntimeProtocol.CoreUtilityKind.CORE_UTILITY_KIND_VERSION,
                    ) { value ->
                        value.onSuccess(result::success)
                            .onFailure { result.error("hydracore_api_failed", it.message, null) }
                    }
                }

                "getCoreCapabilities" -> {
                    runHydraCoreMethodCall(result, "hydraCoreCapabilities")
                }

                "getHydraCoreBuildInfo" -> runHydraCoreMethodCall(
                    result,
                    "hydraCoreBuildInfo",
                )

                "validateHydraConfig" -> runHydraCoreMethodCall(
                    result,
                    "hydraCoreValidateConfig",
                    call.argument<String>("content").orEmpty(),
                    call.argument<String>("profile").orEmpty(),
                )

                "validateHydraSubscription" -> runHydraCoreMethodCall(
                    result,
                    "hydraCoreValidateSubscription",
                    call.argument<String>("content").orEmpty(),
                )

                "inspectHydraSubscription" -> runHydraCoreMethodCall(
                    result,
                    "hydraCoreInspectSubscription",
                    call.argument<String>("content").orEmpty(),
                )

                "openHydraSubscriptionJwe" -> runHydraCoreMethodCall(
                    result,
                    "hydraCoreOpenSubscriptionJWE",
                    call.argument<String>("envelope").orEmpty(),
                    call.argument<String>("keyBase64Url").orEmpty(),
                )

                "validateHydraSubscriptionJwe" -> runHydraCoreMethodCall(
                    result,
                    "hydraCoreValidateSubscriptionJWE",
                    call.argument<String>("envelope").orEmpty(),
                    call.argument<String>("keyBase64Url").orEmpty(),
                )

                "inspectHydraSubscriptionJwe" -> runHydraCoreMethodCall(
                    result,
                    "hydraCoreInspectSubscriptionJWE",
                    call.argument<String>("envelope").orEmpty(),
                    call.argument<String>("keyBase64Url").orEmpty(),
                )

                "checkConfig" -> {
                    val config = call.argument<String>("config").orEmpty()
                    coreRuntimeClient.checkConfig(config) { checkResult ->
                        checkResult.onSuccess { result.success(null) }
                            .onFailure { error ->
                                result.error("config_check_failed", error.message, null)
                            }
                    }
                }

                "getConfigPath" -> {
                    result.success(HydraBoxApplication.configFile.absolutePath)
                }

                "getRuntimeFlags" -> {
                    result.success(
                        mapOf(
                            "wakeLockEnabled" to HydraBoxApplication.wakeLockEnabled,
                            "networkHeartbeatEnabled" to HydraBoxApplication.networkHeartbeatEnabled,
                            "networkHeartbeatIntervalSeconds" to HydraBoxApplication.networkHeartbeatIntervalSeconds,
                            "performanceMode" to HydraBoxApplication.performanceMode,
                            "memoryLimitEnabled" to HydraBoxApplication.memoryLimitEnabled,
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
                        HydraBoxApplication.wakeLockEnabled = wakeLock
                    }
                    if (heartbeat != null) {
                        HydraBoxApplication.networkHeartbeatEnabled = heartbeat
                        heartbeatChanged = true
                    }
                    if (heartbeatInterval != null) {
                        HydraBoxApplication.networkHeartbeatIntervalSeconds = heartbeatInterval.toLong()
                        heartbeatChanged = true
                    }
                    if (performanceMode != null) {
                        HydraBoxApplication.performanceMode = performanceMode
                    }
                    if (memoryLimitEnabled != null) {
                        HydraBoxApplication.memoryLimitEnabled = memoryLimitEnabled
                    }
                    if (heartbeatChanged) {
                        coreRuntimeClient.refreshRuntimeFlags()
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
                        "proxy" -> HydraBoxProxyService::class.java
                        else -> HydraBoxVpnService::class.java
                    }
                    startService(Intent(this, serviceClass).setAction(HydraBoxService.ACTION_RELOAD))
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

                "startManagedUrlTest" -> {
                    SingboxController.startManagedUrlTest(
                        groupTag = call.argument<String>("groupTag") ?: "select",
                        targetOutboundTag = call.argument<String>("targetOutboundTag").orEmpty(),
                        priorityOutboundTag = call.argument<String>("priorityOutboundTag").orEmpty(),
                        excludeOutboundTag = call.argument<String>("excludeOutboundTag").orEmpty(),
                        url = call.argument<String>("url").orEmpty(),
                        timeoutMillis = call.argument<Number>("timeoutMillis")?.toInt() ?: 3_000,
                        concurrency = call.argument<Number>("concurrency")?.toInt() ?: 0,
                        deadlineMillis = call.argument<Number>("deadlineMillis")?.toInt() ?: 10_000,
                        force = call.argument<Boolean>("force") ?: true,
                    ) { managedResult ->
                        managedResult
                            .onSuccess(result::success)
                            .onFailure { result.error("urltest_failed", it.message, null) }
                    }
                }

                "getManagedUrlTestSession" -> {
                    SingboxController.getManagedUrlTestSession(
                        call.argument<String>("sessionId").orEmpty(),
                    ) { sessionResult ->
                        sessionResult
                            .onSuccess(result::success)
                            .onFailure { result.error("urltest_session_failed", it.message, null) }
                    }
                }

                "cancelManagedUrlTest" -> {
                    SingboxController.cancelManagedUrlTest(
                        call.argument<String>("sessionId").orEmpty(),
                    ) { sessionResult ->
                        sessionResult
                            .onSuccess(result::success)
                            .onFailure { result.error("urltest_cancel_failed", it.message, null) }
                    }
                }

                "getRuntimeSnapshot" -> {
                    SingboxController.getRuntimeSnapshot { snapshotResult ->
                        snapshotResult
                            .onSuccess(result::success)
                            .onFailure { result.error("runtime_snapshot_failed", it.message, null) }
                    }
                }

                "preconnectUrlTest" -> {
                    val config = call.argument<String>("config").orEmpty()
                    val groupTag = call.argument<String>("groupTag").orEmpty()
                    val targetOutboundTag = call.argument<String>("targetOutboundTag").orEmpty()
                    if (config.isBlank() || groupTag.isBlank() || targetOutboundTag.isBlank()) {
                        result.error(
                            "invalid_preconnect_request",
                            "Config, group tag and selected outbound are required",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    SingboxController.preconnectUrlTest(
                        config = config,
                        groupTag = groupTag,
                        targetOutboundTag = targetOutboundTag,
                        url = call.argument<String>("url").orEmpty(),
                        timeoutMillis = call.argument<Number>("timeoutMillis")?.toInt() ?: 5_000,
                        deadlineMillis = call.argument<Number>("deadlineMillis")?.toInt() ?: 10_000,
                    ) { probeResult ->
                        probeResult.onSuccess { value ->
                            result.success(
                                mapOf(
                                    "tag" to value.tag,
                                    "delayMillis" to value.delayMillis,
                                    "timeSeconds" to value.timeSeconds,
                                    "status" to value.status,
                                    "error" to value.error,
                                    "errorCode" to value.errorCode,
                                ),
                            )
                        }.onFailure {
                            result.error("preconnect_urltest_failed", it.message, null)
                        }
                    }
                }

                "cancelPreconnectUrlTest" -> {
                    SingboxController.cancelPreconnectUrlTest("flutter_method_channel") { cancellation ->
                        cancellation.onSuccess { result.success(true) }
                            .onFailure { result.error("preconnect_cleanup_failed", it.message, null) }
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
                    val state = HydraBoxDefaultNetworkMonitor.currentInterfaceState("method_channel")
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

                "exportLogs" -> {
                    val content = call.argument<String>("content") ?: ""
                    val suggestedName = call.argument<String>("suggestedName")
                        ?: "hydrabox-logs-${System.currentTimeMillis()}.txt"
                    launchLogExport(content, suggestedName, result)
                }

                "getAndroidId" -> {
                    result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "",
                    )
                }

                "getHydraDeviceId" -> {
                    val canonicalOrigin = call.argument<String>("canonicalOrigin").orEmpty()
                    runCatching {
                        HydraDeviceIdentity.forOrigin(applicationContext, canonicalOrigin)
                    }.onSuccess(result::success).onFailure { error ->
                        result.error("hydra_device_id_failed", error.message, null)
                    }
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

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchImportDeepLink(intent)
    }

    override fun onStop() {
        coreRuntimeClient.cancelPreconnectProbe { }
        super.onStop()
    }

    override fun onDestroy() {
        activityDestroyed = true
        coreManagerHostApiHandler?.close()
        coreManagerHostApiHandler = null
        singboxEventConsumer?.let(coreRuntimeClient::unregisterEventConsumer)
        singboxEventConsumer = null
        coreRuntimeClient.close()
        deepLinkEventSink = null
        super.onDestroy()
    }

    private fun cycleCoreProcessForBundleChange(
        mutation: () -> Unit,
        callback: (Result<Unit>) -> Unit,
    ) {
        val previousClient = coreRuntimeClient
        singboxEventConsumer?.let(previousClient::unregisterEventConsumer)
        previousClient.close()
        ioExecutor.execute {
            stopService(Intent(applicationContext, CoreRuntimeService::class.java))
            val mutationResult = runCatching {
                terminateCoreProcess()
                mutation()
            }
            mainHandler.post {
                if (activityDestroyed) return@post
                val replacement = CoreRuntimeClient(applicationContext)
                mutableCoreRuntimeClient = replacement
                singboxEventConsumer?.let(replacement::registerEventConsumer)
                replacement.connect()
                replacement.contract { handshake ->
                    callback(
                        mutationResult.fold(
                            onSuccess = {
                                handshake.fold(
                                    onSuccess = { Result.success(Unit) },
                                    onFailure = { Result.failure(it) },
                                )
                            },
                            onFailure = { Result.failure(it) },
                        ),
                    )
                }
            }
        }
    }

    private fun terminateCoreProcess() {
        val processName = "$packageName:core"
        val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        activityManager.runningAppProcesses.orEmpty()
            .firstOrNull { it.processName == processName }
            ?.pid
            ?.takeIf { it != android.os.Process.myPid() }
            ?.let(android.os.Process::killProcess)
        val deadline = SystemClock.elapsedRealtime() + CORE_PROCESS_EXIT_DEADLINE_MILLIS
        while (SystemClock.elapsedRealtime() < deadline) {
            val stillAlive = activityManager.runningAppProcesses.orEmpty()
                .any { it.processName == processName }
            if (!stillAlive) return
            Thread.sleep(CORE_PROCESS_EXIT_POLL_MILLIS)
        }
        check(
            activityManager.runningAppProcesses.orEmpty().none {
                it.processName == processName
            },
        ) { "HydraCore process did not stop for version change" }
    }

    override fun onResume() {
        super.onResume()
    }
}
