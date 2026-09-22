package io.hydrabox.platform.android

import android.content.Context
import android.util.AtomicFile
import io.hydrabox.core.ruleset.RuleSetWriter
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.Deflater
import java.util.zip.GZIPInputStream

/**
 * Downloads the Russian IP allocation and compiles it into one geoip rule set the core loads to
 * route Russian destinations straight out instead of through the tunnel.
 *
 * Unlike [AdBlockRuleSets] this is a single file, so it needs no generation/lease dance: an
 * `AtomicFile` replace is atomic at the filesystem level, and a core that already opened the old
 * file keeps reading it through its open handle until it reloads and re-reads the path. The
 * domain half of Russia-direct is not here at all — it is `.ru`/`.рф`/`.su` suffixes emitted
 * inline in the route, which need no download.
 *
 * The source is a country IP allocation (real Russian networks), not a block list: a block list
 * would send exactly the wrong traffic direct. See docs/decision in the spec.
 */
object RussiaRuleSets {
    private const val SOURCE_URL =
        "https://raw.githubusercontent.com/ipverse/rir-ip/master/country/ru/ipv4-aggregated.txt"
    private const val MAX_SOURCE_BYTES = 16 * 1024 * 1024
    private const val TIMEOUT_MILLIS = 30_000
    private const val DIRECTORY = "rulesets"
    private const val GEOIP_FILE = "russia_geoip.srs"
    private const val METADATA_FILE = "russia_geoip.meta"

    data class Status(
        val available: Boolean,
        val networks: Int = 0,
        val updatedAtMillis: Long? = null,
        val bytes: Long = 0,
    ) {
        companion object {
            val Unavailable = Status(available = false)
        }
    }

    fun geoipPath(context: Context): String? {
        val file = File(directory(context), GEOIP_FILE)
        return file.takeIf(File::isFile)?.absolutePath
    }

    fun status(context: Context): Status {
        val root = directory(context)
        val geoip = File(root, GEOIP_FILE)
        val metadata = File(root, METADATA_FILE)
        if (!geoip.isFile) return Status.Unavailable
        val fields =
            runCatching {
                metadata
                    .readText()
                    .lineSequence()
                    .mapNotNull { line ->
                        val name = line.substringBefore('=', "")
                        val value = line.substringAfter('=', "")
                        if (name.isEmpty()) null else name to value
                    }.toMap()
            }.getOrDefault(emptyMap())
        return Status(
            available = true,
            networks = fields["networks"]?.toIntOrNull() ?: 0,
            updatedAtMillis = fields["updated"]?.toLongOrNull(),
            bytes = geoip.length(),
        )
    }

    /** Blocking; the caller runs on a background thread, same contract as [AdBlockRuleSets.update]. */
    @Synchronized
    fun update(context: Context): Status {
        val source = download()
        val cidrs = parseCidrs(source)
        check(cidrs.isNotEmpty()) { "the Russian IP list contained no usable network" }
        val geoip = RuleSetWriter.writeIp(cidrs, ::deflate)
        val root = directory(context).apply { mkdirs() }
        writeAtomic(File(root, GEOIP_FILE), geoip)
        writeAtomic(
            File(root, METADATA_FILE),
            buildString {
                appendLine("networks=${cidrs.size}")
                appendLine("updated=${System.currentTimeMillis()}")
                appendLine("source=${source.length}")
            }.encodeToByteArray(),
        )
        return status(context)
    }

    fun clear(context: Context) {
        val root = directory(context)
        AtomicFile(File(root, GEOIP_FILE)).delete()
        AtomicFile(File(root, METADATA_FILE)).delete()
    }

    /** One CIDR per line; `#` comments and blank lines are skipped, malformed lines dropped later. */
    internal fun parseCidrs(source: String): List<String> =
        source
            .lineSequence()
            .map { it.substringBefore('#').trim() }
            .filter { it.isNotEmpty() && it.contains('/') }
            .toList()

    private fun directory(context: Context) = File(context.filesDir, DIRECTORY)

    private fun writeAtomic(
        target: File,
        bytes: ByteArray,
    ) {
        AtomicFile(target).run {
            val output = startWrite()
            try {
                output.write(bytes)
                finishWrite(output)
            } catch (failure: Throwable) {
                failWrite(output)
                throw failure
            }
        }
    }

    private fun download(): String {
        val connection =
            (URL(SOURCE_URL).openConnection() as HttpURLConnection).apply {
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
                requestMethod = "GET"
                setRequestProperty("User-Agent", "HydraBox/2")
                setRequestProperty("Accept-Encoding", "gzip")
            }
        try {
            check(connection.responseCode == HttpURLConnection.HTTP_OK) {
                "the Russian IP list answered with HTTP ${connection.responseCode}"
            }
            val stream =
                connection.inputStream.let {
                    if (connection.contentEncoding.equals("gzip", ignoreCase = true)) GZIPInputStream(it) else it
                }
            val buffer = ByteArrayOutputStream()
            stream.use { input ->
                val chunk = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(chunk)
                    if (read <= 0) break
                    check(buffer.size() + read <= MAX_SOURCE_BYTES) { "the Russian IP list exceeds 16 MiB" }
                    buffer.write(chunk, 0, read)
                }
            }
            return buffer.toByteArray().decodeToString()
        } catch (error: IOException) {
            throw IllegalStateException("could not download the Russian IP list", error)
        } finally {
            connection.disconnect()
        }
    }

    private fun deflate(bytes: ByteArray): ByteArray {
        val deflater = Deflater(Deflater.BEST_COMPRESSION)
        return try {
            deflater.setInput(bytes)
            deflater.finish()
            val out = ByteArrayOutputStream(bytes.size / 2)
            val chunk = ByteArray(64 * 1024)
            while (!deflater.finished()) {
                val written = deflater.deflate(chunk)
                out.write(chunk, 0, written)
            }
            out.toByteArray()
        } finally {
            deflater.end()
        }
    }
}
