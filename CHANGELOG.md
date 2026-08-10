# HydraBox changelog

## [0.4.0-beta.1]

- Switched the Android runtime to HydraCore
  `v1.13.16-extended-hydracore.6` and its versioned API v2 contract.
- Fixed native JWE subscription validation for the advertised and required
  `call_vk_multi_user` capability.
- Replaced the client-specific subscription formats with Hydra Subscription v2.
- Added independent multi-resource storage and deterministic single-resource
  profile activation.
- Separated app profile identities from resource-local sing-box tags, so
  resources that all expose `proxy` retain independent selection and latency.
- Fixed managed targeted URL tests for group entrypoints by keeping the native
  leaf probe internal while reporting the requested profile identity.
- Added the HydraCore VK Calls `multi_user` capability and outbound contract.
- Replaced the notification and Quick Settings glyph with the monochrome Hydra
  silhouette.
- Made `requested_permissions` an automatic fail-closed compatibility check;
  valid subscriptions are added without a user approval flow.
- Delegated Subscription v2, native config, and JWE validation to HydraCore.
- Adopted runtime snapshots, sequenced runtime events, and managed URL-test
  sessions over one persistent command connection.
- Removed obsolete transport and credential-bridge functionality.
- Changed the canonical Android application ID to `io.hydrabox.client` and the
  Dart package name to `hydrabox`.
- Removed obsolete inherited product aliases while preserving attribution and
  source-history credits.

## [0.3.0-beta.3]

- Fixed the Android status polling unit mismatch that could increase idle CPU
  and battery usage.
- Added cancellable pre-connect latency diagnostics.
- Added origin-scoped Android device IDs and strict encrypted subscription
  transport headers with cross-origin redirect stripping.
- Refreshed the navigation and Material 3 visual system.

## [0.3.0-beta.2]

- Integrated the provenance-bound HydraCore runtime.
- Added lifecycle, routing, import, updater, diagnostics, and Android release
  hardening for the Hydra self-hosted stack.

Earlier inherited release history remains available in Git.
