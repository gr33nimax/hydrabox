import 'dart:async';

import 'package:hydrabox/app/app_background_tasks.dart';
import 'package:hydrabox/logging/app_log_store.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';

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
  Future<void> start({
    required String config,
    required bool useVpn,
    required int interactiveDeadlineMillis,
  });

  Future<void> startPrepared({
    required bool useVpn,
    required int interactiveDeadlineMillis,
  });

  Future<void> applyConfig({
    required String config,
    required bool useVpn,
    required bool restartCore,
    required int interactiveDeadlineMillis,
  });

  Future<void> applyPreparedConfig({
    required bool useVpn,
    required bool restartCore,
    required int interactiveDeadlineMillis,
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
    required int interactiveDeadlineMillis,
  }) {
    return _runtime.applyConfig(
      config: config,
      useVpn: useVpn,
      restartCore: restartCore,
      interactiveDeadlineMillis: interactiveDeadlineMillis,
    );
  }

  @override
  Future<void> applyPreparedConfig({
    required bool useVpn,
    required bool restartCore,
    required int interactiveDeadlineMillis,
  }) {
    return _runtime.applyPreparedConfig(
      useVpn: useVpn,
      restartCore: restartCore,
      interactiveDeadlineMillis: interactiveDeadlineMillis,
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
  Future<void> start({
    required String config,
    required bool useVpn,
    required int interactiveDeadlineMillis,
  }) {
    return _runtime.start(
      config: config,
      useVpn: useVpn,
      interactiveDeadlineMillis: interactiveDeadlineMillis,
    );
  }

  @override
  Future<void> startPrepared({
    required bool useVpn,
    required int interactiveDeadlineMillis,
  }) {
    return _runtime.startPrepared(
      useVpn: useVpn,
      interactiveDeadlineMillis: interactiveDeadlineMillis,
    );
  }

  @override
  Future<Map<String, dynamic>> status() => _runtime.status();

  @override
  Future<void> stop({required String reason}) => _runtime.stop(reason: reason);
}

typedef RuntimeBuildHook = FutureOr<void> Function(SingboxConfigBuildResult);
typedef RuntimeVoidHook = void Function(SingboxConfigBuildResult);
typedef RuntimeLogHook = void Function(String method, String detail);

class RuntimeLifecycleController {
  RuntimeLifecycleController({
    RuntimeLifecycleRuntime? runtime,
    this.startTimeout = const Duration(seconds: 45),
    this.interactiveStartTimeout = const Duration(seconds: 120),
    this.stopTimeout = const Duration(seconds: 7),
    this.stopVerificationTimeout = const Duration(seconds: 2),
    this.stopSettleDelay = const Duration(milliseconds: 200),
    this.healthCheckTimeout = const Duration(seconds: 6),
  }) : _runtime = runtime ?? SingboxRuntimeLifecycleRuntime();

  final RuntimeLifecycleRuntime _runtime;
  final Duration startTimeout;
  final Duration interactiveStartTimeout;
  final Duration stopTimeout;
  final Duration stopVerificationTimeout;
  final Duration stopSettleDelay;
  final Duration healthCheckTimeout;

  Duration startTimeoutForBuild(SingboxConfigBuildResult build) {
    if (!build.hasInteractiveVkCall ||
        interactiveStartTimeout <= startTimeout) {
      return startTimeout;
    }
    return interactiveStartTimeout;
  }

  void dispose() {}

  Future<RuntimeLifecycleResult> startRuntimeWithBuild({
    required SingboxConfigBuildResult build,
    required bool useVpn,
    required RuntimeBuildHook promotePreparedConfig,
    required RuntimeVoidHook cacheStartedBuild,
    required RuntimeLogHook logCall,
    required void Function(String reason) trimMemory,
  }) async {
    trimMemory('before_runtime_start_build');
    cacheStartedBuild(build);
    final effectiveStartTimeout = startTimeoutForBuild(build);
    if (build.hasPreparedConfig) {
      await promotePreparedConfig(build);
      logCall(
        'startPrepared',
        'reason=start runtime useVpn=$useVpn '
            'configOutbounds=${build.configOutboundCount}',
      );
      return _waitForStartFuture(
        _runtime.startPrepared(
          useVpn: useVpn,
          interactiveDeadlineMillis: effectiveStartTimeout.inMilliseconds,
        ),
        useVpn: useVpn,
      );
    } else {
      logCall(
        'start',
        'reason=start runtime useVpn=$useVpn '
            'configOutbounds=${build.configOutboundCount} '
            'configChars=${build.configLength}',
      );
      return _waitForStartFuture(
        _runtime.start(
          config: build.configJson,
          useVpn: useVpn,
          interactiveDeadlineMillis: effectiveStartTimeout.inMilliseconds,
        ),
        useVpn: useVpn,
      );
    }
  }

  Future<RuntimeLifecycleResult> _waitForStartFuture(
    Future<void> startFuture, {
    required bool useVpn,
  }) async {
    try {
      await startFuture;
      return const RuntimeLifecycleResult.success(
        policy: RuntimeApplyPolicy.fullServiceRestart,
      );
    } catch (error, stackTrace) {
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
  }) async {
    var preparedBuildPromoted = false;

    Future<void> promotePreparedConfigOnce(
      SingboxConfigBuildResult candidate,
    ) async {
      if (preparedBuildPromoted && candidate.hasPreparedConfig) {
        return;
      }
      await promotePreparedConfig(candidate);
      preparedBuildPromoted = candidate.hasPreparedConfig;
    }

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
        promotePreparedConfig: promotePreparedConfigOnce,
        cacheStartedBuild: cacheStartedBuild,
        logCall: logCall,
        trimMemory: trimMemory,
      );
    }

    try {
      await _applyBuild(
        build: build,
        useVpn: useVpn,
        restartCore: true,
        promotePreparedConfig: promotePreparedConfigOnce,
        cacheStartedBuild: cacheStartedBuild,
        logCall: logCall,
      );
      return const RuntimeLifecycleResult.success(
        policy: RuntimeApplyPolicy.safeCoreRestart,
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
  }) async {
    try {
      logCall('stop', 'reason=$reason before runtime restart useVpn=$useVpn');
      final stopConfirmed = await stopRuntime(reason: reason);
      if (!stopConfirmed) {
        AppLogStore.error(
          'runtime',
          'runtime restart blocked because the previous service/TUN stop '
              'was not confirmed reason=$reason useVpn=$useVpn',
        );
        return const RuntimeLifecycleResult.failure(
          policy: RuntimeApplyPolicy.fullServiceRestart,
          error: 'runtime_stop_unconfirmed',
        );
      }
      trimMemory('before_runtime_restart');
      final granted = await _runtime.prepareVpn(requiresVpn: useVpn);
      if (!granted) {
        return const RuntimeLifecycleResult.failure(
          policy: RuntimeApplyPolicy.fullServiceRestart,
          error: 'vpn_permission_denied',
        );
      }
      return await startRuntimeWithBuild(
        build: build,
        useVpn: useVpn,
        promotePreparedConfig: promotePreparedConfig,
        cacheStartedBuild: cacheStartedBuild,
        logCall: logCall,
        trimMemory: trimMemory,
      );
    } catch (error, stackTrace) {
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

  Future<bool> stopRuntime({required String reason}) async {
    try {
      await _runtime.stop(reason: reason);
      return true;
    } catch (error, stackTrace) {
      AppLogStore.warning(
        'runtime',
        'native runtime stop call failed reason=$reason error=$error\n'
            '$stackTrace',
      );
      return false;
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
        interactiveDeadlineMillis: startTimeoutForBuild(build).inMilliseconds,
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
      interactiveDeadlineMillis: startTimeoutForBuild(build).inMilliseconds,
    );
  }

}
