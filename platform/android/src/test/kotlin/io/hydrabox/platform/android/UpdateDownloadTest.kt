package io.hydrabox.platform.android

import android.app.DownloadManager
import io.hydrabox.core.update.UpdateManifest
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * The parts of the update download that can be read without a device: how the file in "Downloads"
 * gets its name, and how Android's endings on a download are understood.
 *
 * The name matters beyond tidiness: a later check finds the file by it and a person finds the
 * update in "Downloads" by it, so it is derived from the version rather than from a counter.
 */
class UpdateDownloadTest {
    private fun manifest(version: String) =
        UpdateManifest(
            schema = 1,
            channel = "canary",
            versionCode = 209,
            versionName = version,
            releaseTag = "v$version",
            apkUrl = "https://example.invalid/app.apk",
            sha256 = "00".repeat(32),
            certificateSha256 = "11".repeat(32),
            keyId = "hydrabox-update-1",
        )

    @Test
    fun `the version names the file in Downloads`() {
        assertEquals("hydrabox-2.0.0-canary.5.apk", UpdateClient.fileName(manifest("2.0.0-canary.5")))
    }

    @Test
    fun `a finished download is ready, a failed one keeps its reason, anything else is running`() {
        assertEquals(
            ApkState.Ready(7L),
            UpdateClient.apkStateOf(DownloadManager.STATUS_SUCCESSFUL, 10L, 10L, 0, 7L),
        )
        assertEquals(
            ApkState.Failed(1006),
            UpdateClient.apkStateOf(DownloadManager.STATUS_FAILED, 3L, 10L, 1006, 7L),
        )
        assertEquals(
            ApkState.Downloading(3L, 10L),
            UpdateClient.apkStateOf(DownloadManager.STATUS_RUNNING, 3L, 10L, 0, 7L),
        )
    }
}
