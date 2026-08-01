# Contributing to HydraBox

Thank you for considering a contribution. HydraBox is early, Android-first,
and focused on stability before visual complexity. It is an independent
derivative of Etonify; see [UPSTREAM.md](UPSTREAM.md) for attribution and exact
baselines.

## Useful Contributions

- Android VPN runtime fixes.
- Subscription parser improvements.
- Deep-link import fixes.
- DNS/routing correctness tests.
- UI performance improvements that reduce rebuilds, memory pressure, or heat.
- Localization fixes.
- Security review and log-redaction improvements.

## Before Opening a Pull Request

GitHub Actions is authoritative for HydraBox. Open the pull request against
`extended-core` and wait for the client, Android, and security checks required
for the change. If you also run checks locally, the equivalent commands are:

Run:

```powershell
python -B scripts/fetch_libbox.py
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
- Changes to HydraBox Subscription v1 must keep the server, client, and
  HydraCore capability contract versioned and fail-closed.

## Communication

- Issues and pull requests in this repository are welcome.
- [@etonify](https://t.me/etonify) belongs to the upstream Etonify project and
  is retained here for attribution; it is not HydraBox support.
