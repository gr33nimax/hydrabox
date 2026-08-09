package io.hydrabox.client.singbox

object HydraBoxLogSanitizer {
    private val ansiEscape = Regex("\u001B\\[[;\\d]*m")
    private val proxyUri = Regex(
        """\b(vless|vmess|trojan|ss|ssr|hysteria2|tuic)://[^\s\"'<>]+""",
        RegexOption.IGNORE_CASE,
    )
    private val httpUrl = Regex(
        """\b(https?://)([^/\s?#\"'<>]+)(?:[^\s\"'<>]*)?""",
        RegexOption.IGNORE_CASE,
    )
    private val jsonSecret = Regex(
        """(\"(?:uuid|password|private_key|pre_shared_key|server_key|token|access_token|authorization|cookie|headers?|custom_hwid)\"\s*:\s*)\"[^\"]*\"""",
        RegexOption.IGNORE_CASE,
    )
    private val namedSecret = Regex(
        """\b(uuid|password|passwd|private_key|pre_shared_key|server_key|token|access_token|authorization|cookie|x-hwid|custom_hwid|subscription(?:id)?)\s*[:=]\s*([^\s,;]+)""",
        RegexOption.IGNORE_CASE,
    )
    private val uuid = Regex(
        """\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b""",
        RegexOption.IGNORE_CASE,
    )
    private val ipv4 = Regex("""(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])""")
    private val bracketedIpv6 = Regex("""\[[0-9a-fA-F:%]+]""")

    fun redact(value: String): String {
        var result = value.replace(ansiEscape, "")
        result = result.replace(proxyUri) { match ->
            "${match.groupValues[1]}://<redacted>"
        }
        result = result.replace(httpUrl) { match ->
            "${match.groupValues[1]}${match.groupValues[2]}/<redacted>"
        }
        result = result.replace(jsonSecret) { match ->
            "${match.groupValues[1]}\"<redacted>\""
        }
        result = result.replace(namedSecret) { match ->
            "${match.groupValues[1]}=<redacted>"
        }
        result = result.replace(uuid, "<redacted-uuid>")
        result = result.replace(bracketedIpv6, "[<redacted-ip>]")
        result = result.replace(ipv4, "<redacted-ip>")
        return result
    }
}
