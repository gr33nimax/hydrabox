import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/update/app_update_service.dart';

void main() {
  group('AppUpdateService', () {
    const assets = [
      AppUpdateAsset(
        name: 'etonify-v0.1.0-universal.apk',
        downloadUrl: 'https://example.com/universal.apk',
        sizeBytes: 100,
      ),
      AppUpdateAsset(
        name: 'etonify-v0.1.0-arm64-v8a.apk',
        downloadUrl: 'https://example.com/arm64.apk',
        sizeBytes: 50,
      ),
      AppUpdateAsset(
        name: 'etonify-v0.1.0-x86_64.apk',
        downloadUrl: 'https://example.com/x86_64.apk',
        sizeBytes: 60,
      ),
    ];

    test('selects the current ABI before universal', () {
      final selected = AppUpdateService.selectAssetForAbis(assets, const [
        'arm64-v8a',
        'armeabi-v7a',
      ]);

      expect(selected?.name, 'etonify-v0.1.0-arm64-v8a.apk');
    });

    test('falls back to universal for unknown ABI', () {
      final selected = AppUpdateService.selectAssetForAbis(assets, const [
        'x86',
      ]);

      expect(selected?.name, 'etonify-v0.1.0-universal.apk');
    });

    test('normalizes version with and without v prefix', () {
      expect(AppUpdateService.normalizeVersion('v0.1.0'), '0.1.0');
      expect(AppUpdateService.normalizeVersion('0.1.0'), '0.1.0');
    });

    test('compares versions', () {
      expect(AppUpdateService.isRemoteVersionNewer('0.1.1', '0.1.0'), isTrue);
      expect(AppUpdateService.isRemoteVersionNewer('0.1.0', '0.1.0'), isFalse);
      expect(AppUpdateService.isRemoteVersionNewer('0.1.0', '0.1.1'), isFalse);
    });

    test('sanitizes APK asset file names', () {
      expect(
        AppUpdateService.sanitizeAssetFileName('etonify v0.1.0 arm64-v8a.apk'),
        'etonify-v0.1.0-arm64-v8a.apk',
      );
      expect(
        AppUpdateService.sanitizeAssetFileName('not-an-apk.zip'),
        'etonify-update.apk',
      );
    });
  });
}
