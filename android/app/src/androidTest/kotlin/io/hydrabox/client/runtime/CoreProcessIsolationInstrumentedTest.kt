package io.hydrabox.client.runtime

import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import android.os.Process
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CoreProcessIsolationInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private var connection: ServiceConnection? = null

    @After
    fun unbind() {
        connection?.let { runCatching { context.unbindService(it) } }
        connection = null
    }

    @Test
    fun runtimeServiceUsesVersionedContractInDedicatedProcess() {
        assertServiceProcess(CoreRuntimeService::class.java, ":core")
        assertServiceProcess(CoreProbeService::class.java, ":core_probe")

        val connected = CountDownLatch(1)
        var remote: ICoreRuntimeService? = null
        val serviceConnection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                remote = ICoreRuntimeService.Stub.asInterface(binder)
                connected.countDown()
            }

            override fun onServiceDisconnected(name: ComponentName) = Unit
        }
        connection = serviceConnection
        assertTrue(
            context.bindService(
                Intent(context, CoreRuntimeService::class.java),
                serviceConnection,
                Context.BIND_AUTO_CREATE,
            ),
        )
        assertTrue("core service did not bind", connected.await(20, TimeUnit.SECONDS))

        assertNotNull(remote)
        val service = remote!!
        val contract = CoreRuntimeProtocol.CoreContract.parseFrom(service.contract)
        assertEquals(1, contract.apiMajor)
        assertTrue(
            "runtime snapshot schema 1 is not supported",
            contract.runtimeSnapshotSchema.minimum <= 1 &&
                contract.runtimeSnapshotSchema.maximum >= 1,
        )
        assertTrue(
            "runtime event schema 1 is not supported",
            contract.runtimeEventSchema.minimum <= 1 &&
                contract.runtimeEventSchema.maximum >= 1,
        )
        assertTrue(
            "HydraCore protocol registry was not projected into CoreContract",
            contract.supportedProtocolIdsList.isNotEmpty(),
        )

        val snapshot = CoreRuntimeProtocol.RuntimeSnapshot.parseFrom(service.getSnapshot())
        assertTrue("snapshot sequence must be non-negative", snapshot.lastSequence >= 0L)
        assertTrue("snapshot process epoch is blank", snapshot.processEpoch.isNotBlank())

        val expectedProcess = "${context.packageName}:core"
        val coreProcess = context.getSystemService(ActivityManager::class.java)
            .runningAppProcesses
            .orEmpty()
            .firstOrNull { it.processName == expectedProcess }
        assertNotNull("dedicated core process is not visible", coreProcess)
        assertNotEquals(Process.myPid(), coreProcess!!.pid)
    }

    private fun assertServiceProcess(serviceClass: Class<*>, suffix: String) {
        val packageManager = context.packageManager
        val component = ComponentName(context, serviceClass)
        val info = if (android.os.Build.VERSION.SDK_INT >= 33) {
            packageManager.getServiceInfo(
                component,
                PackageManager.ComponentInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getServiceInfo(component, 0)
        }
        assertEquals("${context.packageName}$suffix", info.processName)
        assertTrue("$component must not be exported", !info.exported)
    }
}
