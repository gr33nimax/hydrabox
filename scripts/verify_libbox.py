#!/usr/bin/env python3
"""Verify bundled libbox artifacts against the pinned extended core source."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import NoReturn

from verify_extended_core import verify_source


ROOT = Path(__file__).resolve().parents[1]
LIBS = ROOT / "android" / "app" / "libs"
AAR = LIBS / "libbox.aar"
SOURCES = LIBS / "libbox-sources.jar"
HASH_FILE = LIBS / "libbox.sha256"
PROVENANCE_FILE = LIBS / "libbox.provenance.json"
CORE_PATH = ROOT / "etonify-core"
BASELINE_FILE = CORE_PATH / "release" / "ETONIFY_BASELINE"
GITMODULES = ROOT / ".gitmodules"
REQUIRED_ANDROID_ABIS = {
    "armeabi-v7a",
    "arm64-v8a",
    "x86",
    "x86_64",
}
PROVENANCE_SCHEMA_VERSION = 2


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(
        ["git", *args],
        cwd=cwd,
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()


def tracked_gitlink_commit() -> str:
    line = git("ls-files", "--stage", "--", "etonify-core")
    match = re.fullmatch(r"160000 ([0-9a-f]{40}) 0\tetonify-core", line)
    if match is None:
        fail("etonify-core must be tracked as a Git submodule")
    return match.group(1)


def submodule_setting(name: str) -> str:
    if not GITMODULES.is_file():
        fail("missing .gitmodules")
    try:
        value = git(
            "config",
            "-f",
            str(GITMODULES),
            "--get",
            f"submodule.etonify-core.{name}",
        )
    except subprocess.CalledProcessError:
        raise RuntimeError(
            f".gitmodules is missing the etonify-core {name}"
        ) from None
    if not value:
        fail(f".gitmodules has an empty etonify-core {name}")
    return value


def normalize_repository(value: str) -> str:
    normalized = value.strip().rstrip("/")
    if normalized.lower().endswith(".git"):
        normalized = normalized[:-4]
    return normalized.lower()


def validate_lfs_configuration() -> None:
    attribute = git(
        "check-attr",
        "filter",
        "--",
        "android/app/libs/libbox.aar",
    )
    if not attribute.endswith(": lfs"):
        fail("android/app/libs/libbox.aar must be tracked by Git LFS")


def validate_archives() -> None:
    try:
        with zipfile.ZipFile(AAR) as archive:
            corrupt_member = archive.testzip()
            if corrupt_member is not None:
                fail(f"libbox.aar has a corrupt member: {corrupt_member}")
            names = set(archive.namelist())
            if "classes.jar" not in names:
                fail("libbox.aar does not contain classes.jar")
            present_abis = {
                match.group(1)
                for name in names
                if (
                    match := re.fullmatch(
                        r"jni/([^/]+)/libbox\.so",
                        name,
                    )
                )
            }
            missing_abis = sorted(REQUIRED_ANDROID_ABIS - present_abis)
            if missing_abis:
                fail(
                    "libbox.aar is missing Android ABIs: "
                    + ", ".join(missing_abis)
                )

        with zipfile.ZipFile(SOURCES) as archive:
            corrupt_member = archive.testzip()
            if corrupt_member is not None:
                fail(f"libbox-sources.jar has a corrupt member: {corrupt_member}")
            if not any(name.endswith(".java") for name in archive.namelist()):
                fail("libbox-sources.jar does not contain generated Java sources")
    except zipfile.BadZipFile as error:
        fail(f"invalid libbox archive: {error}")


def required_string(provenance: dict[str, object], key: str) -> str:
    value = provenance.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"libbox provenance is missing {key}")
    return value.strip()


def declared_go_version() -> str:
    go_mod = CORE_PATH / "go.mod"
    if not go_mod.is_file():
        fail("etonify-core/go.mod is missing")
    match = re.search(
        r"^go\s+([0-9]+(?:\.[0-9]+){1,2})\s*$",
        go_mod.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if match is None:
        fail("etonify-core/go.mod does not declare a Go version")
    return match.group(1)


def baseline_settings() -> dict[str, str]:
    if not BASELINE_FILE.is_file():
        fail("etonify-core/release/ETONIFY_BASELINE is missing")
    settings: dict[str, str] = {}
    for line in BASELINE_FILE.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, separator, value = stripped.partition("=")
        if not separator or not key or not value:
            fail(f"invalid ETONIFY_BASELINE entry: {line!r}")
        settings[key] = value
    for key in (
        "GO_VERSION",
        "GOMOBILE_VERSION",
        "ANDROID_NDK_VERSION",
        "JAVA_VERSION",
    ):
        if not settings.get(key):
            fail(f"ETONIFY_BASELINE is missing {key}")
    return settings


def main() -> None:
    required = (AAR, SOURCES, HASH_FILE, PROVENANCE_FILE)
    missing = [
        str(path.relative_to(ROOT))
        for path in required
        if not path.is_file()
    ]
    if missing:
        fail(f"missing libbox artifacts: {', '.join(missing)}")
    if AAR.stat().st_size == 0 or SOURCES.stat().st_size == 0:
        fail("libbox binary and sources archive must not be empty")
    with AAR.open("rb") as stream:
        if stream.read(64).startswith(b"version https://git-lfs.github.com/"):
            fail("libbox.aar is an LFS pointer; run `git lfs pull` first")
    validate_lfs_configuration()
    validate_archives()

    hash_line = HASH_FILE.read_text(encoding="utf-8").strip()
    hash_match = re.fullmatch(
        r"([0-9a-fA-F]{64})\s+\*?libbox\.aar",
        hash_line,
    )
    if hash_match is None:
        fail("libbox.sha256 must contain one SHA-256 entry for libbox.aar")
    pinned_hash = hash_match.group(1).lower()
    actual_hash = sha256(AAR)
    if actual_hash != pinned_hash:
        fail(
            "libbox.aar SHA-256 mismatch: "
            f"expected {pinned_hash}, got {actual_hash}"
        )

    try:
        provenance = json.loads(PROVENANCE_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"invalid libbox provenance JSON: {error}")
    if not isinstance(provenance, dict):
        fail("libbox provenance must be a JSON object")
    if provenance.get("schema_version") != PROVENANCE_SCHEMA_VERSION:
        fail(
            "libbox provenance schema_version must be "
            f"{PROVENANCE_SCHEMA_VERSION}"
        )
    if provenance.get("artifact") != "libbox.aar":
        fail("libbox provenance has an unexpected artifact name")
    if str(provenance.get("sha256", "")).lower() != actual_hash:
        fail("libbox provenance SHA-256 does not match the bundled AAR")

    actual_sources_hash = sha256(SOURCES)
    if (
        str(provenance.get("sources_sha256", "")).lower()
        != actual_sources_hash
    ):
        fail(
            "libbox provenance sources_sha256 does not match "
            "libbox-sources.jar"
        )

    source_commit = required_string(provenance, "source_commit").lower()
    if re.fullmatch(r"[0-9a-f]{40}", source_commit) is None:
        fail("libbox provenance source_commit must be a full Git commit")
    gitlink_commit = tracked_gitlink_commit()
    if source_commit != gitlink_commit:
        fail(
            "libbox provenance source_commit does not match the etonify-core "
            f"gitlink: {source_commit} != {gitlink_commit}"
        )

    if (CORE_PATH / ".git").exists():
        checkout_commit = git("rev-parse", "HEAD", cwd=CORE_PATH).lower()
        if checkout_commit != source_commit:
            fail(
                "checked-out etonify-core commit does not match libbox "
                f"provenance: {checkout_commit} != {source_commit}"
            )

    configured_repository = submodule_setting("url")
    recorded_repository = required_string(provenance, "source_repository")
    if (
        normalize_repository(recorded_repository)
        != normalize_repository(configured_repository)
    ):
        fail(
            "libbox provenance source_repository does not match .gitmodules: "
            f"{recorded_repository} != {configured_repository}"
        )
    configured_branch = submodule_setting("branch")
    recorded_branch = required_string(provenance, "source_branch")
    if recorded_branch != configured_branch:
        fail(
            "libbox provenance source_branch does not match .gitmodules: "
            f"{recorded_branch} != {configured_branch}"
        )

    baseline = baseline_settings()
    required_string(provenance, "core_version")
    go_actual = required_string(provenance, "go")
    gomobile_actual = required_string(provenance, "gomobile")
    java_actual = required_string(provenance, "java")
    required_string(provenance, "android_ndk")
    android_ndk_requested = required_string(
        provenance,
        "android_ndk_requested",
    )
    if f"go{declared_go_version()}" not in go_actual:
        fail(
            "libbox provenance Go version does not match "
            "etonify-core/go.mod"
        )
    if declared_go_version() != baseline["GO_VERSION"]:
        fail("etonify-core/go.mod does not match ETONIFY_BASELINE GO_VERSION")
    if gomobile_actual != baseline["GOMOBILE_VERSION"]:
        fail(
            "libbox provenance gomobile does not match "
            "ETONIFY_BASELINE GOMOBILE_VERSION"
        )
    if android_ndk_requested != baseline["ANDROID_NDK_VERSION"]:
        fail(
            "libbox provenance android_ndk_requested does not match "
            "ETONIFY_BASELINE ANDROID_NDK_VERSION"
        )
    if (
        re.search(
            rf"\b{re.escape(baseline['JAVA_VERSION'])}(?:\.|\b)",
            java_actual,
        )
        is None
    ):
        fail("libbox provenance Java version does not match ETONIFY_BASELINE")

    source_tags, source_android_api = verify_source()
    recorded_tags = [
        tag.strip()
        for tag in required_string(provenance, "build_tags").split(",")
        if tag.strip()
    ]
    if recorded_tags != source_tags:
        fail(
            "libbox provenance build_tags do not exactly match the "
            "checked-out core builder"
        )
    if provenance.get("android_api") != source_android_api:
        fail(
            "libbox provenance android_api does not match the checked-out "
            f"core builder: {provenance.get('android_api')!r} "
            f"!= {source_android_api}"
        )

    print(
        "Verified libbox.aar "
        f"sha256={actual_hash} source_commit={source_commit} "
        f"protocol_tags={len(source_tags)}"
    )


if __name__ == "__main__":
    try:
        main()
    except (
        OSError,
        subprocess.CalledProcessError,
        TypeError,
        ValueError,
        RuntimeError,
    ) as error:
        print(f"libbox verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
