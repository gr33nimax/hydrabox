package io.hydrabox.core.storage

import io.hydrabox.core.model.OperationError
import io.hydrabox.core.model.OperationState

data class BackupSetting(val key: String, val value: String, val secretValue: ByteArray?)
data class BackupMetadata(val key: String, val value: ByteArray)
data class BackupSubscription(val id: String, val name: String, val sourceSecret: ByteArray, val updatedAtMillis: Long)

data class StorageBackup(
    val schemaVersion: Long,
    val settings: List<BackupSetting>,
    val metadata: List<BackupMetadata>,
    val subscriptions: List<BackupSubscription> = emptyList(),
)

data class BackupOutcome(val schemaVersion: Long, val entries: Int)

data class BackupState(val operation: OperationState<BackupOutcome> = OperationState.Idle)

class BackupService(private val database: StorageDatabase) {
    fun export(): StorageBackup {
        val queries = database.storageDatabaseQueries
        return StorageBackup(
            schemaVersion = StorageDatabase.Schema.version,
            settings = queries.selectAll().executeAsList().map { BackupSetting(it.setting_key, it.value_, it.secret_value) },
            metadata = queries.selectMetadata().executeAsList().map { BackupMetadata(it.storage_key, it.value_) },
            subscriptions = queries.selectSubscriptions().executeAsList().map { BackupSubscription(it.subscription_id, it.name, it.source_secret, it.updated_at_millis) },
        )
    }

    fun import(backup: StorageBackup): OperationState<BackupOutcome> {
        if (backup.schemaVersion !in (StorageDatabase.Schema.version - 1)..StorageDatabase.Schema.version) {
            return OperationState.Failed(OperationError("unsupported_backup_version"))
        }
        val queries = database.storageDatabaseQueries
        queries.transaction {
            queries.deleteAllSettings()
            queries.deleteAllMetadata()
            queries.deleteAllSubscriptions()
            backup.settings.forEach { queries.upsertSetting(it.key, it.value, it.secretValue) }
            backup.metadata.forEach { queries.upsertValue(it.key, it.value) }
            backup.subscriptions.forEach { queries.upsertSubscription(it.id, it.name, it.sourceSecret, it.updatedAtMillis) }
        }
        return OperationState.Succeeded(BackupOutcome(StorageDatabase.Schema.version, backup.settings.size + backup.metadata.size + backup.subscriptions.size))
    }
}
