# HydraCore libbox binary

HydraCore uses
[`gr33nimax/hydracore`](https://github.com/gr33nimax/hydracore/tree/extended-integration),
based directly on the `shtorm-7/sing-box-extended` `extended` line. The AAR
contains the complete four-ABI Android build and every protocol/service tag
recorded in `libbox.provenance.json`.

`HydraCore` is a public distribution name only. The compatibility submodule
path and artifact name remain unchanged, while machine-readable provenance
records both the HydraCore distribution identity and its Etonify lineage so
that the original source and license chain is never obscured.

The pinned release exports `HydraCoreCapabilities()` directly and retains
`EtonifyCapabilities()` as a deprecated compatibility alias. HydraBox does not
invent a remote-execution policy for older binaries: encrypted remote
documents remain fail-closed unless the installed AAR itself advertises the
versioned HydraCore policy.

The binary is intentionally generated rather than committed to this public
fork. From the repository root, hydrate the pinned release asset before an
Android build:

```shell
python -B scripts/fetch_libbox.py
python -B scripts/verify_libbox.py
```

`libbox.sha256` pins the exact AAR. `libbox.provenance.json` additionally pins
the release URL and size, source repository/branch/commit, published build
toolchain, Android API, build tags, and the preserved Etonify version. Both the
fetcher and Android `preBuild` reject a missing, stale or modified archive.
