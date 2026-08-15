#!/usr/bin/env python3
"""Fail when removed client contracts or product aliases become active again."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[1]
ACTIVE_ROOTS = (
    ROOT / "lib",
    ROOT / "pigeons",
    ROOT / "android" / "app" / "src" / "main",
    ROOT / "ios" / "Runner",
    ROOT / "macos" / "Runner",
    ROOT / "linux",
    ROOT / "windows" / "runner",
)
TEXT_SUFFIXES = {
    ".dart",
    ".kt",
    ".kts",
    ".java",
    ".swift",
    ".m",
    ".mm",
    ".h",
    ".cpp",
    ".cc",
    ".c",
    ".xml",
    ".plist",
    ".json",
    ".yaml",
    ".yml",
    ".gradle",
    ".properties",
    ".rc",
}
FORBIDDEN = {
    "removed transport": re.compile(r"wdtt", re.IGNORECASE),
    "removed product alias": re.compile(r"etonify|meowvpn", re.IGNORECASE),
    "removed subscription discriminator": re.compile(
        r"hydrabox\.io/subscription/", re.IGNORECASE
    ),
    "removed JWE key name": re.compile(r"hbx-key", re.IGNORECASE),
}
MAIN_PROCESS_ENTRYPOINTS = (
    ROOT / "android" / "app" / "src" / "main" / "kotlin"
    / "io" / "hydrabox" / "client" / "MainActivity.kt",
    ROOT / "android" / "app" / "src" / "main" / "kotlin"
    / "io" / "hydrabox" / "client" / "HydraBoxApplication.kt",
    ROOT / "android" / "app" / "src" / "main" / "kotlin"
    / "io" / "hydrabox" / "client" / "HydraBoxQuickSettingsTileService.kt",
)
CORE_PROCESS_ROOT = (
    ROOT / "android" / "app" / "src" / "main" / "kotlin"
    / "io" / "hydrabox" / "client" / "runtime"
)


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def active_files() -> list[Path]:
    files: list[Path] = []
    for root in ACTIVE_ROOTS:
        if not root.exists():
            continue
        files.extend(
            path
            for path in root.rglob("*")
            if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES
        )
    return files


def verify_removed_boundaries() -> None:
    violations: list[str] = []
    for path in active_files():
        content = path.read_text(encoding="utf-8", errors="replace")
        for label, pattern in FORBIDDEN.items():
            match = pattern.search(content)
            if match is None:
                continue
            line = content.count("\n", 0, match.start()) + 1
            violations.append(f"{path.relative_to(ROOT)}:{line}: {label}")
    if violations:
        fail("removed client boundary is active:\n" + "\n".join(violations))


def verify_required_contract() -> None:
    parser = (
        ROOT / "lib" / "data" / "subscription" / "parsers"
        / "hydra_subscription_parser.dart"
    ).read_text(encoding="utf-8")
    required = (
        "hydra.io/subscription/v2",
        "network.outbound",
        "network.endpoint.wireguard",
        "network.inbound.call",
        "permissions_automatic",
    )
    missing = [marker for marker in required if marker not in parser]
    if missing:
        fail(f"Hydra Subscription v2 parser is missing markers: {missing!r}")

    gradle = (ROOT / "android" / "app" / "build.gradle.kts").read_text(
        encoding="utf-8"
    )
    if gradle.count('"io.hydrabox.client"') < 2:
        fail("Android namespace and application ID must use io.hydrabox.client")


def verify_android_process_isolation() -> None:
    direct_libbox = re.compile(r"^\s*import\s+io\.nekohasekai\.libbox", re.MULTILINE)
    for path in MAIN_PROCESS_ENTRYPOINTS:
        content = path.read_text(encoding="utf-8")
        if direct_libbox.search(content):
            fail(
                f"{path.relative_to(ROOT)} imports libbox in the Android UI process"
            )

    core_forbidden = re.compile(
        r"^\s*import\s+(?:androidx\.room|io\.flutter|io\.hydrabox\.client\.storage)",
        re.MULTILINE,
    )
    for path in CORE_PROCESS_ROOT.glob("*.kt"):
        content = path.read_text(encoding="utf-8")
        if core_forbidden.search(content):
            fail(
                f"{path.relative_to(ROOT)} crosses the isolated core/storage boundary"
            )

    manifest = (
        ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    ).read_text(encoding="utf-8")
    required_process_bindings = (
        'android:name=".runtime.CoreRuntimeService"',
        'android:name=".runtime.CoreProbeService"',
        'android:process=":core"',
        'android:process=":core_probe"',
    )
    missing = [value for value in required_process_bindings if value not in manifest]
    if missing:
        fail(f"Android core process isolation markers are missing: {missing!r}")

    forbidden_permissions = (
        "android.permission.REQUEST_INSTALL_PACKAGES",
    )
    present_permissions = [value for value in forbidden_permissions if value in manifest]
    if present_permissions:
        fail(f"Android user package contains unsafe permissions: {present_permissions!r}")

    application = (
        ROOT / "android" / "app" / "src" / "main" / "kotlin"
        / "io" / "hydrabox" / "client" / "HydraBoxApplication.kt"
    ).read_text(encoding="utf-8")
    if "else -> bundleManager.configureNativeLoader()" in application:
        fail("Android UI process still configures the HydraCore native loader")


def verify_platform_bridge_boot_order() -> None:
    activity = MAIN_PROCESS_ENTRYPOINTS[0].read_text(encoding="utf-8")
    configure_start = activity.find("override fun configureFlutterEngine")
    configure_end = activity.find("MethodChannel(", configure_start)
    if configure_start < 0 or configure_end < 0:
        fail("MainActivity Flutter engine bootstrap block is missing")
    bootstrap = activity[configure_start:configure_end]
    markers = (
        "CoreManagerHostApi.setUp(binaryMessenger, handler)",
        "setupSingboxHostApi(binaryMessenger)",
        "coreRuntimeClient.connect()",
    )
    positions = [bootstrap.find(marker) for marker in markers]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        fail(
            "MainActivity must register Core Manager and Singbox Pigeon APIs "
            "before binding the isolated HydraCore process"
        )


def main() -> None:
    verify_removed_boundaries()
    verify_required_contract()
    verify_android_process_isolation()
    verify_platform_bridge_boot_order()
    print("Verified HydraBox client boundaries and Hydra Subscription v2 markers")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, UnicodeError) as error:
        print(f"client boundary verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
