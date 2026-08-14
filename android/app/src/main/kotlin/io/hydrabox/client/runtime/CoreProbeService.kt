package io.hydrabox.client.runtime

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.google.protobuf.ByteString
import go.HydraNativeLoader
import io.hydrabox.client.HydraBoxApplication
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import io.hydrabox.client.singbox.HydraBoxProxyPlatformInterface
import io.hydrabox.client.singbox.NativeCoreEnvironment
import io.nekohasekai.libbox.Libbox
import java.security.MessageDigest
import java.util.UUID

class CoreProbeService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val binder = object : ICoreProbeService.Stub() {
        override fun runProbe(requestBytes: ByteArray?): ByteArray {
            val report = probe(requestBytes).toByteArray()
            // A probe process cannot safely load a different .so later in the same VM.
            // Terminate after returning the binder payload so every candidate gets a clean process.
            mainHandler.postDelayed({
                stopSelf()
                android.os.Process.killProcess(android.os.Process.myPid())
            }, PROCESS_EXIT_DELAY_MILLIS)
            return report
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    private fun probe(bytes: ByteArray?): CoreRuntimeProtocol.CoreProbeReport {
        val request = runCatching {
            require(bytes != null && bytes.isNotEmpty() && bytes.size <= MAX_PROBE_REQUEST_BYTES)
            CoreRuntimeProtocol.CoreProbeRequest.parseFrom(bytes)
        }.getOrElse {
            return failure(0L, ByteArray(0), "core.probe.invalid_request", "probe_decode")
        }
        if (request.schemaVersion != SCHEMA_VERSION || request.releaseSequence <= 0L ||
            request.artifactSha256.size() != SHA256_BYTES ||
            request.validationFixturesList.any { it.size() > MAX_FIXTURE_BYTES }
        ) {
            return failure(
                request.releaseSequence,
                request.artifactSha256.toByteArray(),
                "core.probe.invalid_request",
                "probe_validation",
            )
        }
        return runCatching {
            NativeCoreEnvironment.ensureSetup()
            check(HydraNativeLoader.loadedSource() == "active") {
                "The candidate library was not selected"
            }
            val capabilities = invokeCoreString("hydraCoreCapabilities")
            check(capabilities.isNotEmpty()) { "HydraCore capabilities are unavailable" }
            val supportedProtocolIds = CoreCapabilityContract.supportedProtocolIds(capabilities)
            request.validationFixturesList.forEach { fixture ->
                Libbox.checkConfig(fixture.toStringUtf8())
            }
            // Exercise native allocation and close independently from the real runtime.
            Libbox.newStandaloneURLTestSession(
                HydraBoxProxyPlatformInterface(HydraBoxApplication.application),
            ).close()
            val schema = CoreRuntimeProtocol.SchemaRange.newBuilder()
                .setMinimum(1)
                .setMaximum(1)
                .build()
            val contract = CoreRuntimeProtocol.CoreContract.newBuilder()
                .setApiMajor(CORE_API_MAJOR)
                .setApiMinor(CORE_API_MINOR)
                .setCoreVersion(Libbox.version())
                .setProcessEpoch(UUID.randomUUID().toString())
                .setRuntimeSnapshotSchema(schema)
                .setRuntimeEventSchema(schema)
                .setConfigSchema(schema)
                .setSubscriptionSchema(
                    CoreRuntimeProtocol.SchemaRange.newBuilder().setMinimum(2).setMaximum(2),
                )
                .addAllSupportedProtocolIds(supportedProtocolIds)
                .setCapabilitiesSha256(
                    ByteString.copyFrom(MessageDigest.getInstance("SHA-256").digest(capabilities)),
                )
                .build()
            CoreRuntimeProtocol.CoreProbeReport.newBuilder()
                .setSchemaVersion(SCHEMA_VERSION)
                .setReleaseSequence(request.releaseSequence)
                .setArtifactSha256(request.artifactSha256)
                .setHealthy(true)
                .setLoadedSource(HydraNativeLoader.loadedSource())
                .setContract(contract)
                .setValidatedFixtureCount(request.validationFixturesCount)
                .build()
        }.getOrElse {
            failure(
                request.releaseSequence,
                request.artifactSha256.toByteArray(),
                "core.probe.failed",
                "native_probe",
            )
        }
    }

    private fun invokeCoreString(name: String): ByteArray {
        val method = Libbox::class.java.methods.firstOrNull {
            it.name.equals(name, ignoreCase = true) && it.parameterCount == 0
        } ?: throw IllegalStateException("HydraCore API is unavailable")
        return ((method.invoke(null) as? String)
            ?: throw IllegalStateException("HydraCore returned no payload"))
            .toByteArray(Charsets.UTF_8)
    }

    private fun failure(
        releaseSequence: Long,
        sha256: ByteArray,
        code: String,
        stage: String,
    ): CoreRuntimeProtocol.CoreProbeReport = CoreRuntimeProtocol.CoreProbeReport.newBuilder()
        .setSchemaVersion(SCHEMA_VERSION)
        .setReleaseSequence(releaseSequence)
        .setArtifactSha256(ByteString.copyFrom(sha256))
        .setHealthy(false)
        .setLoadedSource(HydraNativeLoader.loadedSource())
        .setError(
            CoreRuntimeProtocol.CoreError.newBuilder()
                .setCode(code)
                .setStage(stage)
                .setRetryable(false)
                .setUserAction(CoreRuntimeProtocol.UserAction.USER_ACTION_ROLLBACK)
                .setSafeMessage("The HydraCore candidate did not pass isolated validation.")
                .setCorrelationId(UUID.randomUUID().toString()),
        )
        .build()

    companion object {
        private const val SCHEMA_VERSION = 1
        private const val CORE_API_MAJOR = 1
        private const val CORE_API_MINOR = 0
        private const val SHA256_BYTES = 32
        private const val MAX_FIXTURE_BYTES = 256 * 1024
        private const val MAX_PROBE_REQUEST_BYTES = 768 * 1024
        private const val PROCESS_EXIT_DELAY_MILLIS = 250L
    }
}
