import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/app_background_tasks.dart';
import 'package:hydrabox/app/hydra_resource_latency_plan.dart';
import 'package:hydrabox/app/hydra_runtime_tag_projection.dart';
import 'package:hydrabox/app/proxy_selection_controller.dart';
import 'package:hydrabox/app/subscription_runtime_controller.dart';
import 'package:hydrabox/core/hydra_profile_identity.dart';
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

  final resourceARuntimeTag = HydraProfileIdentity.runtimeTag(
    profileId: 'profile-a',
    resourceId: 'resource-a',
  );
  final resourceBRuntimeTag = HydraProfileIdentity.runtimeTag(
    profileId: 'profile-b',
    resourceId: 'resource-b',
  );
  final sameNativeTagSubscription = Subscription(
    id: 'same-native-tag',
    name: 'Same native tag',
    url: 'https://provider.example/same-tag',
    selectedProxyTag: resourceARuntimeTag,
    selectedProfileId: 'profile-a',
    profiles: <SubscriptionProfile>[
      SubscriptionProfile(
        id: 'profile-a',
        resourceId: 'resource-a',
        name: 'A',
        entrypointSection: 'outbounds',
        entrypointTag: 'proxy',
        runtimeTag: resourceARuntimeTag,
      ),
      SubscriptionProfile(
        id: 'profile-b',
        resourceId: 'resource-b',
        name: 'B',
        entrypointSection: 'outbounds',
        entrypointTag: 'proxy',
        runtimeTag: resourceBRuntimeTag,
      ),
    ],
    outbounds: const <Outbound>[
      Outbound(
        tag: 'proxy',
        name: 'Native A',
        config: <String, dynamic>{
          'type': 'vless',
          'tag': 'proxy',
          'server': 'a.example',
          '_source_scope': 'resource-a',
          '_hydra_source_section': 'outbounds',
          '_hydra_original_tag': 'proxy',
        },
      ),
      Outbound(
        tag: 'proxy',
        name: 'Native B',
        config: <String, dynamic>{
          'type': 'trojan',
          'tag': 'proxy',
          'server': 'b.example',
          '_source_scope': 'resource-b',
          '_hydra_source_section': 'outbounds',
          '_hydra_original_tag': 'proxy',
        },
      ),
    ],
    resourceConfigs: const <String, Map<String, dynamic>>{
      'resource-a': <String, dynamic>{'marker': 'a'},
      'resource-b': <String, dynamic>{'marker': 'b'},
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
        subscription: sameNativeTagSubscription,
        previousRuntimeTag: resourceARuntimeTag,
        nextRuntimeTag: resourceBRuntimeTag,
      ),
      isTrue,
    );
    expect(
      HydraResourceLatencyPlan.requiresRuntimeReload(
        subscription: sameNativeTagSubscription,
        previousRuntimeTag: resourceARuntimeTag,
        nextRuntimeTag: resourceARuntimeTag,
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

  test('same native proxy tags retain independent latency and selection', () {
    final targets = HydraResourceLatencyPlan.targets(sameNativeTagSubscription);

    expect(targets, hasLength(2));
    expect(targets.map((target) => target.nativeEntrypointTag).toSet(), {
      'proxy',
    });
    expect(targets.map((target) => target.runtimeTag).toSet(), {
      resourceARuntimeTag,
      resourceBRuntimeTag,
    });
    expect(resourceARuntimeTag, isNot(resourceBRuntimeTag));
    expect(
      HydraResourceLatencyPlan.concreteSelectionTag(
        subscription: sameNativeTagSubscription,
        requestedRuntimeTag: 'lowest',
        runtimeLatencies: <String, int>{
          resourceARuntimeTag: 310,
          resourceBRuntimeTag: 95,
        },
      ),
      resourceBRuntimeTag,
    );

    final appOutbounds = sameNativeTagSubscription.selectableOutbounds;
    expect(appOutbounds.map((outbound) => outbound.tag).toSet(), {
      resourceARuntimeTag,
      resourceBRuntimeTag,
    });
    expect(appOutbounds.map((outbound) => outbound.config['tag']).toSet(), {
      'proxy',
    });
  });

  test('native telemetry is projected only to the selected app identity', () {
    final projected = HydraRuntimeTagProjection.canonicalizeGroupUpdates(
      subscription: sameNativeTagSubscription,
      selectedRuntimeTag: resourceBRuntimeTag,
      rawGroups: <dynamic>[
        <String, dynamic>{
          'tag': 'select',
          'selected': 'proxy',
          'items': <dynamic>[
            <String, dynamic>{'tag': 'proxy', 'delay': 95},
          ],
        },
        <String, dynamic>{
          'tag': 'proxy',
          'selected': 'child',
          'items': <dynamic>[],
        },
      ],
    );
    final select = Map<String, dynamic>.from(projected.first as Map);
    final item = Map<String, dynamic>.from(
      (select['items'] as List<dynamic>).single as Map,
    );
    final nativeEntrypointGroup = Map<String, dynamic>.from(
      projected.last as Map,
    );

    expect(select['selected'], resourceBRuntimeTag);
    expect(item['tag'], resourceBRuntimeTag);
    expect(item['delay'], 95);
    expect(nativeEntrypointGroup['tag'], resourceBRuntimeTag);
  });

  test('proxy cache keeps same-native-tag measurements independent', () {
    final cache = buildProxyCache(
      ProxyCacheBuildInput(
        subscription: sameNativeTagSubscription,
        selectedProxyTag: resourceBRuntimeTag,
        lowestLatency: 95,
        runtimeLowestOutboundTag: resourceBRuntimeTag,
        runtimeLowestSelections: <String, String>{
          'lowest': resourceBRuntimeTag,
        },
        urlTestInFlight: false,
        runtimeLatencies: <String, int>{
          resourceARuntimeTag: 310,
          resourceBRuntimeTag: 95,
        },
        unavailableLatencyTags: const <String>{},
        latencyErrors: const <String, String>{},
        runtimeGroupSelections: const <String, String>{},
        markAllServersRussia: false,
      ),
    );
    final byTag = <String, int?>{
      for (final proxy in cache.activeProxies) proxy.tag: proxy.latency,
    };

    expect(byTag[resourceARuntimeTag], 310);
    expect(byTag[resourceBRuntimeTag], 95);
    expect(cache.displayProxy?.tag, resourceBRuntimeTag);
  });

  test(
    'legacy native selection migrates through selected profile identity',
    () {
      final legacyProfile = SubscriptionProfile.fromMap(<String, dynamic>{
        'id': 'profile-b',
        'resource_id': 'resource-b',
        'entrypoint_section': 'outbounds',
        'entrypoint_tag': 'proxy',
        'runtime_tag': 'proxy',
      });
      final legacySelection = sameNativeTagSubscription.copyWith(
        selectedProfileId: 'profile-b',
      );
      final normalized = normalizeActiveSubscriptionSelection(
        legacySelection,
        selectedProxyTag: 'proxy',
        preferSelectedProxyTag: true,
      );

      expect(legacyProfile.runtimeTag, resourceBRuntimeTag);
      expect(normalized.selectedProxyTag, resourceBRuntimeTag);
    },
  );

  test(
    'app selection chooses one native resource without rewriting its tag',
    () {
      final selected = sameNativeTagSubscription.copyWith(
        selectedProxyTag: resourceBRuntimeTag,
      );

      expect(selected.selectedProfileId, 'profile-b');
      expect(selected.activeNativeConfig?['marker'], 'b');
      expect(
        selected.nativeEntrypointTagForRuntimeTag(resourceBRuntimeTag),
        'proxy',
      );
      expect(
        selected.runtimeTagForNativeEntrypoint(selected.outbounds.last),
        resourceBRuntimeTag,
      );
    },
  );

  test('full Hydra latency plan builds a chain in its owner resource', () {
    final withChain = sameNativeTagSubscription.copyWith(
      selectedProxyTag: resourceBRuntimeTag,
      selectedProfileId: 'profile-b',
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-a',
          name: 'Chain A',
          targetTag: resourceARuntimeTag,
          detourTag: resourceARuntimeTag,
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
      ],
    );

    final chainTarget = HydraResourceLatencyPlan.targets(
      withChain,
    ).singleWhere((target) => target.runtimeTag == 'chain-a');

    expect(chainTarget.profileId, 'profile-a');
    expect(chainTarget.resourceId, 'resource-a');
    expect(chainTarget.nativeEntrypointTag, 'chain-a');
    expect(chainTarget.validationError, isEmpty);
  });

  test('chain selection atomically persists its owner and requires reload', () {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);
    final withChain = sameNativeTagSubscription.copyWith(
      selectedProxyTag: resourceBRuntimeTag,
      selectedProfileId: 'profile-b',
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-a',
          name: 'Chain A',
          targetTag: resourceARuntimeTag,
          detourTag: resourceARuntimeTag,
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
      ],
    );

    final selected = controller.withSelectedOutbound(withChain, 'chain-a');

    expect(selected.selectedProxyTag, 'chain-a');
    expect(selected.selectedProfileId, 'profile-a');
    expect(selected.toMetadataMap()['selected_profile_id'], 'profile-a');
    expect(selected.activeNativeConfig?['marker'], 'a');
    expect(
      HydraResourceLatencyPlan.requiresRuntimeReload(
        subscription: withChain,
        previousRuntimeTag: resourceBRuntimeTag,
        nextRuntimeTag: 'chain-a',
      ),
      isTrue,
    );
  });

  test('invalid advertised Hydra chain is planned as terminal unavailable', () {
    final withCrossResourceChain = sameNativeTagSubscription.copyWith(
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-cross',
          name: 'Cross-resource chain',
          targetTag: resourceARuntimeTag,
          detourTag: resourceBRuntimeTag,
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
      ],
    );

    final chainTarget = HydraResourceLatencyPlan.targets(
      withCrossResourceChain,
    ).singleWhere((target) => target.runtimeTag == 'chain-cross');

    expect(chainTarget.nativeEntrypointTag, 'chain-cross');
    expect(chainTarget.validationError, contains('cross-resource'));
    expect(chainTarget.validationError, contains('resource-a'));
    expect(chainTarget.validationError, contains('resource-b'));
  });

  test('invalid chain selection cannot change the persisted owner', () {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);
    final withCrossResourceChain = sameNativeTagSubscription.copyWith(
      selectedProxyTag: resourceBRuntimeTag,
      selectedProfileId: 'profile-b',
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-cross',
          name: 'Cross-resource chain',
          targetTag: resourceARuntimeTag,
          detourTag: resourceBRuntimeTag,
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
      ],
    );

    expect(
      () => controller.withSelectedOutbound(
        withCrossResourceChain,
        'chain-cross',
      ),
      throwsA(isA<StateError>()),
    );
    expect(withCrossResourceChain.selectedProfileId, 'profile-b');
    expect(
      withCrossResourceChain.toMetadataMap()['selected_profile_id'],
      'profile-b',
    );
  });

  test('opaque native detour is terminal and never inferred by tag', () {
    final withOpaqueDetour = sameNativeTagSubscription.copyWith(
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-opaque',
          name: 'Opaque chain',
          targetTag: resourceARuntimeTag,
          detourTag: 'proxy',
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
      ],
    );

    final target = HydraResourceLatencyPlan.targets(
      withOpaqueDetour,
    ).singleWhere((candidate) => candidate.runtimeTag == 'chain-opaque');

    expect(target.validationError, contains('app-owned profile identity'));
  });

  test('owner-local lowest and declared groups remain valid detours', () {
    final withVirtualDetours = sameNativeTagSubscription.copyWith(
      outbounds: <Outbound>[
        ...sameNativeTagSubscription.outbounds,
        const Outbound(
          tag: 'hop-a',
          name: 'Hop A',
          config: <String, dynamic>{
            'type': 'trojan',
            'tag': 'hop-a',
            'server': 'hop-a.example',
            '_source_scope': 'resource-a',
            '_hydra_source_section': 'outbounds',
            '_hydra_original_tag': 'hop-a',
          },
        ),
      ],
      groups: const <SubscriptionGroup>[
        SubscriptionGroup(
          tag: 'group-a',
          name: 'Group A',
          outboundTags: <String>['proxy', 'hop-a'],
        ),
      ],
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-lowest',
          name: 'Lowest detour',
          targetTag: resourceARuntimeTag,
          detourTag: 'lowest',
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
        SubscriptionProxyChain(
          tag: 'chain-group',
          name: 'Group detour',
          targetTag: resourceARuntimeTag,
          detourTag: 'group-a',
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
      ],
    );

    final chainTargets = HydraResourceLatencyPlan.targets(
      withVirtualDetours,
    ).where((target) => target.runtimeTag.startsWith('chain-'));

    expect(chainTargets, hasLength(2));
    expect(
      chainTargets.every((target) => target.validationError.isEmpty),
      isTrue,
    );
    expect(
      chainTargets.every((target) => target.resourceId == 'resource-a'),
      isTrue,
    );
  });

  test('chain/profile runtime-tag collision is terminal ambiguous', () {
    final withCollision = sameNativeTagSubscription.copyWith(
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: resourceARuntimeTag,
          name: 'Colliding chain',
          targetTag: resourceARuntimeTag,
          detourTag: resourceARuntimeTag,
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
      ],
    );

    final target = HydraResourceLatencyPlan.targets(
      withCollision,
    ).singleWhere((candidate) => candidate.runtimeTag == resourceARuntimeTag);

    expect(target.validationError, contains('ambiguous'));
  });

  test('cross-subscription Hydra chain is terminal fail-closed', () {
    final withCrossSubscriptionChain = sameNativeTagSubscription.copyWith(
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-cross-subscription',
          name: 'Cross subscription chain',
          targetTag: resourceARuntimeTag,
          detourTag: resourceARuntimeTag,
          targetSubscriptionId: 'another-subscription',
        ),
      ],
    );

    final target = HydraResourceLatencyPlan.targets(withCrossSubscriptionChain)
        .singleWhere(
          (candidate) => candidate.runtimeTag == 'chain-cross-subscription',
        );

    expect(target.validationError, contains('cross-subscription'));
    expect(target.validationError, contains('another-subscription'));
  });

  test('stale latency cannot select an invalid Hydra chain as fastest', () {
    final withCrossResourceChain = sameNativeTagSubscription.copyWith(
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-cross',
          name: 'Cross-resource chain',
          targetTag: resourceARuntimeTag,
          detourTag: resourceBRuntimeTag,
          targetSubscriptionId: sameNativeTagSubscription.id,
        ),
      ],
    );

    final selected = HydraResourceLatencyPlan.concreteSelectionTag(
      subscription: withCrossResourceChain,
      requestedRuntimeTag: 'lowest',
      runtimeLatencies: <String, int>{
        'chain-cross': 1,
        resourceBRuntimeTag: 50,
      },
    );

    expect(selected, resourceBRuntimeTag);
  });

  test('normalization preserves an app-owned proxy chain selection', () {
    final withChain = sameNativeTagSubscription.copyWith(
      selectedProxyTag: 'chain-a',
      proxyChains: const <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain-a',
          name: 'Chain A',
          targetTag: 'proxy',
          detourTag: 'detour',
        ),
      ],
    );

    final normalized = normalizeActiveSubscriptionSelection(
      withChain,
      selectedProxyTag: 'chain-a',
      preferSelectedProxyTag: true,
    );

    expect(normalized.selectedProxyTag, 'chain-a');
    expect(withChain.selectedProfileId, 'profile-a');
    expect(withChain.activeNativeConfig?['marker'], 'a');
  });
}
