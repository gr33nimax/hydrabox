"""Write the update signing key as PEM, whatever shape the secret carries.

The secret cannot be read from here, so every shape a release pipeline plausibly stores is
accepted: PEM text (with its newlines real or escaped), base64 of that PEM, base64 of a PKCS#8
DER key, and base64 of the raw 32-byte Ed25519 seed. The last one is wrapped into PKCS#8 here,
because OpenSSL refuses to read a bare seed.

Nothing about the value is printed. A refusal names the shape it could not read and how long it
was — what a person needs to fix it, and nothing that would leak it.
"""

import base64
import binascii
import sys

# A PKCS#8 header for an Ed25519 key: version 0, the algorithm identifier for 1.3.101.112, and an
# octet string wrapping the 32-byte seed.
PKCS8_ED25519_PREFIX = bytes.fromhex("302e020100300506032b657004220420")
SEED_BYTES = 32


def armor(der: bytes) -> str:
    body = base64.b64encode(der).decode("ascii")
    lines = "\n".join(body[at : at + 64] for at in range(0, len(body), 64))
    return f"-----BEGIN PRIVATE KEY-----\n{lines}\n-----END PRIVATE KEY-----\n"


def normalize(raw: str) -> str:
    value = raw.strip()
    # A secret pasted with escaped newlines carries the same key; the escape belongs to the
    # transport, not to the key.
    if "\\n" in value and "-----BEGIN" in value:
        value = value.replace("\\n", "\n")
    if "-----BEGIN" in value:
        return value if value.endswith("\n") else value + "\n"
    try:
        decoded = base64.b64decode(value, validate=False)
    except (binascii.Error, ValueError):
        # The decoding error says nothing a person can act on, and the value must not surface.
        raise SystemExit("update signing key is neither PEM nor base64") from None
    if b"-----BEGIN" in decoded:
        text = decoded.decode("utf-8")
        return text if text.endswith("\n") else text + "\n"
    if decoded.startswith(PKCS8_ED25519_PREFIX):
        return armor(decoded)
    if len(decoded) == SEED_BYTES:
        return armor(PKCS8_ED25519_PREFIX + decoded)
    raise SystemExit(
        f"update signing key decoded to {len(decoded)} bytes, which is not an Ed25519 key"
    )


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as target:
        target.write(normalize(sys.stdin.read()))
