package io.hydrabox.platform.android

import android.content.Context
import android.content.Intent
import android.net.VpnService

internal sealed interface ConnectionPreparation {
    data object LegalRequired : ConnectionPreparation

    data object SourceRequired : ConnectionPreparation

    data class Ready(val proxyOnly: Boolean) : ConnectionPreparation
}

/** Shared by the activity and Quick Settings; prepare runs on their worker threads. */
internal object ConnectionStart {
    fun prepare(context: Context): Result<ConnectionPreparation> =
        runCatching { AppStore(context).use { prepare(it).getOrThrow() } }

    fun prepare(store: AppStore): Result<ConnectionPreparation> =
        runCatching {
            val settings = store.settings()
            when {
                settings.acceptedLegalAtMillis == null -> ConnectionPreparation.LegalRequired
                store.generateConfig() == null -> ConnectionPreparation.SourceRequired
                else -> ConnectionPreparation.Ready(store.proxyOnly(settings))
            }
        }

    fun permission(context: Context, ready: ConnectionPreparation.Ready): Intent? =
        if (ready.proxyOnly) null else VpnService.prepare(context)

    fun launch(context: Context) {
        context.startForegroundService(Intent(context, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
    }
}
