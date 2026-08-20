#!/usr/bin/env python3
"""Verify the pinned HydraCore API v2 source and Android release contract."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "hydracore"
BASELINE = CORE / "release" / "UPSTREAM_BASELINE"
PROVENANCE = ROOT / "android" / "app" / "libs" / "libbox.provenance.json"

REQUIRED_SOURCE_MARKERS: dict[str, tuple[str, ...]] = {
    "experimental/libbox/hydracore_capabilities.go": (
        "const hydraCoreAPIVersion = H.APIVersion",
        "func HydraCoreCapabilities() string",
        "return H.CapabilitiesJSON()",
        "func HydraCoreTransportState() string",
        "func HydraCoreCancelRuntimeChallenge(id string) bool",
    ),
    "common/hydracore/capabilities.go": (
        "const APIVersion = 2",
        'CoreID:      "io.hydrabox.hydracore"',
        'json:"runtime_events"',
        'json:"managed_url_test_sessions"',
        'json:"subscription_jwe"',
        'json:"call"',
        'json:"call_vk_parasite"',
        'json:"call_vk_parasite_client"',
        'json:"call_vk_parasite_server"',
        'json:"call_vk_telemetry"',
        'json:"vk_auth_challenges"',
        '[]int{2}',
        '[]string{"__hydra."}',
    ),
    "experimental/libbox/hydracore_build_info.go": (
        "func HydraCoreBuildInfo() string",
        'info.Distribution.ID = "io.hydrabox.hydracore"',
    ),
    "experimental/libbox/hydracore_validation.go": (
        "func HydraCoreValidateConfig(configContent string, profile string) string",
        'case "local":',
        'case "remote_v2":',
    ),
    "experimental/libbox/hydracore_subscription.go": (
        "func HydraCoreSubscriptionSchema() string",
        "func HydraCoreValidateSubscription(content string) string",
        "func HydraCoreInspectSubscription(content string) string",
        'supportedFeatures["call_vk_parasite"] = true',
        '"network.outbound"',
        '"network.inbound.call"',
        '"network.endpoint.wireguard"',
    ),
    "experimental/libbox/hydracore_subscription_jwe.go": (
        "func HydraCoreOpenSubscriptionJWE(",
        "func HydraCoreValidateSubscriptionJWE(",
        "func HydraCoreInspectSubscriptionJWE(",
        'Algorithm != "dir"',
        'Encryption != "A256GCM"',
    ),
    "experimental/libbox/command.go": (
        "CommandRuntimeEvents",
        "CommandURLTestEvents",
    ),
    "experimental/libbox/command_client.go": (
        "func (c *CommandClient) GetRuntimeSnapshot()",
        "func (c *CommandClient) StartURLTestWithOptions(",
        "func (c *CommandClient) GetURLTestSession(",
        "func (c *CommandClient) CancelURLTest(",
    ),
    "experimental/libbox/command_types.go": (
        "type RuntimeSnapshot struct",
        "type RuntimeEvents struct",
        "type URLTestSession struct",
        "URLTestSessionCancelled",
    ),
    "include/call.go": ("call.RegisterInbound", "call.RegisterOutbound"),
    "common/hydracore/call_client.go": (
        'distributionRole  = "client"',
        'callModes     = []string{"vk_parasite"}',
    ),
    "common/hydracore/call_server.go": (
        'distributionRole  = "vps"',
    ),
}

REQUIRED_CONTRACT_FILES = (
    "contract/subscription/HYDRA_SUBSCRIPTION_V2.md",
    "contract/subscription/schema/hydra-subscription-v2.schema.json",
    "contract/subscription/schema/hydra-subscription-jwe-v2.schema.json",
    "release/verify_attribution_boundaries.sh",
    "release/verify_upstream_baseline.sh",
)

REQUIRED_BUILD_TAGS = {
    "with_gvisor",
    "with_quic",
    "with_wireguard",
    "with_utls",
    "with_clash_api",
    "with_call",
    "with_naive_outbound",
}


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def read_upstream_baseline() -> dict[str, str]:
    if not BASELINE.is_file():
        fail("hydracore/release/UPSTREAM_BASELINE is missing")
    settings: dict[str, str] = {}
    for line in BASELINE.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, separator, value = stripped.partition("=")
        if not separator or not key.strip() or not value.strip():
            fail(f"malformed UPSTREAM_BASELINE line: {line!r}")
        settings[key.strip()] = value.strip()
    required = {
        "UPSTREAM_REPOSITORY",
        "UPSTREAM_BRANCH",
        "UPSTREAM_COMMIT",
        "UPSTREAM_TAG",
        "GO_VERSION",
        "GOMOBILE_VERSION",
        "ANDROID_NDK_VERSION",
        "JAVA_VERSION",
        "LIBBOX_ANDROID_API",
        "LIBBOX_BUILD_TAGS",
    }
    missing = sorted(required - settings.keys())
    if missing:
        fail("UPSTREAM_BASELINE is missing: " + ", ".join(missing))
    return settings


def verify_source() -> tuple[list[str], int]:
    if not CORE.is_dir():
        fail("hydracore submodule is not initialized")
    for relative, markers in REQUIRED_SOURCE_MARKERS.items():
        path = CORE / relative
        if not path.is_file():
            fail(f"missing HydraCore API v2 source: {relative}")
        source = path.read_text(encoding="utf-8")
        missing = [marker for marker in markers if marker not in source]
        if missing:
            fail(f"{relative} is missing contract markers: {missing!r}")
    for relative in REQUIRED_CONTRACT_FILES:
        if not (CORE / relative).is_file():
            fail(f"missing HydraCore release contract file: {relative}")

    registry = (CORE / "include" / "registry.go").read_text(encoding="utf-8")
    proxy_constants = (CORE / "constant" / "proxy.go").read_text(encoding="utf-8")
    if "registerWDTT" in registry or "TypeWDTT" in proxy_constants:
        fail("WDTT remains active in the pinned HydraCore source")

    baseline = read_upstream_baseline()
    build_tags = [
        tag.strip()
        for tag in baseline["LIBBOX_BUILD_TAGS"].split(",")
        if tag.strip()
    ]
    if len(set(build_tags)) != len(build_tags):
        fail("UPSTREAM_BASELINE contains duplicate Android build tags")
    missing_tags = sorted(REQUIRED_BUILD_TAGS - set(build_tags))
    if missing_tags:
        fail("HydraCore Android build is missing tags: " + ", ".join(missing_tags))
    try:
        android_api = int(baseline["LIBBOX_ANDROID_API"])
    except ValueError:
        fail("LIBBOX_ANDROID_API must be an integer")
    if android_api < 23:
        fail("HydraCore Android API must be at least 23")
    return build_tags, android_api


def verify_provenance(build_tags: list[str], android_api: int) -> None:
    if not PROVENANCE.is_file():
        fail(f"missing libbox provenance: {PROVENANCE}")
    try:
        provenance = json.loads(PROVENANCE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"invalid libbox provenance JSON: {error}")
    recorded_tags = provenance.get("toolchain", {}).get("build_tags")
    recorded_api = provenance.get("android", {}).get("api")
    client_build_tags = [
        "with_call_client" if tag == "with_call" else tag
        for tag in build_tags
    ]
    if recorded_tags != client_build_tags:
        fail("bundled AAR build tags do not match the client role")
    if recorded_api != android_api:
        fail("bundled AAR Android API does not match UPSTREAM_BASELINE")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--print-build-tags", action="store_true")
    output.add_argument("--print-android-api", action="store_true")
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
        "Verified HydraCore API v2: "
        f"{len(REQUIRED_SOURCE_MARKERS)} API surfaces, "
        f"{len(build_tags)} Android tags, API {android_api}"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, TypeError, ValueError) as error:
        print(f"HydraCore verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
