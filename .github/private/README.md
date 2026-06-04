# Private Build Inputs

Official release builds can restore private Happ crypto compatibility assets from an encrypted archive:

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

The GPG passphrase is stored in the repository secret:

```text
HAPP_CRYPTO_ASSETS_PASSPHRASE
```

Do not commit the raw `assets/happ_crypto` folder or the unencrypted zip archive.
