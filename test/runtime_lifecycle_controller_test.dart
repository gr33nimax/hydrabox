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
    );

    expect(result.success, isTrue);
    expect(runtime.applyPreparedConfigCalls, 1);
    expect(runtime.lastRestartCore, isTrue);
    expect(runtime.stopCalls, 0);
    expect(runtime.startPreparedCalls, 0);
  });


  test('start passes the regular deadline to the native owner', () async {
    final runtime = _FakeRuntime(running: false);
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
    );

    expect(result.success, isTrue);
    expect(runtime.lastInteractiveDeadlineMillis, 10);
    expect(runtime.stopCalls, 0);
  });

  test('start completion belongs to the native owner', () async {
    final runtime = _FakeRuntime(running: false);
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
    );

    expect(result.success, isTrue);
    expect(result.timedOut, isFalse);
    expect(result.error, isNull);
  });

  test(
    'start returns the native command result without status polling',
    () async {
      final runtime = _FakeRuntime(
        running: false,
        confirmStartImmediately: false,
      );
      final controller = RuntimeLifecycleController(
        runtime: runtime,
        startTimeout: const Duration(milliseconds: 500),
      );
      addTearDown(controller.dispose);

      final result = await controller.startRuntimeWithBuild(
        build: _build(),
        useVpn: true,
        promotePreparedConfig: (_) {},
        cacheStartedBuild: (_) {},
        logCall: (_, _) {},
        trimMemory: (_) {},
      );

      expect(result.success, isTrue);
      expect(runtime.statusCalls, 0);
    },
  );

  test('VK call build uses the interactive startup timeout', () async {
    final runtime = _FakeRuntime(
      running: false,
      startDelay: const Duration(milliseconds: 30),
    );
    final controller = RuntimeLifecycleController(
      runtime: runtime,
      startTimeout: const Duration(milliseconds: 10),
      interactiveStartTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    final result = await controller.startRuntimeWithBuild(
      build: _build(hasInteractiveVkCall: true),
      useVpn: true,
      promotePreparedConfig: (_) {},
      cacheStartedBuild: (_) {},
      logCall: (_, _) {},
      trimMemory: (_) {},
    );

    expect(result.success, isTrue);
    expect(runtime.stopCalls, 0);
    expect(runtime.lastInteractiveDeadlineMillis, 100);
  });

  test(
    'running state without legacy owner evidence is a successful start',
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
      );

      expect(result.success, isTrue);
      expect(result.timedOut, isFalse);
      expect(runtime.stopCalls, 0);
    },
  );

  test('explicit stop returns the native command result without status polling', () async {
    final runtime = _FakeRuntime();
    final controller = RuntimeLifecycleController(
      runtime: runtime,
      stopSettleDelay: Duration.zero,
    );
    addTearDown(controller.dispose);

    final stopped = await controller.stopRuntime(reason: 'profile_switch');

    expect(stopped, isTrue);
    expect(runtime.stopCalls, 1);
    expect(runtime.statusCalls, 0);
    expect(runtime.running, isFalse);
  });
}

SingboxConfigBuildResult _build({bool hasInteractiveVkCall = false}) {
  return SingboxConfigBuildResult(
    plan: const SingboxBuildPlan(
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
    hasInteractiveVkCall: hasInteractiveVkCall,
  );
}

class _FakeRuntime implements RuntimeLifecycleRuntime {
  _FakeRuntime({
    this.running = true,
    this.confirmStartImmediately = true,
    this.startDelay = Duration.zero,
  }) : runtimeGeneration = running ? 1 : 0;

  bool running;
  String mode = 'vpn';
  bool confirmStartImmediately;
  Duration startDelay;
  int runtimeGeneration;
  int applyPreparedConfigCalls = 0;
  int applyConfigCalls = 0;
  int stopCalls = 0;
  int prepareVpnCalls = 0;
  int startPreparedCalls = 0;
  int statusCalls = 0;
  int? lastInteractiveDeadlineMillis;
  bool? lastRestartCore;

  @override
  Future<void> applyConfig({
    required String config,
    required bool useVpn,
    required bool restartCore,
    required int interactiveDeadlineMillis,
  }) async {
    lastInteractiveDeadlineMillis = interactiveDeadlineMillis;
    applyConfigCalls++;
    lastRestartCore = restartCore;
    running = true;
    mode = useVpn ? 'vpn' : 'proxy';
  }

  @override
  Future<void> applyPreparedConfig({
    required bool useVpn,
    required bool restartCore,
    required int interactiveDeadlineMillis,
  }) async {
    applyPreparedConfigCalls++;
    lastRestartCore = restartCore;
    running = true;
    mode = useVpn ? 'vpn' : 'proxy';
  }

  @override
  Future<NetworkInterfaceSnapshot> getNetworkInterfaceState() async {
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
  Future<void> start({
    required String config,
    required bool useVpn,
    required int interactiveDeadlineMillis,
  }) async {
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
    }
    mode = useVpn ? 'vpn' : 'proxy';
    if (confirmStartImmediately) {
      confirmStarted(useVpn: useVpn);
    }
  }

  @override
  Future<void> startPrepared({
    required bool useVpn,
    required int interactiveDeadlineMillis,
  }) async {
    startPreparedCalls++;
    lastInteractiveDeadlineMillis = interactiveDeadlineMillis;
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
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
      'state': running ? 'RUNTIME_STATE_RUNNING' : 'RUNTIME_STATE_STOPPED',
      'mode': mode,
      'runtimeGeneration': runtimeGeneration,
    };
  }

  @override
  Future<void> stop({required String reason}) async {
    stopCalls++;
    running = false;
    runtimeGeneration = 0;
  }

  void confirmStarted({required bool useVpn}) {
    running = true;
    mode = useVpn ? 'vpn' : 'proxy';
    runtimeGeneration++;
  }
}
