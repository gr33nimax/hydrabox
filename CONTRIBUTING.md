# Contributing to HydraBox

HydraBox is Android-first and prioritizes subscription safety, runtime
correctness, and daily stability.

Useful contributions include Android VPN lifecycle fixes, subscription parser
and deep-link improvements, DNS/routing tests, UI performance work,
localization, security review, and log redaction.

## Pull requests

- Target `main` and keep the change scoped.
- Do not include live subscription links, UUIDs, passwords, tokens, device
  identifiers, private addresses, or customer data.
- Describe the Android scenario for VPN lifecycle, profile switching,
  subscription refresh, split tunnelling, or DNS changes.
- Version HydraBox Subscription and HydraCore policy changes explicitly and
  keep remote activation fail-closed.
- Do not rename retained compatibility identifiers without a complete storage,
  signing, native-channel, and migration plan.

GitHub Actions is authoritative. A change is ready only when the client,
Android, and security checks required for its scope pass.

Issues and pull requests in this repository are the HydraBox support channel.
Source lineage and upstream contacts are recorded only for attribution in
[CREDITS.md](CREDITS.md).
