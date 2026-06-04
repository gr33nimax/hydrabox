# GitHub Actions for Etonify

This repository contains two useful workflows:

- `CI`: runs Flutter dependency restore, localization generation, optional Pigeon generation, analyzer, and tests.
- `Android Release APK`: builds a signed Android release APK and uploads it as a workflow artifact. When pushed from a tag like `v0.1.0`, it also attaches the APK to a GitHub Release.

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

## Create a Release Keystore

On Windows:

```powershell
keytool -genkeypair -v `
  -keystore etonify-release.jks `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias etonify
```

Keep this file private. If you lose it, you may not be able to update APKs signed with the same identity.

## Convert Keystore to Base64

On Windows:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("etonify-release.jks")) | Set-Clipboard
```

Paste the clipboard value into `ANDROID_KEYSTORE_BASE64`.

Use the keystore password as `ANDROID_KEYSTORE_PASSWORD`, the alias as `ANDROID_KEY_ALIAS`, and the key password as `ANDROID_KEY_PASSWORD`.

## Build a Signed APK

Manual build:

1. Open `Actions`.
2. Select `Android Release APK`.
3. Click `Run workflow`.
4. Download the APK from the workflow artifact.

Release build:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

The workflow will build the APK and attach it to the GitHub Release for that tag.
