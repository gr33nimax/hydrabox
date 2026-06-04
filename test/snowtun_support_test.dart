import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/data/snowtun/snowtun_binary_service.dart';
import 'package:meow_client/data/subscription/subscription_parser.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/singbox_config_builder.dart';

void main() {
  test('keeps snowtun outbound when importing sing-box config', () {
    const content = '''
{
  "outbounds": [
    {
      "type": "snowtun",
      "tag": "snowtun-out",
      "conf_id": "room-1",
      "transport": "xtun"
    }
  ]
}
''';

    final result = SubscriptionParser.parse(content);
    expect(result.outbounds, hasLength(1));
    expect(result.outbounds.first['type'], 'snowtun');
    expect(result.outbounds.first['conf_id'], 'room-1');
    expect(result.outbounds.first['transport'], 'xtun');
  });

  test('injects local snowtun binary path into generated config', () {
    final subscription = Subscription(
      id: 'snowtun',
      name: 'Snowtun',
      url: 'file:///snowtun.json',
      outbounds: const [
        Outbound(
          tag: 'snowtun-out',
          name: 'Snowtun',
          config: {'type': 'snowtun', 'conf_id': 'room-1', 'transport': 'xtun'},
        ),
      ],
    );

    final plan = SingboxConfigBuilder(
      activeSubscription: subscription,
      selectedProxyTag: 'snowtun-out',
      vpnInboundEnabled: false,
      vpnMtu: 3400,
      vpnStrictRoute: true,
      vpnTunImplementation: TunImplementationPreference.mixed,
      proxyInboundEnabled: false,
      proxyMixedListen: '127.0.0.1',
      proxyMixedPort: 1080,
      dnsDirectResolver: 'udp://1.1.1.1',
      dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
      dnsPreferIpv6: false,
      urlTestUrl: 'https://www.gstatic.com/generate_204',
      urlTestIntervalSeconds: 180,
      urlTestTimeoutSeconds: 15,
      urlTestConcurrency: 30,
      urlTestUnavailableCheckIntervalSeconds: 5,
      blockLeaks: false,
      adBlockEnabled: false,
      useRussiaRouteData: false,
      bypassLocalNetwork: true,
      splitRoutingMode: SplitRoutingMode.disabled,
      splitRoutingPackages: const <String>[],
      logLevel: 'warning',
      tcpFastOpenEnabled: true,
      tcpMultiPathEnabled: false,
      interruptExistingConnections: true,
      urlTestStrictTolerance: true,
      markAllServersRussia: false,
      snowtunBinaryPath: '/data/user/0/com.example/files/snowtun/bin/snowtun',
    ).buildPlan();

    final outbounds = (plan.config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    final snowtun = outbounds.firstWhere(
      (outbound) => outbound['type'] == 'snowtun',
    );
    expect(
      snowtun['binary_path'],
      '/data/user/0/com.example/files/snowtun/bin/snowtun',
    );
  });

  test('does not start snowtun protect socket for ordinary proxies', () {
    final subscription = Subscription(
      id: 'vless',
      name: 'VLESS',
      url: 'file:///vless.json',
      outbounds: const [
        Outbound(
          tag: 'vless-out',
          name: 'VLESS',
          config: {
            'type': 'vless',
            'server': 'example.com',
            'server_port': 443,
          },
        ),
      ],
    );

    final plan = SingboxConfigBuilder(
      activeSubscription: subscription,
      selectedProxyTag: 'vless-out',
      vpnInboundEnabled: true,
      vpnMtu: 3400,
      vpnStrictRoute: true,
      vpnTunImplementation: TunImplementationPreference.mixed,
      proxyInboundEnabled: false,
      proxyMixedListen: '127.0.0.1',
      proxyMixedPort: 1080,
      dnsDirectResolver: 'udp://1.1.1.1',
      dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
      dnsPreferIpv6: false,
      urlTestUrl: 'https://www.gstatic.com/generate_204',
      urlTestIntervalSeconds: 180,
      urlTestTimeoutSeconds: 15,
      urlTestConcurrency: 30,
      urlTestUnavailableCheckIntervalSeconds: 5,
      blockLeaks: false,
      adBlockEnabled: false,
      useRussiaRouteData: false,
      bypassLocalNetwork: true,
      splitRoutingMode: SplitRoutingMode.disabled,
      splitRoutingPackages: const <String>[],
      logLevel: 'warning',
      tcpFastOpenEnabled: true,
      tcpMultiPathEnabled: false,
      interruptExistingConnections: true,
      urlTestStrictTolerance: true,
      markAllServersRussia: false,
      snowtunProtectPath: SingboxConfigBuilder.defaultSnowtunProtectPath(),
    ).buildPlan();

    final outbounds = (plan.config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      outbounds.where((outbound) => outbound.containsKey('protect_path')),
      isEmpty,
    );
  });

  test('drops snowtun outbound when local module is not installed', () {
    final subscription = Subscription(
      id: 'snowtun',
      name: 'Snowtun',
      url: 'file:///snowtun.json',
      outbounds: const [
        Outbound(
          tag: 'snowtun-out',
          name: 'Snowtun',
          config: {
            'type': 'snowtun',
            'conf_id': 'room-1',
            'transport': 'xtun',
            'binary_path': '/provider/should-not-be-trusted/snowtun',
          },
        ),
      ],
    );

    final plan = SingboxConfigBuilder(
      activeSubscription: subscription,
      selectedProxyTag: 'snowtun-out',
      vpnInboundEnabled: true,
      vpnMtu: 3400,
      vpnStrictRoute: true,
      vpnTunImplementation: TunImplementationPreference.mixed,
      proxyInboundEnabled: false,
      proxyMixedListen: '127.0.0.1',
      proxyMixedPort: 1080,
      dnsDirectResolver: 'udp://1.1.1.1',
      dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
      dnsPreferIpv6: false,
      urlTestUrl: 'https://www.gstatic.com/generate_204',
      urlTestIntervalSeconds: 180,
      urlTestTimeoutSeconds: 15,
      urlTestConcurrency: 30,
      urlTestUnavailableCheckIntervalSeconds: 5,
      blockLeaks: false,
      adBlockEnabled: false,
      useRussiaRouteData: false,
      bypassLocalNetwork: true,
      splitRoutingMode: SplitRoutingMode.disabled,
      splitRoutingPackages: const <String>[],
      logLevel: 'warning',
      tcpFastOpenEnabled: true,
      tcpMultiPathEnabled: false,
      interruptExistingConnections: true,
      urlTestStrictTolerance: true,
      markAllServersRussia: false,
      snowtunProtectPath: SingboxConfigBuilder.defaultSnowtunProtectPath(),
    ).buildPlan();

    final outbounds = (plan.config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      outbounds.where((outbound) => outbound['type'] == 'snowtun'),
      isEmpty,
    );
    expect(
      outbounds.where((outbound) => outbound.containsKey('protect_path')),
      isEmpty,
    );
  });

  test('resolves preferred ABI keys for Android arm64', () {
    final keys = resolveSnowtunArtifactKeysForCurrentPlatform(
      abi: Abi.androidArm64,
    );
    expect(keys.first, 'arm64-v8a');
    expect(keys, contains('universal'));
  });
}
