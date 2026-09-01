package io.hydrabox.core.subscription

/**
 * URL handling for encrypted Hydra Subscription v2 sources.
 *
 * Cryptography and JWE validation belong exclusively to the core. The client's only job
 * here is to lift the out-of-band key out of the `#hydra-key=` fragment and strip that
 * fragment before any request goes out — a fragment never leaves the device, a query
 * parameter does, which is why a key found in the query is rejected outright rather than
 * quietly accepted.
 */
object HydraSubscriptionUri {
    const val PLAINTEXT_MEDIA_TYPE = "application/vnd.hydra.subscription+json"
    const val ENCRYPTED_MEDIA_TYPE = "application/jose+json"
    const val KEY_FRAGMENT_NAME = "hydra-key"

    private val keyPattern = Regex("^[A-Za-z0-9_-]{43}$")

    /** The 32-byte key as base64url, or null when the source carries none. */
    fun keyOf(url: String): String? {
        val values = fragmentValues(url)
        if (values.size != 1) return null
        return values.single().takeIf { keyPattern.matches(it) }
    }

    fun hasKeyFragment(url: String): Boolean = fragmentValues(url).isNotEmpty()

    /** True when the key was put where it would be sent to the server. */
    fun hasKeyQueryParameter(url: String): Boolean {
        val query = url.substringBefore('#').substringAfter('?', "")
        if (query.isEmpty()) return false
        return query.split('&', ';').any { member ->
            member.substringBefore('=').lowercase() == KEY_FRAGMENT_NAME
        }
    }

    /** The URL as it may be requested: never carrying the key. */
    fun withoutSecretFragment(url: String): String = url.substringBefore('#')

    private fun fragmentValues(url: String): List<String> {
        val fragment = url.substringAfter('#', "")
        if (fragment.isEmpty()) return emptyList()
        return fragment.split('&').mapNotNull { member ->
            val separator = member.indexOf('=')
            val name = if (separator < 0) member else member.substring(0, separator)
            if (name != KEY_FRAGMENT_NAME) null else if (separator < 0) "" else member.substring(separator + 1)
        }
    }
}
