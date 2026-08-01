# HydraCore

HydraCore is the public runtime name used by HydraBox for the extended
sing-box/libbox integration in this repository.

HydraCore is not an independent clean-room core and makes no claim to upstream
authorship. It is based on
[`gr33nimax/etonify-core`](https://github.com/gr33nimax/etonify-core/tree/extended-integration),
which in turn is based on extended sing-box. The pinned source baseline in this
tree is recorded in [UPSTREAM.md](../UPSTREAM.md), and the Android artifact's
complete machine-readable provenance is retained in
`android/app/libs/libbox.provenance.json`.

The source now exposes `libbox.HydraCoreCapabilities()` as the primary
versioned mobile contract and identifies itself as `io.hydrabox.hydracore`.
Its capability document also retains `upstream_project: "etonify-core"`.
`libbox.EtonifyCapabilities()` remains a deprecated alias for already-generated
bindings. The technical submodule path `etonify-core`, Go module paths, and
artifact name `libbox.aar` remain ABI and source-compatibility interfaces.

The pinned compatibility AAR in this checkout predates that new exported
method. HydraBox's Android bridge therefore accepts the legacy alias and adds
the same HydraCore identity fields without hiding `upstream_project`. For the
exact pinned core version and build-verified AAR SHA only, the application also
attaches its own policy-v1 classification and records that adapter as
`remote_policy_source`. Any other legacy binary remains fail-closed. This is an
application trust decision, not a claim that the old binary published a
HydraCore manifest. A fresh AAR built from the current core source exports
`HydraCoreCapabilities()` and the same policy-v1 manifest directly; its release
workflow is named HydraCore and retains Etonify build provenance in the
generated metadata.

Remote policy v1 is intentionally narrower than sing-box schema support. It
authorizes only `$schema`, native `outbounds`/`endpoints`, a fixed set of leaf
client protocols, and userspace WireGuard. HydraBox separately rejects local
paths/interfaces/plugins and unsafe/cyclic references, then runs native config
validation. Unknown future protocol JSON remains lossless in the subscription
store but requires a later policy version before activation.

The same provenance and compatibility policy is recorded inside the core tree
in `etonify-core/HYDRACORE.md`; `etonify-core/ETONIFY_CORE.md` remains intact as
the historical integration and pinned-build record.

HydraCore and its inherited components remain GPL-3.0-or-later. See
[LICENSE](../LICENSE), [NOTICE.md](../NOTICE.md), and
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

For enabled protocol surfaces, validation boundaries, reproducible builds and
the exact pinned artifact workflow, see
[Extended core compatibility](EXTENDED_CORE.md).
