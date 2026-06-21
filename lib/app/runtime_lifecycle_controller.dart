import 'dart:async';

import 'package:meow_client/app/app_background_tasks.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';

enum RuntimeApplyPolicy { logOnly, safeCoreRestart, fullServiceRestart }

class RuntimeLifecycleResult {
  const RuntimeLifecycleResult({
    required this.success,
    required this.policy,
    this.timedOut = false,
    this.recovered = false,
    this.error,
  });

  const RuntimeLifecycleResult.success({
    required RuntimeApplyPolicy policy,
    bool recovered = false,
  }) : this(success: true, policy: policy, recovered: recovered);

  const RuntimeLifecycleResult.failure({
    required RuntimeApplyPolicy policy,
    String? error,
    bool timedOut = false,
  }) : this(success: false, policy: policy, error: error, timedOut: timedOut);

  final bool success;
  final RuntimeApplyPolicy policy;
  final bool timedOut;
  final bool recovered;
  final String? error;
}

abstract interface class RuntimeLifecycleRuntime {
  Future<void> start({required String config, required bool useVpn});

  Future<void> startPrepared({required bool useVpn});

  Future<void> applyConfig({
    required String config,
    required bool useVpn,
    required bool restartCore,
  });

  Future<void> applyPreparedConfig({
    required bool useVpn,
    required bool restartCore,
  });

  Future<void> stop({required String reason});

  Future<bool> prepareVpn({required bool requiresVpn});

  Future<Map<String, dynamic>> status();

  Future<NetworkInterfaceSnapshot> getNetworkInterfaceState();
}

class SingboxRuntimeLifecycleRuntime implements RuntimeLifecycleRuntime {
  SingboxRuntimeLifecycleRuntime([SingboxRuntime? runtime])
    : _runtime = runtime ?? SingboxRuntime.instance;

  final SingboxRuntime _runtime;

  @override
  Future<void> applyConfig({
    required String config,
    required bool useVpn,
    required bool restartCore,
  }) {
    return _runtime.applyConfig(
      config: config,
      useVpn: useVpn,
      restartCore: restartCore,
    );
  }

  @override
  Future<void> applyPreparedConfig({
    required bool useVpn,
    required bool restartCore,
  }) {
    return _runtime.applyPreparedConfig(
      useVpn: useVpn,
      restartCore: restartCore,
    );
  }

  @override
  Future<NetworkInterfaceSnapshot> getNetworkInterfaceState() {
    return _runtime.getNetworkInterfaceState();
  }

  @override
  Future<bool> prepareVpn({required bool requiresVpn}) {
    return _runtime.prepareVpn(requiresVpn: requiresVpn);
  }

  @override
  Future<void> start({required String config, required bool useVpn}) {
    return _runtime.start(config: config, useVpn: useVpn);
  }

  @override
  Future<void> startPrepared({required bool useVpn}) {
    return _runtime.startPrepared(useVpn: useVpn);
  }

  @override
  Future<Map<String, dynamic>> status() => _runtime.status();

  @override
  Future<void> stop({required String reason}) => _runtime.stop(reason: reason);
}

typedef RuntimeBuildHook = FutureOr<void> Function(SingboxConfigBuildResult);
typedef RuntimeVoidHook = void Function(SingboxConfigBuildResult);
typedef RuntimeLogHook = void Function(String method, String detail);
typedef RuntimeTimeoutHook =
    FutureOr<void> Function(RuntimeLifecycleResult result);

class RuntimeLifecycleController {
  RuntimeLifecycleController({
    RuntimeLifecycleRuntime? runtime,
    this.startTimeout = const Duration(seconds: 15),
    this.stopTimeout = const Duration(seconds: 7),
    this.healthCheckTimeout = const Duration(seconds: 6),
  }) : _runtime = runtime ?? SingboxRuntimeLifecycleRuntime();

  final RuntimeLifecycleRuntime _runtime;
  final Duration startTimeout;
  final Duration stopTimeout;
  final Duration healthCheckTimeout;

  Timer? _startWatchdogTimer;
  int _startWatchdogGeneration = 0;
  int _handledStartTimeoutGeneration = 0;

  bool get startWatchdogActive => _startWatchdogTimer != null;

  void dispose() {
    cancelStartWatchdog();
  }

  void cancelStartWatchdog() {
    _startWatchdogGeneration++;
    _startWatchdogTimer?.cancel();
    _startWatchdogTimer = null;
  }

  Future<RuntimeLifecycleResult> startRuntimeWithBuild({
    required SingboxConfigBuildResult build,
    required bool useVpn,
    required RuntimeBuildHook promotePreparedConfig,
    required RuntimeVoidHook cacheStartedBuild,
    required RuntimeLogHook logCall,
    required void Function(String reason) trimMemory,
    required RuntimeTimeoutHook onWatchdogTimeout,
  }) async {
    trimMemory('before_runtime_start_build');
    cacheStartedBuild(build);
    Future<void> startFuture;
    if (build.hasPreparedConfig) {
      await promotePreparedConfig(build);
      logCall(
        'startPrepared',
        'reason=start runtime useVpn=$useVpn '
            'configOutbounds=${build.configOutboundCount}',
      );
      final watchdogGeneration = _armStartWatchdog(
        useVpn: useVpn,
        onTimeout: onWatchdogTimeout,
      );
      startFuture = _runtime.startPrepared(useVpn: useVpn);
      return _waitForStartFuture(
        startFuture,
        watchdogGeneration: watchdogGeneration,
        useVpn: useVpn,
      );
    } else {
      logCall(
        'start',
        'reason=start runtime useVpn=$useVpn '
            'configOutbounds=${build.configOutboundCount} '
            'configChars=${build.configLength}',
      );
      final watchdogGeneration = _armStartWatchdog(
        useVpn: useVpn,
        onTimeout: onWatchdogTimeout,
      );
      startFuture = _runtime.start(config: build.configJson, useVpn: useVpn);
      return _waitForStartFuture(
        startFuture,
        watchdogGeneration: watchdogGeneration,
        useVpn: useVpn,
      );
    }
  }

  Future<RuntimeLifecycleResult> _waitForStartFuture(
    Future<void> startFuture, {
    required int watchdogGeneration,
    required bool useVpn,
  }) async {
    try {
      await startFuture.timeout(startTimeout);
      cancelStartWatchdog();
      return const RuntimeLifecycleResult.success(
        policy: RuntimeApplyPolicy.fullServiceRestart,
      );
    } on TimeoutException catch (error, stackTrace) {
      return _handleImmediateStartTimeout(
        generation: watchdogGeneration,
        useVpn: useVpn,
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      cancelStartWatchdog();
      AppLogStore.error(
        'sing-box',
        'runtime start failed useVpn=$useVpn error=$error\n$stackTrace',
      );
      return RuntimeLifecycleResult.failure(
        policy: RuntimeApplyPolicy.fullServiceRestart,
        error: error.toString(),
      );
    }
  }

  Future<RuntimeLifecycleResult> applyRuntimeBuild({
    required SingboxConfigBuildResult build,
    required bool useVpn,
    required RuntimeApplyPolicy policy,
    required RuntimeBuildHook promotePreparedConfig,
    required RuntimeVoidHook cacheStartedBuild,
    required RuntimeLogHook logCall,
    required void Function(String reason) trimMemory,
    required RuntimeTimeoutHook onWatchdogTimeout,
  }) async {
    AppLogStore.info(
      'runtime',
      'config apply policy=${policy.name} useVpn=$useVpn '
          'outbounds=${build.configOutboundCount} '
          'routeRules=${build.configRouteRuleCount}',
    );
    if (policy == RuntimeApplyPolicy.logOnly) {
      return const RuntimeLifecycleResult.success(
        policy: RuntimeApplyPolicy.logOnly,
      );
    }
    if (policy == RuntimeApplyPolicy.fullServiceRestart) {
      return fullServiceRestart(
        build: build,
        useVpn: useVpn,
        reason: 'config_changed',
        promotePreparedConfig: promotePreparedConfig,
        cacheStartedBuild: cacheStartedBuild,
        logCall: logCall,
        trimMemory: trimMemory,
        onWatchdogTimeout: onWatchdogTimeout,
      );
    }

    try {
      await _applyBuild(
        build: build,
        useVpn: useVpn,
        restartCore: true,
        promotePreparedConfig: promotePreparedConfig,
        cacheStartedBuild: cacheStartedBuild,
        logCall: logCall,
      );
      final healthy = await _waitForHealthyRuntime();
      if (healthy) {
        return const RuntimeLifecycleResult.success(
          policy: RuntimeApplyPolicy.safeCoreRestart,
        );
      }
      AppLogStore.warning(
        'runtime',
        'runtime_interface_recovery reason=safe_core_restart_health_failed',
      );
      final recovered = await fullServiceRestart(
        build: build,
        useVpn: useVpn,
        reason: 'runtime_interface_recovery',
        promotePreparedConfig: promotePreparedConfig,
        cacheStartedBuild: cacheStartedBuild,
        logCall: logCall,
        trimMemory: trimMemory,
        onWatchdogTimeout: onWatchdogTimeout,
      );
      if (!recovered.success) {
        return recovered;
      }
      return const RuntimeLifecycleResult.success(
        policy: RuntimeApplyPolicy.safeCoreRestart,
        recovered: true,
      );
    } catch (error, stackTrace) {
      AppLogStore.error(
        'sing-box',
        'Failed to apply runtime config policy=${policy.name}: '
            '$error\n$stackTrace',
      );
      return RuntimeLifecycleResult.failure(
        policy: policy,
        error: error.toString(),
      );
    }
  }

  Future<RuntimeLifecycleResult> fullServiceRestart({
    required SingboxConfigBuildResult build,
    required bool useVpn,
    required String reason,
    required RuntimeBuildHook promotePreparedConfig,
    required RuntimeVoidHook cacheStartedBuild,
    required RuntimeLogHook logCall,
    required void Function(String reason) trimMemory,
    required RuntimeTimeoutHook onWatchdogTimeout,
  }) async {
    try {
      logCall('stop', 'reason=$reason before runtime restart useVpn=$useVpn');
      await _runtime.stop(reason: reason).timeout(stopTimeout);
      trimMemory('before_runtime_restart');
      final granted = await _runtime.prepareVpn(requiresVpn: useVpn);
      if (!granted) {
        return const RuntimeLifecycleResult.failure(
          policy: RuntimeApplyPolicy.fullServiceRestart,
          error: 'vpn_permission_denied',
        );
      }
      return startRuntimeWithBuild(
        build: build,
        useVpn: useVpn,
        promotePreparedConfig: promotePreparedConfig,
        cacheStartedBuild: cacheStartedBuild,
        logCall: logCall,
        trimMemory: trimMemory,
        onWatchdogTimeout: onWatchdogTimeout,
      );
    } catch (error, stackTrace) {
      cancelStartWatchdog();
      AppLogStore.error(
        'sing-box',
        'runtime full restart failed reason=$reason useVpn=$useVpn '
            'error=$error\n$stackTrace',
      );
      return RuntimeLifecycleResult.failure(
        policy: RuntimeApplyPolicy.fullServiceRestart,
        error: error.toString(),
      );
    }
  }

  Future<void> _applyBuild({
    required SingboxConfigBuildResult build,
    required bool useVpn,
    required bool restartCore,
    required RuntimeBuildHook promotePreparedConfig,
    required RuntimeVoidHook cacheStartedBuild,
    required RuntimeLogHook logCall,
  }) async {
    cacheStartedBuild(build);
    if (build.hasPreparedConfig) {
      await promotePreparedConfig(build);
      logCall(
        'applyPreparedConfig',
        'reason=apply runtime useVpn=$useVpn restartCore=$restartCore '
            'configOutbounds=${build.configOutboundCount}',
      );
      return _runtime.applyPreparedConfig(
        useVpn: useVpn,
        restartCore: restartCore,
      );
    }
    logCall(
      'applyConfig',
      'reason=apply runtime useVpn=$useVpn restartCore=$restartCore '
          'configOutbounds=${build.configOutboundCount} '
          'configChars=${build.configLength}',
    );
    return _runtime.applyConfig(
      config: build.configJson,
      useVpn: useVpn,
      restartCore: restartCore,
    );
  }

  int _armStartWatchdog({
    required bool useVpn,
    required RuntimeTimeoutHook onTimeout,
  }) {
    final generation = ++_startWatchdogGeneration;
    _startWatchdogTimer?.cancel();
    _startWatchdogTimer = Timer(
      startTimeout + const Duration(milliseconds: 250),
      () {
        unawaited(_handleStartWatchdogTimeout(generation, useVpn, onTimeout));
      },
    );
    return generation;
  }

  bool _claimStartTimeoutHandling(int generation) {
    if (generation != _startWatchdogGeneration) {
      return false;
    }
    if (_handledStartTimeoutGeneration == generation) {
      return false;
    }
    _handledStartTimeoutGeneration = generation;
    return true;
  }

  Future<void> _handleStartWatchdogTimeout(
    int generation,
    bool useVpn,
    RuntimeTimeoutHook onTimeout,
  ) async {
    if (generation != _startWatchdogGeneration) {
      return;
    }
    if (!_claimStartTimeoutHandling(generation)) {
      return;
    }
    AppLogStore.error(
      'sing-box',
      'runtime start watchdog timeout useVpn=$useVpn '
          'timeoutMs=${startTimeout.inMilliseconds}',
    );
    final status = await _runtime
        .status()
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => const <String, dynamic>{'running': false},
        )
        .catchError((_) => const <String, dynamic>{'running': false});
    if (generation != _startWatchdogGeneration) {
      return;
    }
    if (status['running'] == true) {
      cancelStartWatchdog();
      return;
    }
    try {
      await _runtime
          .stop(reason: 'start_timeout')
          .timeout(const Duration(seconds: 3));
    } catch (stopError) {
      AppLogStore.warning(
        'sing-box',
        'runtime stop after watchdog timeout failed: $stopError',
      );
    }
    if (generation != _startWatchdogGeneration) {
      return;
    }
    cancelStartWatchdog();
    await onTimeout(
      const RuntimeLifecycleResult.failure(
        policy: RuntimeApplyPolicy.fullServiceRestart,
        timedOut: true,
        error: 'start_timeout',
      ),
    );
  }

  Future<RuntimeLifecycleResult> _handleImmediateStartTimeout({
    required int generation,
    required bool useVpn,
    required TimeoutException error,
    required StackTrace stackTrace,
  }) async {
    final claimed = _claimStartTimeoutHandling(generation);
    cancelStartWatchdog();
    if (!claimed) {
      final status = await _runtime
          .status()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => const <String, dynamic>{'running': false},
          )
          .catchError((_) => const <String, dynamic>{'running': false});
      if (status['running'] == true) {
        return const RuntimeLifecycleResult.success(
          policy: RuntimeApplyPolicy.fullServiceRestart,
        );
      }
      return const RuntimeLifecycleResult.failure(
        policy: RuntimeApplyPolicy.fullServiceRestart,
        timedOut: true,
        error: 'start_timeout',
      );
    }
    AppLogStore.error(
      'sing-box',
      'runtime start timeout useVpn=$useVpn '
          'timeoutMs=${startTimeout.inMilliseconds} error=$error\n'
          '$stackTrace',
    );
    final status = await _runtime
        .status()
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => const <String, dynamic>{'running': false},
        )
        .catchError((_) => const <String, dynamic>{'running': false});
    if (status['running'] == true) {
      return const RuntimeLifecycleResult.success(
        policy: RuntimeApplyPolicy.fullServiceRestart,
      );
    }
    try {
      await _runtime
          .stop(reason: 'start_timeout')
          .timeout(const Duration(seconds: 3));
    } catch (stopError) {
      AppLogStore.warning(
        'sing-box',
        'runtime stop after start timeout failed: $stopError',
      );
    }
    return const RuntimeLifecycleResult.failure(
      policy: RuntimeApplyPolicy.fullServiceRestart,
      timedOut: true,
      error: 'start_timeout',
    );
  }

  Future<bool> _waitForHealthyRuntime() async {
    final deadline = DateTime.now().add(healthCheckTimeout);
    var lastStatus = const <String, dynamic>{};
    var lastInterface = NetworkInterfaceSnapshot.unavailable;
    while (DateTime.now().isBefore(deadline)) {
      lastStatus = await _runtime
          .status()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => const <String, dynamic>{'running': false},
          )
          .catchError((_) => const <String, dynamic>{'running': false});
      lastInterface = await _runtime
          .getNetworkInterfaceState()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => NetworkInterfaceSnapshot.unavailable,
          )
          .catchError((_) => NetworkInterfaceSnapshot.unavailable);
      final running = lastStatus['running'] == true;
      AppLogStore.info(
        'runtime',
        'runtime health check running=$running '
            'interfaceUsable=${lastInterface.usable} '
            'interface=${lastInterface.interfaceName} '
            'index=${lastInterface.interfaceIndex} '
            'reason=${lastInterface.reason}',
      );
      if (running && lastInterface.usable) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    final running = lastStatus['running'] == true;
    AppLogStore.warning(
      'runtime',
      'runtime health check failed running=$running '
          'interfaceUsable=${lastInterface.usable} '
          'interface=${lastInterface.interfaceName} '
          'index=${lastInterface.interfaceIndex} '
          'reason=${lastInterface.reason}',
    );
    return false;
  }
}
