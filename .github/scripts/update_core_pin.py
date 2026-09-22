"""Repin the HydraCore artifact for an automated channel build (repository_dispatch).

A `core-released` dispatch names the just-published core release. Pinning it means three
files agree: the submodule gitlink, the provenance document, and the AAR the build verifies.
The submodule pointer is moved by the workflow's git step; this writes a provenance document
whose AAR sha256 is the real hash of the release's own AAR, so `verifyLibboxProvenance` (which
checks version, source commit, and AAR digest) passes for a document nobody hand-edited.

The AAR sha256 is not published anywhere as a ready figure: the signed bundle manifest carries
per-.so digests, not the .aar's. So the AAR is downloaded here and hashed, then left in place so
`hydrate_libbox.py` finds it already matching and re-verifies rather than re-downloading.

`upstream.commit` is read from the pinned core's own `release/UPSTREAM_BASELINE` at the
dispatched commit, so the provenance cannot name an upstream the core does not itself claim.
"""

import hashlib
import json
import os
import re
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

ASSET = "hydracore-client-libbox.aar"
CORE_REPOSITORY = "https://github.com/gr33nimax/hydracore"
MAX_AAR_BYTES = 512 * 1024 * 1024


def read_upstream_commit(baseline: Path) -> str:
    text = baseline.read_text(encoding="utf-8")
    match = re.search(r"^UPSTREAM_COMMIT=(\S+)", text, re.MULTILINE)
    if not match:
        raise SystemExit("pinned core UPSTREAM_BASELINE has no UPSTREAM_COMMIT")
    return match.group(1)


def download_and_hash(core_tag: str, target: Path) -> str:
    version = urllib.parse.quote(core_tag, safe="")
    url = f"{CORE_REPOSITORY}/releases/download/{version}/{ASSET}"
    # CORE_REPOSITORY is a fixed https constant and core_tag is percent-encoded, so the scheme
    # cannot be anything but https; assert it so a future edit cannot open file:/custom schemes.
    if not url.startswith("https://"):
        raise SystemExit("refusing a non-https core artifact URL")
    target.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            dir=target.parent, suffix=".part", delete=False
        ) as output:
            temporary = Path(output.name)
            size = 0
            with urllib.request.urlopen(url, timeout=120) as response:  # noqa: S310 (https asserted above)
                while chunk := response.read(1024 * 1024):
                    size += len(chunk)
                    if size > MAX_AAR_BYTES:
                        raise SystemExit("core AAR exceeds size limit")
                    digest.update(chunk)
                    output.write(chunk)
        temporary.replace(target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return digest.hexdigest()


def main() -> None:
    core_tag = os.environ["CORE_TAG"].strip()
    core_commit = os.environ["CORE_COMMIT"].strip()
    if not core_tag or not core_commit:
        raise SystemExit("CORE_TAG and CORE_COMMIT are required")

    root = Path(__file__).resolve().parents[2]
    libs = root / "platform/android/libs"
    provenance_path = libs / "libbox.provenance.json"
    aar_path = libs / "libbox.aar"
    baseline = root / "hydracore/release/UPSTREAM_BASELINE"

    upstream_commit = read_upstream_commit(baseline)
    aar_sha256 = download_and_hash(core_tag, aar_path)

    provenance = {
        "schema_version": 3,
        "distribution": {
            "id": "io.hydrabox.hydracore",
            "name": "HydraCore",
            "version": core_tag,
            "role": "client",
        },
        "source": {
            "repository": CORE_REPOSITORY,
            "commit": core_commit,
            "version": core_tag,
        },
        "upstream": {
            "project": "sing-box-extended",
            "commit": upstream_commit,
        },
        "artifacts": {
            ASSET: {"sha256": aar_sha256},
        },
    }
    provenance_path.write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"Repinned HydraCore to {core_tag} ({core_commit[:12]}), AAR sha256 {aar_sha256}"
    )


if __name__ == "__main__":
    main()
