package io.hydrabox.core.storage

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFalse

class StorageTest {
    @Test fun `migration from version one preserves a setting`() {
        val driver = StorageTestDriver.versionOne()

        StorageDatabase.Schema.migrate(driver, 1, StorageDatabase.Schema.version)

        assertContentEquals(listOf("theme", "dark"), StorageDatabase(driver).settingsQueries.selectAll().executeAsList().single())
    }

    @Test fun `secret fields are never stored as plaintext`() {
        val plaintext = "private-credential".encodeToByteArray()
        val encrypted = SecretFieldCodec(FixedKeyProvider()).encrypt(plaintext)

        assertFalse(encrypted.decodeToString().contains("private-credential"))
        assertContentEquals(plaintext, SecretFieldCodec(FixedKeyProvider()).decrypt(encrypted))
    }
}
