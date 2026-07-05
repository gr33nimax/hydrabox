# Etonify Notices

Etonify is developed by MeowTeam and is intended to be licensed under Apache License 2.0 for original project code.

## Third-Party Components

- `third_party/flutter_circle_flags` is based on `circle_flags`, distributed under the MIT License. Its license is preserved in `third_party/flutter_circle_flags/LICENSE`.
- Etonify bundles a modified sing-box/libbox core maintained by dudosxdev: https://github.com/dudosxdev/sing-box. The core and its dependencies remain subject to their own licenses.
- Etonify uses Flutter, Android Gradle Plugin, Kotlin, sing-box/libbox integration, and other dependencies listed in `pubspec.yaml`, Gradle files, and generated lock files. Their own licenses remain applicable.

## Private Compatibility Assets

Official Etonify release builds may include private Happ crypto compatibility assets restored from GitHub Actions secrets at build time. These assets are not part of the public source tree and are not covered by the public repository contents.

APK obfuscation and minification are used for official release builds to reduce casual repackaging and reverse engineering, but bundled APK assets should not be treated as cryptographically secret.

## Historical Context

Etonify has historical project lineage and UI/runtime ideas that were originally explored around Hiddify-style clients. The current goal is to maintain Etonify as its own Android-first client with original runtime, subscription, diagnostics, and UI work.

Before a public binary release, review any remaining legacy source files and third-party assets to confirm license compatibility with Apache License 2.0.
