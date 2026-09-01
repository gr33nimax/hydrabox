package io.hydrabox.core.config

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFailsWith

class ConfigGeneratorTest {
    @Test fun `generated config pins domain resolver and proxy DNS final`() {
        val json = ConfigGenerator.generate(ConfigInput("https://dns.cloudflare.com/dns-query", ready = true))
        assertContains(json, "\"default_domain_resolver\":\"dns-local\"")
        assertContains(json, "\"domain_resolver\":\"dns-local\"")
        assertContains(json, "\"final\":\"dns-proxy\"")
    }

    @Test fun `DNS refuses traffic before runtime is ready`() {
        assertFailsWith<IllegalStateException> { ConfigGenerator.generate(ConfigInput("udp://1.1.1.1", ready = false)) }
    }
}
