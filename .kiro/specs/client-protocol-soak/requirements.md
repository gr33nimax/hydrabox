# Requirements: Client Protocol Soak Test

**Status:** Draft — Requirements approval required

## Purpose

Evaluate the stability of the HydraBox2 Android client and embedded HydraCore across every profile enabled by the supplied subscription. Collect reproducible evidence, distinguish client defects from server/network failures, and optimize client-side code only when a measured client-side cause is established.

## Scope decomposition

1. **Profile inventory** — enumerate each enabled profile, protocol/transport, selector path and test eligibility without exposing credentials.
2. **Client protocol harness** — execute a consistent connect → health → data-plane → disconnect/reconnect scenario for each profile.
3. **Observability** — collect client/core logs, Android state, resource measurements and any profiler surface exposed on port 9091.
4. **Stability scenarios** — repeat startup/reconnect and bounded steady-state checks; test network handover only with explicit approval because it disrupts connectivity.
5. **Analysis and optimization** — identify only measured client-side failures, make minimal fixes, and compare before/after under the same scenario.

## Requirements

### R1 — Complete profile accounting

**User story:** As a maintainer, I want every enabled profile accounted for, so that an untested protocol cannot be mistaken for a healthy one.

1. WHEN a test run starts THEN the harness SHALL create an inventory with a stable profile identifier, protocol/transport classification, and eligibility status for every enabled server.
2. WHEN a profile cannot be exercised THEN the report SHALL mark it `skipped` or `failed` with an observable reason; it SHALL NOT report it as healthy.
3. WHEN evidence is written THEN it SHALL redact subscription URLs, credentials, private keys, tokens, and full generated configurations.

### R2 — Repeatable per-profile client scenario

**User story:** As a maintainer, I want one comparable scenario per profile, so that protocol failures can be compared rather than inferred from UI state.

1. WHEN an eligible profile is tested THEN the client SHALL record the duration and outcome of cold start, configuration acceptance, transport-health transition, and disconnect.
2. WHEN a profile reaches a connected state THEN the harness SHALL collect independent data-plane evidence where available: selected outbound, exit lookup, configured URL-test result, and a positive TUN byte-counter delta under bounded workload.
3. WHEN latency, exit lookup, or address projection is absent while data-plane evidence succeeds THEN the report SHALL classify the observability failure separately from the protocol/data-plane result; it SHALL not silently report the profile healthy.
4. WHEN a profile is disconnected and reconnected THEN the harness SHALL record whether it restores the expected selected route without leaked service, binding, or core state.
5. IF a step exceeds its documented timeout THEN the harness SHALL preserve the relevant logcat, Android service state, and profiler snapshot before continuing to the next profile.
6. The harness SHALL execute profiles serially by default so simultaneous standalone sessions do not distort core resource or flood-control behavior.

### R3 — Stability coverage

**User story:** As a maintainer, I want bounded repetition and steady-state evidence, so that one successful connection is not confused with stability.

1. WHEN a profile passes the basic scenario THEN the harness SHALL perform at least three connect/disconnect cycles unless the profile fails earlier.
2. WHEN a profile is held connected THEN the harness SHALL collect periodic health and resource samples for 10 minutes after three successful reconnect cycles.
3. WHEN a Wi-Fi/mobile handover is performed THEN the harness SHALL record the network generation, route recovery and data-plane result before and after the handover; it SHALL report an unavailable or filtered mobile network as an environment condition, not a client pass or failure.
4. The harness SHALL not alter server-side configuration, subscription contents, or credentials.

### R4 — Observability and profiling

**User story:** As a maintainer, I want evidence sufficient to diagnose client-side causes, so that an optimization is based on measurements.

1. WHEN a run begins THEN the harness SHALL create a timestamped evidence directory containing a manifest, commands, device metadata, selected logcat and per-profile summaries.
2. FOR EACH profile scenario, the harness SHALL collect applicable Android data: process identity, `dumpsys` service/VPN state, network state, memory/CPU samples, and client/core logs.
3. WHEN port 9091 is reachable from the test host or device THEN the harness SHALL capture relevant Go pprof endpoints without collecting secrets and record endpoint/status/content type.
4. IF port 9091 is unavailable or authenticated THEN the report SHALL record that condition explicitly without treating it as a protocol failure.
5. WHEN an app/client fault occurs THEN the report SHALL retain the complete causal log window and relevant thread/heap/Perfetto evidence when justified by the symptom.

### R5 — Diagnosis and optimization discipline

**User story:** As a maintainer, I want client optimizations to improve measured behavior without hiding server failures.

1. WHEN a failure is observed THEN the analysis SHALL classify it as client, core, server/relay, network, or inconclusive and cite evidence for the classification.
2. WHEN a client-side defect is confirmed THEN the implementation SHALL add the smallest regression test or reproducible check that would fail without the fix.
3. WHEN an optimization is proposed THEN the same profile, device, network, workload and timeout SHALL be measured before and after the change.
4. The report SHALL distinguish an individual profile failure from a cross-protocol client regression.
5. The harness SHALL not modify HydraCore merely to suppress a client-visible symptom without a demonstrated core-side cause.

## Acceptance criteria

- Every eligible enabled profile has a pass/fail/skipped outcome and evidence reference.
- Every failure includes a bounded reason and diagnostic artifact; no silent omission is allowed.
- Port 9091 is either profiled or explicitly documented as unavailable/unsupported.
- A client optimization, if any, has a reproducible before/after measurement and regression coverage.
- The final report identifies unresolved external dependencies separately from client defects.

## Constraints

- Test device: Android handset attached through ADB; preserve its original network mode and application state after the run.
- No secrets in console output, reports, commits, or evidence manifests.
- Live VK/TURN/captcha behavior requires the actual server event; absence of an event is not proof of correctness or failure.
- Go pprof is expected on port 9091; only non-secret diagnostic endpoints are in scope.
- Local Windows `go test -race` remains unavailable without a CGO/gcc toolchain; race evidence requires Linux CI.
- Wi-Fi/mobile handover is authorized; server mutation, subscription mutation, and destructive cleanup are not.

## Open questions

1. **Resolved:** soak duration is 10 minutes per protocol after three reconnect cycles.
2. **Resolved:** port 9091 exposes Go pprof.
3. **Resolved:** Wi-Fi ↔ mobile-data handover is authorized; mobile whitelist state is unknown and must be reported as environment evidence.
4. **Resolved:** use a documented public HTTPS workload selected in `design.md`; endpoint failures must be classified separately from client/protocol failures.
