package io.hydrabox.client.core

import android.content.Context
import android.util.AtomicFile
import io.hydrabox.client.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import javax.net.ssl.HttpsURLConnection

data class CheckedCoreRelease(
    val releaseId: Long,
    val releaseSequence: Long,
    val version: String,
    val publishedAt: String,
    val coreApiMajor: Int,
    val coreApiMinor: Int,
    val artifactSizeBytes: Long,
)

enum class CoreReleaseChannel(val id: String) {
    STABLE("stable"),
    DEBUG("debug");

    companion object {
        fun parse(value: String): CoreReleaseChannel =
            entries.firstOrNull { it.id == value.trim().lowercase() } ?: DEBUG
    }
}

/** Explicit-only updater. Construction never performs network I/O. */
class CoreBundleUpdater(
    context: Context,
    private val verifier: CoreBundleSignatureVerifier = CoreBundleSignatureVerifier(),
) {
    private val appContext = context.applicationContext
    private val manager = CoreBundleManager(appContext, verifier)
    private val checkDirectory = File(appContext.noBackupFilesDir, "hydracore/update-check-v1")
    private val checkedManifest = File(checkDirectory, MANIFEST_ASSET)
    private val checkedSignature = File(checkDirectory, SIGNATURE_ASSET)
    private val checkedReleaseId = File(checkDirectory, "release-id.txt")
    private val preferences = appContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun selectedChannel(): CoreReleaseChannel = CoreReleaseChannel.parse(
        preferences.getString(RELEASE_CHANNEL, null).orEmpty(),
    )

    /** Called only from the user's Check action. */
    fun checkLatest(channel: CoreReleaseChannel): CheckedCoreRelease {
        check(verifier.hasTrustedKeys()) { "No trusted HydraCore release key is installed" }
        val releases = readJsonArray(
            api("releases", "per_page=$RELEASE_PAGE_SIZE"),
            MAX_RELEASES_JSON_BYTES,
        )
        val release = selectCoreBundleRelease(
            releases,
            requiredAssets = setOf(MANIFEST_ASSET, SIGNATURE_ASSET),
            channel = channel,
        )
        val releaseId = release.getLong("id")
        require(releaseId > 0L) { "HydraCore GitHub release id is invalid" }
        val manifestAssetId = assetId(release, MANIFEST_ASSET)
        val signatureAssetId = assetId(release, SIGNATURE_ASSET)
        val manifestBytes = downloadAsset(manifestAssetId, CoreBundleManifest.MAX_MANIFEST_BYTES)
        val signatureBytes = downloadAsset(signatureAssetId, ED25519_SIGNATURE_BYTES)
        val manifest = CoreBundleManifest.parse(manifestBytes)
        verifier.verify(manifestBytes, signatureBytes, manifest.keyId)
        val artifact = manifest.artifactForAbi(selectedAbi(manifest))
            ?: throw IllegalStateException("HydraCore release has no compatible artifact")
        // Resolve the signed asset name in the same fixed GitHub release now;
        // no URL from the signed document is accepted or persisted.
        assetId(release, artifact.assetName)
        persistCheckedRelease(releaseId, manifestBytes, signatureBytes)
        check(preferences.edit().putString(RELEASE_CHANNEL, channel.id).commit()) {
            "Cannot persist HydraCore release channel"
        }
        return CheckedCoreRelease(
            releaseId = releaseId,
            releaseSequence = manifest.releaseSequence,
            version = manifest.version,
            publishedAt = manifest.publishedAt.toString(),
            coreApiMajor = manifest.coreApiMajor,
            coreApiMinor = manifest.coreApiMinor,
            artifactSizeBytes = artifact.sizeBytes,
        )
    }

    /** Called only from the user's Download action after a successful check. */
    fun downloadChecked(): InstalledCoreBundle {
        val releaseId = checkedReleaseId.readText(Charsets.US_ASCII).trim().toLong()
        require(releaseId > 0L) { "Checked HydraCore release id is invalid" }
        val manifestBytes = checkedManifest.readBytes()
        val signatureBytes = checkedSignature.readBytes()
        val manifest = CoreBundleManifest.parse(manifestBytes)
        verifier.verify(manifestBytes, signatureBytes, manifest.keyId)
        val artifact = manifest.artifactForAbi(selectedAbi(manifest))
            ?: throw IllegalStateException("HydraCore release has no compatible artifact")
        val release = readJson(api("releases/$releaseId"), MAX_RELEASE_JSON_BYTES)
        require(release.getLong("id") == releaseId && !release.optBoolean("draft", true)) {
            "Checked HydraCore release is no longer available"
        }
        val artifactAssetId = assetId(release, artifact.assetName)
        require(artifact.sizeBytes in 1..MAX_ARTIFACT_DOWNLOAD_BYTES.toLong()) {
            "HydraCore artifact exceeds the client download limit"
        }
        require(checkDirectory.mkdirs() || checkDirectory.isDirectory)
        val temporaryArtifact = File(checkDirectory, "candidate-download.part")
        return try {
            downloadAssetToFile(
                assetId = artifactAssetId,
                maximumBytes = artifact.sizeBytes,
                destination = temporaryArtifact,
            )
            FileInputStream(temporaryArtifact).use { artifactStream ->
                manager.stageCandidate(manifestBytes, signatureBytes, artifactStream)
            }
        } finally {
            temporaryArtifact.delete()
        }
    }

    private fun persistCheckedRelease(
        releaseId: Long,
        manifest: ByteArray,
        signature: ByteArray,
    ) {
        require(checkDirectory.mkdirs() || checkDirectory.isDirectory)
        writeAtomic(checkedManifest, manifest)
        writeAtomic(checkedSignature, signature)
        writeAtomic(checkedReleaseId, "$releaseId\n".toByteArray(Charsets.US_ASCII))
    }

    private fun writeAtomic(file: File, bytes: ByteArray) {
        val atomic = AtomicFile(file)
        var output: FileOutputStream? = null
        try {
            output = atomic.startWrite()
            output.write(bytes)
            atomic.finishWrite(output)
        } catch (error: Throwable) {
            output?.let(atomic::failWrite)
            throw error
        }
    }

    private fun assetId(release: JSONObject, name: String): Long {
        val assets = release.getJSONArray("assets")
        var found = 0L
        for (index in 0 until assets.length()) {
            val asset = assets.getJSONObject(index)
            if (asset.optString("name") != name) continue
            require(found == 0L) { "HydraCore release contains duplicate asset names" }
            found = asset.getLong("id")
            require(found > 0L && asset.optLong("size", 0L) > 0L) {
                "HydraCore release asset metadata is invalid"
            }
        }
        require(found > 0L) { "HydraCore release asset is missing: $name" }
        return found
    }

    private fun selectedAbi(manifest: CoreBundleManifest): String =
        android.os.Build.SUPPORTED_ABIS.firstOrNull { manifest.artifactForAbi(it) != null }
            ?: throw IllegalStateException("HydraCore release does not support this device")

    private fun downloadAsset(assetId: Long, maximumBytes: Int): ByteArray =
        request(
            api("releases/assets/$assetId"),
            maximumBytes,
            accept = "application/octet-stream",
        )

    private fun downloadAssetToFile(
        assetId: Long,
        maximumBytes: Long,
        destination: File,
    ) {
        if (destination.exists()) check(destination.delete())
        try {
            requestToFile(
                initialUrl = api("releases/assets/$assetId"),
                maximumBytes = maximumBytes,
                accept = "application/octet-stream",
                destination = destination,
            )
        } catch (error: Throwable) {
            destination.delete()
            throw error
        }
    }

    private fun readJson(url: URL, maximumBytes: Int): JSONObject =
        JSONObject(request(url, maximumBytes, "application/vnd.github+json").toString(Charsets.UTF_8))

    private fun readJsonArray(url: URL, maximumBytes: Int): JSONArray =
        JSONArray(request(url, maximumBytes, "application/vnd.github+json").toString(Charsets.UTF_8))

    private fun request(initialUrl: URL, maximumBytes: Int, accept: String): ByteArray {
        require(maximumBytes in 1..MAX_ARTIFACT_DOWNLOAD_BYTES)
        var current = initialUrl
        repeat(MAX_REDIRECTS + 1) { redirectCount ->
            require(current.protocol.equals("https", ignoreCase = true)) { "HTTPS is required" }
            val connection = current.openConnection() as HttpsURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = READ_TIMEOUT_MILLIS
            connection.setRequestProperty("Accept", accept)
            connection.setRequestProperty("User-Agent", "HydraBox/${BuildConfig.VERSION_NAME}")
            connection.setRequestProperty("X-GitHub-Api-Version", GITHUB_API_VERSION)
            val status = connection.responseCode
            if (status in REDIRECT_CODES) {
                require(redirectCount < MAX_REDIRECTS) { "Too many HydraCore download redirects" }
                val location = connection.getHeaderField("Location")
                    ?: throw IllegalStateException("HydraCore redirect has no location")
                val redirected = current.toURI().resolve(location).toURL()
                require(redirected.protocol.equals("https", ignoreCase = true)) {
                    "HydraCore download cannot downgrade HTTPS"
                }
                current = redirected
                connection.disconnect()
                return@repeat
            }
            require(status == HttpURLConnection.HTTP_OK) {
                "HydraCore GitHub request failed with HTTP $status"
            }
            val declared = connection.contentLengthLong
            require(declared <= 0L || declared <= maximumBytes.toLong()) {
                "HydraCore download exceeds the declared size limit"
            }
            val output = ByteArrayOutputStream(minOf(maximumBytes, 64 * 1024))
            connection.inputStream.use { input ->
                val buffer = ByteArray(64 * 1024)
                var received = 0
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    received += read
                    require(received <= maximumBytes) { "HydraCore download is too large" }
                    output.write(buffer, 0, read)
                }
            }
            connection.disconnect()
            return output.toByteArray()
        }
        throw IllegalStateException("HydraCore request did not complete")
    }

    private fun requestToFile(
        initialUrl: URL,
        maximumBytes: Long,
        accept: String,
        destination: File,
    ) {
        require(maximumBytes in 1..MAX_ARTIFACT_DOWNLOAD_BYTES.toLong())
        var current = initialUrl
        repeat(MAX_REDIRECTS + 1) { redirectCount ->
            require(current.protocol.equals("https", ignoreCase = true)) { "HTTPS is required" }
            val connection = current.openConnection() as HttpsURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = READ_TIMEOUT_MILLIS
            connection.setRequestProperty("Accept", accept)
            connection.setRequestProperty("User-Agent", "HydraBox/${BuildConfig.VERSION_NAME}")
            connection.setRequestProperty("X-GitHub-Api-Version", GITHUB_API_VERSION)
            val status = connection.responseCode
            if (status in REDIRECT_CODES) {
                require(redirectCount < MAX_REDIRECTS) { "Too many HydraCore download redirects" }
                val location = connection.getHeaderField("Location")
                    ?: throw IllegalStateException("HydraCore redirect has no location")
                val redirected = current.toURI().resolve(location).toURL()
                require(redirected.protocol.equals("https", ignoreCase = true)) {
                    "HydraCore download cannot downgrade HTTPS"
                }
                current = redirected
                connection.disconnect()
                return@repeat
            }
            require(status == HttpURLConnection.HTTP_OK) {
                "HydraCore GitHub request failed with HTTP $status"
            }
            val declared = connection.contentLengthLong
            require(declared <= 0L || declared <= maximumBytes) {
                "HydraCore download exceeds the declared size limit"
            }
            var received = 0L
            FileOutputStream(destination).buffered().use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        received += read.toLong()
                        require(received <= maximumBytes) { "HydraCore download is too large" }
                        output.write(buffer, 0, read)
                    }
                }
            }
            connection.disconnect()
            require(received == maximumBytes) { "HydraCore artifact size does not match the manifest" }
            return
        }
        throw IllegalStateException("HydraCore request did not complete")
    }

    private fun api(path: String, query: String? = null): URL =
        URI("https", "api.github.com", "/repos/$FIXED_REPOSITORY/$path", query, null).toURL()

    companion object {
        private const val FIXED_REPOSITORY = "gr33nimax/hydracore"
        private const val PREFERENCES = "hydracore-updater-v1"
        private const val RELEASE_CHANNEL = "release-channel"
        private const val MANIFEST_ASSET = "hydracore-bundle-manifest-v1.json"
        private const val SIGNATURE_ASSET = "hydracore-bundle-manifest-v1.sig"
        private const val GITHUB_API_VERSION = "2022-11-28"
        private const val ED25519_SIGNATURE_BYTES = 64
        private const val MAX_RELEASE_JSON_BYTES = 512 * 1024
        private const val MAX_RELEASES_JSON_BYTES = 2 * 1024 * 1024
        private const val RELEASE_PAGE_SIZE = 30
        private const val MAX_ARTIFACT_DOWNLOAD_BYTES = 256 * 1024 * 1024
        private const val CONNECT_TIMEOUT_MILLIS = 15_000
        private const val READ_TIMEOUT_MILLIS = 60_000
        private const val MAX_REDIRECTS = 5
        private val REDIRECT_CODES = setOf(301, 302, 303, 307, 308)
    }
}

/**
 * GitHub's `releases/latest` endpoint excludes prereleases. HydraCore bundle
 * releases can intentionally be prereleases while the embedded client core is
 * being qualified, so select the newest published release that actually
 * carries the signed update surface instead of following GitHub's stable tag.
 */
internal fun selectCoreBundleRelease(
    releases: JSONArray,
    requiredAssets: Set<String>,
    channel: CoreReleaseChannel,
): JSONObject {
    require(requiredAssets.isNotEmpty()) { "HydraCore bundle asset set is empty" }
    for (index in 0 until releases.length()) {
        val release = releases.optJSONObject(index) ?: continue
        if (release.optBoolean("draft", true) || release.optLong("id", 0L) <= 0L) continue
        val prerelease = release.optBoolean("prerelease", false)
        if (channel == CoreReleaseChannel.DEBUG && !prerelease) continue
        if (channel == CoreReleaseChannel.STABLE && prerelease) continue
        val assets = release.optJSONArray("assets") ?: continue
        val present = buildSet {
            for (assetIndex in 0 until assets.length()) {
                val asset = assets.optJSONObject(assetIndex) ?: continue
                if (asset.optLong("id", 0L) <= 0L || asset.optLong("size", 0L) <= 0L) continue
                asset.optString("name").takeIf(String::isNotBlank)?.let(::add)
            }
        }
        if (present.containsAll(requiredAssets)) return release
    }
    throw IllegalStateException("No published HydraCore bundle release is available")
}
