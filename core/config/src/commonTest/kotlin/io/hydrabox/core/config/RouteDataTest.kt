package io.hydrabox.core.config

import kotlin.test.Test
import kotlin.test.assertEquals

class RouteDataTest {
    @Test fun `Russia address exclusion requires both route data and setting`() {
        assertEquals(listOf("ru-geoip-ru"), RouteData.russiaAddressExclusions(useRussiaRouteData = true, routeExcludeRussiaEnabled = true))
        assertEquals(emptyList(), RouteData.russiaAddressExclusions(useRussiaRouteData = true, routeExcludeRussiaEnabled = false))
        assertEquals(emptyList(), RouteData.russiaAddressExclusions(useRussiaRouteData = false, routeExcludeRussiaEnabled = true))
    }

    @Test fun `adblock and Russia paths are explicit configuration inputs`() {
        val data = RouteData(adBlockPath = "adblock.srs", russiaRuleSetPaths = mapOf("ru-geoip-ru" to "geoip-ru.srs"))
        assertEquals("adblock.srs", data.adBlockPath); assertEquals("geoip-ru.srs", data.russiaRuleSetPaths.getValue("ru-geoip-ru"))
    }
}
