package io.hydrabox.client.update

import android.content.Context
import io.hydrabox.client.BuildConfig
import io.hydrabox.client.core.CoreBundleSignatureVerifier
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.time.Instant
import org.json.JSONObject

/** Verifies the raw signed client-update manifest and enforces monotonic releases. */
class AppUpdateManifestVerifier(
    context: Context,
    private val signatureVerifier: CoreBundleSignatureVerifier =
        CoreBundleSignatureVerifier(BuildConfig.HYDRABOX_UPDATE_RELEASE_PUBLIC_KEYS),
) {
    private val preferences = context.applicationContext.getSharedPreferences(
        "hydrabox_app_update_trust_v1",
        Context.MODE_PRIVATE,
    )

    @Synchronized
    fun verifyAndRecord(manifestBytes: ByteArray, detachedSignature: ByteArray): Long {
        check(signatureVerifier.hasTrustedKeys()) {
            "No trusted HydraBox update key is installed"
        }
        require(manifestBytes.isNotEmpty() && manifestBytes.size <= MAX_MANIFEST_BYTES) {
            "HydraBox update manifest size is invalid"
        }
        val decoder = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        val root = JSONObject(decoder.decode(ByteBuffer.wrap(manifestBytes)).toString())
        require(root.getInt("schemaVersion") == SCHEMA_VERSION) {
            "Unsupported HydraBox update manifest schema"
        }
        require(root.getString("distributionId") == DISTRIBUTION_ID) {
            "Unexpected HydraBox update distribution"
        }
        require(root.getString("packageName") == DISTRIBUTION_ID) {
            "HydraBox update package is incompatible"
        }
        val releaseSequence = root.getLong("releaseSequence")
        require(releaseSequence > 0L) { "HydraBox releaseSequence must be positive" }
        val keyId = root.getString("keyId")
        require(KEY_ID.matches(keyId)) { "HydraBox update key id is invalid" }
        require(COMMIT.matches(root.getString("sourceCommit"))) {
            "HydraBox update source commit is invalid"
        }
        Instant.parse(root.getString("publishedAt"))

        val highestSeen = preferences.getLong(HIGHEST_SEEN_SEQUENCE, 0L)
        require(releaseSequence >= highestSeen) {
            "HydraBox update manifest downgrade is not allowed"
        }
        signatureVerifier.verify(manifestBytes, detachedSignature, keyId)
        if (releaseSequence > highestSeen) {
            check(
                preferences.edit()
                    .putLong(HIGHEST_SEEN_SEQUENCE, releaseSequence)
                    .commit(),
            ) { "HydraBox update trust state could not be persisted" }
        }
        return releaseSequence
    }

    companion object {
        const val SCHEMA_VERSION = 1
        const val DISTRIBUTION_ID = "io.hydrabox.client"
        const val MAX_MANIFEST_BYTES = 256 * 1024
        private const val HIGHEST_SEEN_SEQUENCE = "highest_seen_sequence"
        private val KEY_ID = Regex("^[A-Za-z0-9._-]{1,64}$")
        private val COMMIT = Regex("^[0-9a-f]{40}$")
    }
}
