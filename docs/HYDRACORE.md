# HydraCore integration

HydraBox uses the published HydraCore Android runtime. The client pins the
release tag, source commit, AAR checksum, sources checksum, build inputs, and
machine-readable provenance under `android/app/libs`.

The required native contract is HydraCore API v2 with identity
`io.hydrabox.hydracore`. Startup fails closed if the runtime does not expose
config validation, runtime snapshots and events, managed URL-test sessions,
Subscription v2, JWE, remote policy v2, and the required protocol manifest.

Hydra Subscription v2 uses the discriminator `hydra.io/subscription/v2`.
HydraCore owns strict schema, remote-policy, reference-graph, permission, and
native-config validation. The client evaluates its own minimum version and
feature requirements, stores each resource independently, and activates only
the single resource selected by the current profile. Resources are never
merged.

`requested_permissions` is an internal compatibility declaration. HydraCore
and the client require it to exactly describe the resource authority:

- `network.outbound` for outbound objects;
- `network.endpoint.wireguard` for WireGuard endpoints;
- `network.inbound.call` for Call inbounds.

Supported exact declarations are accepted automatically while the subscription
is added. There is no permission prompt, grant screen, pending state, or later
approval step. Unknown, duplicate, missing, or over-declared permissions reject
the subscription.

Encrypted subscriptions use flattened JWE JSON with `alg=dir` and
`enc=A256GCM`. The 32-byte base64url key is carried only as `hydra-key` in the
URL fragment. The fragment is stripped from HTTP requests and diagnostics;
decryption and validation are delegated to HydraCore.

Runtime status, groups, and URL-test progress use the versioned HydraCore event
stream over one persistent command client. The polling interval is clamped to
the runtime contract and selected performance mode. URL tests are managed
sessions that can be inspected or cancelled without creating a second command
connection.

The exact portable contract is authoritative in the pinned HydraCore submodule:
`contract/subscription/HYDRA_SUBSCRIPTION_V2.md` and its JSON schemas.
