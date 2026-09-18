package io.hydrabox.platform.android

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.util.Base64
import io.hydrabox.core.update.InstallFault
import io.hydrabox.core.update.PinnedUpdateKeys
import io.hydrabox.core.update.UpdateDecision
import io.hydrabox.core.update.UpdateManifest
import io.hydrabox.core.update.decideUpdate
import java.io.ByteArrayOutputStream
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

/**
 * What the system download knows about the artifact this channel offered.
 *
 * The download itself belongs to Android: it survives this process, it shows its own progress in
 * the shade, and it puts the file in "Downloads" where a person can find it again. What the app
 * keeps is the handle — the id Android returned — because that is the only thing the query, the
 * reader and the installer need, and it is not derivable from the outside. Everything else is
 * asked of the download manager every time it is needed.
 */
sealed interface ApkState {
    /** Nothing was asked for on this install, or the download is gone. */
    data object Missing : ApkState

    data class Downloading(
        val bytesDownloaded: Long,
        val totalBytes: Long,
    ) : ApkState

    data class Ready(
        val downloadId: Long,
    ) : ApkState

    /** Android stopped the download: no network, no space, a lost address. */
    data class Failed(
        val reason: Int,
    ) : ApkState
}

/**
 * The client half of the update path: fetch the signed manifest for a channel, let the core vouch
 * for the exact bytes, and then hand the artifact to Android — the download to the download
 * manager, the install to the installer.
 *
 * The download is deliberately not this application's work. A browser asking for an APK and a
 * phone updating itself are the same act from the person's side: a progress bar in the shade, a
 * finished file in "Downloads", a tap that opens the installer. Doing it here instead meant a
 * private copy in the cache, an invisible transfer and a session the installer had to be talked
 * into — three things that could fail with nowhere to look.
 *
 * Every function here blocks. Callers run them on the io executor, as every other network path in
 * this application does.
 */
object UpdateClient {
    // One fixed address per channel (ADR 0009). The address carries no version, no tag and no
    // decision of its own: everything that decides whether the document may be used is inside the
    // signed bytes, because a URL is a place rather than a claim.
    // One fixed address per channel, and the branch is the channel: a release publishes its own
    // channel file into its own branch, so nothing has to cross between release lines. Reading
    // every channel out of `canary` would have left the stable line unreachable the moment it
    // started releasing from anywhere else (ADR 0009).
    private const val REPOSITORY = "https://raw.githubusercontent.com/gr33nimax/hydrabox"
    private const val MAX_MANIFEST_BYTES = 64 * 1024
    private const val TIMEOUT_MILLIS = 20_000
    private const val APK_MIME = "application/vnd.android.package-archive"
    private const val PREFERENCES = "hydrabox-update"
    private const val KEY_DOWNLOAD_ID = "download_id"
    private const val KEY_DOWNLOAD_VERSION = "download_version"

    fun check(channel: String): UpdateCheck {
        val name = channel.trim().lowercase()
        val address = "$REPOSITORY/$name/update/$name"
        val body = read("$address.json", MAX_MANIFEST_BYTES) ?: return UpdateCheck.Unreachable
        val signature = read("$address.sig", MAX_MANIFEST_BYTES)?.decodeToString()?.trim().orEmpty()
        // The build carries `keyId=base64` pairs while the verifier reads a JSON list with the key
        // in base64url, so the shapes are translated here. A list that cannot be read becomes an
        // empty string, which verifies nothing — the only safe direction for this to fail in.
        val keys = PinnedUpdateKeys.toCoreJson(BuildConfig.HYDRABOX_UPDATE_PUBLIC_KEYS).orEmpty()
        // The key is the pinned one, never the one the document claims: a manifest that named its
        // own key would get to choose which of the pinned keys vouches for it.
        val verified =
            HydraCoreGate.verifyUpdateManifest(
                manifestBase64 = base64Url(body),
                signatureBase64 = signature,
                keyId = BuildConfig.HYDRABOX_UPDATE_KEY_ID,
                keysJson = keys,
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

    /** The name the artifact takes in "Downloads": the version names its own file. */
    fun fileName(manifest: UpdateManifest): String = "hydrabox-${manifest.versionName.trim()}.apk"

    /**
     * Starts the system download, the way a browser starts one.
     *
     * A finished notification is asked for on purpose: the tap on it is the install, and there is
     * nothing in this application that has to run for it to work.
     */
    fun startDownload(
        context: Context,
        manifest: UpdateManifest,
    ): Long? {
        val request =
            DownloadManager
                .Request(Uri.parse(manifest.apkUrl))
                .setTitle(fileName(manifest))
                .setMimeType(APK_MIME)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName(manifest))
                // An app that finds its own update usually knows the person wants it; roaming is
                // the one case where the cost is a surprise, so that stays at the default.
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(false)
        return try {
            val id = manager(context).enqueue(request)
            remember(context, id, manifest.versionName)
            HydraLog.info(AREA, "the system download of ${manifest.versionName} was started")
            id
        } catch (failure: Exception) {
            HydraLog.warn(AREA, "the system download could not be started", failure)
            null
        }
    }

    /** What Android knows about the download this application asked for, if it asked for one. */
    fun apkState(
        context: Context,
        manifest: UpdateManifest,
    ): ApkState {
        val id = rememberedId(context) ?: return ApkState.Missing
        // The handle belongs to one version: a newer release must not be reported as the file the
        // older one left behind.
        if (rememberedVersion(context) != manifest.versionName) return ApkState.Missing
        val query = DownloadManager.Query().setFilterById(id)
        return try {
            manager(context).query(query).use { cursor ->
                if (!cursor.moveToFirst()) return ApkState.Missing
                apkStateOf(
                    status = cursor.columnInt(DownloadManager.COLUMN_STATUS),
                    downloaded = cursor.columnLong(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                    total = cursor.columnLong(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                    reason = cursor.columnInt(DownloadManager.COLUMN_REASON),
                    downloadId = id,
                )
            }
        } catch (failure: Exception) {
            HydraLog.warn(AREA, "the system download could not be asked about itself", failure)
            ApkState.Missing
        }
    }

    /**
     * Checks the downloaded bytes against the signed manifest.
     *
     * Android refuses an APK signed by another key when it installs one, so the certificate is not
     * re-derived here: the digest is what binds these bytes to the document this channel signed,
     * and that is the claim worth checking before the installer is opened.
     */
    fun verify(
        context: Context,
        manifest: UpdateManifest,
        downloadId: Long,
    ): InstallFault? {
        val uri = downloadedUri(context, downloadId) ?: return InstallFault.UNREACHABLE
        val digest = MessageDigest.getInstance("SHA-256")
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    digest.update(buffer, 0, read)
                }
            } ?: return InstallFault.UNREACHABLE
            if (hex(digest.digest()).equals(manifest.sha256, ignoreCase = true)) {
                null
            } else {
                InstallFault.DIGEST_MISMATCH
            }
        } catch (failure: Exception) {
            HydraLog.warn(AREA, "the downloaded artifact could not be read back", failure)
            InstallFault.UNREACHABLE
        }
    }

    /**
     * The install itself, as the shade does it: the file the system downloaded, handed to the
     * installer with the one permission it needs to read it.
     */
    fun installIntent(
        context: Context,
        downloadId: Long,
    ): Intent? {
        val uri = downloadedUri(context, downloadId) ?: return null
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

/**
     * One download row as this application understands it.
     *
     * Android reports three endings — success, failure, and anything else still running — and the
     * mapping is kept away from the cursor so it can be read and tested without a device.
     */
    internal fun apkStateOf(
        status: Int,
        downloaded: Long,
        total: Long,
        reason: Int,
        downloadId: Long,
    ): ApkState =
        when (status) {
            DownloadManager.STATUS_SUCCESSFUL -> ApkState.Ready(downloadId)
            DownloadManager.STATUS_FAILED -> ApkState.Failed(reason)
            else -> ApkState.Downloading(downloaded, total)
        }

    fun forget(context: Context) {
        context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    private fun downloadedUri(
        context: Context,
        downloadId: Long,
    ): Uri? =
        try {
            manager(context).getUriForDownloadedFile(downloadId)
        } catch (failure: Exception) {
            HydraLog.warn(AREA, "the downloaded file has no readable address", failure)
            null
        }

    private fun remember(
        context: Context,
        id: Long,
        version: String,
    ) {
        context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_DOWNLOAD_ID, id)
            .putString(KEY_DOWNLOAD_VERSION, version)
            .apply()
    }

    private fun rememberedId(context: Context): Long? =
        context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getLong(KEY_DOWNLOAD_ID, 0L)
            .takeIf { it != 0L }

    private fun rememberedVersion(context: Context): String? =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(KEY_DOWNLOAD_VERSION, null)

    private fun manager(context: Context): DownloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun android.database.Cursor.columnInt(name: String): Int = getInt(getColumnIndexOrThrow(name))

    private fun android.database.Cursor.columnLong(name: String): Long = getLong(getColumnIndexOrThrow(name))

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
