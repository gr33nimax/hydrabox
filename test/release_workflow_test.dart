import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release workflow builds the canonical package remotely', () {
    final workflow = File(
      '.github/workflows/android-release.yml',
    ).readAsStringSync();

    expect(
      workflow,
      isNot(contains(r'hydrabox-v${RELEASE_VERSION}-universal.apk')),
    );
    expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-arm64-v8a.apk'));
    expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-armeabi-v7a.apk'));
    expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-x86_64.apk'));
    expect(workflow, contains('"packageName": "io.hydrabox.client"'));
    expect(workflow, contains('"distributionId": "io.hydrabox.client"'));
    expect(workflow, contains('"releaseSequence": int(release_sequence)'));
    expect(workflow, contains('hydrabox-update.json.sig'));
    expect(workflow, contains('scripts/sign_update_manifest.go'));
    expect(workflow, contains('HYDRABOX_UPDATE_ED25519_PRIVATE_KEY'));
    expect(workflow, contains('ARM64 APK size regression'));
    expect(workflow, contains('Unsafe installer permission'));
    expect(workflow, contains('REQUEST_INSTALL_PACKAGES'));
    expect(workflow, contains('HydraCore PT_LOAD alignment'));
    expect(workflow, contains('Signing identity mismatch'));
    expect(workflow, contains('python3 -B scripts/fetch_libbox.py'));
    expect(workflow, contains('python3 -B scripts/verify_libbox.py'));
    expect(workflow, contains('flutter gen-l10n'));
    expect(
      workflow,
      contains('dart run pigeon --input pigeons/singbox_api.dart'),
    );
    expect(workflow, contains('--draft'));
    expect(workflow, contains(r'--target "$GITHUB_SHA"'));
    expect(workflow, contains('HydraBox-ARM64-INSTALL-THIS-'));
  });

  test('client CI generates and verifies everything on GitHub', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();

    expect(workflow, contains('submodules: recursive'));
    expect(workflow, contains('scripts/verify_extended_core.py --source-only'));
    expect(workflow, contains('scripts/verify_client_boundaries.py'));
    expect(workflow, contains('scripts/fetch_libbox.py'));
    expect(workflow, contains('scripts/verify_libbox.py'));
    expect(workflow, contains('HYDRACORE_RELEASE_PUBLIC_KEYS'));
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
    expect(workflow, contains('flutter build apk --release --split-per-abi'));
    expect(workflow, contains('app-arm64-v8a-release.apk'));
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

    expect(workflow, contains('api-level: [26, 30, 34]'));
    expect(workflow, isNot(contains('api-level: 37')));
    expect(workflow, isNot(contains('37.0')));
    expect(workflow, contains('system-image-api-level:'));
    expect(workflow, contains('channel: stable'));
    expect(workflow, contains('target: default'));
    expect(workflow, contains('runner: [ubuntu-latest]'));
    expect(workflow, contains('arch: [x86_64]'));
    expect(workflow, contains('disk-size: 8G'));
    expect(workflow, contains('disable-linux-hw-accel:'));
    expect(workflow, isNot(contains('channel: canary')));
    expect(workflow, contains("if: matrix.arch == 'x86_64'"));
    expect(workflow, contains('flutter build apk --release --split-per-abi'));
    expect(
      workflow,
      isNot(contains('flutter build apk --debug --split-per-abi')),
    );
    expect(workflow, contains('app-x86_64-release.apk'));
    expect(workflow, contains('app-arm64-v8a-release.apk'));
    expect(workflow, contains(':app:assembleDebugAndroidTest'));
    expect(
      workflow,
      contains('android-instrumentation-test-only-do-not-install'),
    );
    expect(workflow, isNot(contains('set -euo pipefail')));
    expect(workflow, isNot(contains(r'test_apk=')));
    expect(workflow, contains('submodules: recursive'));
    expect(workflow, contains('scripts/fetch_libbox.py'));
    expect(workflow, contains('HYDRACORE_RELEASE_PUBLIC_KEYS'));
    final runner = File(
      '.github/scripts/run-android-instrumentation.sh',
    ).readAsStringSync();
    expect(runner, contains(r'app-$arch-release.apk'));
    expect(runner, contains('build/instrumentation'));
    expect(runner, contains('adb shell am instrument -w'));
    expect(runner, contains('io.hydrabox.client/.MainActivity'));
    expect(runner, contains('platform_bridge_ready name=core_manager'));
    expect(runner, contains('platform_bridge_ready name=singbox'));
    expect(runner, contains('startup_healthy source='));
    expect(
      runner,
      contains('platform_bridge_result name=getCoreCapabilities success=true'),
    );
    expect(runner, contains('hydrabox_bootstrap_ready api=2 role=client'));
    expect(
      workflow,
      contains(
        'reactivecircus/android-emulator-runner@a421e43855164a8197daf9d8d40fe71c6996bb0d',
      ),
    );
  });

  test('application supplies WorkManager configuration before scheduling', () {
    final application = File(
      'android/app/src/main/kotlin/io/hydrabox/client/HydraBoxApplication.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(application, contains('Configuration.Provider'));
    expect(application, contains('workManagerConfiguration'));
    expect(manifest, contains('androidx.work.WorkManagerInitializer'));
    expect(manifest, contains('tools:node="remove"'));
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
      'version': 'v1.13.16-extended-hydracore.11-debug.44',
      'role': 'client',
    });
    expect(
      (provenance['source'] as Map<String, dynamic>)['commit'],
      'c3abeeb300e87d28851a6a763dfc9fd48460348e',
    );
    expect(
      (provenance['upstream'] as Map<String, dynamic>)['commit'],
      '545424b86bc4513f90580ebeab2e2d1514089718',
    );
    final artifacts = provenance['artifacts'] as Map<String, dynamic>;
    expect(
      (artifacts['hydracore-client-libbox.aar']
          as Map<String, dynamic>)['sha256'],
      'd9a8c327eb4ea9a17d155511555c5f7db9fd45105c61b6eec3d365e399a55041',
    );
    expect(
      (artifacts['hydracore-client-libbox-sources.jar']
          as Map<String, dynamic>)['sha256'],
      '8ca57fbf682413a416f678d5133165433c83eedb7ff5fb7cf80a7605734ca84d',
    );
  });

  test('fallback client versions and changelog match pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;

    expect(version, '1.0.0');
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
