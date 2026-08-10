import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release workflow builds the canonical package remotely', () {
    final workflow = File(
      '.github/workflows/android-release.yml',
    ).readAsStringSync();

    expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-universal.apk'));
    expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-arm64-v8a.apk'));
    expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-armeabi-v7a.apk'));
    expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-x86_64.apk'));
    expect(workflow, contains('"packageName": "io.hydrabox.client"'));
    expect(workflow, contains('python3 -B scripts/fetch_libbox.py'));
    expect(workflow, contains('python3 -B scripts/verify_libbox.py'));
    expect(workflow, contains('flutter gen-l10n'));
    expect(
      workflow,
      contains('dart run pigeon --input pigeons/singbox_api.dart'),
    );
    expect(workflow, contains('--draft'));
    expect(workflow, contains(r'--target "$GITHUB_SHA"'));
  });

  test('client CI generates and verifies everything on GitHub', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();

    expect(workflow, contains('submodules: recursive'));
    expect(workflow, contains('scripts/verify_extended_core.py --source-only'));
    expect(workflow, contains('scripts/verify_client_boundaries.py'));
    expect(workflow, contains('dart format lib test pigeons'));
    expect(workflow, contains('build/remote-generated.patch'));
    expect(workflow, contains('git diff --exit-code'));
    expect(workflow, contains('flutter analyze'));
    expect(workflow, contains('flutter test --reporter expanded'));
    expect(workflow, contains(':app:testDebugUnitTest'));
    expect(workflow, contains(':app:lintDebug'));
    expect(workflow, contains(':app:assembleDebug'));
    expect(
      workflow,
      contains('android/app/src/main/kotlin/io/hydrabox/client/generated'),
    );
  });

  test('HydraCore provenance schema v3 pins exact source and artifacts', () {
    final provenance =
        jsonDecode(
              File(
                'android/app/libs/libbox.provenance.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(provenance['schema_version'], 3);
    expect(provenance['distribution'], {
      'id': 'io.hydrabox.hydracore',
      'name': 'HydraCore',
      'version': 'v1.13.16-extended-hydracore.5',
    });
    expect(
      (provenance['source'] as Map<String, dynamic>)['commit'],
      '50545d23df03718e0f4cd15c76c600627f508c6b',
    );
    expect(
      (provenance['upstream'] as Map<String, dynamic>)['commit'],
      '545424b86bc4513f90580ebeab2e2d1514089718',
    );
    final artifacts = provenance['artifacts'] as Map<String, dynamic>;
    expect(
      (artifacts['libbox.aar'] as Map<String, dynamic>)['sha256'],
      '3a77374886de7506537374f6399853a0a30c6d0afaf07efd1bb94cb7b89dc162',
    );
    expect(
      (artifacts['libbox-sources.jar'] as Map<String, dynamic>)['sha256'],
      'e0bd7bdafdb9f90ab6a7a10e9311e7bcdea94970ab6a8d4da65f0742b9b8bf30',
    );
  });

  test('fallback client versions and changelog match pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;

    expect(version, '0.4.0-beta.1');
    expect(
      File('lib/app/app.dart').readAsStringSync(),
      contains("_fallbackClientVersionLabel = '$version'"),
    );
    expect(
      File('lib/singbox/singbox_runtime.dart').readAsStringSync(),
      contains("normalized.isEmpty ? '$version' : normalized"),
    );
    expect(
      File(
        'lib/data/subscription/subscription_fetcher.dart',
      ).readAsStringSync(),
      contains("fallbackAppVersion = '$version'"),
    );
    expect(File('CHANGELOG.md').readAsStringSync(), contains('## [$version]'));
  });
}
