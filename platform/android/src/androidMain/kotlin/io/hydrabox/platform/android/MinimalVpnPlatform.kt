package io.hydrabox.platform.android

import android.net.VpnService
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState

/** Thin Android adapter for the B03 walking skeleton. */
class MinimalVpnPlatform(private val service: VpnService) : PlatformInterface {
    override fun autoDetectInterfaceControl(fd: Int) {
        check(service.protect(fd)) { "VpnService.protect failed" }
    }

    override fun bindInterfaceControl(fd: Int, interfaceName: String) = autoDetectInterfaceControl(fd)
    override fun clearDNSCache() = Unit
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) = Unit
    override fun findConnectionOwner(ipProtocol: Int, sourceAddress: String?, sourcePort: Int, destinationAddress: String?, destinationPort: Int) = ConnectionOwner()
    override fun getInterfaces(): NetworkInterfaceIterator = object : NetworkInterfaceIterator {
        override fun hasNext() = false
        override fun next(): NetworkInterface = error("No network interfaces")
    }
    override fun includeAllNetworks() = false
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun readWIFIState() = WIFIState("", "")
    override fun sendNotification(notification: Notification?) = Unit
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) = Unit
    override fun systemCertificates(): StringIterator = object : StringIterator {
        override fun hasNext() = false
        override fun len() = 0
        override fun next(): String = error("No certificates")
    }
    override fun underNetworkExtension() = false
    override fun usePlatformAutoDetectInterfaceControl() = true
    override fun useProcFS() = false

    override fun openTun(options: TunOptions): Int {
        check(VpnService.prepare(service) == null) { "VPN permission is not granted" }
        val builder = service.Builder().setSession("HydraBox").setMtu(options.mtu)
        var hasIpv4 = false
        var hasIpv6 = false
        options.inet4Address.consume { address, prefix -> builder.addAddress(address, prefix); hasIpv4 = true }
        options.inet6Address.consume { address, prefix -> builder.addAddress(address, prefix); hasIpv6 = true }
        if (options.autoRoute) {
            val hasIpv4Route = options.inet4RouteRange.consume { address, prefix -> builder.addRoute(address, prefix) }
            val hasIpv6Route = options.inet6RouteRange.consume { address, prefix -> builder.addRoute(address, prefix) }
            if (hasIpv4 && !hasIpv4Route) builder.addRoute("0.0.0.0", 0)
            if (hasIpv6 && !hasIpv6Route) builder.addRoute("::", 0)
            options.includePackage.consume { builder.addAllowedApplication(it) }
            options.excludePackage.consume { builder.addDisallowedApplication(it) }
        }
        options.dnsServerAddress?.value?.takeIf(String::isNotBlank)?.let(builder::addDnsServer)
        return (builder.establish() ?: error("Unable to establish TUN")).detachFd()
    }

    private fun io.nekohasekai.libbox.RoutePrefixIterator.consume(block: (String, Int) -> Unit): Boolean {
        var found = false
        while (hasNext()) {
            next().let { block(it.address(), it.prefix()) }
            found = true
        }
        return found
    }

    private fun StringIterator?.consume(block: (String) -> Unit) {
        while (this?.hasNext() == true) block(next())
    }
}
