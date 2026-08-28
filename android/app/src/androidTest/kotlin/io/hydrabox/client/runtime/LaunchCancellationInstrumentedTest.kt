package io.hydrabox.client.runtime

import android.content.Context
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.hydrabox.client.runtime.proto.CoreRuntimeProtocol
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LaunchCancellationInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private var client: CoreRuntimeClient? = null

    @After
    fun cleanup() {
        client?.close()
        client = null
    }

    @Test
    fun cancellingFiveLaunchesDoesNotLeaveTheRuntimeRunning() {
        repeat(RUNS) { run ->
            val runtime = CoreRuntimeClient(context)
            client = runtime
            runtime.connect()
            val stopped = CountDownLatch(1)
            runtime.start(
                config = blackholeProfile(),
                useVpn = true,
                source = "exp2b-$run",
            ) { }
            Thread(
                {
                    SystemClock.sleep(CANCEL_DELAY_MS)
                    runtime.stop("exp2b-$run") { stopped.countDown() }
                },
                "LaunchCancellation-$run",
            ).start()
            assertTrue("run=$run did not finish", stopped.await(RUN_DEADLINE_MS, TimeUnit.MILLISECONDS))
            assertTrue(
                "run=$run left runtime running",
                runtime.cachedSnapshot()?.state !=
                    CoreRuntimeProtocol.RuntimeState.RUNTIME_STATE_RUNNING,
            )
            runtime.close()
            client = null
        }
    }

    private fun blackholeProfile(): ByteArray =
        requireNotNull(javaClass.classLoader)
            .getResourceAsStream("profile_blackhole.json")
            .use { requireNotNull(it).readBytes() }

    private companion object {
        const val RUNS = 5
        const val CANCEL_DELAY_MS = 2_000L
        const val RUN_DEADLINE_MS = 35_000L
    }
}
