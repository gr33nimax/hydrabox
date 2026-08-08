package io.hydrabox.client.singbox

import java.net.URI

internal object HydraBoxVkCaptchaUrlPolicy {
    fun isSafeLoopbackUrl(rawUrl: String): Boolean {
        return runCatching {
            val uri = URI(rawUrl)
            uri.scheme.equals("http", ignoreCase = true) &&
                (uri.host == "127.0.0.1" || uri.host.equals("localhost", ignoreCase = true)) &&
                uri.port in 1..65535
        }.getOrDefault(false)
    }
}
