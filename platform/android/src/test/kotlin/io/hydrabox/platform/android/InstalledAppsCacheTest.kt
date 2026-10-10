package io.hydrabox.platform.android

import io.hydrabox.core.projection.InstalledApp
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class InstalledAppsCacheTest {
    @Test fun `full application names win over shortened launcher labels`() {
        assertEquals("Яндекс Карты", installedAppLabel("Яндекс Карты", "Карты", "ru.yandex.yandexmaps"))
        assertEquals("Карты", installedAppLabel(" ", "Карты", "ru.yandex.yandexmaps"))
        assertEquals("Карты", installedAppLabel("ru.yandex.yandexmaps", "Карты", "ru.yandex.yandexmaps"))
        assertEquals("ru.yandex.yandexmaps", installedAppLabel(null, null, "ru.yandex.yandexmaps"))
    }

    @Test fun `toggling a package updates its selection without enumerating again`() {
        var enumerations = 0
        val cache = InstalledAppsCache {
            enumerations++
            listOf(InstalledApp("maps", "Яндекс Карты", false))
        }
        assertFalse(cache.read(emptySet()).single().excluded)
        assertTrue(cache.read(setOf("maps")).single().excluded)
        assertFalse(cache.read(emptySet()).single().excluded)
        assertEquals(1, enumerations)
    }

    @Test fun `reopening refreshes the inventory and collapses launcher aliases`() {
        var apps = listOf(InstalledApp("maps", "Яндекс Карты", false))
        val cache = InstalledAppsCache { apps }
        assertEquals(1, cache.read(emptySet()).size)
        apps = apps + apps + InstalledApp("browser", "Браузер", false)
        cache.invalidate()
        assertEquals(listOf("maps", "browser"), cache.read(emptySet()).map { it.packageName })
    }

    @Test fun `invalidation during a read is honoured by the next read`() {
        var enumerations = 0
        lateinit var cache: InstalledAppsCache
        cache = InstalledAppsCache {
            if (++enumerations == 1) cache.invalidate()
            listOf(InstalledApp("maps", "Яндекс Карты", false))
        }
        cache.read(emptySet())
        cache.read(emptySet())
        assertEquals(2, enumerations)
    }

    @Test fun `a failed enumeration is retried instead of cached as an empty inventory`() {
        var enumerations = 0
        val cache = InstalledAppsCache {
            if (++enumerations == 1) throw IllegalStateException("package manager unavailable")
            listOf(InstalledApp("maps", "Яндекс Карты", false))
        }
        assertFailsWith<IllegalStateException> { cache.read(emptySet()) }
        assertEquals("Яндекс Карты", cache.read(emptySet()).single().label)
    }
}
