import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/proxy_runtime_controller.dart';
import 'package:meow_client/models/subscription.dart';

void main() {
  test('URLTest group delay updates runtime latency', () {
    final controller = ProxyRuntimeController()..beginLatencySession();
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
    expect(result.requiresRootRebuild, isTrue);
    expect(controller.runtimeLatencies['vless-1'], 73);
    expect(controller.lowestLatency, 73);
    expect(controller.unavailableLatencyTags, isNot(contains('vless-1')));
  });

  test(
    'URLTest failures keep the last latency and never mark proxy unavailable',
    () {
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
      expect(controller.unavailableLatencyTags, isNot(contains('vless-1')));
      expect(controller.runtimeLatencies['vless-1'], 82);
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
      expect(controller.unavailableLatencyTags, isNot(contains('vless-1')));
      expect(controller.runtimeLatencies['vless-1'], 82);
      expect(controller.latencyErrors['vless-1'], 'context deadline exceeded');
      expect(controller.latencyFailureCounts['vless-1'], 2);
    },
  );

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

  test('unfinished session entries become timeout without losing latency', () {
    final controller = ProxyRuntimeController();
    addTearDown(controller.dispose);
    controller.runtimeLatencies['vless-1'] = 73;

    controller.beginLatencySession();
    final changed = controller.finishLatencySession(const ['vless-1']);

    expect(changed, isTrue);
    expect(controller.runtimeLatencies['vless-1'], 73);
    expect(controller.latencyErrors['vless-1'], 'timeout');
    expect(controller.unavailableLatencyTags, isEmpty);
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
      expect(result.requiresRootRebuild, isTrue);
      expect(controller.runtimeLatencies['vless-1'], 73);
    },
  );
}

ProxyRuntimeGroupUpdateInput _input({
  required List<dynamic> rawGroups,
  String selectedProxyTag = 'vless-1',
  bool runtimeSelectionUpdatesAllowed = true,
  bool latencySessionRunning = false,
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
    pendingRuntimeSelectTag: null,
    runtimeSelectionUpdatesAllowed: runtimeSelectionUpdatesAllowed,
    currentResolvedActiveOutboundTag: 'vless-1',
    activeOutboundTags: const {'vless-1', 'vless-2'},
    latencySessionRunning: latencySessionRunning,
    proxyCacheContainsTag: (tag) => tag == 'vless-1',
    visibleGroupProxyCacheMissingChild: (_, _) => false,
  );
}
