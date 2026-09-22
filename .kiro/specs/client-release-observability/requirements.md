# Requirements: Client, release, and diagnostics controls

**Status:** Approved — 2026-09-16
**Date:** 2026-09-16

## Purpose

Bring the subscription-addition flow into the existing HydraBox visual language, let a person select the release channel/branch used for in-app updates, make the existing pprof listener on port 9091 explicitly controllable, and assess existing local changes before any commit or push.

## Scope decomposition

| Capability | Outcome | Dependency |
| --- | --- | --- |
| Subscription-addition UI | A coherent, accessible entry flow for URL/file subscription import | Independent |
| Update channel | A selected branch/channel, initially including `canary`, that safely discovers and installs a signed release | Depends on current release metadata and updater capability |
| pprof control | A persisted explicit on/off setting for the 9091 diagnostic listener | Depends on where the listener is owned |
| Local-change review | A written verdict for every existing uncommitted change and a commit only for approved, coherent changes | Independent; push remains separate |
| TLS fragmentation compatibility | Fragment supported TLS outbounds without making a subscription containing Naive unusable | Independent |

## Verified current state

- The normal subscription-import UI is `AddSourceSheet` in `ui/app/src/commonMain/kotlin/io/hydrabox/ui/app/SourcesScreen.kt`. It currently closes immediately for both URL and file submission, so an asynchronous failure loses the open form and its typed state.
- The repository has a release workflow, but no in-app updater: the workflow publishes unsigned-for-client metadata only as a GitHub prerelease with APK and SHA-256; the existing release spec explicitly excludes an update manifest and client updater.
- pprof is configured only for debug builds through `AppStore.generateConfig()`: it passes loopback `127.0.0.1:9091` to `TunnelInput.debugListen`; release builds pass an empty value. Changing it requires regenerating/restarting the tunnel configuration.
- The remote `origin/canary` exists at `697bdfb73e28af9d8e59f05c18d95ac43cb08e87`, but the local remote-tracking refs are stale. The current release workflow does not mark releases with a channel.
- Pre-existing local work contains two whitespace/formatting-only code diffs, the completed route-separator micro-fix, several draft specs, an unfinished protocol-soak harness, and private `.pi/` task artifacts. No whole working tree commit is currently justified.
- TLS fragmentation currently reaches every type in `dialCapableTypes`, including `naive`. The bundled core rejects both generated fields (`tls.fragment` and `tls.record_fragment`) for Naive with the reported error, so one Naive server can make the full tunnel configuration fail.

## Requirements

### R1 — Subscription addition fits the application

**User story:** As a person adding a subscription, I want one clear import flow that matches the rest of HydraBox, so that I know what to enter and what will happen.

1. WHEN the person opens the subscription-addition screen THEN the application SHALL use the existing design-system spacing, typography, actions, and error treatment.
2. WHEN the person chooses URL or file import THEN the application SHALL make the choice and its consequence explicit without hiding the alternate import path.
3. WHEN the person submits an invalid, insecure, unsupported, or unreachable source THEN the application SHALL preserve their input where safe and show the existing actionable failure explanation.
4. WHEN import succeeds THEN the application SHALL return to an observable state showing the imported source and its server count or failure state.
5. The flow SHALL remain accessible by screen reader and usable at narrow phone widths.

### R2 — Selected update channel

**User story:** As a person using a pre-release build, I want to select `canary` or another supported update channel, so that the app checks the release line I chose rather than a hard-coded branch.

1. WHEN the person opens update settings THEN the application SHALL show the active update channel and exactly the first-release choices `Stable` and `Canary`.
2. WHEN the person changes channel THEN the application SHALL persist the choice and explain that the next update check uses that channel.
3. WHEN an update check finds a release matching the selected channel THEN the application SHALL show the version, publication identity, and an explicit install action.
4. IF no matching release exists, metadata is invalid, an artifact fails integrity/signature verification, or installation is denied by Android THEN the application SHALL fail closed with an actionable message and SHALL NOT install the artifact.
5. The release channel SHALL default to the existing safe behavior; changing it SHALL not affect subscription refreshes or 1.x release behavior.

### R3 — pprof listener control

**User story:** As a maintainer, I want to explicitly enable or disable pprof on port 9091, so that diagnostic exposure is deliberate.

1. WHEN the pprof setting is disabled THEN the application/core SHALL not expose a listener on port 9091.
2. WHEN the setting is enabled THEN the application/core SHALL expose pprof only through its documented diagnostic listener and report a failure if binding port 9091 is impossible.
3. WHEN the person changes the setting THEN the application SHALL state whether restart/reconnect is required and persist the selected state.
4. The setting SHALL default to disabled; it SHALL not silently enable profiling after update or restore.

### R4 — Core-validated TLS fragmentation

**User story:** As a person choosing either TLS-fragmentation mode, I want every advertised eligible protocol to start with the bundled core, so that the setting is a working capability rather than untested JSON.

1. WHEN TLS fragmentation is `record` or `fragment` AND an outbound is type `naive` THEN the application SHALL preserve its subscription-provided TLS configuration but SHALL NOT add `tls.record_fragment`, `tls.fragment`, or `tls.fragment_fallback_delay`.
2. WHEN TLS fragmentation is enabled THEN the application SHALL add only the selected fields to the explicit core-validated TLS-capable set: `http`, `vmess`, `trojan`, `vless`, `anytls`, `shadowtls`, and `trusttunnel`.
3. WHEN an outbound has no TLS object or is outside that set (`socks`, `shadowsocks`, `mieru`, `ssh`, `naive`, and the QUIC-based `hysteria`, `hysteria2`, `tuic`, `masque`) THEN the application SHALL not advertise or synthesize TLS fragmentation for it.
   - QUIC-based transports accept the fields without an error but never apply them: the bundled core wraps a fragmented connection only on the stream/TCP TLS path (`common/tls/std_client.go`, `common/tls/utls_client.go`), while QUIC hands the TLS config to its own stack. The setting is therefore inert for them and SHALL NOT be presented as effective.
   - `sudoku` is fragment-capable in the core (`transport/sudoku/obfs/httpmask/tunnel.go` calls `tlsConfig.Client(conn)`), but its TLS lives inside `http_mask.tls` rather than a top-level `tls`. It stays outside the set until nested handling exists; the boundary SHALL be stated rather than implied.
4. FOR EACH eligible type and each mode, a complete generated configuration SHALL pass the exact bundled-core configuration constructor without reaching a network or using subscription credentials.
5. WHEN a catalog contains all supported and unsupported current outbound types THEN a complete configuration for each mode SHALL validate, preserving fields for ineligible outbounds and applying the selected fields only to eligible ones.
6. Regression evidence SHALL state its boundary: constructor validation proves the bundled core accepts and applies the configuration path; it does not claim live-network fragmentation for every transport without protocol-level evidence.
7. The compatibility matrix SHALL run under the same build tags as the shipped client core — `release/DEFAULT_BUILD_TAGS`, which includes `with_quic`, `with_utls`, `with_sudoku`, `with_trusttunnel`, and `with_naive_outbound` — or the check silently skips the transports it means to test.
   - `with_naive_outbound` pulls the cronet stack and cannot be built on a desktop host; the Naive refusal is therefore covered by a test that skips only on the explicit "not included in this build" error, and by source evidence (`protocol/naive/outbound.go`).

### R5 — Review and commit local work

**User story:** As the repository owner, I want each pre-existing local change assessed before it is committed, so that unrelated or incomplete work is not sent to the remote.

1. BEFORE creating any commit, the work SHALL classify every pre-existing modified or untracked path as include, exclude, or needs clarification, with a reason and verification evidence.
2. WHEN a coherent subset is approved for inclusion THEN the work SHALL run relevant checks and create a descriptive local commit.
3. The work SHALL NOT push, publish a release, modify remote branches, or discard excluded changes without a separate explicit instruction.
4. Any change that stores secrets, build outputs, tool state, or unrelated experimentation SHALL be excluded from the proposed commit unless explicitly approved.

## Non-functional requirements

- **Security:** Update discovery and install paths must treat remote metadata and APKs as hostile until verified; pprof must remain opt-in or otherwise justified by an existing secure default.
- **Compatibility:** Android support remains minSdk 26; the 2.x change must not alter the 1.x update channel.
- **Quality:** UI changes reuse existing components; no formatter-only churn or unrelated refactor is allowed.
- **Evidence:** Every implementation slice has a focused build/test or reproducible check.

## Out of scope

- Publishing a release or pushing to any remote in this request.
- New release infrastructure beyond what in-app update discovery requires.
- Changing pprof endpoints, adding authentication, or moving the port from 9091 unless investigation proves the current ownership requires it.
- Changing subscription parser semantics or provider data.

## Open questions

1. The client currently has no update protocol. `canary` must therefore be a fixed, allowlisted channel in signed update metadata—not an arbitrary branch name. The metadata publication and key-rotation contract must be designed before implementation.
2. The remote `canary` branch exists, but the exact release/tag convention that identifies a release as canary must be defined before release-workflow changes.
3. **Resolved:** pprof is loopback-only and defaults to disabled; the setting is an explicit opt-in.
4. A local commit is authorized conditionally by R5; remote push is explicitly out of scope until requested.
