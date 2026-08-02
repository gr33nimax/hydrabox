# HydraCore integration

HydraCore is the native Android runtime used by HydraBox. The client pins one
published HydraCore release, source commit, checksum, and machine-readable
provenance document under `android/app/libs`.

The preferred native contract is `libbox.HydraCoreCapabilities()` with public
identity `io.hydrabox.hydracore`. A small set of inherited package, binding,
submodule, and artifact identifiers remain unchanged solely for source and
binary compatibility; see [CREDITS.md](../CREDITS.md).

Remote policy v2 is deliberately narrower than the native schema. It permits
only the versioned root fields and leaf client objects enumerated by the exact
installed HydraCore manifest. HydraBox additionally removes local-authority
fields, rejects unsafe or cyclic references, and runs native configuration
validation before activation. Unknown future JSON remains lossless in storage
but requires a later compatible policy before execution.

Policy v2 adds one bounded `wdtt` endpoint. Its native JSON contains only an
opaque `credential_ref`; the matching device grant is accepted only from an
authenticated Subscription v2 JWE, stored in Android Keystore-backed encrypted
Hive, and installed through the process-local libbox bridge immediately before
runtime start. The required runtime contract fixes worker groups at 9, recommends
18, caps steady state at 36, uses 15-minute leases refreshed after 10 minutes,
and supports hot rotation without restarting the VPN.

The HydraCore source contract is documented in the pinned submodule's
`HYDRACORE.md`. Build provenance is authoritative; a branch name or compatible
method alias is never sufficient evidence that an arbitrary AAR is trusted.
