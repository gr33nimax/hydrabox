#!/usr/bin/env python3
"""Parse and validate HydraCore Android release provenance schema v3."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn


PROVENANCE_SCHEMA_VERSION = 3
LIBBOX_ARTIFACT = "libbox.aar"
LIBBOX_SOURCES_ARTIFACT = "libbox-sources.jar"
LIBBOX_RELEASE_REPOSITORY = "gr33nimax/hydracore"
LIBBOX_RELEASE_BASE_URL = (
    f"https://github.com/{LIBBOX_RELEASE_REPOSITORY}/releases/download"
)
HYDRACORE_DISTRIBUTION_ID = "io.hydrabox.hydracore"
HYDRACORE_DISTRIBUTION_NAME = "HydraCore"
HYDRACORE_UPSTREAM_PROJECT = "sing-box-extended"

_SHA256 = re.compile(r"[0-9a-fA-F]{64}")
_GIT_COMMIT = re.compile(r"[0-9a-fA-F]{40}")
_RELEASE_TAG = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,127}")


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def required_map(value: object, name: str) -> dict[str, object]:
    if not isinstance(value, dict):
        fail(f"libbox provenance {name} must be an object")
    return value


def required_string(value: dict[str, object], key: str, *, prefix: str = "") -> str:
    raw = value.get(key)
    label = f"{prefix}.{key}" if prefix else key
    if not isinstance(raw, str) or not raw.strip():
        fail(f"libbox provenance is missing {label}")
    normalized = raw.strip()
    if any(ord(character) < 32 for character in normalized):
        fail(f"libbox provenance {label} contains control characters")
    return normalized


def required_sha256(artifacts: dict[str, object], name: str) -> str:
    metadata = required_map(artifacts.get(name), f"artifacts.{name}")
    digest = required_string(metadata, "sha256", prefix=f"artifacts.{name}")
    if _SHA256.fullmatch(digest) is None:
        fail(f"libbox provenance artifacts.{name}.sha256 is malformed")
    return digest.lower()


def expected_download_url(release_tag: str, artifact: str = LIBBOX_ARTIFACT) -> str:
    if _RELEASE_TAG.fullmatch(release_tag) is None:
        fail("libbox provenance release tag is not a safe GitHub release tag")
    return f"{LIBBOX_RELEASE_BASE_URL}/{release_tag}/{artifact}"


@dataclass(frozen=True)
class LibboxProvenance:
    raw: dict[str, object]
    sha256: str
    sources_sha256: str
    source_commit: str
    source_version: str
    release_tag: str
    download_url: str
    distribution_id: str
    distribution_name: str
    upstream_project: str
    upstream_commit: str
    upstream_tag: str
    build_tags: tuple[str, ...]
    android_api: int
    android_ndk_requested: str


def parse_provenance(value: object) -> LibboxProvenance:
    provenance = required_map(value, "root")
    if provenance.get("schema_version") != PROVENANCE_SCHEMA_VERSION:
        fail(
            "libbox provenance schema_version must be "
            f"{PROVENANCE_SCHEMA_VERSION}"
        )

    distribution = required_map(provenance.get("distribution"), "distribution")
    distribution_id = required_string(distribution, "id", prefix="distribution")
    distribution_name = required_string(
        distribution, "name", prefix="distribution"
    )
    release_tag = required_string(distribution, "version", prefix="distribution")
    if distribution_id != HYDRACORE_DISTRIBUTION_ID:
        fail("libbox provenance has an unexpected distribution.id")
    if distribution_name != HYDRACORE_DISTRIBUTION_NAME:
        fail("libbox provenance has an unexpected distribution.name")
    if _RELEASE_TAG.fullmatch(release_tag) is None:
        fail("libbox provenance distribution.version is malformed")

    source = required_map(provenance.get("source"), "source")
    source_commit = required_string(source, "commit", prefix="source").lower()
    source_version = required_string(source, "version", prefix="source")
    if _GIT_COMMIT.fullmatch(source_commit) is None:
        fail("libbox provenance source.commit must be a full Git commit")
    if source_version != release_tag:
        fail("libbox provenance source.version must match distribution.version")

    upstream = required_map(provenance.get("upstream"), "upstream")
    upstream_project = required_string(upstream, "project", prefix="upstream")
    upstream_commit = required_string(upstream, "commit", prefix="upstream").lower()
    upstream_tag = required_string(upstream, "tag", prefix="upstream")
    if upstream_project != HYDRACORE_UPSTREAM_PROJECT:
        fail("libbox provenance has an unexpected upstream.project")
    if _GIT_COMMIT.fullmatch(upstream_commit) is None:
        fail("libbox provenance upstream.commit must be a full Git commit")

    toolchain = required_map(provenance.get("toolchain"), "toolchain")
    build_tags_raw = toolchain.get("build_tags")
    if (
        not isinstance(build_tags_raw, list)
        or not build_tags_raw
        or any(not isinstance(tag, str) or not tag for tag in build_tags_raw)
    ):
        fail("libbox provenance toolchain.build_tags must be a non-empty list")
    build_tags = tuple(build_tags_raw)
    if len(set(build_tags)) != len(build_tags):
        fail("libbox provenance toolchain.build_tags contains duplicates")
    for field in ("go", "gomobile", "java"):
        required_string(toolchain, field, prefix="toolchain")

    android = required_map(provenance.get("android"), "android")
    android_api = android.get("api")
    if isinstance(android_api, bool) or not isinstance(android_api, int):
        fail("libbox provenance android.api must be an integer")
    required_string(android, "ndk", prefix="android")
    android_ndk_requested = required_string(
        android, "ndk_requested", prefix="android"
    )

    artifacts = required_map(provenance.get("artifacts"), "artifacts")
    sha256 = required_sha256(artifacts, LIBBOX_ARTIFACT)
    sources_sha256 = required_sha256(artifacts, LIBBOX_SOURCES_ARTIFACT)

    lineage = provenance.get("lineage")
    if not isinstance(lineage, list) or not lineage:
        fail("libbox provenance lineage must be a non-empty list")
    for index, entry in enumerate(lineage):
        item = required_map(entry, f"lineage[{index}]")
        required_string(item, "project", prefix=f"lineage[{index}]")
        required_string(item, "role", prefix=f"lineage[{index}]")

    return LibboxProvenance(
        raw=provenance,
        sha256=sha256,
        sources_sha256=sources_sha256,
        source_commit=source_commit,
        source_version=source_version,
        release_tag=release_tag,
        download_url=expected_download_url(release_tag),
        distribution_id=distribution_id,
        distribution_name=distribution_name,
        upstream_project=upstream_project,
        upstream_commit=upstream_commit,
        upstream_tag=upstream_tag,
        build_tags=build_tags,
        android_api=android_api,
        android_ndk_requested=android_ndk_requested,
    )


def load_provenance(path: Path) -> LibboxProvenance:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"invalid libbox provenance JSON: {error}")
    return parse_provenance(value)


def validate_core_pins(
    provenance: LibboxProvenance,
    *,
    source_commit: str,
    release_tag: str,
    upstream_commit: str,
) -> None:
    if provenance.source_commit != source_commit.strip().lower():
        fail("libbox provenance source.commit does not match the gitlink")
    if provenance.release_tag != release_tag.strip():
        fail("libbox provenance release version does not match HydraCore")
    if provenance.upstream_commit != upstream_commit.strip().lower():
        fail("libbox provenance upstream.commit does not match the baseline")
