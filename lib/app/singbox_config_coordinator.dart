import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meow_client/app/app_background_tasks.dart';
import 'package:meow_client/app/runtime_lifecycle_controller.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';

enum SingboxConfigCoordinatorPhase {
  reconfiguring,
  stopping,
  connected,
  failed,
}

class SingboxConfigCoordinatorSnapshot {
  const SingboxConfigCoordinatorSnapshot({
    required this.connected,
    required this.runtimeTransitionInProgress,
    required this.activeSubscription,
    required this.selectedProxyTag,
    required this.excludedOutboundTags,
    required this.vpnInboundEnabled,
    required this.vpnMtu,
    required this.vpnStrictRoute,
    required this.vpnTunImplementation,
    required this.proxyInboundEnabled,
    required this.proxyMixedListen,
    required this.proxyMixedPort,
    required this.dnsDirectResolver,
    required this.dnsProxyResolver,
    required this.dnsPreferIpv6,
    required this.russiaDnsDirectResolver,
    required this.urlTestUrl,
    required this.urlTestIntervalSeconds,
    required this.urlTestTimeoutSeconds,
    required this.urlTestConcurrency,
    required this.urlTestUnavailableCheckIntervalSeconds,
    required this.blockLeaks,
    required this.adBlockEnabled,
    required this.adBlockBlockRuleSetPath,
    required this.adBlockAllowRuleSetPath,
    required this.useRussiaRouteData,
    required this.routeDataAvailable,
    required this.routeDataSourceKind,
    required this.routeDataRelease,
    required this.russiaGeositeRuBlockedPath,
    required this.russiaGeositeRuAvailableOnlyInsidePath,
    required this.russiaGeositeCategoryRuPath,
    required this.russiaGeoipRuBlockedPath,
    required this.russiaGeoipRuWhitelistPath,
    required this.russiaGeoipRuPath,
    required this.russiaCuratedDirectServicesPath,
    required this.russiaAiServicesPath,
    required this.bypassLocalNetwork,
    required this.splitRoutingMode,
    required this.splitRoutingPackages,
    required this.logLevel,
    required this.tcpFastOpenEnabled,
    required this.tcpMultiPathEnabled,
    required this.tlsFragmentationMode,
    required this.interruptExistingConnections,
    required this.urlTestStrictTolerance,
    required this.markAllServersRussia,
    this.snowtunBinaryPath,
    this.snowtunProtectPath,
  });

  final bool connected;
  final bool runtimeTransitionInProgress;
  final Subscription? activeSubscription;
  final String selectedProxyTag;
  final Set<String> excludedOutboundTags;
  final bool vpnInboundEnabled;
  final int vpnMtu;
  final bool vpnStrictRoute;
  final TunImplementationPreference vpnTunImplementation;
  final bool proxyInboundEnabled;
  final String proxyMixedListen;
  final int proxyMixedPort;
  final String dnsDirectResolver;
  final String dnsProxyResolver;
  final bool dnsPreferIpv6;
  final String russiaDnsDirectResolver;
  final String urlTestUrl;
  final int urlTestIntervalSeconds;
  final int urlTestTimeoutSeconds;
  final int urlTestConcurrency;
  final int urlTestUnavailableCheckIntervalSeconds;
  final bool blockLeaks;
  final bool adBlockEnabled;
  final String? adBlockBlockRuleSetPath;
  final String? adBlockAllowRuleSetPath;
  final bool useRussiaRouteData;
  final bool routeDataAvailable;
  final String routeDataSourceKind;
  final String? routeDataRelease;
  final String? russiaGeositeRuBlockedPath;
  final String? russiaGeositeRuAvailableOnlyInsidePath;
  final String? russiaGeositeCategoryRuPath;
  final String? russiaGeoipRuBlockedPath;
  final String? russiaGeoipRuWhitelistPath;
  final String? russiaGeoipRuPath;
  final String? russiaCuratedDirectServicesPath;
  final String? russiaAiServicesPath;
  final bool bypassLocalNetwork;
  final SplitRoutingMode splitRoutingMode;
  final List<String> splitRoutingPackages;
  final String logLevel;
  final bool tcpFastOpenEnabled;
  final bool tcpMultiPathEnabled;
  final TlsFragmentationMode tlsFragmentationMode;
  final bool interruptExistingConnections;
  final bool urlTestStrictTolerance;
  final bool markAllServersRussia;
  final String? snowtunBinaryPath;
  final String? snowtunProtectPath;

  bool get routeDataPathsValid =>
      russiaGeositeRuBlockedPath?.isNotEmpty == true &&
      russiaGeositeRuAvailableOnlyInsidePath?.isNotEmpty == true &&
      russiaGeositeCategoryRuPath?.isNotEmpty == true &&
      russiaGeoipRuBlockedPath?.isNotEmpty == true &&
      russiaGeoipRuWhitelistPath?.isNotEmpty == true &&
      russiaGeoipRuPath?.isNotEmpty == true;
}

typedef SingboxConfigCoordinatorSnapshotReader =
    SingboxConfigCoordinatorSnapshot Function();
typedef SingboxConfigHydrationHook = Future<bool> Function();
typedef SingboxConfigStartupValidation =
    bool Function(SingboxConfigBuildResult build, String reason);
typedef SingboxConfigPhaseSetter =
    void Function(SingboxConfigCoordinatorPhase phase);
typedef SingboxConfigRuntimeFailureNotifier =
    void Function({required bool timedOut});
typedef SingboxConfigPostConnectUrlTestScheduler =
    void Function({required String reason, required Duration delay});

class SingboxConfigCoordinator {
  SingboxConfigCoordinator({
    required SingboxConfigCoordinatorSnapshotReader readSnapshot,
    required bool Function() isMounted,
    required SingboxConfigHydrationHook ensureActiveSubscriptionHydrated,
    required RuntimeLifecycleController runtimeLifecycle,
    required SingboxConfigStartupValidation applyStartupValidationResult,
    required void Function() showNoValidOutboundsWarning,
    required SingboxConfigPhaseSetter setPhase,
    required SingboxConfigRuntimeFailureNotifier showRuntimeFailure,
    required RuntimeLogHook logCall,
    required void Function(String reason) trimRuntimeStartMemory,
    required RuntimeTimeoutHook onRuntimeLifecycleTimeout,
    required RuntimeVoidHook cacheStartedBuild,
    required SingboxConfigPostConnectUrlTestScheduler
    schedulePostConnectSelectedProxyUrlTest,
    required Future<void> Function() syncRuntimeState,
  }) : _readSnapshot = readSnapshot,
       _isMounted = isMounted,
       _ensureActiveSubscriptionHydrated = ensureActiveSubscriptionHydrated,
       _runtimeLifecycle = runtimeLifecycle,
       _applyStartupValidationResult = applyStartupValidationResult,
       _showNoValidOutboundsWarning = showNoValidOutboundsWarning,
       _setPhase = setPhase,
       _showRuntimeFailure = showRuntimeFailure,
       _logCall = logCall,
       _trimRuntimeStartMemory = trimRuntimeStartMemory,
       _onRuntimeLifecycleTimeout = onRuntimeLifecycleTimeout,
       _cacheStartedBuild = cacheStartedBuild,
       _schedulePostConnectSelectedProxyUrlTest =
           schedulePostConnectSelectedProxyUrlTest,
       _syncRuntimeState = syncRuntimeState;

  final SingboxConfigCoordinatorSnapshotReader _readSnapshot;
  final bool Function() _isMounted;
  final SingboxConfigHydrationHook _ensureActiveSubscriptionHydrated;
  final RuntimeLifecycleController _runtimeLifecycle;
  final SingboxConfigStartupValidation _applyStartupValidationResult;
  final void Function() _showNoValidOutboundsWarning;
  final SingboxConfigPhaseSetter _setPhase;
  final SingboxConfigRuntimeFailureNotifier _showRuntimeFailure;
  final RuntimeLogHook _logCall;
  final void Function(String reason) _trimRuntimeStartMemory;
  final RuntimeTimeoutHook _onRuntimeLifecycleTimeout;
  final RuntimeVoidHook _cacheStartedBuild;
  final SingboxConfigPostConnectUrlTestScheduler
  _schedulePostConnectSelectedProxyUrlTest;
  final Future<void> Function() _syncRuntimeState;

  int _runtimeConfigApplyGeneration = 0;
  int _singboxConfigBuildGeneration = 0;
  Future<String?>? _singboxConfigPathFuture;

  void emitCurrentConfigLog(String reason, {bool restartRuntime = true}) {
    unawaited(
      emitCurrentConfigLogAsync(reason, restartRuntime: restartRuntime),
    );
  }

  Future<void> emitCurrentConfigLogAsync(
    String reason, {
    required bool restartRuntime,
    bool applyWhenNativeRunning = false,
  }) async {
    var snapshot = _readSnapshot();
    var applyToRuntime =
        snapshot.connected || snapshot.runtimeTransitionInProgress;
    if (!applyToRuntime && applyWhenNativeRunning) {
      final status = await _runtimeStatusSnapshot(
        reason: 'config_emit_native_running',
      );
      applyToRuntime = status['running'] == true;
    }
    final generation = applyToRuntime ? ++_runtimeConfigApplyGeneration : 0;
    if (applyToRuntime && _isMounted()) {
      _setPhase(SingboxConfigCoordinatorPhase.reconfiguring);
    }
    final build = await buildCurrentSingboxConfigInBackground(
      prepareConfig: applyToRuntime,
      returnConfig: applyToRuntime,
    );
    if (build == null) {
      if (applyToRuntime && _isMounted() && _isCurrentApply(generation)) {
        _setPhase(SingboxConfigCoordinatorPhase.connected);
      }
      return;
    }
    if (applyToRuntime && !_applyStartupValidationResult(build, reason)) {
      discardPreparedConfigCandidate(build);
      if (_isMounted() && _isCurrentApply(generation)) {
        _setPhase(SingboxConfigCoordinatorPhase.failed);
      }
      _showNoValidOutboundsWarning();
      return;
    }
    recordBuiltConfigLog(reason, build);
    if (!applyToRuntime) {
      return;
    }
    snapshot = _readSnapshot();
    await applyRuntimeConfig(
      build: build,
      useVpn: snapshot.vpnInboundEnabled,
      restartRuntime: restartRuntime,
      generation: generation,
    );
  }

  Future<void> applyRuntimeConfig({
    required SingboxConfigBuildResult build,
    required bool useVpn,
    required bool restartRuntime,
    int? generation,
  }) async {
    final applyGeneration = generation ?? ++_runtimeConfigApplyGeneration;
    try {
      final policy = await _resolveRuntimeApplyPolicy(
        useVpn: useVpn,
        restartRuntime: restartRuntime,
      );
      if (!_isMounted() || !_isCurrentApply(applyGeneration)) {
        return;
      }
      if (policy == RuntimeApplyPolicy.logOnly) {
        AppLogStore.info(
          'runtime',
          'config apply skipped because runtime is not running useVpn=$useVpn',
        );
        return;
      }
      _setPhase(
        policy == RuntimeApplyPolicy.fullServiceRestart
            ? SingboxConfigCoordinatorPhase.stopping
            : SingboxConfigCoordinatorPhase.reconfiguring,
      );
      final result = await _runtimeLifecycle.applyRuntimeBuild(
        build: build,
        useVpn: useVpn,
        policy: policy,
        promotePreparedConfig: promotePreparedConfigBuild,
        cacheStartedBuild: _cacheStartedBuild,
        logCall: _logCall,
        trimMemory: _trimRuntimeStartMemory,
        onWatchdogTimeout: _onRuntimeLifecycleTimeout,
      );
      if (!_isMounted() || !_isCurrentApply(applyGeneration)) {
        return;
      }
      if (!result.success) {
        _setPhase(SingboxConfigCoordinatorPhase.failed);
        _showRuntimeFailure(timedOut: result.timedOut);
        return;
      }
      if (result.policy == RuntimeApplyPolicy.safeCoreRestart) {
        _setPhase(SingboxConfigCoordinatorPhase.connected);
        if (result.recovered) {
          AppLogStore.info(
            'runtime',
            'safe core restart recovered with one full service restart',
          );
        }
        _schedulePostConnectSelectedProxyUrlTest(
          reason:
              'config_apply_${result.recovered ? 'recovered' : 'safe_core_restart'}',
          delay: const Duration(milliseconds: 900),
        );
      }
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 500),
          _syncRuntimeState,
        ),
      );
    } catch (error, stackTrace) {
      AppLogStore.error(
        'sing-box',
        'Failed to apply config: $error\n$stackTrace',
      );
      if (_isMounted()) {
        _setPhase(SingboxConfigCoordinatorPhase.failed);
        _showRuntimeFailure(timedOut: false);
      }
    }
  }

  Future<RuntimeLifecycleResult> startRuntimeWithBuild(
    SingboxConfigBuildResult build, {
    required bool useVpn,
  }) {
    return _runtimeLifecycle.startRuntimeWithBuild(
      build: build,
      useVpn: useVpn,
      promotePreparedConfig: promotePreparedConfigBuild,
      cacheStartedBuild: _cacheStartedBuild,
      logCall: _logCall,
      trimMemory: _trimRuntimeStartMemory,
      onWatchdogTimeout: _onRuntimeLifecycleTimeout,
    );
  }

  Future<SingboxConfigBuildResult?> buildCurrentSingboxConfigInBackground({
    bool dropStale = true,
    bool prepareConfig = true,
    bool returnConfig = false,
  }) async {
    if (!await _ensureActiveSubscriptionHydrated()) {
      return null;
    }
    final generation = ++_singboxConfigBuildGeneration;
    final configPath = prepareConfig ? await ensureSingboxConfigPath() : null;
    if (!_isMounted()) {
      return null;
    }
    if (dropStale && generation != _singboxConfigBuildGeneration) {
      return null;
    }
    final stagedConfigPath = configPath == null
        ? null
        : '$configPath.pending.$generation';
    final input = _currentSingboxConfigBuildInput(
      outputConfigPath: stagedConfigPath,
      returnConfig: returnConfig || (prepareConfig && configPath == null),
    );
    late final SingboxConfigBuildResult result;
    try {
      result = await buildSingboxConfigInBackground(input);
    } catch (_) {
      _deletePreparedConfigCandidate(stagedConfigPath);
      rethrow;
    }
    if (!_isMounted()) {
      _deletePreparedConfigCandidate(stagedConfigPath);
      return null;
    }
    if (dropStale && generation != _singboxConfigBuildGeneration) {
      _deletePreparedConfigCandidate(stagedConfigPath);
      return null;
    }
    return result;
  }

  Future<void> promotePreparedConfigBuild(
    SingboxConfigBuildResult build,
  ) async {
    if (!build.hasPreparedConfig) {
      return;
    }
    final targetPath = await ensureSingboxConfigPath();
    if (targetPath == null || targetPath.trim().isEmpty) {
      throw StateError('Prepared config target path is unavailable.');
    }
    _promotePreparedConfigCandidate(
      sourcePath: build.configPath!,
      targetPath: targetPath,
    );
  }

  void discardPreparedConfigCandidate(SingboxConfigBuildResult build) {
    if (!build.hasPreparedConfig) {
      return;
    }
    _deletePreparedConfigCandidate(build.configPath);
  }

  Future<void> logCurrentSingboxConfig(String reason) async {
    final build = await buildCurrentSingboxConfigInBackground(
      prepareConfig: false,
    );
    if (build == null) {
      return;
    }
    recordBuiltConfigLog(reason, build);
  }

  void recordBuiltConfigLog(String reason, SingboxConfigBuildResult build) {
    final snapshot = _readSnapshot();
    AppLogStore.info(
      'sing-box config diagnostics',
      'reason=$reason '
          'useRussiaRouteData=${snapshot.useRussiaRouteData} '
          'routeDataAvailable=${snapshot.routeDataAvailable} '
          'routeDataPathsValid=${snapshot.routeDataPathsValid} '
          'routeDataSource=${snapshot.routeDataSourceKind} '
          'routeDataRelease=${snapshot.routeDataRelease ?? ''} '
          'activeSubscription=${snapshot.activeSubscription?.id ?? ''} '
          'selectedProxy=${snapshot.selectedProxyTag} '
          'outbounds=${build.configOutboundCount} '
          'inbounds=${build.configInboundCount} '
          'routeRules=${build.configRouteRuleCount}',
    );
    if (build.configJson.isNotEmpty) {
      final decoded = jsonDecode(build.configJson);
      if (decoded is Map<String, dynamic>) {
        AppLogStore.config(reason, decoded);
        return;
      }
    }
    if (build.hasReturnedConfig) {
      AppLogStore.config(reason, build.plan.config);
      return;
    }
    AppLogStore.info(
      'sing-box config ($reason)',
      'config omitted: ${build.configOutboundCount} outbounds, '
          '${build.configInboundCount} inbounds, '
          '${build.configRouteRuleCount} route rules, '
          '${build.configLength} chars',
    );
  }

  Future<String?> ensureSingboxConfigPath() {
    return _singboxConfigPathFuture ??= SingboxRuntime.instance.getConfigPath();
  }

  Future<RuntimeApplyPolicy> _resolveRuntimeApplyPolicy({
    required bool useVpn,
    required bool restartRuntime,
  }) async {
    final status = await _runtimeStatusSnapshot(reason: 'config_apply_policy');
    final running = status['running'] == true;
    final currentMode = status['mode']?.toString().toLowerCase();
    final targetMode = useVpn ? 'vpn' : 'proxy';
    final recordedServiceAlive = status['recordedServiceAlive'] == true;
    final runtimeIntentFresh = status['runtimeIntentFresh'] == true;
    final transitionInProgress = _readSnapshot().runtimeTransitionInProgress;
    final policy = running && currentMode == targetMode
        ? RuntimeApplyPolicy.safeCoreRestart
        : (running ||
                  recordedServiceAlive ||
                  runtimeIntentFresh ||
                  transitionInProgress ||
                  restartRuntime
              ? RuntimeApplyPolicy.fullServiceRestart
              : RuntimeApplyPolicy.logOnly);
    AppLogStore.info(
      'runtime',
      'config apply policy resolved policy=${policy.name} '
          'requestedRestart=$restartRuntime running=$running '
          'mode=${currentMode ?? ''} target=$targetMode '
          'recordedServiceAlive=$recordedServiceAlive '
          'runtimeIntentFresh=$runtimeIntentFresh',
    );
    return policy;
  }

  Future<Map<String, dynamic>> _runtimeStatusSnapshot({
    required String reason,
  }) async {
    try {
      return await SingboxRuntime.instance.status().timeout(
        const Duration(seconds: 2),
      );
    } catch (error) {
      AppLogStore.warning(
        'runtime',
        'status snapshot failed reason=$reason error=$error',
      );
      return const <String, dynamic>{'running': false};
    }
  }

  bool _isCurrentApply(int generation) {
    return generation == _runtimeConfigApplyGeneration;
  }

  SingboxConfigBuildInput _currentSingboxConfigBuildInput({
    String? outputConfigPath,
    required bool returnConfig,
  }) {
    final snapshot = _readSnapshot();
    return SingboxConfigBuildInput(
      activeSubscription: snapshot.activeSubscription,
      selectedProxyTag: snapshot.selectedProxyTag,
      excludedOutboundTags: Set<String>.from(snapshot.excludedOutboundTags),
      vpnInboundEnabled: snapshot.vpnInboundEnabled,
      vpnMtu: snapshot.vpnMtu,
      vpnStrictRoute: snapshot.vpnStrictRoute,
      vpnTunImplementation: snapshot.vpnTunImplementation,
      proxyInboundEnabled: snapshot.proxyInboundEnabled,
      proxyMixedListen: snapshot.proxyMixedListen,
      proxyMixedPort: snapshot.proxyMixedPort,
      dnsDirectResolver: snapshot.dnsDirectResolver,
      dnsProxyResolver: snapshot.dnsProxyResolver,
      dnsPreferIpv6: snapshot.dnsPreferIpv6,
      russiaDnsDirectResolver: snapshot.russiaDnsDirectResolver,
      urlTestUrl: snapshot.urlTestUrl,
      urlTestIntervalSeconds: snapshot.urlTestIntervalSeconds,
      urlTestTimeoutSeconds: snapshot.urlTestTimeoutSeconds,
      urlTestConcurrency: snapshot.urlTestConcurrency,
      urlTestUnavailableCheckIntervalSeconds:
          snapshot.urlTestUnavailableCheckIntervalSeconds,
      blockLeaks: snapshot.blockLeaks,
      adBlockEnabled: snapshot.adBlockEnabled,
      adBlockBlockRuleSetPath: snapshot.adBlockBlockRuleSetPath,
      adBlockAllowRuleSetPath: snapshot.adBlockAllowRuleSetPath,
      useRussiaRouteData: snapshot.useRussiaRouteData,
      russiaGeositeRuBlockedPath: snapshot.russiaGeositeRuBlockedPath,
      russiaGeositeRuAvailableOnlyInsidePath:
          snapshot.russiaGeositeRuAvailableOnlyInsidePath,
      russiaGeositeCategoryRuPath: snapshot.russiaGeositeCategoryRuPath,
      russiaGeoipRuBlockedPath: snapshot.russiaGeoipRuBlockedPath,
      russiaGeoipRuWhitelistPath: snapshot.russiaGeoipRuWhitelistPath,
      russiaGeoipRuPath: snapshot.russiaGeoipRuPath,
      russiaCuratedDirectServicesPath: snapshot.russiaCuratedDirectServicesPath,
      russiaAiServicesPath: snapshot.russiaAiServicesPath,
      bypassLocalNetwork: snapshot.bypassLocalNetwork,
      splitRoutingMode: snapshot.splitRoutingMode,
      splitRoutingPackages: snapshot.splitRoutingPackages,
      logLevel: snapshot.logLevel,
      tcpFastOpenEnabled: snapshot.tcpFastOpenEnabled,
      tcpMultiPathEnabled: snapshot.tcpMultiPathEnabled,
      tlsFragmentationMode: snapshot.tlsFragmentationMode,
      interruptExistingConnections: snapshot.interruptExistingConnections,
      urlTestStrictTolerance: snapshot.urlTestStrictTolerance,
      markAllServersRussia: snapshot.markAllServersRussia,
      snowtunBinaryPath: snapshot.snowtunBinaryPath,
      snowtunProtectPath: snapshot.snowtunProtectPath,
      outputConfigPath: outputConfigPath,
      returnConfig: returnConfig,
    );
  }

  void _promotePreparedConfigCandidate({
    required String sourcePath,
    required String targetPath,
  }) {
    if (sourcePath == targetPath) {
      return;
    }
    final source = File(sourcePath);
    final target = File(targetPath);
    target.parent.createSync(recursive: true);
    try {
      source.renameSync(target.path);
      return;
    } on FileSystemException {
      if (target.existsSync()) {
        target.deleteSync();
      }
    }
    source.renameSync(target.path);
  }

  void _deletePreparedConfigCandidate(String? path) {
    if (path == null || path.trim().isEmpty) {
      return;
    }
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
