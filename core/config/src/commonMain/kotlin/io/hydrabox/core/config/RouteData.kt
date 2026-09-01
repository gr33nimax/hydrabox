package io.hydrabox.core.config

data class RouteData(val adBlockPath: String?, val russiaRuleSetPaths: Map<String, String>) {
    companion object {
        fun russiaAddressExclusions(useRussiaRouteData: Boolean, routeExcludeRussiaEnabled: Boolean): List<String> =
            if (useRussiaRouteData && routeExcludeRussiaEnabled) listOf("ru-geoip-ru") else emptyList()
    }
}
