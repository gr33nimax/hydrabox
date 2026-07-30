# Extended sing-box core

Etonify is built against the [`shtorm-7/sing-box-extended`](https://github.com/shtorm-7/sing-box-extended)
`extended` line through the `gr33nimax/etonify-core` integration submodule.
The Android AAR is produced from the checked-out submodule commit; the
provenance file next to the AAR records the exact commit, Go/gomobile/NDK
versions and build tags.

## Protocol coverage

The Android build enables the optional core tags for:

- inbound: TUN, redirect, TProxy, direct, SOCKS, HTTP, mixed, Shadowsocks,
  VMess, Trojan, Naive, ShadowTLS, VLESS, AnyTLS, Mieru, SSH, Bond, Failover,
  TrustTunnel, Hysteria, Hysteria2, TUIC, MTProxy, Sudoku and Snell;
- outbound: direct, block, fallback, selector, URLTest, SOCKS, HTTP,
  Shadowsocks, VMess, Trojan, Naive, Tor, SSH, ShadowTLS, VLESS, Mieru,
  AnyTLS, MASQUE, OpenVPN, Bond, Failover, TrustTunnel, bandwidth/connection/
  traffic/rate limiters (`bandwidth-limiter`, `connection-limiter`,
  `traffic-limiter`, `rate-limiter`), parser, Hysteria, Hysteria2, TUIC,
  Sudoku and Snell;
- endpoints: `vpn-server`, `vpn-client`, `wireguard`, `warp` and `tailscale`;
- DNS transports: TCP, UDP, TLS, HTTPS, QUIC/HTTP3, SDNS, hosts, local,
  fake-IP, fallback, resolved, DHCP and Tailscale (`h3` is the exact HTTP/3
  DNS type);
- V2Ray transports: HTTP, WebSocket, gRPC, HTTP Upgrade, XHTTP/SplitHTTP,
  mKCP/KCP and QUIC;
- providers: inline, local and remote;
- services: admin panel, manager, manager API, node, node-manager API,
  resolved, SSM API, Tailscale DERP, CCM, OCM, OOM killer and profiler;
- other full-config runtime surfaces: ACME TLS, Clash API and V2Ray API.

The importer has a lossless path for a complete sing-box JSON document.  It
does not apply a Flutter-side allow-list to such a document: protocol-specific
fields, nested transports, `endpoints`, `services`, providers and custom DNS
sections are retained and passed to libbox.  The native core remains the
authority for validating option types and required fields.

Share-link formats still receive conservative normalization because they are
translated from a smaller URI schema.  A provider that uses a protocol without
a share-link representation should publish a full sing-box JSON config.

Treat complete sing-box JSON documents as trusted executable configuration.
They may declare listeners, local-file providers and management services, so
importing an untrusted document can expose local ports or grant it access to
resources available to the Etonify process. This warning does not reduce the
extended core surface; it makes the authority granted to a full config
explicit.

Two upstream protocol families are intentional stubs in the extended core:
the removed ShadowsocksR inbound/outbound and the removed WireGuard outbound
form. Use a WireGuard `endpoint` for WireGuard and do not treat ShadowsocksR as
supported. The app rejects the ShadowsocksR stubs instead of claiming that
they work.

Legacy WireGuard outbounds are converted to the endpoint schema. The pinned
extended core no longer exposes the old three-byte `reserved` bind override;
`[0, 0, 0]` is normalized to an absent override, while non-zero values are
rejected instead of being silently discarded. Cloudflare WARP configurations
should use its dedicated `warp` endpoint.

## Reproducible build

The CI workflow runs `go test` with the exact extended Android tag set, builds
the Android AAR with those tags, copies the AAR and source archive into
`android/app/libs`, writes a SHA-256/provenance record, and runs both artifact
and registry coverage checks. Changing the submodule pointer intentionally
causes the workflow to rebuild the bundle. The AAR is stored with Git LFS so
the complete four-ABI extended build is not constrained by GitHub's regular
blob-size limit. After cloning, run `git lfs pull` before an Android build so
`android/app/libs/libbox.aar` is hydrated instead of remaining an LFS pointer.

The build tags and Android API stored in provenance are extracted from the
checked-out core's `cmd/internal/build_libbox` entrypoint.  Verification fails
if a required protocol would resolve to a not-included stub, if the AAR omits
one of the four Android ABIs, or if the artifact, source archive, repository,
branch, commit, toolchain, tags, and API no longer agree with the pinned
submodule.
