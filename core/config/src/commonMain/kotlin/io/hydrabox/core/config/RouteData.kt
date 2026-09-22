package io.hydrabox.core.config

/**
 * The rule sets on disk that the configuration may point at.
 *
 * HydraBox 1.x downloaded and compiled these outside the configuration and then referenced
 * them as local files (`singbox_config_builder.dart`, `type: local`). Nothing here decides
 * whether a set is used — that is a setting — but a set that is not on disk cannot be used at
 * all, which is why the paths are nullable and the switch above them reads this.
 */
data class RouteData(
    val adBlockPath: String? = null,
    val adBlockAllowPath: String? = null,
    val russiaRuleSetPaths: Map<String, String> = emptyMap(),
    /** The compiled geoip set of Russian IP ranges, or null when it has not been downloaded. */
    val russiaGeoipPath: String? = null,
) {
    val adBlockAvailable get() = adBlockPath != null

    /** The IP half of the Russia-direct route needs the geoip set on disk; the domain half never does. */
    val russiaGeoipAvailable get() = russiaGeoipPath != null

    companion object {
        val None = RouteData()

        /**
         * The `.ru`/`.su`/`.рф` suffixes that go direct by name, independent of any download.
         * `xn--p1ai` is `.рф` in punycode, which is how the core actually sees it.
         */
        val RUSSIA_DOMAIN_SUFFIXES = listOf(".ru", ".su", ".рф", ".xn--p1ai")

        fun russiaAddressExclusions(
            useRussiaRouteData: Boolean,
            routeExcludeRussiaEnabled: Boolean,
        ): List<String> = if (useRussiaRouteData && routeExcludeRussiaEnabled) listOf("ru-geoip-ru") else emptyList()
    }
}
