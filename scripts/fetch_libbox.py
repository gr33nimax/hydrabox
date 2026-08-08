#!/usr/bin/env python3
"""Hydrate libbox.aar from the pinned, provenance-verified HydraCore release."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Callable, NoReturn

from libbox_provenance import LibboxProvenance, load_provenance, validate_core_pins


ROOT = Path(__file__).resolve().parents[1]
LIBS = ROOT / "android" / "app" / "libs"
AAR = LIBS / "libbox.aar"
PROVENANCE_FILE = LIBS / "libbox.provenance.json"
CORE_PATH = ROOT / "hydracore"
CORE_VERSION_FILE = CORE_PATH / "release" / "HYDRACORE_VERSION"
UPSTREAM_BASELINE_FILE = CORE_PATH / "release" / "UPSTREAM_BASELINE"
DOWNLOAD_CHUNK_SIZE = 1024 * 1024
DOWNLOAD_TIMEOUT_SECONDS = 120
MAX_DOWNLOAD_BYTES = 200 * 1024 * 1024
USER_AGENT = "HydraBox-HydraCore-hydrator/2"


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def sha256_and_size(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(DOWNLOAD_CHUNK_SIZE), b""):
            digest.update(block)
            size += len(block)
            if size > MAX_DOWNLOAD_BYTES:
                fail("libbox archive exceeds the client safety limit")
    return digest.hexdigest(), size


def pinned_core_commit() -> str:
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD:hydracore"],
        cwd=ROOT,
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()


def pinned_release_tag() -> str:
    if not CORE_VERSION_FILE.is_file():
        fail("hydracore/release/HYDRACORE_VERSION is missing")
    value = CORE_VERSION_FILE.read_text(encoding="utf-8").strip()
    if not value:
        fail("hydracore/release/HYDRACORE_VERSION is empty")
    return value


def pinned_upstream_commit() -> str:
    if not UPSTREAM_BASELINE_FILE.is_file():
        fail("hydracore/release/UPSTREAM_BASELINE is missing")
    for line in UPSTREAM_BASELINE_FILE.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if separator and key.strip() == "UPSTREAM_COMMIT":
            return value.strip()
    fail("hydracore/release/UPSTREAM_BASELINE has no UPSTREAM_COMMIT")


@dataclass(frozen=True)
class FetchResult:
    destination: Path
    downloaded: bool
    sha256: str
    size_bytes: int


Opener = Callable[..., BinaryIO]


def _is_current(destination: Path, provenance: LibboxProvenance) -> bool:
    if not destination.exists():
        return False
    if destination.is_symlink() or not destination.is_file():
        fail(f"libbox destination is not a regular file: {destination}")
    digest, _ = sha256_and_size(destination)
    return digest == provenance.sha256


def fetch_libbox(
    provenance_path: Path = PROVENANCE_FILE,
    destination: Path = AAR,
    *,
    opener: Opener = urllib.request.urlopen,
) -> FetchResult:
    provenance = load_provenance(provenance_path)
    validate_core_pins(
        provenance,
        source_commit=pinned_core_commit(),
        release_tag=pinned_release_tag(),
        upstream_commit=pinned_upstream_commit(),
    )
    if _is_current(destination, provenance):
        _, size = sha256_and_size(destination)
        return FetchResult(destination, False, provenance.sha256, size)

    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        fail(f"refusing to replace symlink destination: {destination}")
    request = urllib.request.Request(
        provenance.download_url,
        headers={"Accept": "application/octet-stream", "User-Agent": USER_AGENT},
        method="GET",
    )
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w+b",
            prefix=f".{destination.name}.",
            suffix=".tmp",
            dir=destination.parent,
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            digest = hashlib.sha256()
            received_size = 0
            with opener(request, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response:
                status = getattr(response, "status", 200)
                if status != 200:
                    fail(f"libbox download returned HTTP status {status}")
                length = getattr(response, "headers", {}).get("Content-Length")
                if length is not None and int(length) > MAX_DOWNLOAD_BYTES:
                    fail("libbox Content-Length exceeds the client safety limit")
                while True:
                    block = response.read(DOWNLOAD_CHUNK_SIZE)
                    if not block:
                        break
                    received_size += len(block)
                    if received_size > MAX_DOWNLOAD_BYTES:
                        fail("libbox download exceeds the client safety limit")
                    digest.update(block)
                    temporary.write(block)
            if received_size == 0:
                fail("libbox download is empty")
            actual_sha256 = digest.hexdigest()
            if actual_sha256 != provenance.sha256:
                fail(
                    "libbox download SHA-256 mismatch: "
                    f"expected {provenance.sha256}, got {actual_sha256}"
                )
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, destination)
        temporary_path = None
        return FetchResult(destination, True, provenance.sha256, received_size)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def main() -> None:
    result = fetch_libbox()
    state = "Downloaded" if result.downloaded else "Already verified"
    print(
        f"{state} {result.destination.relative_to(ROOT)} "
        f"sha256={result.sha256} size={result.size_bytes}"
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
        print(f"libbox fetch failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
