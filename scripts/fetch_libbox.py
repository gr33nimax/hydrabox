#!/usr/bin/env python3
"""Hydrate the pinned libbox.aar from its verified public core release."""

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

from libbox_provenance import (
    LibboxProvenance,
    load_provenance,
    validate_core_pins,
)


ROOT = Path(__file__).resolve().parents[1]
LIBS = ROOT / "android" / "app" / "libs"
AAR = LIBS / "libbox.aar"
PROVENANCE_FILE = LIBS / "libbox.provenance.json"
CORE_VERSION_FILE = ROOT / "etonify-core" / "release" / "ETONIFY_VERSION"
DOWNLOAD_CHUNK_SIZE = 1024 * 1024
DOWNLOAD_TIMEOUT_SECONDS = 120
USER_AGENT = "Etonify-libbox-hydrator/1"


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def sha256_and_size(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(DOWNLOAD_CHUNK_SIZE), b""):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def pinned_core_commit() -> str:
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD:etonify-core"],
        cwd=ROOT,
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()


def pinned_release_tag() -> str:
    if not CORE_VERSION_FILE.is_file():
        fail("etonify-core/release/ETONIFY_VERSION is missing")
    value = CORE_VERSION_FILE.read_text(encoding="utf-8").strip()
    if not value:
        fail("etonify-core/release/ETONIFY_VERSION is empty")
    return value


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
    if destination.is_symlink():
        fail(f"refusing to inspect symlink destination: {destination}")
    if not destination.is_file():
        fail(f"libbox destination is not a regular file: {destination}")
    if destination.stat().st_size != provenance.size_bytes:
        return False
    actual_sha256, actual_size = sha256_and_size(destination)
    return (
        actual_size == provenance.size_bytes
        and actual_sha256 == provenance.sha256
    )


def fetch_libbox(
    provenance_path: Path = PROVENANCE_FILE,
    destination: Path = AAR,
    *,
    opener: Opener = urllib.request.urlopen,
) -> FetchResult:
    """Download and atomically install the provenance-pinned AAR.

    ``opener`` is dependency injection for network-free unit tests. Production
    callers cannot override the validated URL through the CLI or environment.
    """

    provenance = load_provenance(provenance_path)
    validate_core_pins(
        provenance,
        source_commit=pinned_core_commit(),
        release_tag=pinned_release_tag(),
    )
    if destination.name != provenance.raw["artifact"]:
        fail(
            "libbox destination filename does not match provenance artifact: "
            f"{destination.name}"
        )
    if _is_current(destination, provenance):
        return FetchResult(
            destination=destination,
            downloaded=False,
            sha256=provenance.sha256,
            size_bytes=provenance.size_bytes,
        )

    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        fail(f"refusing to replace symlink destination: {destination}")

    request = urllib.request.Request(
        provenance.download_url,
        headers={
            "Accept": "application/octet-stream",
            "User-Agent": USER_AGENT,
        },
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

            with opener(
                request,
                timeout=DOWNLOAD_TIMEOUT_SECONDS,
            ) as response:
                status = getattr(response, "status", 200)
                if status != 200:
                    fail(f"libbox download returned HTTP status {status}")
                headers = getattr(response, "headers", {})
                content_length = headers.get("Content-Length")
                if content_length is not None:
                    try:
                        reported_size = int(content_length)
                    except (TypeError, ValueError):
                        fail(
                            "libbox download returned an invalid "
                            "Content-Length"
                        )
                    if reported_size != provenance.size_bytes:
                        fail(
                            "libbox download Content-Length mismatch: "
                            f"expected {provenance.size_bytes}, "
                            f"got {reported_size}"
                        )

                while True:
                    block = response.read(DOWNLOAD_CHUNK_SIZE)
                    if not block:
                        break
                    received_size += len(block)
                    if received_size > provenance.size_bytes:
                        fail(
                            "libbox download exceeded the expected size: "
                            f"{provenance.size_bytes} bytes"
                        )
                    digest.update(block)
                    temporary.write(block)

            actual_sha256 = digest.hexdigest()
            if received_size != provenance.size_bytes:
                fail(
                    "libbox download size mismatch: "
                    f"expected {provenance.size_bytes}, got {received_size}"
                )
            if actual_sha256 != provenance.sha256:
                fail(
                    "libbox download SHA-256 mismatch: "
                    f"expected {provenance.sha256}, got {actual_sha256}"
                )
            temporary.flush()
            os.fsync(temporary.fileno())

        os.replace(temporary_path, destination)
        temporary_path = None
        return FetchResult(
            destination=destination,
            downloaded=True,
            sha256=provenance.sha256,
            size_bytes=provenance.size_bytes,
        )
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
