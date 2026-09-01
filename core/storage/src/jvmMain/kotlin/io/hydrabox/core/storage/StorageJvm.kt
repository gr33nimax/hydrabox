package io.hydrabox.core.storage

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.sun.jna.platform.win32.Crypt32Util
import java.io.File
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

actual class StorageContext(val directory: File)

actual fun openStorageDriver(context: StorageContext, databaseName: String): SqlDriver =
    JdbcSqliteDriver("jdbc:sqlite:${File(context.directory, databaseName).absolutePath}").also(StorageDatabase.Schema::create)

actual fun platformSecretFieldCipher(driver: SqlDriver): SecretFieldCipher {
    check(System.getProperty("os.name").startsWith("Windows")) { "DPAPI is required for desktop secret storage" }
    val queries = StorageDatabase(driver).storageDatabaseQueries
    val protected = queries.selectValue(FIELD_KEY_NAME).executeAsOneOrNull()
    val key = protected?.let(Crypt32Util::cryptUnprotectData) ?: ByteArray(AES_KEY_BYTES).also {
        SecureRandom().nextBytes(it)
        queries.upsertValue(FIELD_KEY_NAME, Crypt32Util.cryptProtectData(it))
    }
    return AesGcmFieldCipher(SecretKeySpec(key, "AES"))
}

private class AesGcmFieldCipher(private val key: SecretKey) : SecretFieldCipher {
    override fun encrypt(plaintext: ByteArray): ByteArray = Cipher.getInstance("AES/GCM/NoPadding").run {
        init(Cipher.ENCRYPT_MODE, key)
        iv + doFinal(plaintext)
    }

    override fun decrypt(ciphertext: ByteArray): ByteArray = Cipher.getInstance("AES/GCM/NoPadding").run {
        require(ciphertext.size > GCM_IV_BYTES)
        init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, ciphertext.copyOfRange(0, GCM_IV_BYTES)))
        doFinal(ciphertext.copyOfRange(GCM_IV_BYTES, ciphertext.size))
    }
}

private const val FIELD_KEY_NAME = "field-cipher-key"
private const val AES_KEY_BYTES = 32
private const val GCM_IV_BYTES = 12
private const val GCM_TAG_BITS = 128
