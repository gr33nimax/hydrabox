import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';

void main() {
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
