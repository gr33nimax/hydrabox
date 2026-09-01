package io.hydrabox.platform.android

import android.content.Context
import io.hydrabox.core.config.TunnelConfigGenerator
import io.hydrabox.core.config.TunnelInput
import io.hydrabox.core.diagnostics.Secret
import io.hydrabox.core.projection.ProxyEntry
import io.hydrabox.core.projection.SettingsSummary
import io.hydrabox.core.projection.SubscriptionSummary
import io.hydrabox.core.settings.Settings
import io.hydrabox.core.settings.SettingsStore
import io.hydrabox.core.storage.SecretFieldCodec
import io.hydrabox.core.storage.StorageContext
import io.hydrabox.core.storage.StorageDatabase
import io.hydrabox.core.storage.openStorageDriver
import io.hydrabox.core.storage.platformSecretFieldCipher
import io.hydrabox.core.subscription.ShareLink
import io.hydrabox.core.subscription.SubscriptionParser
import io.hydrabox.core.subscription.SubscriptionRecord
import io.hydrabox.core.subscription.SubscriptionStore

/**
 * Android-side composition of the core stores. Both processes open the same SQLite
 * database: the UI process writes subscriptions and the selection, the `:core` process
 * reads them when it builds a configuration. That is why the storage engine is SQLite and
 * not a document file.
 */
class AppStore(context: Context) {
    private val driver = openStorageDriver(StorageContext(context.applicationContext), DATABASE_NAME)
    private val database = StorageDatabase(driver)
    private val codec = SecretFieldCodec(platformSecretFieldCipher(driver))
    private val subscriptions = SubscriptionStore(database, codec, codec)
    private val settingsStore = SettingsStore(database, codec, codec)
    private val queries = database.storageDatabaseQueries

    fun settings(): Settings = runCatching { settingsStore.load() }.getOrElse { defaultSettings() }

    fun saveSettings(settings: Settings) = settingsStore.save(settings)

    fun records(): List<SubscriptionRecord> = runCatching { subscriptions.all() }.getOrDefault(emptyList())

    fun addSubscription(name: String, source: String) {
        val links = SubscriptionParser.parseAll(source)
        check(links.isNotEmpty()) { "no outbounds in subscription" }
        val id = "sub-" + (queries.selectSubscriptions().executeAsList().size + 1) + "-" + source.hashCode().toUInt().toString(16)
        subscriptions.save(
            SubscriptionRecord(
                id = id,
                name = name.trim().takeIf(String::isNotEmpty) ?: links.first().name.takeIf(String::isNotEmpty) ?: id,
                source = Secret.of(source),
                updatedAtMillis = System.currentTimeMillis(),
            ),
        )
        if (selectedTag() == null) select(tagOf(links.first(), 0))
    }

    fun removeSubscription(id: String) = queries.deleteSubscription(id)

    fun links(): List<Pair<String, ShareLink>> = records().flatMap { record ->
        runCatching {
            record.source.use(SubscriptionParser::parseAll).map { record.id to it }
        }.getOrDefault(emptyList())
    }

    fun summaries(): List<SubscriptionSummary> {
        val grouped = links().groupBy { it.first }
        return records().map { record ->
            SubscriptionSummary(record.id, record.name, grouped[record.id]?.size ?: 0, record.updatedAtMillis)
        }
    }

    fun proxies(): List<ProxyEntry> {
        val selected = selectedTag()
        return links().mapIndexed { index, (subscriptionId, link) ->
            val tag = tagOf(link, index)
            ProxyEntry(tag, typeOf(link), subscriptionId, tag == selected)
        }
    }

    fun selectedTag(): String? = queries.selectValue(SELECTED_KEY).executeAsOneOrNull()?.decodeToString()

    fun select(tag: String) = queries.upsertValue(SELECTED_KEY, tag.encodeToByteArray())

    fun settingsSummary(settings: Settings = settings()) = SettingsSummary(
        performanceMode = settings.performanceMode.name.lowercase(),
        proxyDnsResolver = settings.dnsProxyResolver,
        directDnsResolver = settings.dnsDirectResolver,
        vpnMtu = settings.vpnMtu,
        splitRoutingPackageCount = settings.splitRoutingPackages.size,
        statusNotificationEnabled = settings.statusNotificationEnabled,
    )

    /** Builds the configuration the core will run. Returns null when nothing is selected. */
    fun generateConfig(): String? {
        val entries = links()
        if (entries.isEmpty()) return null
        val settings = settings()
        return TunnelConfigGenerator.generate(
            TunnelInput(
                links = entries.mapIndexed { index, (_, link) -> renamed(link, tagOf(link, index)) },
                selectedTag = selectedTag(),
                proxyDnsResolver = settings.dnsProxyResolver,
                directDnsResolver = settings.dnsDirectResolver.substringAfter("://", settings.dnsDirectResolver),
                mtu = settings.vpnMtu,
                excludePackages = settings.splitRoutingPackages,
            ),
        )
    }

    private fun renamed(link: ShareLink, tag: String): ShareLink = when (link) {
        is ShareLink.Vless -> link.copy(name = tag)
        is ShareLink.Trojan -> link.copy(name = tag)
        is ShareLink.Proxy -> link.copy(name = tag)
        is ShareLink.WireGuard -> link.copy(name = tag)
    }

    private fun tagOf(link: ShareLink, index: Int): String =
        link.name.trim().takeIf(String::isNotEmpty) ?: "${link.server}-${link.port}-$index"

    private fun typeOf(link: ShareLink): String = when (link) {
        is ShareLink.Vless -> "vless"
        is ShareLink.Trojan -> "trojan"
        is ShareLink.Proxy -> link.type
        is ShareLink.WireGuard -> "wireguard"
    }

    private fun defaultSettings() = Settings(
        performanceMode = io.hydrabox.core.settings.PerformanceMode.STANDARD,
        urlTestUrl = io.hydrabox.core.settings.DEFAULT_URL_TEST_URL,
        urlTestIntervalSeconds = 600,
        urlTestTimeoutSeconds = 5,
        urlTestConcurrency = 4,
        urlTestUnavailableCheckIntervalSeconds = 60,
        locationLookupLimit = 16,
        locationLookupTimeoutSeconds = 5,
        locationLookupConcurrency = 4,
        russiaDnsDirectResolver = io.hydrabox.core.settings.DEFAULT_RUSSIA_DNS_DIRECT_RESOLVER,
        dnsDirectResolver = "1.1.1.1",
        dnsProxyResolver = "https://dns.cloudflare.com/dns-query",
        memoryLimitEnabled = false,
        memoryLimitWarningDismissed = false,
        statusNotificationEnabled = true,
        notificationTrafficDisplayMode = io.hydrabox.core.settings.NotificationTrafficDisplayMode.BOTH,
        acceptedLegalVersion = "",
        acceptedLegalAtMillis = null,
        tlsFragmentationMode = io.hydrabox.core.settings.TlsFragmentationMode.DISABLED,
        proxyUsername = io.hydrabox.core.settings.DEFAULT_PROXY_USERNAME,
        proxyPassword = null,
        proxySort = "name",
        vpnMtu = 9000,
        splitRoutingPackages = emptyList(),
    )

    private companion object {
        const val DATABASE_NAME = "hydrabox.db"
        const val SELECTED_KEY = "runtime.selected.outbound"
    }
}
