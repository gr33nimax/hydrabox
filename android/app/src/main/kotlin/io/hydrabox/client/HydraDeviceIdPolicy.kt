package io.hydrabox.client

import java.net.IDN
import java.net.URI
import java.security.MessageDigest
import java.util.Base64

internal object HydraDeviceIdPolicy {
    private const val DOMAIN_SEPARATOR = "hydrabox-hwid-v1"

    fun canonicalHttpsOrigin(value: String): String {
        val uri = URI(value.trim())
        require(uri.scheme.equals("https", ignoreCase = true)) {
            "Hydra device origin must use HTTPS"
        }
        require(uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null) {
            "Hydra device origin must not contain credentials, query or fragment"
        }
        require(uri.path.isNullOrEmpty() || uri.path == "/") {
            "Hydra device origin must not contain a path"
        }
        val rawHost = requireNotNull(uri.host) { "Hydra device origin host is missing" }
        val asciiHost = if (rawHost.contains(':')) {
            rawHost.lowercase()
        } else {
            IDN.toASCII(rawHost, IDN.USE_STD3_ASCII_RULES).lowercase()
        }
        val host = if (asciiHost.contains(':') && !asciiHost.startsWith("[")) {
            "[$asciiHost]"
        } else {
            asciiHost
        }
        val port = uri.port
        require(port == -1 || port in 1..65535) { "Hydra device origin port is invalid" }
        return if (port == -1 || port == 443) "https://$host" else "https://$host:$port"
    }

    fun derive(packageName: String, deviceComponent: String, origin: String): String {
        require(packageName.isNotBlank()) { "Package name is missing" }
        require(deviceComponent.isNotBlank()) { "Device identity is missing" }
        val canonicalOrigin = canonicalHttpsOrigin(origin)
        val input = buildString {
            append(DOMAIN_SEPARATOR)
            append('\u0000')
            append(packageName)
            append('\u0000')
            append(deviceComponent)
            append('\u0000')
            append(canonicalOrigin)
        }
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return "hbx1_" + Base64.getUrlEncoder().withoutPadding().encodeToString(digest)
    }
}
