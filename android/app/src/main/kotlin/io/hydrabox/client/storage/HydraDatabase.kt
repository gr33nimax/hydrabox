package io.hydrabox.client.storage

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import io.hydrabox.client.platform.AndroidProcessIdentity

@Database(
    entities = [
        SubscriptionEntity::class,
        SubscriptionVersionEntity::class,
        SubscriptionRefreshCandidateEntity::class,
        ResourceEntity::class,
        ProfileEntity::class,
        OutboundPresentationEntity::class,
        SelectorChoiceEntity::class,
        ProbeResultEntity::class,
        DailyTrafficEntity::class,
        IncidentEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class HydraDatabase : RoomDatabase() {
    abstract fun subscriptions(): SubscriptionDao
    abstract fun subscriptionVersions(): SubscriptionVersionDao
    abstract fun subscriptionRefreshCandidates(): SubscriptionRefreshCandidateDao
    abstract fun resources(): ResourceDao
    abstract fun profiles(): ProfileDao
    abstract fun outboundPresentation(): OutboundPresentationDao
    abstract fun selectorChoices(): SelectorChoiceDao
    abstract fun probes(): ProbeResultDao
    abstract fun dailyTraffic(): DailyTrafficDao
    abstract fun incidents(): IncidentDao

    companion object {
        @Volatile
        private var instance: HydraDatabase? = null

        fun open(context: Context): HydraDatabase {
            val app = context.applicationContext
            val processName = AndroidProcessIdentity.current(app)
            check(!processName.endsWith(":core")) {
                "The HydraCore process cannot open the domain database"
            }
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(app, HydraDatabase::class.java, "hydrabox-v1.db")
                    .build()
                    .also { instance = it }
            }
        }
    }
}
