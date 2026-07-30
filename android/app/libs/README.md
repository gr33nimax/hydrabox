# libbox binary

This fork uses
[`gr33nimax/etonify-core`](https://github.com/gr33nimax/etonify-core/tree/extended-integration),
based directly on the `shtorm-7/sing-box-extended` `extended` line. The AAR
contains the complete four-ABI Android build and every protocol/service tag
recorded in `libbox.provenance.json`.

The binary is intentionally generated rather than committed to this public
fork. From the repository root, hydrate the pinned release asset before an
Android build:

```shell
python -B scripts/fetch_libbox.py
python -B scripts/verify_libbox.py
```

`libbox.sha256` pins the exact AAR. `libbox.provenance.json` additionally pins
the release URL and size, source repository/branch/commit, toolchain, Android
API and build tags. Both the fetcher and Android `preBuild` reject a missing,
stale or modified archive.
