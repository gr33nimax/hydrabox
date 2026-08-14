package io.hydrabox.client.storage

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction

@Dao
abstract class SubscriptionDao {
    @Query("SELECT * FROM subscriptions ORDER BY displayName COLLATE NOCASE")
    abstract suspend fun all(): List<SubscriptionEntity>

    @Query("SELECT * FROM subscriptions WHERE id = :id")
    abstract suspend fun byId(id: String): SubscriptionEntity?

    @Query(
        "SELECT * FROM subscriptions WHERE automaticRefreshEnabled = 1 " +
            "AND sourceType = 'remote' AND nextRefreshAtMillis IS NOT NULL " +
            "AND nextRefreshAtMillis <= :nowMillis ORDER BY nextRefreshAtMillis LIMIT :limit",
    )
    abstract suspend fun dueForRefresh(nowMillis: Long, limit: Int): List<SubscriptionEntity>

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract suspend fun insert(subscription: SubscriptionEntity)

    @Query(
        "UPDATE subscriptions SET previousVersionId = activeVersionId, activeVersionId = :versionId, " +
            "revision = revision + 1, updatedAtMillis = :updatedAtMillis WHERE id = :subscriptionId",
    )
    abstract suspend fun activateVersion(
        subscriptionId: String,
        versionId: String,
        updatedAtMillis: Long,
    ): Int

    @Query(
        "UPDATE subscriptions SET nextRefreshAtMillis = :nextRefreshAtMillis, " +
            "updatedAtMillis = :updatedAtMillis WHERE id = :subscriptionId",
    )
    abstract suspend fun scheduleNextRefresh(
        subscriptionId: String,
        nextRefreshAtMillis: Long,
        updatedAtMillis: Long,
    )

    @Insert(onConflict = OnConflictStrategy.ABORT)
    protected abstract suspend fun insertVersion(version: SubscriptionVersionEntity)

    @Insert(onConflict = OnConflictStrategy.ABORT)
    protected abstract suspend fun insertResources(resources: List<ResourceEntity>)

    @Query(
        "DELETE FROM subscription_versions WHERE subscriptionId = :subscriptionId " +
            "AND id NOT IN (:keepIds)",
    )
    protected abstract suspend fun deleteVersionsExcept(subscriptionId: String, keepIds: List<String>)

    @Transaction
    open suspend fun commitValidatedVersion(
        subscriptionId: String,
        version: SubscriptionVersionEntity,
        resources: List<ResourceEntity>,
        updatedAtMillis: Long,
    ) {
        insertVersion(version)
        if (resources.isNotEmpty()) insertResources(resources)
        check(activateVersion(subscriptionId, version.id, updatedAtMillis) == 1) {
            "Subscription disappeared during version activation"
        }
        val activated = requireNotNull(byId(subscriptionId))
        deleteVersionsExcept(
            subscriptionId,
            listOfNotNull(activated.activeVersionId, activated.previousVersionId).distinct(),
        )
    }
}

@Dao
abstract class SubscriptionVersionDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract suspend fun insert(version: SubscriptionVersionEntity)

    @Query("SELECT * FROM subscription_versions WHERE id = :id")
    abstract suspend fun byId(id: String): SubscriptionVersionEntity?

    @Query(
        "SELECT * FROM subscription_versions WHERE subscriptionId = :subscriptionId " +
            "AND validationStatus = 'valid' ORDER BY createdAtMillis DESC",
    )
    abstract suspend fun validVersions(subscriptionId: String): List<SubscriptionVersionEntity>

    @Query(
        "DELETE FROM subscription_versions WHERE subscriptionId = :subscriptionId " +
            "AND id NOT IN (:keepIds)",
    )
    abstract suspend fun deleteExcept(subscriptionId: String, keepIds: List<String>)
}

@Dao
interface ResourceDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertAll(resources: List<ResourceEntity>)

    @Query("SELECT * FROM resources WHERE subscriptionVersionId = :versionId ORDER BY sortOrder")
    suspend fun forVersion(versionId: String): List<ResourceEntity>
}

@Dao
interface ProfileDao {
    @Query("SELECT * FROM profiles ORDER BY displayName COLLATE NOCASE")
    suspend fun all(): List<ProfileEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(profile: ProfileEntity)
}

@Dao
interface OutboundPresentationDao {
    @Query("SELECT * FROM outbound_presentation WHERE profileId = :profileId ORDER BY sortOrder")
    suspend fun forProfile(profileId: String): List<OutboundPresentationEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(values: List<OutboundPresentationEntity>)
}

@Dao
interface SelectorChoiceDao {
    @Query("SELECT * FROM selector_choices")
    suspend fun all(): List<SelectorChoiceEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(value: SelectorChoiceEntity)
}

@Dao
interface ProbeResultDao {
    @Query(
        "SELECT * FROM probe_results WHERE stableOutboundId = :outboundId " +
            "ORDER BY measuredAtMillis DESC LIMIT :limit",
    )
    suspend fun recent(outboundId: String, limit: Int = 20): List<ProbeResultEntity>

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(value: ProbeResultEntity)

    @Query("DELETE FROM probe_results WHERE measuredAtMillis < :cutoffMillis")
    suspend fun deleteOlderThan(cutoffMillis: Long): Int

    @Query(
        "DELETE FROM probe_results WHERE id IN (SELECT id FROM probe_results " +
            "WHERE stableOutboundId = :outboundId ORDER BY measuredAtMillis DESC LIMIT -1 OFFSET :keep)",
    )
    suspend fun trimOutbound(outboundId: String, keep: Int = 20): Int
}

@Dao
interface DailyTrafficDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(value: DailyTrafficEntity)

    @Query("SELECT * FROM daily_traffic WHERE epochDay >= :minimumEpochDay ORDER BY epochDay")
    suspend fun since(minimumEpochDay: Long): List<DailyTrafficEntity>

    @Query("DELETE FROM daily_traffic WHERE epochDay < :minimumEpochDay")
    suspend fun deleteBefore(minimumEpochDay: Long): Int

    @Query("DELETE FROM daily_traffic")
    suspend fun reset()
}

@Dao
interface IncidentDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(value: IncidentEntity)

    @Query("SELECT * FROM incidents ORDER BY occurredAtMillis DESC LIMIT :limit")
    suspend fun recent(limit: Int = 1000): List<IncidentEntity>

    @Query("SELECT COALESCE(SUM(sizeBytes), 0) FROM incidents")
    suspend fun totalSizeBytes(): Long

    @Query("DELETE FROM incidents WHERE occurredAtMillis < :cutoffMillis")
    suspend fun deleteOlderThan(cutoffMillis: Long): Int

    @Query(
        "DELETE FROM incidents WHERE id IN (SELECT id FROM incidents " +
            "ORDER BY occurredAtMillis DESC LIMIT -1 OFFSET :keep)",
    )
    suspend fun trimCount(keep: Int = 1000): Int

    @Query("DELETE FROM incidents WHERE id IN (:ids)")
    suspend fun deleteIds(ids: List<String>): Int
}
