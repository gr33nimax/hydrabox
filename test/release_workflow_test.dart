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
      expect(workflow, contains(r'etonify-v${RELEASE_VERSION}-universal.apk'));
      expect(workflow, contains(r'etonify-v${RELEASE_VERSION}-arm64-v8a.apk'));
      expect(
        workflow,
        contains(r'etonify-v${RELEASE_VERSION}-armeabi-v7a.apk'),
      );
      expect(workflow, contains(r'etonify-v${RELEASE_VERSION}-x86_64.apk'));
      expect(workflow, contains('--draft'));
      expect(workflow, contains('uses: actions/checkout@v7.0.1'));
      expect(workflow, contains('uses: actions/setup-java@v5.6.0'));
      expect(workflow, contains('python3 -B scripts/fetch_libbox.py'));
      expect(workflow, contains('python3 -B scripts/verify_libbox.py'));
      expect(workflow, isNot(contains('uses: actions/checkout@v4')));
      expect(workflow, isNot(contains('uses: actions/setup-java@v4')));
    },
  );
}
