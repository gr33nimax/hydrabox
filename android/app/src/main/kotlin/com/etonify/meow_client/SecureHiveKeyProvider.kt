package com.etonify.meow_client

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps the Hive data key encrypted by a non-exportable Android Keystore key.
 * The raw data key is returned only to this process so Hive can encrypt records.
 */
object SecureHiveKeyProvider {
    private const val ANDROID_KEY_STORE = "AndroidKeyStore"
    private const val WRAPPING_KEY_ALIAS = "etonify.hive.wrap.v1"
    private const val PREFERENCES_NAME = "etonify_secure_storage"
    private const val WRAPPED_DATA_KEY = "wrapped_hive_data_key_v1"
    private const val DATA_KEY_BYTES = 32
    private const val GCM_NONCE_BYTES = 12
    private const val GCM_TAG_BITS = 128

    @Synchronized
    fun getOrCreateDataKey(context: Context): String {
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val wrappingKey = getOrCreateWrappingKey()
        val encoded = preferences.getString(WRAPPED_DATA_KEY, null)

        val dataKey = if (encoded == null) {
            ByteArray(DATA_KEY_BYTES).also(SecureRandom()::nextBytes).also { key ->
                val wrapped = wrap(key, wrappingKey)
                check(preferences.edit().putString(WRAPPED_DATA_KEY, wrapped).commit()) {
                    "Failed to persist the wrapped Hive key"
                }
            }
        } else {
            unwrap(encoded, wrappingKey)
        }

        check(dataKey.size == DATA_KEY_BYTES) { "Invalid Hive data key length" }
        return Base64.encodeToString(dataKey, Base64.NO_WRAP)
    }

    private fun getOrCreateWrappingKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(WRAPPING_KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                WRAPPING_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun wrap(dataKey: ByteArray, wrappingKey: SecretKey): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey)
        val ciphertext = cipher.doFinal(dataKey)
        val envelope = cipher.iv + ciphertext
        return Base64.encodeToString(envelope, Base64.NO_WRAP)
    }

    private fun unwrap(envelope: String, wrappingKey: SecretKey): ByteArray {
        val decoded = Base64.decode(envelope, Base64.NO_WRAP)
        require(decoded.size > GCM_NONCE_BYTES) { "Invalid wrapped Hive key" }
        val nonce = decoded.copyOfRange(0, GCM_NONCE_BYTES)
        val ciphertext = decoded.copyOfRange(GCM_NONCE_BYTES, decoded.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, wrappingKey, GCMParameterSpec(GCM_TAG_BITS, nonce))
        return cipher.doFinal(ciphertext)
    }
}
