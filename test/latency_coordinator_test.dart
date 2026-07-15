import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/latency_coordinator.dart';
import 'package:meow_client/singbox/libbox_capabilities.dart';

const _testPolicy = LatencyUiPolicy(
  nativeCommandTimeout: Duration(milliseconds: 80),
  firstEventGrace: Duration(milliseconds: 60),
  eventSettleDelay: Duration(milliseconds: 25),
  hardWatchdog: Duration(milliseconds: 500),
);

void main() {
  test('bundled core capabilities do not advertise unsupported controls', () {
    const capabilities = LibboxCapabilities.bundledLegacy;

    expect(capabilities.supportsTargetedUrlTest, isFalse);
    expect(capabilities.supportsUrlTestTimeout, isFalse);
    expect(capabilities.supportsUrlTestConcurrency, isFalse);
    expect(capabilities.supportsUrlTestDeadline, isFalse);
    expect(capabilities.supportsUrlTestForce, isFalse);
    expect(
      capabilities.urlTestCompletionModel,
      UrlTestCompletionModel.groupEvents,
    );
  });

  test('startup issues one selector-wide HTTP URLTest request', () async {
    final requests = <LatencyTestRequest>[];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final coordinator = _coordinator(
      runTest: (request) async => requests.add(request),
      eventBaselineTimes: () => <String, int>{'proxy-1': now - 10},
    );
    addTearDown(coordinator.dispose);

    final result = coordinator.runStartup(reason: 'test');
    await Future<void>.delayed(Duration.zero);

    expect(requests, hasLength(1));
    expect(requests.single.groupTag, 'select');
    expect(requests.single.targetOutboundTag, isEmpty);
    expect(requests.single.priorityOutboundTag, 'proxy-1');
    expect(requests.single.excludeOutboundTag, isEmpty);
    expect(coordinator.phase, LatencySessionPhase.collectingEvents);
    expect(
      coordinator.handleGroupEvent(tag: 'proxy-1', timeSeconds: now),
      isTrue,
    );
    expect(await result, isTrue);
    expect(coordinator.phase, LatencySessionPhase.settled);
  });

  test(
    'RPC completion is acceptance, not completion of URLTest results',
    () async {
      var completed = false;
      final coordinator = _coordinator(runTest: (_) async {});
      addTearDown(coordinator.dispose);

      final result = coordinator.runFull(reason: 'manual').then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.isRunning, isTrue);
      expect(coordinator.phase, LatencySessionPhase.collectingEvents);
      expect(completed, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(completed, isFalse);
      expect(await result, isTrue);
      expect(coordinator.isRunning, isFalse);
    },
  );

  test('only fresh per-tag events extend a running session', () async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final coordinator = _coordinator(
      runTest: (_) async {},
      eventBaselineTimes: () => <String, int>{
        'proxy-1': now,
        'proxy-2': now - 5,
      },
    );
    addTearDown(coordinator.dispose);

    final result = coordinator.runFull(reason: 'manual');
    await Future<void>.delayed(Duration.zero);

    expect(
      coordinator.handleGroupEvent(tag: 'proxy-1', timeSeconds: now),
      isFalse,
    );
    expect(
      coordinator.handleGroupEvent(tag: 'proxy-2', timeSeconds: now),
      isTrue,
    );
    expect(
      coordinator.handleGroupEvent(tag: 'proxy-2', timeSeconds: now),
      isFalse,
    );
    expect(await result, isTrue);
  });

  test(
    'a second request is not queued while a session is collecting',
    () async {
      final coordinator = _coordinator(runTest: (_) async {});
      addTearDown(coordinator.dispose);

      final first = coordinator.runFull(reason: 'manual');
      await Future<void>.delayed(Duration.zero);
      expect(await coordinator.runFull(reason: 'manual_repeat'), isFalse);

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        coordinator.handleGroupEvent(tag: 'proxy-1', timeSeconds: now),
        isTrue,
      );
      expect(await first, isTrue);
    },
  );

  test(
    'native command timeout ends UI without starting another command',
    () async {
      final blocker = Completer<void>();
      var calls = 0;
      final coordinator = _coordinator(
        runTest: (_) {
          calls++;
          return blocker.future;
        },
      );
      addTearDown(coordinator.dispose);

      expect(await coordinator.runFull(reason: 'manual'), isFalse);
      expect(coordinator.isRunning, isFalse);
      expect(
        await coordinator.runFull(reason: 'repeat_after_ui_timeout'),
        isFalse,
      );
      expect(calls, 1);

      blocker.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('does not start tests in background or while disconnected', () async {
    var connected = false;
    var foreground = true;
    var calls = 0;
    final coordinator = _coordinator(
      runTest: (_) async => calls++,
      isConnected: () => connected,
      isForeground: () => foreground,
    );
    addTearDown(coordinator.dispose);

    expect(await coordinator.runFull(reason: 'disconnected'), isFalse);
    connected = true;
    foreground = false;
    expect(await coordinator.runFull(reason: 'background'), isFalse);
    expect(calls, 0);
  });

  test('late RPC completion from an old runtime is discarded', () async {
    final blocker = Completer<void>();
    var operationGeneration = 1;
    final coordinator = _coordinator(
      runTest: (_) => blocker.future,
      operationGeneration: () => operationGeneration,
    );
    addTearDown(coordinator.dispose);

    final result = coordinator.runFull(reason: 'old_runtime');
    await Future<void>.delayed(Duration.zero);
    operationGeneration++;
    blocker.complete();

    expect(await result, isFalse);
    expect(coordinator.isRunning, isFalse);
  });

  test('large subscriptions skip automatic and startup group tests', () async {
    var calls = 0;
    final coordinator = _coordinator(
      runTest: (_) async => calls++,
      outboundCount: () => 1000,
    );
    addTearDown(coordinator.dispose);

    expect(await coordinator.runStartup(reason: 'startup'), isFalse);
    expect(await coordinator.runActive(reason: 'selection'), isFalse);
    expect(await coordinator.runFull(reason: 'auto_interval'), isFalse);

    final manual = coordinator.runFull(reason: 'manual');
    await Future<void>.delayed(Duration.zero);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    coordinator.handleGroupEvent(tag: 'proxy-1', timeSeconds: now);
    expect(await manual, isTrue);
    expect(calls, 1);
  });

  test('manual cancellation waits for the native command lane', () async {
    final blocker = Completer<void>();
    final coordinator = _coordinator(runTest: (_) => blocker.future);
    addTearDown(coordinator.dispose);

    final active = coordinator.runFull(reason: 'manual');
    await Future<void>.delayed(Duration.zero);
    var waitFinished = false;
    final wait = coordinator.cancelAndWait().then((_) => waitFinished = true);
    await Future<void>.delayed(Duration.zero);
    expect(waitFinished, isFalse);

    blocker.complete();
    await wait;
    expect(await active, isFalse);
    expect(waitFinished, isTrue);
  });
}

LatencyCoordinator _coordinator({
  required LatencyTestRunner runTest,
  LatencyBoolReader? isConnected,
  LatencyBoolReader? isForeground,
  LatencyIntReader? outboundCount,
  LatencyEventTimesReader? eventBaselineTimes,
  LatencyIntReader? operationGeneration,
}) {
  return LatencyCoordinator(
    runTest: runTest,
    isConnected: isConnected ?? () => true,
    isForeground: isForeground ?? () => true,
    activeOutboundTag: () => 'proxy-1',
    testUrl: () => 'https://example.com/generate_204',
    outboundCount: outboundCount ?? () => 12,
    eventBaselineTimes: eventBaselineTimes,
    operationGeneration: operationGeneration,
    onSessionChanged: (_, _, _) {},
    uiPolicy: _testPolicy,
  );
}
