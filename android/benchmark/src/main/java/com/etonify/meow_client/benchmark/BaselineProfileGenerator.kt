package com.etonify.meow_client.benchmark

import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
@LargeTest
class BaselineProfileGenerator {
    @get:Rule
    val baselineProfileRule = BaselineProfileRule()

    @Test
    fun startupProfile() = baselineProfileRule.collect(
        packageName = TARGET_PACKAGE,
        maxIterations = 5,
        stableIterations = 3,
        includeInStartupProfile = true,
    ) {
        launchHydraBox()
    }

    @Test
    fun criticalUserJourneys() = baselineProfileRule.collect(
        packageName = TARGET_PACKAGE,
        maxIterations = 5,
        stableIterations = 3,
        includeInStartupProfile = false,
    ) {
        prepareMainScreen()
        openSettingsAndReturn()
        if (vpnConnectionBenchmarkEnabled()) {
            tryConnectVpn()
        }
        openAndScrollProxyList()
    }
}
