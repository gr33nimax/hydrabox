package io.hydrabox.client.singbox

object RuntimeServiceModeResolver {
    const val VPN = "vpn"
    const val PROXY = "proxy"

    fun configuredMode(inboundTypes: Iterable<String>): String? {
        val normalized = inboundTypes.map { it.trim().lowercase() }
        return when {
            normalized.any { it == "tun" } -> VPN
            normalized.any { it == "mixed" || it == "http" || it == "socks" } -> PROXY
            else -> null
        }
    }

    fun activeMode(runningMode: String?, vpnRecorded: Boolean, proxyRecorded: Boolean): String? {
        return when (runningMode?.trim()?.lowercase()) {
            VPN -> VPN
            PROXY -> PROXY
            else -> when {
                vpnRecorded -> VPN
                proxyRecorded -> PROXY
                else -> null
            }
        }
    }
}
