"""Collect a complete, ABI-checked APK set and write the signed channel document's inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")


def collect(outputs: Path, destination: Path, tag: str, repository: str) -> dict:
    metadata = json.loads((outputs / "output-metadata.json").read_text())
    artifacts = {}
    destination.mkdir(parents=True, exist_ok=True)
    sums = []
    for element in metadata["elements"]:
        filters = element["filters"]
        if not filters:
            abi = "universal"
        elif len(filters) == 1 and filters[0]["filterType"] == "ABI":
            abi = filters[0]["value"]
        else:
            raise ValueError("unexpected APK filters")
        if abi not in (*ABIS, "universal") or abi in artifacts:
            raise ValueError(f"unexpected or duplicate ABI: {abi}")
        source = outputs / element["outputFile"]
        with zipfile.ZipFile(source) as apk:
            packaged = {name.split('/')[1] for name in apk.namelist()
                        if name.startswith('lib/') and name.endswith('/libbox.so')}
            expected = set(ABIS) if abi == "universal" else {abi}
            if packaged != expected:
                raise ValueError(f"{abi}: packaged core ABIs {packaged}, expected {expected}")
        name = f"hydrabox-{tag}-{abi}.apk"
        target = destination / name
        shutil.copyfile(source, target)
        with target.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        artifacts[abi] = {"apkUrl": f"https://github.com/{repository}/releases/download/{tag}/{name}", "sha256": digest}
        sums.append(f"{digest}  {name}\n")
    if set(artifacts) != {*ABIS, "universal"}:
        raise ValueError("release must contain universal and every supported ABI")
    (destination / 'SHA256SUMS').write_text(''.join(sorted(sums)))
    (destination / 'artifacts.json').write_text(json.dumps(artifacts, indent=2) + '\n')
    return artifacts


def manifest(artifacts: dict, channel: str, name: str, code: int, tag: str, cert: str, key_id: str) -> dict:
    # Schema 1's original fields deliberately remain a universal APK: installed 2.1.0
    # clients ignore the new map and can still upgrade. New clients choose an exact ABI.
    return {"schema": 1, "channel": channel, "versionCode": code, "versionName": name,
            "releaseTag": tag, **artifacts["universal"], "certificateSha256": cert,
            "keyId": key_id, "artifacts": {abi: artifacts[abi] for abi in ABIS}}


if __name__ == '__main__':
    import os
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['collect', 'manifest'])
    args = parser.parse_args()
    if args.action == 'collect':
        collect(Path('platform/android/build/outputs/apk/release'), Path('release'), os.environ['TAG'], os.environ['GITHUB_REPOSITORY'])
    else:
        artifacts = json.loads(Path('release/artifacts.json').read_text())
        body = manifest(artifacts, os.environ['CHANNEL'], os.environ['NAME'], int(os.environ['CODE']), os.environ['TAG'], os.environ['CERT'], os.environ['KEY_ID'])
        Path(f"update/{os.environ['CHANNEL']}.json").write_text(json.dumps(body, indent=2) + '\n')
