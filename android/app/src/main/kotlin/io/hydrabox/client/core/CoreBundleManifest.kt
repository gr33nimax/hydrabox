package io.hydrabox.client.core

import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.time.Instant

data class SchemaRange(val minimum: Int, val maximum: Int) {
    init {
        require(minimum >= 1 && maximum >= minimum) { "invalid schema range" }
    }

    fun contains(value: Int): Boolean = value in minimum..maximum
}

data class CoreBundleArtifact(
    val abi: String,
    val assetName: String,
    val sizeBytes: Long,
    val sha256: String,
    val minSdk: Int,
)

data class CoreBundleManifest(
    val releaseSequence: Long,
    val version: String,
    val sourceCommit: String,
    val upstreamCommit: String,
    val publishedAt: Instant,
    val coreApiMajor: Int,
    val coreApiMinor: Int,
    val runtimeSnapshotSchema: SchemaRange,
    val runtimeEventSchema: SchemaRange,
    val configSchema: SchemaRange,
    val subscriptionSchema: SchemaRange,
    val capabilitiesSha256: String,
    val keyId: String,
    val artifacts: List<CoreBundleArtifact>,
) {
    fun artifactForAbi(abi: String): CoreBundleArtifact? =
        artifacts.singleOrNull { it.abi == abi }

    companion object {
        const val SCHEMA_VERSION = 1
        const val DISTRIBUTION_ID = "io.hydrabox.hydracore"
        const val CORE_API_MAJOR = 1
        const val MAX_MANIFEST_BYTES = 128 * 1024
        const val MAX_ARTIFACT_BYTES = 256L * 1024L * 1024L

        private val versionPattern = Regex("^[0-9A-Za-z][0-9A-Za-z._+-]{0,126}$")
        private val commitPattern = Regex("^[0-9a-f]{40}$")
        private val shaPattern = Regex("^[0-9a-f]{64}$")
        private val keyPattern = Regex("^[A-Za-z0-9._-]{1,64}$")
        private val assetPattern = Regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,126}$")
        private val supportedAbis = setOf("arm64-v8a", "armeabi-v7a", "x86_64")
        private const val RUNTIME_SNAPSHOT_SCHEMA = 1
        private const val RUNTIME_EVENT_SCHEMA = 1
        private const val CONFIG_SCHEMA = 1
        private const val SUBSCRIPTION_SCHEMA = 2

        fun parse(rawBytes: ByteArray): CoreBundleManifest {
            require(rawBytes.isNotEmpty() && rawBytes.size <= MAX_MANIFEST_BYTES) {
                "HydraCore manifest size is invalid"
            }
            val decoder = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            val root = JSONObject(decoder.decode(ByteBuffer.wrap(rawBytes)).toString())
            require(root.getInt("schemaVersion") == SCHEMA_VERSION) {
                "Unsupported HydraCore manifest schema"
            }
            require(root.getString("distributionId") == DISTRIBUTION_ID) {
                "Unexpected HydraCore distribution"
            }
            val releaseSequence = root.getLong("releaseSequence")
            require(releaseSequence > 0) { "HydraCore releaseSequence must be positive" }
            val coreApiMajor = root.getInt("coreApiMajor")
            val coreApiMinor = root.getInt("coreApiMinor")
            require(coreApiMajor == CORE_API_MAJOR && coreApiMinor >= 0) {
                "HydraCore API is incompatible"
            }
            val runtimeSnapshotSchema = root.schemaRange("runtimeSnapshotSchema")
            val runtimeEventSchema = root.schemaRange("runtimeEventSchema")
            val configSchema = root.schemaRange("configSchema")
            val subscriptionSchema = root.schemaRange("subscriptionSchema")
            require(
                runtimeSnapshotSchema.contains(RUNTIME_SNAPSHOT_SCHEMA) &&
                    runtimeEventSchema.contains(RUNTIME_EVENT_SCHEMA) &&
                    configSchema.contains(CONFIG_SCHEMA) &&
                    subscriptionSchema.contains(SUBSCRIPTION_SCHEMA)
            ) {
                "HydraCore schema surface is incompatible"
            }
            return CoreBundleManifest(
                releaseSequence = releaseSequence,
                version = root.requiredString("version", versionPattern),
                sourceCommit = root.requiredString("sourceCommit", commitPattern).lowercase(),
                upstreamCommit = root.requiredString("upstreamCommit", commitPattern).lowercase(),
                publishedAt = Instant.parse(root.getString("publishedAt")),
                coreApiMajor = coreApiMajor,
                coreApiMinor = coreApiMinor,
                runtimeSnapshotSchema = runtimeSnapshotSchema,
                runtimeEventSchema = runtimeEventSchema,
                configSchema = configSchema,
                subscriptionSchema = subscriptionSchema,
                capabilitiesSha256 =
                    root.requiredString("capabilitiesSha256", shaPattern).lowercase(),
                keyId = root.requiredString("keyId", keyPattern),
                artifacts = parseArtifacts(root.getJSONArray("artifacts")),
            )
        }

        private fun parseArtifacts(array: JSONArray): List<CoreBundleArtifact> {
            require(array.length() in 1..supportedAbis.size) {
                "HydraCore manifest has an invalid artifact count"
            }
            val seen = mutableSetOf<String>()
            return List(array.length()) { index ->
                val item = array.getJSONObject(index)
                val abi = item.getString("abi")
                require(abi in supportedAbis && seen.add(abi)) {
                    "HydraCore artifact ABI is invalid or duplicated"
                }
                val size = item.getLong("sizeBytes")
                require(size in 1..MAX_ARTIFACT_BYTES) {
                    "HydraCore artifact size is invalid"
                }
                val minSdk = item.getInt("minSdk")
                require(minSdk in 26..100) { "HydraCore artifact minSdk is invalid" }
                CoreBundleArtifact(
                    abi = abi,
                    assetName = item.requiredString("assetName", assetPattern),
                    sizeBytes = size,
                    sha256 = item.requiredString("sha256", shaPattern).lowercase(),
                    minSdk = minSdk,
                )
            }
        }

        private fun JSONObject.schemaRange(name: String): SchemaRange {
            val value = getJSONObject(name)
            return SchemaRange(value.getInt("min"), value.getInt("max"))
        }

        private fun JSONObject.requiredString(name: String, pattern: Regex): String {
            val value = getString(name).trim()
            require(pattern.matches(value)) { "HydraCore manifest $name is invalid" }
            return value
        }
    }
}
