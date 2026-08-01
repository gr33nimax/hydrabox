# Inherited Private Build Inputs

An encrypted Happ compatibility archive may be present for inherited workflow
compatibility:

```text
.github/private/happ_crypto_assets.zip.gpg
```

The decrypted archive must contain:

```text
selectors.json
expanded_rsa_keys.json
crypt51_rsa_keys.json
native_rsa_keys.json
```

Encryption does not grant permission to redistribute the archive or its
decrypted contents. The HydraBox release workflow excludes these assets by
default. A distributor must verify its rights before enabling the
`include_private_happ_assets` workflow input.

When those rights have been verified, the GPG passphrase can be stored in the
repository secret:

```text
HAPP_CRYPTO_ASSETS_PASSPHRASE
```

Do not commit the raw `assets/happ_crypto` folder or the unencrypted zip archive.
