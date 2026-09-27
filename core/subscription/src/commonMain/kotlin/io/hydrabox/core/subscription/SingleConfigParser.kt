package io.hydrabox.core.subscription

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/** Parses one or more explicitly supplied configs without treating a subscription as a config. */
object SingleConfigParser {
    private val json =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
        }
    private val metaTypes = setOf("direct", "block", "dns", "selector", "urltest")
    private val endpointTypes = setOf("wireguard", "tailscale")

    fun parse(
        input: String,
        name: String? = null,
    ): List<CatalogOutbound> {
        val body = input.trim()
        require(body.isNotEmpty()) { "empty config" }
        require(!body.startsWith("http://", true) && !body.startsWith("https://", true)) {
            "this is a subscription URL; use subscription import instead"
        }
        return parseBody(body, name?.trim()?.takeIf(String::isNotEmpty), allowBase64 = true)
    }

    fun isSubscriptionDocument(input: String): Boolean {
        val body = input.trim()
        if (body.isEmpty()) return false
        if (looksLikeSubscriptionDocument(body)) return true
        return OutboundCatalogParser.expandBase64(body)?.let(::looksLikeSubscriptionDocument) == true
    }

    private fun looksLikeSubscriptionDocument(body: String): Boolean {
        val root = runCatching { parseJson(body) }.getOrNull() as? JsonObject
        if (root?.get("type") != null) return false
        if (root != null && isSubscriptionDocument(root)) return true
        return recognizedSubscription(body)?.format?.let { it != SubscriptionDocumentFormat.UNKNOWN } == true
    }

    private fun parseBody(
        body: String,
        name: String?,
        allowBase64: Boolean,
    ): List<CatalogOutbound> {
        val shareLinks =
            body
                .lineSequence()
                .map(String::trim)
                .filter { it.isNotEmpty() && !it.startsWith("#") }
                .toList()
        if (shareLinks.size > 1 && shareLinks.all { it.contains("://") }) return parseShareLinks(shareLinks)

        if (body.startsWith("[Interface]", ignoreCase = true) ||
            (body.contains("://") && !body.startsWith("{") && !body.startsWith("["))
        ) {
            val link =
                runCatching { SubscriptionParser.parse(body) }.getOrElse { failure ->
                    recognizedSubscription(body)?.let { subscriptionError() }
                    throw IllegalArgumentException("invalid single share link: ${failure.message ?: "unsupported format"}", failure)
                }
            val tag = name ?: link.name.trim().takeIf(String::isNotEmpty) ?: "${link.server}-${link.port}"
            return listOf(
                CatalogOutbound(
                    tag = tag,
                    type = ShareLinkOutbound.typeOf(link),
                    json = ShareLinkOutbound.toJson(link, tag),
                    endpoint = ShareLinkOutbound.isEndpoint(link),
                    label = name,
                ),
            )
        }

        val element = parseJson(body)
        if (element != null) {
            when (element) {
                is JsonObject -> {
                    if (element["type"] != null) return parseOutbounds(listOf(element), name)
                    if (isSubscriptionDocument(element)) subscriptionError()
                    recognizedSubscription(body)?.let { subscriptionError() }
                    throw IllegalArgumentException("expected a sing-box outbound object with a type")
                }

                is JsonArray -> {
                    val outbounds = element.filterIsInstance<JsonObject>()
                    if (outbounds.isNotEmpty() && outbounds.size == element.size && outbounds.all { it["type"] != null }) {
                        return parseOutbounds(outbounds, name)
                    }
                    recognizedSubscription(body)?.let { subscriptionError() }
                    throw IllegalArgumentException("expected an array of sing-box outbound objects")
                }

                else -> {
                    throw IllegalArgumentException("expected a share link or sing-box outbound JSON")
                }
            }
        }

        if (allowBase64) {
            OutboundCatalogParser.expandBase64(body)?.let { decoded ->
                return parseBody(decoded.trim(), name, allowBase64 = false)
            }
            recognizedSubscription(body)?.let { subscriptionError() }
        }
        throw IllegalArgumentException("unrecognized config; expected one share link, outbound JSON, or Base64")
    }

    private fun parseShareLinks(links: List<String>): List<CatalogOutbound> {
        val taken = mutableSetOf<String>()
        return links.mapIndexed { index, value ->
            val link =
                runCatching { SubscriptionParser.parse(value) }
                    .getOrElse { failure -> throw IllegalArgumentException("invalid share link on line ${index + 1}", failure) }
            val preferred = link.name.trim().takeIf(String::isNotEmpty) ?: "${link.server}-${link.port}"
            val tag =
                generateSequence(0) { it + 1 }
                    .map { suffix -> if (suffix == 0) preferred else "$preferred ($suffix)" }
                    .first(taken::add)
            CatalogOutbound(
                tag = tag,
                type = ShareLinkOutbound.typeOf(link),
                json = ShareLinkOutbound.toJson(link, tag),
                endpoint = ShareLinkOutbound.isEndpoint(link),
            )
        }
    }

    private fun parseOutbounds(
        items: List<JsonObject>,
        name: String?,
    ): List<CatalogOutbound> {
        require(items.isNotEmpty()) { "config contains no outbounds" }
        val taken = mutableSetOf<String>()
        val normalized =
            items.mapIndexed { index, item ->
                val type =
                    item["type"]?.jsonPrimitive?.contentOrNull?.takeIf(String::isNotBlank)
                        ?: throw IllegalArgumentException("outbound ${index + 1} has no type")
                val originalTag = item["tag"]?.jsonPrimitive?.contentOrNull?.takeIf(String::isNotBlank)
                val tag =
                    when {
                        items.size == 1 && name != null -> name
                        originalTag != null -> originalTag
                        else -> generatedTag(item, type, index)
                    }
                require(taken.add(tag)) { "duplicate outbound tag: $tag" }
                val outbound =
                    if (item["tag"]?.jsonPrimitive?.contentOrNull == tag) {
                        item
                    } else {
                        buildJsonObject {
                            item.forEach { (key, value) -> if (key != "tag") put(key, value) }
                            put("tag", JsonPrimitive(tag))
                        }
                    }
                CatalogOutbound(
                    tag = tag,
                    type = type,
                    json = outbound,
                    selectable = type.lowercase() !in metaTypes,
                    endpoint = type.lowercase() in endpointTypes,
                    label = name.takeIf { items.size == 1 },
                )
            }
        require(normalized.any(CatalogOutbound::selectable)) { "config contains no selectable outbound" }

        val document =
            buildJsonObject {
                putJsonArray("outbounds") {
                    normalized.filterNot(CatalogOutbound::endpoint).forEach { add(it.json) }
                }
                putJsonArray("endpoints") {
                    normalized.filter(CatalogOutbound::endpoint).forEach { add(it.json) }
                }
            }
        val parsed = OutboundCatalogParser.inspect(document.toString())
        require(parsed.skipped.isEmpty() && parsed.catalog.outbounds.size == normalized.size) {
            parsed.skipped.joinToString("; ").ifEmpty { "some outbounds could not be parsed" }
        }
        val metadata = normalized.associateBy(CatalogOutbound::tag)
        return parsed.catalog.outbounds.map { outbound ->
            val source = metadata.getValue(outbound.tag)
            outbound.copy(label = source.label, scope = source.scope, endpoint = source.endpoint)
        }
    }

    private fun generatedTag(
        item: JsonObject,
        type: String,
        index: Int,
    ): String {
        val server = item["server"]?.jsonPrimitive?.contentOrNull?.takeIf(String::isNotBlank)
        val port = item["server_port"]?.jsonPrimitive?.contentOrNull?.takeIf(String::isNotBlank)
        return listOfNotNull(type, server, port).joinToString("-").ifEmpty { "$type-${index + 1}" }
    }

    private fun parseJson(body: String): JsonElement? =
        if (body.startsWith("{") || body.startsWith("[")) {
            runCatching { json.parseToJsonElement(body) }.getOrElse {
                throw IllegalArgumentException("invalid JSON config: ${it.message ?: "parse error"}", it)
            }
        } else {
            null
        }

    private fun isSubscriptionDocument(root: JsonObject): Boolean =
        root.containsKey("outbounds") || root.containsKey("endpoints") || root.containsKey("resources") ||
            root.containsKey("servers") || root.containsKey("proxies") || root.containsKey("api_version") ||
            root["kind"]?.jsonPrimitive?.contentOrNull == "Subscription"

    private fun recognizedSubscription(body: String): OutboundCatalog? =
        runCatching { OutboundCatalogParser.inspect(body).catalog }.getOrNull()

    private fun subscriptionError(): Nothing =
        throw IllegalArgumentException("this is a subscription document; use subscription import instead")
}
