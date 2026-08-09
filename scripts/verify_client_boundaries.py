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


def main() -> None:
    verify_removed_boundaries()
    verify_required_contract()
    print("Verified HydraBox client boundaries and Hydra Subscription v2 markers")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, UnicodeError) as error:
        print(f"client boundary verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
