# HydraBox

<div align="center">

[English](README.md) / [Русский](README_ru.md)

<img width="220" alt="HydraBox logo" src="assets/branding/hydrabox-logo.png" />

<img width="1672" height="941" alt="HydraBox interface" src="https://github.com/user-attachments/assets/c5a9780c-6b26-45e1-9458-42c23e204dde" />

[![Client checks](https://github.com/gr33nimax/hydrabox/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/gr33nimax/hydrabox/actions/workflows/ci.yml)
[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter)](#)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=flat-square)](LICENSE)

**Subscription-first Android client for the Hydra self-hosted VPN stack.**

</div>

HydraBox imports, refreshes, stores, and activates one encrypted subscription
from a server you control. [HYDRA Ultimate](https://github.com/gr33nimax/HYDRA-ULTIMATE)
produces that subscription; [HydraCore](https://github.com/gr33nimax/hydracore)
validates and executes its native networking configuration.

```text
HYDRA Ultimate  ->  encrypted subscription  ->  HydraBox  ->  HydraCore
self-hosted server                               client        runtime
```

Hydra is not a hosted VPN provider. HydraBox does not sell or provision
servers: you own the server and subscription.

## Status

HydraBox is in public beta. Android is the supported production target. Other
Flutter platform folders remain source-compatible development targets, not a
release promise.

## Features

- Android VPN TUN mode powered by HydraCore.
- Versioned HydraBox Subscription v1 with JWE A256GCM transport and lossless
  storage of the native runtime document.
- Fail-closed capability and remote-safety validation before activation.
- URL, QR, file, clipboard, and deep-link subscription import.
- Local HTTP/SOCKS mixed proxy for manual clients.
- Split tunnelling, DNS/routing controls, server latency checks, updater, and
  redacted diagnostics.
- Manual and legacy imports for migration and interoperability; the Hydra
  product contract remains the encrypted subscription.

## Quick start

1. Deploy HYDRA Ultimate on a server you control.
2. Copy its encrypted HydraBox subscription URL or QR code.
3. Install HydraBox from [GitHub Releases](https://github.com/gr33nimax/hydrabox/releases).
4. Import the subscription and connect.

The decryption key is carried only in the URL fragment and is not sent to the
subscription server. The exact schema, trust boundary, validation rules, and
test vectors are documented in
[HydraBox Subscription v1](docs/hydrabox-subscription-v1.md).

## Security model

HydraBox treats every remote subscription as untrusted input. Activation
requires authenticated JWE decryption, schema validation, an exact compatible
HydraCore policy manifest, removal of local-authority fields, a closed reference
graph, and native config validation. Unknown future fields remain storable but
cannot become executable merely because they exist in JSON.

Report vulnerabilities according to [SECURITY.md](SECURITY.md). Never attach
live subscription URLs, keys, credentials, device identifiers, or private
server addresses to a public issue.

## Development

The authoritative build and verification environment is GitHub Actions. It
checks the pinned HydraCore artifact and provenance, Flutter analysis/tests,
Android unit/lint/assembly gates, and CodeQL. Contributions target `main`; see
[CONTRIBUTING.md](CONTRIBUTING.md) and
[GitHub Actions](docs/github-actions.md).

## Credits and license

HydraBox began as a fork of
[Etonify](https://github.com/yamixdev/Etonify). We are grateful to MeowTeam and
all upstream contributors whose work made this project possible. HydraBox is
now maintained independently for the Hydra ecosystem while preserving the
complete source history, corresponding source, copyright notices, and
licenses. Exact lineage and retained compatibility identifiers are documented
in [CREDITS.md](CREDITS.md), [NOTICE.md](NOTICE.md), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The project is distributed
under [GPL-3.0-or-later](LICENSE).
