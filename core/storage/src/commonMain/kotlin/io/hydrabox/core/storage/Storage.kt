package io.hydrabox.core.storage

import app.cash.sqldelight.db.SqlDriver
import io.hydrabox.core.diagnostics.SecretOpener
import io.hydrabox.core.diagnostics.SecretSealer

interface SecretFieldCipher {
    fun encrypt(plaintext: ByteArray): ByteArray
    fun decrypt(ciphertext: ByteArray): ByteArray
}

class SecretFieldCodec(private val cipher: SecretFieldCipher) : SecretSealer, SecretOpener {
    override fun seal(plaintext: String): ByteArray = cipher.encrypt(plaintext.encodeToByteArray())
    override fun open(ciphertext: ByteArray): String = cipher.decrypt(ciphertext).decodeToString()
}

expect class StorageContext

expect fun openStorageDriver(context: StorageContext, databaseName: String): SqlDriver

expect fun platformSecretFieldCipher(driver: SqlDriver): SecretFieldCipher
