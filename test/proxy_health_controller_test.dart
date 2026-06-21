import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/proxy_health_controller.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';

void main() {
  test('queue refresh marks checking and respects concurrency', () async {
    final requests = <EndpointProbeRequest>[];
    final completions = Queue<Completer<EndpointProbeResult>>();
    final visualUpdates = <Set<String>>[];
    final outbounds = {
      'vless-1': _outbound('vless-1'),
      'vless-2': _outbound('vless-2'),
    };
    final controller = ProxyHealthController(
      isMounted: () => true,
      isForegroundLifecycleActive: () => true,
      isConnected: () => false,
      isRuntimeTransitionInProgress: () => false,
      concurrency: () => 1,
      resolveOutboundByTag: (tag) => outbounds[tag],
      networkInterfaceUsable: (_) async => true,
      probeEndpoint: (request) {
        requests.add(request);
        final completer = Completer<EndpointProbeResult>();
        completions.add(completer);
        return completer.future;
      },
      onVisualUpdate: visualUpdates.add,
    );
    addTearDown(controller.dispose);

    controller.queueRefresh(outbounds.values, reason: 'test');

    expect(requests.map((request) => request.tag), ['vless-1']);
    expect(controller.effective('vless-1')?.state, ProxyHealthState.checking);
    expect(controller.effective('vless-2')?.state, ProxyHealthState.checking);
    expect(visualUpdates.first, {'vless-1', 'vless-2'});

    completions.removeFirst().complete(_result('vless-1', latencyMs: 70));
    await Future<void>.delayed(Duration.zero);

    expect(requests.map((request) => request.tag), ['vless-1', 'vless-2']);

    completions.removeFirst().complete(_result('vless-2', latencyMs: 91));
    await Future<void>.delayed(Duration.zero);

    expect(controller.effective('vless-1')?.latency, 70);
    expect(controller.effective('vless-2')?.latency, 91);
  });

  test(
    'protect_failed keeps stale state and retries when protect is ready',
    () async {
      final requests = <EndpointProbeRequest>[];
      var connected = true;
      final controller = ProxyHealthController(
        isMounted: () => true,
        isForegroundLifecycleActive: () => true,
        isConnected: () => connected,
        isRuntimeTransitionInProgress: () => false,
        concurrency: () => 1,
        resolveOutboundByTag: (_) => _outbound('vless-1'),
        networkInterfaceUsable: (_) async => true,
        protectRetryDelay: const Duration(milliseconds: 1),
        probeEndpoint: (request) async {
          requests.add(request);
          if (requests.length == 1) {
            return _result(
              request.tag,
              reachable: false,
              protectedSocket: false,
              errorCode: 'protect_failed',
            );
          }
          return _result(request.tag, latencyMs: 66);
        },
        onVisualUpdate: (_) {},
      );
      addTearDown(controller.dispose);

      controller.queueRefresh([_outbound('vless-1')], reason: 'test');
      await _waitUntil(() => requests.length >= 2);

      final health = controller.effective('vless-1');
      expect(connected, isTrue);
      expect(requests.length, 2);
      expect(health?.state, ProxyHealthState.reachable);
      expect(health?.latency, 66);
    },
  );

  test('no interface preserves previous latency as stale state', () async {
    var connected = false;
    var networkUsable = true;
    final controller = ProxyHealthController(
      isMounted: () => true,
      isForegroundLifecycleActive: () => true,
      isConnected: () => connected,
      isRuntimeTransitionInProgress: () => false,
      concurrency: () => 1,
      resolveOutboundByTag: (_) => _outbound('vless-1'),
      networkInterfaceUsable: (_) async => networkUsable,
      forceRefreshCooldown: Duration.zero,
      probeEndpoint: (request) async => _result(request.tag, latencyMs: 88),
      onVisualUpdate: (_) {},
    );
    addTearDown(controller.dispose);

    controller.queueRefresh([_outbound('vless-1')], reason: 'initial');
    await _waitUntil(() => controller.effective('vless-1')?.latency == 88);

    connected = true;
    networkUsable = false;
    controller.queueRefresh(
      [_outbound('vless-1')],
      reason: 'manual_ping_all_connected_fallback',
      ignoreTtl: true,
    );
    await _waitUntil(
      () => controller.effective('vless-1')?.errorCode == 'no_interface',
    );

    final health = controller.effective('vless-1');
    expect(health?.state, ProxyHealthState.stale);
    expect(health?.latency, 88);
    expect(health?.errorCode, 'no_interface');
  });
}

Outbound _outbound(String tag) {
  return Outbound(
    tag: tag,
    name: tag,
    config: {
      'type': 'vless',
      'server': '$tag.example.test',
      'server_port': 443,
    },
  );
}

EndpointProbeResult _result(
  String tag, {
  bool reachable = true,
  int? latencyMs,
  String errorCode = '',
  bool protectedSocket = true,
}) {
  return EndpointProbeResult(
    tag: tag,
    reachable: reachable,
    latencyMs: latencyMs,
    errorCode: errorCode,
    checkedAtMillis: DateTime.now().millisecondsSinceEpoch,
    protectedSocket: protectedSocket,
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not met before timeout');
}
