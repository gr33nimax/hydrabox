package io.hydrabox.core.update

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * The pair the release pipeline carries is a public key, and it ships inside every build, so it is
 * not a secret. It is also the exact shape that has to survive this translation, which is why the
 * assertion is about the key's bytes rather than about a string this test would have to predict.
 */
@OptIn(ExperimentalEncodingApi::class)
class PinnedUpdateKeysTest {
    private val published = "hydrabox-update-1=353GN3KyNH76Kh73yaLqJM2/zil8J+gD8/9YepqRMN4="
    private val publishedKeyBytes = Base64.Default.decode("353GN3KyNH76Kh73yaLqJM2/zil8J+gD8/9YepqRMN4=")

    private fun keys(json: String) =
        Json
            .parseToJsonElement(json)
            .jsonObject
            .getValue("keys")
            .jsonArray

    @Test fun `the pipeline shape becomes the shape the core reads`() {
        val json = PinnedUpdateKeys.toCoreJson(published)!!
        val entry = keys(json).single().jsonObject
        assertEquals("hydrabox-update-1", entry.getValue("key_id").jsonPrimitive.content)
        val translated = entry.getValue("public_key").jsonPrimitive.content
        // base64url and unpadded, because that is what the verifier decodes.
        assertEquals(false, translated.contains('+') || translated.contains('/') || translated.contains('='))
        // Padding optional on the way in: the translation writes it absent because that is what
        // the verifier's decoder expects, and this decoder has to be told to accept that.
        assertEquals(
            publishedKeyBytes.toList(),
            Base64.UrlSafe
                .withPadding(Base64.PaddingOption.ABSENT_OPTIONAL)
                .decode(translated)
                .toList(),
        )
    }

    @Test fun `several keys survive and so do newlines`() {
        val json = PinnedUpdateKeys.toCoreJson("$published\nother-1=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")!!
        assertEquals(
            listOf("hydrabox-update-1", "other-1"),
            keys(json).map {
                it.jsonObject
                    .getValue("key_id")
                    .jsonPrimitive.content
            },
        )
    }

    @Test fun `a list that cannot be read is refused rather than shortened`() {
        // Every one of these is a configuration mistake, and reading past it is how a list of one
        // trusted key quietly becomes a list of none.
        assertNull(PinnedUpdateKeys.toCoreJson(""))
        assertNull(PinnedUpdateKeys.toCoreJson("   "))
        assertNull(PinnedUpdateKeys.toCoreJson("hydrabox-update-1="))
        assertNull(PinnedUpdateKeys.toCoreJson("=353GN3KyNH76Kh73yaLqJM2/zil8J+gD8/9YepqRMN4="))
        assertNull(PinnedUpdateKeys.toCoreJson("hydrabox-update-1=not base64 at all"))
        // Right alphabet, wrong length: 8 bytes is not an Ed25519 public key.
        assertNull(PinnedUpdateKeys.toCoreJson("hydrabox-update-1=AAAAAAAAAAA="))
        // One good pair does not excuse one broken pair.
        assertNull(PinnedUpdateKeys.toCoreJson("$published,broken"))
    }
}
