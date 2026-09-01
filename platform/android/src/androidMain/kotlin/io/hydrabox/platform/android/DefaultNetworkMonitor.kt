package io.hydrabox.platform.android

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface as JavaNetworkInterface
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Tracks the network the system would use if the tunnel did not exist, and tells the core
 * about it.
 *
 * Two rules carried over from 1.x, both learned the hard way. A network carrying
 * `TRANSPORT_VPN` is never a candidate — otherwise our own tunnel is treated as a usable
 * upstream. And the current value is replayed to a listener the moment it registers,
 * because the core registers after the first callback has already fired, and without the
 * replay a cold start never learns which interface to bind to.
 */
class DefaultNetworkMonitor(context: Context) {
    private val connectivity = context.applicationContext
        .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val listeners = CopyOnWriteArraySet<InterfaceUpdateListener>()
    private val lock = Any()

    @Volatile private var current: Iface? = null
    @Volatile private var generation: Long = 0
    private var callback: ConnectivityManager.NetworkCallback? = null

    data class Iface(val name: String, val index: Int)

    val networkGeneration get() = generation

    fun start() = synchronized(lock) {
        if (callback != null) return@synchronized
        val created = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = refresh()
            override fun onLost(network: Network) = refresh()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = refresh()
            override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = refresh()
        }
        callback = created
        runCatching {
            connectivity.registerNetworkCallback(
                NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build(),
                created,
            )
        }
        refresh()
    }

    fun stop() = synchronized(lock) {
        callback?.let { registered -> runCatching { connectivity.unregisterNetworkCallback(registered) } }
        callback = null
    }

    fun addListener(listener: InterfaceUpdateListener) {
        listeners += listener
        // Replay, not wait: the value may already be known.
        publish(listener, current)
    }

    fun removeListener(listener: InterfaceUpdateListener) {
        listeners -= listener
    }

    private fun refresh() {
        val resolved = resolve()
        if (resolved == current) return
        synchronized(lock) {
            current = resolved
            generation += 1
        }
        listeners.forEach { publish(it, resolved) }
    }

    private fun publish(listener: InterfaceUpdateListener, iface: Iface?) {
        runCatching {
            if (iface == null) listener.updateDefaultInterface("", -1, false, false)
            else listener.updateDefaultInterface(iface.name, iface.index, false, false)
        }
    }

    /** The best non-VPN network with internet, resolved down to an interface index. */
    private fun resolve(): Iface? {
        val candidates = runCatching { connectivity.allNetworks.toList() }.getOrDefault(emptyList())
        val names = candidates.mapNotNull { network ->
            val capabilities = connectivity.getNetworkCapabilities(network) ?: return@mapNotNull null
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return@mapNotNull null
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return@mapNotNull null
            val name = connectivity.getLinkProperties(network)?.interfaceName ?: return@mapNotNull null
            val rank = when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 0
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 1
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
                else -> 3
            }
            rank to name
        }.sortedBy { it.first }.map { it.second }
        val name = names.firstOrNull { it != "tun0" && !it.startsWith("tun") } ?: return null
        val index = runCatching { JavaNetworkInterface.getByName(name)?.index }.getOrNull() ?: return null
        return if (index > 0) Iface(name, index) else null
    }
}
