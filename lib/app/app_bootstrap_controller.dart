import 'package:hydrabox/data/adblock/ad_block_rule_set_service.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/data/routing/russia_route_data_service.dart';
import 'package:hydrabox/data/subscription/subscription_fetcher.dart';
import 'package:hydrabox/data/subscription/subscription_store.dart';
import 'package:hydrabox/logging/app_log_store.dart';
import 'package:hydrabox/singbox/core_config_migration.dart';
import 'package:hydrabox/singbox/hydracore_capabilities.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';

typedef BootstrapAction = Future<void> Function();
typedef SettingsStoreLoader = Future<AppSettingsStore> Function();
typedef AppVersionInfoLoader = Future<AppVersionInfo> Function();
typedef CoreCapabilitiesLoader = Future<HydraCoreCapabilities> Function();
typedef AdBlockStatusLoader = Future<AdBlockRuleSetStatus> Function();
typedef RussiaRouteStatusLoader = Future<RussiaRouteDataStatus> Function();

enum AppBootstrapFailureStage {
  storageRecovery,
  platformBridgeRecovery,
  coreRecovery,
}

/// A recoverable bootstrap failure that must be surfaced to the user.
///
/// Production bootstrap deliberately does not substitute in-memory state or
/// invented core capabilities. The UI can stay available and offer recovery,
/// but connect remains fail-closed until this failure is repaired.
class AppBootstrapException implements Exception {
  const AppBootstrapException({
    required this.stage,
    required this.cause,
    required this.stackTrace,
  });

  final AppBootstrapFailureStage stage;
  final Object cause;
  final StackTrace stackTrace;

  String get code {
    final value = cause;
    if (value is HydraCoreHandshakeException) return value.code;
    if (stage == AppBootstrapFailureStage.coreRecovery &&
        value is FormatException) {
      return 'core.contract.invalid';
    }
    return switch (stage) {
      AppBootstrapFailureStage.storageRecovery => 'storage.bootstrap.failed',
      AppBootstrapFailureStage.platformBridgeRecovery =>
        'platform.bridge.unavailable',
      AppBootstrapFailureStage.coreRecovery => 'core.bootstrap.failed',
    };
  }

  String get safeMessage {
    final value = cause;
    if (value is HydraCoreHandshakeException) return value.safeMessage;
    return switch (stage) {
      AppBootstrapFailureStage.storageRecovery =>
        'Persistent application storage could not be opened.',
      AppBootstrapFailureStage.platformBridgeRecovery =>
        'The Android platform bridge is not ready.',
      AppBootstrapFailureStage.coreRecovery =>
        'HydraCore did not provide a compatible runtime contract.',
    };
  }

  @override
  String toString() => 'AppBootstrapException($stage): $cause';
}

class AppBootstrapResult {
  const AppBootstrapResult({
    required this.store,
    required this.ownsStore,
    required this.state,
    required this.adBlockStatus,
    required this.russiaRouteDataStatus,
    required this.appVersionInfo,
    required this.coreCapabilities,
    required this.pendingCoreConfigMigration,
    required this.usesInMemoryStore,
  });

  final AppSettingsStore store;
  final bool ownsStore;
  final AppSettingsState state;
  final AdBlockRuleSetStatus adBlockStatus;
  final RussiaRouteDataStatus russiaRouteDataStatus;
  final AppVersionInfo appVersionInfo;
  final HydraCoreCapabilities coreCapabilities;
  final CoreConfigMigrationResult? pendingCoreConfigMigration;
  final bool usesInMemoryStore;
}

/// Optional rule-set status loaded after the first application frame.
///
/// The underlying files are only required to build a runtime configuration
/// when the corresponding feature is enabled. Keeping a disabled feature out
/// of the critical startup path makes the home screen available sooner while
/// preserving the safe path for an enabled feature.
class BootstrapDeferredStatuses {
  const BootstrapDeferredStatuses({
    required this.adBlockStatus,
    required this.russiaRouteDataStatus,
  });

  final AdBlockRuleSetStatus adBlockStatus;
  final RussiaRouteDataStatus russiaRouteDataStatus;
}

/// Loads the durable application state without owning any Flutter UI state.
///
/// Keeping storage, native metadata and core compatibility checks here makes
/// bootstrap independently testable and prevents the root widget from becoming
/// the owner of every startup dependency.
class AppBootstrapController {
  AppBootstrapController({
    required this.fallbackClientVersionLabel,
    BootstrapAction? initializeHive,
    BootstrapAction? initializeSubscriptions,
    SettingsStoreLoader? openSettingsStore,
    AppVersionInfoLoader? loadAppVersionInfo,
    CoreCapabilitiesLoader? loadCoreCapabilities,
    AdBlockStatusLoader? loadAdBlockStatus,
    RussiaRouteStatusLoader? loadRussiaRouteStatus,
  }) : _initializeHive = initializeHive ?? HiveAppSettingsStore.initHive,
       _initializeSubscriptions =
           initializeSubscriptions ?? SubscriptionStore.init,
       _openSettingsStore = openSettingsStore ?? HiveAppSettingsStore.open,
       _loadAppVersionInfo =
           loadAppVersionInfo ??
           (() => SingboxRuntime.instance.getAppVersionInfo()),
       _loadCoreCapabilities =
           loadCoreCapabilities ??
           (() => SingboxRuntime.instance.getCoreCapabilities()),
       _loadAdBlockStatus =
           loadAdBlockStatus ?? AdBlockRuleSetService.instance.loadStatus,
       _loadRussiaRouteStatus =
           loadRussiaRouteStatus ?? RussiaRouteDataService.instance.loadStatus;

  final String fallbackClientVersionLabel;
  final BootstrapAction _initializeHive;
  final BootstrapAction _initializeSubscriptions;
  final SettingsStoreLoader _openSettingsStore;
  final AppVersionInfoLoader _loadAppVersionInfo;
  final CoreCapabilitiesLoader _loadCoreCapabilities;
  final AdBlockStatusLoader _loadAdBlockStatus;
  final RussiaRouteStatusLoader _loadRussiaRouteStatus;

  Future<AppBootstrapResult> load({AppSettingsStore? providedStore}) async {
    AppSettingsStore? store;
    var ownsStore = false;
    late AppSettingsState state;
    var adBlockStatus = const AdBlockRuleSetStatus.unavailable();
    var russiaRouteDataStatus = const RussiaRouteDataStatus.unavailable();
    final usesInMemoryStore = providedStore is MemoryAppSettingsStore;

    try {
      if (usesInMemoryStore) {
        store = providedStore;
      } else {
        await _initializeHive();
        final subscriptionInitFuture = _initializeSubscriptions();
        final storeFuture = providedStore == null
            ? _openSettingsStore()
            : Future<AppSettingsStore>.value(providedStore);
        await subscriptionInitFuture;
        store = await storeFuture;
        ownsStore = providedStore == null;
      }
      state = await store.loadState();
      if (state.adBlockEnabled || state.useRussiaRouteData) {
        final requiredStatuses = await loadDeferredStatuses(
          includeAdBlock: state.adBlockEnabled,
          includeRussiaRouteData: state.useRussiaRouteData,
        );
        adBlockStatus = requiredStatuses.adBlockStatus;
        russiaRouteDataStatus = requiredStatuses.russiaRouteDataStatus;
      }
    } catch (error, stackTrace) {
      AppLogStore.error(
        'bootstrap',
        'Durable storage bootstrap failed: $error\n$stackTrace',
      );
      if (providedStore == null && store != null) {
        try {
          await store.close();
        } catch (_) {}
      }
      throw AppBootstrapException(
        stage: AppBootstrapFailureStage.storageRecovery,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    final appVersionInfoFuture = readAppVersionInfo();
    final HydraCoreCapabilities coreCapabilities;
    try {
      coreCapabilities = await _readCoreCapabilities();
    } catch (error, stackTrace) {
      AppLogStore.error(
        'bootstrap',
        'HydraCore contract bootstrap failed: $error\n$stackTrace',
      );
      if (ownsStore) {
        try {
          await store.close();
        } catch (_) {}
      }
      throw AppBootstrapException(
        stage: _isPlatformBridgeFailure(error)
            ? AppBootstrapFailureStage.platformBridgeRecovery
            : AppBootstrapFailureStage.coreRecovery,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    final appVersionInfo = await appVersionInfoFuture;
    final migration = CoreConfigMigration.plan(
      state: state,
      capabilities: coreCapabilities,
    );
    CoreConfigMigrationResult? pendingCoreConfigMigration;
    if (migration.requiresValidation) {
      pendingCoreConfigMigration = migration;
      final persistedSchemaVersion = state.coreConfigSchemaVersion;
      state = migration.state.copyWith(
        coreConfigSchemaVersion: persistedSchemaVersion,
      );
      AppLogStore.info(
        'sing-box',
        'core config migration prepared '
            'from=$persistedSchemaVersion '
            'to=${migration.state.coreConfigSchemaVersion} '
            'changes=${migration.changes.join(',')}',
      );
    } else if (migration.status == CoreConfigMigrationStatus.blocked) {
      AppLogStore.warning(
        'sing-box',
        'core config migration blocked: ${migration.blockReason}',
      );
    }

    return AppBootstrapResult(
      store: store,
      ownsStore: ownsStore,
      state: state,
      adBlockStatus: adBlockStatus,
      russiaRouteDataStatus: russiaRouteDataStatus,
      appVersionInfo: appVersionInfo,
      coreCapabilities: coreCapabilities,
      pendingCoreConfigMigration: pendingCoreConfigMigration,
      usesInMemoryStore: usesInMemoryStore,
    );
  }

  static bool _isPlatformBridgeFailure(Object error) {
    if (error is! HydraCoreHandshakeException) return false;
    return const <String>{
      'channel-error',
      'missing-plugin',
      'platform.bridge.unavailable',
      'runtime.ipc.bind_exception',
    }.contains(error.code);
  }

  /// Reads status data that is useful for settings UI but not needed to draw
  /// the initial screen when the related features are disabled.
  Future<BootstrapDeferredStatuses> loadDeferredStatuses({
    bool includeAdBlock = true,
    bool includeRussiaRouteData = true,
  }) async {
    final adBlockStatusFuture = includeAdBlock
        ? _loadAdBlockStatusSafely()
        : Future<AdBlockRuleSetStatus>.value(
            const AdBlockRuleSetStatus.unavailable(),
          );
    final russiaRouteStatusFuture = includeRussiaRouteData
        ? _loadRussiaRouteStatusSafely()
        : Future<RussiaRouteDataStatus>.value(
            const RussiaRouteDataStatus.unavailable(),
          );
    return BootstrapDeferredStatuses(
      adBlockStatus: await adBlockStatusFuture,
      russiaRouteDataStatus: await russiaRouteStatusFuture,
    );
  }

  Future<AdBlockRuleSetStatus> _loadAdBlockStatusSafely() async {
    try {
      return await _loadAdBlockStatus();
    } catch (_) {
      return const AdBlockRuleSetStatus.unavailable();
    }
  }

  Future<RussiaRouteDataStatus> _loadRussiaRouteStatusSafely() async {
    try {
      return await _loadRussiaRouteStatus();
    } catch (_) {
      return const RussiaRouteDataStatus.unavailable();
    }
  }

  Future<AppVersionInfo> readAppVersionInfo() async {
    try {
      final info = await _loadAppVersionInfo();
      if (info.versionName.trim().isNotEmpty) {
        SubscriptionFetcher.configureAppVersion(info.versionName);
        return info;
      }
    } catch (error) {
      AppLogStore.warning('app version', 'Failed to read app version: $error');
    }
    SubscriptionFetcher.configureAppVersion(fallbackClientVersionLabel);
    return AppVersionInfo(
      packageName: '',
      versionName: fallbackClientVersionLabel,
      versionCode: 0,
    );
  }

  Future<HydraCoreCapabilities> _readCoreCapabilities() async {
    final capabilities = await _loadCoreCapabilities();
    if (!capabilities.isCompatibleRelease) {
      throw const FormatException('Installed HydraCore is incompatible');
    }
    return capabilities;
  }
}
