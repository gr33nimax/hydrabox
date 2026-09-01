package io.hydrabox.core.config

data class ConfigInput(val proxyDnsResolver: String, val ready: Boolean)

object ConfigGenerator {
    fun generate(input: ConfigInput): String {
        check(input.ready) { "DNS must reject requests before runtime is ready" }
        return """{"log":{"level":"warn"},"dns":{"servers":[{"tag":"dns-local","address":"local"},{"tag":"dns-proxy","address":"${input.proxyDnsResolver}","domain_resolver":"dns-local"}],"final":"dns-proxy"},"outbounds":[{"type":"direct","tag":"direct"}],"route":{"default_domain_resolver":"dns-local","final":"direct"}}"""
    }
}
