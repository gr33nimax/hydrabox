#!/usr/bin/env python3
"""Verify bundled HydraCore Android artifacts against source and provenance."""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import NoReturn

from libbox_provenance import load_provenance, validate_core_pins
from verify_extended_core import read_upstream_baseline, verify_source


ROOT = Path(__file__).resolve().parents[1]
LIBS = ROOT / "android" / "app" / "libs"
AAR = LIBS / "libbox.aar"
SOURCES = LIBS / "libbox-sources.jar"
HASH_FILE = LIBS / "libbox.sha256"
PROVENANCE_FILE = LIBS / "libbox.provenance.json"
CORE_PATH = ROOT / "hydracore"
VERSION_FILE = CORE_PATH / "release" / "HYDRACORE_VERSION"
GITMODULES = ROOT / ".gitmodules"
REQUIRED_ANDROID_ABIS = {"armeabi-v7a", "arm64-v8a", "x86", "x86_64"}
LIBBOX_SOURCE = "io/nekohasekai/libbox/Libbox.java"
REQUIRED_HYDRACORE_JAVA_METHODS = {
    "hydraCoreCapabilities()",
    "hydraCoreBuildInfo()",
    "hydraCoreValidateConfig(String configContent, String profile)",
    "hydraCoreValidateSubscription(String content)",
    "hydraCoreInspectSubscription(String content)",
    "hydraCoreOpenSubscriptionJWE(String envelope, String keyBase64URL)",
    "hydraCoreValidateSubscriptionJWE(String envelope, String keyBase64URL)",
    "hydraCoreInspectSubscriptionJWE(String envelope, String keyBase64URL)",
}


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
        ["git", *args], cwd=cwd, text=True, stderr=subprocess.STDOUT
    ).strip()


def tracked_gitlink_commit() -> str:
    line = git("ls-files", "--stage", "--", "hydracore")
    match = re.fullmatch(r"160000 ([0-9a-f]{40}) 0\thydracore", line)
    if match is None:
        fail("hydracore must be tracked as a Git submodule")
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
            f"submodule.hydracore.{name}",
        )
    except subprocess.CalledProcessError:
        fail(f".gitmodules is missing the hydracore {name}")
    if not value:
        fail(f".gitmodules has an empty hydracore {name}")
    return value


def normalize_repository(value: str) -> str:
    normalized = value.strip().rstrip("/")
    if normalized.lower().endswith(".git"):
        normalized = normalized[:-4]
    return normalized.lower()


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
                if (match := re.fullmatch(r"jni/([^/]+)/libbox\.so", name))
            }
            missing_abis = sorted(REQUIRED_ANDROID_ABIS - present_abis)
            if missing_abis:
                fail("libbox.aar is missing Android ABIs: " + ", ".join(missing_abis))
        with zipfile.ZipFile(SOURCES) as archive:
            corrupt_member = archive.testzip()
            if corrupt_member is not None:
                fail(f"libbox-sources.jar has a corrupt member: {corrupt_member}")
            if not any(name.endswith(".java") for name in archive.namelist()):
                fail("libbox-sources.jar does not contain generated Java sources")
            if LIBBOX_SOURCE not in archive.namelist():
                fail("libbox-sources.jar does not contain Libbox.java")
            libbox_source = archive.read(LIBBOX_SOURCE).decode("utf-8")
            missing_methods = sorted(
                method
                for method in REQUIRED_HYDRACORE_JAVA_METHODS
                if method not in libbox_source
            )
            if missing_methods:
                fail(
                    "libbox Android API is missing HydraCore methods: "
                    + ", ".join(missing_methods)
                )
    except zipfile.BadZipFile as error:
        fail(f"invalid libbox archive: {error}")


def main() -> None:
    if not AAR.is_file():
        fail("android/app/libs/libbox.aar is missing; run scripts/fetch_libbox.py")
    if not SOURCES.is_file() or not HASH_FILE.is_file():
        fail("bundled libbox metadata is incomplete")

    build_tags, android_api = verify_source()
    provenance = load_provenance(PROVENANCE_FILE)
    baseline = read_upstream_baseline()
    release_tag = VERSION_FILE.read_text(encoding="utf-8").strip()
    validate_core_pins(
        provenance,
        source_commit=tracked_gitlink_commit(),
        release_tag=release_tag,
        upstream_commit=baseline["UPSTREAM_COMMIT"],
    )

    if normalize_repository(submodule_setting("url")) != normalize_repository(
        str(provenance.raw["source"]["repository"])
    ):
        fail("HydraCore submodule URL does not match provenance")
    if submodule_setting("branch") != "main":
        fail("HydraCore submodule branch must be main")
    if list(provenance.build_tags) != build_tags:
        fail("bundled AAR build tags do not match UPSTREAM_BASELINE")
    if provenance.android_api != android_api:
        fail("bundled AAR Android API does not match UPSTREAM_BASELINE")
    if provenance.android_ndk_requested != baseline["ANDROID_NDK_VERSION"]:
        fail("bundled AAR NDK does not match UPSTREAM_BASELINE")

    actual_aar_sha = sha256(AAR)
    if actual_aar_sha != provenance.sha256:
        fail("libbox.aar does not match provenance")
    checksum_fields = HASH_FILE.read_text(encoding="utf-8").strip().split()
    if not checksum_fields or checksum_fields[0].lower() != actual_aar_sha:
        fail("libbox.sha256 does not match libbox.aar")
    if sha256(SOURCES) != provenance.sources_sha256:
        fail("libbox-sources.jar does not match provenance")

    validate_archives()
    print(
        "Verified HydraCore Android distribution: "
        f"{release_tag}, API {android_api}, {len(build_tags)} build tags, "
        f"sha256={actual_aar_sha}"
    )


if __name__ == "__main__":
    try:
        main()
    except (
        OSError,
        RuntimeError,
        subprocess.CalledProcessError,
        TypeError,
        ValueError,
    ) as error:
        print(f"libbox verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
