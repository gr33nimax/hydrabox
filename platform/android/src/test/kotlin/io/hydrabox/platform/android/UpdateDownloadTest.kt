package io.hydrabox.platform.android

import android.app.DownloadManager
import io.hydrabox.core.update.UpdateManifest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * The parts of the update download that can be read without a device: how the file in "Downloads"
 * gets its name, and how Android's endings on a download are understood.
 *
 * A product version can span several builds: both the destination and the remembered download
 * must distinguish those releases so the first tap cannot try to install an earlier APK.
 */
class UpdateDownloadTest {
    private fun manifest(
        version: String,
        versionCode: Int = 209,
        releaseTag: String = "v$version",
        sha256: String = "00".repeat(32),
    ) =
        UpdateManifest(
            schema = 1,
            channel = "canary",
            versionCode = versionCode,
            versionName = version,
            releaseTag = releaseTag,
            apkUrl = "https://example.invalid/app.apk",
            sha256 = sha256,
            certificateSha256 = "11".repeat(32),
            keyId = "hydrabox-update-1",
        )

    @Test
    fun `the release and build code name the file in Downloads`() {
        assertEquals("hydrabox-2.0.0-canary.5-209-000000000000.apk", UpdateClient.fileName(manifest("2.0.0-canary.5")))
    }

    @Test
    fun `successive stable builds with the same version name cannot reuse the old APK`() {
        val previous = manifest("2.1.0", 221, "v2.1.0-stable.10", "aa".repeat(32))
        val offered = manifest("2.1.0", 222, "v2.1.0-stable.11", "bb".repeat(32))
        val downloaded = ApkDownloadReference(7L, previous.versionCode, previous.sha256)

        assertTrue(downloaded.matches(previous))
        assertFalse(downloaded.matches(offered))
        assertNotEquals(UpdateClient.fileName(previous), UpdateClient.fileName(offered))
    }

    @Test
    fun `different ABI artifacts of the same release have separate destinations`() {
        val universal = manifest("2.1.1", 228, "v2.1.1-stable.1", "aa".repeat(32))
        val arm = universal.copy(apkUrl = "https://example.invalid/arm.apk", sha256 = "bb".repeat(32))
        assertNotEquals(UpdateClient.fileName(universal), UpdateClient.fileName(arm))
        assertFalse(ApkDownloadReference(7L, 228, universal.sha256).matches(arm))
    }

    @Test
    fun `matching the build code alone does not identify the downloaded bytes`() {
        val offered = manifest("2.1.0", 222, "v2.1.0-stable.11", "bb".repeat(32))
        assertFalse(ApkDownloadReference(7L, 222, "aa".repeat(32)).matches(offered))
        assertFalse(ApkDownloadReference(7L, 221, offered.sha256).matches(offered))
        assertTrue(ApkDownloadReference(7L, 222, offered.sha256.uppercase()).matches(offered))
    }

    @Test
    fun `legacy download records without an artifact identity are not ready for install`() {
        assertFalse(ApkDownloadReference(7L, 0, "").matches(manifest("2.1.0")))
    }

    @Test
    fun `a release tag cannot turn the destination name into a path`() {
        val file = UpdateClient.fileName(manifest("2.1.0", releaseTag = "v../outside\\apk"))
        assertFalse(file.contains('/'))
        assertFalse(file.contains('\\'))
        assertTrue(file.endsWith("-209-000000000000.apk"))
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
