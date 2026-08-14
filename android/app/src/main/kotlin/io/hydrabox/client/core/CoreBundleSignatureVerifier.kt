package io.hydrabox.client.core

import android.util.Base64
import io.hydrabox.client.BuildConfig
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer

class CoreBundleSignatureVerifier(
    encodedKeyRing: String = BuildConfig.HYDRACORE_RELEASE_PUBLIC_KEYS,
) {
    private val keys: Map<String, ByteArray> = parseKeyRing(encodedKeyRing)

    fun hasTrustedKeys(): Boolean = keys.isNotEmpty()

    fun verify(manifestBytes: ByteArray, detachedSignature: ByteArray, keyId: String) {
        val publicKey = keys[keyId]
            ?: throw SecurityException("HydraCore manifest key is not trusted")
        require(detachedSignature.size == ED25519_SIGNATURE_BYTES) {
            "HydraCore detached signature length is invalid"
        }
        val verifier = Ed25519Signer()
        verifier.init(false, Ed25519PublicKeyParameters(publicKey, 0))
        verifier.update(manifestBytes, 0, manifestBytes.size)
        if (!verifier.verifySignature(detachedSignature)) {
            throw SecurityException("HydraCore manifest signature is invalid")
        }
    }

    private fun parseKeyRing(encoded: String): Map<String, ByteArray> {
        if (encoded.isBlank()) return emptyMap()
        return encoded.split(';').associate { entry ->
            val separator = entry.indexOf('=')
            require(separator in 1 until entry.lastIndex) {
                "Invalid HydraCore public key ring entry"
            }
            val keyId = entry.substring(0, separator).trim()
            require(Regex("^[A-Za-z0-9._-]{1,64}$").matches(keyId)) {
                "Invalid HydraCore public key id"
            }
            val key = Base64.decode(entry.substring(separator + 1).trim(), Base64.NO_WRAP)
            require(key.size == ED25519_PUBLIC_KEY_BYTES) {
                "Invalid HydraCore Ed25519 public key"
            }
            keyId to key
        }
    }

    companion object {
        private const val ED25519_PUBLIC_KEY_BYTES = 32
        private const val ED25519_SIGNATURE_BYTES = 64
    }
}
