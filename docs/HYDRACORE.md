# HydraCore integration

HydraCore is the native Android runtime used by HydraBox. The client pins one
published HydraCore release, source commit, checksum, and machine-readable
provenance document under `android/app/libs`.

The preferred native contract is `libbox.HydraCoreCapabilities()` with public
identity `io.hydrabox.hydracore`. A small set of inherited package, binding,
submodule, and artifact identifiers remain unchanged solely for source and
binary compatibility; see [CREDITS.md](../CREDITS.md).

Remote policy v1 is deliberately narrower than the native schema. It permits
only the versioned root fields and leaf client objects enumerated by the exact
installed HydraCore manifest. HydraBox additionally removes local-authority
fields, rejects unsafe or cyclic references, and runs native configuration
validation before activation. Unknown future JSON remains lossless in storage
but requires a later compatible policy before execution.

The HydraCore source contract is documented in the pinned submodule's
`HYDRACORE.md`. Build provenance is authoritative; a branch name or compatible
method alias is never sufficient evidence that an arbitrary AAR is trusted.
