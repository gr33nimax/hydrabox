import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:hydrabox/singbox/hydracore_capabilities.dart';

void main() {
  test('required HydraCore release exposes the complete API v2 contract', () {
    const capabilities = HydraCoreCapabilities.requiredV2;

    expect(capabilities.apiVersion, 2);
    expect(capabilities.coreId, HydraCoreCapabilities.hydraCoreId);
    expect(capabilities.remotePolicyVersion, 2);
    expect(capabilities.subscriptionContracts, contains(2));
    expect(capabilities.supportsRuntimeSnapshot, isTrue);
    expect(capabilities.supportsRuntimeEvents, isTrue);
    expect(capabilities.supportsManagedUrlTestSessions, isTrue);
    expect(capabilities.supportsSubscriptionJwe, isTrue);
    expect(capabilities.coreRole, 'client');
    expect(capabilities.supportsCallVkParasiteClient, isTrue);
    expect(capabilities.supportsCallVkParasiteServer, isFalse);
    expect(capabilities.supportsCallVkFourLaneKcp, isTrue);
    expect(capabilities.remoteSafeInboundTypes, isEmpty);
    expect(capabilities.remoteSafeOutboundTypes, contains('call'));
    expect(capabilities.remoteSafeEndpointTypes, {'wireguard'});
    expect(capabilities.isCompatibleRelease, isTrue);
  });

  test('active profile selects one resource without merging documents', () {
    const subscription = Subscription(
      id: 'multi-resource',
      name: 'Multi-resource',
      url: 'https://provider.example/subscription',
      selectedProfileId: 'profile-b',
      profiles: [
        SubscriptionProfile(
          id: 'profile-a',
          resourceId: 'resource-a',
          name: 'A',
          entrypointSection: 'outbounds',
          entrypointTag: 'proxy',
          runtimeTag: 'proxy',
        ),
        SubscriptionProfile(
          id: 'profile-b',
          resourceId: 'resource-b',
          name: 'B',
          entrypointSection: 'outbounds',
          entrypointTag: 'proxy',
          runtimeTag: 'proxy',
        ),
      ],
      resourceConfigs: {
        'resource-a': {
          'outbounds': [
            {'type': 'vless', 'tag': 'proxy', 'server': 'a.example'},
          ],
        },
        'resource-b': {
          'outbounds': [
            {'type': 'trojan', 'tag': 'proxy', 'server': 'b.example'},
          ],
        },
      },
    );

    final selected = subscription.activeNativeConfig!;
    expect(selected['outbounds'], hasLength(1));
    expect(
      (selected['outbounds'] as List<dynamic>).single['server'],
      'b.example',
    );
    expect(selected.toString(), isNot(contains('a.example')));
  });

  test('disabled selected profile falls back to the first enabled profile', () {
    const subscription = Subscription(
      id: 'disabled-profile',
      name: 'Disabled profile',
      url: 'https://provider.example/subscription',
      selectedProfileId: 'disabled',
      profiles: [
        SubscriptionProfile(
          id: 'disabled',
          resourceId: 'resource-disabled',
          name: 'Disabled',
          entrypointSection: 'outbounds',
          entrypointTag: 'disabled',
          runtimeTag: 'disabled',
          enabled: false,
        ),
        SubscriptionProfile(
          id: 'enabled',
          resourceId: 'resource-enabled',
          name: 'Enabled',
          entrypointSection: 'outbounds',
          entrypointTag: 'enabled',
          runtimeTag: 'enabled',
        ),
      ],
      resourceConfigs: {
        'resource-disabled': {'marker': 'disabled'},
        'resource-enabled': {'marker': 'enabled'},
      },
    );

    expect(subscription.activeNativeConfig?['marker'], 'enabled');
  });
}
