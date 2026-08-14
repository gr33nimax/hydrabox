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
    expect(workflow, contains('"distributionId": "io.hydrabox.client"'));
    expect(workflow, contains('"releaseSequence": int(release_sequence)'));
    expect(workflow, contains('hydrabox-update.json.sig'));
    expect(workflow, contains('scripts/sign_update_manifest.go'));
    expect(workflow, contains('HYDRABOX_UPDATE_ED25519_PRIVATE_KEY'));
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
    expect(workflow, contains('scripts/fetch_libbox.py'));
    expect(workflow, contains('scripts/verify_libbox.py'));
    expect(workflow, isNot(contains('scripts/build_pinned_libbox.sh')));
    expect(workflow, contains('dart format lib test pigeons'));
    expect(workflow, contains('build/remote-generated.patch'));
    expect(workflow, contains('git diff --exit-code'));
    expect(workflow, contains('flutter analyze'));
    expect(workflow, contains('flutter test --reporter expanded'));
    expect(workflow, contains(':app:testDebugUnitTest'));
    expect(workflow, contains(':app:lintDebug'));
    expect(workflow, contains(':app:assembleDebug'));
    expect(workflow, contains(':app:assembleDebugAndroidTest'));
    expect(workflow, contains('build/app/outputs/apk/debug/*.apk'));
    expect(workflow, contains('Build debug-signed release-mode test APK'));
    expect(workflow, contains('HYDRABOX_ALLOW_DEBUG_RELEASE_SIGNING'));
    expect(workflow, contains('Upload test APK'));
    expect(
      workflow,
      contains('android/app/src/main/kotlin/io/hydrabox/client/generated'),
    );
  });

  test('Android lifecycle seams run only in the GitHub emulator matrix', () {
    final workflow = File(
      '.github/workflows/android-instrumentation.yml',
    ).readAsStringSync();

    expect(workflow, contains('api-level: [26, 30, 34, 37]'));
    expect(
      workflow,
      contains("matrix.api-level == 37 && 'canary' || 'stable'"),
    );
    expect(
      workflow,
      contains("sdkmanager --install 'platforms;android-37' --channel=3"),
    );
    expect(workflow, contains(':app:connectedDebugAndroidTest'));
    expect(workflow, contains('submodules: recursive'));
    expect(workflow, contains('scripts/fetch_libbox.py'));
    expect(
      workflow,
      contains(
        'reactivecircus/android-emulator-runner@a421e43855164a8197daf9d8d40fe71c6996bb0d',
      ),
    );
  });

  test('duplicate automatic HydraCore and test APK workflows are removed', () {
    expect(
      File('.github/workflows/android-test-apk.yml').existsSync(),
      isFalse,
    );
    expect(File('.github/workflows/sync-hydracore.yml').existsSync(), isFalse);
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
      'version': 'v1.13.16-extended-hydracore.11-debug.13',
      'role': 'client',
    });
    expect(
      (provenance['source'] as Map<String, dynamic>)['commit'],
      'd0d4b1dca77b6c691945999f17d56f223b7d4ea0',
    );
    expect(
      (provenance['upstream'] as Map<String, dynamic>)['commit'],
      '545424b86bc4513f90580ebeab2e2d1514089718',
    );
    final artifacts = provenance['artifacts'] as Map<String, dynamic>;
    expect(
      (artifacts['hydracore-client-libbox.aar']
          as Map<String, dynamic>)['sha256'],
      '96e8dbb75f946c19a972ed00ac1acdf66510f6de7b992aff9552f68d30b89339',
    );
    expect(
      (artifacts['hydracore-client-libbox-sources.jar']
          as Map<String, dynamic>)['sha256'],
      'e0bd7bdafdb9f90ab6a7a10e9311e7bcdea94970ab6a8d4da65f0742b9b8bf30',
    );
  });

  test('fallback client versions and changelog match pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;

    expect(version, '0.5.0');
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
