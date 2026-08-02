// SPDX-License-Identifier: GPL-3.0-only

package com.etonify.meow_client

import android.annotation.SuppressLint
import android.app.Dialog
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import io.nekohasekai.libbox.Libbox
import org.json.JSONArray
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

internal fun normalizeHydraWdttTurnAddress(raw: String): String? {
    var value = raw.trim().substringBefore('?').trim()
    value = value.replace(Regex("^turns?:", RegexOption.IGNORE_CASE), "")
        .removePrefix("//")
    if (value.isBlank() || value.length > 512 || value.any { it == '\r' || it == '\n' }) {
        return null
    }
    val separator = value.lastIndexOf(':')
    if (separator <= 0 || separator == value.lastIndex) return null
    val port = value.substring(separator + 1).toIntOrNull() ?: return null
    if (port !in 1..65535) return null
    return value
}

internal fun isHydraWdttTrustedVkUrl(raw: String): Boolean {
    val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: return false
    if (!uri.scheme.equals("https", ignoreCase = true)) return false
    val host = uri.host?.lowercase().orEmpty()
    return host == "vk.com" || host.endsWith(".vk.com") ||
        host == "vk.ru" || host.endsWith(".vk.ru")
}

private data class HydraWdttVkBinding(
    val credentialRef: String,
    val hash: String,
)

private data class HydraWdttVkTurnCredentials(
    val username: String,
    val password: String,
    val urls: List<String>,
)

/**
 * Owns VK account fallback for WDTT. TURN secrets stay in native process
 * memory and are passed directly to HydraCore; Flutter receives only success
 * or failure. A headless refresh runs before the VK credentials expire.
 */
internal object HydraWdttVkAuthManager {
    private const val AUTH_TIMEOUT_MS = 5 * 60_000L
    private const val HEADLESS_TIMEOUT_MS = 24_000L
    private const val REFRESH_AFTER_MS = 6 * 60_000L
    private const val ACCOUNT_CREDENTIAL_TTL_SECONDS = 8 * 60L
    private const val NOTIFICATION_CHANNEL = "hydrabox_wdtt_vk_auth"
    private const val NOTIFICATION_ID = 19842
    private val hashPattern = Regex("^[A-Za-z0-9._~:-]{1,256}$")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bindings = linkedMapOf<String, HydraWdttVkBinding>()
    private val refreshTasks = mutableMapOf<String, Runnable>()
    @Volatile
    private var allowedCredentialRefs = emptySet<String>()
    private var foregroundActivity = WeakReference<MainActivity>(null)
    private var pendingInteractive: HydraWdttVkBinding? = null
    private var activeInteractive = false
    private var activeHeadless = false

    fun attach(activity: MainActivity) {
        foregroundActivity = WeakReference(activity)
        val pending = pendingInteractive ?: return
        pendingInteractive = null
        openInteractive(activity, pending, null)
    }

    fun detach(activity: MainActivity) {
        if (foregroundActivity.get() === activity) {
            foregroundActivity.clear()
        }
    }

    fun retainCredentialRefs(refs: Set<String>) {
        allowedCredentialRefs = refs.toSet()
        val removed = bindings.keys.filterNot(refs::contains)
        removed.forEach { ref ->
            bindings.remove(ref)
            refreshTasks.remove(ref)?.let(mainHandler::removeCallbacks)
        }
        pendingInteractive = pendingInteractive?.takeIf {
            refs.contains(it.credentialRef)
        }
        bindings.values.forEach { scheduleRefresh(it, 1_000L) }
    }

    fun authenticate(
        activity: MainActivity,
        credentialRef: String,
        hash: String,
        completion: (Result<Unit>) -> Unit,
    ) {
        val binding = validateBinding(credentialRef, hash)
        if (binding == null || !allowedCredentialRefs.contains(binding.credentialRef)) {
            completion(Result.failure(IllegalArgumentException("Invalid Hydra WDTT VK auth request")))
            return
        }
        mainHandler.post { openInteractive(activity, binding, completion) }
    }

    private fun validateBinding(credentialRef: String, hash: String): HydraWdttVkBinding? {
        val cleanRef = credentialRef.trim()
        val cleanHash = hash.trim()
        val invalidRef = cleanRef.length !in 1..256 || cleanRef.any { character ->
            character.isWhitespace() || character.isISOControl() ||
                character in "|/\\?#@"
        }
        if (invalidRef || !hashPattern.matches(cleanHash)) {
            return null
        }
        return HydraWdttVkBinding(cleanRef, cleanHash)
    }

    private fun openInteractive(
        activity: MainActivity,
        binding: HydraWdttVkBinding,
        completion: ((Result<Unit>) -> Unit)?,
    ) {
        if (activeInteractive) {
            completion?.invoke(Result.failure(IllegalStateException("VK authentication is already active")))
            return
        }
        activeInteractive = true
        createSession(
            context = activity,
            binding = binding,
            visible = true,
        ) { result ->
            activeInteractive = false
            result.onSuccess { remember(binding) }
            completion?.invoke(result)
        }
    }

    private fun remember(binding: HydraWdttVkBinding) {
        if (!allowedCredentialRefs.contains(binding.credentialRef)) return
        bindings[binding.credentialRef] = binding
        pendingInteractive = null
        cancelNotification()
        scheduleRefresh(binding, REFRESH_AFTER_MS)
    }

    private fun scheduleRefresh(binding: HydraWdttVkBinding, delayMs: Long) {
        refreshTasks.remove(binding.credentialRef)?.let(mainHandler::removeCallbacks)
        val task = Runnable { refresh(binding) }
        refreshTasks[binding.credentialRef] = task
        mainHandler.postDelayed(task, delayMs)
    }

    private fun refresh(binding: HydraWdttVkBinding) {
        if (bindings[binding.credentialRef] != binding) return
        if (activeHeadless || activeInteractive) {
            scheduleRefresh(binding, 30_000L)
            return
        }
        activeHeadless = true
        val context: Context = foregroundActivity.get()
            ?: MeowApplication.application.applicationContext
        createSession(context, binding, visible = false) { result ->
            activeHeadless = false
            result.onSuccess {
                remember(binding)
            }.onFailure {
                pendingInteractive = binding
                val activity = foregroundActivity.get()
                if (activity != null) {
                    pendingInteractive = null
                    openInteractive(activity, binding, null)
                } else {
                    showNotification(context)
                }
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createSession(
        context: Context,
        binding: HydraWdttVkBinding,
        visible: Boolean,
        completion: (Result<Unit>) -> Unit,
    ) {
        val finished = AtomicBoolean(false)
        val bridgeNonce = UUID.randomUUID().toString()
        val interceptorScript = INTERCEPT_AND_JOIN_SCRIPT.replace(
            "{{BRIDGE_NONCE}}",
            bridgeNonce,
        )
        var dialog: Dialog? = null
        var webView: WebView? = null
        val timeout = Runnable {
            finishSession(
                finished,
                dialog,
                webView,
                completion,
                Result.failure(IllegalStateException("VK authentication timed out")),
            )
        }
        fun finish(result: Result<Unit>) {
            mainHandler.post {
                mainHandler.removeCallbacks(timeout)
                finishSession(finished, dialog, webView, completion, result)
            }
        }

        try {
            CookieManager.getInstance().apply {
                setAcceptCookie(true)
                flush()
            }
            val view = WebView(context)
            webView = view
            CookieManager.getInstance().setAcceptThirdPartyCookies(view, true)
            view.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                cacheMode = WebSettings.LOAD_DEFAULT
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                allowFileAccess = false
                allowContentAccess = false
                javaScriptCanOpenWindowsAutomatically = false
            }
            view.addJavascriptInterface(object {
                @JavascriptInterface
                fun onTurnServer(nonce: String, payload: String) {
                    if (nonce != bridgeNonce) return
                    val credentials = parseTurnCredentials(payload) ?: return
                    if (!allowedCredentialRefs.contains(binding.credentialRef)) {
                        finish(Result.failure(IllegalStateException("WDTT credential is no longer active")))
                        return
                    }
                    val expiresAt = System.currentTimeMillis() / 1000L +
                        ACCOUNT_CREDENTIAL_TTL_SECONDS
                    val result = runCatching {
                        Libbox.setHydraWDTTVKAccountCredentials(
                            binding.credentialRef,
                            credentials.username,
                            credentials.password,
                            JSONArray(credentials.urls).toString(),
                            expiresAt,
                        )
                    }
                    finish(result)
                }
            }, "HydraBoxWdttVk")
            view.webChromeClient = WebChromeClient()
            view.webViewClient = object : WebViewClient() {
                override fun onPageStarted(
                    view: WebView?,
                    url: String?,
                    favicon: android.graphics.Bitmap?,
                ) {
                    super.onPageStarted(view, url, favicon)
                    if (isHydraWdttTrustedVkUrl(url.orEmpty())) {
                        view?.evaluateJavascript(interceptorScript, null)
                    }
                }

                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?,
                ): Boolean = !isHydraWdttTrustedVkUrl(request?.url?.toString().orEmpty())

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    if (isHydraWdttTrustedVkUrl(url.orEmpty())) {
                        view?.evaluateJavascript(interceptorScript, null)
                    }
                }
            }

            if (visible) {
                val activity = context as? MainActivity
                    ?: throw IllegalStateException("VK login requires a foreground activity")
                dialog = buildDialog(activity, view) {
                    finish(Result.failure(IllegalStateException("VK authentication cancelled")))
                }.also(Dialog::show)
            } else {
                view.alpha = 0.01f
                view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                val host = (context as? MainActivity)
                    ?.findViewById<ViewGroup>(android.R.id.content)
                if (host != null) {
                    host.addView(view, FrameLayout.LayoutParams(1, 1))
                } else {
                    view.measure(
                        View.MeasureSpec.makeMeasureSpec(360, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(640, View.MeasureSpec.EXACTLY),
                    )
                    view.layout(0, 0, 360, 640)
                }
                view.onResume()
            }
            view.loadUrl(
                "https://m.vk.ru/call/join/${Uri.encode(binding.hash)}",
                mapOf("Accept-Language" to "ru,en;q=0.8"),
            )
            mainHandler.postDelayed(
                timeout,
                if (visible) AUTH_TIMEOUT_MS else HEADLESS_TIMEOUT_MS,
            )
        } catch (error: Throwable) {
            finish(Result.failure(error))
        }
    }

    private fun finishSession(
        finished: AtomicBoolean,
        dialog: Dialog?,
        webView: WebView?,
        completion: (Result<Unit>) -> Unit,
        result: Result<Unit>,
    ) {
        if (!finished.compareAndSet(false, true)) return
        runCatching { dialog?.dismiss() }
        runCatching {
            webView?.stopLoading()
            webView?.removeJavascriptInterface("HydraBoxWdttVk")
            (webView?.parent as? ViewGroup)?.removeView(webView)
            webView?.destroy()
        }
        completion(result)
    }

    private fun buildDialog(
        activity: MainActivity,
        webView: WebView,
        onCancel: () -> Unit,
    ): Dialog {
        val title = TextView(activity).apply {
            text = "Вход VK для WDTT"
            textSize = 18f
            setTextColor(Color.WHITE)
            setPadding(24, 20, 16, 16)
        }
        val cancel = Button(activity).apply {
            text = "Отмена"
            setOnClickListener { onCancel() }
        }
        val header = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(Color.rgb(30, 30, 34))
            addView(title, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(cancel, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
        }
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(header)
            addView(webView, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ))
        }
        return Dialog(activity, android.R.style.Theme_DeviceDefault_NoActionBar).apply {
            setContentView(content)
            setCancelable(true)
            setOnCancelListener { onCancel() }
            window?.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
    }

    private fun parseTurnCredentials(payload: String): HydraWdttVkTurnCredentials? {
        if (payload.length !in 2..64_000) return null
        return runCatching {
            val json = JSONObject(payload)
            val username = json.optString("username")
            val password = json.optString("credential")
            if (username.isBlank() || password.isBlank() ||
                username.length > 2048 || password.length > 2048
            ) return null
            val rawUrls = json.optJSONArray("urls") ?: return null
            val urls = buildList {
                for (index in 0 until minOf(rawUrls.length(), 16)) {
                    normalizeHydraWdttTurnAddress(rawUrls.optString(index))?.let(::add)
                }
            }.distinct()
            if (urls.isEmpty()) null else HydraWdttVkTurnCredentials(username, password, urls)
        }.getOrNull()
    }

    @SuppressLint("MissingPermission")
    private fun showNotification(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "WDTT VK authentication",
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        manager.notify(
            NOTIFICATION_ID,
            NotificationCompat.Builder(context, NOTIFICATION_CHANNEL)
                .setSmallIcon(R.drawable.ic_meow_status)
                .setContentTitle("HydraBox: нужен вход VK")
                .setContentText("Откройте HydraBox, чтобы обновить доступ WDTT")
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build(),
        )
    }

    private fun cancelNotification() {
        val context = foregroundActivity.get()?.applicationContext ?: return
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private const val INTERCEPT_AND_JOIN_SCRIPT = """
        (function() {
          if (!window.__hydraboxWdttVkInstalled) {
            window.__hydraboxWdttVkInstalled = true;
            function emit(value) {
              try {
                var data = typeof value === 'string' ? JSON.parse(value) : value;
                var turn = data && (data.turn_server || (data.response && data.response.turn_server));
                if (turn && turn.username && turn.credential && turn.urls) {
                  window.HydraBoxWdttVk.onTurnServer('{{BRIDGE_NONCE}}', JSON.stringify(turn));
                }
              } catch (_) {}
            }
            var originalFetch = window.fetch;
            if (originalFetch) window.fetch = async function() {
              var response = await originalFetch.apply(this, arguments);
              try { emit(await response.clone().text()); } catch (_) {}
              return response;
            };
            var originalSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.send = function() {
              this.addEventListener('load', function() { emit(this.responseText); });
              return originalSend.apply(this, arguments);
            };
          }
          function clickJoin() {
            var nodes = document.querySelectorAll('button,a,[role="button"],input[type="button"],input[type="submit"]');
            for (var i = 0; i < nodes.length; i++) {
              var text = (nodes[i].innerText || nodes[i].textContent || nodes[i].value || '').trim().toLowerCase();
              if (text === 'присоединиться' || text === 'join' ||
                  text === 'продолжить в браузере' || text === 'continue in browser') {
                try { nodes[i].click(); } catch (_) {}
                return;
              }
            }
          }
          clickJoin();
          if (!window.__hydraboxWdttVkJoinTimer) {
            window.__hydraboxWdttVkJoinTimer = setInterval(clickJoin, 1000);
            setTimeout(function() { clearInterval(window.__hydraboxWdttVkJoinTimer); }, 45000);
          }
        })();
    """
}
