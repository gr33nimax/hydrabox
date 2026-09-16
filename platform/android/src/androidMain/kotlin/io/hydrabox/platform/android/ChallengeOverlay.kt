package io.hydrabox.platform.android

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Color
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.hydrabox.core.contract.TransportChallenge
import kotlinx.coroutines.delay
import java.net.URI

private const val AREA = "challenge"

/** How long the page is given before the screen admits that it is not coming. */
private const val LOAD_TIMEOUT_MILLIS = 25_000L

/** VK's own hosts: the captcha may legitimately send the user to one of them. */
private val VK_HOSTS = setOf("vk.com", "vk.ru", "ok.ru", "okcdn.ru")

/**
 * One question, and nothing of the previous one.
 *
 * A challenge is a session with an identity, a deadline and an owner — not a picture. Keying the
 * screen by that identity is what stops a new question from opening with the attempt counter and
 * the failure message of the one before it.
 */
@Composable
fun ChallengeOverlay(
    challenge: TransportChallenge,
    onDismiss: () -> Unit,
) {
    key(challenge.id) {
        ChallengeOverlayContent(challenge, onDismiss)
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun ChallengeOverlayContent(
    challenge: TransportChallenge,
    onDismiss: () -> Unit,
) {
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var expired by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }
    val allowedOrigin = remember(challenge.url) { originOf(challenge.url) }

    LaunchedEffect(attempt, loading) {
        if (!loading) return@LaunchedEffect
        delay(LOAD_TIMEOUT_MILLIS)
        if (loading) {
            loading = false
            failure = "нет ответа за ${LOAD_TIMEOUT_MILLIS / 1000} с"
            HydraLog.warn(AREA, "the captcha page did not finish loading in time")
        }
    }

    // The core hands out a deadline with the question. Ignoring it left a screen that could sit
    // there after the core had stopped waiting for it.
    val expiresAt = challenge.expiresAtMillis
    if (expiresAt > 0) {
        LaunchedEffect(expiresAt) {
            val remaining = expiresAt - System.currentTimeMillis()
            if (remaining > 0) delay(remaining)
            loading = false
            expired = true
            failure = "время на подтверждение истекло"
            HydraLog.warn(AREA, "the challenge expired before it was answered")
        }
    }

    Column(
        modifier =
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.surface)
                // The runtime screen is edge-to-edge: without this the header and "close" hide
                // under the status bar, and the keyboard covers the bottom of the question.
                .safeDrawingPadding()
                .imePadding(),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                stringResource(R.string.captcha_title),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.captcha_close))
            }
        }
        if (loading) {
            Text(
                stringResource(R.string.captcha_loading),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
        val reason = failure
        if (reason != null) {
            Column(
                modifier = Modifier.fillMaxSize().padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    stringResource(R.string.captcha_failed),
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(reason, style = MaterialTheme.typography.bodySmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // Retrying an expired question would only reload a page the core no longer
                    // serves: once the deadline has passed, closing is the honest action.
                    if (!expired) {
                        TextButton(
                            onClick = {
                                failure = null
                                loading = true
                                attempt += 1
                            },
                        ) {
                            Text(stringResource(R.string.captcha_retry))
                        }
                    }
                    TextButton(onClick = onDismiss) {
                        Text(stringResource(R.string.captcha_close))
                    }
                }
            }
            return@Column
        }
        key(attempt) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { context ->
                    WebView(context).apply {
                        // The page is VK's captcha, proxied through the core; its own scripts are
                        // what submit the answer and report the token back. A transparent
                        // background keeps the theme's surface visible instead of a white flash
                        // while the page paints.
                        setBackgroundColor(Color.TRANSPARENT)
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.useWideViewPort = true
                        settings.loadWithOverviewMode = true
                        settings.builtInZoomControls = true
                        settings.displayZoomControls = false
                        settings.mediaPlaybackRequiresUserGesture = false
                        webViewClient =
                            object : WebViewClient() {
                                override fun shouldOverrideUrlLoading(
                                    view: WebView?,
                                    request: WebResourceRequest?,
                                ): Boolean {
                                    val target = request?.url?.toString() ?: return false
                                    if (isAllowedNavigation(target, allowedOrigin)) return false
                                    // A help or privacy link would replace the question with a page
                                    // that has no way back to it.
                                    HydraLog.warn(AREA, "the captcha page tried to open $target")
                                    return true
                                }

                                override fun onPageStarted(
                                    view: WebView?,
                                    url: String?,
                                    favicon: Bitmap?,
                                ) {
                                    loading = true
                                    HydraLog.debug(AREA, "the captcha page started loading")
                                }

                                override fun onPageFinished(
                                    view: WebView?,
                                    url: String?,
                                ) {
                                    loading = false
                                    HydraLog.info(AREA, "the captcha page finished loading")
                                }

                                override fun onReceivedError(
                                    view: WebView?,
                                    request: WebResourceRequest?,
                                    error: WebResourceError?,
                                ) {
                                    // Only the page itself: every asset that fails would otherwise
                                    // replace the one message that explains the screen.
                                    if (request?.isForMainFrame == false) return
                                    loading = false
                                    failure = error?.description?.toString() ?: "страница не открылась"
                                    HydraLog.warn(AREA, "the captcha page could not be loaded: $failure")
                                }

                                override fun onReceivedHttpError(
                                    view: WebView?,
                                    request: WebResourceRequest?,
                                    response: WebResourceResponse?,
                                ) {
                                    if (request?.isForMainFrame == false) return
                                    loading = false
                                    failure = "HTTP ${response?.statusCode}"
                                    HydraLog.warn(AREA, "the captcha page answered $failure")
                                }
                            }
                        if (challenge.url.isNotEmpty()) loadUrl(challenge.url)
                    }
                },
                // Nothing may keep loading, scripting or holding the page once the question is
                // gone: without this the old page outlived its overlay.
                onRelease = { view ->
                    view.stopLoading()
                    view.webViewClient = WebViewClient()
                    view.loadUrl("about:blank")
                    view.removeAllViews()
                    view.destroy()
                },
                // A new question in the same overlay: the core mints a new challenge identity and
                // serves a new page, so pointing the view at it is the whole of the update.
                update = { view ->
                    if (challenge.url.isNotEmpty() && view.url != challenge.url) view.loadUrl(challenge.url)
                },
            )
        }
    }
}

/** The origin of the page the core serves, which is the only non-HTTPS address allowed here. */
private fun originOf(url: String): String =
    runCatching {
        val uri = URI(url)
        val port = if (uri.port >= 0) ":${uri.port}" else ""
        "${uri.scheme}://${uri.host}$port"
    }.getOrDefault("")

/**
 * Whether a navigation may leave the served page.
 *
 * The captcha is one page on loopback: its own origin, and VK's hosts if the question itself sends
 * the user there. Everything else is a detour out of a screen whose only way back is the page it
 * left.
 */
private fun isAllowedNavigation(
    url: String,
    allowedOrigin: String,
): Boolean {
    if (allowedOrigin.isNotEmpty() && url.startsWith(allowedOrigin)) return true
    val uri = runCatching { URI(url) }.getOrNull() ?: return false
    if (!uri.scheme.equals("https", ignoreCase = true)) return false
    val host = uri.host?.lowercase()?.trimEnd('.') ?: return false
    return VK_HOSTS.any { host == it || host.endsWith(".$it") }
}
