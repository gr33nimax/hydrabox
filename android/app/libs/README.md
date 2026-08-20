# HydraCore Android distribution

HydraBox pins the supported HydraCore Android release through four independent
authorities: the `hydracore` gitlink, release version, schema-v3 provenance,
and the SHA-256 digest of `libbox.aar`.

The AAR itself is intentionally not committed. The `debug` branch downloads the
client-role AAR published by the exact pinned HydraCore `debug` commit, then
verifies its digest against `libbox.provenance.json` and `libbox.sha256` before
building the client. HydraCore performs the expensive reproducible AAR build
once; HydraBox consumes that verified release artifact without rebuilding it in
parallel workflows. Generated Java sources are retained for API-surface
inspection.

The required runtime identity is `io.hydrabox.hydracore`, role `client`, public
API version 2. Bundle manifests with core API major 1 and 2 are accepted during
the staged capability-contract migration; the isolated runtime probe still must
report the exact API major implemented by the running HydraBox process. VPS code
is shipped separately. HydraBox does not use deprecated capability aliases or
fall back to older subscription contracts.

Historical project lineage is preserved in `CREDITS.md`,
`THIRD_PARTY_NOTICES.md`, and the release provenance. It is not an active
application or runtime identity.
