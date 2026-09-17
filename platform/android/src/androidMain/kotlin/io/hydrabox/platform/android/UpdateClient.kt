package io.hydrabox.platform.android

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import io.hydrabox.core.update.InstallFault
import io.hydrabox.core.update.UpdateDecision
import io.hydrabox.core.update.UpdateManifest
import io.hydrabox.core.update.decideUpdate
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

private const val AREA = "update"

/** What a check produced. "The question could not be asked" is not the same answer as "nothing new". */
sealed interface UpdateCheck {
    data class Decided(
        val decision: UpdateDecision,
    ) : UpdateCheck

    data object Unreachable : UpdateCheck
}

/** What staging an install produced. */
sealed interface InstallOutcome {
    /** Android's own confirmation is on screen. Nothing has been installed yet. */
    data object Started : InstallOutcome

    data class Refused(
        val fault: InstallFault,
    ) : InstallOutcome
}

/**
 * The client half of the update path: fetch the signed manifest for a channel, let the core vouch
 * for the exact bytes, and only then hand the artifact to Android's installer.
 *
 * Every function here blocks. Callers run them on the io executor, as every other network path in
 * this application does.
 */
object UpdateClient {
    // One fixed address per channel (ADR 0009). The address carries no version, no tag and no
    // decision of its own: everything that decides whether the document may be used is inside the
    // signed bytes, because a URL is a place rather than a claim.
    private const val BASE = "https://raw.githubusercontent.com/gr33nimax/hydrabox/canary/update/"
    private const val MAX_MANIFEST_BYTES = 64 * 1024
    private const val MAX_APK_BYTES = 256L * 1024 * 1024
    private const val TIMEOUT_MILLIS = 20_000
    private const val APK_NAME = "hydrabox-update.apk"

    fun check(channel: String): UpdateCheck {
        val name = channel.trim().lowercase()
        val body = read("$BASE$name.json", MAX_MANIFEST_BYTES) ?: return UpdateCheck.Unreachable
        val signature = read("$BASE$name.sig", MAX_MANIFEST_BYTES)?.decodeToString()?.trim().orEmpty()
        // The key is the pinned one, never the one the document claims: a manifest that named its
        // own key would get to choose which of the pinned keys vouches for it.
        val verified =
            HydraCoreGate.verifyUpdateManifest(
                manifestBase64 = base64Url(body),
                signatureBase64 = signature,
                keyId = BuildConfig.HYDRABOX_UPDATE_KEY_ID,
                keysJson = BuildConfig.HYDRABOX_UPDATE_PUBLIC_KEYS,
            )
        return UpdateCheck.Decided(
            decideUpdate(
                manifestBody = body.decodeToString(),
                signatureVerified = verified,
                selectedChannel = name,
                installedVersionCode = BuildConfig.VERSION_CODE,
            ),
        )
    }

    fun install(
        context: Context,
        manifest: UpdateManifest,
    ): InstallOutcome {
        val apk = File(context.cacheDir, APK_NAME)
        apk.delete()
        when (val fetched = download(manifest.apkUrl, apk)) {
            Fetched.Unreachable -> {
                return InstallOutcome.Refused(InstallFault.UNREACHABLE)
            }

            Fetched.TooLarge -> {
                apk.delete()
                return InstallOutcome.Refused(InstallFault.TOO_LARGE)
            }

            is Fetched.Whole -> {
                if (!fetched.digest.equals(manifest.sha256, ignoreCase = true)) {
                    apk.delete()
                    return InstallOutcome.Refused(InstallFault.DIGEST_MISMATCH)
                }
            }
        }
        // Android refuses an APK signed by another key on its own; checking here names the reason
        // instead of leaving a failed install without one.
        if (!certificateDigest(context, apk).equals(manifest.certificateSha256, ignoreCase = true)) {
            apk.delete()
            return InstallOutcome.Refused(InstallFault.CERTIFICATE_MISMATCH)
        }
        return stage(context, apk)
    }

    private sealed interface Fetched {
        data class Whole(
            val digest: String,
        ) : Fetched

        data object Unreachable : Fetched

        data object TooLarge : Fetched
    }

    private fun download(
        url: String,
        target: File,
    ): Fetched {
        val connection = open(url) ?: return Fetched.Unreachable
        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return Fetched.Unreachable
            if (connection.contentLengthLong > MAX_APK_BYTES) return Fetched.TooLarge
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            connection.inputStream.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        // The declared length is a claim; the count is the fact.
                        if (total > MAX_APK_BYTES) return Fetched.TooLarge
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                    }
                }
            }
            Fetched.Whole(hex(digest.digest()))
        } catch (failure: Exception) {
            HydraLog.warn(AREA, "the update artifact could not be read", failure)
            Fetched.Unreachable
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Hands the artifact to the installer through a session rather than a path: the system reads it
     * back through a descriptor this process opened, so no file URI is ever exposed to another app.
     */
    private fun stage(
        context: Context,
        apk: File,
    ): InstallOutcome {
        val installer = context.packageManager.packageInstaller
        val params =
            PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(context.packageName)
            }
        return try {
            val session = installer.openSession(installer.createSession(params))
            try {
                session.openWrite(APK_NAME, 0, apk.length).use { output ->
                    apk.inputStream().use { input -> input.copyTo(output) }
                    session.fsync(output)
                }
                val outcome =
                    PendingIntent.getBroadcast(
                        context,
                        0,
                        Intent(context, UpdateInstallReceiver::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                session.commit(outcome.intentSender)
            } finally {
                session.close()
            }
            InstallOutcome.Started
        } catch (failure: Exception) {
            HydraLog.warn(AREA, "the installer session could not be opened", failure)
            InstallOutcome.Refused(InstallFault.NO_INSTALLER)
        }
    }

    private fun certificateDigest(
        context: Context,
        apk: File,
    ): String? {
        @Suppress("DEPRECATION")
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                PackageManager.GET_SIGNATURES
            }
        val archive = context.packageManager.getPackageArchiveInfo(apk.absolutePath, flags) ?: return null
        val signers =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                archive.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                archive.signatures
            }
        val signer = signers?.firstOrNull() ?: return null
        return hex(MessageDigest.getInstance("SHA-256").digest(signer.toByteArray()))
    }

    /** Reads a small document with a ceiling, because the ceiling is the only thing a sender cannot lie about. */
    private fun read(
        url: String,
        limit: Int,
    ): ByteArray? {
        val connection = open(url) ?: return null
        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            val collected = ByteArrayOutputStream()
            val buffer = ByteArray(8 * 1024)
            connection.inputStream.use { input ->
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (collected.size() + read > limit) {
                        HydraLog.warn(AREA, "an update document exceeded its ceiling")
                        return null
                    }
                    collected.write(buffer, 0, read)
                }
            }
            collected.toByteArray()
        } catch (failure: Exception) {
            HydraLog.warn(AREA, "an update document could not be read", failure)
            null
        } finally {
            connection.disconnect()
        }
    }

    private fun open(url: String): HttpURLConnection? =
        try {
            (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
                instanceFollowRedirects = true
                requestMethod = "GET"
            }
        } catch (failure: Exception) {
            HydraLog.warn(AREA, "an update address could not be opened", failure)
            null
        }

    private fun base64Url(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

    /** One case and no locale: a digest compared across two machines has to be the same string. */
    private fun hex(bytes: ByteArray): String {
        val digits = "0123456789ABCDEF"
        val out = StringBuilder(bytes.size * 2)
        for (byte in bytes) {
            val value = byte.toInt() and 0xFF
            out.append(digits[value ushr 4]).append(digits[value and 0x0F])
        }
        return out.toString()
    }
}
