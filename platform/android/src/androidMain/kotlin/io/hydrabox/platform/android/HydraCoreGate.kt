package io.hydrabox.platform.android

import io.hydrabox.core.subscription.SourceFailure
import io.hydrabox.core.subscription.SubscriptionException
import io.nekohasekai.libbox.Libbox
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * The core is authoritative for the Hydra subscription contract: schema, references,
 * permissions and JWE. This is the gate to it — the client validates through the core and
 * only then projects the document, instead of re-implementing the rules and drifting.
 */
object HydraCoreGate {
    private const val AREA = "hydra-gate"
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    data class Inspection(
        val valid: Boolean,
        val subscriptionId: String? = null,
        val displayName: String? = null,
        val notAfter: String? = null,
        val profiles: Int = 0,
        val resources: Int = 0,
        val diagnostics: List<String> = emptyList(),
    )

    /** True when the body is a JOSE envelope rather than a plaintext document. */
    fun looksEncrypted(body: String): Boolean {
        val trimmed = body.trim()
        if (!trimmed.startsWith("{")) return false
        val root = runCatching { json.parseToJsonElement(trimmed) }.getOrNull() as? JsonObject ?: return false
        return root.containsKey("protected") && root.containsKey("ciphertext") ||
            root.containsKey("protected") && !root.containsKey("resources")
    }

    fun looksHydra(body: String): Boolean {
        val trimmed = body.trim()
        if (!trimmed.startsWith("{")) return false
        val root = runCatching { json.parseToJsonElement(trimmed) }.getOrNull() as? JsonObject ?: return false
        return root["api_version"]?.jsonPrimitive?.contentOrNull?.startsWith("hydra.io/subscription") == true ||
            root["kind"]?.jsonPrimitive?.contentOrNull == "Subscription" ||
            looksEncrypted(trimmed)
    }

    /**
     * Opens an envelope through the core. The key never leaves this call, and the failure
     * message comes from the core rather than being invented here.
     */
    fun open(envelope: String, keyBase64Url: String): String {
        HydraLog.debug(AREA, "opening an encrypted subscription, ${envelope.length} chars")
        return runCatching { Libbox.hydraCoreOpenSubscriptionJWE(envelope, keyBase64Url) }
            .onSuccess { HydraLog.info(AREA, "envelope opened, ${it.length} chars of document") }
            .getOrElse { failure ->
                // This is the line the alpha threw away. Whatever the core said — a bad key,
                // an unsupported feature, a document it will not accept — is the only thing
                // that makes the difference between a fixable report and "it does not work".
                HydraLog.error(AREA, "the core could not open the envelope", failure)
                throw SubscriptionException(
                    failure = SourceFailure.ENCRYPTED_WITHOUT_KEY.takeIf { looksLikeKeyFailure(failure) }
                        ?: SourceFailure.INVALID_CONTENT,
                    detail = HydraLog.describe(failure),
                    cause = failure,
                )
            }
    }

    /**
     * A core diagnostic in the product's vocabulary. `unsupported_required_feature` is the
     * one a person can act on — the subscription needs a core this build does not have — and
     * it must not read as "the link is wrong".
     */
    private fun failureOf(rejections: List<String>): SourceFailure {
        val joined = rejections.joinToString("; ")
        return when {
            joined.contains("unsupported_required_feature") ||
                joined.contains("incompatible_core_version") ||
                joined.contains("incompatible_subscription_contract") -> SourceFailure.CORE_TOO_OLD
            joined.contains("expired") || joined.contains("not_yet_valid") -> SourceFailure.EXPIRED
            joined.contains("decrypt") || joined.contains("authentication") -> SourceFailure.ENCRYPTED_WITHOUT_KEY
            else -> SourceFailure.INVALID_CONTENT
        }
    }

    private fun looksLikeKeyFailure(failure: Throwable): Boolean =
        HydraLog.describe(failure).lowercase().let { text ->
            text.contains("key") || text.contains("decrypt") || text.contains("authentication")
        }

    fun inspect(document: String): Inspection {
        val raw = runCatching { Libbox.hydraCoreInspectSubscription(document) }
            .onFailure { HydraLog.warn(AREA, "the core could not inspect the document", it) }
            .getOrNull()
        val root = runCatching { json.parseToJsonElement(raw.orEmpty()) }.getOrNull() as? JsonObject
            ?: return Inspection(valid = false, diagnostics = listOf("inspection failed"))
        val identity = root["identity"] as? JsonObject
        val validity = root["validity"] as? JsonObject
        return Inspection(
            valid = root["valid"]?.jsonPrimitive?.contentOrNull == "true",
            subscriptionId = identity?.get("id")?.jsonPrimitive?.contentOrNull,
            // The core's inspection does not carry the display block, so the name is read
            // from the document. Without it every Hydra subscription arrives in the list as
            // "Subscription 1" while the provider gave it a name.
            displayName = displayName(document) ?: identity?.get("name")?.jsonPrimitive?.contentOrNull,
            notAfter = validity?.get("not_after")?.jsonPrimitive?.contentOrNull,
            profiles = (root["profiles"] as? JsonArray)?.size ?: 0,
            resources = (root["resources"] as? JsonArray)?.size ?: 0,
            diagnostics = messages(root["diagnostics"] as? JsonArray),
        )
    }

    /**
     * `display.name` is either a string or a map of translations with a `default`. The
     * person's own language wins when the provider sent one.
     */
    private fun displayName(document: String, language: String? = null): String? {
        val root = runCatching { json.parseToJsonElement(document) }.getOrNull() as? JsonObject ?: return null
        val name = (root["display"] as? JsonObject)?.get("name") ?: return null
        (name as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)?.let { return it }
        val translations = name as? JsonObject ?: return null
        val preferred = language?.let { translations[it] }?.jsonPrimitive?.contentOrNull
        return preferred?.takeIf(String::isNotBlank)
            ?: translations["default"]?.jsonPrimitive?.contentOrNull?.takeIf(String::isNotBlank)
            ?: translations.values.firstNotNullOfOrNull { it.jsonPrimitive.contentOrNull?.takeIf(String::isNotBlank) }
    }

    private fun diagnose(result: String): List<String> {
        val root = runCatching { json.parseToJsonElement(result) }.getOrNull() as? JsonObject
            ?: return listOf("the core returned an unreadable validation result")
        if (root["valid"]?.jsonPrimitive?.contentOrNull == "true") return emptyList()
        return messages(root["diagnostics"] as? JsonArray).ifEmpty { listOf("validation failed without a reason") }
    }

    private fun messages(diagnostics: JsonArray?): List<String> = diagnostics.orEmpty().mapNotNull { entry ->
        val diagnostic = entry as? JsonObject ?: return@mapNotNull null
        val code = diagnostic["code"]?.jsonPrimitive?.contentOrNull
        val message = diagnostic["message"]?.jsonPrimitive?.contentOrNull
        val path = diagnostic["path"]?.jsonPrimitive?.contentOrNull
        listOfNotNull(code, message, path?.takeIf { it != "$" }?.let { "at $it" }).joinToString(": ")
            .takeIf(String::isNotEmpty)
    }
}
