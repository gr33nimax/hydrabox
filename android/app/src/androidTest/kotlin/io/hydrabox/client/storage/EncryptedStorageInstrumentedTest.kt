package io.hydrabox.client.storage

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EncryptedStorageInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test
    fun roomAndKeystoreKeepOnlyActiveAndPreviousValidatedVersions() = runBlocking {
        withContext(Dispatchers.IO) {
            val database = HydraDatabase.open(context)
            database.clearAllTables()
            try {
                val crypto = DomainCrypto(context)
                val repository = SubscriptionRepository(database, crypto)
                val sourceUrl = "https://example.com/private/subscription"
                val subscriptionId = repository.createRemoteSubscription(
                    displayName = "Instrumented subscription",
                    url = sourceUrl,
                    headers = mapOf("Authorization" to "Bearer instrumented-secret"),
                    automaticRefreshEnabled = false,
                )

                val stored = requireNotNull(database.subscriptions().byId(subscriptionId))
                val encryptedSource = requireNotNull(stored.encryptedSource)
                assertFalse(encryptedSource.toString(StandardCharsets.UTF_8).contains(sourceUrl))
                assertNotEquals(sourceUrl.toByteArray().toList(), encryptedSource.toList())
                val source = repository.readRemoteSource(subscriptionId)
                assertEquals(sourceUrl, source.url)
                assertEquals("Bearer instrumented-secret", source.headers["Authorization"])

                val versionIds = (1..3).map { revision ->
                    repository.commitValidatedVersion(
                        subscriptionId,
                        ValidatedSubscriptionVersion(
                            rawDocument = "raw-$revision".toByteArray(),
                            compiledConfig = "config-$revision".toByteArray(),
                            presentationProjection = "projection-$revision".toByteArray(),
                            warningsJson = "[]",
                            resources = listOf(
                                ValidatedResource(
                                    stableResourceId = "resource-$revision",
                                    resourceType = "network.outbound",
                                    definition = "secret-resource-$revision".toByteArray(),
                                    sortOrder = 0,
                                ),
                            ),
                        ),
                    )
                }

                val activated = requireNotNull(database.subscriptions().byId(subscriptionId))
                assertEquals(versionIds[2], activated.activeVersionId)
                assertEquals(versionIds[1], activated.previousVersionId)
                assertEquals(
                    setOf(versionIds[1], versionIds[2]),
                    database.subscriptionVersions().validVersions(subscriptionId)
                        .map { it.id }
                        .toSet(),
                )
                assertEquals("config-3", repository.readCompiledConfig(subscriptionId).toString(Charsets.UTF_8))
                assertTrue(activated.revision >= 4L)
            } finally {
                database.clearAllTables()
            }
        }
    }
}
