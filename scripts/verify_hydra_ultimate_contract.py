#!/usr/bin/env python3
"""Verify the pinned HYDRA ULTIMATE producer against HydraBox/HydraCore."""

from __future__ import annotations

import base64
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[1]
CORE_JWE_TEST = (
    ROOT
    / "hydracore"
    / "experimental"
    / "libbox"
    / "hydracore_subscription_jwe_test.go"
)
EXPECTED_PROTECTED = {
    "alg": "dir",
    "enc": "A256GCM",
    "typ": "hydra-subscription+jwe",
    "cty": "application/vnd.hydra.subscription+json",
}


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def go_raw_constant(source: str, name: str) -> str:
    match = re.search(rf"const {re.escape(name)} = `([^`]*)`", source)
    if match is None:
        fail(f"HydraCore JWE test is missing {name}")
    return match.group(1)


def decode_base64url(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def verify(producer: Path, expected_commit: str) -> None:
    actual_commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"],
        cwd=producer,
        text=True,
    ).strip()
    if actual_commit != expected_commit:
        fail(
            "HYDRA ULTIMATE checkout mismatch: "
            f"expected {expected_commit}, got {actual_commit}"
        )

    fixture_path = producer / "tests" / "fixtures" / "hydra-jwe-v2.json"
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    key = fixture.get("key")
    if not isinstance(key, str) or re.fullmatch(r"[A-Za-z0-9_-]{43}", key) is None:
        fail("HYDRA ULTIMATE fixture does not contain a 32-byte base64url key")

    envelope = fixture.get("jwe")
    if not isinstance(envelope, dict) or set(envelope) != {
        "protected",
        "encrypted_key",
        "iv",
        "ciphertext",
        "tag",
    }:
        fail("HYDRA ULTIMATE fixture is not strict flattened JWE JSON")
    if envelope["encrypted_key"] != "":
        fail("HYDRA ULTIMATE JWE must use direct encryption")
    protected = json.loads(decode_base64url(envelope["protected"]))
    if protected != EXPECTED_PROTECTED:
        fail("HYDRA ULTIMATE JWE protected header is incompatible")

    plaintext = fixture.get("plaintext")
    if not isinstance(plaintext, dict):
        fail("HYDRA ULTIMATE fixture plaintext must be an object")
    if plaintext.get("api_version") != "hydra.io/subscription/v2":
        fail("HYDRA ULTIMATE fixture is not Subscription v2")

    core_source = CORE_JWE_TEST.read_text(encoding="utf-8")
    core_plaintext = json.loads(go_raw_constant(core_source, "plaintext"))
    core_envelope = json.loads(go_raw_constant(core_source, "expectedEnvelope"))
    if plaintext != core_plaintext:
        fail("producer and HydraCore known-answer plaintext differ")
    if envelope != core_envelope:
        fail("producer and HydraCore known-answer JWE differ")

    producer_source = (
        producer / "hydra" / "services" / "subscriptions" / "hydrabox.py"
    ).read_text(encoding="utf-8")
    for marker in (
        'HYDRABOX_API_VERSION = "hydra.io/subscription/v2"',
        '"subscription-jwe"',
        '"automatic-permissions"',
        '"multi-resource"',
        '"call"',
        '"multi_user"',
        '"call_vk_multi_user"',
    ):
        if marker not in producer_source:
            fail(f"HYDRA ULTIMATE producer is missing contract marker: {marker}")

    calls_runtime_source = (
        producer / "hydra" / "services" / "calls_infrastructure.py"
    ).read_text(encoding="utf-8")
    for marker in (
        'features.get("call_vk_multi_user") is True',
        '"multi_user" in modes',
    ):
        if marker not in calls_runtime_source:
            fail(f"HYDRA ULTIMATE Calls runtime is missing capability gate: {marker}")

    print(
        "Verified HYDRA ULTIMATE producer contract: "
        f"commit={actual_commit}, fixture={fixture_path.name}"
    )


def main() -> None:
    if len(sys.argv) != 3:
        fail(
            "usage: verify_hydra_ultimate_contract.py "
            "<producer-checkout> <expected-commit>"
        )
    verify(Path(sys.argv[1]).resolve(), sys.argv[2].strip())


if __name__ == "__main__":
    try:
        main()
    except (
        json.JSONDecodeError,
        OSError,
        RuntimeError,
        subprocess.CalledProcessError,
        UnicodeDecodeError,
        ValueError,
    ) as error:
        print(f"HYDRA ULTIMATE contract verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
