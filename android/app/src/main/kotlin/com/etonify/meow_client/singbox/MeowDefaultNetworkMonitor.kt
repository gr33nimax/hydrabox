package com.etonify.meow_client.singbox

import android.annotation.TargetApi
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.etonify.meow_client.MeowApplication
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

object MeowDefaultNetworkMonitor {
    private const val TAG = "MeowDefaultNetwork"
    private const val NETWORK_CHANGE_DEBOUNCE_MS = 500L
    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val notifyExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "MeowNetworkNotify").apply { isDaemon = true }
    }
    private val heartbeatExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "MeowNetworkHeartbeat").apply { isDaemon = true }
    }
    private val notificationGeneration = AtomicLong(0L)
    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .apply {
            if (Build.VERSION.SDK_INT == Build.VERSION_CODES.M) {
                removeCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                removeCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)
            }
        }
        .build()

    private var started = false
    private var currentNetwork: Network? = null
    private var listener: InterfaceUpdateListener? = null
    private var heartbeatFuture: ScheduledFuture<*>? = null
    private var pendingNotifyRunnable: Runnable? = null

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            Log.i(TAG, "onAvailable network=$network")
            MeowDiagnostics.log(TAG, "onAvailable ${describeNetwork(network)}")
            updateNetwork(network)
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            Log.i(
                TAG,
                "onCapabilitiesChanged network=$network transports=${describeTransports(networkCapabilities)}",
            )
            MeowDiagnostics.log(
                TAG,
                "onCapabilitiesChanged ${describeNetwork(network, networkCapabilities)}",
            )
            updateNetwork(network)
        }

        override fun onLost(network: Network) {
            Log.w(TAG, "onLost network=$network")
            MeowDiagnostics.log(TAG, "onLost ${describeNetwork(network)}")
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
        }
        Log.i(TAG, "start")
        MeowDiagnostics.log(TAG, "start current=${describeCurrentState()}")
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
        }
        Log.i(TAG, "stop")
        MeowDiagnostics.log(TAG, "stop current=${describeCurrentState()}")
        notificationGeneration.incrementAndGet()
        stopHeartbeat()
        runCatching {
            MeowApplication.connectivity.unregisterNetworkCallback(callback)
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
        if (!MeowApplication.networkHeartbeatEnabled) return
        val intervalSeconds = MeowApplication.networkHeartbeatIntervalSeconds
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
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val active = MeowApplication.connectivity.activeNetwork
        val cached = synchronized(lock) { currentNetwork }
        val activeUsable = active?.let(::isUsableNetwork) ?: false
        if (active != null && active != cached && activeUsable) {
            Log.i(TAG, "heartbeat divergence cached=$cached active=$active")
            synchronized(lock) {
                if (started) currentNetwork = active
            }
            notifyListener()
        } else if (active == null && cached != null) {
            Log.i(TAG, "heartbeat lost cached=$cached")
            val replacement = resolveBestNetwork(exclude = cached)
            synchronized(lock) {
                if (started) currentNetwork = replacement
            }
            notifyListener()
        } else if (cached != null && listenerInterfaceLikelyStale(cached)) {
            Log.i(TAG, "heartbeat re-assert cached=$cached")
            notifyListener()
        }
    }

    private fun listenerInterfaceLikelyStale(network: Network): Boolean {
        val name = MeowApplication.connectivity.getLinkProperties(network)?.interfaceName ?: return true
        return runCatching { NetworkInterface.getByName(name)?.index ?: -1 }.getOrDefault(-1) < 0
    }

    fun require(): Network {
        synchronized(lock) {
            currentNetwork?.let { return it }
        }
        resolveBestNetwork()?.let {
            MeowDiagnostics.log(TAG, "require resolved best ${describeNetwork(it)}")
            return it
        }
        val ready = CountDownLatch(1)
        repeat(20) {
            synchronized(lock) {
                if (currentNetwork != null) {
                    ready.countDown()
                }
            }
            if (ready.await(100, TimeUnit.MILLISECONDS)) {
                synchronized(lock) {
                    currentNetwork?.let {
                        MeowDiagnostics.log(TAG, "require waited current ${describeNetwork(it)}")
                        return it
                    }
                }
            }
        }
        synchronized(lock) {
            currentNetwork?.let {
                MeowDiagnostics.log(TAG, "require late current ${describeNetwork(it)}")
                return it
            }
        }
        resolveBestNetwork()?.let {
            MeowDiagnostics.log(TAG, "require late best ${describeNetwork(it)}")
            return it
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            (MeowApplication.connectivity.activeNetwork ?: error("missing default network")).also {
                MeowDiagnostics.log(TAG, "require fallback active ${describeNetwork(it)}")
            }
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
                    MeowApplication.connectivity.getLinkProperties(network)?.interfaceName
                val index = if (interfaceName.isNullOrBlank()) {
                    -1
                } else {
                    runCatching { NetworkInterface.getByName(interfaceName)?.index ?: -1 }
                        .getOrDefault(-1)
                }
                if (!interfaceName.isNullOrBlank() && index >= 0) {
                    MeowDiagnostics.log(
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
        MeowDiagnostics.log(
            TAG,
            "awaitUsableDefaultInterface timed out current=${describeCurrentState()}",
        )
        return false
    }

    fun setListener(newListener: InterfaceUpdateListener?) {
        synchronized(lock) {
            listener = newListener
        }
        notificationGeneration.incrementAndGet()
        if (newListener != null) {
            notifyListener()
        }
    }

    private fun updateNetwork(network: Network) {
        if (!isUsableNetwork(network)) {
            Log.i(TAG, "ignore unusable network=$network")
            MeowDiagnostics.log(TAG, "ignore unusable ${describeNetwork(network)}")
            return
        }
        var shouldNotify = false
        synchronized(lock) {
            if (currentNetwork == network) {
                return
            }
            shouldNotify = true
            currentNetwork = network
        }
        Log.i(TAG, "updateNetwork network=$network notify=$shouldNotify")
        MeowDiagnostics.log(
            TAG,
            "updateNetwork ${describeNetwork(network)} notify=$shouldNotify",
        )
        if (shouldNotify) {
            notifyListener()
        }
    }

    private fun notifyListener() {
        val generation = notificationGeneration.incrementAndGet()
        val capturedNetwork = synchronized(lock) {
            if (listener == null) return
            currentNetwork
        }
        val runnable = Runnable {
            notifyExecutor.execute {
                runCatching { notifyListenerInternal(generation, capturedNetwork) }
                    .onFailure { Log.e(TAG, "notifyListenerInternal failed", it) }
            }
        }
        mainHandler.post {
            pendingNotifyRunnable?.let(mainHandler::removeCallbacks)
            pendingNotifyRunnable = runnable
            mainHandler.postDelayed(runnable, NETWORK_CHANGE_DEBOUNCE_MS)
        }
    }

    private fun notifyListenerInternal(generation: Long, capturedNetwork: Network?) {
        if (notificationGeneration.get() != generation) return
        val currentListener = synchronized(lock) { listener } ?: return
        val effectiveNetwork = capturedNetwork ?: resolveBestNetwork()
        if (effectiveNetwork == null) {
            if (notificationGeneration.get() != generation) return
            Log.i(TAG, "updateDefaultInterface: none")
            MeowDiagnostics.log(TAG, "updateDefaultInterface none current=${describeCurrentState()}")
            runCatching { currentListener.updateDefaultInterface("", -1, false, false) }
                .onFailure { Log.e(TAG, "updateDefaultInterface failed", it) }
            SingboxController.emitNetworkChanged(
                "default_interface_lost",
                describeCurrentState(),
                null,
                -1,
            )
            return
        }
        synchronized(lock) {
            if (started) currentNetwork = effectiveNetwork
        }
        val interfaceName =
            MeowApplication.connectivity.getLinkProperties(effectiveNetwork)?.interfaceName
        if (interfaceName.isNullOrBlank()) {
            if (notificationGeneration.get() != generation) return
            Log.w(TAG, "updateDefaultInterface: missing link properties for $effectiveNetwork")
            runCatching { currentListener.updateDefaultInterface("", -1, false, false) }
                .onFailure { Log.e(TAG, "updateDefaultInterface failed", it) }
            SingboxController.emitNetworkChanged(
                "default_interface_missing",
                describeNetwork(effectiveNetwork),
                null,
                -1,
            )
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
        Log.i(TAG, "updateDefaultInterface: $interfaceName index=$index")
        MeowDiagnostics.log(
            TAG,
            "updateDefaultInterface interface=$interfaceName index=$index current=${describeNetwork(effectiveNetwork)}",
        )
        runCatching { currentListener.updateDefaultInterface(interfaceName, index, false, false) }
            .onFailure { Log.e(TAG, "updateDefaultInterface failed", it) }
        SingboxController.emitNetworkChanged(
            "default_interface",
            describeNetwork(effectiveNetwork),
            interfaceName,
            index,
        )
    }

    private fun resolveBestNetwork(exclude: Network? = null): Network? {
        val connectivity = MeowApplication.connectivity
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val active = connectivity.activeNetwork
            if (active != null && active != exclude && isUsableNetwork(active)) {
                return active
            }
        }
        return connectivity.allNetworks
            .asSequence()
            .filter { it != exclude }
            .filter(::isUsableNetwork)
            .sortedByDescending(::networkScore)
            .firstOrNull()
            ?.also {
                Log.i(TAG, "resolveBestNetwork -> $it")
                MeowDiagnostics.log(TAG, "resolveBestNetwork -> ${describeNetwork(it)} exclude=${describeNetwork(exclude)}")
            }
    }

    private fun isUsableNetwork(network: Network): Boolean {
        val capabilities = MeowApplication.connectivity.getNetworkCapabilities(network) ?: return false
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

    private fun networkScore(network: Network): Int {
        val capabilities = MeowApplication.connectivity.getNetworkCapabilities(network) ?: return Int.MIN_VALUE
        var score = 0
        if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
            score += 100
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
        val connectivity = MeowApplication.connectivity
        val resolvedCapabilities = capabilities ?: connectivity.getNetworkCapabilities(network)
        val linkProperties = connectivity.getLinkProperties(network)
        val active = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            connectivity.activeNetwork == network
        } else {
            false
        }
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
        val active = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            MeowApplication.connectivity.activeNetwork
        } else {
            null
        }
        val current = synchronized(lock) { currentNetwork }
        return "current=${describeNetwork(current)} active=${describeNetwork(active)}"
    }

    private fun register() {
        when (Build.VERSION.SDK_INT) {
            in 31..Int.MAX_VALUE ->
                @TargetApi(31)
                runCatching {
                    MeowDiagnostics.log(TAG, "register method=registerBestMatchingNetworkCallback sdk=${Build.VERSION.SDK_INT}")
                    MeowApplication.connectivity.registerBestMatchingNetworkCallback(
                        request,
                        callback,
                        mainHandler,
                    )
                }.onFailure {
                    SingboxController.log("error", "default network callback failed: ${it.message}")
                }
            in 28 until 31 ->
                @TargetApi(28)
                runCatching {
                    MeowDiagnostics.log(TAG, "register method=requestNetwork(mainHandler) sdk=${Build.VERSION.SDK_INT}")
                    MeowApplication.connectivity.requestNetwork(request, callback, mainHandler)
                }.onFailure {
                    SingboxController.log("error", "default network request failed: ${it.message}")
                }
            in 24 until 28 ->
                @TargetApi(24)
                runCatching {
                    MeowDiagnostics.log(TAG, "register method=registerDefaultNetworkCallback sdk=${Build.VERSION.SDK_INT}")
                    MeowApplication.connectivity.registerDefaultNetworkCallback(callback)
                }.onFailure {
                    SingboxController.log("error", "default network callback failed: ${it.message}")
                }
            else ->
                runCatching {
                    MeowDiagnostics.log(TAG, "register method=requestNetwork sdk=${Build.VERSION.SDK_INT}")
                    MeowApplication.connectivity.requestNetwork(request, callback)
                }.onFailure {
                    SingboxController.log("error", "default network request failed: ${it.message}")
                }
        }
    }
}
