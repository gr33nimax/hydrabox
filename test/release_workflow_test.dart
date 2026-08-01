import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android release workflow uses updater-compatible tags and APK names',
    () {
      final workflow = File(
        '.github/workflows/android-release.yml',
      ).readAsStringSync();

      expect(workflow, contains(r'raw="${raw#v}"'));
      expect(workflow, contains(r'TAG_NAME=${raw}'));
      expect(workflow, contains(r'RELEASE_TITLE=v${raw}'));
      expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-universal.apk'));
      expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-arm64-v8a.apk'));
      expect(
        workflow,
        contains(r'hydrabox-v${RELEASE_VERSION}-armeabi-v7a.apk'),
      );
      expect(workflow, contains(r'hydrabox-v${RELEASE_VERSION}-x86_64.apk'));
      expect(workflow, contains('hydrabox-update.json'));
      expect(workflow, contains('name: hydrabox-release-apks-'));
      expect(workflow, contains('include_private_happ_assets:'));
      expect(workflow, contains('default: false'));
      expect(
        workflow,
        contains(r'if: ${{ inputs.include_private_happ_assets }}'),
      );
      expect(
        workflow,
        contains('Private Happ assets were explicitly requested.'),
      );
      expect(workflow, contains('packageName": "com.etonify.meow_client"'));
      expect(
        workflow,
        isNot(contains(r'etonify-v${RELEASE_VERSION}-universal.apk')),
      );
      expect(workflow, contains('--draft'));
      expect(workflow, contains(r'--target "$GITHUB_SHA"'));
      expect(workflow, contains('Release target mismatch'));
      expect(workflow, contains('Refusing to replace'));
      expect(
        workflow,
        contains(
          'uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd',
        ),
      );
      expect(
        workflow,
        contains(
          'uses: actions/setup-java@03ad4de0992f5dab5e18fcb136590ce7c4a0ac95',
        ),
      );
      expect(
        RegExp(
          'uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a',
        ).allMatches(workflow).length,
        2,
      );
      expect(
        workflow,
        isNot(
          contains(
            RegExp(r'uses: actions/(checkout|setup-java|upload-artifact)@v'),
          ),
        ),
      );
      expect(workflow, contains('python3 -B scripts/fetch_libbox.py'));
      expect(workflow, contains('python3 -B scripts/verify_libbox.py'));
      expect(
        workflow,
        contains(r'update_repository_owner="${GITHUB_REPOSITORY%%/*}"'),
      );
      expect(
        workflow,
        contains(r'update_repository_name="${GITHUB_REPOSITORY#*/}"'),
      );
      expect(
        workflow,
        contains(
          '--dart-define=HYDRABOX_UPDATE_REPOSITORY_OWNER='
          r'${update_repository_owner}',
        ),
      );
      expect(
        workflow,
        contains(
          '--dart-define=HYDRABOX_UPDATE_REPOSITORY_NAME='
          r'${update_repository_name}',
        ),
      );
      expect(workflow, isNot(contains('uses: actions/checkout@v4')));
      expect(workflow, isNot(contains('uses: actions/setup-java@v4')));
    },
  );

  test('HydraCore sync preserves verified distribution provenance', () {
    final workflow = File(
      '.github/workflows/sync-hydracore.yml',
    ).readAsStringSync();

    expect(
      workflow,
      contains('CORE_DISTRIBUTION_ID: "io.hydrabox.hydracore"'),
    );
    expect(workflow, contains('CORE_DISTRIBUTION_NAME: "HydraCore"'));
    expect(workflow, contains('CORE_UPSTREAM_PROJECT: "etonify-core"'));
    expect(workflow, contains('release/HYDRACORE_VERSION'));
    expect(
      workflow,
      contains('"hydracore_version": os.environ["CORE_RELEASE_TAG"]'),
    );
    expect(
      RegExp(
        '"etonify_version": os\\.environ\\["CORE_ETONIFY_VERSION"\\]',
      ).allMatches(workflow).length,
      2,
      reason: 'Etonify provenance must be verified and preserved',
    );
    for (final field in [
      'GO',
      'GOMOBILE',
      'JAVA',
      'ANDROID_NDK',
      'ANDROID_NDK_REQUESTED',
    ]) {
      expect(
        workflow,
        contains('os.environ["PUBLISHED_$field"]'),
        reason: 'app provenance must describe the published AAR toolchain',
      );
    }
    expect(workflow, isNot(contains('export GO_ACTUAL="\$(go version)"')));
    for (final field in [
      'distribution_id',
      'distribution_name',
      'upstream_project',
    ]) {
      expect(
        RegExp('"$field": os\\.environ\\["CORE_[A-Z_]+"\\]')
            .allMatches(workflow)
            .length,
        2,
        reason: '$field must be verified and written to app provenance',
      );
    }

    final provenance =
        jsonDecode(
              File(
                'android/app/libs/libbox.provenance.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(provenance['distribution_id'], 'io.hydrabox.hydracore');
    expect(provenance['distribution_name'], 'HydraCore');
    expect(provenance['upstream_project'], 'etonify-core');
    expect(provenance['etonify_version'], isNotEmpty);

    final coreWorkflow = File(
      'etonify-core/.github/workflows/hydracore.yml',
    ).readAsStringSync();
    expect(coreWorkflow, contains('"android_ndk": "\${ndk_revision}"'));
    expect(
      coreWorkflow,
      contains('"android_ndk_requested": "\${ANDROID_NDK_VERSION}"'),
    );
  });

  test('HydraCore exposes only the verified product workflow', () {
    final workflowNames = Directory('etonify-core/.github/workflows')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList();

    expect(workflowNames, ['hydracore.yml']);
    expect(Directory('etonify-core/docs').existsSync(), isFalse);
  });

  test('core README leads with HydraCore and isolates source attribution', () {
    final readme = File('etonify-core/README.md').readAsStringSync();

    expect(readme, startsWith('# HydraCore'));
    expect(readme, contains('[CREDITS.md](CREDITS.md)'));
    expect(readme, isNot(contains('[ETONIFY_CORE.md]')));
    expect(readme, contains('[LICENSE](LICENSE)'));
  });

  test('fallback client version and changelog match pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;

    expect(version, '0.3.0-beta.2');
    expect(
      File('lib/app/app.dart').readAsStringSync(),
      contains("_fallbackClientVersionLabel = '$version'"),
    );
    expect(
      File('lib/singbox/singbox_runtime.dart').readAsStringSync(),
      contains("normalized.isEmpty ? '$version' : normalized"),
    );
    expect(
      File('CHANGELOG.md').readAsStringSync(),
      contains('## [$version]'),
    );
  });
}
