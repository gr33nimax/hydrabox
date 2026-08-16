from __future__ import annotations

import hashlib
import io
import json
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from urllib.request import Request


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from fetch_libbox import MAX_DOWNLOAD_BYTES, fetch_libbox  # noqa: E402
from libbox_provenance import (  # noqa: E402
    LIBBOX_ARTIFACT,
    expected_download_url,
    parse_provenance,
)


ROOT = SCRIPTS.parent
PINNED_PROVENANCE = json.loads(
    (ROOT / "android" / "app" / "libs" / "libbox.provenance.json").read_text(
        encoding="utf-8"
    )
)


def provenance_for(payload: bytes) -> dict[str, object]:
    provenance = deepcopy(PINNED_PROVENANCE)
    provenance["artifacts"][LIBBOX_ARTIFACT]["sha256"] = hashlib.sha256(
        payload
    ).hexdigest()
    return provenance


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
        self.headers: dict[str, str] = {}
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
        status: int = 200,
    ) -> None:
        self.payload = payload
        self.content_length = content_length
        self.status = status
        self.requests: list[Request] = []

    def __call__(self, request: Request, *, timeout: int) -> FakeResponse:
        self.requests.append(request)
        return FakeResponse(
            self.payload,
            content_length=self.content_length,
            status=self.status,
        )


class FetchLibboxTest(unittest.TestCase):
    @staticmethod
    def write_provenance(directory: Path, value: dict[str, object]) -> Path:
        path = directory / "libbox.provenance.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_schema_v3_pins_distribution_source_upstream_and_artifacts(self) -> None:
        parsed = parse_provenance(PINNED_PROVENANCE)

        self.assertEqual(parsed.distribution_id, "io.hydrabox.hydracore")
        self.assertEqual(parsed.distribution_name, "HydraCore")
        self.assertEqual(parsed.distribution_role, "client")
        self.assertEqual(
            parsed.release_tag,
            "v1.13.16-extended-hydracore.11-debug.30",
        )
        self.assertEqual(
            parsed.source_commit,
            "527201d9de515cc6f703fc5c7a11cb6d3f4817ac",
        )
        self.assertEqual(
            parsed.upstream_commit,
            "545424b86bc4513f90580ebeab2e2d1514089718",
        )
        self.assertEqual(
            parsed.sha256,
            "8ae3e2ac956bcf5627414a2ebf105bf31a79c99e295ea75b1bdf00de4feee955",
        )

    def test_downloads_only_the_pinned_release_asset(self) -> None:
        payload = b"verified-hydracore-aar" * 2048
        opener = RecordingOpener(payload, content_length=len(payload))
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            provenance_path = self.write_provenance(
                directory, provenance_for(payload)
            )
            destination = directory / "libbox.aar"

            result = fetch_libbox(
                provenance_path,
                destination,
                opener=opener,
            )

            self.assertTrue(result.downloaded)
            self.assertEqual(destination.read_bytes(), payload)
            self.assertEqual(len(opener.requests), 1)
            request = opener.requests[0]
            self.assertEqual(
                request.full_url,
                expected_download_url(PINNED_PROVENANCE["distribution"]["version"]),
            )
            self.assertIsNone(request.get_header("Authorization"))

    def test_matching_destination_skips_network(self) -> None:
        payload = b"already-present"
        opener = RecordingOpener(b"must-not-download")
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            provenance_path = self.write_provenance(
                directory, provenance_for(payload)
            )
            destination = directory / "libbox.aar"
            destination.write_bytes(payload)

            result = fetch_libbox(
                provenance_path,
                destination,
                opener=opener,
            )

            self.assertFalse(result.downloaded)
            self.assertEqual(opener.requests, [])

    def test_checksum_failure_preserves_existing_destination(self) -> None:
        expected = b"expected"
        opener = RecordingOpener(b"tampered")
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            provenance_path = self.write_provenance(
                directory, provenance_for(expected)
            )
            destination = directory / "libbox.aar"
            destination.write_bytes(b"old")

            with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                fetch_libbox(
                    provenance_path,
                    destination,
                    opener=opener,
                )

            self.assertEqual(destination.read_bytes(), b"old")
            self.assertEqual(list(directory.glob(".libbox.aar.*.tmp")), [])

    def test_oversized_content_length_fails_before_download(self) -> None:
        payload = b"expected"
        opener = RecordingOpener(
            payload,
            content_length=MAX_DOWNLOAD_BYTES + 1,
        )
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            provenance_path = self.write_provenance(
                directory, provenance_for(payload)
            )

            with self.assertRaisesRegex(RuntimeError, "Content-Length"):
                fetch_libbox(
                    provenance_path,
                    directory / "libbox.aar",
                    opener=opener,
                )

    def test_malformed_or_legacy_provenance_fails_closed(self) -> None:
        for mutate in (
            lambda value: value.update(schema_version=2),
            lambda value: value["distribution"].update(id="other.core"),
            lambda value: value["source"].update(commit="short"),
            lambda value: value["upstream"].update(project="other"),
            lambda value: value["artifacts"][LIBBOX_ARTIFACT].update(
                sha256="invalid"
            ),
        ):
            value = deepcopy(PINNED_PROVENANCE)
            mutate(value)
            with self.subTest(value=value):
                with self.assertRaises(RuntimeError):
                    parse_provenance(value)


if __name__ == "__main__":
    unittest.main()
