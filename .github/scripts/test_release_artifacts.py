import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('release_artifacts', Path(__file__).with_name('release_artifacts.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseArtifactsTest(unittest.TestCase):
    def fixture(self, root, missing=None, wrong=None):
        entries = []
        for abi in (*release.ABIS, 'universal'):
            if abi == missing:
                continue
            filename = abi + '.apk'
            with zipfile.ZipFile(root / filename, 'w') as apk:
                abis = release.ABIS if abi == 'universal' else [abi]
                for packaged in abis:
                    apk.writestr(f'lib/{wrong or packaged}/libbox.so', b'core')
            entries.append({'filters': [] if abi == 'universal' else [{'filterType': 'ABI', 'value': abi}], 'outputFile': filename})
        (root / 'output-metadata.json').write_text(json.dumps({'elements': entries}))

    def test_complete_set_and_old_client_universal_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            artifacts = release.collect(root, root / 'release', 'v2.1.1-stable.1', 'gr33nimax/hydrabox')
            body = release.manifest(artifacts, 'stable', '2.1.1', 228, 'v2.1.1-stable.1', 'a' * 64, 'key')
            self.assertEqual(artifacts['universal']['apkUrl'], body['apkUrl'])
            self.assertEqual(artifacts['universal']['sha256'], body['sha256'])
            self.assertEqual(set(release.ABIS), set(body['artifacts']))
            self.assertEqual(4, len((root / 'release/SHA256SUMS').read_text().splitlines()))

    def test_missing_architecture_or_wrong_native_library_refuses_release(self):
        for options in [{'missing': 'armeabi-v7a'}, {'wrong': 'x86'}]:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root, **options)
                with self.assertRaises(ValueError):
                    release.collect(root, root / 'release', 'tag', 'owner/repo')


if __name__ == '__main__':
    unittest.main()
