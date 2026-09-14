package io.hydrabox.platform.android

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.system.OsConstants
import io.nekohasekai.libbox.BridgeOptions
import io.nekohasekai.libbox.BridgeSession
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.NetworkInterface as JavaNetworkInterface

/**
 * The Android half of the core's platform contract: it opens the tun device, enumerates
 * interfaces and reports which one the system would use without the tunnel.
 *
 * Reporting real interfaces is not optional. With a platform interface present the core
 * forces its default network strategy and dials only through the interface whose index it
 * was told about, so an empty enumeration means every dial fails with no usable
 * interface — which looks exactly like a broken server.
 */
class AndroidVpnPlatform(
    private val service: VpnService,
    private val monitor: DefaultNetworkMonitor,
) : PlatformInterface {
    private val connectivity =
        service.applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val resolver = AndroidLocalResolver(monitor)

    override fun autoDetectInterfaceControl(fd: Int) {
        check(service.protect(fd)) { "VpnService.protect failed" }
    }

    override fun bindInterfaceControl(
        fd: Int,
        interfaceName: String,
    ) = autoDetectInterfaceControl(fd)

    override fun clearDNSCache() = Unit

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        listener?.let(monitor::removeListener)
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        listener?.let(monitor::addListener)
    }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int,
    ) = ConnectionOwner()

    /**
     * Nothing here can say who owns a connection, so the core is told once instead of asked per
     * connection.
     *
     * `useProcFS` is false — under a tunnel the interesting sockets are not ours to read — and the
     * answer above is an empty owner. The core used to assume every platform could answer, and
     * profiling showed that assumption as a third of all the time spent crossing into Java: one
     * round trip per connection, for a value that was empty every time and used by nothing, since
     * no routing rule here matches on a process.
     */
    override fun usePlatformConnectionOwnerFinder() = false

    override fun getInterfaces(): NetworkInterfaceIterator {
        val javaInterfaces =
            runCatching { JavaNetworkInterface.getNetworkInterfaces()?.toList() }
                .getOrNull()
                .orEmpty()
        val collected = mutableListOf<NetworkInterface>()
        runCatching { connectivity.allNetworks.toList() }.getOrDefault(emptyList()).forEach { network ->
            val link = connectivity.getLinkProperties(network) ?: return@forEach
            val capabilities = connectivity.getNetworkCapabilities(network) ?: return@forEach
            val java = javaInterfaces.firstOrNull { it.name == link.interfaceName } ?: return@forEach
            collected +=
                NetworkInterface().apply {
                    index = java.index
                    mtu = runCatching { java.mtu }.getOrDefault(1500)
                    name = java.name
                    addresses =
                        SimpleStringIterator(
                            java.interfaceAddresses.mapNotNull { address ->
                                val host = address.address.hostAddress ?: return@mapNotNull null
                                "${host.substringBefore('%')}/${address.networkPrefixLength}"
                            },
                        )
                    dnsServer = SimpleStringIterator(link.dnsServers.mapNotNull { it.hostAddress })
                    type =
                        when {
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                            else -> Libbox.InterfaceTypeOther
                        }
                    metered = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
                    var computed = 0
                    if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                        computed = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                    }
                    if (runCatching { java.isLoopback }.getOrDefault(false)) computed = computed or OsConstants.IFF_LOOPBACK
                    if (runCatching { java.isPointToPoint }.getOrDefault(false)) computed = computed or OsConstants.IFF_POINTOPOINT
                    if (runCatching { java.supportsMulticast() }.getOrDefault(false)) computed = computed or OsConstants.IFF_MULTICAST
                    flags = computed
                }
        }
        return object : NetworkInterfaceIterator {
            private val iterator = collected.iterator()

            override fun hasNext() = iterator.hasNext()

            override fun next(): NetworkInterface = iterator.next()
        }
    }

    override fun includeAllNetworks() = false

    /**
     * The system resolver. Returning null here made the core fall back to a resolver that
     * reads `/etc/resolv.conf`, and every name in the configuration — the proxy resolver's
     * own host included — resolves through this transport.
     */
    override fun localDNSTransport(): LocalDNSTransport = resolver

    override fun readWIFIState() = WIFIState("", "")

    override fun sendNotification(notification: Notification?) = Unit

    override fun underNetworkExtension() = false

    override fun usePlatformAutoDetectInterfaceControl() = true

    override fun useProcFS() = false

    override fun openTun(options: TunOptions): Int {
        check(VpnService.prepare(service) == null) { "VPN permission is not granted" }
        val builder = service.Builder().setSession("HydraBox").setMtu(options.mtu)
        var hasIpv4 = false
        var hasIpv6 = false
        options.inet4Address.consume { address, prefix ->
            builder.addAddress(address, prefix)
            hasIpv4 = true
        }
        options.inet6Address.consume { address, prefix ->
            builder.addAddress(address, prefix)
            hasIpv6 = true
        }
        if (options.autoRoute) {
            val hasIpv4Route = options.inet4RouteRange.consume { address, prefix -> builder.addRoute(address, prefix) }
            val hasIpv6Route = options.inet6RouteRange.consume { address, prefix -> builder.addRoute(address, prefix) }
            if (hasIpv4 && !hasIpv4Route) builder.addRoute("0.0.0.0", 0)
            if (hasIpv6 && !hasIpv6Route) builder.addRoute("::", 0)
            // A package the system does not know throws, and every one of these calls used to be
            // swallowed. With an allow list that means the builder is left with no allow list at
            // all — and a tunnel with no allow list carries every application on the device, which
            // is the opposite of what "only these apps" asks for. So the intention is counted, and
            // a policy that could not be applied at all refuses the start instead of inverting it.
            val intended = mutableListOf<String>()
            val refused = mutableListOf<String>()
            options.includePackage.consume { name ->
                intended += name
                runCatching { builder.addAllowedApplication(name) }.onFailure { refused += name }
            }
            check(intended.isEmpty() || refused.size < intended.size) {
                "none of the applications chosen as the only ones inside the tunnel are installed: " +
                    refused.joinToString()
            }
            if (refused.isNotEmpty()) {
                HydraLog.warn(AREA, "${refused.size} of ${intended.size} allowed applications are not installed")
            }
            // The other direction fails safe: an exclusion that will not apply leaves the
            // application inside the tunnel, so it is worth a line and not a refusal.
            options.excludePackage.consume { name ->
                runCatching { builder.addDisallowedApplication(name) }
                    .onFailure { HydraLog.warn(AREA, "an application kept outside the tunnel is not installed") }
            }
        }
        options.dnsServerAddress.consume { address ->
            address.takeIf(String::isNotBlank)?.let(builder::addDnsServer)
        }
        return (builder.establish() ?: error("unable to establish the tun device")).detachFd()
    }

    // The migrated core exposes Tailscale-era platform services the app never provides.
    // Capabilities answer "no"; the calls that would need one throw so the core records
    // a refusal instead of a silent empty success.
    override fun usePlatformShell() = false

    override fun usePlatformBridge() = false

    override fun tailscaleHostname() = ""

    override fun checkPlatformShell(): Unit = error("the platform shell is unavailable")

    override fun openShellSession(
        user: PlatformUser?,
        command: String?,
        environ: StringIterator?,
        term: String?,
        rows: Int,
        cols: Int,
    ): ShellSession = error("the platform shell is unavailable")

    override fun lookupUser(username: String?): PlatformUser = error("there are no platform users")

    override fun lookupSFTPServer(): String = error("the SFTP server is unavailable")

    override fun readSystemSSHHostKey(): String = error("there is no system SSH host key")

    override fun createBridge(options: BridgeOptions?): BridgeSession = error("the bridge interface is unavailable")

    override fun startNeighborMonitor(listener: NeighborUpdateListener?) = Unit

    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) = Unit

    override fun registerMyInterface(name: String?) = Unit

    override fun cancelNotification(
        identifier: String?,
        typeID: Int,
    ) = Unit

    private companion object {
        const val AREA = "tun"
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

/** Minimal bridge from a Kotlin collection to the iterator shape the core expects. */
class SimpleStringIterator(
    values: Iterable<String>,
) : StringIterator {
    private val backing = values.toList()
    private val iterator = backing.iterator()

    override fun hasNext() = iterator.hasNext()

    override fun len() = backing.size

    override fun next(): String = iterator.next()
}
