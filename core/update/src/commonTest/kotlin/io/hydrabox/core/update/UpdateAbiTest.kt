package io.hydrabox.core.update

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class UpdateAbiTest {
    private val universal = "a".repeat(64)
    private val arm = "b".repeat(64)
    private val arm64 = "c".repeat(64)
    private fun body(artifactUrl: String = "https://example.org/arm.apk") = """
        {"schema":1,"channel":"stable","versionCode":228,"versionName":"2.1.1",
        "releaseTag":"v2.1.1-stable.1","apkUrl":"https://example.org/universal.apk",
        "sha256":"$universal","certificateSha256":"$universal","keyId":"key",
        "artifacts":{
            "armeabi-v7a":{"apkUrl":"$artifactUrl","sha256":"$arm"},
            "arm64-v8a":{"apkUrl":"https://example.org/arm64.apk","sha256":"$arm64"}
        }}
    """.trimIndent()

    private fun selected(vararg abis: String) =
        assertIs<UpdateDecision.Available>(decideUpdate(body(), true, "stable", 227, abis.toList())).manifest

    @Test fun `32 bit system selects arm even on a 64 bit capable processor`() {
        assertEquals("https://example.org/arm.apk", selected("armeabi-v7a", "armeabi").apkUrl)
        assertEquals(arm, selected("armeabi-v7a").sha256)
    }

    @Test fun `device preference wins and unsupported ABI falls back to universal`() {
        assertEquals(arm64, selected("arm64-v8a", "armeabi-v7a").sha256)
        assertEquals(universal, selected("x86_64").sha256)
        assertEquals(universal, selected().sha256)
    }

    @Test fun `invalid artifact cannot bypass signature or URL checks`() {
        assertEquals(UpdateFault.UNVERIFIED, assertIs<UpdateDecision.Refused>(decideUpdate(body(), false, "stable", 227, listOf("arm64-v8a"))).fault)
        assertEquals(UpdateFault.INSECURE_URL, assertIs<UpdateDecision.Refused>(decideUpdate(body("http://example.org/arm.apk"), true, "stable", 227)).fault)
    }

    @Test fun `legacy manifests still offer their original APK`() {
        val legacy = body().substringBefore(",\n        \"artifacts\"") + "}"
        // Use a manifest without the optional map, as published by 2.1.0.
        val parsed = assertIs<ManifestOutcome.Accepted>(UpdateManifestParser.parse(body())).manifest
        assertEquals(parsed.apkUrl, parsed.copy(artifacts = emptyMap()).forAbis(listOf("armeabi-v7a")).apkUrl)
    }
}
