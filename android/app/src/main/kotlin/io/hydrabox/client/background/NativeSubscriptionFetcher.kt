package io.hydrabox.client.background

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import io.hydrabox.client.BuildConfig
import io.hydrabox.client.storage.RemoteSubscriptionSource
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

/** Fetches a remote subscription without starting a Flutter engine. */
class NativeSubscriptionFetcher(context: Context) {
    private val connectivity = context.applicationContext
        .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    fun fetch(source: RemoteSubscriptionSource): ByteArray {
        var current = URI(source.url).toURL()
        require(current.protocol == "https" || current.protocol == "http") {
            "Subscription URL must use HTTP or HTTPS"
        }
        val initialOrigin = current.origin()
        var allowSensitiveHeaders = true
        repeat(MAX_REDIRECTS + 1) { redirectCount ->
            val network = selectNonVpnNetwork()
            val connection = network.openConnection(current) as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = READ_TIMEOUT_MILLIS
            connection.setRequestProperty("Accept", "application/vnd.hydra.subscription+json, application/jose+json, */*")
            connection.setRequestProperty("User-Agent", "HydraBox/${BuildConfig.VERSION_NAME}")
            source.headers.forEach { (name, value) ->
                if (allowSensitiveHeaders || !name.isSensitiveHeader()) {
                    connection.setRequestProperty(name, value)
                }
            }
            val status = connection.responseCode
            if (status in REDIRECT_CODES) {
                require(redirectCount < MAX_REDIRECTS) { "Too many subscription redirects" }
                val location = connection.getHeaderField("Location")
                    ?: throw IOException("Subscription redirect has no location")
                val redirected = current.toURI().resolve(location).toURL()
                require(redirected.protocol == "https" || redirected.protocol == "http") {
                    "Subscription redirect uses an unsupported protocol"
                }
                require(!(current.protocol == "https" && redirected.protocol == "http")) {
                    "Subscription redirect cannot downgrade HTTPS"
                }
                if (redirected.origin() != initialOrigin) allowSensitiveHeaders = false
                current = redirected
                connection.disconnect()
                return@repeat
            }
            if (status != HttpURLConnection.HTTP_OK) {
                connection.disconnect()
                throw HttpStatusException(status)
            }
            try {
                val declaredSize = connection.contentLengthLong
                require(declaredSize <= 0L || declaredSize <= MAX_DOCUMENT_BYTES.toLong()) {
                    "Subscription exceeds the declared size limit"
                }
                val output = ByteArrayOutputStream(
                    minOf(
                        MAX_DOCUMENT_BYTES,
                        declaredSize.takeIf { it in 1..MAX_DOCUMENT_BYTES.toLong() }?.toInt()
                            ?: DEFAULT_BUFFER_BYTES,
                    ),
                )
                connection.inputStream.use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_BYTES)
                    var received = 0
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        received += read
                        require(received <= MAX_DOCUMENT_BYTES) { "Subscription is too large" }
                        output.write(buffer, 0, read)
                    }
                }
                return output.toByteArray()
            } finally {
                connection.disconnect()
            }
        }
        throw IOException("Subscription request did not complete")
    }

    private fun selectNonVpnNetwork(): Network {
        val candidates = connectivity.allNetworks.mapNotNull { network ->
            val capabilities = connectivity.getNetworkCapabilities(network) ?: return@mapNotNull null
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            ) {
                return@mapNotNull null
            }
            network to capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        }
        return candidates.sortedByDescending { it.second }.firstOrNull()?.first
            ?: throw IOException("No non-VPN network is available for subscription refresh")
    }

    private fun URL.origin(): String {
        val normalizedPort = when {
            port >= 0 -> port
            protocol == "https" -> 443
            else -> 80
        }
        return "${protocol.lowercase()}://${host.lowercase()}:$normalizedPort"
    }

    private fun String.isSensitiveHeader(): Boolean {
        val normalized = lowercase()
        return normalized in SENSITIVE_HEADERS || SENSITIVE_HEADER_PARTS.any(normalized::contains)
    }

    class HttpStatusException(val statusCode: Int) : IOException("HTTP $statusCode")

    companion object {
        private const val MAX_DOCUMENT_BYTES = 12 * 1024 * 1024
        private const val DEFAULT_BUFFER_BYTES = 64 * 1024
        private const val CONNECT_TIMEOUT_MILLIS = 15_000
        private const val READ_TIMEOUT_MILLIS = 60_000
        private const val MAX_REDIRECTS = 5
        private val REDIRECT_CODES = setOf(301, 302, 303, 307, 308)
        private val SENSITIVE_HEADERS = setOf(
            "authorization",
            "proxy-authorization",
            "cookie",
            "x-hwid",
        )
        private val SENSITIVE_HEADER_PARTS = setOf(
            "token",
            "secret",
            "password",
            "api-key",
            "apikey",
            "hwid",
        )
    }
}
