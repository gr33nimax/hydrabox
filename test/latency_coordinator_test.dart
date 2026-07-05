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

  test(
    'active refresh keeps HTTP selector semantics without target probe',
    () async {
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
      expect(requests.single.timeoutMillis, inInclusiveRange(14900, 15000));
    },
  );

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
}
