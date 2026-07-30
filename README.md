# Etonify

<div align="center">

[English](README.md) / [Русский](README_ru.md) / [Українська](README_uk.md) / [简体中文](README_cn.md) / [فارسی](README_fa.md)

<img width="1672" height="941" alt="etonify" src="https://github.com/user-attachments/assets/c5a9780c-6b26-45e1-9458-42c23e204dde" />

[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter)](#)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=flat-square)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-@etonify-26A5E4?style=flat-square&logo=telegram)](https://t.me/etonify)

**Android-first open-source VPN client built around a modified sing-box core.**

</div>

Etonify is an Android-focused VPN client for people who need a transparent, maintainable, and community-driven alternative to legacy VPN clients. Its Android runtime, subscription handling, UI, diagnostics, and maintenance flow are developed around Etonify and the [extended sing-box core](docs/EXTENDED_CORE.md). Complete sing-box JSON documents are passed through losslessly, so protocols and fields added by the core do not require a matching Flutter release.

The app does not provide VPN servers. It is a client for subscriptions and configurations that you own or are allowed to use.

## Status

Etonify is in early public development. Android is the only production target right now. Other Flutter platform folders may exist in the repository, but they are not release targets yet.

## Features

- Android VPN TUN mode powered by the extended `etonify-core` integration.
- Local mixed proxy inbound for apps or devices that use HTTP/SOCKS manually.
- Subscription import from URL, QR code, local file, clipboard, and deep links.
- Deep link handlers for `etonify://`, `happ://add`, `happ://crypt*`, and `sing-box://import-remote-profile`.
- Happ link decryptor for `crypt`, `crypt2`, `crypt3`, `crypt4`, and `crypt5` links.
- Happ subscription import with explicit HWID consent when a provider requires it.
- Subscription refresh, reparse, usage display, expiration display, and safe handling of invalid refresh results.
- Proxy list with country flags, latency, source-order sorting, latency/name/country sorting, URL-test, and quick server switching.
- Split tunneling using Android VPN app allow/disallow rules plus sing-box routing fallback.
- DNS presets and custom DNS resolver support, including UDP, TCP, DoT, DoH, and device DNS modes.
- Smart Routing rule sets and a locally compiled AdGuard DNS filter.
- Traffic dashboard with live speed, session totals, active profile, active proxy, and a lightweight graph.
- GitHub release update center with ABI-aware APK selection and download progress.
- Runtime logs, diagnostics, memory cleanup hooks, and redaction for known sensitive values.
- RU/EN app localization, with more user-facing translations planned.

## Community

- Telegram channel: [@etonify](https://t.me/etonify)
- Direct contact with the developers: [Etonify Direct](https://t.me/etonify?direct)
- MeowTeam: YamixDEV works on the Android client, releases, and [etonify-core](https://github.com/yamixdev/etonify-core/tree/etonify-dev); [dudosxdev](https://github.com/dudosxdev) contributes networking and protocol expertise.
- Issues and pull requests are welcome.
- Security reports are welcome. Please avoid publishing exploitable details publicly before the team has time to investigate.

## Development

Requirements:

- Flutter 3.44.0 or newer with Dart `>=3.11.4`.
- Android SDK 36.
- JDK 21 can be used to run Gradle, while Android bytecode targets remain Java 17 for current AGP compatibility.

Common commands:

```powershell
python -B scripts/fetch_libbox.py
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

Local release APK for device testing:

```powershell
$env:MEOW_ALLOW_DEBUG_RELEASE_SIGNING='true'
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

For public distribution, create a real release keystore and `android/key.properties`. That file is intentionally ignored by Git.

## Notes

- Production focus is Android.
- This fork hydrates `libbox.aar` from the pinned
  [`gr33nimax/etonify-core`](https://github.com/gr33nimax/etonify-core/tree/extended-integration)
  prerelease. Its source commit, release URL, SHA-256 and build provenance are
  documented under `android/app/libs` and verified before every Android build.
- Generated l10n files under `lib/l10n/generated` are part of the source tree because the app imports them directly.
- `third_party/flutter_circle_flags` is required by `pubspec.yaml` as a local path dependency.
- Third-party attribution notes are tracked in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Official release builds can include private Happ crypto compatibility assets restored from GitHub Actions secrets. These assets are not part of the public source tree.

## License

Etonify is licensed under the [GNU General Public License v3.0 or later](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for bundled and adapted components.
