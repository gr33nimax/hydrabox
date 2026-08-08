package io.hydrabox.client

import android.content.Context
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object HydraDeviceIdentity {
    private const val KEY_STORE = "AndroidKeyStore"
    private const val WRAPPING_KEY_ALIAS = "hydrabox.hwid.seed.wrap.v1"
    private const val PREFERENCES_NAME = "hydrabox_device_identity"
    private const val WRAPPED_SEED = "wrapped_seed_v1"
    private const val SEED_BYTES = 32
    private const val NONCE_BYTES = 12

    @Synchronized
    fun forOrigin(context: Context, origin: String): String {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID,
        )?.trim().orEmpty()
        val component = androidId.ifEmpty {
            Base64.encodeToString(
                getOrCreateFallbackSeed(context),
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
            )
        }
        return HydraDeviceIdPolicy.derive(context.packageName, component, origin)
    }

    private fun getOrCreateFallbackSeed(context: Context): ByteArray {
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val wrappingKey = getOrCreateWrappingKey()
        val stored = preferences.getString(WRAPPED_SEED, null)
        if (stored != null) {
            runCatching { unwrap(stored, wrappingKey) }
                .getOrNull()
                ?.takeIf { it.size == SEED_BYTES }
                ?.let { return it }
        }
        val seed = ByteArray(SEED_BYTES).also(SecureRandom()::nextBytes)
        check(preferences.edit().putString(WRAPPED_SEED, wrap(seed, wrappingKey)).commit()) {
            "Failed to persist HydraBox identity seed"
        }
        return seed
    }

    private fun getOrCreateWrappingKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEY_STORE).apply { load(null) }
        (keyStore.getKey(WRAPPING_KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEY_STORE)
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

    private fun wrap(seed: ByteArray, key: SecretKey): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return Base64.encodeToString(cipher.iv + cipher.doFinal(seed), Base64.NO_WRAP)
    }

    private fun unwrap(envelope: String, key: SecretKey): ByteArray {
        val decoded = Base64.decode(envelope, Base64.NO_WRAP)
        require(decoded.size > NONCE_BYTES) { "Invalid wrapped HydraBox identity seed" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(128, decoded.copyOfRange(0, NONCE_BYTES)),
        )
        return cipher.doFinal(decoded.copyOfRange(NONCE_BYTES, decoded.size))
    }
}
