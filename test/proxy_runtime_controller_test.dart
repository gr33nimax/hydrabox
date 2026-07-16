import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/proxy_runtime_controller.dart';
import 'package:meow_client/models/subscription.dart';

void main() {
  test('URLTest group delay updates runtime latency', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);

    final result = controller.applyGroupUpdates(
      _input(
        rawGroups: [
          {
            'tag': 'select',
            'selected': 'vless-1',
            'items': [
              {
                'tag': 'vless-1',
                'status': 'available',
                'delay': 73,
                'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              },
            ],
          },
        ],
        latencySessionRunning: true,
      ),
    );

    expect(result.changed, isTrue);
    expect(result.requiresRootRebuild, isFalse);
    expect(controller.runtimeLatencies['vless-1'], 73);
    expect(controller.lowestLatency, 73);
    expect(controller.unavailableLatencyTags, isNot(contains('vless-1')));
  });

  test('URLTest failures clear stale latency and mark proxy unavailable', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);
    controller.runtimeLatencies['vless-1'] = 82;

    final first = controller.applyGroupUpdates(
      _input(
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {
                'tag': 'vless-1',
                'status': 'unavailable',
                'error': 'context deadline exceeded',
                'time': 1,
              },
            ],
          },
        ],
      ),
    );

    expect(first.changed, isTrue);
    expect(controller.unavailableLatencyTags, contains('vless-1'));
    expect(controller.runtimeLatencies['vless-1'], isNull);
    expect(controller.latencyErrors['vless-1'], 'context deadline exceeded');
    expect(controller.latencyFailureCounts['vless-1'], 1);

    final second = controller.applyGroupUpdates(
      _input(
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {
                'tag': 'vless-1',
                'status': 'unavailable',
                'error': 'context deadline exceeded',
                'time': 2,
              },
            ],
          },
        ],
      ),
    );

    expect(second.changed, isTrue);
    expect(controller.unavailableLatencyTags, contains('vless-1'));
    expect(controller.runtimeLatencies['vless-1'], isNull);
    expect(controller.latencyErrors['vless-1'], 'context deadline exceeded');
    expect(controller.latencyFailureCounts['vless-1'], 2);
  });

  test('frozen transition keeps existing latency and ignores failures', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);

    controller.runtimeLatencies['vless-1'] = 73;
    controller.lowestLatency = 73;
    controller.beginTransition();

    final result = controller.applyGroupUpdates(
      _input(
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {
                'tag': 'vless-1',
                'status': 'unavailable',
                'error': 'no available network interface',
                'time': 2,
              },
            ],
          },
        ],
      ),
    );

    expect(result.changed, isFalse);
    expect(controller.updatesFrozen, isTrue);
    expect(controller.runtimeLatencies['vless-1'], 73);
    expect(controller.lowestLatency, 73);
    expect(controller.unavailableLatencyTags, isEmpty);

    controller.endTransition();
    final next = controller.applyGroupUpdates(
      _input(
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {'tag': 'vless-1', 'status': 'available', 'delay': 91, 'time': 3},
            ],
          },
        ],
      ),
    );

    expect(next.changed, isTrue);
    expect(controller.runtimeLatencies['vless-1'], 91);
    expect(controller.lowestLatency, 91);
  });

  test('session owner filters cached values before applying fresh result', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);
    controller.runtimeLatencies.addAll({'vless-1': 42, 'vless-2': 51});
    controller.runtimeLatencyTimes.addAll({'vless-1': 100, 'vless-2': 100});

    final cachedSnapshot = controller.applyGroupUpdates(
      _input(
        shouldIgnoreLatencyResult: (_, timeSeconds) => timeSeconds <= 100,
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {
                'tag': 'vless-1',
                'status': 'available',
                'delay': 42,
                'time': 100,
              },
            ],
          },
        ],
      ),
    );

    expect(cachedSnapshot.changed, isFalse);

    final freshSnapshot = controller.applyGroupUpdates(
      _input(
        shouldIgnoreLatencyResult: (_, timeSeconds) => timeSeconds <= 100,
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {
                'tag': 'vless-1',
                'status': 'available',
                'delay': 73,
                'time': 101,
              },
            ],
          },
        ],
      ),
    );

    expect(freshSnapshot.changed, isTrue);
    expect(controller.runtimeLatencies['vless-1'], 73);
    expect(controller.runtimeLatencies['vless-2'], 51);
    expect(controller.latencyErrors['vless-2'], isNull);
  });

  test('duplicate failure timestamp is applied only once', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);
    final snapshot = [
      {
        'tag': 'select',
        'items': [
          {
            'tag': 'vless-1',
            'status': 'unavailable',
            'error': 'timeout',
            'time': 50,
          },
        ],
      },
    ];

    final first = controller.applyGroupUpdates(_input(rawGroups: snapshot));
    final duplicate = controller.applyGroupUpdates(_input(rawGroups: snapshot));

    expect(first.changed, isTrue);
    expect(duplicate.changed, isFalse);
    expect(controller.latencyFailureCounts['vless-1'], 1);
  });

  test('older URLTest snapshots cannot overwrite a newer result', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);

    final newer = controller.applyGroupUpdates(
      _input(
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {
                'tag': 'vless-1',
                'status': 'available',
                'delay': 73,
                'time': 20,
              },
            ],
          },
        ],
      ),
    );
    final older = controller.applyGroupUpdates(
      _input(
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {
                'tag': 'vless-1',
                'status': 'available',
                'delay': 999,
                'time': 19,
              },
            ],
          },
        ],
      ),
    );

    expect(newer.changed, isTrue);
    expect(older.changed, isFalse);
    expect(controller.runtimeLatencies['vless-1'], 73);
    expect(controller.runtimeLatencyTimes['vless-1'], 20);
  });

  test('an error without an unavailable status is still a failed URLTest', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);
    controller.runtimeLatencies['vless-1'] = 73;

    controller.applyGroupUpdates(
      _input(
        rawGroups: [
          {
            'tag': 'select',
            'items': [
              {'tag': 'vless-1', 'error': 'TLS handshake failed', 'time': 30},
            ],
          },
        ],
      ),
    );

    expect(controller.runtimeLatencies['vless-1'], isNull);
    expect(controller.unavailableLatencyTags, contains('vless-1'));
    expect(controller.latencyErrors['vless-1'], 'TLS handshake failed');
  });

  test('reachable endpoint fallback does not override URLTest failure', () {
    expect(
      ProxyRuntimeController.effectiveLatencyUnavailable(
        urlTestUnavailable: true,
        endpointFallbackReachable: true,
      ),
      isTrue,
    );
    expect(
      ProxyRuntimeController.effectiveLatencyError(
        urlTestError: 'context deadline exceeded',
        endpointFallbackReachable: true,
      ),
      'context deadline exceeded',
    );
    expect(
      ProxyRuntimeController.effectiveLatencyUnavailable(
        urlTestUnavailable: true,
        endpointFallbackReachable: false,
      ),
      isTrue,
    );
  });

  test(
    'runtime selected event is ignored when selection updates are disabled',
    () {
      final controller = ProxyRuntimeController();
      addTearDown(controller.dispose);

      final result = controller.applyGroupUpdates(
        _input(
          selectedProxyTag: 'vless-2',
          runtimeSelectionUpdatesAllowed: false,
          rawGroups: [
            {
              'tag': 'select',
              'selected': 'vless-1',
              'items': [
                {
                  'tag': 'vless-1',
                  'status': 'available',
                  'delay': 73,
                  'time': 1,
                },
              ],
            },
          ],
        ),
      );

      expect(result.changed, isTrue);
      expect(result.selectedProxyTagToApply, isNull);
      expect(result.requiresRootRebuild, isFalse);
      expect(controller.runtimeLatencies['vless-1'], 73);
    },
  );

  test('session activity without new telemetry does not rebuild UI', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);

    final result = controller.applyGroupUpdates(
      _input(
        latencySessionRunning: true,
        rawGroups: [
          {'tag': 'select', 'selected': 'vless-1', 'items': const <dynamic>[]},
        ],
      ),
    );

    expect(result.changed, isFalse);
    expect(result.requiresRootRebuild, isFalse);
  });

  test('confirmed runtime selection still requires a root rebuild', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);

    final result = controller.applyGroupUpdates(
      _input(
        selectedProxyTag: 'vless-2',
        rawGroups: [
          {'tag': 'select', 'selected': 'vless-1', 'items': const <dynamic>[]},
        ],
      ),
    );

    expect(result.changed, isTrue);
    expect(result.selectedProxyTagToApply, 'vless-1');
    expect(result.requiresRootRebuild, isTrue);
  });

  test('stale runtime selection cannot replace pending startup choice', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);

    final result = controller.applyGroupUpdates(
      _input(
        selectedProxyTag: 'france',
        pendingRuntimeSelectTag: 'france',
        rawGroups: [
          {'tag': 'select', 'selected': 'sweden', 'items': const <dynamic>[]},
        ],
      ),
    );

    expect(result.selectedProxyTagToApply, isNull);
    expect(result.shouldClearRuntimeProxySelectionGuard, isFalse);
  });
}

ProxyRuntimeGroupUpdateInput _input({
  required List<dynamic> rawGroups,
  String selectedProxyTag = 'vless-1',
  String? pendingRuntimeSelectTag,
  bool runtimeSelectionUpdatesAllowed = true,
  bool latencySessionRunning = false,
  StaleLatencyResultFilter? shouldIgnoreLatencyResult,
}) {
  return ProxyRuntimeGroupUpdateInput(
    rawGroups: rawGroups,
    activeSubscription: const Subscription(
      id: 'sub-1',
      name: 'Subscription',
      url: 'https://example.test/sub',
      outbounds: [
        Outbound(
          tag: 'vless-1',
          name: 'VLESS 1',
          config: {
            'type': 'vless',
            'server': 'example.test',
            'server_port': 443,
          },
        ),
      ],
    ),
    selectedProxyTag: selectedProxyTag,
    pendingRuntimeSelectTag: pendingRuntimeSelectTag,
    runtimeSelectionUpdatesAllowed: runtimeSelectionUpdatesAllowed,
    currentResolvedActiveOutboundTag: 'vless-1',
    activeOutboundTags: const {'vless-1', 'vless-2'},
    latencySessionRunning: latencySessionRunning,
    shouldIgnoreLatencyResult: shouldIgnoreLatencyResult ?? (_, _) => false,
    proxyCacheContainsTag: (tag) => tag == 'vless-1',
    visibleGroupProxyCacheMissingChild: (_, _) => false,
  );
}
