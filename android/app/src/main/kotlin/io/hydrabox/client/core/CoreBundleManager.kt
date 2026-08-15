package io.hydrabox.client.core

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.system.Os
import android.system.OsConstants
import go.HydraNativeLoader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale

data class InstalledCoreBundle(
    val releaseSequence: Long,
    val version: String,
    val abi: String,
    val libraryPath: String,
    val sha256: String,
    val capabilitiesSha256: String,
)

data class CoreBundleState(
    val active: InstalledCoreBundle?,
    val previous: InstalledCoreBundle?,
    val candidate: InstalledCoreBundle?,
    val trustedKeyRingAvailable: Boolean,
    val usingEmbeddedFallback: Boolean,
)

/** Owns the embedded/active/previous HydraCore slots and their health journal. */
class CoreBundleManager(
    context: Context,
    private val signatureVerifier: CoreBundleSignatureVerifier =
        CoreBundleSignatureVerifier(),
) {
    private val appContext = context.applicationContext
    private val root = File(appContext.noBackupFilesDir, ROOT_DIRECTORY)
    private val versions = File(root, VERSIONS_DIRECTORY)
    private val staging = File(root, STAGING_DIRECTORY)
    private val prefs = appContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    @Synchronized
    fun readState(): CoreBundleState {
        val active = readSlot(ACTIVE_PREFIX)?.takeIf(::isInstalledFileValid)
        val previous = readSlot(PREVIOUS_PREFIX)?.takeIf(::isInstalledFileValid)
        val candidate = readSlot(CANDIDATE_PREFIX)?.takeIf(::isInstalledFileValid)
        return CoreBundleState(
            active = active,
            previous = previous,
            candidate = candidate,
            trustedKeyRingAvailable = signatureVerifier.hasTrustedKeys(),
            usingEmbeddedFallback = active == null,
        )
    }

    @Synchronized
    fun stageCandidate(
        manifestBytes: ByteArray,
        detachedSignature: ByteArray,
        artifactStream: InputStream,
    ): InstalledCoreBundle {
        val manifest = CoreBundleManifest.parse(manifestBytes)
        signatureVerifier.verify(manifestBytes, detachedSignature, manifest.keyId)
        val currentSequence = maxOf(
            prefs.getLong("${ACTIVE_PREFIX}sequence", 0L),
            prefs.getLong("highest_seen_sequence", 0L),
        )
        require(manifest.releaseSequence >= currentSequence) {
            "HydraCore downgrade is not allowed"
        }
        val abi = selectAbi(manifest)
        val artifact = manifest.artifactForAbi(abi)
            ?: throw IllegalArgumentException("HydraCore has no artifact for this ABI")
        require(artifact.minSdk <= Build.VERSION.SDK_INT) {
            "HydraCore requires a newer Android version"
        }
        ensureDirectories()
        File(root, CANDIDATE_LOADER_FAILURE_MARKER).delete()
        clearDirectory(staging)
        val temporary = File(staging, "${artifact.assetName}.part")
        val actual = copyAndDigest(artifactStream, temporary, artifact.sizeBytes)
        require(actual == artifact.sha256) { "HydraCore artifact digest mismatch" }
        makeReadOnly(temporary)

        val versionDirectory = File(
            versions,
            "${manifest.releaseSequence}-${safePathSegment(manifest.version)}",
        )
        val abiDirectory = File(versionDirectory, abi)
        require(abiDirectory.mkdirs() || abiDirectory.isDirectory) {
            "Cannot create HydraCore version directory"
        }
        val destination = File(abiDirectory, LIBRARY_FILE)
        if (destination.exists()) {
            require(destination.delete()) { "Cannot replace staged HydraCore candidate" }
        }
        atomicMove(temporary, destination)
        makeReadOnly(destination)
        val installed = InstalledCoreBundle(
            releaseSequence = manifest.releaseSequence,
            version = manifest.version,
            abi = abi,
            libraryPath = destination.canonicalPath,
            sha256 = artifact.sha256,
            capabilitiesSha256 = manifest.capabilitiesSha256,
        )
        require(isInstalledFileValid(installed)) { "Staged HydraCore candidate is invalid" }
        val editor = prefs.edit()
        writeSlot(editor, CANDIDATE_PREFIX, installed)
        editor.remove("candidate_probed_sequence")
        editor.remove("candidate_probed_sha256")
        require(editor.commit()) { "Cannot persist HydraCore candidate" }
        return installed
    }

    @Synchronized
    fun markCandidateProbed(releaseSequence: Long, sha256: String) {
        val candidate = readSlot(CANDIDATE_PREFIX)
            ?: throw IllegalStateException("No HydraCore candidate is staged")
        require(isInstalledFileValid(candidate)) { "HydraCore candidate is no longer valid" }
        require(candidate.releaseSequence == releaseSequence && candidate.sha256 == sha256) {
            "HydraCore probe report is stale"
        }
        require(
            prefs.edit()
                .putLong("candidate_probed_sequence", releaseSequence)
                .putString("candidate_probed_sha256", sha256)
                .commit(),
        ) { "Cannot persist HydraCore probe state" }
    }

    /** Called only after :core_probe has completed all validation fixtures. */
    @Synchronized
    fun activateCandidate(runtimeDisconnected: Boolean): InstalledCoreBundle {
        require(runtimeDisconnected) { "Disconnect runtime before activating HydraCore" }
        val candidate = readSlot(CANDIDATE_PREFIX)
            ?: throw IllegalStateException("No HydraCore candidate is staged")
        require(isInstalledFileValid(candidate)) { "HydraCore candidate is no longer valid" }
        require(
            prefs.getLong("candidate_probed_sequence", 0L) == candidate.releaseSequence &&
                prefs.getString("candidate_probed_sha256", null) == candidate.sha256,
        ) { "HydraCore candidate has not passed the isolated probe" }
        val active = readSlot(ACTIVE_PREFIX)?.takeIf(::isInstalledFileValid)
        val editor = prefs.edit()
        if (active == null) clearSlot(editor, PREVIOUS_PREFIX)
        else writeSlot(editor, PREVIOUS_PREFIX, active)
        writeSlot(editor, ACTIVE_PREFIX, candidate)
        clearSlot(editor, CANDIDATE_PREFIX)
        editor.remove("candidate_probed_sequence")
        editor.remove("candidate_probed_sha256")
        editor.putLong("highest_seen_sequence", candidate.releaseSequence)
        editor.putLong("healthy_sequence", 0L)
        editor.putInt("unhealthy_launches", 0)
        editor.remove("last_launch_at")
        require(editor.commit()) { "Cannot activate HydraCore candidate" }
        return candidate
    }

    @Synchronized
    fun restorePreviousOrEmbedded(): InstalledCoreBundle? {
        val previous = readSlot(PREVIOUS_PREFIX)?.takeIf(::isInstalledFileValid)
        val editor = prefs.edit()
        if (previous == null) clearSlot(editor, ACTIVE_PREFIX)
        else writeSlot(editor, ACTIVE_PREFIX, previous)
        clearSlot(editor, PREVIOUS_PREFIX)
        clearSlot(editor, CANDIDATE_PREFIX)
        editor.remove("candidate_probed_sequence")
        editor.remove("candidate_probed_sha256")
        editor.putLong("healthy_sequence", previous?.releaseSequence ?: 0L)
        editor.putInt("unhealthy_launches", 0)
        editor.remove("last_launch_at")
        require(editor.commit()) { "Cannot restore HydraCore" }
        pruneUnusedVersions()
        return previous
    }

    @Synchronized
    fun noteCoreProcessStart(nowMillis: Long = System.currentTimeMillis()): Boolean {
        val active = readSlot(ACTIVE_PREFIX)?.takeIf(::isInstalledFileValid) ?: return false
        if (prefs.getLong("healthy_sequence", 0L) == active.releaseSequence) return false
        val lastLaunch = prefs.getLong("last_launch_at", 0L)
        val insideFailureWindow = lastLaunch > 0L &&
            nowMillis - lastLaunch in 0..HEALTH_WINDOW_MILLIS
        val loaderFailed = File(root, LOADER_FAILURE_MARKER).exists()
        val launches = if (insideFailureWindow || loaderFailed) {
            prefs.getInt("unhealthy_launches", 0) + 1
        } else {
            1
        }
        File(root, LOADER_FAILURE_MARKER).delete()
        if (launches >= MAX_UNHEALTHY_LAUNCHES) {
            restorePreviousOrEmbedded()
            return true
        }
        require(
            prefs.edit()
                .putInt("unhealthy_launches", launches)
                .putLong("last_launch_at", nowMillis)
                .commit(),
        ) { "Cannot persist HydraCore launch state" }
        return false
    }

    @Synchronized
    fun markHealthy(releaseSequence: Long) {
        val active = readSlot(ACTIVE_PREFIX)
            ?: throw IllegalStateException("Embedded core health is tracked by the APK")
        require(active.releaseSequence == releaseSequence) {
            "HydraCore health generation is stale"
        }
        require(
            prefs.edit()
                .putLong("healthy_sequence", releaseSequence)
                .putInt("unhealthy_launches", 0)
                .remove("last_launch_at")
                .commit(),
        ) { "Cannot persist HydraCore health" }
        pruneUnusedVersions()
    }

    fun configureNativeLoader() {
        val active = readSlot(ACTIVE_PREFIX)?.takeIf(::isInstalledFileValid)
        if (active == null) {
            HydraNativeLoader.clearCandidate()
            return
        }
        HydraNativeLoader.configure(
            root.canonicalPath,
            active.libraryPath,
            active.sha256,
            File(root, LOADER_FAILURE_MARKER).canonicalPath,
            "active",
        )
    }

    fun configureCandidateLoaderForProbe() {
        val candidate = readSlot(CANDIDATE_PREFIX)?.takeIf(::isInstalledFileValid)
            ?: throw IllegalStateException("No valid HydraCore candidate is staged")
        HydraNativeLoader.configure(
            root.canonicalPath,
            candidate.libraryPath,
            candidate.sha256,
            File(root, CANDIDATE_LOADER_FAILURE_MARKER).canonicalPath,
            "candidate",
        )
    }

    private fun selectAbi(manifest: CoreBundleManifest): String =
        Build.SUPPORTED_ABIS.firstOrNull { manifest.artifactForAbi(it) != null }
            ?: throw IllegalArgumentException("HydraCore does not support this device ABI")

    private fun ensureDirectories() {
        require(root.mkdirs() || root.isDirectory) { "Cannot create HydraCore root" }
        require(versions.mkdirs() || versions.isDirectory) { "Cannot create HydraCore versions" }
        require(staging.mkdirs() || staging.isDirectory) { "Cannot create HydraCore staging" }
    }

    private fun copyAndDigest(input: InputStream, target: File, expectedSize: Long): String {
        val digest = MessageDigest.getInstance("SHA-256")
        var received = 0L
        FileOutputStream(target, false).use { output ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                received += read
                require(received <= expectedSize) { "HydraCore artifact exceeds manifest size" }
                digest.update(buffer, 0, read)
                output.write(buffer, 0, read)
            }
            output.fd.sync()
        }
        require(received == expectedSize) { "HydraCore artifact size mismatch" }
        return digest.digest().toHex()
    }

    private fun isInstalledFileValid(bundle: InstalledCoreBundle): Boolean = runCatching {
        val canonicalRoot = versions.canonicalFile
        val library = File(bundle.libraryPath).canonicalFile
        library.path.startsWith(canonicalRoot.path + File.separator) &&
            library.isFile &&
            !Files.isSymbolicLink(library.toPath()) &&
            sha256(library) == bundle.sha256
    }.getOrDefault(false)

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().toHex()
    }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02x".format(Locale.ROOT, it.toInt() and 0xff) }

    private fun makeReadOnly(file: File) {
        Os.chmod(
            file.absolutePath,
            OsConstants.S_IRUSR or OsConstants.S_IRGRP or OsConstants.S_IROTH,
        )
        require(!file.canWrite()) { "HydraCore native library remains writable" }
    }

    private fun atomicMove(source: File, destination: File) {
        try {
            Files.move(
                source.toPath(),
                destination.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(source.toPath(), destination.toPath())
        }
    }

    private fun readSlot(prefix: String): InstalledCoreBundle? {
        val sequence = prefs.getLong("${prefix}sequence", 0L)
        val version = prefs.getString("${prefix}version", null).orEmpty()
        val abi = prefs.getString("${prefix}abi", null).orEmpty()
        val path = prefs.getString("${prefix}path", null).orEmpty()
        val sha = prefs.getString("${prefix}sha256", null).orEmpty()
        val capabilitiesSha =
            prefs.getString("${prefix}capabilities_sha256", null).orEmpty()
        if (sequence <= 0L || version.isBlank() || abi.isBlank() ||
            path.isBlank() || !SHA_PATTERN.matches(sha) ||
            !SHA_PATTERN.matches(capabilitiesSha)
        ) return null
        return InstalledCoreBundle(sequence, version, abi, path, sha, capabilitiesSha)
    }

    private fun writeSlot(
        editor: SharedPreferences.Editor,
        prefix: String,
        bundle: InstalledCoreBundle,
    ) {
        editor.putLong("${prefix}sequence", bundle.releaseSequence)
        editor.putString("${prefix}version", bundle.version)
        editor.putString("${prefix}abi", bundle.abi)
        editor.putString("${prefix}path", bundle.libraryPath)
        editor.putString("${prefix}sha256", bundle.sha256)
        editor.putString("${prefix}capabilities_sha256", bundle.capabilitiesSha256)
    }

    private fun clearSlot(editor: SharedPreferences.Editor, prefix: String) {
        editor.remove("${prefix}sequence")
        editor.remove("${prefix}version")
        editor.remove("${prefix}abi")
        editor.remove("${prefix}path")
        editor.remove("${prefix}sha256")
        editor.remove("${prefix}capabilities_sha256")
    }

    private fun pruneUnusedVersions() {
        val keep = listOfNotNull(readSlot(ACTIVE_PREFIX), readSlot(PREVIOUS_PREFIX))
            .mapNotNull { File(it.libraryPath).parentFile?.parentFile?.canonicalPath }
            .toSet()
        versions.listFiles()?.forEach { directory ->
            if (directory.canonicalPath !in keep) {
                clearDirectory(directory)
                require(directory.delete() || !directory.exists()) {
                    "Cannot remove old HydraCore directory"
                }
            }
        }
    }

    private fun clearDirectory(directory: File) {
        val canonicalRoot = root.canonicalFile
        val canonical = directory.canonicalFile
        require(canonical.path.startsWith(canonicalRoot.path + File.separator)) {
            "Refusing to clear a path outside HydraCore root"
        }
        directory.listFiles()?.forEach { child ->
            if (child.isDirectory && !Files.isSymbolicLink(child.toPath())) {
                clearDirectory(child)
            }
            require(child.delete() || !child.exists()) { "Cannot remove old HydraCore file" }
        }
    }

    private fun safePathSegment(value: String): String =
        value.replace(Regex("[^0-9A-Za-z._+-]"), "_")

    companion object {
        private val SHA_PATTERN = Regex("^[0-9a-f]{64}$")
        private const val ROOT_DIRECTORY = "hydracore"
        private const val VERSIONS_DIRECTORY = "versions"
        private const val STAGING_DIRECTORY = "staging"
        private const val LIBRARY_FILE = "libbox.so"
        private const val LOADER_FAILURE_MARKER = "loader-failure.marker"
        private const val CANDIDATE_LOADER_FAILURE_MARKER = "candidate-loader-failure.marker"
        private const val PREFERENCES = "hydracore_bundle_state_v1"
        private const val ACTIVE_PREFIX = "active_"
        private const val PREVIOUS_PREFIX = "previous_"
        private const val CANDIDATE_PREFIX = "candidate_"
        private const val MAX_UNHEALTHY_LAUNCHES = 2
        private const val HEALTH_WINDOW_MILLIS = 60_000L
    }
}
