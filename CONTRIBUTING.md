# Contributing to Etonify

Thank you for considering a contribution. Etonify is early, Android-first, and focused on stability before visual complexity.

## Useful Contributions

- Android VPN runtime fixes.
- Subscription parser improvements.
- Deep-link import fixes.
- DNS/routing correctness tests.
- UI performance improvements that reduce rebuilds, memory pressure, or heat.
- Localization fixes.
- Security review and log-redaction improvements.

## Before Opening a Pull Request

Run:

```powershell
flutter gen-l10n
flutter analyze
flutter test
```

For Android runtime changes, also build a release APK:

```powershell
$env:MEOW_ALLOW_DEBUG_RELEASE_SIGNING='true'
flutter build apk --release
```

## Pull Request Notes

- Keep changes scoped.
- Do not include real subscription links, UUIDs, passwords, tokens, HWID, or private server data in tests or screenshots.
- Prefer small, verifiable fixes over broad rewrites.
- If a change touches VPN start/stop, server selection, subscription refresh, split tunneling, or DNS, describe the manual Android test scenario.

## Communication

- Telegram channel: [@etonify](https://t.me/etonify)
- Issues and pull requests are welcome.
