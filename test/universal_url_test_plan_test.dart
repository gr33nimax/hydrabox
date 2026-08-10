import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/universal_url_test_plan.dart';
import 'package:hydrabox/models/subscription.dart';

void main() {
  test('plans every supported outbound without a protocol allowlist', () {
    const subscription = Subscription(
      id: 'all-protocols',
      name: 'All protocols',
      url: 'https://provider.example/subscription',
      outbounds: <Outbound>[
        Outbound(
          tag: 'wireguard',
          name: 'WireGuard',
          config: <String, dynamic>{'type': 'wireguard'},
        ),
        Outbound(
          tag: 'anytls',
          name: 'AnyTLS',
          config: <String, dynamic>{'type': 'anytls'},
        ),
        Outbound(
          tag: 'hysteria2',
          name: 'Hysteria2',
          config: <String, dynamic>{'type': 'hysteria2'},
        ),
        Outbound(
          tag: 'vless-xhttp',
          name: 'VLESS XHTTP',
          config: <String, dynamic>{'type': 'vless'},
        ),
        Outbound(
          tag: 'internal-group',
          name: 'Internal',
          config: <String, dynamic>{
            'type': 'selector',
            '_group_only': true,
          },
        ),
      ],
      proxyChains: <SubscriptionProxyChain>[
        SubscriptionProxyChain(
          tag: 'chain',
          name: 'Chain',
          targetTag: 'vless-xhttp',
          detourTag: 'wireguard',
        ),
      ],
    );

    final targets = UniversalUrlTestPlan.targets(subscription);

    expect(targets.map((target) => target.runtimeTag), <String>[
      'wireguard',
      'anytls',
      'hysteria2',
      'vless-xhttp',
      'chain',
    ]);
    expect(
      targets.every((target) => !target.requiresIsolatedConfig),
      isTrue,
    );
  });

  test('maps Hydra resources to the same universal target contract', () {
    const subscription = Subscription(
      id: 'hydra',
      name: 'Hydra',
      url: 'https://provider.example/hydra',
      profiles: <SubscriptionProfile>[
        SubscriptionProfile(
          id: 'profile',
          resourceId: 'resource',
          name: 'AnyTLS',
          entrypointSection: 'outbounds',
          entrypointTag: 'native-anytls',
          runtimeTag: 'app-anytls',
        ),
      ],
      resourceConfigs: <String, Map<String, dynamic>>{
        'resource': <String, dynamic>{'outbounds': <dynamic>[]},
      },
    );

    final target = UniversalUrlTestPlan.targets(subscription).single;

    expect(target.runtimeTag, 'app-anytls');
    expect(target.nativeOutboundTag, 'native-anytls');
    expect(target.profileId, 'profile');
    expect(target.requiresIsolatedConfig, isTrue);
  });
}
