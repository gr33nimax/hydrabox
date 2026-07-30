#!/usr/bin/env python3
"""Verify the runnable extended protocol surface of the Android libbox build."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "etonify-core"
REGISTRY = CORE / "include" / "registry.go"
BUILD_LIBBOX = CORE / "cmd" / "internal" / "build_libbox" / "main.go"
V2RAY_TRANSPORT = CORE / "transport" / "v2ray" / "transport.go"
DEFAULT_BUILD_TAGS = CORE / "release" / "DEFAULT_BUILD_TAGS"
PROVENANCE = ROOT / "android" / "app" / "libs" / "libbox.provenance.json"

# These are calls in include/registry.go, not option-model names. Requiring the
# calls catches accidental loss of a protocol family while allowing the core to
# evolve its concrete option structs.
REQUIRED_REGISTRY_MARKERS = {
    # Inbounds.
    "TUN inbound": "tun.RegisterInbound(registry)",
    "redirect inbound": "redirect.RegisterRedirect(registry)",
    "TProxy inbound": "redirect.RegisterTProxy(registry)",
    "direct inbound": "direct.RegisterInbound(registry)",
    "SOCKS inbound": "socks.RegisterInbound(registry)",
    "HTTP inbound": "http.RegisterInbound(registry)",
    "mixed inbound": "mixed.RegisterInbound(registry)",
    "Shadowsocks inbound": "shadowsocks.RegisterInbound(registry)",
    "VMess inbound": "vmess.RegisterInbound(registry)",
    "Trojan inbound": "trojan.RegisterInbound(registry)",
    "Naive inbound": "naive.RegisterInbound(registry)",
    "ShadowTLS inbound": "shadowtls.RegisterInbound(registry)",
    "VLESS inbound": "vless.RegisterInbound(registry)",
    "AnyTLS inbound": "anytls.RegisterInbound(registry)",
    "Mieru inbound": "mieru.RegisterInbound(registry)",
    "SSH inbound": "ssh.RegisterInbound(registry)",
    "Bond inbound": "bond.RegisterInbound(registry)",
    "Failover inbound": "failover.RegisterInbound(registry)",
    "TrustTunnel inbound": "registerTrustTunnelInbound(registry)",
    "QUIC inbounds": "registerQUICInbounds(registry)",
    "MTProxy inbound": "registerMTProxyInbound(registry)",
    "Sudoku inbound": "registerSudokuInbound(registry)",
    "Snell inbound": "registerSnellInbound(registry)",
    # Outbounds and outbound groups/limiters.
    "direct outbound": "direct.RegisterOutbound(registry)",
    "block outbound": "block.RegisterOutbound(registry)",
    "fallback outbound": "group.RegisterFallback(registry)",
    "selector outbound": "group.RegisterSelector(registry)",
    "URLTest outbound": "group.RegisterURLTest(registry)",
    "SOCKS outbound": "socks.RegisterOutbound(registry)",
    "HTTP outbound": "http.RegisterOutbound(registry)",
    "Shadowsocks outbound": "shadowsocks.RegisterOutbound(registry)",
    "VMess outbound": "vmess.RegisterOutbound(registry)",
    "Trojan outbound": "trojan.RegisterOutbound(registry)",
    "Naive outbound": "registerNaiveOutbound(registry)",
    "Tor outbound": "tor.RegisterOutbound(registry)",
    "SSH outbound": "ssh.RegisterOutbound(registry)",
    "ShadowTLS outbound": "shadowtls.RegisterOutbound(registry)",
    "VLESS outbound": "vless.RegisterOutbound(registry)",
    "Mieru outbound": "mieru.RegisterOutbound(registry)",
    "AnyTLS outbound": "anytls.RegisterOutbound(registry)",
    "MASQUE outbound": "registerMASQUEOutbound(registry)",
    "OpenVPN outbound": "registerOpenVPNOutbound(registry)",
    "Bond outbound": "bond.RegisterOutbound(registry)",
    "Failover outbound": "failover.RegisterOutbound(registry)",
    "TrustTunnel outbound": "registerTrustTunnelOutbound(registry)",
    "bandwidth-limiter outbound": "bandwidth.RegisterOutbound(registry)",
    "connection-limiter outbound": "connection.RegisterOutbound(registry)",
    "traffic-limiter outbound": "traffic.RegisterOutbound(registry)",
    "rate-limiter outbound": "rate.RegisterOutbound(registry)",
    "parser outbound": "parser.RegisterOutbound(registry)",
    "QUIC outbounds": "registerQUICOutbounds(registry)",
    "Sudoku outbound": "registerSudokuOutbound(registry)",
    "Snell outbound": "registerSnellOutbound(registry)",
    # Endpoints.
    "vpn-server endpoint": "vpn.RegisterServerEndpoint(registry)",
    "vpn-client endpoint": "vpn.RegisterClientEndpoint(registry)",
    "wireguard/warp endpoints": "registerWireGuardEndpoint(registry)",
    "tailscale endpoint": "registerTailscaleEndpoint(registry)",
    # DNS transports.
    "TCP DNS": "transport.RegisterTCP(registry)",
    "UDP DNS": "transport.RegisterUDP(registry)",
    "TLS DNS": "transport.RegisterTLS(registry)",
    "HTTPS DNS": "transport.RegisterHTTPS(registry)",
    "SDNS": "transport.RegisterSDNS(registry)",
    "hosts DNS": "hosts.RegisterTransport(registry)",
    "local DNS": "local.RegisterTransport(registry)",
    "fake-IP DNS": "fakeip.RegisterTransport(registry)",
    "fallback DNS": "fallback.RegisterTransport(registry)",
    "resolved DNS": "resolved.RegisterTransport(registry)",
    "QUIC/h3 DNS": "registerQUICTransports(registry)",
    "DHCP DNS": "registerDHCPTransport(registry)",
    "Tailscale DNS": "registerTailscaleTransport(registry)",
    # Services and APIs that are part of full-config passthrough.
    "admin-panel service": "admin_panel.RegisterService(registry)",
    "manager service": "manager.RegisterService(registry)",
    "manager-api service": "manager_api.RegisterService(registry)",
    "node service": "node.RegisterService(registry)",
    "node-manager-api service": "node_manager_api.RegisterService(registry)",
    "resolved service": "resolved.RegisterService(registry)",
    "ssm-api service": "ssmapi.RegisterService(registry)",
    "DERP service": "registerDERPService(registry)",
    "CCM service": "registerCCMService(registry)",
    "OCM service": "registerOCMService(registry)",
    "OOM-killer service": "registerOOMKillerService(registry)",
    "profiler service": "registerProfilerService(registry)",
    # Providers consumed by full-config passthrough.
    "inline provider": "localProvider.RegisterProviderInline(registry)",
    "local provider": "localProvider.RegisterProviderLocal(registry)",
    "remote provider": "remoteProvider.RegisterProvider(registry)",
}

# The Android build must include every tag in release/DEFAULT_BUILD_TAGS.
# These extra tags promote additional registered mobile-safe services/APIs
# from their not-included stubs to real implementations.
REQUIRED_ADDITIONAL_ANDROID_TAGS = {
    "with_manager",
    "with_admin_panel",
    "with_profiler",
    "with_v2ray_api",
}

REQUIRED_TAGGED_IMPLEMENTATIONS = {
    CORE / "include" / "quic.go": {
        "Hysteria inbound": "hysteria.RegisterInbound(registry)",
        "Hysteria outbound": "hysteria.RegisterOutbound(registry)",
        "Hysteria2 inbound": "hysteria2.RegisterInbound(registry)",
        "Hysteria2 outbound": "hysteria2.RegisterOutbound(registry)",
        "TUIC inbound": "tuic.RegisterInbound(registry)",
        "TUIC outbound": "tuic.RegisterOutbound(registry)",
        "QUIC DNS transport": "quic.RegisterTransport(registry)",
        "HTTP/3 DNS transport": "quic.RegisterHTTP3Transport(registry)",
        "V2Ray QUIC transport": '"github.com/sagernet/sing-box/transport/v2rayquic"',
    },
    CORE / "include" / "wireguard.go": {
        "WireGuard endpoint": "wireguard.RegisterEndpoint(registry)",
        "WARP endpoint": "warp.RegisterEndpoint(registry)",
    },
    CORE / "include" / "masque.go": {
        "MASQUE outbound": "masque.RegisterOutbound(registry)",
    },
    CORE / "include" / "mtproxy.go": {
        "MTProxy inbound": "mtproxy.RegisterInbound(registry)",
    },
    CORE / "include" / "trusttunnel.go": {
        "TrustTunnel inbound": "trusttunnel.RegisterInbound(registry)",
        "TrustTunnel outbound": "trusttunnel.RegisterOutbound(registry)",
    },
    CORE / "include" / "openvpn.go": {
        "OpenVPN outbound": "openvpn.RegisterOutbound(registry)",
    },
    CORE / "include" / "sudoku.go": {
        "Sudoku inbound": "sudoku.RegisterInbound(registry)",
        "Sudoku outbound": "sudoku.RegisterOutbound(registry)",
    },
    CORE / "include" / "snell.go": {
        "Snell inbound": "snell.RegisterInbound(registry)",
        "Snell outbound": "snell.RegisterOutbound(registry)",
    },
    CORE / "include" / "tailscale.go": {
        "Tailscale endpoint": "tailscale.RegisterEndpoint(registry)",
        "Tailscale DNS": "tailscale.RegistryTransport(registry)",
    },
    CORE / "include" / "dhcp.go": {
        "DHCP DNS": "dhcp.RegisterTransport(registry)",
    },
    CORE / "include" / "naive_outbound.go": {
        "Naive outbound": "naive.RegisterOutbound(registry)",
    },
    CORE / "common" / "tls" / "acme.go": {
        "ACME TLS": "func startACME(",
    },
    CORE / "service" / "manager" / "service.go": {
        "manager service": "func RegisterService(",
    },
    CORE / "service" / "admin_panel" / "service.go": {
        "admin-panel service": "func RegisterService(",
    },
    CORE / "include" / "ccm.go": {
        "CCM service": "ccm.RegisterService(registry)",
    },
    CORE / "include" / "ocm.go": {
        "OCM service": "ocm.RegisterService(registry)",
    },
    CORE / "include" / "profiler.go": {
        "profiler service": "profiler.RegisterService(registry)",
    },
    CORE / "include" / "v2rayapi.go": {
        "V2Ray API": '"github.com/sagernet/sing-box/experimental/v2rayapi"',
    },
}

REQUIRED_V2RAY_TRANSPORT_MARKERS = {
    "HTTP": "C.V2RayTransportTypeHTTP",
    "WebSocket": "C.V2RayTransportTypeWebsocket",
    "QUIC": "C.V2RayTransportTypeQUIC",
    "gRPC": "C.V2RayTransportTypeGRPC",
    "HTTP Upgrade": "C.V2RayTransportTypeHTTPUpgrade",
    "XHTTP/SplitHTTP": "C.V2RayTransportTypeXHTTP",
    "mKCP/KCP": "C.V2RayTransportTypeKCP",
}

REQUIRED_EXACT_CONSTANTS = {
    CORE / "constant" / "proxy.go": {
        "TypeBandwidthLimiter": "bandwidth-limiter",
        "TypeConnectionLimiter": "connection-limiter",
        "TypeTrafficLimiter": "traffic-limiter",
        "TypeRateLimiter": "rate-limiter",
        "TypeWireGuard": "wireguard",
        "TypeWARP": "warp",
        "TypeTailscale": "tailscale",
        "TypeVPNClient": "vpn-client",
        "TypeVPNServer": "vpn-server",
    },
    CORE / "constant" / "dns.go": {
        "DNSTypeHTTP3": "h3",
    },
}

_SHARED_TAG_APPEND = re.compile(
    r"sharedTags\s*=\s*append\(\s*sharedTags\s*,(?P<body>.*?)\)",
    re.DOTALL,
)
_GO_STRING = re.compile(r'"(?:\\.|[^"\\])*"')
_ANDROID_CONFIG = re.compile(
    r"AndroidBuildConfig\s*\{(?P<body>.*?)\}",
    re.DOTALL,
)


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def read_android_build_tags() -> list[str]:
    """Return the exact release tags passed to gomobile for libbox.aar."""

    if not BUILD_LIBBOX.is_file():
        fail(f"missing libbox build entrypoint: {BUILD_LIBBOX}")
    source = BUILD_LIBBOX.read_text(encoding="utf-8")
    tags: list[str] = []
    matches = list(_SHARED_TAG_APPEND.finditer(source))
    if not matches:
        fail("could not find sharedTags append statements in libbox builder")

    for match in matches:
        body = match.group("body")
        literals = _GO_STRING.findall(body)
        residue = _GO_STRING.sub("", body).replace(",", "").strip()
        if residue:
            fail(
                "sharedTags contains a dynamic expression; update the verifier "
                f"before trusting the Android build: {residue!r}"
            )
        tags.extend(json.loads(literal) for literal in literals)

    if not tags:
        fail("the Android libbox build has no shared tags")
    duplicates = sorted({tag for tag in tags if tags.count(tag) > 1})
    if duplicates:
        fail("the Android libbox build repeats tags: " + ", ".join(duplicates))
    return tags


def read_release_default_build_tags() -> list[str]:
    if not DEFAULT_BUILD_TAGS.is_file():
        fail(f"missing extended default build tags: {DEFAULT_BUILD_TAGS}")
    tags = [
        tag.strip()
        for tag in DEFAULT_BUILD_TAGS.read_text(encoding="utf-8").split(",")
        if tag.strip()
    ]
    if not tags:
        fail("release/DEFAULT_BUILD_TAGS is empty")
    duplicates = sorted({tag for tag in tags if tags.count(tag) > 1})
    if duplicates:
        fail(
            "release/DEFAULT_BUILD_TAGS repeats tags: "
            + ", ".join(duplicates)
        )
    return tags


def required_android_build_tags() -> set[str]:
    return (
        set(read_release_default_build_tags())
        | REQUIRED_ADDITIONAL_ANDROID_TAGS
    )


def read_android_api() -> int:
    """Return the minSdk used for the primary libbox.aar variant."""

    if not BUILD_LIBBOX.is_file():
        fail(f"missing libbox build entrypoint: {BUILD_LIBBOX}")
    source = BUILD_LIBBOX.read_text(encoding="utf-8")
    for match in _ANDROID_CONFIG.finditer(source):
        body = match.group("body")
        output_match = re.search(r'OutputName\s*:\s*"([^"]+)"', body)
        if output_match is None or output_match.group(1) != "libbox.aar":
            continue
        api_match = re.search(r"AndroidAPI\s*:\s*(\d+)", body)
        if api_match is None:
            fail("primary libbox.aar build does not declare AndroidAPI")
        return int(api_match.group(1))
    fail("could not find the primary libbox.aar Android build configuration")


def verify_source() -> tuple[list[str], int]:
    if not CORE.is_dir():
        fail("etonify-core submodule is not initialized")
    if not REGISTRY.is_file():
        fail(f"missing core registry: {REGISTRY}")

    registry = REGISTRY.read_text(encoding="utf-8")
    missing_registry = [
        label
        for label, marker in REQUIRED_REGISTRY_MARKERS.items()
        if marker not in registry
    ]
    if missing_registry:
        fail("core registry is missing: " + ", ".join(missing_registry))

    for path, required_markers in REQUIRED_TAGGED_IMPLEMENTATIONS.items():
        if not path.is_file():
            fail(f"missing tagged protocol implementation: {path}")
        implementation = path.read_text(encoding="utf-8")
        missing_implementations = [
            label
            for label, marker in required_markers.items()
            if marker not in implementation
        ]
        if missing_implementations:
            fail(
                f"{path.relative_to(CORE)} is missing implementations: "
                + ", ".join(missing_implementations)
            )

    if not V2RAY_TRANSPORT.is_file():
        fail(f"missing V2Ray transport dispatcher: {V2RAY_TRANSPORT}")
    v2ray_transport = V2RAY_TRANSPORT.read_text(encoding="utf-8")
    missing_v2ray_transports = [
        label
        for label, marker in REQUIRED_V2RAY_TRANSPORT_MARKERS.items()
        if marker not in v2ray_transport
    ]
    if missing_v2ray_transports:
        fail(
            "V2Ray transport dispatcher is missing: "
            + ", ".join(missing_v2ray_transports)
        )

    for path, expected_constants in REQUIRED_EXACT_CONSTANTS.items():
        if not path.is_file():
            fail(f"missing protocol constants: {path}")
        source = path.read_text(encoding="utf-8")
        for name, expected_value in expected_constants.items():
            pattern = re.compile(
                rf'^[ \t]*{re.escape(name)}[ \t]*=[ \t]*'
                rf'"{re.escape(expected_value)}"[ \t]*$',
                re.MULTILINE,
            )
            if pattern.search(source) is None:
                fail(
                    f"{path.relative_to(CORE)} must declare "
                    f'{name} = "{expected_value}"'
                )

    required_tags = required_android_build_tags()
    build_tags = read_android_build_tags()
    missing_tags = sorted(required_tags - set(build_tags))
    if missing_tags:
        fail(
            "primary Android libbox build would select not-included stubs; "
            "missing tags: "
            + ", ".join(missing_tags)
        )
    return build_tags, read_android_api()


def verify_provenance(build_tags: list[str], android_api: int) -> None:
    if not PROVENANCE.is_file():
        fail(f"missing libbox provenance: {PROVENANCE}")
    try:
        provenance = json.loads(PROVENANCE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"invalid libbox provenance JSON: {error}")
    if not isinstance(provenance, dict):
        fail("libbox provenance must be a JSON object")

    recorded_tags = [
        tag.strip()
        for tag in str(provenance.get("build_tags", "")).split(",")
        if tag.strip()
    ]
    if recorded_tags != build_tags:
        missing = sorted(set(build_tags) - set(recorded_tags))
        unexpected = sorted(set(recorded_tags) - set(build_tags))
        details = []
        if missing:
            details.append("missing " + ", ".join(missing))
        if unexpected:
            details.append("unexpected " + ", ".join(unexpected))
        if not details:
            details.append("tag order differs from the core builder")
        fail("bundled AAR build tags do not match the core builder: " + "; ".join(details))

    recorded_api = provenance.get("android_api")
    if recorded_api != android_api:
        fail(
            "bundled AAR Android API does not match the core builder: "
            f"{recorded_api!r} != {android_api}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-only",
        action="store_true",
        help="verify the checked-out core without requiring a rebuilt AAR",
    )
    output = parser.add_mutually_exclusive_group()
    output.add_argument(
        "--print-build-tags",
        action="store_true",
        help="print the exact comma-separated tags used by libbox.aar",
    )
    output.add_argument(
        "--print-android-api",
        action="store_true",
        help="print the Android API used by the primary libbox.aar",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    build_tags, android_api = verify_source()

    if args.print_build_tags:
        print(",".join(build_tags))
        return
    if args.print_android_api:
        print(android_api)
        return
    if not args.source_only:
        verify_provenance(build_tags, android_api)

    print(
        "Verified extended core: "
        f"{len(REQUIRED_REGISTRY_MARKERS)} registered core surfaces, "
        f"{sum(map(len, REQUIRED_TAGGED_IMPLEMENTATIONS.values()))} "
        "tagged implementations, "
        f"{len(REQUIRED_V2RAY_TRANSPORT_MARKERS)} V2Ray transports, "
        f"{sum(map(len, REQUIRED_EXACT_CONSTANTS.values()))} exact type "
        "constants, "
        f"{len(required_android_build_tags())} required Android tags, "
        f"API {android_api}"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, TypeError, ValueError) as error:
        print(f"extended core verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
