# Tasks: Client Protocol Soak Test

**Status:** Draft — Tasks approval required

## Progress

- [x] Requirements approved
- [x] Design approved
- [ ] Tasks approved
- [ ] Evidence collection complete
- [ ] Client optimization candidates resolved or documented

## 1. Prepare a deterministic, redacting host harness

- [ ] 1.1 Implement inventory and evidence bootstrap
  - Add a dependency-free host-side MJS harness under `tools/` that records device/APK/Core metadata, creates a unique run directory and writes a hash manifest.
  - Collect profile identifiers/types through the app-visible state or redacted metadata; reject any field resembling a credential or full subscription URL.
  - _Requirements: R1, R4_
  - **Done when:** a dry-run creates a redacted `profiles.json` and evidence manifest without starting a tunnel.

- [ ] 1.2 Implement lifecycle and data-plane scenario commands
  - Add serialized operations for select, cold connect, health wait, exit/URL-test evidence, disconnect and repeat.
  - Record phase timestamps and enforce explicit timeouts with evidence capture rather than unbounded retries.
  - _Requirements: R2, R3_
  - **Done when:** a single selected profile can run three cycles and always restores the initial selection/mode in cleanup.

- [ ] 1.3 Implement bounded public workload collection
  - Use the design’s public 1 MiB HTTPS endpoint at most once per 30 seconds during the 10-minute hold, one stream only.
  - Record status, elapsed time and transferred byte count; classify endpoint-wide failure separately.
  - _Requirements: R2, R3, R5_
  - **Done when:** workload output is bounded to 20 MiB/profile and all outcomes are written as structured evidence.

## 2. Add client/core observability

- [ ] 2.1 Implement Android state and resource snapshots
  - Collect filtered/full bounded logcat windows, `dumpsys` VPN/service/network state, process identity and CPU/PSS deltas.
  - Add failure-only collection paths for thread/Perfetto data where the observed symptom warrants it.
  - _Requirements: R2, R4_
  - **Done when:** every failed phase points to a bounded diagnostic artifact.

- [ ] 2.2 Implement safe pprof capture through adb forwarding
  - Discover the loopback `9091` listener after core startup; assign a host-local forward and capture index, goroutine and heap snapshots.
  - Capture 30-second CPU and 5-second trace profiles only for observed stalls; remove forwards during cleanup.
  - _Requirements: R4, R5_
  - **Done when:** pprof unavailable is reported explicitly, and successful captures never print profile bodies or secrets.

## 3. Execute the protocol matrix

- [ ] 3.1 Run baseline and reconnect matrix
  - Exercise every eligible profile serially: cold connect, three reconnect cycles, selected-route and data-plane evidence, 10-minute steady-state workload, teardown.
  - _Requirements: R1, R2, R3_
  - **Done when:** each inventory entry is pass/fail/skipped/inconclusive with a run directory.

- [ ] 3.2 Run authorized network-handover matrix
  - For profiles passing the baseline, attempt one Wi-Fi/mobile handover only when Android exposes a usable target network.
  - Record network generation, route and data-plane before/after; never label a missing/filtered mobile network as client failure.
  - _Requirements: R3, R4_
  - **Done when:** every eligible handover outcome has state and log evidence.

## 4. Diagnose and optimize measured client defects

- [ ] 4.1 Produce a classification report
  - Group failures by causal signature; distinguish client/core from profile, relay, endpoint and network environment failures.
  - Identify only repeatable or directly traced client-side candidates.
  - _Requirements: R5_
  - **Done when:** every proposed optimization cites at least two matching runs or a direct crash/leak trace.

- [ ] 4.2 Apply and prove minimal client/core fixes when justified
  - Add regression coverage before/with each confirmed fix.
  - Repeat the affected scenario twice after the fix on the same profile/device/network and compare timing, resource and pprof evidence against baseline.
  - _Requirements: R5_
  - **Done when:** the report contains before/after evidence, full relevant tests pass, and unresolved external failures remain explicitly classified.

## Dependencies

`1.1 → 1.2 → 1.3 → 2.1/2.2 → 3.1 → 3.2 → 4.1 → 4.2`

## Residual external limits

- Linux CI is required for Go race testing.
- VK/TURN/captcha assertions need the corresponding live server event.
- A mobile whitelist/filter can make handover data-plane evidence inconclusive rather than client-failing.
