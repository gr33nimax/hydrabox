package io.hydrabox.client.storage

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.Serializer
import io.hydrabox.client.storage.proto.AppSettingsProtocol
import io.hydrabox.client.platform.AndroidProcessIdentity
import kotlinx.coroutines.flow.Flow
import java.io.File
import java.io.InputStream
import java.io.OutputStream

object AppSettingsSerializer : Serializer<AppSettingsProtocol.AppSettings> {
    override val defaultValue: AppSettingsProtocol.AppSettings =
        AppSettingsProtocol.AppSettings.newBuilder()
            .setSchemaVersion(1)
            .setRevision(1)
            .setThemeMode("system")
            .setNetworkHeartbeatEnabled(true)
            .setNetworkHeartbeatIntervalSeconds(180)
            .setPerformanceMode("standard")
            .setMemoryLimitEnabled(true)
            .setDefaultSubscriptionRefreshMillis(6 * 60 * 60 * 1000L)
            .build()

    override suspend fun readFrom(input: InputStream): AppSettingsProtocol.AppSettings {
        val value = AppSettingsProtocol.AppSettings.parseFrom(input)
        require(value.schemaVersion == 1) { "Unsupported settings schema" }
        return value
    }

    override suspend fun writeTo(
        t: AppSettingsProtocol.AppSettings,
        output: OutputStream,
    ) {
        require(t.schemaVersion == 1) { "Unsupported settings schema" }
        t.writeTo(output)
    }
}

class AppSettingsStore private constructor(
    private val dataStore: DataStore<AppSettingsProtocol.AppSettings>,
) {
    val values: Flow<AppSettingsProtocol.AppSettings> = dataStore.data

    suspend fun update(
        mutation: (AppSettingsProtocol.AppSettings.Builder) -> Unit,
    ): AppSettingsProtocol.AppSettings = dataStore.updateData { current ->
        current.toBuilder().also(mutation)
            .setSchemaVersion(1)
            .setRevision(current.revision + 1)
            .build()
    }

    companion object {
        @Volatile
        private var instance: AppSettingsStore? = null

        fun open(context: Context): AppSettingsStore {
            val app = context.applicationContext
            val processName = AndroidProcessIdentity.current(app)
            check(!processName.endsWith(":core")) {
                "The HydraCore process cannot open application settings"
            }
            return instance ?: synchronized(this) {
                instance ?: AppSettingsStore(
                    DataStoreFactory.create(
                        serializer = AppSettingsSerializer,
                        produceFile = { File(app.filesDir, "datastore/app-settings-v1.pb") },
                    ),
                ).also { instance = it }
            }
        }
    }
}
