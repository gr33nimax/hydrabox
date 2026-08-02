# HydraBox changelog

## [0.3.0-beta.4]

- Established `hydrabox` as the canonical repository and public product name.
- Moved the stable product line to `main` and reduced the public branch surface.
- Added the canonical three-headed green HydraBox logo across repository and
  platform launcher assets.
- Consolidated source lineage, licenses, and retained compatibility identifiers
  in the credits and third-party notice set.
- Added HydraBox Subscription v2 and subscription-native WDTT endpoints.
- Added Keystore-backed device-grant persistence and a process-local HydraCore
  credential bridge; grants never enter native runtime JSON or profile exports.
- Added the 9/18/36 WDTT worker contract, 15-minute leases refreshed after
  10 minutes, and hot worker-generation rotation without a VPN restart.
- Added anonymous-first VK TURN acquisition with a native account/WebView
  fallback. Account TURN secrets remain process-local and refresh before their
  short lifetime expires; a notification requests login if the VK session ends.

## [0.3.0-beta.3]

- Fixed the Android status polling unit mismatch that could drive idle CPU and
  battery usage, and added native callback/notification performance counters.
- Added a cancellable, selected-server pre-connect URLTest session with no TUN
  or local inbounds.
- Added origin-scoped Android Hydra device IDs and strict JWE subscription
  transport headers with cross-origin redirect stripping.
- Replaced the proxy drawer with persistent Home, Servers, and More navigation,
  refreshed the Material 3 visual system, and regenerated platform icons from
  the canonical dotted green hydra.

## [0.3.0-beta.2]

- Added HydraBox Subscription v1 with authenticated JWE transport, explicit
  profiles, an opaque native runtime document, and fail-closed activation.
- Integrated the provenance-bound HydraCore runtime and capability contract.
- Added lifecycle, routing, import, updater, diagnostics, and Android release
  hardening for the Hydra self-hosted stack.

Earlier inherited release history remains available in Git and is intentionally
not presented as the HydraBox product changelog.
