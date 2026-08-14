package io.hydrabox.client.platform

import android.app.ActivityManager
import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Process
import java.io.File

/** Process identity that remains correct on API 26-27 multi-process apps. */
object AndroidProcessIdentity {
    fun current(context: Context): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Application.getProcessName().trim().takeIf(String::isNotEmpty)?.let { return it }
        }
        runCatching {
            File("/proc/self/cmdline").readBytes()
                .take(MAX_CMDLINE_BYTES)
                .takeWhile { it != 0.toByte() }
                .toByteArray()
                .toString(Charsets.UTF_8)
                .trim()
        }.getOrNull()?.takeIf(String::isNotEmpty)?.let { return it }

        val activityManager = context.applicationContext
            .getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        activityManager.runningAppProcesses
            ?.firstOrNull { it.pid == Process.myPid() }
            ?.processName
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?.let { return it }
        throw IllegalStateException("Android process identity is unavailable")
    }

    private const val MAX_CMDLINE_BYTES = 512
}
