# Credits and source lineage

HydraBox is an independent client maintained for the Hydra self-hosted VPN
stack. It is not affiliated with or endorsed by any upstream project.

## Application lineage

HydraBox evolved from [`yamixdev/Etonify`](https://github.com/yamixdev/Etonify).
The imported application baseline is commit
`b0d311607ec024ca505c77ba7419f579b0edd0d6`. The retained Git history records
later authorship and modifications.

Original notice:

> Copyright 2026 MeowTeam.

HydraBox modifications are copyright 2026 HydraBox contributors.

## Runtime lineage

[HydraCore](https://github.com/gr33nimax/hydracore) is the maintained runtime
used by HydraBox. HydraCore retains its own complete lineage from sing-box,
sing-box-extended, and the mobile integration on which it was based. Exact
runtime commit, release tag, digest, toolchain, build tags, and download URL are
recorded in `android/app/libs/libbox.provenance.json`.

## Compatibility identifiers

The following inherited identifiers remain where an in-place rename could
break storage, native channels, backups, deep links, or signed upgrades:

- Android/Linux application ID and Kotlin namespace `com.etonify.meow_client`;
- Apple bundle identifiers and the Dart package name `meow_client`;
- platform-channel names beginning with `meow_client/`;
- legacy deep-link aliases, Hive locations, and backup magic;
- the `etonify-core` submodule path and `libbox.aar` artifact name.

These are compatibility interfaces, not public branding. Android package-name
continuity alone does not allow an independently signed APK to replace an
existing installation; the signing certificate or authorized signing lineage
must also match.

## License

HydraBox is distributed under [GPL-3.0-or-later](LICENSE). Original and
component-specific notices are preserved in [NOTICE.md](NOTICE.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Redistributors must provide
corresponding source and preserve all notices required by applicable licenses.
