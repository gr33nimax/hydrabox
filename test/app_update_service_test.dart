import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/update/app_update_service.dart';

void main() {
  group('AppUpdateService', () {
    test('stays fail-closed without a HydraBox release repository', () async {
      expect(AppUpdateService.updatesConfigured, isFalse);

      final result = await AppUpdateService.instance.checkForUpdates(
        currentVersion: '0.1.0',
        currentBuildNumber: 1,
        manual: true,
      );

      expect(result.status, AppUpdateStatus.disabled);
      expect(result.info, isNull);
    });

    const assets = [
      AppUpdateAsset(
        name: 'hydrabox-v0.1.0-universal.apk',
        downloadUrl: 'https://example.com/universal.apk',
        sizeBytes: 100,
      ),
      AppUpdateAsset(
        name: 'hydrabox-v0.1.0-arm64-v8a.apk',
        downloadUrl: 'https://example.com/arm64.apk',
        sizeBytes: 50,
      ),
      AppUpdateAsset(
        name: 'hydrabox-v0.1.0-x86_64.apk',
        downloadUrl: 'https://example.com/x86_64.apk',
        sizeBytes: 60,
      ),
    ];

    test('selects the current ABI before universal', () {
      final selected = AppUpdateService.selectAssetForAbis(assets, const [
        'arm64-v8a',
        'armeabi-v7a',
      ]);

      expect(selected?.name, 'hydrabox-v0.1.0-arm64-v8a.apk');
    });

    test('falls back to universal for unknown ABI', () {
      final selected = AppUpdateService.selectAssetForAbis(assets, const [
        'x86',
      ]);

      expect(selected?.name, 'hydrabox-v0.1.0-universal.apk');
    });

    test('normalizes version with and without v prefix', () {
      expect(AppUpdateService.normalizeVersion('v0.1.0'), '0.1.0');
      expect(AppUpdateService.normalizeVersion('0.1.0'), '0.1.0');
      expect(AppUpdateService.normalizeVersion('0.1.0+7'), '0.1.0');
      expect(AppUpdateService.extractBuildNumber('0.1.0+7'), 7);
      expect(
        AppUpdateService.extractBuildNumber(
          'Версия проекта обновлена до 0.2.0+4',
        ),
        4,
      );
    });

    test('compares versions', () {
      expect(AppUpdateService.isRemoteVersionNewer('0.1.1', '0.1.0'), isTrue);
      expect(AppUpdateService.isRemoteVersionNewer('0.1.0', '0.1.0'), isFalse);
      expect(AppUpdateService.isRemoteVersionNewer('0.1.0', '0.1.1'), isFalse);
      expect(
        AppUpdateService.isRemoteVersionNewer(
          '0.2.0',
          '0.2.0',
          remoteBuildNumber: 4,
          currentBuildNumber: 3,
        ),
        isTrue,
      );
      expect(
        AppUpdateService.isRemoteVersionNewer(
          '0.2.0',
          '0.2.0',
          remoteBuildNumber: 4,
          currentBuildNumber: 4,
        ),
        isFalse,
      );
      expect(
        AppUpdateService.isRemoteVersionNewer('0.2.0+4', '0.2.0+3'),
        isTrue,
      );
    });

    test('keeps user-facing update version without build code', () {
      const info = AppUpdateInfo(
        version: '0.2.1',
        buildNumber: 5,
        tagName: '0.2.1',
        title: '0.2.1',
        body: '',
        htmlUrl: 'https://example.com/release',
        publishedAt: null,
        asset: AppUpdateAsset(
          name: 'hydrabox-v0.2.1-arm64-v8a.apk',
          downloadUrl: 'https://example.com/app.apk',
          sizeBytes: 100,
        ),
      );

      expect(info.displayVersion, '0.2.1');
      expect(info.technicalVersion, '0.2.1+5');
    });

    test('sanitizes APK asset file names', () {
      expect(
        AppUpdateService.sanitizeAssetFileName('hydrabox v0.1.0 arm64-v8a.apk'),
        'hydrabox-v0.1.0-arm64-v8a.apk',
      );
      expect(
        AppUpdateService.sanitizeAssetFileName('not-an-apk.zip'),
        'hydrabox-update.apk',
      );
    });

    test('parses release manifest compatibility and integrity metadata', () {
      final sha256 = List.filled(32, 'ab').join();
      final manifest = AppUpdateManifest.fromJson({
        'schemaVersion': 1,
        'distributionId': 'io.hydrabox.client',
        'releaseSequence': 42,
        'sourceCommit': List.filled(40, 'a').join(),
        'publishedAt': '2026-08-14T12:00:00Z',
        'keyId': 'hydrabox-update-1',
        'version': 'v0.2.1+5',
        'buildNumber': 5,
        'minSdk': 24,
        'packageName': 'io.hydrabox.client',
        'assets': [
          {
            'name': 'hydrabox-v0.2.1-arm64-v8a.apk',
            'sizeBytes': 123456,
            'sha256': sha256,
          },
        ],
      });

      expect(manifest, isNotNull);
      expect(manifest!.version, '0.2.1');
      expect(manifest.releaseSequence, 42);
      expect(manifest.buildNumber, 5);
      expect(manifest.minimumAndroidSdk, 24);
      expect(manifest.packageName, 'io.hydrabox.client');
      expect(
        manifest.assets['hydrabox-v0.2.1-arm64-v8a.apk']?.sizeBytes,
        123456,
      );
      expect(manifest.assets['hydrabox-v0.2.1-arm64-v8a.apk']?.sha256, sha256);
    });

    test('rejects a manifest without version, package, or asset list', () {
      expect(AppUpdateManifest.fromJson(null), isNull);
      expect(
        AppUpdateManifest.fromJson({
          'schemaVersion': 1,
          'distributionId': 'io.hydrabox.client',
          'releaseSequence': 42,
          'sourceCommit': List.filled(40, 'a').join(),
          'publishedAt': '2026-08-14T12:00:00Z',
          'keyId': 'hydrabox-update-1',
          'version': '0.2.1',
          'packageName': '',
          'assets': const [],
        }),
        isNull,
      );
      expect(
        AppUpdateManifest.fromJson({
          'schemaVersion': 1,
          'distributionId': 'io.hydrabox.client',
          'releaseSequence': 42,
          'sourceCommit': List.filled(40, 'a').join(),
          'publishedAt': '2026-08-14T12:00:00Z',
          'keyId': 'hydrabox-update-1',
          'version': '',
          'packageName': 'io.hydrabox.client',
          'assets': const [],
        }),
        isNull,
      );
    });
  });
}
