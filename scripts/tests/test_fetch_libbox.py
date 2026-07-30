from __future__ import annotations

import hashlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from urllib.request import Request


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from fetch_libbox import fetch_libbox  # noqa: E402
from libbox_provenance import (  # noqa: E402
    expected_download_url,
    parse_provenance,
)


ROOT = SCRIPTS.parent
RELEASE_TAG = (
    ROOT / "etonify-core" / "release" / "ETONIFY_VERSION"
).read_text(encoding="utf-8").strip()
SOURCE_COMMIT = subprocess.check_output(
    ["git", "rev-parse", "HEAD:etonify-core"],
    cwd=ROOT,
    text=True,
).strip()


def provenance_for(payload: bytes) -> dict[str, object]:
    return {
        "schema_version": 2,
        "artifact": "libbox.aar",
        "sha256": hashlib.sha256(payload).hexdigest(),
        "size_bytes": len(payload),
        "source_commit": SOURCE_COMMIT,
        "core_version": "v1.13.14-extended-2.5.3-2-g060ece46a",
        "release_tag": RELEASE_TAG,
        "download_url": expected_download_url(RELEASE_TAG),
    }


class FakeResponse(io.BytesIO):
    def __init__(
        self,
        payload: bytes,
        *,
        content_length: int | None = None,
        status: int = 200,
    ) -> None:
        super().__init__(payload)
        self.status = status
        self.headers = {}
        if content_length is not None:
            self.headers["Content-Length"] = str(content_length)

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()


class RecordingOpener:
    def __init__(
        self,
        payload: bytes,
        *,
        content_length: int | None = None,
    ) -> None:
        self.payload = payload
        self.content_length = content_length
        self.requests: list[Request] = []
        self.timeouts: list[int] = []

    def __call__(
        self,
        request: Request,
        *,
        timeout: int,
    ) -> FakeResponse:
        self.requests.append(request)
        self.timeouts.append(timeout)
        return FakeResponse(
            self.payload,
            content_length=self.content_length,
        )


class FetchLibboxTest(unittest.TestCase):
    def write_provenance(
        self,
        directory: Path,
        provenance: dict[str, object],
    ) -> Path:
        path = directory / "libbox.provenance.json"
        path.write_text(
            json.dumps(provenance),
            encoding="utf-8",
        )
        return path

    def temporary_files(self, directory: Path) -> list[Path]:
        return list(directory.glob(".libbox.aar.*.tmp"))

    def test_downloads_validated_asset_without_authorization_header(self) -> None:
        payload = (b"verified-libbox" * 100_000) + b"!"
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            destination = directory / "libbox.aar"
            destination.write_bytes(b"old artifact")
            provenance = provenance_for(payload)
            provenance_path = self.write_provenance(directory, provenance)
            opener = RecordingOpener(
                payload,
                content_length=len(payload),
            )

            result = fetch_libbox(
                provenance_path,
                destination,
                opener=opener,
            )

            self.assertTrue(result.downloaded)
            self.assertEqual(destination.read_bytes(), payload)
            self.assertEqual(result.sha256, provenance["sha256"])
            self.assertEqual(result.size_bytes, len(payload))
            self.assertEqual(len(opener.requests), 1)
            request = opener.requests[0]
            self.assertEqual(
                request.full_url,
                expected_download_url(RELEASE_TAG),
            )
            self.assertIsNone(request.get_header("Authorization"))
            self.assertEqual(self.temporary_files(directory), [])

    def test_matching_destination_is_idempotent_and_skips_network(self) -> None:
        payload = b"already-present"
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            destination = directory / "libbox.aar"
            destination.write_bytes(payload)
            provenance_path = self.write_provenance(
                directory,
                provenance_for(payload),
            )

            def forbidden_opener(*args: object, **kwargs: object) -> None:
                self.fail("network must not be used for a verified destination")

            result = fetch_libbox(
                provenance_path,
                destination,
                opener=forbidden_opener,
            )

            self.assertFalse(result.downloaded)
            self.assertEqual(destination.read_bytes(), payload)
            self.assertEqual(self.temporary_files(directory), [])

    def test_rejects_non_pinned_url_before_opening_network(self) -> None:
        payload = b"payload"
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            destination = directory / "libbox.aar"
            destination.write_bytes(b"keep me")
            provenance = provenance_for(payload)
            provenance["download_url"] = (
                "https://example.invalid/releases/download/"
                f"{RELEASE_TAG}/libbox.aar"
            )
            provenance_path = self.write_provenance(directory, provenance)
            opener = RecordingOpener(payload)

            with self.assertRaisesRegex(
                RuntimeError,
                "must exactly match the pinned release asset",
            ):
                fetch_libbox(
                    provenance_path,
                    destination,
                    opener=opener,
                )

            self.assertEqual(opener.requests, [])
            self.assertEqual(destination.read_bytes(), b"keep me")
            self.assertEqual(self.temporary_files(directory), [])

    def test_checksum_failure_preserves_destination_and_cleans_temp(self) -> None:
        expected = b"expected"
        downloaded = b"tampered"
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            destination = directory / "libbox.aar"
            destination.write_bytes(b"keep me")
            provenance = provenance_for(expected)
            provenance["size_bytes"] = len(downloaded)
            provenance_path = self.write_provenance(directory, provenance)

            with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                fetch_libbox(
                    provenance_path,
                    destination,
                    opener=RecordingOpener(downloaded),
                )

            self.assertEqual(destination.read_bytes(), b"keep me")
            self.assertEqual(self.temporary_files(directory), [])

    def test_content_length_failure_preserves_destination(self) -> None:
        payload = b"expected"
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            destination = directory / "libbox.aar"
            destination.write_bytes(b"keep me")
            provenance_path = self.write_provenance(
                directory,
                provenance_for(payload),
            )

            with self.assertRaisesRegex(
                RuntimeError,
                "Content-Length mismatch",
            ):
                fetch_libbox(
                    provenance_path,
                    destination,
                    opener=RecordingOpener(
                        payload,
                        content_length=len(payload) + 1,
                    ),
                )

            self.assertEqual(destination.read_bytes(), b"keep me")
            self.assertEqual(self.temporary_files(directory), [])

    def test_requires_full_source_commit_and_safe_release_tag(self) -> None:
        provenance = provenance_for(b"payload")
        provenance["source_commit"] = "060ece46"
        with self.assertRaisesRegex(RuntimeError, "full Git commit"):
            parse_provenance(provenance)

        provenance = provenance_for(b"payload")
        provenance["release_tag"] = "../other-release"
        with self.assertRaisesRegex(RuntimeError, "safe GitHub release tag"):
            parse_provenance(provenance)

    def test_rejects_unpinned_source_commit_before_network(self) -> None:
        payload = b"payload"
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            destination = directory / "libbox.aar"
            provenance = provenance_for(payload)
            provenance["source_commit"] = "f" * 40
            provenance_path = self.write_provenance(directory, provenance)
            opener = RecordingOpener(payload)

            with self.assertRaisesRegex(
                RuntimeError,
                "source_commit does not match the pinned core",
            ):
                fetch_libbox(
                    provenance_path,
                    destination,
                    opener=opener,
                )

            self.assertEqual(opener.requests, [])
            self.assertFalse(destination.exists())
            self.assertEqual(self.temporary_files(directory), [])

    def test_rejects_unpinned_release_version_before_network(self) -> None:
        payload = b"payload"
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            destination = directory / "libbox.aar"
            provenance = provenance_for(payload)
            provenance["release_tag"] = "v9.9.9-other"
            provenance["download_url"] = expected_download_url(
                "v9.9.9-other"
            )
            provenance_path = self.write_provenance(directory, provenance)
            opener = RecordingOpener(payload)

            with self.assertRaisesRegex(
                RuntimeError,
                "release_tag does not match the pinned core version",
            ):
                fetch_libbox(
                    provenance_path,
                    destination,
                    opener=opener,
                )

            self.assertEqual(opener.requests, [])
            self.assertFalse(destination.exists())
            self.assertEqual(self.temporary_files(directory), [])


if __name__ == "__main__":
    unittest.main()
