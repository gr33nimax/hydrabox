package com.etonify.meow_client.singbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.etonify.meow_client.MainActivity
import com.etonify.meow_client.R
import kotlin.math.max

/**
 * Owns the foreground notification while a libbox runtime is active.
 *
 * The service, rather than Flutter, owns this state intentionally: a VPN
 * foreground service can outlive the Activity and Flutter engine. Flutter only
 * supplies the currently selected outbound and localized labels; transfer
 * speeds remain native status-stream values.
 */
internal class MeowForegroundNotification(
    private val service: Service,
    private val notificationId: Int,
) {
    companion object {
        const val CHANNEL_ID = "etonify_vpn_status"
        const val ACTION_REFRESH_LATENCY = "com.etonify.meow_client.singbox.REFRESH_LATENCY"

        private const val ACTION_REFRESH_REQUEST_CODE = 4201
        private const val ACTION_STOP_REQUEST_CODE = 4202
        private const val CONTENT_REQUEST_CODE = 4203
        private const val DEFAULT_LATENCY_TIMEOUT_MS = 20_000L
        private const val MAX_TEXT_LENGTH = 120
    }

    private data class UrlTestRequest(
        val groupTag: String,
        val targetOutboundTag: String,
        val priorityOutboundTag: String,
        val excludeOutboundTag: String,
        val url: String,
        val timeoutMillis: Int,
        val concurrency: Int,
        val deadlineMillis: Int,
    ) {
        companion object {
            fun fromArguments(arguments: Map<*, *>): UrlTestRequest? {
                fun text(key: String): String =
                    arguments[key]?.toString()?.trim()?.take(MAX_TEXT_LENGTH).orEmpty()
                fun number(key: String, fallback: Int): Int =
                    (arguments[key] as? Number)?.toInt()?.takeIf { it > 0 } ?: fallback

                val target = text("targetOutboundTag")
                val url = text("url")
                if (target.isEmpty() || url.isEmpty()) {
                    return null
                }
                val timeout = number("timeoutMillis", 15_000).coerceIn(1_000, 30_000)
                return UrlTestRequest(
                    groupTag = text("groupTag").ifEmpty { "select" },
                    targetOutboundTag = target,
                    priorityOutboundTag = text("priorityOutboundTag").ifEmpty { target },
                    excludeOutboundTag = text("excludeOutboundTag"),
                    url = url,
                    timeoutMillis = timeout,
                    concurrency = number("concurrency", 1).coerceIn(1, 4),
                    deadlineMillis = number("deadlineMillis", timeout + 5_000)
                        .coerceIn(timeout, 35_000),
                )
            }
        }
    }

    private data class Presentation(
        val detailed: Boolean = true,
        val title: String = "",
        val latencyMillis: Long? = null,
        val connectedText: String = "VPN подключён",
        val checkingText: String = "...",
        val unavailableText: String = "Пинг недоступен",
        val refreshLabel: String = "Проверить пинг",
        val stopLabel: String = "Остановить",
        val urlTestRequest: UrlTestRequest? = null,
    )

    private val notificationManager =
        service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var foregroundStarted = false
    private var lifecycleStatus = "Starting"
    private var presentation = Presentation()
    private var uplink = 0L
    private var downlink = 0L
    private var trafficAvailable = false
    private var latencyChecking = false
    private var latencyActionGeneration = 0L
    private var latencyActionInFlight = false

    fun buildForForeground(status: String): Notification {
        synchronized(this) {
            lifecycleStatus = status
            foregroundStarted = true
            ensureChannel()
            return buildNotification()
        }
    }

    fun updatePresentation(arguments: Map<*, *>): Boolean {
        synchronized(this) {
            fun text(key: String, fallback: String): String =
                arguments[key]?.toString()?.trim()?.take(MAX_TEXT_LENGTH)?.ifEmpty { fallback }
                    ?: fallback

            val detailed = arguments["detailed"] as? Boolean ?: true
            val latency = (arguments["latencyMillis"] as? Number)?.toLong()?.takeIf { it >= 0L }
            presentation = Presentation(
                detailed = detailed,
                title = text("title", ""),
                latencyMillis = latency,
                connectedText = text("connectedText", "VPN подключён"),
                checkingText = text("checkingText", "..."),
                unavailableText = text("unavailableText", "Пинг недоступен"),
                refreshLabel = text("refreshLabel", "Проверить пинг"),
                stopLabel = text("stopLabel", "Остановить"),
                urlTestRequest = UrlTestRequest.fromArguments(arguments),
            )
            if (!latencyChecking) {
                // Flutter delivers the last known successful result on every
                // selected-outbound update. Do not leave an old action result
                // visible after a real selection change.
                latencyActionInFlight = false
            }
            refreshLocked()
        }
        return true
    }

    fun updateTraffic(
        uplink: Long,
        downlink: Long,
        trafficAvailable: Boolean,
    ) {
        synchronized(this) {
            val changed = this.uplink != uplink ||
                this.downlink != downlink ||
                this.trafficAvailable != trafficAvailable
            this.uplink = uplink
            this.downlink = downlink
            this.trafficAvailable = trafficAvailable
            if (changed) {
                refreshLocked()
            }
        }
    }

    fun onUrlTestResult(
        tag: String?,
        delayMillis: Long,
        timeSeconds: Long,
        status: String?,
    ) {
        val normalizedTag = tag?.trim().orEmpty()
        synchronized(this) {
            val request = presentation.urlTestRequest ?: return
            if (!latencyActionInFlight || normalizedTag != request.targetOutboundTag) {
                return
            }
            val actionStartedAtSeconds = latencyActionGeneration
            // Cached group snapshots are often delivered immediately after an
            // Activity reattaches. Do not paint one as the answer to a fresh
            // notification action; the core timestamp must be newer than the
            // tap that started this targeted URLTest.
            if (timeSeconds <= 0L || timeSeconds < actionStartedAtSeconds) {
                return
            }
            latencyActionInFlight = false
            latencyChecking = false
            presentation = presentation.copy(
                latencyMillis = delayMillis.takeIf { it > 0L },
            )
            refreshLocked()
        }
    }

    fun requestLatencyRefresh(): Boolean {
        val request: UrlTestRequest
        val actionGeneration: Long
        synchronized(this) {
            request = presentation.urlTestRequest ?: return false
            if (lifecycleStatus != "Connected" || latencyActionInFlight) {
                return false
            }
            latencyActionInFlight = true
            latencyChecking = true
            actionGeneration = System.currentTimeMillis() / 1_000L
            latencyActionGeneration = actionGeneration
            refreshLocked()
        }
        SingboxController.urlTest(
            groupTag = request.groupTag,
            targetOutboundTag = request.targetOutboundTag,
            priorityOutboundTag = request.priorityOutboundTag,
            excludeOutboundTag = request.excludeOutboundTag,
            url = request.url,
            timeoutMillis = request.timeoutMillis,
            concurrency = request.concurrency,
            deadlineMillis = request.deadlineMillis,
            force = true,
        ) { result ->
            if (result.isFailure) {
                completeLatencyAction(actionGeneration, null)
            }
        }
        mainHandler.postDelayed(
            { completeLatencyAction(actionGeneration, null) },
            max(request.deadlineMillis.toLong(), DEFAULT_LATENCY_TIMEOUT_MS) + 1_000L,
        )
        return true
    }

    private fun completeLatencyAction(
        actionGeneration: Long,
        latencyMillis: Long?,
    ) {
        synchronized(this) {
            if (!latencyActionInFlight || latencyActionGeneration != actionGeneration) {
                return
            }
            latencyActionInFlight = false
            latencyChecking = false
            if (latencyMillis != null) {
                presentation = presentation.copy(latencyMillis = latencyMillis)
            }
            refreshLocked()
        }
    }

    private fun ensureChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Etonify VPN",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "VPN connection status"
            setShowBadge(false)
            setSound(null, null)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun refreshLocked() {
        if (!foregroundStarted) {
            return
        }
        mainHandler.post {
            synchronized(this) {
                if (foregroundStarted) {
                    notificationManager.notify(notificationId, buildNotification())
                }
            }
        }
    }

    private fun buildNotification(): Notification {
        val connected = lifecycleStatus == "Connected"
        val showDetails = connected && presentation.detailed
        val title = if (showDetails && presentation.title.isNotEmpty()) {
            presentation.title
        } else {
            "Etonify"
        }
        val content = when {
            !connected -> lifecycleStatusText(lifecycleStatus)
            !showDetails -> presentation.connectedText
            else -> detailedContent()
        }
        val builder = Notification.Builder(service, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_meow_status)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(contentIntent())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        if (showDetails && presentation.urlTestRequest != null) {
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(service, android.R.drawable.ic_popup_sync),
                    presentation.refreshLabel,
                    serviceIntent(ACTION_REFRESH_LATENCY, ACTION_REFRESH_REQUEST_CODE),
                ).build(),
            )
        }
        builder.addAction(
            Notification.Action.Builder(
                Icon.createWithResource(service, android.R.drawable.ic_menu_close_clear_cancel),
                presentation.stopLabel,
                // The stop path removes the foreground notification only after
                // runtime cleanup is confirmed by MeowBoxService.
                serviceIntent(MeowBoxService.ACTION_STOP, ACTION_STOP_REQUEST_CODE),
            ).build(),
        )
        return builder.build()
    }

    private fun detailedContent(): String {
        val traffic = if (trafficAvailable) {
            "↓ ${formatRate(downlink)}  ↑ ${formatRate(uplink)}"
        } else {
            "↓ —  ↑ —"
        }
        val latency = when {
            latencyChecking -> presentation.checkingText
            presentation.latencyMillis != null -> "${presentation.latencyMillis} мс"
            else -> presentation.unavailableText
        }
        return "$traffic  ·  $latency"
    }

    private fun lifecycleStatusText(status: String): String = when (status) {
        "Starting" -> "Подключение…"
        "Restarting" -> "Перезапуск…"
        "Reloading" -> "Применение настроек…"
        "Waiting for network" -> "Ожидание сети…"
        "Stopping" -> "Отключение…"
        else -> status
    }

    private fun serviceIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(service, service.javaClass).apply {
            this.action = action
            if (action == MeowBoxService.ACTION_STOP) {
                putExtra(MeowBoxService.EXTRA_STOP_REASON, "notification_action")
            }
        }
        return PendingIntent.getService(
            service,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun contentIntent(): PendingIntent {
        val intent = Intent(service, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            service,
            CONTENT_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun formatRate(bytesPerSecond: Long): String {
        if (bytesPerSecond <= 0L) return "0 Б/с"
        val units = arrayOf("Б/с", "КБ/с", "МБ/с", "ГБ/с")
        var value = bytesPerSecond.toDouble()
        var index = 0
        while (value >= 1024.0 && index < units.lastIndex) {
            value /= 1024.0
            index++
        }
        val formatted = if (value >= 100.0 || index == 0) {
            value.toInt().toString()
        } else {
            "%.1f".format(java.util.Locale.US, value)
        }
        return "$formatted ${units[index]}"
    }
}
