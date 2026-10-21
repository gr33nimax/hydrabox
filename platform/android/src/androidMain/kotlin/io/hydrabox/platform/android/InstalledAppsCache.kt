package io.hydrabox.platform.android

import io.hydrabox.core.projection.InstalledApp
import java.util.concurrent.atomic.AtomicLong

/** Package metadata is stable during a visit; the chosen package set is not. */
internal class InstalledAppsCache(private val load: () -> List<InstalledApp>) {
    private data class Entry(val revision: Long, val apps: List<InstalledApp>)
    private val revision = AtomicLong()
    @Volatile private var cached: Entry? = null

    fun invalidate() {
        revision.incrementAndGet()
    }

    fun read(selected: Set<String>): List<InstalledApp> {
        val version = revision.get()
        val apps = cached?.takeIf { it.revision == version }?.apps
            ?: load().distinctBy { it.packageName }.also {
                // A reload requested during enumeration must still happen on the next read.
                if (revision.get() == version) cached = Entry(version, it)
            }
        return apps.map { it.copy(excluded = it.packageName in selected) }
    }
}

/** Launcher aliases can say just "Maps" even when the application is called "Yandex Maps". */
internal fun installedAppLabel(application: String?, launcher: String?, packageName: String): String =
    application?.trim()?.takeIf { it.isNotEmpty() && it != packageName }
        ?: launcher?.trim()?.takeIf(String::isNotEmpty)
        ?: packageName
