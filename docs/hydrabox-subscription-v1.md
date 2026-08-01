# HydraBox Subscription v1

Status: **draft 0.3 / fail-closed compatibility profile**

HydraBox Subscription is a versioned envelope for one native sing-box runtime
document plus an explicit list of user-facing profiles. It is designed around
four invariants:

1. `profiles` is the only source of entries shown in the proxy selector.
2. Native `outbounds` and `endpoints` are runtime objects, not profiles.
3. An accepted sing-box document remains opaque to the envelope schema and is
   preserved in full; HydraCore is the protocol-schema authority.
4. Confidential transport uses standard JWE and is fail-closed. A key-bearing
   source cannot silently become plaintext or fall back to a legacy parser.

The envelope schema does not enumerate protocols. A future HydraCore outbound
such as:

```json
{
  "type": "future-protocol",
  "tag": "future-main",
  "future_option": {"kept": true}
}
```

remains valid at the envelope/storage layer and is retained losslessly. Runtime
activation is a separate, versioned permission decision. Remote policy v1
activates only the exact leaf protocol set listed below; an unknown future type
stays stored but cannot run until a later policy version classifies its fields,
references, and side effects. HydraCore schema validation is the final syntax
and compatibility check, not a grant of local-process authority.

## Media types and files

Plain subscription data:

```text
application/vnd.hydrabox.subscription+json
```

Encrypted JWE JSON:

```text
application/jose+json
```

Suggested file extensions:

```text
.hbx.json       plaintext data
.hbx.jwe.json   encrypted JWE JSON
```

HydraBox wire files are strict UTF-8. A UTF-16 BOM may still be accepted for
legacy subscription formats, but it is rejected for plaintext HydraBox and
flattened JWE. An HTTP `Content-Type` is also a fail-closed discriminator:
`application/vnd.hydrabox.subscription+json` must contain plaintext v1, while
`application/jose+json` must contain authenticated JWE and requires its key.
Parameters and media-type case do not weaken this rule.

An encrypted file still needs its 32-byte key through a separate trusted
channel. The key is never embedded in the encrypted file itself. The current
HydraBox UI accepts encrypted subscriptions through a key-bearing HTTPS
URL/QR. The standalone parser can authenticate encrypted file content when a
caller supplies the key explicitly, but persistent encrypted file import fails
closed until HydraBox has Keystore-backed per-file key storage and a restore
prompt. There is no file-key prompt in the v1 UI.

## Plain SubscriptionData

```json
{
  "api_version": "hydrabox.io/subscription/v1",
  "kind": "SubscriptionData",
  "issuer": "https://provider.example",
  "subscription_id": "customer-main",
  "channel": "stable",
  "sequence": 42,
  "issued_at": "2026-07-30T18:00:00Z",
  "not_before": "2026-07-30T17:55:00Z",
  "expires_at": "2026-08-30T18:00:00Z",
  "default_profile_id": "trojan-shadowtls",
  "metadata": {
    "name": {
      "default": "HydraBox Demo",
      "ru": "Демонстрационная подписка"
    },
    "homepage": "https://provider.example",
    "support_url": "https://provider.example/support"
  },
  "compatibility": {
    "client": {
      "min_version": "1.0.0",
      "required_features": []
    },
    "core": {
      "id": "io.hydrabox.hydracore",
      "version_range": ">=1.13.14 <2.0.0",
      "required_features": [
        "io.hydrabox.hydracore/outbound/trojan",
        "io.hydrabox.hydracore/outbound/shadowtls"
      ]
    }
  },
  "update": {
    "url": "https://provider.example/customer-main",
    "minimum_interval_seconds": 21600
  },
  "runtime": {
    "format": "sing-box-json",
    "ownership": {
      "inbounds": "client",
      "route_final": "selected-profile",
      "dns": "merge-safe",
      "route_rules": "merge-safe",
      "log": "client-overlay",
      "global": "client-overlay"
    },
    "document": {
      "outbounds": [
        {
          "type": "trojan",
          "tag": "trojan-main",
          "server": "origin.example.invalid",
          "server_port": 443,
          "password": "not-a-real-secret",
          "detour": "shadowtls-transport"
        },
        {
          "type": "shadowtls",
          "tag": "shadowtls-transport",
          "server": "transport.example.invalid",
          "server_port": 443,
          "version": 3,
          "password": "not-a-real-secret",
          "tls": {
            "enabled": true,
            "server_name": "cover.example.invalid"
          }
        }
      ]
    }
  },
  "profiles": [
    {
      "id": "trojan-shadowtls",
      "name": {
        "default": "Trojan over ShadowTLS"
      },
      "entrypoint": {
        "section": "outbounds",
        "tag": "trojan-main"
      },
      "enabled": true,
      "required_features": []
    }
  ],
  "required_extensions": [],
  "extensions": {}
}
```

The checked-in example uses reserved `.invalid` hosts and cannot connect to a
real server. Its `compatibility` and `update` objects are declarative metadata;
their current implementation status is described below.

## Profiles and runtime objects

A profile is stable publisher/UI identity:

```text
profile.id = trojan-shadowtls
profile.entrypoint = outbounds/trojan-main
```

The referenced outbound and its ShadowTLS detour are native runtime identity:

```text
trojan-main.detour -> shadowtls-transport
```

The result is unambiguous:

```text
Visible profiles: trojan-shadowtls
Runtime objects:  trojan-main, shadowtls-transport
```

HydraBox does not infer v1 profiles from `route.final`, selectors, detours, or
protocol names. Legacy sing-box imports may retain compatibility heuristics,
but those heuristics are not part of this format.

Every enabled profile entrypoint must resolve exactly once. v1 forbids two
profiles from naming the same entrypoint. A later format may add an explicit
alias model without overloading native objects.

## One native document

v1 intentionally contains one `runtime.document`.

Independent sing-box documents can have incompatible DNS, route, listener,
provider and service policies. Automatically merging them would require an
older client to discover every reference field of every future protocol, which
is impossible to do losslessly. Providers should publish independent graphs as
independent subscriptions.

A future `SubscriptionBundle` kind may carry multiple independently secured
child subscriptions. It must not redefine v1 document-merging behavior.

## Runtime ownership

Remote configuration is active code-like input. It can otherwise declare local
listeners, files, providers and services. The v1 compatibility profile fixes
client ownership to the following values:

```json
{
  "inbounds": "client",
  "route_final": "selected-profile",
  "dns": "merge-safe",
  "route_rules": "merge-safe",
  "log": "client-overlay",
  "global": "client-overlay"
}
```

- Omitting `runtime.ownership` means exactly these fixed defaults; it does not
  grant the publisher additional authority. If the object is present, all six
  values must match this object.
- HydraBox owns every local inbound, including Android TUN and mixed inbounds.
- The selected profile entrypoint becomes the effective route target.
- DNS, route rules, route final, logging and global runtime settings remain
  client-owned. The ownership keys reserve these semantics for compatible
  later policies; remote policy v1 does not activate publisher `dns`, `route`,
  `log`, `ntp`, or `global` top-level sections.
- Protocol-specific fields inside allowed native objects are retained, but
  local-process authority is filtered separately from protocol validation.

Until HydraBox has a separate, explicit local-consent mechanism, v1 rejects a
remote document containing any of the following:

- `inbounds`, `services`, or `experimental` sections;
- a local-file provider or a v1-reserved local-authority field such as a
  certificate/key/config/database/socket path, state directory, command, or
  executable reference;
- a listener, management API, profiler, command, or executable supplied through
  an extension or an otherwise opaque native field.

Remote policy v1 rejects every non-empty `providers` collection, every
`route.rule_set`, and all GeoIP/Geosite downloads. Those later responses would
be separate trust boundaries not protected by the enclosing JWE sequence or
AEAD tag. A provider/resource feature requires a later policy with recursive
validation; HydraCore merely recognizing its schema is insufficient. A
publisher signature would establish publisher identity, not local consent.

The exact v1 activation manifest is deliberately small:

```text
top level:  $schema, outbounds, endpoints
outbounds:  socks, http, vmess, trojan, naive, shadowtls, vless, mieru,
            anytls, trusttunnel, hysteria, hysteria2, tuic, sudoku, snell
endpoints:  wireguard (userspace only)
DNS/providers/rule sets: none
```

For v1, `wireguard` means the userspace endpoint and classic AmneziaWG
parameters (`jc`, `jmin`, `jmax`, `s1..s4`, and `h1..h4`). qWDTT `i1..i5`,
`j1..j3`, and `itime` are outside this policy and are rejected before the
document reaches HydraCore. They are neither interpreted nor rewritten.

`direct`, `block`, selector/url-test/fallback groups, `shadowsocks` plugins,
`ssh`, `openvpn`, `masque`, `warp`, parser/tor/composite/limiter types, and
reverse VPN/service endpoints are not remote-safe in policy v1. The client
also rejects local path/interface/plugin fields, references to client-owned
tags, composite nested graphs, and detour cycles. A freshly built HydraCore
must advertise the same versioned manifest. The pinned legacy AAR is not given
a synthetic manifest and therefore cannot activate HydraBox remote runtime
documents.

The application reserves native tags beginning with `__hydrabox.` and the
current app-owned outbound tags `select`, `direct`, `lowest`, `lowest-open`,
`lowest-free`, and `mixed`. A publisher must not use any of them anywhere in
the combined native `outbounds` + `endpoints` namespace, including on helper
objects that are not profiles. HydraBox v1 never renames an accepted native
tag: a collision is rejected, and a persisted tag-identity mismatch stops
runtime assembly fail-closed. HydraBox never rewrites an accepted native tag.
For activation, policy v1 treats canonical reference fields such as `detour`,
`outbound`, `endpoint`, and `outbounds` semantically: references must remain
inside the same remote graph, composite fields are rejected, and cycles fail
closed. A future protocol that gives those fields different semantics needs a
new policy version; its original JSON remains retained in storage meanwhile.

The envelope therefore has no protocol allowlist, while the executable remote
policy intentionally does. A profile still has to materialize as a selectable
current-schema entrypoint; WireGuard profiles use a native top-level
`endpoints` object rather than the removed outbound form.

## Structural validation

Before accepting a document, a client must:

1. Require strict UTF-8 and reject duplicate JSON keys.
2. Enforce the v1 wire and nesting limits before an unbounded JSON decode.
3. Require the exact `api_version` and `kind`; never fall back to a legacy
   parser after seeing a HydraBox/JWE discriminator or an `hbx-key` hint.
4. Require an HTTPS fetch URL. `issuer` must be an HTTPS origin without
   userinfo, path (other than `/`), query, or fragment. Metadata and update URLs
   must use HTTPS and contain no userinfo or fragment.
5. Validate string identifiers, RFC 3339 timestamps and `sequence` without
   lossy coercion or calendar normalization. Identifiers and native tags must
   not contain control characters or surrounding whitespace.
6. Reject unknown envelope, runtime, profile and entrypoint fields. Optional
   future data belongs in the relevant `extensions` object.
7. Reject an unknown member of `required_extensions`.
8. Require unique profile IDs.
9. Require native tags to be unique across the combined
   `outbounds` + `endpoints` namespace and reject every client-owned tag.
10. Resolve every enabled entrypoint exactly once in its declared section.
11. Require `default_profile_id` to name an enabled profile.
12. Preserve the complete accepted native document; do not extract a guessed
    dependency closure, rename native tags, or rewrite unknown native fields.
13. Require an exact, integer-versioned HydraCore capability contract and its
    remote-policy manifest. A legacy or synthetic manifest is insufficient.
14. Apply the v1 top-level/type allowlists, recursively reject local authority,
    validate the closed reference graph, assemble a temporary client-owned
    runtime, and run HydraCore `checkConfig` before activation.

JSON Schema validates the portable shape. Cross-reference, uniqueness, trust,
time and HydraCore checks are runtime requirements.

## Extensions

The envelope is strict. Extensibility is explicit:

```json
{
  "required_extensions": [
    "com.provider.device-binding/v1"
  ],
  "extensions": {
    "com.provider.device-binding/v1": {
      "mode": "attested"
    },
    "com.provider.labels/v1": {
      "tier": "premium"
    }
  }
}
```

Extension names must use the schema's controlled reverse-DNS namespace.

- Unknown optional extensions are retained and ignored.
- Unknown required extensions reject the document.
- An extension cannot weaken core v1 security, identity or runtime-ownership
  invariants.

## Declarative compatibility and update metadata

`compatibility` and `update` are versioned, strictly validated and retained so
future clients can act on them without changing the v1 wire shape. In the
current compatibility implementation they are declarative:

- `compatibility.client.min_version`, `compatibility.core.version_range`, and
  all `required_features` lists are not capability gates. HydraCore's final
  configuration check remains authoritative.
- `update.url` is not followed and cannot silently change the trusted source;
  refresh continues to use the user-imported URL.
- `update.minimum_interval_seconds` is only a scheduling hint. It cannot weaken
  local refresh limits or any trust decision.

Providers must not rely on these fields to make an otherwise unsafe or
unsupported document acceptable. Enforcing them later requires a separately
versioned capability registry and update-source transition policy.

## Encrypted transport: JWE

HydraBox does not define a custom cipher container. The supported shared-secret
profile is flattened JWE JSON Serialization (RFC 7516):

```json
{
  "protected": "BASE64URL(PROTECTED_HEADER)",
  "iv": "BASE64URL_12_BYTE_IV",
  "ciphertext": "BASE64URL_CIPHERTEXT",
  "tag": "BASE64URL_16_BYTE_TAG"
}
```

The protected header is:

```json
{
  "alg": "dir",
  "enc": "A256GCM",
  "typ": "hbx+jwe",
  "cty": "application/vnd.hydrabox.subscription+json",
  "kid": "customer-key-2026-01"
}
```

Normative rules:

- The content-encryption key is exactly 32 random bytes.
- The IV is 12 fresh random bytes for every encryption.
- The authentication tag is 16 bytes.
- JWE additional authenticated data is the ASCII base64url protected-header
  value, as defined by JWE.
- Padding in base64url members is forbidden.
- `zip` and all compression are forbidden in v1.
- Algorithm negotiation is forbidden: `dir` + `A256GCM` is the only suite in
  this profile.
- The client verifies the AEAD tag before parsing plaintext.
- The strict v1 JSON profile has no unprotected header, external `aad`,
  recipient array, compression, or non-empty encrypted key. With `alg=dir`,
  the JWE Encrypted Key is empty and the `encrypted_key` member is absent.
- A malformed or unsupported JWE is an error. It is never reinterpreted as a
  plaintext HydraBox document, native sing-box document, or legacy format.

### Key delivery

For an HTTPS subscription, a shared key may be delivered through a trusted QR
code or deep link:

```text
https://provider.example/customer-main#hbx-key=BASE64URL_32_BYTES
```

The URL fragment:

- contains exactly one non-empty `hbx-key` value; an empty, duplicated or
  malformed value is an error and still keeps the source in fail-closed mode;
- is stripped before every HTTP/native fetch;
- is never sent as a query parameter, header or log field. Any `hbx-key`
  query parameter (including encoded/case variants) is rejected before a
  network request and before persistence;
- is stored in Android only inside the application's Keystore-backed encrypted
  subscription storage. Another platform must provide equivalent protected
  storage before persisting a key-bearing URL;
- must not be returned by the subscription endpoint.

The network URL must itself use HTTPS. If an imported source contains
`hbx-key`, HydraBox requires the response to be a valid v1 JWE authenticated by
that key. Plaintext, malformed JOSE, unsupported algorithms, and legacy
subscription bodies are rejected even during the first import. This key hint
is therefore also an encryption-policy signal, not merely an optional decoder
parameter.

Possession of a shared `dir` key provides confidentiality and AEAD integrity
against parties without that key. It does not prove which holder published the
document.

### Publisher signatures

Publisher identity is a separate property. The production multi-device
security profile will use nested JWS General JSON with protected `alg`, `kid`,
`typ` and `cty`, followed by JWE encryption (`sign`, then `encrypt`). General
JWS supports overlap signatures for safe key rotation.

Inline ad-hoc signatures are not part of v1 draft 0.3. Until a trusted JWS key
store and rotation state are implemented, clients must not display
“publisher verified” merely because a key or signature appears inside a
downloaded document.

## Update and anti-downgrade state

The client stores trust state for:

```text
(issuer, subscription_id, channel)
```

The v1 compatibility implementation records:

```text
highest sequence
digest accepted at that sequence
encrypted/plaintext security level
exact accepted API version
```

Rules:

- Lower `sequence` is rejected.
- Equal sequence + equal digest is idempotent.
- Equal sequence + different digest is publisher equivocation and is rejected.
- Encrypted-to-plaintext transitions are rejected automatically. An unsupported
  API version is rejected before any legacy-format fallback.
- Issuer, subscription ID or channel changes require a new user-authorized
  subscription.
- The high-water mark is global to the exact tuple, not scoped to a local UI
  record ID. A second active record with the same tuple is rejected. Legacy
  duplicate records are reconciled deterministically at startup; ambiguous
  same-sequence/different-digest records remain blocked rather than guessed.
- A refreshed runtime is not activated until its assembled configuration passes
  HydraCore validation.

Backup records do not bypass this boundary. Every record claiming HydraBox v1
must contain its original wire payload; import reparses it, verifies the trust
digest/identity, and rebuilds native config, profiles, and projections. A
serialized `native_config` or `source_metadata` mismatch rejects the backup.

Payload persistence uses staged encrypted generations: HydraBox writes and
flushes a new payload first, then switches the metadata `payload_ref`, and only
then removes the previous generation. A crash before the pointer switch keeps
the preceding complete payload selected, so metadata and payload cannot be
torn by normal save ordering. This is storage crash consistency, not semantic
rollback: the previous generation is cleaned after commit, and HydraBox does
not yet retain a separately validated runtime generation or a highest-ever
major across deletion/re-import. Those stronger last-known-good claims must not
be made by the UI.

`update.minimum_interval_seconds` is a publisher hint. HydraBox applies local
limits and never allows it to force an unsafe refresh rate. `update.url` must
be well-formed HTTPS metadata, but v1 does not follow it; the original
user-authorized source and its redirect policy remain authoritative.

## Resource limits

The compatibility profile applies:

```text
outer response:       16 MiB
decrypted plaintext:  12 MiB
JSON depth:           64
profiles:             4096
identifier length:    128 characters
native tag length:    512 characters
sequence:             0..2^53-1
JWE recipients:       one (`dir` profile)
compression:          forbidden
```

Remote-policy-v1 WireGuard endpoints also have an activation resource budget,
enforced by both HydraBox and HydraCore during config construction:

```text
workers:              0..64 (0 selects the core default)
preallocated buffers: 0..4096 per pool (0 selects the platform default)
amnezia.jc:           0..128
amnezia.jmin/jmax:    0..65535, with jmin <= jmax
amnezia.s1..s4:       0..65535 bytes each
jc * jmax:            <= 4 MiB per handshake junk burst
```

Providers should stay far below these ceilings. Implementations may impose
stricter local limits.

## Acceptance pipeline

```text
limit wire bytes
  -> strict-discriminate HydraBox/JWE (no legacy fallback)
  -> strict-parse JWE
  -> validate protected suite
  -> decrypt and authenticate
  -> limit plaintext bytes/depth
  -> strict-parse SubscriptionData
  -> validate envelope/extensions/time/sequence
  -> resolve explicit profiles
  -> reject unconsented local-process authority
  -> require exact HydraCore identity + integer policy-v1 manifest
  -> enforce exact v1 top-level/types and closed acyclic references
  -> assemble client-owned runtime
  -> HydraCore config check
  -> switch the active runtime
```

The active-runtime switch is distinct from the crash-consistent payload-pointer
commit and is not an automatic semantic rollback facility; see the
anti-downgrade section.

The machine-readable schemas are:

- [`schema/hydrabox-subscription-v1.schema.json`](schema/hydrabox-subscription-v1.schema.json)
- [`schema/hydrabox-subscription-jwe-v1.schema.json`](schema/hydrabox-subscription-jwe-v1.schema.json)
