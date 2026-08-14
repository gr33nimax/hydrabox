package io.hydrabox.client.storage

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class DomainCrypto(context: Context) {
    private val dataKeyFile = File(context.noBackupFilesDir, "storage/domain-data-key-v1.bin")
    private val random = SecureRandom()
    private val dataKey: SecretKey by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { loadOrCreateDataKey() }

    fun encrypt(plaintext: ByteArray, associatedData: ByteArray): ByteArray {
        val nonce = ByteArray(GCM_NONCE_BYTES).also(random::nextBytes)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, dataKey, GCMParameterSpec(GCM_TAG_BITS, nonce))
        cipher.updateAAD(associatedData)
        val ciphertext = cipher.doFinal(plaintext)
        return ByteBuffer.allocate(HEADER_BYTES + nonce.size + ciphertext.size)
            .put(MAGIC)
            .put(FORMAT_VERSION)
            .put(nonce)
            .put(ciphertext)
            .array()
    }

    fun decrypt(blob: ByteArray, associatedData: ByteArray): ByteArray {
        require(blob.size >= HEADER_BYTES + GCM_NONCE_BYTES + GCM_TAG_BYTES) {
            "Encrypted domain value is truncated"
        }
        val buffer = ByteBuffer.wrap(blob)
        val magic = ByteArray(MAGIC.size).also(buffer::get)
        require(magic.contentEquals(MAGIC) && buffer.get() == FORMAT_VERSION) {
            "Encrypted domain value has an unsupported format"
        }
        val nonce = ByteArray(GCM_NONCE_BYTES).also(buffer::get)
        val ciphertext = ByteArray(buffer.remaining()).also(buffer::get)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, dataKey, GCMParameterSpec(GCM_TAG_BITS, nonce))
        cipher.updateAAD(associatedData)
        return cipher.doFinal(ciphertext)
    }

    private fun loadOrCreateDataKey(): SecretKey {
        val wrappingKey = loadOrCreateWrappingKey()
        if (dataKeyFile.exists()) {
            return SecretKeySpec(unwrapDataKey(dataKeyFile.readBytes(), wrappingKey), "AES")
        }
        val raw = ByteArray(DATA_KEY_BYTES).also(random::nextBytes)
        val wrapped = wrapDataKey(raw, wrappingKey)
        dataKeyFile.parentFile?.let { require(it.mkdirs() || it.isDirectory) }
        val atomic = AtomicFile(dataKeyFile)
        var output: FileOutputStream? = null
        try {
            output = atomic.startWrite()
            output.write(wrapped)
            atomic.finishWrite(output)
        } catch (error: Throwable) {
            output?.let(atomic::failWrite)
            throw error
        } finally {
            raw.fill(0)
        }
        return SecretKeySpec(unwrapDataKey(wrapped, wrappingKey), "AES")
    }

    private fun loadOrCreateWrappingKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
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

    private fun wrapDataKey(raw: ByteArray, wrappingKey: SecretKey): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        // Android Keystore keys with randomized encryption enabled must generate
        // their own IV. Supplying one is rejected on API 23+.
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey)
        val nonce = requireNotNull(cipher.iv) { "Android Keystore returned no GCM nonce" }
        require(nonce.size == GCM_NONCE_BYTES) { "Android Keystore returned an invalid GCM nonce" }
        cipher.updateAAD(DATA_KEY_AAD)
        val ciphertext = cipher.doFinal(raw)
        return ByteBuffer.allocate(HEADER_BYTES + nonce.size + ciphertext.size)
            .put(MAGIC)
            .put(FORMAT_VERSION)
            .put(nonce)
            .put(ciphertext)
            .array()
    }

    private fun unwrapDataKey(wrapped: ByteArray, wrappingKey: SecretKey): ByteArray {
        require(wrapped.size == HEADER_BYTES + GCM_NONCE_BYTES + DATA_KEY_BYTES + GCM_TAG_BYTES) {
            "Wrapped domain data key has an invalid size"
        }
        val buffer = ByteBuffer.wrap(wrapped)
        val magic = ByteArray(MAGIC.size).also(buffer::get)
        require(magic.contentEquals(MAGIC) && buffer.get() == FORMAT_VERSION) {
            "Wrapped domain data key has an unsupported format"
        }
        val nonce = ByteArray(GCM_NONCE_BYTES).also(buffer::get)
        val ciphertext = ByteArray(buffer.remaining()).also(buffer::get)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, wrappingKey, GCMParameterSpec(GCM_TAG_BITS, nonce))
        cipher.updateAAD(DATA_KEY_AAD)
        return cipher.doFinal(ciphertext).also {
            require(it.size == DATA_KEY_BYTES) { "Unwrapped domain data key has an invalid size" }
        }
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "hydrabox-domain-wrapping-key-v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val DATA_KEY_BYTES = 32
        private const val GCM_NONCE_BYTES = 12
        private const val GCM_TAG_BYTES = 16
        private const val GCM_TAG_BITS = 128
        private val MAGIC = byteArrayOf(0x48, 0x42, 0x58, 0x31)
        private const val FORMAT_VERSION: Byte = 1
        private const val HEADER_BYTES = 5
        private val DATA_KEY_AAD = "io.hydrabox.client/domain-data-key/v1".toByteArray(Charsets.US_ASCII)
    }
}
