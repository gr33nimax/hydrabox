package io.hydrabox.core.update

import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/**
 * The pinned update keys, as the build carries them, translated into what the core reads.
 *
 * The two sides were written apart and their shapes differ: a release pipeline stores
 * `keyId=base64Key` pairs, one per line or comma, while the verifier takes a JSON list and
 * expects the key as base64url. Neither shape is wrong, and neither may be guessed at: a key
 * this function cannot read is a refusal, because the alternative — skipping an entry that
 * looks odd — is how a list of one trusted key quietly becomes a list of none.
 */
object PinnedUpdateKeys {
    private const val PUBLIC_KEY_BYTES = 32

    /**
     * The pinned pairs as JSON for the core, or null when they cannot be read.
     *
     * Null is a refusal, not an empty list: callers pass it through, the verifier finds no key it
     * may use, and nothing installs. That is the only safe direction for this to fail in.
     */
    @OptIn(ExperimentalEncodingApi::class)
    fun toCoreJson(pinned: String): String? {
        val entries =
            pinned
                .split(',', '\n')
                .map(String::trim)
                .filter(String::isNotEmpty)
        if (entries.isEmpty()) return null
        val decoded =
            entries.map { entry ->
                val divider = entry.indexOf('=')
                // The identifier is everything before the first `=`, and the key is everything
                // after it — including any `=` the key's own padding carries.
                if (divider <= 0 || divider == entry.lastIndex) return null
                val keyId = entry.substring(0, divider).trim()
                val key = entry.substring(divider + 1).trim()
                if (keyId.isEmpty() || key.isEmpty()) return null
                val bytes = runCatching { Base64.Default.decode(key) }.getOrNull() ?: return null
                // A key of the wrong length is not a key for this scheme; saying so here keeps the
                // verifier from having to guess later.
                if (bytes.size != PUBLIC_KEY_BYTES) return null
                keyId to Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT).encode(bytes)
            }
        return buildString {
            append("{\"keys\":[")
            decoded.forEachIndexed { index, (keyId, key) ->
                if (index > 0) append(',')
                append("{\"key_id\":\"")
                    .append(keyId)
                    .append("\",\"public_key\":\"")
                    .append(key)
                    .append("\"}")
            }
            append("]}")
        }
    }
}
