package io.hydrabox.core.update

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class UpdateDecisionTest {
    private val digest = "a".repeat(64)

    private fun manifest(
        channel: String = "canary",
        versionCode: Int = 201,
        apkUrl: String = "https://example.invalid/hydrabox.apk",
    ) = """
        {
          "schema": 1,
          "channel": "$channel",
          "versionCode": $versionCode,
          "versionName": "2.0.0-alpha9",
          "releaseTag": "v2.0.0-alpha9-canary",
          "apkUrl": "$apkUrl",
          "sha256": "$digest",
          "certificateSha256": "$digest",
          "keyId": "update-2026-01"
        }
        """.trimIndent()

    private fun fault(
        body: String,
        verified: Boolean = true,
        channel: String = "canary",
        installed: Int = 200,
    ): UpdateFault = assertIs<UpdateDecision.Refused>(decideUpdate(body, verified, channel, installed)).fault

    @Test fun `a document nobody vouched for is never examined`() {
        // The order is the whole point: an unverified document is refused before it is parsed,
        // so a malformed body cannot teach the caller anything about where parsing fails and a
        // well-formed one never reaches the channel or version rules.
        assertEquals(UpdateFault.UNVERIFIED, fault("not json at all", verified = false))
        assertEquals(UpdateFault.UNVERIFIED, fault(manifest(), verified = false))
    }

    @Test fun `a verified document is still refused when it is malformed`() {
        assertEquals(UpdateFault.MALFORMED, fault("not json at all"))
        assertEquals(UpdateFault.MALFORMED, fault("   "))
        assertEquals(UpdateFault.INSECURE_URL, fault(manifest(apkUrl = "http://example.invalid/app.apk")))
    }

    @Test fun `a release for another channel is refused rather than compared`() {
        assertEquals(UpdateFault.WRONG_CHANNEL, fault(manifest(channel = "stable"), channel = "canary"))
        assertEquals(UpdateFault.WRONG_CHANNEL, fault(manifest(channel = "canary"), channel = "stable"))
    }

    @Test fun `only a verified newer release becomes installable`() {
        val decision =
            decideUpdate(manifest(versionCode = 201), signatureVerified = true, selectedChannel = "canary", installedVersionCode = 200)
        assertEquals(201, assertIs<UpdateDecision.Available>(decision).manifest.versionCode)
    }

    @Test fun `the same version and an older one are not updates`() {
        // Switching release lines legitimately points at an older build, and an equal version
        // code is a reinstall Android would refuse; neither is a failure to show a person.
        assertIs<UpdateDecision.NoUpdate>(decideUpdate(manifest(versionCode = 200), true, "canary", 200))
        assertIs<UpdateDecision.NoUpdate>(decideUpdate(manifest(versionCode = 199), true, "canary", 200))
    }

    @Test fun `the channel a person chose decides and not the one in the document`() {
        val onStable = decideUpdate(manifest(channel = "stable", versionCode = 201), true, "stable", 200)
        assertEquals(201, assertIs<UpdateDecision.Available>(onStable).manifest.versionCode)
    }

    @Test fun `a release of the split shape is decided by its version code alone`() {
        // The new shape carries a plain semver version and a channel-qualified tag; neither is
        // what decides an update. The decision must still come from `versionCode`, so a newer
        // release of the new shape installs and an equal one does not.
        fun body(versionCode: Int) =
            """
            {
              "schema": 1,
              "channel": "canary",
              "versionCode": $versionCode,
              "versionName": "2.1.0",
              "releaseTag": "v2.1.0-canary.11",
              "apkUrl": "https://example.invalid/hydrabox.apk",
              "sha256": "$digest",
              "certificateSha256": "$digest",
              "keyId": "update-2026-01"
            }
            """.trimIndent()
        assertEquals(
            219,
            assertIs<UpdateDecision.Available>(
                decideUpdate(body(219), signatureVerified = true, selectedChannel = "canary", installedVersionCode = 218),
            ).manifest.versionCode,
        )
        assertIs<UpdateDecision.NoUpdate>(decideUpdate(body(218), true, "canary", 218))
    }
}
