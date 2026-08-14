package io.hydrabox.client.storage

import java.security.MessageDigest
import java.net.URI
import java.util.UUID
import org.json.JSONObject

data class ValidatedResource(
    val stableResourceId: String,
    val resourceType: String,
    val definition: ByteArray,
    val sortOrder: Int,
)

data class ValidatedSubscriptionVersion(
    val rawDocument: ByteArray,
    val compiledConfig: ByteArray,
    val presentationProjection: ByteArray,
    val warningsJson: String,
    val resources: List<ValidatedResource>,
)

data class RemoteSubscriptionSource(
    val url: String,
    val headers: Map<String, String>,
)

/** Accepts only a core-validated immutable version and switches it atomically. */
class SubscriptionRepository(
    private val database: HydraDatabase,
    private val crypto: DomainCrypto,
) {
    suspend fun createRemoteSubscription(
        displayName: String,
        url: String,
        headers: Map<String, String> = emptyMap(),
        refreshIntervalMillis: Long = DEFAULT_REFRESH_INTERVAL_MILLIS,
        automaticRefreshEnabled: Boolean = true,
        nowMillis: Long = System.currentTimeMillis(),
    ): String {
        val normalizedName = displayName.trim()
        require(normalizedName.isNotEmpty() && normalizedName.length <= 256)
        val sourceUri = URI(url.trim())
        require(sourceUri.scheme.equals("https", true) || sourceUri.scheme.equals("http", true))
        require(!sourceUri.host.isNullOrBlank())
        require(sourceUri.userInfo == null && sourceUri.fragment == null)
        val normalizedHeaders = headers.mapKeys { (name, _) ->
            name.trim().also {
                require(HEADER_NAME.matches(it))
                require(it.lowercase() !in TRANSPORT_HEADERS)
            }
        }.mapValues { (_, value) ->
            value.also { require(!it.contains('\r') && !it.contains('\n')) }
        }
        val subscriptionId = UUID.randomUUID().toString()
        val sourceJson = JSONObject()
            .put("url", sourceUri.toString())
            .put("headers", JSONObject(normalizedHeaders))
            .toString()
            .toByteArray(Charsets.UTF_8)
        val interval = refreshIntervalMillis.coerceAtLeast(MINIMUM_REFRESH_INTERVAL_MILLIS)
        database.subscriptions().insert(
            SubscriptionEntity(
                id = subscriptionId,
                displayName = normalizedName,
                sourceType = "remote",
                encryptedSource = crypto.encrypt(
                    sourceJson,
                    "subscription:$subscriptionId:source".aad(),
                ),
                activeVersionId = null,
                previousVersionId = null,
                refreshIntervalMillis = interval,
                nextRefreshAtMillis = if (automaticRefreshEnabled) nowMillis else null,
                automaticRefreshEnabled = automaticRefreshEnabled,
                revision = 1,
                createdAtMillis = nowMillis,
                updatedAtMillis = nowMillis,
            ),
        )
        return subscriptionId
    }

    suspend fun readRemoteSource(subscriptionId: String): RemoteSubscriptionSource {
        val subscription = requireNotNull(database.subscriptions().byId(subscriptionId))
        require(subscription.sourceType == "remote") { "Subscription is not remote" }
        val encrypted = requireNotNull(subscription.encryptedSource) {
            "Remote subscription source is missing"
        }
        val source = JSONObject(
            crypto.decrypt(encrypted, "subscription:$subscriptionId:source".aad())
                .toString(Charsets.UTF_8),
        )
        val headersObject = source.optJSONObject("headers")
        val headers = buildMap {
            if (headersObject != null) {
                val keys = headersObject.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    put(key, headersObject.getString(key))
                }
            }
        }
        return RemoteSubscriptionSource(source.getString("url"), headers)
    }

    suspend fun stageValidatedRefresh(
        subscriptionId: String,
        rawDocument: ByteArray,
        inspectionProjection: ByteArray,
        nowMillis: Long = System.currentTimeMillis(),
    ) {
        require(rawDocument.isNotEmpty())
        val subscription = requireNotNull(database.subscriptions().byId(subscriptionId))
        val candidate = SubscriptionRefreshCandidateEntity(
            subscriptionId = subscriptionId,
            fetchedAtMillis = nowMillis,
            contentSha256 = MessageDigest.getInstance("SHA-256").digest(rawDocument),
            encryptedRawDocument = crypto.encrypt(
                rawDocument,
                "subscription:$subscriptionId:refresh-candidate".aad(),
            ),
            inspectionProjection = inspectionProjection.copyOf(),
        )
        database.subscriptions().stageValidatedRefresh(
            subscriptionId = subscriptionId,
            candidate = candidate,
            nextRefreshAtMillis = nowMillis + subscription.refreshIntervalMillis
                .coerceAtLeast(MINIMUM_REFRESH_INTERVAL_MILLIS),
            updatedAtMillis = nowMillis,
        )
    }
    suspend fun commitValidatedVersion(
        subscriptionId: String,
        validated: ValidatedSubscriptionVersion,
        nowMillis: Long = System.currentTimeMillis(),
    ): String {
        require(validated.rawDocument.isNotEmpty() && validated.compiledConfig.isNotEmpty())
        val versionId = UUID.randomUUID().toString()
        val rawAad = "subscription:$subscriptionId:version:$versionId:raw".aad()
        val configAad = "subscription:$subscriptionId:version:$versionId:config".aad()
        val planSha = MessageDigest.getInstance("SHA-256").digest(validated.compiledConfig)
        val version = SubscriptionVersionEntity(
            id = versionId,
            subscriptionId = subscriptionId,
            createdAtMillis = nowMillis,
            contentSha256 = MessageDigest.getInstance("SHA-256").digest(validated.rawDocument),
            encryptedRawDocument = crypto.encrypt(validated.rawDocument, rawAad),
            compiledPlanSha256 = planSha,
            encryptedCompiledConfig = crypto.encrypt(validated.compiledConfig, configAad),
            presentationProjection = validated.presentationProjection.copyOf(),
            warningsJson = validated.warningsJson,
            validationStatus = "valid",
        )
        val resources = validated.resources.map { value ->
            val resourceId = UUID.randomUUID().toString()
            ResourceEntity(
                id = resourceId,
                subscriptionVersionId = versionId,
                stableResourceId = value.stableResourceId,
                resourceType = value.resourceType,
                encryptedDefinition = crypto.encrypt(
                    value.definition,
                    "subscription:$subscriptionId:version:$versionId:resource:$resourceId".aad(),
                ),
                sortOrder = value.sortOrder,
            )
        }
        database.subscriptions().commitValidatedVersion(
            subscriptionId,
            version,
            resources,
            nowMillis,
        )
        return versionId
    }

    suspend fun readCompiledConfig(subscriptionId: String): ByteArray {
        val subscription = requireNotNull(database.subscriptions().byId(subscriptionId))
        val versionId = requireNotNull(subscription.activeVersionId)
        val version = requireNotNull(database.subscriptionVersions().byId(versionId))
        return crypto.decrypt(
            version.encryptedCompiledConfig,
            "subscription:$subscriptionId:version:$versionId:config".aad(),
        )
    }

    private fun String.aad(): ByteArray = toByteArray(Charsets.UTF_8)

    companion object {
        private val HEADER_NAME = Regex("^[!#$%&'*+.^_`|~0-9A-Za-z-]{1,128}$")
        private val TRANSPORT_HEADERS = setOf(
            "connection",
            "content-length",
            "host",
            "keep-alive",
            "proxy-connection",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade",
        )
        private const val DEFAULT_REFRESH_INTERVAL_MILLIS = 6L * 60L * 60L * 1000L
        private const val MINIMUM_REFRESH_INTERVAL_MILLIS = 15L * 60L * 1000L
    }
}
