package io.hydrabox.client.storage

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(tableName = "subscriptions")
data class SubscriptionEntity(
    @androidx.room.PrimaryKey val id: String,
    val displayName: String,
    val sourceType: String,
    val encryptedSource: ByteArray?,
    val activeVersionId: String?,
    val previousVersionId: String?,
    val refreshIntervalMillis: Long,
    val nextRefreshAtMillis: Long?,
    val automaticRefreshEnabled: Boolean,
    val revision: Long,
    val createdAtMillis: Long,
    val updatedAtMillis: Long,
)

@Entity(
    tableName = "subscription_versions",
    foreignKeys = [
        ForeignKey(
            entity = SubscriptionEntity::class,
            parentColumns = ["id"],
            childColumns = ["subscriptionId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("subscriptionId"), Index(value = ["subscriptionId", "createdAtMillis"])],
)
data class SubscriptionVersionEntity(
    @androidx.room.PrimaryKey val id: String,
    val subscriptionId: String,
    val createdAtMillis: Long,
    val contentSha256: ByteArray,
    val encryptedRawDocument: ByteArray,
    val compiledPlanSha256: ByteArray,
    val encryptedCompiledConfig: ByteArray,
    val presentationProjection: ByteArray,
    val warningsJson: String,
    val validationStatus: String,
)

@Entity(
    tableName = "resources",
    foreignKeys = [
        ForeignKey(
            entity = SubscriptionVersionEntity::class,
            parentColumns = ["id"],
            childColumns = ["subscriptionVersionId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index("subscriptionVersionId"),
        Index(value = ["subscriptionVersionId", "stableResourceId"], unique = true),
    ],
)
data class ResourceEntity(
    @androidx.room.PrimaryKey val id: String,
    val subscriptionVersionId: String,
    val stableResourceId: String,
    val resourceType: String,
    val encryptedDefinition: ByteArray,
    val sortOrder: Int,
)

@Entity(tableName = "profiles", indices = [Index("subscriptionId")])
data class ProfileEntity(
    @androidx.room.PrimaryKey val id: String,
    val subscriptionId: String?,
    val subscriptionVersionId: String?,
    val displayName: String,
    val compiledPlanSha256: ByteArray,
    val encryptedCompiledConfig: ByteArray,
    val createdAtMillis: Long,
    val updatedAtMillis: Long,
)

@Entity(
    tableName = "outbound_presentation",
    indices = [Index("profileId"), Index(value = ["profileId", "stableOutboundId"], unique = true)],
)
data class OutboundPresentationEntity(
    @androidx.room.PrimaryKey val id: String,
    val profileId: String,
    val stableOutboundId: String,
    val displayName: String,
    val protocolId: String,
    val groupId: String,
    val endpointIdentitySha256: ByteArray,
    val sortOrder: Int,
)

@Entity(tableName = "selector_choices")
data class SelectorChoiceEntity(
    @androidx.room.PrimaryKey val selectorId: String,
    val stableOutboundId: String,
    val updatedAtMillis: Long,
)

@Entity(
    tableName = "probe_results",
    indices = [Index("stableOutboundId"), Index(value = ["stableOutboundId", "measuredAtMillis"])],
)
data class ProbeResultEntity(
    @androidx.room.PrimaryKey val id: String,
    val sessionId: String,
    val stableOutboundId: String,
    val delayMillis: Long?,
    val measuredAtMillis: Long,
    val networkFingerprint: String,
    val outcome: String,
    val errorCode: String?,
)

@Entity(tableName = "daily_traffic", primaryKeys = ["profileId", "epochDay"])
data class DailyTrafficEntity(
    val profileId: String,
    val epochDay: Long,
    val uplinkBytes: Long,
    val downlinkBytes: Long,
    val updatedAtMillis: Long,
)

@Entity(tableName = "incidents", indices = [Index("occurredAtMillis"), Index("correlationId")])
data class IncidentEntity(
    @androidx.room.PrimaryKey val id: String,
    val occurredAtMillis: Long,
    val category: String,
    val code: String,
    val correlationId: String,
    val generation: Long?,
    val coreProcessEpoch: String?,
    val encryptedPayload: ByteArray,
    val sizeBytes: Int,
)
