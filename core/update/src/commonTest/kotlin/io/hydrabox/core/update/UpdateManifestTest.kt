package io.hydrabox.core.update

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

class UpdateManifestTest {
    private val digest = "a".repeat(64)

    private fun manifest(
        schema: Int = UpdateManifestParser.SCHEMA,
        channel: String = "canary",
        versionCode: Int = 201,
        apkUrl: String = "https://example.invalid/hydrabox.apk",
        sha256: String = digest,
        certificateSha256: String = digest,
        keyId: String = "update-2026-01",
    ) = """
        {
          "schema": $schema,
          "channel": "$channel",
          "versionCode": $versionCode,
          "versionName": "2.0.0-alpha9",
          "releaseTag": "v2.0.0-alpha9-canary",
          "apkUrl": "$apkUrl",
          "sha256": "$sha256",
          "certificateSha256": "$certificateSha256",
          "keyId": "$keyId"
        }
        """.trimIndent()

    private fun accepted(body: String): UpdateManifest = assertIs<ManifestOutcome.Accepted>(UpdateManifestParser.parse(body)).manifest

    private fun rejected(body: String): ManifestFault = assertIs<ManifestOutcome.Rejected>(UpdateManifestParser.parse(body)).fault

    @Test fun `a well formed manifest is read and its digests are held in one case`() {
        val parsed = accepted(manifest(sha256 = "A".repeat(64), certificateSha256 = "b".repeat(64)))
        assertEquals(201, parsed.versionCode)
        assertEquals("canary", parsed.channel)
        assertEquals("a".repeat(64), parsed.sha256)
        assertEquals("B".repeat(64), parsed.certificateSha256)
    }

    @Test fun `a document this build cannot read is refused rather than guessed at`() {
        assertEquals(ManifestFault.MALFORMED, rejected("not json at all"))
        assertEquals(ManifestFault.MALFORMED, rejected("[]"))
        assertEquals(ManifestFault.UNSUPPORTED_SCHEMA, rejected(manifest(schema = UpdateManifestParser.SCHEMA + 1)))
    }

    @Test fun `a manifest without a version cannot be compared with what is installed`() {
        assertEquals(
            ManifestFault.MALFORMED,
            rejected(manifest().replace("\"versionCode\": 201,", "")),
        )
    }

    @Test fun `an empty field stops the manifest before any of it is used`() {
        assertEquals(ManifestFault.EMPTY_FIELD, rejected(manifest(keyId = "")))
        assertEquals(ManifestFault.EMPTY_FIELD, rejected(manifest(channel = "  ")))
    }

    @Test fun `an update fetched in the clear is refused`() {
        assertEquals(ManifestFault.INSECURE_URL, rejected(manifest(apkUrl = "http://example.invalid/app.apk")))
    }

    @Test fun `a digest that is not a sha256 is refused`() {
        assertEquals(ManifestFault.BAD_DIGEST, rejected(manifest(sha256 = "abc")))
        assertEquals(ManifestFault.BAD_DIGEST, rejected(manifest(certificateSha256 = "z".repeat(64))))
    }

    @Test fun `equal is not newer`() {
        val parsed = accepted(manifest(versionCode = 200))
        assertFalse(parsed.isNewerThan(200), "installing the same version code is a reinstall, not an update")
        assertTrue(parsed.isNewerThan(199))
        assertFalse(accepted(manifest(versionCode = 20)).isNewerThan(200))
    }

    @Test fun `the channel has to match the one a person selected`() {
        val parsed = accepted(manifest(channel = "Canary"))
        assertTrue(parsed.matchesChannel("canary"))
        assertFalse(parsed.matchesChannel("stable"))
    }

    @Test fun `a release names the product as a plain semver and its channel only in the tag`() {
        // The split: `versionName` is the product's semver and carries no channel, while the
        // channel lives in `releaseTag` and in the `channel` field alone. The parser reads each
        // on its own, so a version that no longer embeds its channel is not a shape it refuses.
        val body =
            """
            {
              "schema": 1,
              "channel": "canary",
              "versionCode": 219,
              "versionName": "2.1.0",
              "releaseTag": "v2.1.0-canary.11",
              "apkUrl": "https://example.invalid/hydrabox.apk",
              "sha256": "$digest",
              "certificateSha256": "$digest",
              "keyId": "update-2026-01"
            }
            """.trimIndent()
        val parsed = accepted(body)
        assertEquals("2.1.0", parsed.versionName)
        assertEquals("v2.1.0-canary.11", parsed.releaseTag)
        assertEquals("canary", parsed.channel)
    }

    @Test fun `a manifest from before the split still parses`() {
        // The manifests the old scheme published named the version and the tag with the same
        // string, channel and all. An installed client still fetches them, so the parser has to
        // keep reading that shape rather than only the new one.
        val body =
            """
            {
              "schema": 1,
              "channel": "canary",
              "versionCode": 217,
              "versionName": "2.0.0-canary.9",
              "releaseTag": "2.0.0-canary.9",
              "apkUrl": "https://example.invalid/hydrabox.apk",
              "sha256": "$digest",
              "certificateSha256": "$digest",
              "keyId": "update-2026-01"
            }
            """.trimIndent()
        val parsed = accepted(body)
        assertEquals("2.0.0-canary.9", parsed.versionName)
        assertEquals("2.0.0-canary.9", parsed.releaseTag)
    }
}
