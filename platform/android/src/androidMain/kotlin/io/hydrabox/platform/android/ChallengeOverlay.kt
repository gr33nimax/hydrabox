package io.hydrabox.platform.android

import android.annotation.SuppressLint
import android.graphics.Bitmap
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
import androidx.compose.foundation.layout.padding
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

private const val AREA = "challenge"

/** How long the page is given before the screen admits that it is not coming. */
private const val LOAD_TIMEOUT_MILLIS = 25_000L

/**
 * The core's own page, inside the application.
 *
 * The captcha is served by the core on a loopback port, rewritten so that it answers there, and
 * the page hands the token back to the core by itself once it is solved. A browser tab would
 * leave the application and could not be taken down when the question is gone; here it is one
 * overlay that disappears the moment the core says there is nothing left to answer — and
 * "close" tells the core so, instead of leaving it to wait out its window for nobody.
 *
 * The page is relayed through the tunnel that is being negotiated, so it can be slow or it can
 * be refused, and a WebView left to itself reports neither: no callback fires, the view stays
 * white, and the screen is a header over nothing — which is how this arrived once, with no way
 * to tell a slow page from a dead one.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun ChallengeOverlay(
    challenge: TransportChallenge,
    onDismiss: () -> Unit,
) {
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableStateOf(0) }

    LaunchedEffect(attempt, loading) {
        if (!loading) return@LaunchedEffect
        delay(LOAD_TIMEOUT_MILLIS)
        if (loading) {
            loading = false
            failure = "нет ответа за ${LOAD_TIMEOUT_MILLIS / 1000} с"
            HydraLog.warn(AREA, "the captcha page did not finish loading in time")
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface),
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
                    TextButton(
                        onClick = {
                            failure = null
                            loading = true
                            attempt += 1
                        },
                    ) {
                        Text(stringResource(R.string.captcha_retry))
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
                        // what submit the answer and report the token back.
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        webViewClient =
                            object : WebViewClient() {
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
                // A new question in the same overlay: the core mints a new challenge identity and
                // serves a new page, so pointing the view at it is the whole of the update.
                update = { view ->
                    if (challenge.url.isNotEmpty() && view.url != challenge.url) view.loadUrl(challenge.url)
                },
            )
        }
    }
}
