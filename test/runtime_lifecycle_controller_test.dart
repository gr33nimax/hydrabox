import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/app_background_tasks.dart';
import 'package:hydrabox/app/runtime_lifecycle_controller.dart';
import 'package:hydrabox/singbox/singbox_config_builder.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';

void main() {
  test('safe core restart applies prepared config without full stop', () async {
    final runtime = _FakeRuntime();
    final controller = RuntimeLifecycleController(
      runtime: runtime,
      healthCheckTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    final result = await controller.applyRuntimeBuild(
      build: _build(),
      useVpn: true,
      policy: RuntimeApplyPolicy.safeCoreRestart,
      promotePreparedConfig: (_) {},
      cacheStartedBuild: (_) {},
      logCall: (_, _) {},
      trimMemory: (_) {},
      onWatchdogTimeout: (_) {},
    );

    expect(result.success, isTrue);
    expect(runtime.applyPreparedConfigCalls, 1);
    expect(runtime.lastRestartCore, isTrue);
    expect(runtime.stopCalls, 0);
    expect(runtime.startPreparedCalls, 0);
  });

  test(
    'unusable interface after safe restart runs one full recovery restart',
    () async {
      final runtime = _FakeRuntime(interfaceUsable: false);
      final controller = RuntimeLifecycleController(
        runtime: runtime,
        healthCheckTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);

      var promoteCalls = 0;
      final result = await controller.applyRuntimeBuild(
        build: _build(),
        useVpn: true,
        policy: RuntimeApplyPolicy.safeCoreRestart,
        promotePreparedConfig: (_) => promoteCalls++,
        cacheStartedBuild: (_) {},
        logCall: (_, _) {},
        trimMemory: (_) {},
        onWatchdogTimeout: (_) {},
      );

      expect(result.success, isTrue);
      expect(result.recovered, isTrue);
      expect(runtime.applyPreparedConfigCalls, 1);
      expect(runtime.stopCalls, 1);
      expect(runtime.prepareVpnCalls, 1);
      expect(runtime.startPreparedCalls, 1);
      expect(promoteCalls, 1);
    },
  );

  test(
    'safe restart exception recovers when the runtime also stopped',
    () async {
      final runtime = _FakeRuntime(failApplyAndStopRuntime: true);
      final controller = RuntimeLifecycleController(
        runtime: runtime,
        healthCheckTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);
      var promoteCalls = 0;

      final result = await controller.applyRuntimeBuild(
        build: _build(),
        useVpn: true,
        policy: RuntimeApplyPolicy.safeCoreRestart,
        promotePreparedConfig: (_) => promoteCalls++,
        cacheStartedBuild: (_) {},
        logCall: (_, _) {},
        trimMemory: (_) {},
        onWatchdogTimeout: (_) {},
      );

      expect(result.success, isTrue);
      expect(result.recovered, isTrue);
      expect(runtime.stopCalls, 1);
      expect(runtime.startPreparedCalls, 1);
      expect(promoteCalls, 1);
    },
  );

  test(
    'start watchdog timeout reports failure without localization context',
    () async {
      final runtime = _FakeRuntime(running: false, startCompletes: false);
      final controller = RuntimeLifecycleController(
        runtime: runtime,
        startTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);

      final result = await controller.startRuntimeWithBuild(
        build: _build(),
        useVpn: true,
        promotePreparedConfig: (_) {},
        cacheStartedBuild: (_) {},
        logCall: (_, _) {},
        trimMemory: (_) {},
        onWatchdogTimeout: (_) {},
      );

      expect(result.success, isFalse);
      expect(result.timedOut, isTrue);
      expect(runtime.stopCalls, 1);
    },
  );

  test(
    'native startup error is returned without waiting for timeout',
    () async {
      final runtime = _FakeRuntime(
        running: false,
        confirmStartImmediately: false,
        lastError: 'HydraBox VK WebView credentials are required',
      );
      final controller = RuntimeLifecycleController(
        runtime: runtime,
        startTimeout: const Duration(seconds: 2),
      );
      addTearDown(controller.dispose);

      final result = await controller.startRuntimeWithBuild(
        build: _build(),
        useVpn: true,
        promotePreparedConfig: (_) {},
        cacheStartedBuild: (_) {},
        logCall: (_, _) {},
        trimMemory: (_) {},
        onWatchdogTimeout: (_) {},
      );

      expect(result.success, isFalse);
      expect(result.timedOut, isFalse);
      expect(result.error, contains('VK WebView credentials'));
    },
  );

  test('start waits for the native runtime owner before succeeding', () async {
    final runtime = _FakeRuntime(
      running: false,
      confirmStartImmediately: false,
    );
    final controller = RuntimeLifecycleController(
      runtime: runtime,
      startTimeout: const Duration(milliseconds: 500),
    );
    addTearDown(controller.dispose);

    var completed = false;
    final resultFuture = controller
        .startRuntimeWithBuild(
          build: _build(),
          useVpn: true,
          promotePreparedConfig: (_) {},
          cacheStartedBuild: (_) {},
          logCall: (_, _) {},
          trimMemory: (_) {},
          onWatchdogTimeout: (_) {},
        )
        .then((result) {
          completed = true;
          return result;
        });

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(completed, isFalse);

    runtime.confirmStarted(useVpn: true);
    final result = await resultFuture;

    expect(result.success, isTrue);
    expect(runtime.statusCalls, greaterThanOrEqualTo(1));
  });

  test(
    'running without a native runtime owner is not a successful start',
    () async {
      final runtime = _FakeRuntime(
        running: false,
        confirmStartImmediately: false,
      );
      final controller = RuntimeLifecycleController(
        runtime: runtime,
        startTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(controller.dispose);

      runtime.running = true;
      final result = await controller.startRuntimeWithBuild(
        build: _build(),
        useVpn: true,
        promotePreparedConfig: (_) {},
        cacheStartedBuild: (_) {},
        logCall: (_, _) {},
        trimMemory: (_) {},
        onWatchdogTimeout: (_) {},
      );

      expect(result.success, isFalse);
      expect(result.timedOut, isTrue);
      expect(runtime.stopCalls, 1);
    },
  );

  test(
    'full restart refuses to start over an unconfirmed native stop',
    () async {
      final runtime = _FakeRuntime(ignoreStop: true);
      final controller = RuntimeLifecycleController(
        runtime: runtime,
        stopVerificationTimeout: const Duration(milliseconds: 20),
        stopSettleDelay: Duration.zero,
      );
      addTearDown(controller.dispose);

      final result = await controller.applyRuntimeBuild(
        build: _build(),
        useVpn: true,
        policy: RuntimeApplyPolicy.fullServiceRestart,
        promotePreparedConfig: (_) {},
        cacheStartedBuild: (_) {},
        logCall: (_, _) {},
        trimMemory: (_) {},
        onWatchdogTimeout: (_) {},
      );

      expect(result.success, isFalse);
      expect(result.error, 'runtime_stop_unconfirmed');
      expect(runtime.stopCalls, 1);
      expect(runtime.startPreparedCalls, 0);
    },
  );

  test(
    'explicit stop waits until service and runtime ownership are gone',
    () async {
      final runtime = _FakeRuntime();
      final controller = RuntimeLifecycleController(
        runtime: runtime,
        stopSettleDelay: Duration.zero,
      );
      addTearDown(controller.dispose);

      final stopped = await controller.stopRuntime(reason: 'profile_switch');

      expect(stopped, isTrue);
      expect(runtime.stopCalls, 1);
      expect(runtime.statusCalls, greaterThanOrEqualTo(1));
      expect(runtime.running, isFalse);
      expect(runtime.recordedServiceAlive, isFalse);
      expect(runtime.activeRuntimeOwner, isFalse);
    },
  );
}

SingboxConfigBuildResult _build() {
  return const SingboxConfigBuildResult(
    plan: SingboxBuildPlan(
      config: <String, dynamic>{},
      proxyOutboundTagsByIndex: <int, String>{0: 'vless-1'},
      visibleProxyOutboundCount: 1,
    ),
    configJson: '',
    configPath: 'prepared.json',
    configLength: 2,
    configOutboundCount: 1,
    configInboundCount: 1,
    configRouteRuleCount: 4,
    invalidOutbounds: <InvalidStartupOutbound>[],
    invalidOutboundCount: 0,
    selectedProxyInvalid: false,
    startableOutboundCount: 1,
  );
}

class _FakeRuntime implements RuntimeLifecycleRuntime {
  _FakeRuntime({
    this.running = true,
    this.interfaceUsable = true,
    this.startCompletes = true,
    this.failApplyAndStopRuntime = false,
    this.ignoreStop = false,
    this.confirmStartImmediately = true,
    this.lastError = '',
  }) : recordedServiceAlive = running,
       activeRuntimeOwner = running,
       runtimeGeneration = running ? 1 : 0;

  bool running;
  String mode = 'vpn';
  bool interfaceUsable;
  bool startCompletes;
  bool failApplyAndStopRuntime;
  bool ignoreStop;
  bool confirmStartImmediately;
  String lastError;
  bool recordedServiceAlive;
  bool activeRuntimeOwner;
  int runtimeGeneration;
  int applyPreparedConfigCalls = 0;
  int applyConfigCalls = 0;
  int stopCalls = 0;
  int prepareVpnCalls = 0;
  int startPreparedCalls = 0;
  int statusCalls = 0;
  bool? lastRestartCore;

  @override
  Future<void> applyConfig({
    required String config,
    required bool useVpn,
    required bool restartCore,
  }) async {
    applyConfigCalls++;
    lastRestartCore = restartCore;
    running = true;
    mode = useVpn ? 'vpn' : 'proxy';
  }

  @override
  Future<void> applyPreparedConfig({
    required bool useVpn,
    required bool restartCore,
  }) async {
    applyPreparedConfigCalls++;
    lastRestartCore = restartCore;
    if (failApplyAndStopRuntime) {
      failApplyAndStopRuntime = false;
      running = false;
      throw StateError('runtime stopped during safe restart');
    }
    running = true;
    mode = useVpn ? 'vpn' : 'proxy';
  }

  @override
  Future<NetworkInterfaceSnapshot> getNetworkInterfaceState() async {
    if (!interfaceUsable) {
      return NetworkInterfaceSnapshot.unavailable;
    }
    return const NetworkInterfaceSnapshot(
      available: true,
      interfaceName: 'wlan0',
      interfaceIndex: 1,
      generation: 1,
      reason: 'test',
      updatedAtMillis: 1,
    );
  }

  @override
  Future<bool> prepareVpn({required bool requiresVpn}) async {
    prepareVpnCalls++;
    return true;
  }

  @override
  Future<void> start({required String config, required bool useVpn}) async {
    if (!startCompletes) {
      await Future<void>.delayed(const Duration(minutes: 1));
    }
    mode = useVpn ? 'vpn' : 'proxy';
    if (confirmStartImmediately) {
      confirmStarted(useVpn: useVpn);
    }
  }

  @override
  Future<void> startPrepared({required bool useVpn}) async {
    startPreparedCalls++;
    if (!startCompletes) {
      await Future<void>.delayed(const Duration(minutes: 1));
    }
    mode = useVpn ? 'vpn' : 'proxy';
    if (confirmStartImmediately) {
      confirmStarted(useVpn: useVpn);
    }
  }

  @override
  Future<Map<String, dynamic>> status() async {
    statusCalls++;
    return <String, dynamic>{
      'running': running,
      'mode': mode,
      'runtimeGeneration': runtimeGeneration,
      'recordedServiceAlive': recordedServiceAlive,
      'activeRuntimeOwner': activeRuntimeOwner,
      'lastError': lastError,
    };
  }

  @override
  Future<void> stop({required String reason}) async {
    stopCalls++;
    if (!ignoreStop) {
      running = false;
      recordedServiceAlive = false;
      activeRuntimeOwner = false;
      runtimeGeneration = 0;
    }
  }

  void confirmStarted({required bool useVpn}) {
    running = true;
    mode = useVpn ? 'vpn' : 'proxy';
    recordedServiceAlive = true;
    activeRuntimeOwner = true;
    runtimeGeneration++;
  }
}
