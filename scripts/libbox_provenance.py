#!/usr/bin/env python3
"""Parse and validate the pinned Android libbox release provenance."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn


PROVENANCE_SCHEMA_VERSION = 2
LIBBOX_ARTIFACT = "libbox.aar"
LIBBOX_RELEASE_REPOSITORY = "gr33nimax/etonify-core"
LIBBOX_RELEASE_BASE_URL = (
    f"https://github.com/{LIBBOX_RELEASE_REPOSITORY}/releases/download"
)
HYDRACORE_DISTRIBUTION_ID = "io.hydrabox.hydracore"
HYDRACORE_DISTRIBUTION_NAME = "HydraCore"
HYDRACORE_UPSTREAM_PROJECT = "etonify-core"

_SHA256 = re.compile(r"[0-9a-fA-F]{64}")
_GIT_COMMIT = re.compile(r"[0-9a-fA-F]{40}")
_RELEASE_TAG = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,127}")


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def required_string(provenance: dict[str, object], key: str) -> str:
    value = provenance.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"libbox provenance is missing {key}")
    normalized = value.strip()
    if any(ord(character) < 32 for character in normalized):
        fail(f"libbox provenance {key} contains control characters")
    return normalized


def expected_download_url(release_tag: str) -> str:
    if _RELEASE_TAG.fullmatch(release_tag) is None:
        fail("libbox provenance release_tag is not a safe GitHub release tag")
    return f"{LIBBOX_RELEASE_BASE_URL}/{release_tag}/{LIBBOX_ARTIFACT}"


@dataclass(frozen=True)
class LibboxProvenance:
    """Security-sensitive fields needed to fetch and verify libbox.aar."""

    raw: dict[str, object]
    sha256: str
    size_bytes: int
    source_commit: str
    core_version: str
    release_tag: str
    download_url: str
    distribution_id: str
    distribution_name: str
    upstream_project: str
    etonify_version: str


def parse_provenance(value: object) -> LibboxProvenance:
    if not isinstance(value, dict):
        fail("libbox provenance must be a JSON object")
    provenance: dict[str, object] = value

    if provenance.get("schema_version") != PROVENANCE_SCHEMA_VERSION:
        fail(
            "libbox provenance schema_version must be "
            f"{PROVENANCE_SCHEMA_VERSION}"
        )
    if provenance.get("artifact") != LIBBOX_ARTIFACT:
        fail("libbox provenance has an unexpected artifact name")

    distribution_id = required_string(provenance, "distribution_id")
    if distribution_id != HYDRACORE_DISTRIBUTION_ID:
        fail("libbox provenance has an unexpected distribution_id")
    distribution_name = required_string(provenance, "distribution_name")
    if distribution_name != HYDRACORE_DISTRIBUTION_NAME:
        fail("libbox provenance has an unexpected distribution_name")
    upstream_project = required_string(provenance, "upstream_project")
    if upstream_project != HYDRACORE_UPSTREAM_PROJECT:
        fail("libbox provenance has an unexpected upstream_project")
    etonify_version = required_string(provenance, "etonify_version")
    if _RELEASE_TAG.fullmatch(etonify_version) is None:
        fail("libbox provenance etonify_version is not a safe version tag")

    expected_sha256 = required_string(provenance, "sha256")
    if _SHA256.fullmatch(expected_sha256) is None:
        fail("libbox provenance sha256 must be a 64-character hex digest")

    size_bytes = provenance.get("size_bytes")
    if (
        isinstance(size_bytes, bool)
        or not isinstance(size_bytes, int)
        or size_bytes <= 0
    ):
        fail("libbox provenance size_bytes must be a positive integer")

    source_commit = required_string(provenance, "source_commit")
    if _GIT_COMMIT.fullmatch(source_commit) is None:
        fail("libbox provenance source_commit must be a full Git commit")

    core_version = required_string(provenance, "core_version")
    release_tag = required_string(provenance, "release_tag")
    pinned_download_url = expected_download_url(release_tag)
    download_url = required_string(provenance, "download_url")
    if download_url != pinned_download_url:
        fail(
            "libbox provenance download_url must exactly match the pinned "
            f"release asset: {pinned_download_url}"
        )

    return LibboxProvenance(
        raw=provenance,
        sha256=expected_sha256.lower(),
        size_bytes=size_bytes,
        source_commit=source_commit.lower(),
        core_version=core_version,
        release_tag=release_tag,
        download_url=download_url,
        distribution_id=distribution_id,
        distribution_name=distribution_name,
        upstream_project=upstream_project,
        etonify_version=etonify_version,
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
    etonify_version: str,
) -> None:
    expected_commit = source_commit.strip().lower()
    if provenance.source_commit != expected_commit:
        fail(
            "libbox provenance source_commit does not match the pinned core: "
            f"{provenance.source_commit} != {expected_commit}"
        )
    expected_release_tag = release_tag.strip()
    if provenance.release_tag != expected_release_tag:
        fail(
            "libbox provenance release_tag does not match the pinned core "
            f"version: {provenance.release_tag} != {expected_release_tag}"
        )
    expected_etonify_version = etonify_version.strip()
    if provenance.etonify_version != expected_etonify_version:
        fail(
            "libbox provenance etonify_version does not match the pinned "
            "Etonify provenance version: "
            f"{provenance.etonify_version} != {expected_etonify_version}"
        )
