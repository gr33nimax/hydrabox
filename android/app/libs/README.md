# HydraCore Android distribution

HydraBox pins the supported HydraCore Android release through four independent
authorities: the `hydracore` gitlink, release version, schema-v3 provenance,
and the SHA-256 digest of `libbox.aar`.

The AAR itself is intentionally not committed. GitHub Actions downloads the
published client-role asset `hydracore-client-libbox.aar` into the local
`libbox.aar` path, verifies it against `libbox.provenance.json` and
`libbox.sha256`, and only then builds or tests the client. Generated Java
sources are retained for API-surface inspection.

The required runtime identity is `io.hydrabox.hydracore`, role `client`, public
API version 2. The pinned client runtime exposes VK Calls multi-user outbound
wire v2 only; VPS inbound code is shipped separately. HydraBox does not use
deprecated capability aliases or fall back to older runtime and subscription
contracts.

Historical project lineage is preserved in `CREDITS.md`,
`THIRD_PARTY_NOTICES.md`, and the release provenance. It is not an active
application or runtime identity.
