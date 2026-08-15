import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/app_bootstrap_controller.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/singbox/hydracore_capabilities.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';

void main() {
  test('memory bootstrap skips durable storage initialization', () async {
    var hiveInitialized = false;
    var subscriptionsInitialized = false;
    var durableStoreOpened = false;
    final controller = AppBootstrapController(
      fallbackClientVersionLabel: '0.3.0',
      initializeHive: () async => hiveInitialized = true,
      initializeSubscriptions: () async => subscriptionsInitialized = true,
      openSettingsStore: () async {
        durableStoreOpened = true;
        return MemoryAppSettingsStore();
      },
      loadAppVersionInfo: () async => const AppVersionInfo(
        packageName: 'io.hydrabox.client',
        versionName: '0.3.0',
        versionCode: 12,
      ),
      loadCoreCapabilities: () async => HydraCoreCapabilities.requiredV2,
    );

    final result = await controller.load(
      providedStore: MemoryAppSettingsStore(),
    );

    expect(result.usesInMemoryStore, isTrue);
    expect(result.ownsStore, isFalse);
    expect(result.appVersionInfo.versionName, '0.3.0');
    expect(result.state.localeCode, 'system');
    expect(hiveInitialized, isFalse);
    expect(subscriptionsInitialized, isFalse);
    expect(durableStoreOpened, isFalse);
  });

  test('failed durable storage enters explicit recovery', () async {
    final failingStore = _FailingSettingsStore();
    final controller = AppBootstrapController(
      fallbackClientVersionLabel: '0.3.0',
      initializeHive: () async {},
      initializeSubscriptions: () async {},
      openSettingsStore: () async => failingStore,
      loadAppVersionInfo: () async => const AppVersionInfo(
        packageName: '',
        versionName: '0.3.0',
        versionCode: 0,
      ),
      loadCoreCapabilities: () async => HydraCoreCapabilities.requiredV2,
    );

    await expectLater(
      controller.load(),
      throwsA(
        isA<AppBootstrapException>().having(
          (error) => error.stage,
          'stage',
          AppBootstrapFailureStage.storageRecovery,
        ),
      ),
    );

    expect(failingStore.closed, isTrue);
  });

  test('missing core capabilities fail closed', () async {
    final controller = AppBootstrapController(
      fallbackClientVersionLabel: '0.3.0',
      loadAppVersionInfo: () async => throw StateError('version unavailable'),
      loadCoreCapabilities: () async => throw StateError('core unavailable'),
    );

    try {
      await controller.load(providedStore: MemoryAppSettingsStore());
      fail('bootstrap should have required core recovery');
    } on AppBootstrapException catch (error) {
      expect(error.stage, AppBootstrapFailureStage.coreRecovery);
      expect(error.code, 'core.bootstrap.failed');
      expect(error.safeMessage, isNotEmpty);
    }
  });

  test('typed core startup failure remains visible to recovery UI', () async {
    final controller = AppBootstrapController(
      fallbackClientVersionLabel: '0.3.0',
      loadCoreCapabilities: () async => throw const HydraCoreHandshakeException(
        code: 'core.startup.native_setup',
        stage: 'native_setup',
        retryable: false,
        safeMessage: 'HydraCore could not initialize its native runtime.',
      ),
    );

    try {
      await controller.load(providedStore: MemoryAppSettingsStore());
      fail('bootstrap should have required core recovery');
    } on AppBootstrapException catch (error) {
      expect(error.stage, AppBootstrapFailureStage.coreRecovery);
      expect(error.code, 'core.startup.native_setup');
      expect(
        error.safeMessage,
        'HydraCore could not initialize its native runtime.',
      );
    }
  });

  test(
    'missing Pigeon handler is bridge recovery, not core corruption',
    () async {
      final controller = AppBootstrapController(
        fallbackClientVersionLabel: '1.0.0',
        loadCoreCapabilities: () async =>
            throw const HydraCoreHandshakeException(
              code: 'channel-error',
              stage: 'capability_handshake',
              retryable: false,
              safeMessage: 'Unable to establish the Android platform channel.',
            ),
      );

      try {
        await controller.load(providedStore: MemoryAppSettingsStore());
        fail('bootstrap should have required platform bridge recovery');
      } on AppBootstrapException catch (error) {
        expect(error.stage, AppBootstrapFailureStage.platformBridgeRecovery);
        expect(error.code, 'channel-error');
      }
    },
  );

  test('disabled rule-set status is deferred until after bootstrap', () async {
    var adBlockRequests = 0;
    var russiaRouteRequests = 0;
    final controller = AppBootstrapController(
      fallbackClientVersionLabel: '0.3.0',
      loadAppVersionInfo: () async => const AppVersionInfo(
        packageName: '',
        versionName: '0.3.0',
        versionCode: 0,
      ),
      loadCoreCapabilities: () async => HydraCoreCapabilities.requiredV2,
      loadAdBlockStatus: () async {
        adBlockRequests++;
        throw StateError('ad block status unavailable');
      },
      loadRussiaRouteStatus: () async {
        russiaRouteRequests++;
        throw StateError('russia route status unavailable');
      },
    );

    final result = await controller.load(
      providedStore: MemoryAppSettingsStore(),
    );

    expect(result.adBlockStatus.available, isFalse);
    expect(result.russiaRouteDataStatus.available, isFalse);
    expect(adBlockRequests, 0);
    expect(russiaRouteRequests, 0);

    await controller.loadDeferredStatuses();

    expect(adBlockRequests, 1);
    expect(russiaRouteRequests, 1);
  });

  test('enabled rule-set status remains in the safe startup path', () async {
    var adBlockRequests = 0;
    var russiaRouteRequests = 0;
    final store = MemoryAppSettingsStore();
    await store.saveState(
      (await store.loadState()).copyWith(
        adBlockEnabled: true,
        useRussiaRouteData: true,
      ),
    );
    final controller = AppBootstrapController(
      fallbackClientVersionLabel: '0.3.0',
      loadAppVersionInfo: () async => const AppVersionInfo(
        packageName: '',
        versionName: '0.3.0',
        versionCode: 0,
      ),
      loadCoreCapabilities: () async => HydraCoreCapabilities.requiredV2,
      loadAdBlockStatus: () async {
        adBlockRequests++;
        throw StateError('ad block status unavailable');
      },
      loadRussiaRouteStatus: () async {
        russiaRouteRequests++;
        throw StateError('russia route status unavailable');
      },
    );

    await controller.load(providedStore: store);

    expect(adBlockRequests, 1);
    expect(russiaRouteRequests, 1);
  });
}

class _FailingSettingsStore extends AppSettingsStore {
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<AppSettingsState> loadState() async {
    throw StateError('settings unavailable');
  }

  @override
  Future<void> saveState(AppSettingsState state) async {}
}
