import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';

void main() {
  group('AppVersionInfo', () {
    test('does not expose Android versionCode in display version', () {
      const info = AppVersionInfo(
        packageName: 'io.hydrabox.client',
        versionName: '0.2.1',
        versionCode: 2005,
      );

      expect(info.displayVersion, '0.2.1');
      expect(info.updateBuildNumber, 5);
    });

    test('uses the current release label when native metadata is empty', () {
      const info = AppVersionInfo(
        packageName: 'io.hydrabox.client',
        versionName: '',
        versionCode: 2012,
      );

      expect(info.displayVersion, '1.0.0');
      expect(info.updateBuildNumber, 12);
    });
  });

  group('SingboxRuntime Pigeon normalization', () {
    test('accepts installed app maps with Object keys', () {
      final value = <Object?>[
        <Object?, Object?>{
          'packageName': 'com.example.app',
          'label': 'Example',
          'system': false,
        },
      ];

      final normalized = normalizePigeonMapListForTest(value);

      expect(normalized, hasLength(1));
      expect(normalized.single['packageName'], 'com.example.app');
      expect(normalized.single['label'], 'Example');
      expect(normalized.single['system'], false);
    });
  });
}
