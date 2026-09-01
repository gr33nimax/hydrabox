package io.hydrabox.core.storage

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

actual class StorageContext(val context: Context)

actual fun openStorageDriver(context: StorageContext, databaseName: String): SqlDriver =
    AndroidSqliteDriver(StorageDatabase.Schema, context.context, databaseName)

actual fun platformSecretFieldCipher(driver: SqlDriver): SecretFieldCipher =
    AesGcmFieldCipher(androidKey())

private fun androidKey(): SecretKey {
    val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    return keyStore.getKey(KEY_ALIAS, null) as? SecretKey ?: KeyGenerator.getInstance(
        KeyProperties.KEY_ALGORITHM_AES,
        "AndroidKeyStore",
    ).run {
        init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        generateKey()
    }
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

private const val KEY_ALIAS = "hydrabox.storage.field.v1"
private const val GCM_IV_BYTES = 12
private const val GCM_TAG_BITS = 128
