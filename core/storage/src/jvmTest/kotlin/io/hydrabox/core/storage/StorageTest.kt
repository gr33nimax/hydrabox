package io.hydrabox.core.storage

import io.hydrabox.core.diagnostics.Secret
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith

class StorageTest {
    @Test fun `migration from the previous schema preserves a setting`() {
        val driver = StorageTestDriver.previousVersion()

        StorageDatabase.Schema.migrate(driver, StorageDatabase.Schema.version - 1, StorageDatabase.Schema.version)

        val setting = StorageDatabase(driver).storageDatabaseQueries.selectAll().executeAsOne()
        assertEquals("theme", setting.setting_key)
        assertEquals("dark", setting.value_)
    }

    @Test fun `secret fields are never stored as plaintext`() {
        val secret = Secret.of("private-credential")
        val codec = SecretFieldCodec(FixedKeyProvider())
        val encrypted = secret.sealWith(codec)
        val driver = StorageTestDriver.currentVersion()
        val queries = StorageDatabase(driver).storageDatabaseQueries

        queries.upsertSetting("subscription", "private", encrypted)
        val stored = queries.selectSecretValue("subscription") { requireNotNull(it) }.executeAsOne()

        assertFalse(stored.decodeToString().contains("private-credential"))
        assertContentEquals(encrypted, Secret.openWith(encrypted, codec).sealWith(codec))
        assertFailsWith<IllegalStateException> { Secret.openWith(encrypted, SecretFieldCodec(NoKeyProvider)) }
    }
}

private object NoKeyProvider : SecretFieldCipher {
    override fun encrypt(plaintext: ByteArray): ByteArray = error("no key provider")
    override fun decrypt(ciphertext: ByteArray): ByteArray = error("no key provider")
}

private class FixedKeyProvider : SecretFieldCipher {
    override fun encrypt(plaintext: ByteArray) = plaintext.map { (it.toInt() xor 0x5A).toByte() }.toByteArray()
    override fun decrypt(ciphertext: ByteArray) = encrypt(ciphertext)
}
