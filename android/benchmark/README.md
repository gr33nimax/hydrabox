# HydraBox Android performance profiles

This module measures release-like Android startup and generates Baseline and
Startup Profiles on a connected Android 13+ physical device.

```powershell
cd android
.\gradlew.bat :app:generateBaselineProfile
.\gradlew.bat :benchmark:connectedBenchmarkReleaseAndroidTest
```

The startup-only journey is included in `startup-prof.txt`. Settings, opening
the proxy panel, and list scrolling are included only in the broader Baseline
Profile.

Real VPN connection is deliberately opt-in because the device must already
contain a usable subscription and the test changes system-wide networking.
Run it only on a seeded test device; the benchmark force-stops HydraBox on exit.
The `etonifyBenchmarkConnectVpn` argument is retained as a compatibility ID:

```powershell
.\gradlew.bat :benchmark:connectedBenchmarkReleaseAndroidTest `
  -Pandroid.testInstrumentationRunnerArguments.etonifyBenchmarkConnectVpn=true
```

The same flag can include the connection path in a manually generated Baseline
Profile. Keep it disabled for routine CI and clean-device profile generation.
