import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/latency_coordinator.dart';

void main() {
  test('startup uses one selector-wide legacy HTTP session', () async {
    final requests = <LatencyTestRequest>[];
    final coordinator = LatencyCoordinator(
      runTest: (request) async => requests.add(request),
      isConnected: () => true,
      isForeground: () => true,
      activeOutboundTag: () => 'proxy-1',
      testUrl: () => 'https://example.com/generate_204',
      outboundCount: () => 12,
      onSessionChanged: (_, _, _) {},
    );
    addTearDown(coordinator.dispose);

    expect(await coordinator.runStartup(reason: 'test'), isTrue);
    expect(requests, hasLength(1));
    expect(requests.single.targetOutboundTag, isEmpty);
    expect(requests.single.priorityOutboundTag, 'proxy-1');
    expect(requests.single.excludeOutboundTag, isEmpty);
    expect(requests.single.deadlineMillis, inInclusiveRange(14900, 15000));
  });

  test('active refresh uses a real selector-wide HTTP URLTest', () async {
    final requests = <LatencyTestRequest>[];
    final coordinator = LatencyCoordinator(
      runTest: (request) async => requests.add(request),
      isConnected: () => true,
      isForeground: () => true,
      activeOutboundTag: () => 'proxy-1',
      testUrl: () => 'https://example.com/generate_204',
      outboundCount: () => 12,
      onSessionChanged: (_, _, _) {},
    );
    addTearDown(coordinator.dispose);

    expect(await coordinator.runActive(reason: 'selection'), isTrue);
    expect(requests, hasLength(1));
    expect(requests.single.targetOutboundTag, isEmpty);
    expect(requests.single.priorityOutboundTag, 'proxy-1');
    expect(requests.single.concurrency, 0);
    expect(requests.single.timeoutMillis, inInclusiveRange(14900, 15000));
  });

  test('repeated requests do not create parallel sessions', () async {
    final blocker = Completer<void>();
    var calls = 0;
    final coordinator = LatencyCoordinator(
      runTest: (_) async {
        calls++;
        await blocker.future;
      },
      isConnected: () => true,
      isForeground: () => true,
      activeOutboundTag: () => 'proxy-1',
      testUrl: () => 'https://example.com/generate_204',
      outboundCount: () => 30,
      onSessionChanged: (_, _, _) {},
    );
    addTearDown(coordinator.dispose);

    final first = coordinator.runFull(reason: 'manual');
    await Future<void>.delayed(Duration.zero);
    expect(await coordinator.runFull(reason: 'manual_repeat'), isFalse);
    expect(calls, 1);
    blocker.complete();
    expect(await first, isTrue);
  });

  test('does not start tests in background or while disconnected', () async {
    var connected = false;
    var foreground = true;
    var calls = 0;
    final coordinator = LatencyCoordinator(
      runTest: (_) async {
        calls++;
      },
      isConnected: () => connected,
      isForeground: () => foreground,
      activeOutboundTag: () => 'proxy-1',
      testUrl: () => 'https://example.com/generate_204',
      outboundCount: () => 1,
      onSessionChanged: (_, _, _) {},
    );
    addTearDown(coordinator.dispose);

    expect(await coordinator.runFull(reason: 'disconnected'), isFalse);
    connected = true;
    foreground = false;
    expect(await coordinator.runFull(reason: 'background'), isFalse);
    expect(calls, 0);
  });

  test('large subscriptions skip automatic and startup full tests', () async {
    var calls = 0;
    final coordinator = LatencyCoordinator(
      runTest: (_) async => calls++,
      isConnected: () => true,
      isForeground: () => true,
      activeOutboundTag: () => 'proxy-1',
      testUrl: () => 'https://example.com/generate_204',
      outboundCount: () => 1000,
      onSessionChanged: (_, _, _) {},
    );
    addTearDown(coordinator.dispose);

    expect(await coordinator.runStartup(reason: 'startup'), isFalse);
    expect(await coordinator.runActive(reason: 'selection'), isFalse);
    expect(await coordinator.runFull(reason: 'auto_interval'), isFalse);
    expect(await coordinator.runFull(reason: 'manual'), isTrue);
    expect(calls, 1);
  });

  test('late result from an old runtime operation is discarded', () async {
    final blocker = Completer<void>();
    var operationGeneration = 1;
    final coordinator = LatencyCoordinator(
      runTest: (_) => blocker.future,
      isConnected: () => true,
      isForeground: () => true,
      activeOutboundTag: () => 'proxy-1',
      testUrl: () => 'https://example.com/generate_204',
      outboundCount: () => 1,
      onSessionChanged: (_, _, _) {},
      canRunDiagnostics: () => true,
      operationGeneration: () => operationGeneration,
    );
    addTearDown(coordinator.dispose);

    final result = coordinator.runActive(reason: 'old_runtime');
    await Future<void>.delayed(Duration.zero);
    operationGeneration++;
    blocker.complete();

    expect(await result, isFalse);
    expect(coordinator.isRunning, isFalse);
  });

  test(
    'manual replacement waits until the native session leaves the lane',
    () async {
      final blocker = Completer<void>();
      final coordinator = LatencyCoordinator(
        runTest: (_) => blocker.future,
        isConnected: () => true,
        isForeground: () => true,
        activeOutboundTag: () => 'proxy-1',
        testUrl: () => 'https://example.com/generate_204',
        outboundCount: () => 2,
        onSessionChanged: (_, _, _) {},
      );
      addTearDown(coordinator.dispose);

      final active = coordinator.runActive(reason: 'automatic');
      await Future<void>.delayed(Duration.zero);
      var waitFinished = false;
      final wait = coordinator.cancelAndWait().then((_) => waitFinished = true);
      await Future<void>.delayed(Duration.zero);
      expect(waitFinished, isFalse);

      blocker.complete();
      await wait;
      expect(await active, isFalse);
      expect(waitFinished, isTrue);
    },
  );
}
