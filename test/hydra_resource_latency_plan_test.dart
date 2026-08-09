import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/hydra_resource_latency_plan.dart';
import 'package:hydrabox/models/subscription.dart';

void main() {
  const subscription = Subscription(
    id: 'multi-resource',
    name: 'Multi-resource',
    url: 'https://provider.example/subscription',
    selectedProfileId: 'amnezia-profile',
    profiles: <SubscriptionProfile>[
      SubscriptionProfile(
        id: 'amnezia-profile',
        resourceId: 'amnezia-resource',
        name: 'Amnezia',
        entrypointSection: 'outbounds',
        entrypointTag: 'amnezia-internal',
        runtimeTag: 'amnezia',
      ),
      SubscriptionProfile(
        id: 'hysteria-profile',
        resourceId: 'hysteria-resource',
        name: 'Hysteria2',
        entrypointSection: 'outbounds',
        entrypointTag: 'hy2-internal',
        runtimeTag: 'hysteria2',
      ),
      SubscriptionProfile(
        id: 'duplicate-hysteria-profile',
        resourceId: 'duplicate-resource',
        name: 'Duplicate',
        entrypointSection: 'outbounds',
        entrypointTag: 'duplicate',
        runtimeTag: 'hysteria2',
      ),
      SubscriptionProfile(
        id: 'disabled-profile',
        resourceId: 'disabled-resource',
        name: 'Disabled',
        entrypointSection: 'outbounds',
        entrypointTag: 'disabled',
        runtimeTag: 'disabled',
        enabled: false,
      ),
    ],
    resourceConfigs: <String, Map<String, dynamic>>{
      'amnezia-resource': <String, dynamic>{'marker': 'amnezia'},
      'hysteria-resource': <String, dynamic>{'marker': 'hysteria'},
      'duplicate-resource': <String, dynamic>{'marker': 'duplicate'},
      'disabled-resource': <String, dynamic>{'marker': 'disabled'},
    },
  );

  test('plans one standalone URLTest per enabled runtime tag', () {
    final targets = HydraResourceLatencyPlan.targets(
      subscription,
      excludedRuntimeTags: const <String>{'amnezia'},
    );

    expect(targets.map((target) => target.runtimeTag), <String>['hysteria2']);
    expect(targets.single.resourceId, 'hysteria-resource');
  });

  test('cross-resource selection requires a runtime reload', () {
    expect(
      HydraResourceLatencyPlan.requiresRuntimeReload(
        subscription: subscription,
        previousRuntimeTag: 'amnezia',
        nextRuntimeTag: 'hysteria2',
      ),
      isTrue,
    );
    expect(
      HydraResourceLatencyPlan.requiresRuntimeReload(
        subscription: subscription,
        previousRuntimeTag: 'amnezia',
        nextRuntimeTag: 'amnezia',
      ),
      isFalse,
    );
  });

  test('lowest selection resolves to the fastest independent resource', () {
    expect(
      HydraResourceLatencyPlan.concreteSelectionTag(
        subscription: subscription,
        requestedRuntimeTag: 'lowest',
        runtimeLatencies: const <String, int>{'amnezia': 320, 'hysteria2': 140},
      ),
      'hysteria2',
    );
  });

  test('ordinary subscriptions keep command-based selector changes', () {
    const ordinary = Subscription(
      id: 'ordinary',
      name: 'Ordinary',
      url: 'https://provider.example/ordinary',
    );
    expect(
      HydraResourceLatencyPlan.requiresRuntimeReload(
        subscription: ordinary,
        previousRuntimeTag: 'a',
        nextRuntimeTag: 'b',
      ),
      isFalse,
    );
  });
}
