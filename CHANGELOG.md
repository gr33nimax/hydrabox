# HydraBox changelog

## [0.5.0]

- Consolidated debug verification and test APK generation into one GitHub
  Actions job. HydraBox now consumes the verified HydraCore `debug` release AAR
  instead of rebuilding it in multiple workflows, while retaining exact source,
  provenance, digest, ABI and API checks.
- Unified manual and active-proxy latency checks behind one isolated URLTest
  path for every supported outbound protocol, including WireGuard, AnyTLS,
  Hysteria2, VLESS/XHTTP, and proxy chains.
- Replaced the floating server-list action with a toolbar refresh action and a
  visible in-progress state.
- Added live upload speed to compact traffic views and made upload/download
  totals independently monotonic when native snapshots arrive out of order.
- Fixed Wi-Fi/mobile handover recovery for long-lived VK Calls connections by
  preferring the callback network and resetting native route state in the VPN
  foreground service.
- Upgraded Android to HydraCore `v1.13.16-extended-hydracore.10-debug.2`, retaining the
  reusable XHTTP/network handover fixes and adding the authenticated VK Calls
  client telemetry required for protocol experiments.
- Switched the migrated default connectivity probe from Google to Cloudflare.

## [0.4.0-beta.1]

- Исправлен lifecycle default-network monitor: основной VPN runtime и
  standalone URLTest теперь зарегистрированы независимо. Закрытие latency
  probe больше не отцепляет VPN listener и не создаёт ложный `network_changed`.
- Native Calls получает немедленный Hydracore rebind при Wi-Fi/mobile handover;
  worker transports пересоздаются без потери логического KCP/RelayBridge.
- Клиент проверяет role-specific Hydracore contract (`client`, multi-user-only,
  wire v2) и загружает отдельный `hydracore-client-libbox.aar`.
- Adaptive launcher artwork уменьшен до безопасной 64dp-зоны, чтобы OEM mask
  не растягивала и не обрезала головы Hydra.

- Switched the Android runtime to the client-role HydraCore
  `v1.13.16-extended-hydracore.7` and its versioned API v2 contract.
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
