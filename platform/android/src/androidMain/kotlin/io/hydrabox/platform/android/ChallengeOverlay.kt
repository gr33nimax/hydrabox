package io.hydrabox.platform.android

import android.annotation.SuppressLint
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.hydrabox.core.contract.TransportChallenge

/**
 * The core's own page, inside the application.
 *
 * The captcha is served by the core on a loopback port, rewritten so that it answers there, and
 * the page hands the token back to the core by itself once it is solved. A browser tab would
 * leave the application and could not be taken down when the question is gone; here it is one
 * overlay that disappears the moment the core says there is nothing left to answer — and
 * "close" tells the core so, instead of leaving it to wait out its window for nobody.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun ChallengeOverlay(challenge: TransportChallenge, onDismiss: () -> Unit) {
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
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                WebView(context).apply {
                    // The page is VK's captcha, proxied through the core; its own scripts are
                    // what submit the answer and report the token back.
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    webViewClient = WebViewClient()
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
