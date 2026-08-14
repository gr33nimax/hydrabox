package io.hydrabox.client.storage

import java.security.MessageDigest
import java.util.UUID

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

/** Accepts only a core-validated immutable version and switches it atomically. */
class SubscriptionRepository(
    private val database: HydraDatabase,
    private val crypto: DomainCrypto,
) {
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
}
