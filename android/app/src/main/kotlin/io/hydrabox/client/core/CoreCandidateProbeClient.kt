package io.hydrabox.client.core

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.google.protobuf.ByteString
import io.hydrabox.client.runtime.CoreProbeService
import io.hydrabox.client.runtime.ICoreProbeService
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Runs a staged candidate in :core_probe and persists proof only after a valid report. */
class CoreCandidateProbeClient(context: Context) {
    private val appContext = context.applicationContext
    private val manager = CoreBundleManager(appContext)
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HydraCoreCandidateProbe").apply { isDaemon = true }
    }

    fun probe(
        validationFixtures: List<ByteArray>,
        callback: (Result<CoreRuntimeProtocol.CoreProbeReport>) -> Unit,
    ) {
        val candidate = manager.readState().candidate
        if (candidate == null) {
            callback(Result.failure(IllegalStateException("No HydraCore candidate is staged")))
            return
        }
        require(validationFixtures.sumOf(ByteArray::size) <= MAX_TOTAL_FIXTURE_BYTES) {
            "HydraCore validation fixtures are too large"
        }
        val request = CoreRuntimeProtocol.CoreProbeRequest.newBuilder()
            .setSchemaVersion(SCHEMA_VERSION)
            .setReleaseSequence(candidate.releaseSequence)
            .setArtifactSha256(ByteString.copyFrom(candidate.sha256.hexToBytes()))
            .addAllValidationFixtures(validationFixtures.map { ByteString.copyFrom(it) })
            .build()
        val completed = AtomicBoolean(false)
        lateinit var connection: ServiceConnection
        fun complete(result: Result<CoreRuntimeProtocol.CoreProbeReport>) {
            if (!completed.compareAndSet(false, true)) return
            runCatching { appContext.unbindService(connection) }
            appContext.stopService(Intent(appContext, CoreProbeService::class.java))
            handler.post { callback(result) }
        }
        connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                val service = ICoreProbeService.Stub.asInterface(binder)
                executor.execute {
                    val result = runCatching {
                        val report = CoreRuntimeProtocol.CoreProbeReport.parseFrom(
                            service.runProbe(request.toByteArray()),
                        )
                        check(report.healthy)
                        check(report.releaseSequence == candidate.releaseSequence)
                        check(report.artifactSha256.toByteArray().contentEquals(candidate.sha256.hexToBytes()))
                        check(report.loadedSource == "active")
                        check(report.contract.apiMajor == CoreBundleManifest.CORE_API_MAJOR)
                        check(report.validatedFixtureCount == validationFixtures.size)
                        manager.markCandidateProbed(candidate.releaseSequence, candidate.sha256)
                        report
                    }
                    complete(result)
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                complete(Result.failure(IllegalStateException("HydraCore candidate probe crashed")))
            }

            override fun onBindingDied(name: ComponentName?) {
                complete(Result.failure(IllegalStateException("HydraCore candidate probe binding died")))
            }

            override fun onNullBinding(name: ComponentName?) {
                complete(Result.failure(IllegalStateException("HydraCore candidate probe refused binding")))
            }
        }
        val bound = appContext.bindService(
            Intent(appContext, CoreProbeService::class.java),
            connection,
            Context.BIND_AUTO_CREATE,
        )
        if (!bound) {
            complete(Result.failure(IllegalStateException("HydraCore candidate probe could not start")))
            return
        }
        handler.postDelayed({
            complete(Result.failure(IllegalStateException("HydraCore candidate probe timed out")))
        }, PROBE_DEADLINE_MILLIS)
    }

    private fun String.hexToBytes(): ByteArray {
        require(length % 2 == 0)
        return ByteArray(length / 2) { index ->
            substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }

    companion object {
        private const val SCHEMA_VERSION = 1
        private const val MAX_TOTAL_FIXTURE_BYTES = 512 * 1024
        private const val PROBE_DEADLINE_MILLIS = 30_000L
    }
}
