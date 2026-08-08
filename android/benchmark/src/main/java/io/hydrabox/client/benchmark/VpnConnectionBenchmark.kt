package io.hydrabox.client.benchmark

import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.FrameTimingMetric
import androidx.benchmark.macro.StartupMode
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
@LargeTest
class VpnConnectionBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun connectVpn() {
        assumeTrue(
            "Pass hydraboxBenchmarkConnectVpn=true only on a seeded test device",
            vpnConnectionBenchmarkEnabled(),
        )
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        try {
            benchmarkRule.measureRepeated(
                packageName = TARGET_PACKAGE,
                metrics = listOf(FrameTimingMetric()),
                compilationMode = CompilationMode.Partial(),
                startupMode = StartupMode.COLD,
                iterations = 3,
                setupBlock = { pressHome() },
                measureBlock = {
                    prepareMainScreen()
                    tryConnectVpn()
                },
            )
        } finally {
            // Never leave a benchmark VPN running on the developer's device.
            device.executeShellCommand("am force-stop $TARGET_PACKAGE")
        }
    }
}
