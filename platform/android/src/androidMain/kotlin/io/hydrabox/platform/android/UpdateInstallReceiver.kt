package io.hydrabox.platform.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

private const val AREA = "update"

/**
 * The installer's verdict, from the system rather than from us: Android is the only authority on
 * whether an APK was accepted, and this is how it says so.
 *
 * The interesting case is [PackageInstaller.STATUS_PENDING_USER_ACTION]. A committed session does
 * not install anything by itself — the system hands back the confirmation it wants shown, and an
 * application that ignores it leaves the install waiting for ever with nothing on screen. That was
 * the whole of `PackageInstaller` failing quietly, so the intent is forwarded rather than logged.
 */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmation = confirmationOf(intent)
                if (confirmation == null) {
                    HydraLog.warn(AREA, "the installer asked for a confirmation it did not send")
                } else {
                    confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    runCatching { context.startActivity(confirmation) }
                        .onFailure { HydraLog.warn(AREA, "the install confirmation could not be shown", it) }
                }
            }

            PackageInstaller.STATUS_SUCCESS -> {
                HydraLog.info(AREA, "the update was installed")
            }

            else -> {
                // The message is the system's own words, and it is the only explanation a person
                // can be given for a refusal that happened outside this application.
                HydraLog.warn(
                    AREA,
                    "the update was not installed: " +
                        intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE).orEmpty(),
                )
            }
        }
    }

    private fun confirmationOf(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT) as? Intent
        }
}
