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
import android.os.SystemClock
import android.util.Log
import io.hydrabox.client.HydraBoxApplication
import io.hydrabox.client.runtime.CoreProcessIdentity
import io.hydrabox.client.runtime.CoreRuntimeService
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

internal fun msSinceLastCallback(nowMs: Long, lastMs: Long): Long =
    if (lastMs < 0L) -1L else (nowMs - lastMs).coerceAtLeast(0L)

internal data class NetworkIdentity(
    val androidNetworkId: String?,
    val interfaceName: String,
    val interfaceIndex: Int,
)

internal data class PhysicalNetworkSnapshot(
    val network: Network?,
    val identity: NetworkIdentity,
)

internal data class NetworkTransition(
    val generation: Long,
    val changed: Boolean,
    val publishUpdate: Boolean,
)

internal fun nextNetworkTransition(
    previous: NetworkIdentity?,
    current: NetworkIdentity,
    generation: Long,
): NetworkTransition {
    val changed = previous != current
    return NetworkTransition(
        generation = if (changed) generation + 1 else generation,
        changed = changed,
        publishUpdate = changed,
    )
}

internal enum class NetworkEventTrigger(val telemetryValue: String) {
    CALLBACK("callback"),
    HEARTBEAT("heartbeat"),
    LAUNCH("launch"),
}

internal enum class NetworkEventBranch(val telemetryValue: String) {
    DIVERGENCE("divergence"),
    LOST_SELECTABLE("lost_selectable"),
    LOST_ACTIVE("lost_active"),
    STALE_IFACE("stale_iface"),
    NOOP("noop"),
    CHANGED("changed"),
    NONE("none"),
    INDEX_UNAVAILABLE("index_unavailable"),
}

internal fun decideNetworkEventBranch(
    trigger: NetworkEventTrigger,
    bestNetworkPresent: Boolean,
    bestMatchesCached: Boolean,
    cachedNetworkPresent: Boolean,
    activeNetworkPresent: Boolean,
    cachedInterfaceStale: Boolean,
    changed: Boolean = false,
    none: Boolean = false,
): NetworkEventBranch = when {
    trigger == NetworkEventTrigger.LAUNCH -> NetworkEventBranch.NOOP
    none -> NetworkEventBranch.NONE
    changed -> NetworkEventBranch.CHANGED
    bestNetworkPresent && !bestMatchesCached -> NetworkEventBranch.DIVERGENCE
    !bestNetworkPresent && cachedNetworkPresent -> NetworkEventBranch.LOST_SELECTABLE
    !activeNetworkPresent && cachedNetworkPresent -> NetworkEventBranch.LOST_ACTIVE
    cachedInterfaceStale -> NetworkEventBranch.STALE_IFACE
    else -> NetworkEventBranch.NOOP
}

private fun shortMonitorId(value: String): String = value.take(8).ifEmpty { "none" }

internal enum class InterfacePublication {
    PUBLISH_INTERFACE,
    RETRY_SNAPSHOT,
    PUBLISH_NONE,
}

internal fun decideInterfacePublication(
    effectiveNetworkPresent: Boolean,
    interfaceIndex: Int,
    consecutiveUnresolvedSnapshots: Int,
): InterfacePublication = when {
    !effectiveNetworkPresent -> InterfacePublication.PUBLISH_NONE
    interfaceIndex >= 0 -> InterfacePublication.PUBLISH_INTERFACE
    consecutiveUnresolvedSnapshots >= 3 -> InterfacePublication.PUBLISH_NONE
    else -> InterfacePublication.RETRY_SNAPSHOT
}

internal fun replayDefaultInterface(
    listener: InterfaceUpdateListener,
    interfaceName: String,
    interfaceIndex: Int,
): Boolean {
    if (interfaceName.isBlank() || interfaceName == "tun0" || interfaceIndex < 0) return false
    listener.updateDefaultInterface(interfaceName, interfaceIndex, false, false)
    return true
}

object HydraBoxDefaultNetworkMonitor {
    private const val TAG = "HydraBoxDefaultNetwork"
    private const val NO_CALLBACK_YET = -1L
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
    private val networkGeneration = AtomicLong(0L)
    private val lastAndroidCallbackElapsedMs = AtomicLong(NO_CALLBACK_YET)
    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .build()

    private var started = false
    private var currentNetwork: Network? = null
    private val listeners = IdentityListenerRegistry<InterfaceUpdateListener>()
    private var heartbeatFuture: ScheduledFuture<*>? = null
    private var pendingSnapshotRunnable: Runnable? = null
    private var currentSnapshot: PhysicalNetworkSnapshot? = null

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
            lastAndroidCallbackElapsedMs.set(SystemClock.elapsedRealtime())
            Log.i(TAG, "onAvailable network=$network")
            HydraBoxDiagnostics.log(TAG, "onAvailable ${describeNetwork(network)}")
            scheduleSnapshot(NetworkEventTrigger.CALLBACK.telemetryValue)
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            lastAndroidCallbackElapsedMs.set(SystemClock.elapsedRealtime())
            Log.i(
                TAG,
                "onCapabilitiesChanged network=$network transports=${describeTransports(networkCapabilities)}",
            )
            HydraBoxDiagnostics.log(
                TAG,
                "onCapabilitiesChanged ${describeNetwork(network, networkCapabilities)}",
            )
            scheduleSnapshot(NetworkEventTrigger.CALLBACK.telemetryValue)
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            lastAndroidCallbackElapsedMs.set(SystemClock.elapsedRealtime())
            HydraBoxDiagnostics.log(
                TAG,
                "onLinkPropertiesChanged network=$network interface=${linkProperties.interfaceName}",
            )
            scheduleSnapshot(NetworkEventTrigger.CALLBACK.telemetryValue)
        }

        override fun onLost(network: Network) {
            lastAndroidCallbackElapsedMs.set(SystemClock.elapsedRealtime())
            Log.w(TAG, "onLost network=$network")
            HydraBoxDiagnostics.log(TAG, "onLost ${describeNetwork(network)}")
            scheduleSnapshot(NetworkEventTrigger.CALLBACK.telemetryValue)
        }
    }

    fun start() {
        synchronized(lock) {
            if (started) {
                return
            }
            started = true
            currentSnapshot = null
        }
        Log.i(TAG, "start")
        HydraBoxDiagnostics.log(TAG, "start current=${describeCurrentState()}")
        register()
        HydraBoxDiagnostics.event(
            "NETWORK", "ep" to shortMonitorId(CoreProcessIdentity.epoch), "cg" to CoreProcessIdentity.generation.get(),
            "rg" to SingboxController.activeRuntimeGeneration, "ng" to networkGeneration.get(),
            "trigger" to NetworkEventTrigger.LAUNCH.telemetryValue,
            "branch" to decideNetworkEventBranch(
                trigger = NetworkEventTrigger.LAUNCH,
                bestNetworkPresent = false,
                bestMatchesCached = true,
                cachedNetworkPresent = false,
                activeNetworkPresent = true,
                cachedInterfaceStale = false,
            ).telemetryValue,
            "ms_since_last_callback" to msSinceLastCallback(SystemClock.elapsedRealtime(), lastAndroidCallbackElapsedMs.get()),
        )
        startHeartbeat()
        scheduleSnapshot(NetworkEventTrigger.LAUNCH.telemetryValue, immediate = true)
    }

    fun stop() {
        synchronized(lock) {
            if (!started) {
                return
            }
            started = false
            currentNetwork = null
            currentSnapshot = null
            pendingSnapshotRunnable?.let(networkHandler::removeCallbacks)
            pendingSnapshotRunnable = null
        }
        Log.i(TAG, "stop")
        HydraBoxDiagnostics.log(TAG, "stop current=${describeCurrentState()}")
        publishNetworkChanged(emptyList(), null, "", -1, networkGeneration.get())
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
        scheduleSnapshot(NetworkEventTrigger.HEARTBEAT.telemetryValue)
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
            generation = networkGeneration.get(),
            reason = reason,
            updatedAtMillis = System.currentTimeMillis(),
        )
    }

    fun addListener(newListener: InterfaceUpdateListener) {
        synchronized(lock) {
            listeners.add(newListener)
        }
        HydraBoxDiagnostics.log(
            TAG,
            "listener_attached count=${listenerCount()} current=${describeCurrentState()}",
        )
        replayTo(newListener)
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

    fun reassertDefaultInterface() {
        listeners.snapshot().forEach(::replayTo)
    }

    internal fun listenerCount(): Int = synchronized(lock) { listeners.size() }

    private fun scheduleSnapshot(trigger: String, immediate: Boolean = false) {
        val runnable = Runnable { notifyExecutor.execute { onSnapshot(trigger) } }
        networkHandler.post {
            pendingSnapshotRunnable?.let(networkHandler::removeCallbacks)
            pendingSnapshotRunnable = runnable
            if (immediate) networkHandler.post(runnable)
            else networkHandler.postDelayed(runnable, NETWORK_CHANGE_DEBOUNCE_MS)
        }
    }

    private fun publishNetworkChanged(
        listeners: List<InterfaceUpdateListener>,
        network: Network?,
        interfaceName: String,
        interfaceIndex: Int,
        generation: Long,
        replay: Boolean = false,
    ) {
        CoreRuntimeService.submitInternalNetwork(
            network,
            CoreRuntimeProtocol.NetworkChanged.newBuilder()
                .setNetworkGeneration(generation)
                .setInterfaceName(interfaceName)
                .setInterfaceIndex(interfaceIndex)
                .setAvailable(interfaceName.isNotBlank() && interfaceIndex >= 0)
                .build(),
            listeners,
            replay,
        )
    }

    private fun onSnapshot(trigger: String) {
        val network = resolveBestNetwork()
        val interfaceName = network?.let {
            HydraBoxApplication.connectivity.getLinkProperties(it)?.interfaceName?.trim()
        }.orEmpty()
        val interfaceIndex = if (interfaceName.isEmpty()) -1 else resolveInterfaceIndex(interfaceName)
        val snapshot = PhysicalNetworkSnapshot(
            network,
            NetworkIdentity(network?.toString(), interfaceName, interfaceIndex),
        )
        val previous: PhysicalNetworkSnapshot?
        val currentListeners: List<InterfaceUpdateListener>
        synchronized(lock) {
            if (!started) return
            previous = currentSnapshot
            val transition = nextNetworkTransition(previous?.identity, snapshot.identity, networkGeneration.get())
            if (!transition.changed) {
                logNetworkSnapshot(
                    trigger,
                    NetworkEventBranch.NOOP,
                    transition.generation,
                    snapshot.identity.interfaceName,
                    snapshot.identity.interfaceIndex,
                )
                return
            }
            currentSnapshot = snapshot
            currentNetwork = network
            networkGeneration.set(transition.generation)
            currentListeners = listeners.snapshot()
        }
        val branch = if (network == null) NetworkEventBranch.NONE else NetworkEventBranch.CHANGED
        logNetworkSnapshot(trigger, branch, networkGeneration.get(), interfaceName, interfaceIndex)
        publishNetworkChanged(currentListeners, network, interfaceName, interfaceIndex, networkGeneration.get())
    }

    private fun replayTo(listener: InterfaceUpdateListener) {
        val snapshot = synchronized(lock) {
            if (listeners.contains(listener)) currentSnapshot else null
        } ?: resolveReplaySnapshot() ?: return
        if (!synchronized(lock) { listeners.contains(listener) }) return
        runCatching {
            replayDefaultInterface(
                listener,
                snapshot.identity.interfaceName,
                snapshot.identity.interfaceIndex,
            )
        }.onFailure { error ->
            HydraBoxDiagnostics.log(TAG, "listener_replay_failed", error)
        }
    }

    private fun resolveReplaySnapshot(): PhysicalNetworkSnapshot? {
        val network = resolveBestNetwork() ?: return null
        val interfaceName = HydraBoxApplication.connectivity.getLinkProperties(network)
            ?.interfaceName
            ?.trim()
            .orEmpty()
        val interfaceIndex = if (interfaceName.isEmpty()) -1 else resolveInterfaceIndex(interfaceName)
        return PhysicalNetworkSnapshot(
            network,
            NetworkIdentity(network.toString(), interfaceName, interfaceIndex),
        )
    }

    private fun logNetworkSnapshot(
        trigger: String,
        branch: NetworkEventBranch,
        generation: Long,
        interfaceName: String = currentSnapshot?.identity?.interfaceName.orEmpty(),
        interfaceIndex: Int = currentSnapshot?.identity?.interfaceIndex ?: -1,
    ) {
        HydraBoxDiagnostics.event(
            "NETWORK", "ep" to shortMonitorId(CoreProcessIdentity.epoch), "cg" to CoreProcessIdentity.generation.get(),
            "rg" to SingboxController.activeRuntimeGeneration, "ng" to generation,
            "trigger" to trigger,
            "branch" to branch.telemetryValue,
            "iface_name" to interfaceName,
            "iface_idx" to interfaceIndex,
            "ms_since_last_callback" to msSinceLastCallback(SystemClock.elapsedRealtime(), lastAndroidCallbackElapsedMs.get()),
        )
    }

    private fun resolveInterfaceIndex(interfaceName: String): Int {
        var index = -1
        for (attempt in 0 until 10) {
            index = runCatching { NetworkInterface.getByName(interfaceName)?.index ?: -1 }
                .getOrDefault(-1)
            if (index >= 0) break
            try {
                Thread.sleep(100)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return -1
            }
        }
        return index
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
                    score = networkScore(capabilities, isValidated),
                )
            }
        val current = synchronized(lock) { currentNetwork }
        val selectedNetwork = selectDefaultNetworkCandidate(
            candidates = candidates.map { candidate ->
                DefaultNetworkCandidate(
                    value = candidate.network,
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
        return isBaseUsableNetwork(capabilities) && hasUsableNetworkInterface(network)
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
        isValidated: Boolean,
    ): Int {
        var score = 0
        if (isValidated) {
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
