package com.etonify.meow_client.singbox

import io.nekohasekai.libbox.StringIterator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SplitTunnelPackagesTest {
    @Test
    fun `resolves each JNI iterator getter once`() {
        var includeGetterCalls = 0
        var excludeGetterCalls = 0

        val packages = readSplitTunnelPackages(
            includePackage = {
                includeGetterCalls++
                ListStringIterator(listOf("com.example.one", "com.example.two"))
            },
            excludePackage = {
                excludeGetterCalls++
                ListStringIterator(emptyList())
            },
        )

        assertEquals(1, includeGetterCalls)
        assertEquals(1, excludeGetterCalls)
        assertEquals(listOf("com.example.one", "com.example.two"), packages.included)
        assertEquals(emptyList<String>(), packages.excluded)
    }

    @Test
    fun `rejects an iterator that exceeds the package limit`() {
        val iterator = InfiniteStringIterator()

        assertThrows(SplitTunnelConfigurationException::class.java) {
            readSplitTunnelPackages(
                includePackage = { iterator },
                excludePackage = { ListStringIterator(emptyList()) },
            )
        }

        assertEquals(MAX_SPLIT_TUNNEL_PACKAGE_COUNT, iterator.nextCalls)
    }

    @Test
    fun `rejects simultaneous include and exclude modes`() {
        assertThrows(SplitTunnelConfigurationException::class.java) {
            readSplitTunnelPackages(
                includePackage = { ListStringIterator(listOf("com.example.included")) },
                excludePackage = { ListStringIterator(listOf("com.example.excluded")) },
            )
        }
    }
}

private class ListStringIterator(
    private val values: List<String>,
) : StringIterator {
    private val iterator = values.iterator()

    override fun hasNext(): Boolean = iterator.hasNext()

    override fun len(): Int = values.size

    override fun next(): String = iterator.next()
}

private class InfiniteStringIterator : StringIterator {
    var nextCalls = 0
        private set

    override fun hasNext(): Boolean = true

    override fun len(): Int = Int.MAX_VALUE

    override fun next(): String {
        nextCalls++
        return "com.example.repeated"
    }
}
