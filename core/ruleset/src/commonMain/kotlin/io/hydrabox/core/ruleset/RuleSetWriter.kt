package io.hydrabox.core.ruleset

/**
 * Writes a sing-box binary rule-set (`.srs`).
 *
 * HydraBox 1.x compiled these itself rather than shipping them
 * (`lib/data/adblock/ad_block_rule_set_service.dart`), and it has to stay that way: the
 * source lists are hosts files of a few hundred thousand domains, and the core will only
 * load the binary form. The format is the one sing-box reads: the magic `SRS`, format
 * version 2, then a zlib-compressed body holding one default rule whose only item is a
 * domain matcher — a succinct trie over the reversed domains.
 *
 * The encoding is byte-for-byte the same as 1.x's, which is what lets a rule set compiled by
 * either version load in either.
 */
object RuleSetWriter {
    /** The compression step, which every platform already has and no platform shares. */
    fun write(
        domains: Collection<String>,
        compress: (ByteArray) -> ByteArray,
    ): ByteArray {
        val body = ByteAccumulator()
        body.uvarint(if (domains.isEmpty()) 0 else 1)
        if (domains.isNotEmpty()) defaultDomainRule(body, domains)
        val out = ByteAccumulator()
        out.bytes(MAGIC)
        out.byte(FORMAT_VERSION)
        out.bytes(compress(body.toByteArray()))
        return out.toByteArray()
    }

    /**
     * The IP form of [write]: one default rule whose only item is an IP-CIDR set, which is what a
     * geoip rule set is. The core reads it exactly as `common/srs/ip_set.go` writes it — an IP set
     * is a version byte, a big-endian uint64 range count, then each range as two length-prefixed
     * addresses (from, to). A `10.0.0.0/24` is the range `10.0.0.0`..`10.0.0.255`.
     *
     * IPv6 (`128`-bit, 16-byte) CIDRs are accepted too; anything unparseable is skipped rather
     * than guessed, the same discipline [AdBlockFilter] applies to domains.
     */
    fun writeIp(
        cidrs: Collection<String>,
        compress: (ByteArray) -> ByteArray,
    ): ByteArray {
        val ranges =
            cidrs
                .asSequence()
                .mapNotNull(::cidrToRange)
                .sortedWith(compareBy({ it.from.size }, { bytesUnsigned(it.from) }))
                .toList()
        val body = ByteAccumulator()
        body.uvarint(if (ranges.isEmpty()) 0 else 1)
        if (ranges.isNotEmpty()) defaultIpRule(body, ranges)
        val out = ByteAccumulator()
        out.bytes(MAGIC)
        out.byte(FORMAT_VERSION)
        out.bytes(compress(body.toByteArray()))
        return out.toByteArray()
    }

    private fun defaultDomainRule(
        writer: ByteAccumulator,
        domains: Collection<String>,
    ) {
        writer.byte(0)
        writer.byte(RULE_ITEM_DOMAIN)
        succinctSet(prepare(domains)).writeTo(writer)
        writer.byte(RULE_ITEM_FINAL)
        writer.byte(0)
    }

    class IpRange(
        val from: ByteArray,
        val to: ByteArray,
    )

    private fun defaultIpRule(
        writer: ByteAccumulator,
        ranges: List<IpRange>,
    ) {
        writer.byte(0)
        writer.byte(RULE_ITEM_IP_CIDR)
        // The IP set, byte for byte as common/srs/ip_set.go reads it.
        writer.byte(1)
        writer.uint64Be(ranges.size.toLong())
        ranges.forEach { range ->
            writer.byteList(range.from)
            writer.byteList(range.to)
        }
        writer.byte(RULE_ITEM_FINAL)
        writer.byte(0)
    }

    /**
     * A CIDR to the first and last address it covers. The mask is applied to get the network
     * address (from) and its complement OR-ed in to get the broadcast (to), so the range is
     * inclusive on both ends — what the core stores. Only well-formed IPv4/IPv6 with an in-range
     * prefix is accepted; everything else returns null and is dropped.
     */
    internal fun cidrToRange(cidr: String): IpRange? {
        val trimmed = cidr.trim()
        if (trimmed.isEmpty()) return null
        val slash = trimmed.indexOf('/')
        if (slash <= 0 || slash == trimmed.length - 1) return null
        val addr = parseAddr(trimmed.substring(0, slash)) ?: return null
        val prefix = trimmed.substring(slash + 1).toIntOrNull() ?: return null
        val bits = addr.size * 8
        if (prefix < 0 || prefix > bits) return null
        val from = addr.copyOf()
        val to = addr.copyOf()
        for (i in 0 until bits) {
            val byteIndex = i / 8
            val bitMask = 1 shl (7 - (i % 8))
            if (i < prefix) continue
            from[byteIndex] = (from[byteIndex].toInt() and bitMask.inv()).toByte()
            to[byteIndex] = (to[byteIndex].toInt() or bitMask).toByte()
        }
        return IpRange(from, to)
    }

    /** IPv4 dotted quad or a bounded IPv6; null on anything else. */
    private fun parseAddr(text: String): ByteArray? {
        if (text.contains(':')) return parseIpv6(text)
        val parts = text.split('.')
        if (parts.size != 4) return null
        val out = ByteArray(4)
        for (i in 0 until 4) {
            val value = parts[i].toIntOrNull() ?: return null
            if (value < 0 || value > 255) return null
            out[i] = value.toByte()
        }
        return out
    }

    private fun parseIpv6(text: String): ByteArray? {
        val halves = text.split("::", limit = 2)

        fun groups(part: String): List<Int>? {
            if (part.isEmpty()) return emptyList()
            return part.split(':').map { g ->
                if (g.isEmpty() || g.length > 4) return null
                g.toIntOrNull(16) ?: return null
            }
        }
        val out = ByteArray(16)
        val head: List<Int>
        val tail: List<Int>
        if (halves.size == 2) {
            head = groups(halves[0]) ?: return null
            tail = groups(halves[1]) ?: return null
        } else {
            head = groups(text) ?: return null
            tail = emptyList()
            if (head.size != 8) return null
        }
        if (head.size + tail.size > 8) return null
        var idx = 0
        head.forEach { g ->
            out[idx++] = (g ushr 8).toByte()
            out[idx++] = g.toByte()
        }
        idx = 16 - tail.size * 2
        tail.forEach { g ->
            out[idx++] = (g ushr 8).toByte()
            out[idx++] = g.toByte()
        }
        return out
    }

    private fun bytesUnsigned(bytes: ByteArray): Long {
        var acc = 0L
        bytes.take(8).forEach { acc = (acc shl 8) or (it.toLong() and 0xFF) }
        return acc
    }

    /**
     * Domains go in reversed and prefixed with a root marker, so that a suffix match becomes
     * a prefix match in the trie — `example.com` matching `ads.example.com`.
     */
    private fun prepare(domains: Collection<String>): List<String> =
        domains
            .asSequence()
            .filter(String::isNotEmpty)
            .distinct()
            .map { domain -> (ROOT_LABEL_MARKER + domain).reversed() }
            .sorted()
            .toList()

    private class QueueEntry(
        val start: Int,
        val end: Int,
        val column: Int,
    )

    private class SuccinctSet(
        val leaves: List<Long>,
        val labelBitmap: List<Long>,
        val labels: ByteArray,
    ) {
        fun writeTo(writer: ByteAccumulator) {
            writer.byte(0)
            writer.uint64List(leaves)
            writer.uint64List(labelBitmap)
            writer.byteList(labels)
        }
    }

    /** The trie, as sing-box stores it: one bit per leaf, one bit per label boundary. */
    private fun succinctSet(keys: List<String>): SuccinctSet {
        val leaves = mutableListOf<Long>()
        val labelBitmap = mutableListOf<Long>()
        val labels = mutableListOf<Byte>()
        var labelIndex = 0
        val queue = mutableListOf(QueueEntry(0, keys.size, 0))
        var index = 0
        while (index < queue.size) {
            val entry = queue[index]
            index += 1
            if (entry.start >= entry.end) continue
            var start = entry.start
            if (entry.column == keys[start].length) {
                start += 1
                setBit(leaves, index - 1)
            }
            var cursor = start
            while (cursor < entry.end) {
                val from = cursor
                val current = keys[from][entry.column]
                while (cursor < entry.end && keys[cursor][entry.column] == current) cursor += 1
                queue += QueueEntry(from, cursor, entry.column + 1)
                labels += current.code.toByte()
                labelIndex += 1
            }
            setBit(labelBitmap, labelIndex)
            labelIndex += 1
        }
        return SuccinctSet(leaves, labelBitmap, labels.toByteArray())
    }

    private fun setBit(
        bitmap: MutableList<Long>,
        index: Int,
    ) {
        val word = index ushr 6
        while (bitmap.size <= word) bitmap += 0L
        bitmap[word] = bitmap[word] or (1L shl (index and 63))
    }

    private val MAGIC = byteArrayOf(0x53, 0x52, 0x53)
    private const val FORMAT_VERSION = 2
    private const val RULE_ITEM_DOMAIN = 2
    private const val RULE_ITEM_IP_CIDR = 6
    private const val RULE_ITEM_FINAL = 0xFF
    private const val ROOT_LABEL_MARKER = "\n"
}

internal class ByteAccumulator {
    private val buffer = mutableListOf<Byte>()

    fun byte(value: Int) {
        buffer += (value and 0xFF).toByte()
    }

    fun bytes(values: ByteArray) {
        values.forEach { buffer += it }
    }

    fun uvarint(value: Int) {
        var current = value
        while (current >= 0x80) {
            byte((current and 0xFF) or 0x80)
            current = current shr 7
        }
        byte(current and 0xFF)
    }

    /** A fixed-width big-endian uint64, as sing-box writes an IP-set range count. */
    fun uint64Be(value: Long) {
        for (shift in 56 downTo 0 step 8) byte(((value ushr shift) and 0xFF).toInt())
    }

    fun uint64List(values: List<Long>) {
        uvarint(values.size)
        values.forEach { value ->
            for (shift in 56 downTo 0 step 8) byte(((value ushr shift) and 0xFF).toInt())
        }
    }

    fun byteList(values: ByteArray) {
        uvarint(values.size)
        bytes(values)
    }

    fun toByteArray(): ByteArray = buffer.toByteArray()
}
