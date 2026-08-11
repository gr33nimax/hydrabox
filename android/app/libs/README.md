# HydraCore Android distribution

HydraBox pins the supported HydraCore Android release through four independent
authorities: the `hydracore` gitlink, release version, schema-v3 provenance,
and the SHA-256 digest of `libbox.aar`.

The AAR itself is intentionally not committed. Branch verification reproduces
the client-role AAR from the exact pinned gitlink with the release toolchain,
then verifies its digest against `libbox.provenance.json` and
`libbox.sha256` before building the client. Published releases remain the
normal hydration source outside this branch workflow. Generated Java sources
are retained for API-surface inspection.

The required runtime identity is `io.hydrabox.hydracore`, role `client`, public
API version 2. The pinned client runtime exposes VK Calls multi-user outbound
wire v2 and authenticated telemetry only; VPS inbound code is shipped
separately. HydraBox does not use deprecated capability aliases or fall back
to older runtime and subscription contracts.

Historical project lineage is preserved in `CREDITS.md`,
`THIRD_PARTY_NOTICES.md`, and the release provenance. It is not an active
application or runtime identity.
