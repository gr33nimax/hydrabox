package io.hydrabox.platform.android

import io.hydrabox.core.subscription.HydraSubscriptionUri
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream

/**
 * Fetches a subscription body over HTTP. Deliberately platform-side: the core modules
 * stay free of a network stack, and the `:core` process never needs the network to build a
 * configuration because the body is stored once, here.
 */
object SubscriptionFetcher {
    private const val MAX_BYTES = 12 * 1024 * 1024
    private const val TIMEOUT_MILLIS = 20_000
    private const val MAX_REDIRECTS = 5

    fun fetch(url: String): String {
        var target = URL(url)
        var redirects = 0
        while (true) {
            val connection = (target.openConnection() as HttpURLConnection).apply {
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
                instanceFollowRedirects = false
                requestMethod = "GET"
                setRequestProperty("User-Agent", "HydraBox/2.0.0-alpha1")
                setRequestProperty("Accept-Encoding", "gzip")
                setRequestProperty(
                    "Accept",
                    "${HydraSubscriptionUri.PLAINTEXT_MEDIA_TYPE}, ${HydraSubscriptionUri.ENCRYPTED_MEDIA_TYPE}, */*",
                )
            }
            try {
                val code = connection.responseCode
                if (code in 301..308 && code != 304) {
                    val location = connection.getHeaderField("Location")
                        ?: error("subscription redirect without a location")
                    check(++redirects <= MAX_REDIRECTS) { "too many subscription redirects" }
                    target = URL(target, location)
                    continue
                }
                check(code == HttpURLConnection.HTTP_OK) { "subscription responded with HTTP $code" }
                val stream = connection.inputStream.let {
                    if (connection.contentEncoding.equals("gzip", ignoreCase = true)) GZIPInputStream(it) else it
                }
                val buffer = ByteArrayOutputStream()
                stream.use { input ->
                    val chunk = ByteArray(16 * 1024)
                    while (true) {
                        val read = input.read(chunk)
                        if (read <= 0) break
                        check(buffer.size() + read <= MAX_BYTES) { "subscription exceeds 12 MiB" }
                        buffer.write(chunk, 0, read)
                    }
                }
                return buffer.toByteArray().decodeToString().trim()
                    .also { check(it.isNotEmpty()) { "subscription body is empty" } }
            } finally {
                connection.disconnect()
            }
        }
    }
}
