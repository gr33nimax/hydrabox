# GitHub Actions for HydraBox

This repository uses GitHub Actions as the authoritative build and verification
environment:

- `HydraBox · Client checks` restores dependencies, generates localization and
  Pigeon bindings, runs the analyzer and tests, then runs Android unit/lint and
  debug assembly gates.
- `HydraBox · CodeQL security` runs the repository security scan.
- `HydraBox · Test APK` creates a clearly marked debug-signed test artifact.
- `HydraBox · Android release` builds signed APKs for `universal`, `arm64-v8a`,
  `armeabi-v7a`, and `x86_64`, publishes updater metadata, and creates or
  updates a draft GitHub Release.
- `HydraCore · Sync extended libbox` rebuilds the pinned core, verifies its
  published release provenance, updates the checked-in metadata/source JAR,
  and dispatches the client checks for the resulting commit.

## Required Repository Secrets

Open the repository on GitHub and go to:

`Settings -> Secrets and variables -> Actions -> New repository secret`

Create these secrets:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

`HAPP_CRYPTO_ASSETS_PASSPHRASE` is optional and must be configured only when
the distributor has independently verified rights to restore and redistribute
the inherited Happ assets.

## Create a Release Keystore

On Windows:

```powershell
keytool -genkeypair -v `
  -keystore hydrabox-release.jks `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias hydrabox
```

Keep this file private. If you lose it, you may not be able to update APKs
signed with the same identity. Retaining `com.etonify.meow_client` alone does
not make HydraBox an installable upgrade from Etonify: that also requires an
authorized matching signing certificate or signing lineage.

## Convert Keystore to Base64

On Windows:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("hydrabox-release.jks")) | Set-Clipboard
```

Paste the clipboard value into `ANDROID_KEYSTORE_BASE64`.

Use the keystore password as `ANDROID_KEYSTORE_PASSWORD`, the alias as `ANDROID_KEY_ALIAS`, and the key password as `ANDROID_KEY_PASSWORD`.

## Add Private Happ Crypto Assets

GitHub Actions secrets are limited to 48 KB, so the public repository does not store raw `assets/happ_crypto` and does not store a large base64 zip secret.

An inherited encrypted archive may be committed to the repository:

```text
.github/private/happ_crypto_assets.zip.gpg
```

Encryption does not grant redistribution rights. The workflow leaves these
assets excluded by default. A distributor may enable the
`include_private_happ_assets` input and configure
`HAPP_CRYPTO_ASSETS_PASSPHRASE` only after verifying the necessary rights.

Create a zip archive from your local private assets:

```powershell
$zip = Join-Path $PWD.Path "happ_crypto_assets.zip"
Compress-Archive -Path ".\assets\happ_crypto\*" -DestinationPath $zip -Force
```

Encrypt the zip with GPG:

```powershell
New-Item -ItemType Directory -Force .github\private | Out-Null
gpg --symmetric --cipher-algo AES256 --output .github\private\happ_crypto_assets.zip.gpg $zip
```

Use the same passphrase you typed into GPG as `HAPP_CRYPTO_ASSETS_PASSPHRASE`.

When explicitly enabled, the release workflow validates that these files are
present after restore:

```text
selectors.json
expanded_rsa_keys.json
crypt51_rsa_keys.json
native_rsa_keys.json
```

APK obfuscation can make casual reverse engineering harder, but it does not
make bundled assets secret or change their license. See [NOTICE.md](../NOTICE.md).

## Build Signed APKs

Manual build:

1. Open `Actions`.
2. Select `HydraBox · Android release`.
3. Click `Run workflow`.
4. Use `build_name` as `0.1.0` or `v0.1.0`; both are normalized.
5. Leave `include_private_happ_assets` disabled unless redistribution rights
   have been verified.
6. Download APKs from the workflow artifact or from the created draft release.

The checked-in workflow is manual (`workflow_dispatch`); pushing a tag alone
does not start a release build.

The workflow normalizes release metadata like this:

```text
input:         0.1.0 or v0.1.0
release tag:  0.1.0
release title: v0.1.0
```

HydraBox builds keep automatic updates disabled unless both
`HYDRABOX_UPDATE_REPOSITORY_OWNER` and `HYDRABOX_UPDATE_REPOSITORY_NAME` are
provided as Dart defines. The Android release workflow derives both values from
its GitHub-provided `GITHUB_REPOSITORY` (`owner/name`), so a release build follows
the repository that produced it instead of consuming the upstream Etonify
release channel.

When a HydraBox-controlled source is configured, the updater expects these
release asset names:

```text
hydrabox-v0.1.0-universal.apk
hydrabox-v0.1.0-arm64-v8a.apk
hydrabox-v0.1.0-armeabi-v7a.apk
hydrabox-v0.1.0-x86_64.apk
```

The app first looks for the APK matching the current device ABI, then falls back to `universal`.
