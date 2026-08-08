package io.hydrabox.client.singbox

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlin.random.Random

/**
 * Runs the checkbox stage of VK Smart Captcha in an isolated, off-screen
 * WebView. The loopback reverse proxy in HydraCore captures success_token.
 * Slider and kaleidoscope challenges deliberately fall through to the visible
 * browser fallback in Flutter.
 *
 * The click-strategy attribution and GPL-3.0 source link are recorded in the
 * repository's THIRD_PARTY_NOTICES.md.
 */
object HydraBoxVkCaptchaSolver {
    private const val TAG = "HydraBoxVkCaptcha"
    private const val SOLVER_LIFETIME_MS = 11_500L
    private val mainHandler = Handler(Looper.getMainLooper())
    private val captchaUrlPattern = Regex(
        "vk-auth:\\s*solve the captcha to continue:\\s*" +
            "(http://(?:127\\.0\\.0\\.1|localhost):\\d+(?:/\\S*)?)",
        RegexOption.IGNORE_CASE,
    )

    private var generation = 0
    private var currentUrl: String? = null
    private var currentWebView: WebView? = null

    fun maybeStart(context: Context, message: String) {
        val rawUrl = captchaUrlPattern.find(message)?.groupValues?.getOrNull(1) ?: return
        if (!HydraBoxVkCaptchaUrlPolicy.isSafeLoopbackUrl(rawUrl)) return
        mainHandler.post { start(context.applicationContext, rawUrl) }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun start(context: Context, url: String) {
        if (currentUrl == url && currentWebView != null) return
        destroyCurrent()
        val solveGeneration = ++generation
        currentUrl = url

        val viewportWidth = Random.nextInt(356, 369)
        val viewportHeight = Random.nextInt(376, 389)
        val webView = runCatching {
            WebView(context).apply {
                settings.allowContentAccess = false
                settings.allowFileAccess = false
                settings.allowFileAccessFromFileURLs = false
                settings.allowUniversalAccessFromFileURLs = false
                settings.javaScriptCanOpenWindowsAutomatically = false
                settings.setSupportMultipleWindows(false)
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW

                // Smart Captcha requires JavaScript. The only top-level document
                // allowed below is HydraCore's validated loopback challenge URL.
                // codeql[java/android/websettings-javascript-enabled]
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.databaseEnabled = true
                settings.cacheMode = WebSettings.LOAD_NO_CACHE
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
                settings.userAgentString =
                    "Mozilla/5.0 (Linux; Android 15; Mobile) " +
                    "AppleWebKit/537.36 (KHTML, like Gecko) " +
                    "Chrome/146.0.0.0 Mobile Safari/537.36"
                webChromeClient = WebChromeClient()
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        view: WebView,
                        request: WebResourceRequest,
                    ): Boolean = request.isForMainFrame &&
                        !HydraBoxVkCaptchaUrlPolicy.isSafeLoopbackUrl(request.url.toString())

                    @Suppress("DEPRECATION")
                    override fun shouldOverrideUrlLoading(view: WebView, loadedUrl: String): Boolean =
                        !HydraBoxVkCaptchaUrlPolicy.isSafeLoopbackUrl(loadedUrl)

                    override fun onPageFinished(view: WebView, loadedUrl: String?) {
                        super.onPageFinished(view, loadedUrl)
                        mainHandler.postDelayed(
                            { attemptAutoClick(view, solveGeneration, 0) },
                            Random.nextLong(650L, 1_200L),
                        )
                    }
                }
                measure(
                    View.MeasureSpec.makeMeasureSpec(viewportWidth, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(viewportHeight, View.MeasureSpec.EXACTLY),
                )
                layout(0, 0, viewportWidth, viewportHeight)
                onResume()
            }
        }.getOrElse { error ->
            Log.w(TAG, "Unable to create captcha WebView", error)
            currentUrl = null
            return
        }

        currentWebView = webView
        Log.i(TAG, "Starting automatic VK captcha checkbox attempt")
        webView.loadUrl(url)
        mainHandler.postDelayed(
            { if (generation == solveGeneration) destroyCurrent() },
            SOLVER_LIFETIME_MS,
        )
    }

    private fun attemptAutoClick(webView: WebView, solveGeneration: Int, attempt: Int) {
        if (generation != solveGeneration || currentWebView !== webView) return
        val findCheckbox = """
            (function() {
              var slider = document.querySelector(
                '[class*="SliderCaptcha"], [class*="Kaleidoscope"], ' +
                '.vkc__SliderCaptcha-module__description, ' +
                '.vkc__KaleidoscopeScreen-module__captchaId, ' +
                '.vkc__SwipeButton-module__track');
              if (slider) return 'slider';
              var el = document.querySelector('label.vkc__Checkbox-module__Checkbox');
              if (!el) el = document.querySelector('label[for="not-robot-captcha-checkbox"]');
              if (!el) el = document.getElementById('not-robot-captcha-checkbox');
              if (!el) return 'not_found';
              var rect = el.getBoundingClientRect();
              var style = window.getComputedStyle(el);
              if (rect.width < 5 || rect.height < 5 ||
                  style.display === 'none' || style.visibility === 'hidden') return 'not_found';
              return rect.left + ',' + rect.top + ',' + rect.width + ',' + rect.height;
            })();
        """.trimIndent()

        webView.evaluateJavascript(findCheckbox) { rawResult ->
            if (generation != solveGeneration || currentWebView !== webView) return@evaluateJavascript
            val result = rawResult.orEmpty().trim('"')
            if (result == "slider") {
                Log.i(TAG, "VK captcha requires a visible slider fallback")
                destroyCurrent()
                return@evaluateJavascript
            }
            val coordinates = result.split(',').mapNotNull(String::toFloatOrNull)
            if (coordinates.size != 4) {
                if (attempt < 8) {
                    mainHandler.postDelayed(
                        { attemptAutoClick(webView, solveGeneration, attempt + 1) },
                        350L,
                    )
                }
                return@evaluateJavascript
            }
            val left = coordinates[0]
            val top = coordinates[1]
            val width = coordinates[2]
            val height = coordinates[3]
            val cssX = left + width * (0.15f + Random.nextFloat() * 0.7f)
            val cssY = top + height * (0.25f + Random.nextFloat() * 0.5f)
            mainHandler.postDelayed(
                { simulateTouch(webView, solveGeneration, cssX, cssY) },
                Random.nextLong(420L, 680L),
            )
        }
    }

    private fun simulateTouch(
        webView: WebView,
        solveGeneration: Int,
        cssX: Float,
        cssY: Float,
    ) {
        if (generation != solveGeneration || currentWebView !== webView) return
        val density = webView.resources.displayMetrics.density
        val x = cssX * density
        val y = cssY * density
        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(
            downTime,
            downTime,
            MotionEvent.ACTION_DOWN,
            x,
            y,
            0.5f + Random.nextFloat() * 0.4f,
            1f,
            0,
            1f,
            1f,
            0,
            0,
        )
        down.source = InputDevice.SOURCE_TOUCHSCREEN
        webView.dispatchTouchEvent(down)
        down.recycle()

        mainHandler.postDelayed({
            if (generation != solveGeneration || currentWebView !== webView) return@postDelayed
            val up = MotionEvent.obtain(
                downTime,
                SystemClock.uptimeMillis(),
                MotionEvent.ACTION_UP,
                x + Random.nextFloat() * density,
                y + Random.nextFloat() * density,
                0f,
                1f,
                0,
                1f,
                1f,
                0,
                0,
            )
            up.source = InputDevice.SOURCE_TOUCHSCREEN
            webView.dispatchTouchEvent(up)
            up.recycle()
            Log.i(TAG, "Automatic VK captcha checkbox click dispatched")
        }, Random.nextLong(80L, 180L))
    }

    private fun destroyCurrent() {
        generation++
        currentUrl = null
        val webView = currentWebView ?: return
        currentWebView = null
        runCatching {
            webView.stopLoading()
            webView.loadUrl("about:blank")
            webView.webViewClient = WebViewClient()
            webView.webChromeClient = null
            webView.onPause()
            webView.removeAllViews()
            webView.destroy()
        }.onFailure { error -> Log.w(TAG, "Unable to destroy captcha WebView", error) }
    }
}
