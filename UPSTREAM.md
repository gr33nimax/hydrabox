# Upstream provenance

HydraBox is an independent, unofficial derivative of Etonify. HydraCore is
the public name used by HydraBox for its extended sing-box runtime, which is
based on `etonify-core`.

This project does not claim authorship, ownership, endorsement, or affiliation
with Etonify, MeowTeam, sing-box, or their maintainers. Their copyright notices
and licenses remain in place.

## Pinned baselines

| HydraBox component | Upstream source | Baseline in this tree |
| --- | --- | --- |
| HydraBox application | [`yamixdev/Etonify`](https://github.com/yamixdev/Etonify) | `b0d311607ec024ca505c77ba7419f579b0edd0d6` |
| HydraCore runtime | [`gr33nimax/hydracore`](https://github.com/gr33nimax/hydracore/tree/extended-integration), itself derived from extended sing-box | `a52ab5c0e8aeabd8b5057f85ca518796ce2c57ed` |

The commit history records later HydraBox changes. Binary core provenance,
including the exact source commit, release asset, SHA-256, toolchain and build
tags, is retained in `android/app/libs/libbox.provenance.json`.

## Compatibility identifiers retained intentionally

The first HydraBox releases keep the following identifiers:

- Android application ID and Kotlin namespace `com.etonify.meow_client`;
- Linux GTK application ID `com.etonify.meow_client`, iOS/macOS bundle ID
  `com.etonify.meowClient`, and the existing iOS URL-role identifier;
- Dart package name `meow_client`;
- platform-channel names beginning with `meow_client/`;
- existing `etonify://` and `meowvpn://` deep-link aliases;
- existing encrypted Hive locations and backup magic;
- Android artifact name `libbox.aar` and the `etonify-core` submodule path.

These compatibility identifiers are distinct from public build names. Current
desktop artifacts use `hydrabox` for the Windows and Linux executable and
`HydraBox.app` on macOS; the legacy application, bundle, and URL-role IDs remain
solely to avoid an unnecessary storage/integration migration.

Changing those identifiers in place can break Keystore-bound storage, backups,
native channel communication, installed deep links, and an authorized signed
upgrade path. Keeping them is only one part of Android upgrade compatibility:
an independently signed APK still cannot replace Etonify without an authorized
matching signing certificate or signing lineage. HydraBox adds its own public
name and `hydrabox://` deep-link alias while retaining the old identifiers as
compatibility interfaces. A future breaking identifier migration must include
explicit data and key migration.

The in-app legal, welcome, home-title, and connection-button surfaces and the
platform launcher/status resources use repository-native HydraBox marks rather
than the inherited upstream SVG. Store-specific artwork review remains a
separate release-preparation item for each platform.

## Licensing

The project-level [LICENSE](LICENSE) remains GPL-3.0-or-later. Original notices
are preserved in [NOTICE.md](NOTICE.md), component notices in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and nested dependencies keep
their own license files. Renaming a component does not replace or weaken any
of those terms.
