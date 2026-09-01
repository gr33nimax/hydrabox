package io.hydrabox.platform.android

import android.content.Context
import io.hydrabox.core.config.AUTO_TAG
import io.hydrabox.core.config.TunnelConfigGenerator
import io.hydrabox.core.config.TunnelInput
import io.hydrabox.core.diagnostics.Secret
import io.hydrabox.core.projection.ProxyEntry
import io.hydrabox.core.projection.SettingsSummary
import io.hydrabox.core.projection.SubscriptionSummary
import io.hydrabox.core.settings.DEFAULT_PROXY_USERNAME
import io.hydrabox.core.settings.DEFAULT_RUSSIA_DNS_DIRECT_RESOLVER
import io.hydrabox.core.settings.DEFAULT_URL_TEST_URL
import io.hydrabox.core.settings.NotificationTrafficDisplayMode
import io.hydrabox.core.settings.PerformanceMode
import io.hydrabox.core.settings.Settings
import io.hydrabox.core.settings.SettingsStore
import io.hydrabox.core.settings.TlsFragmentationMode
import io.hydrabox.core.settings.normalizeSplitRoutingPackages
import io.hydrabox.core.storage.SecretFieldCodec
import io.hydrabox.core.storage.StorageContext
import io.hydrabox.core.storage.StorageDatabase
import io.hydrabox.core.storage.openStorageDriver
import io.hydrabox.core.storage.platformSecretFieldCipher
import io.hydrabox.core.subscription.CatalogOutbound
import io.hydrabox.core.subscription.OutboundCatalogParser
import io.hydrabox.core.subscription.SubscriptionRecord
import io.hydrabox.core.subscription.SubscriptionStore

/**
 * Android-side composition of the core stores. Both processes open the same SQLite
 * database: the UI process writes subscriptions and the selection, the `:core` process
 * reads them when it builds a configuration. That is why the engine is SQLite and not a
 * document file.
 */
class AppStore(context: Context) {
    private val driver = openStorageDriver(StorageContext(context.applicationContext), DATABASE_NAME)
    private val database = StorageDatabase(driver)
    private val codec = SecretFieldCodec(platformSecretFieldCipher(driver))
    private val subscriptions = SubscriptionStore(database, codec, codec)
    private val settingsStore = SettingsStore(database, codec, codec)
    private val queries = database.storageDatabaseQueries

    // --- settings -----------------------------------------------------------------

    fun settings(): Settings = runCatching { settingsStore.load() }.getOrElse { defaultSettings() }

    fun saveSettings(settings: Settings) = settingsStore.save(settings)

    fun settingsSummary(settings: Settings = settings()) = SettingsSummary(
        performanceMode = settings.performanceMode.name.lowercase(),
        proxyDnsResolver = settings.dnsProxyResolver,
        directDnsResolver = settings.dnsDirectResolver,
        vpnMtu = settings.vpnMtu,
        splitRoutingPackageCount = settings.splitRoutingPackages.size,
        statusNotificationEnabled = settings.statusNotificationEnabled,
    )

    fun setSplitRoutingPackages(raw: String) = saveSettings(
        settings().copy(
            splitRoutingPackages = normalizeSplitRoutingPackages(raw.split(',', '\n', ' ')),
        ),
    )

    // --- subscriptions ------------------------------------------------------------

    fun records(): List<SubscriptionRecord> = runCatching { subscriptions.all() }.getOrDefault(emptyList())

    /**
     * Accepts a subscription URL or an inline body. A URL is fetched now and its body is
     * stored, so the core process never needs the network to build a configuration.
     */
    fun addSubscription(name: String, source: String): String {
        val trimmed = source.trim()
        val remote = trimmed.startsWith("http://") || trimmed.startsWith("https://")
        val body = if (remote) SubscriptionFetcher.fetch(trimmed) else trimmed
        val catalog = OutboundCatalogParser.parse(body)
        val id = "sub-" + (records().size + 1) + "-" + trimmed.hashCode().toUInt().toString(16)
        val label = name.trim().takeIf(String::isNotEmpty)
            ?: catalog.selectable.firstOrNull()?.tag?.takeIf { catalog.selectable.size == 1 }
            ?: "Subscription ${records().size + 1}"
        subscriptions.save(SubscriptionRecord(id, label, Secret.of(body), System.currentTimeMillis()))
        if (remote) queries.upsertValue(urlKey(id), trimmed.encodeToByteArray())
        if (selectedTag() == null) catalog.defaultTag?.let(::select)
            ?: catalog.selectable.firstOrNull()?.let { select(it.tag) }
        return id
    }

    fun refreshSubscription(id: String) {
        val url = queries.selectValue(urlKey(id)).executeAsOneOrNull()?.decodeToString()
        checkNotNull(url) { "subscription has no source URL to refresh" }
        val body = SubscriptionFetcher.fetch(url)
        OutboundCatalogParser.parse(body)
        val current = records().firstOrNull { it.id == id } ?: error("unknown subscription")
        subscriptions.save(SubscriptionRecord(id, current.name, Secret.of(body), System.currentTimeMillis()))
    }

    fun removeSubscription(id: String) {
        queries.deleteSubscription(id)
        queries.upsertValue(urlKey(id), ByteArray(0))
    }

    fun renameSubscription(id: String, name: String) {
        val current = records().firstOrNull { it.id == id } ?: return
        subscriptions.save(SubscriptionRecord(id, name.trim().ifEmpty { current.name }, current.source, current.updatedAtMillis))
    }

    private fun catalogs(): List<Pair<SubscriptionRecord, List<CatalogOutbound>>> = records().map { record ->
        record to runCatching {
            record.source.use(OutboundCatalogParser::parse).outbounds.map { it.copy(scope = record.id) }
        }.getOrDefault(emptyList())
    }

    fun summaries(): List<SubscriptionSummary> = catalogs().map { (record, outbounds) ->
        SubscriptionSummary(
            id = record.id,
            name = record.name,
            outboundCount = outbounds.count(CatalogOutbound::selectable),
            updatedAtMillis = record.updatedAtMillis,
        )
    }

    fun proxies(): List<ProxyEntry> {
        val selected = selectedTag() ?: AUTO_TAG
        val named = catalogs().flatMap { (record, outbounds) ->
            outbounds.filter(CatalogOutbound::selectable).map { outbound ->
                ProxyEntry(outbound.tag, outbound.type, record.id, outbound.tag == selected)
            }
        }
        if (named.isEmpty()) return named
        // The automatic group is a real outbound in the generated config, so it belongs in
        // the same list rather than being a separate control.
        return listOf(ProxyEntry(AUTO_TAG, "lowest latency", "", selected == AUTO_TAG)) + named
    }

    fun parseError(id: String): String? = records().firstOrNull { it.id == id }?.let { record ->
        runCatching { record.source.use(OutboundCatalogParser::parse) }.exceptionOrNull()?.message
    }

    // --- selection and configuration ----------------------------------------------

    fun selectedTag(): String? = queries.selectValue(SELECTED_KEY).executeAsOneOrNull()
        ?.decodeToString()?.takeIf(String::isNotEmpty)

    fun select(tag: String) = queries.upsertValue(SELECTED_KEY, tag.encodeToByteArray())

    /** Builds the configuration the core will run. Returns null when nothing is usable. */
    fun generateConfig(): String? {
        val outbounds = catalogs().flatMap { it.second }
        if (outbounds.none(CatalogOutbound::selectable)) return null
        val settings = settings()
        return TunnelConfigGenerator.generate(
            TunnelInput(
                outbounds = outbounds,
                selectedTag = selectedTag(),
                proxyDnsResolver = settings.dnsProxyResolver,
                directDnsResolver = settings.dnsDirectResolver,
                mtu = settings.vpnMtu,
                excludePackages = settings.splitRoutingPackages,
                urlTestUrl = settings.urlTestUrl,
                urlTestIntervalSeconds = settings.urlTestIntervalSeconds,
            ),
        )
    }

    // --- start diagnostics --------------------------------------------------------

    /**
     * The core process records why a start failed; the UI process reads it back. Without
     * this the only symptom is a tunnel that never comes up and no reason anywhere.
     */
    fun recordStartFailure(reason: String) = queries.upsertValue(START_FAILURE_KEY, reason.encodeToByteArray())

    fun clearStartFailure() = queries.upsertValue(START_FAILURE_KEY, ByteArray(0))

    fun startFailure(): String? = queries.selectValue(START_FAILURE_KEY).executeAsOneOrNull()
        ?.decodeToString()?.takeIf(String::isNotEmpty)

    /** The configuration as the core will see it, for the diagnostics screen. */
    fun configPreview(): String? = runCatching { generateConfig() }.getOrElse { "generation failed: ${it.message}" }

    private fun urlKey(id: String) = "subscription.$id.url"

    private fun defaultSettings() = Settings(
        performanceMode = PerformanceMode.STANDARD,
        urlTestUrl = DEFAULT_URL_TEST_URL,
        urlTestIntervalSeconds = 600,
        urlTestTimeoutSeconds = 5,
        urlTestConcurrency = 4,
        urlTestUnavailableCheckIntervalSeconds = 60,
        locationLookupLimit = 16,
        locationLookupTimeoutSeconds = 5,
        locationLookupConcurrency = 4,
        russiaDnsDirectResolver = DEFAULT_RUSSIA_DNS_DIRECT_RESOLVER,
        dnsDirectResolver = "1.1.1.1",
        dnsProxyResolver = "https://dns.cloudflare.com/dns-query",
        memoryLimitEnabled = false,
        memoryLimitWarningDismissed = false,
        statusNotificationEnabled = true,
        notificationTrafficDisplayMode = NotificationTrafficDisplayMode.BOTH,
        acceptedLegalVersion = "",
        acceptedLegalAtMillis = null,
        tlsFragmentationMode = TlsFragmentationMode.DISABLED,
        proxyUsername = DEFAULT_PROXY_USERNAME,
        proxyPassword = null,
        proxySort = "name",
        vpnMtu = 9000,
        splitRoutingPackages = emptyList(),
    )

    private companion object {
        const val DATABASE_NAME = "hydrabox.db"
        const val SELECTED_KEY = "runtime.selected.outbound"
        const val START_FAILURE_KEY = "runtime.last.start.failure"
    }
}
