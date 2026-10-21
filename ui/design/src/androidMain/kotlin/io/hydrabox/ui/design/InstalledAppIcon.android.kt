package io.hydrabox.ui.design

import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

private val appIconCache = object : LruCache<String, Bitmap>(4 * 1024 * 1024) {
    override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
}

@Composable
actual fun InstalledAppIcon(packageName: String, modifier: Modifier) {
    val context = LocalContext.current.applicationContext
    val size = (40 * LocalDensity.current.density).roundToInt().coerceAtLeast(1)
    val configuration = LocalConfiguration.current.hashCode()
    val key = "$packageName:$size:$configuration"
    val bitmap by produceState<Bitmap?>(appIconCache.get(key), key) {
        value = withContext(Dispatchers.IO) {
            appIconCache.get(key) ?: runCatching {
                val drawable = context.packageManager.getApplicationIcon(packageName)
                Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { rendered ->
                    drawable.setBounds(0, 0, size, size)
                    drawable.draw(Canvas(rendered))
                    appIconCache.put(key, rendered)
                }
            }.getOrNull()
        }
    }
    val image = remember(bitmap) { bitmap?.asImageBitmap() }
    if (image != null) {
        Image(image, contentDescription = null, modifier = modifier)
    } else {
        Icon(HydraIcons.Apps, contentDescription = null, modifier = modifier)
    }
}
