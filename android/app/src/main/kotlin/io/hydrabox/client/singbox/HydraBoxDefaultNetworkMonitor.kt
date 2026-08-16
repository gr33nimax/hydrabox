package io.hydrabox.client.singbox

import android.annotation.TargetApi
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import io.hydrabox.client.HydraBoxApplication
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

object HydraBoxDefaultNetworkMonitor {
    private const val TAG = "HydraBoxDefaultNetwork"
    private const val NETWORK_CHANGE_DEBOUNCE_MS = 1_500L
    private val lock = Any()
    private val networkHandlerThread = HandlerThread("HydraBoxNetworkCallback").apply { start() }
    private val networkHandler = Handler(networkHandlerThread.looper)
    private val notifyExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HydraBoxNetworkNotify").apply { isDaemon = true }
    }
    private val heartbeatExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "HydraBoxNetworkHeartbeat").apply { isDaemon = true }
    }
    private val notificationGeneration = AtomicLong(0L)
    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .build()

    private var started = false
    private var currentNetwork: Network? = null
    private val listeners = IdentityListenerRegistry<InterfaceUpdateListener>()
    private var heartbeatFuture: ScheduledFuture<*>? = null
    private var pendingNotifyRunnable: Runnable? = null
    private var lastNotificationKey: String? = null

    private data class NetworkCandidate(
        val network: Network,
        val capabilities: NetworkCapabilities,
        val isActive: Boolean,
        val isValidated: Boolean,
        val score: Int,
    )

    data class InterfaceState(
        val available: Boolean,
        val interfaceName: String,
        val interfaceIndex: Int,
        val generation: Long,
        val reason: String,
        val updatedAtMillis: Long,
    )

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            Log.i(TAG, "onAvailable network=$network")
            HydraBoxDiagnostics.log(TAG, "onAvailable ${describeNetwork(network)}")
            updateNetwork(network)
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            Log.i(
                TAG,
                "onCapabilitiesChanged network=$network transports=${describeTransports(networkCapabilities)}",
            )
            HydraBoxDiagnostics.log(
                TAG,
                "onCapabilitiesChanged ${describeNetwork(network, networkCapabilities)}",
            )
            updateNetwork(network)
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            HydraBoxDiagnostics.log(
                TAG,
                "onLinkPropertiesChanged network=$network interface=${linkProperties.interfaceName}",
            )
            updateNetwork(network)
        }

        override fun onLost(network: Network) {
            Log.w(TAG, "onLost network=$network")
            HydraBoxDiagnostics.log(TAG, "onLost ${describeNetwork(network)}")
            synchronized(lock) {
                if (currentNetwork == network) {
                    currentNetwork = resolveBestNetwork(exclude = network)
                }
            }
            notifyListener()
        }
    }

    fun start() {
        synchronized(lock) {
            if (started) {
                return
            }
            started = true
            lastNotificationKey = null
        }
        Log.i(TAG, "start")
        HydraBoxDiagnostics.log(TAG, "start current=${describeCurrentState()}")
        register()
        startHeartbeat()
    }

    fun stop() {
        synchronized(lock) {
            if (!started) {
                return
            }
            started = false
            currentNetwork = null
            lastNotificationKey = null
            pendingNotifyRunnable?.let(networkHandler::removeCallbacks)
            pendingNotifyRunnable = null
        }
        Log.i(TAG, "stop")
        HydraBoxDiagnostics.log(TAG, "stop current=${describeCurrentState()}")
        notificationGeneration.incrementAndGet()
        HydraBoxVpnService.setUnderlyingNetwork(null, "monitor_stop")
        stopHeartbeat()
        runCatching {
            HydraBoxApplication.connectivity.unregisterNetworkCallback(callback)
        }
    }

    fun refreshHeartbeat() {
        val currentlyStarted = synchronized(lock) { started }
        if (!currentlyStarted) {
            return
        }
        startHeartbeat()
    }

    private fun startHeartbeat() {
        heartbeatFuture?.cancel(false)
        if (!HydraBoxApplication.networkHeartbeatEnabled) return
        val intervalSeconds = HydraBoxApplication.networkHeartbeatIntervalSeconds
        heartbeatFuture = heartbeatExecutor.scheduleWithFixedDelay(
            { runCatching { heartbeatTick() }.onFailure { Log.e(TAG, "heartbeat failed", it) } },
            intervalSeconds,
            intervalSeconds,
            TimeUnit.SECONDS,
        )
    }

    private fun stopHeartbeat() {
        heartbeatFuture?.cancel(false)
        heartbeatFuture = null
    }

    private fun heartbeatTick() {
        val currentlyStarted = synchronized(lock) { started }
        if (!currentlyStarted) return
        val active = HydraBoxApplication.connectivity.activeNetwork
        val cached = synchronized(lock) { currentNetwork }
        val best = resolveBestNetwork()
        if (best != null && best != cached) {
            Log.i(TAG, "heartbeat divergence cached=$cached best=$best")
            synchronized(lock) {
                if (started) currentNetwork = best
            }
            notifyListener()
        } else if (best == null && cached != null) {
            Log.i(TAG, "heartbeat lost selectable default cached=$cached")
            synchronized(lock) {
                if (started) currentNetwork = null
            }
            notifyListener(force = true)
        } else if (active == null && cached != null) {
            Log.i(TAG, "heartbeat lost cached=$cached")
            val replacement = resolveBestNetwork(exclude = cached)
            synchronized(lock) {
                if (started) currentNetwork = replacement
            }
            notifyListener(force = true)
        } else if (cached != null && listenerInterfaceLikelyStale(cached)) {
            Log.i(TAG, "heartbeat re-assert cached=$cached")
            notifyListener(force = true)
        } else if (cached != null) {
            Log.d(TAG, "heartbeat current network remains valid cached=$cached")
        }
    }

    private fun listenerInterfaceLikelyStale(network: Network): Boolean {
        val name = HydraBoxApplication.connectivity.getLinkProperties(network)?.interfaceName ?: return true
        return runCatching { NetworkInterface.getByName(name)?.index ?: -1 }.getOrDefault(-1) < 0
    }

    fun require(): Network {
        synchronized(lock) { currentNetwork }?.takeIf(::isSelectableNetwork)?.let {
            return it
        }
        resolveBestNetwork()?.let {
            HydraBoxDiagnostics.log(TAG, "require resolved best ${describeNetwork(it)}")
            return it
        }
        val ready = CountDownLatch(1)
        repeat(20) {
            val current = synchronized(lock) { currentNetwork }
            if (current?.let(::isSelectableNetwork) == true) {
                ready.countDown()
            }
            if (ready.await(100, TimeUnit.MILLISECONDS)) {
                synchronized(lock) { currentNetwork }?.takeIf(::isSelectableNetwork)?.let {
                    HydraBoxDiagnostics.log(TAG, "require waited current ${describeNetwork(it)}")
                    return it
                }
            }
        }
        synchronized(lock) { currentNetwork }?.takeIf(::isSelectableNetwork)?.let {
            HydraBoxDiagnostics.log(TAG, "require late current ${describeNetwork(it)}")
            return it
        }
        resolveBestNetwork()?.let {
            HydraBoxDiagnostics.log(TAG, "require late best ${describeNetwork(it)}")
            return it
        }
        val active = HydraBoxApplication.connectivity.activeNetwork
        return if (active != null && isSelectableNetwork(active)) {
            HydraBoxDiagnostics.log(TAG, "require fallback active ${describeNetwork(active)}")
            active
        } else {
            error("missing default network")
        }
    }

    fun awaitUsableDefaultInterface(timeoutMs: Long = 1_500L): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() <= deadline) {
            val network = resolveBestNetwork()
            if (network != null) {
                synchronized(lock) {
                    if (started) currentNetwork = network
                }
                val interfaceName =
                    HydraBoxApplication.connectivity.getLinkProperties(network)?.interfaceName
                val index = if (interfaceName.isNullOrBlank()) {
                    -1
                } else {
                    runCatching { NetworkInterface.getByName(interfaceName)?.index ?: -1 }
                        .getOrDefault(-1)
                }
                if (!interfaceName.isNullOrBlank() && index >= 0) {
                    HydraBoxDiagnostics.log(
                        TAG,
                        "awaitUsableDefaultInterface ready interface=$interfaceName index=$index " +
                            "current=${describeNetwork(network)}",
                    )
                    return true
                }
            }
            try {
                Thread.sleep(100)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }
        }
        HydraBoxDiagnostics.log(
            TAG,
            "awaitUsableDefaultInterface timed out current=${describeCurrentState()}",
        )
        return false
    }

    fun currentInterfaceState(reason: String = "query"): InterfaceState {
        val network = resolveBestNetwork()
        val interfaceName = network?.let {
            HydraBoxApplication.connectivity.getLinkProperties(it)?.interfaceName
        }?.trim().orEmpty()
        val index = if (interfaceName.isEmpty()) {
            -1
        } else {
            runCatching { NetworkInterface.getByName(interfaceName)?.index ?: -1 }
                .getOrDefault(-1)
        }
        return InterfaceState(
            available = interfaceName.isNotEmpty() && index >= 0,
            interfaceName = interfaceName,
            interfaceIndex = index,
            generation = notificationGeneration.get(),
            reason = reason,
            updatedAtMillis = System.currentTimeMillis(),
        )
    }

    fun addListener(newListener: InterfaceUpdateListener) {
        synchronized(lock) {
            listeners.add(newListener)
        }
        notificationGeneration.incrementAndGet()
        HydraBoxDiagnostics.log(
            TAG,
            "listener_attached count=${listenerCount()} current=${describeCurrentState()}",
        )
        // A newly attached libbox runtime must receive the current interface
        // even if the physical network did not change. Limit that forced
        // delivery to the new listener so an existing runtime is not reset.
        notifyListener(
            immediate = true,
            force = true,
            notifyDuplicate = true,
            targetListener = newListener,
        )
    }

    fun removeListener(listener: InterfaceUpdateListener) {
        val removed = synchronized(lock) { listeners.remove(listener) }
        if (removed) {
            HydraBoxDiagnostics.log(
                TAG,
                "listener_detached count=${listenerCount()} current=${describeCurrentState()}",
            )
        }
    }

    internal fun listenerCount(): Int = synchronized(lock) { listeners.size() }

    fun reassertDefaultInterface(reason: String) {
        val hasListener = synchronized(lock) { !listeners.isEmpty() }
        HydraBoxDiagnostics.log(
            TAG,
            "reassertDefaultInterface reason=$reason listener=$hasListener current=${describeCurrentState()}",
        )
        if (!hasListener) return
        // Re-apply VpnService.setUnderlyingNetworks(), but do not send the same
        // interface to libbox again. Android emits repeated capability/link
        // callbacks for one Network and every duplicate core notification
        // resets all outbound transports.
        notifyListener(immediate = true, force = true)
    }

    private fun updateNetwork(network: Network) {
        if (!isBaseUsableNetwork(network)) {
            Log.i(TAG, "ignore unusable network=$network")
            HydraBoxDiagnostics.log(TAG, "ignore unusable ${describeNetwork(network)}")
            synchronized(lock) {
                if (currentNetwork == network) currentNetwork = resolveBestNetwork(exclude = network)
            }
            notifyListener(force = true)
            return
        }
        // A callback for a newly available physical transport must be allowed
        // to replace an old, no-longer-validated interface. While a VPN is
        // active ConnectivityManager.activeNetwork is often the VPN itself,
        // so keeping currentNetwork unconditionally can pin libbox to dead
        // Wi-Fi after a Wi-Fi -> cellular handover.
        val preferredNetwork = resolveBestNetwork(preferred = network)
        var shouldNotify = false
        var shouldForceNotify = false
        var previousNetwork: Network? = null
        synchronized(lock) {
            previousNetwork = currentNetwork
            if (preferredNetwork == null) {
                if (currentNetwork == network) {
                    currentNetwork = null
                    shouldNotify = true
                }
            } else if (currentNetwork == preferredNetwork) {
                shouldForceNotify = network == preferredNetwork
            } else {
                shouldNotify = true
                currentNetwork = preferredNetwork
            }
        }
        Log.i(TAG, "updateNetwork network=$network preferred=$preferredNetwork notify=$shouldNotify")
        HydraBoxDiagnostics.log(
            TAG,
            "updateNetwork event=${describeNetwork(network)} preferred=${describeNetwork(preferredNetwork)} " +
                "previous=${describeNetwork(previousNetwork)} notify=$shouldNotify force=$shouldForceNotify",
        )
        if (shouldForceNotify) {
            notifyListener(force = true)
            return
        }
        if (shouldNotify) {
            notifyListener()
        }
    }

    private fun notifyListener(
        immediate: Boolean = false,
        force: Boolean = false,
        notifyDuplicate: Boolean = false,
        targetListener: InterfaceUpdateListener? = null,
    ) {
        val generation = notificationGeneration.incrementAndGet()
        val capturedNetwork = synchronized(lock) {
            if (listeners.isEmpty()) return
            currentNetwork
        }
        val runnable = Runnable {
            notifyExecutor.execute {
                runCatching {
                    notifyListenerInternal(
                        generation,
                        capturedNetwork,
                        force,
                        notifyDuplicate,
                        targetListener,
                    )
                }
                    .onFailure { Log.e(TAG, "notifyListenerInternal failed", it) }
            }
        }
        networkHandler.post {
            pendingNotifyRunnable?.let(networkHandler::removeCallbacks)
            pendingNotifyRunnable = runnable
            if (immediate) {
                networkHandler.post(runnable)
            } else {
                networkHandler.postDelayed(runnable, NETWORK_CHANGE_DEBOUNCE_MS)
            }
        }
    }

    private fun markInterfaceState(key: String): Boolean {
        synchronized(lock) {
            val duplicate = lastNotificationKey == key
            lastNotificationKey = key
            return duplicate
        }
    }

    private fun notifyListenerInternal(
        generation: Long,
        capturedNetwork: Network?,
        force: Boolean,
        notifyDuplicate: Boolean,
        targetListener: InterfaceUpdateListener?,
    ) {
        if (notificationGeneration.get() != generation) return
        val currentListeners = synchronized(lock) {
            if (targetListener != null) {
                if (listeners.contains(targetListener)) listOf(targetListener) else emptyList()
            } else {
                listeners.snapshot()
            }
        }
        if (currentListeners.isEmpty()) return
        val bestNetwork = resolveBestNetwork(preferred = capturedNetwork)
        val effectiveNetwork = bestNetwork ?: capturedNetwork?.takeIf(::isSelectableNetwork)
        if (effectiveNetwork == null) {
            if (notificationGeneration.get() != generation) return
            val duplicate = markInterfaceState("none")
            Log.i(TAG, "updateDefaultInterface: none")
            HydraBoxDiagnostics.log(TAG, "updateDefaultInterface none current=${describeCurrentState()}")
            HydraBoxVpnService.setUnderlyingNetwork(
                null,
                if (force) "default_interface_lost_forced" else "default_interface_lost",
            )
            if (duplicate && !notifyDuplicate) return
            notifyListeners(currentListeners, "", -1)
            if (shouldBroadcastNetworkChange(duplicate, targetListener != null)) {
                SingboxController.emitNetworkChanged(
                    "default_interface_lost",
                    describeCurrentState(),
                    null,
                    -1,
                    notificationGeneration.get(),
                )
            }
            return
        }
        synchronized(lock) {
            if (started) currentNetwork = effectiveNetwork
        }
        val interfaceName =
            HydraBoxApplication.connectivity.getLinkProperties(effectiveNetwork)?.interfaceName
        if (interfaceName.isNullOrBlank()) {
            if (notificationGeneration.get() != generation) return
            val duplicate = markInterfaceState("missing:$effectiveNetwork")
            Log.w(TAG, "updateDefaultInterface: missing link properties for $effectiveNetwork")
            HydraBoxVpnService.setUnderlyingNetwork(
                null,
                if (force) "default_interface_missing_forced" else "default_interface_missing",
            )
            if (duplicate && !notifyDuplicate) return
            notifyListeners(currentListeners, "", -1)
            if (shouldBroadcastNetworkChange(duplicate, targetListener != null)) {
                SingboxController.emitNetworkChanged(
                    "default_interface_missing",
                    describeNetwork(effectiveNetwork),
                    null,
                    -1,
                    notificationGeneration.get(),
                )
            }
            return
        }
        var index = -1
        for (attempt in 0 until 10) {
            if (notificationGeneration.get() != generation) return
            index = runCatching { NetworkInterface.getByName(interfaceName)?.index ?: -1 }
                .getOrDefault(-1)
            if (index >= 0) break
            try {
                Thread.sleep(100)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
        }
        if (notificationGeneration.get() != generation) return
        val notifyKey = "$effectiveNetwork:$interfaceName:$index"
        val duplicate = markInterfaceState(notifyKey)
        Log.i(TAG, "updateDefaultInterface: $interfaceName index=$index")
        HydraBoxDiagnostics.log(
            TAG,
            "updateDefaultInterface interface=$interfaceName index=$index force=$force duplicate=$duplicate " +
                "current=${describeNetwork(effectiveNetwork)}",
        )
        HydraBoxVpnService.setUnderlyingNetwork(
            effectiveNetwork,
            if (force && duplicate) {
                "default_interface_reassert"
            } else if (force) {
                "default_interface_forced"
            } else {
                "default_interface"
            },
        )
        if (duplicate && !notifyDuplicate) {
            HydraBoxDiagnostics.log(
                TAG,
                "skip duplicate core interface update interface=$interfaceName index=$index",
            )
            return
        }
        notifyListeners(currentListeners, interfaceName, index)
        if (shouldBroadcastNetworkChange(duplicate, targetListener != null)) {
            SingboxController.emitNetworkChanged(
                "default_interface",
                describeNetwork(effectiveNetwork),
                interfaceName,
                index,
                notificationGeneration.get(),
            )
        }
    }

    private fun notifyListeners(
        snapshot: List<InterfaceUpdateListener>,
        interfaceName: String,
        interfaceIndex: Int,
    ) {
        snapshot.forEach { currentListener ->
            val stillAttached = synchronized(lock) { listeners.contains(currentListener) }
            if (!stillAttached) return@forEach
            runCatching {
                currentListener.updateDefaultInterface(
                    interfaceName,
                    interfaceIndex,
                    false,
                    false,
                )
            }.onFailure { Log.e(TAG, "updateDefaultInterface failed", it) }
        }
    }

    private fun resolveBestNetwork(
        exclude: Network? = null,
        preferred: Network? = null,
    ): Network? {
        val connectivity = HydraBoxApplication.connectivity
        val active = connectivity.activeNetwork
        val candidates = connectivity.allNetworks
            .mapNotNull { network ->
                if (network == exclude) return@mapNotNull null
                val capabilities = connectivity.getNetworkCapabilities(network) ?: return@mapNotNull null
                if (!isBaseUsableNetwork(capabilities)) return@mapNotNull null
                val isActive = active == network
                val isValidated =
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                NetworkCandidate(
                    network = network,
                    capabilities = capabilities,
                    isActive = isActive,
                    isValidated = isValidated,
                    score = networkScore(capabilities, isActive, isValidated),
                )
            }
        val current = synchronized(lock) { currentNetwork }
        val selectedNetwork = selectDefaultNetworkCandidate(
            candidates = candidates.map { candidate ->
                DefaultNetworkCandidate(
                    value = candidate.network,
                    isActive = candidate.isActive,
                    isValidated = candidate.isValidated,
                    hasUsableInterface = hasUsableNetworkInterface(candidate.network),
                    score = candidate.score,
                )
            },
            current = current,
            preferred = preferred,
        )?.value
        val selected = candidates.firstOrNull { it.network == selectedNetwork }
        if (selected == null && candidates.isNotEmpty()) {
            HydraBoxDiagnostics.log(
                TAG,
                "resolveBestNetwork none selectable candidates=${candidates.size} " +
                    "exclude=${describeNetwork(exclude)}",
            )
        }
        return selected?.network?.also {
            val fallback = when {
                selected.isValidated -> ""
                selected.isActive -> " fallback_unvalidated=true"
                else -> " fallback_interface=true"
            }
            Log.i(TAG, "resolveBestNetwork -> $it")
            HydraBoxDiagnostics.log(
                TAG,
                "resolveBestNetwork -> ${describeNetwork(it, selected.capabilities)} " +
                    "exclude=${describeNetwork(exclude)} candidates=${candidates.size}$fallback",
            )
        }
    }

    private fun isBaseUsableNetwork(network: Network): Boolean {
        val capabilities = HydraBoxApplication.connectivity.getNetworkCapabilities(network) ?: return false
        return isBaseUsableNetwork(capabilities)
    }

    private fun isBaseUsableNetwork(capabilities: NetworkCapabilities): Boolean {
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            return false
        }
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)) {
            return false
        }
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            return false
        }
        return true
    }

    private fun isSelectableNetwork(network: Network): Boolean {
        val capabilities = HydraBoxApplication.connectivity.getNetworkCapabilities(network) ?: return false
        if (!isBaseUsableNetwork(capabilities)) return false
        val validated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        return validated && hasUsableNetworkInterface(network)
    }

    private fun hasUsableNetworkInterface(network: Network): Boolean {
        val interfaceName = HydraBoxApplication.connectivity
            .getLinkProperties(network)
            ?.interfaceName
            ?.takeIf { it.isNotBlank() }
            ?: return false
        return runCatching { NetworkInterface.getByName(interfaceName)?.index ?: -1 }
            .getOrDefault(-1) >= 0
    }

    private fun networkScore(
        capabilities: NetworkCapabilities,
        isActive: Boolean,
        isValidated: Boolean,
    ): Int {
        var score = 0
        if (isValidated) {
            score += 100
        }
        if (isActive) {
            score += 40
        }
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
            score += 30
        }
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
            score += 20
        }
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
            score += 10
        }
        return score
    }

    private fun describeTransports(capabilities: NetworkCapabilities): String {
        val transports = mutableListOf<String>()
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports += "wifi"
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports += "cellular"
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) transports += "ethernet"
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) transports += "vpn"
        if (transports.isEmpty()) transports += "other"
        return transports.joinToString(",")
    }

    fun describeNetwork(network: Network?): String {
        return describeNetwork(network, null)
    }

    fun describeNetwork(network: Network?, capabilities: NetworkCapabilities? = null): String {
        if (network == null) return "network=null"
        val connectivity = HydraBoxApplication.connectivity
        val resolvedCapabilities = capabilities ?: connectivity.getNetworkCapabilities(network)
        val linkProperties = connectivity.getLinkProperties(network)
        val active = connectivity.activeNetwork == network
        val transports = resolvedCapabilities?.let(::describeTransports) ?: "unknown"
        val validated = resolvedCapabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        val internet = resolvedCapabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        val restricted = resolvedCapabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        val vpn = resolvedCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        val interfaceName = linkProperties?.interfaceName ?: "unknown"
        return buildString {
            append("network=")
            append(network)
            append(" active=")
            append(active)
            append(" interface=")
            append(interfaceName)
            append(" validated=")
            append(validated)
            append(" internet=")
            append(internet)
            append(" notRestricted=")
            append(restricted)
            append(" vpn=")
            append(vpn)
            append(" transports=")
            append(transports)
        }
    }

    fun describeCurrentState(): String {
        val active = HydraBoxApplication.connectivity.activeNetwork
        val current = synchronized(lock) { currentNetwork }
        return "current=${describeNetwork(current)} active=${describeNetwork(active)}"
    }

    private fun register() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            @TargetApi(Build.VERSION_CODES.S)
            runCatching {
                HydraBoxDiagnostics.log(TAG, "register method=registerBestMatchingNetworkCallback sdk=${Build.VERSION.SDK_INT}")
                HydraBoxApplication.connectivity.registerBestMatchingNetworkCallback(
                    request,
                    callback,
                    networkHandler,
                )
            }.onFailure {
                SingboxController.log("error", "default network callback failed: ${it.message}")
            }
        } else {
            runCatching {
                HydraBoxDiagnostics.log(TAG, "register method=registerNetworkCallback(networkHandler) sdk=${Build.VERSION.SDK_INT}")
                HydraBoxApplication.connectivity.registerNetworkCallback(
                    request,
                    callback,
                    networkHandler,
                )
            }.onFailure {
                SingboxController.log("error", "default network callback failed: ${it.message}")
            }
        }
    }
}

internal fun shouldBroadcastNetworkChange(
    duplicate: Boolean,
    targetedInitialization: Boolean,
): Boolean = !duplicate && !targetedInitialization
