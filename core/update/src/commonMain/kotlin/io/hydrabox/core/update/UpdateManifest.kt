package io.hydrabox.core.update

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * A release manifest as it arrives from the network.
 *
 * Nothing in this file is trusted. The signature over the exact bytes has to be checked
 * against an allowlisted key before a caller acts on any of these values, and that check does
 * not happen here: this parser only refuses what is malformed on its face, so that a hostile
 * document cannot reach the installer through a shape mistake.
 *
 * A signature proves who wrote the document; it says nothing about whether the document
 * matches what is installed — comparing [versionCode] is the caller's job.
 */
data class UpdateManifest(
    val schema: Int,
    val channel: String,
    val versionCode: Int,
    val versionName: String,
    val releaseTag: String,
    val apkUrl: String,
    val sha256: String,
    val certificateSha256: String,
    val keyId: String,
    val signature: String,
) {
    /**
     * Whether this release is newer than the installed build. Equal is not newer: an update
     * that installs the same version code is a reinstall, and Android refuses it anyway.
     */
    fun isNewerThan(installedVersionCode: Int): Boolean = versionCode > installedVersionCode

    /** Whether the manifest names the release line a person selected. */
    fun matchesChannel(selected: String): Boolean = channel.equals(selected.trim(), ignoreCase = true)
}

/** Why a manifest cannot be used. One reason, so a caller can say something specific. */
enum class ManifestFault {
    /** Not a JSON object, or a field that has to be a number is not one. */
    MALFORMED,

    /** A schema this build does not know how to read. */
    UNSUPPORTED_SCHEMA,

    /** A field that must carry something carried nothing. */
    EMPTY_FIELD,

    /** An address that is not HTTPS: an update fetched in the clear is an update somebody else chose. */
    INSECURE_URL,

    /** A digest that is not a SHA-256. */
    BAD_DIGEST,
}

sealed interface ManifestOutcome {
    data class Accepted(
        val manifest: UpdateManifest,
    ) : ManifestOutcome

    data class Rejected(
        val fault: ManifestFault,
    ) : ManifestOutcome
}

object UpdateManifestParser {
    /** The only schema this client understands. A newer one is refused rather than guessed at. */
    const val SCHEMA = 1

    private const val HTTPS_PREFIX = "https://"
    private val digest = Regex("^[0-9a-fA-F]{64}$")
    private val json = Json { ignoreUnknownKeys = true }

    fun parse(body: String): ManifestOutcome {
        val root =
            runCatching { json.parseToJsonElement(body) }.getOrNull() as? JsonObject
                ?: return ManifestOutcome.Rejected(ManifestFault.MALFORMED)
        val schema = root.number("schema") ?: return ManifestOutcome.Rejected(ManifestFault.MALFORMED)
        if (schema != SCHEMA) return ManifestOutcome.Rejected(ManifestFault.UNSUPPORTED_SCHEMA)
        val versionCode = root.number("versionCode") ?: return ManifestOutcome.Rejected(ManifestFault.MALFORMED)
        if (versionCode <= 0) return ManifestOutcome.Rejected(ManifestFault.MALFORMED)
        val fields =
            listOf("channel", "versionName", "releaseTag", "apkUrl", "sha256", "certificateSha256", "keyId", "signature")
                .associateWith { root.text(it) }
        if (fields.values.any { it.isNullOrBlank() }) return ManifestOutcome.Rejected(ManifestFault.EMPTY_FIELD)
        val apkUrl = fields.getValue("apkUrl")!!
        if (!apkUrl.startsWith(HTTPS_PREFIX)) return ManifestOutcome.Rejected(ManifestFault.INSECURE_URL)
        val sha256 = fields.getValue("sha256")!!
        val certificateSha256 = fields.getValue("certificateSha256")!!
        if (!digest.matches(sha256) || !digest.matches(certificateSha256)) {
            return ManifestOutcome.Rejected(ManifestFault.BAD_DIGEST)
        }
        return ManifestOutcome.Accepted(
            UpdateManifest(
                schema = schema,
                channel = fields.getValue("channel")!!.trim().lowercase(),
                versionCode = versionCode,
                versionName = fields.getValue("versionName")!!.trim(),
                releaseTag = fields.getValue("releaseTag")!!.trim(),
                apkUrl = apkUrl,
                // Digests compare case-insensitively, so they are held in one case rather than
                // making every comparison remember to fold it.
                sha256 = sha256.lowercase(),
                certificateSha256 = certificateSha256.uppercase(),
                keyId = fields.getValue("keyId")!!.trim(),
                signature = fields.getValue("signature")!!.trim(),
            ),
        )
    }

    private fun JsonObject.number(name: String): Int? = this[name]?.jsonPrimitive?.intOrNull

    private fun JsonObject.text(name: String): String? = this[name]?.jsonPrimitive?.contentOrNull
}
