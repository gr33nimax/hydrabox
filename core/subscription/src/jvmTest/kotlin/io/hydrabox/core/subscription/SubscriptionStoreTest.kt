package io.hydrabox.core.subscription

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import io.hydrabox.core.diagnostics.Secret
import io.hydrabox.core.storage.SecretFieldCipher
import io.hydrabox.core.storage.SecretFieldCodec
import io.hydrabox.core.storage.StorageDatabase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFails

class SubscriptionStoreTest {
    @Test fun `subscription update changes one encrypted SQLDelight row`() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also(StorageDatabase.Schema::create)
        val cipher = SecretFieldCodec(FixedCipher)
        val store = SubscriptionStore(StorageDatabase(driver), cipher, cipher)
        store.save(SubscriptionRecord("a", "First", Secret.of("vless://one"), 1))
        store.save(SubscriptionRecord("b", "Second", Secret.of("vless://two"), 2))
        store.save(SubscriptionRecord("a", "Renamed", Secret.of("vless://updated"), 3))

        assertEquals(listOf("Renamed", "Second"), store.all().map(SubscriptionRecord::name))
        val raw = StorageDatabase(driver).storageDatabaseQueries.selectSubscriptionSecret("a").executeAsOne()
        assertFalse(raw.decodeToString().contains("updated"))
    }

    @Test fun `failed refresh leaves the persisted subscription unchanged`() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also(StorageDatabase.Schema::create)
        val cipher = SecretFieldCodec(FixedCipher)
        val store = SubscriptionStore(StorageDatabase(driver), cipher, cipher)
        val original = SubscriptionRecord("a", "Original", Secret.of("vless://one"), 1)
        store.save(original)

        assertFails { SubscriptionUpdater(store).refresh(original) { error("network failure") } }
        assertEquals("Original", store.all().single().name)
    }
}

private object FixedCipher : SecretFieldCipher {
    override fun encrypt(plaintext: ByteArray) = plaintext.map { (it.toInt() xor 0x5A).toByte() }.toByteArray()
    override fun decrypt(ciphertext: ByteArray) = encrypt(ciphertext)
}
