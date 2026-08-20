import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:hydrabox/singbox/singbox_config_builder.dart';

void main() {
  const sampleSubscription = Subscription(
    id: 'sub-fakeip-test',
    name: 'FakeIP Test Sub',
    url: 'https://example.com/sub',
    outbounds: [],
  );

  SingboxConfigBuilder createBuilder({
    bool dnsFakeIpEnabled = true,
    bool dnsPreferIpv6 = false,
    bool useRussiaRouteData = true,
    bool adBlockEnabled = false,
    String cacheId = 'sub-fakeip-test',
  }) {
    return SingboxConfigBuilder(
      activeSubscription: sampleSubscription,
      selectedProxyTag: 'proxy-1',
      cacheId: cacheId,
      vpnInboundEnabled: true,
      vpnMtu: 9000,
      vpnStrictRoute: true,
      vpnTunImplementation: TunImplementationPreference.mixed,
      proxyInboundEnabled: false,
      proxyMixedListen: '127.0.0.1',
      proxyMixedPort: 1080,
      dnsDirectResolver: 'udp://1.1.1.1',
      dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
      dnsPreferIpv6: dnsPreferIpv6,
      dnsFakeIpEnabled: dnsFakeIpEnabled,
      russiaDnsDirectResolver: defaultRussiaDnsDirectResolver,
      urlTestUrl: defaultUrlTestUrl,
      urlTestIntervalSeconds: 1800,
      urlTestTimeoutSeconds: 15,
      urlTestConcurrency: 8,
      urlTestUnavailableCheckIntervalSeconds: 120,
      blockLeaks: false,
      adBlockEnabled: adBlockEnabled,
      useRussiaRouteData: useRussiaRouteData,
      russiaGeositeRuBlockedPath: useRussiaRouteData
          ? '/tmp/geosite-ru-blocked.srs'
          : null,
      russiaGeositeRuAvailableOnlyInsidePath: useRussiaRouteData
          ? '/tmp/geosite-ru-available-only-inside.srs'
          : null,
      russiaGeositeCategoryRuPath: useRussiaRouteData
          ? '/tmp/geosite-category-ru.srs'
          : null,
      russiaGeoipRuBlockedPath: useRussiaRouteData
          ? '/tmp/geoip-ru-blocked.srs'
          : null,
      russiaGeoipRuWhitelistPath: useRussiaRouteData
          ? '/tmp/geoip-ru-whitelist.srs'
          : null,
      russiaGeoipRuPath: useRussiaRouteData ? '/tmp/geoip-ru.srs' : null,
      russiaCuratedDirectServicesPath: useRussiaRouteData
          ? '/tmp/geosite-ru-available-only-inside.srs'
          : null,
      russiaAiServicesPath: useRussiaRouteData
          ? '/tmp/geosite-ru-blocked.srs'
          : null,
      bypassLocalNetwork: true,
      splitRoutingMode: SplitRoutingMode.disabled,
      splitRoutingPackages: const <String>[],
      logLevel: 'warning',
      tcpFastOpenEnabled: true,
      tcpMultiPathEnabled: false,
      tlsFragmentationMode: TlsFragmentationMode.disabled,
      interruptExistingConnections: true,
      urlTestStrictTolerance: true,
      markAllServersRussia: false,
    );
  }

  test(
    'Test 1: dns.servers contains dns-fakeip with IPv4 and conditional IPv6',
    () {
      final configIpv4 = createBuilder(
        dnsFakeIpEnabled: true,
        dnsPreferIpv6: false,
      ).build();

      final serversIpv4 = (configIpv4['dns']['servers'] as List)
          .cast<Map<String, dynamic>>();
      final fakeIpServerIpv4 = serversIpv4.firstWhere(
        (s) => s['tag'] == 'dns-fakeip',
      );
      expect(fakeIpServerIpv4['type'], 'fakeip');
      expect(fakeIpServerIpv4['inet4_range'], '198.18.0.0/15');
      expect(fakeIpServerIpv4, isNot(contains('inet6_range')));

      final configIpv6 = createBuilder(
        dnsFakeIpEnabled: true,
        dnsPreferIpv6: true,
      ).build();

      final serversIpv6 = (configIpv6['dns']['servers'] as List)
          .cast<Map<String, dynamic>>();
      final fakeIpServerIpv6 = serversIpv6.firstWhere(
        (s) => s['tag'] == 'dns-fakeip',
      );
      expect(fakeIpServerIpv6['type'], 'fakeip');
      expect(fakeIpServerIpv6['inet4_range'], '198.18.0.0/15');
      expect(fakeIpServerIpv6['inet6_range'], 'fc00::/18');
    },
  );

  test('Test 2: dns.servers does not contain dns-fakeip when disabled', () {
    final config = createBuilder(dnsFakeIpEnabled: false).build();
    final servers = (config['dns']['servers'] as List)
        .cast<Map<String, dynamic>>();
    expect(servers.any((s) => s['tag'] == 'dns-fakeip'), isFalse);
  });

  test(
    'Test 3: dns.rules routes A/AAAA queries to dns-fakeip at the end of rules',
    () {
      final config = createBuilder(dnsFakeIpEnabled: true).build();
      final dnsRules = (config['dns']['rules'] as List)
          .cast<Map<String, dynamic>>();
      expect(dnsRules, isNotEmpty);

      final lastRule = dnsRules.last;
      expect(lastRule['action'], 'route');
      expect(lastRule['server'], 'dns-fakeip');
      expect(lastRule['query_type'], ['A', 'AAAA']);
    },
  );

  test(
    'Test 4: route.rules contains resolve action before geoip whitelist/direct rule',
    () {
      final config = createBuilder(
        dnsFakeIpEnabled: true,
        useRussiaRouteData: true,
      ).build();

      final routeRules = (config['route']['rules'] as List)
          .cast<Map<String, dynamic>>();
      final geoipRuleIndex = routeRules.indexWhere((r) {
        final ruleSet = r['rule_set'];
        return ruleSet is List &&
            ruleSet.contains('ru-geoip-ru-whitelist') &&
            ruleSet.contains('ru-geoip-ru');
      });

      expect(geoipRuleIndex, greaterThan(0));
      final resolveRule = routeRules[geoipRuleIndex - 1];
      expect(resolveRule['action'], 'resolve');
      expect(resolveRule['server'], 'dns-local');
    },
  );

  test(
    'Test 5: route.rules does not contain resolve action when fakeip is disabled',
    () {
      final config = createBuilder(
        dnsFakeIpEnabled: false,
        useRussiaRouteData: true,
      ).build();

      final routeRules = (config['route']['rules'] as List)
          .cast<Map<String, dynamic>>();
      expect(routeRules.any((r) => r['action'] == 'resolve'), isFalse);
    },
  );

  test(
    'Test 6: experimental.cache_file contains store_fakeip only when fakeip is enabled',
    () {
      final enabledConfig = createBuilder(dnsFakeIpEnabled: true).build();
      final enabledCacheFile =
          enabledConfig['experimental']['cache_file'] as Map<String, dynamic>;
      expect(enabledCacheFile['enabled'], isTrue);
      expect(enabledCacheFile['store_rdrc'], isTrue);
      expect(enabledCacheFile['store_fakeip'], isTrue);

      final disabledConfig = createBuilder(dnsFakeIpEnabled: false).build();
      final disabledCacheFile =
          disabledConfig['experimental']['cache_file'] as Map<String, dynamic>;
      expect(disabledCacheFile['enabled'], isTrue);
      expect(disabledCacheFile['store_rdrc'], isTrue);
      expect(disabledCacheFile, isNot(contains('store_fakeip')));
    },
  );

  test(
    'Test 7: isolated fakeip without russiaRouteData or adBlock still generates dns.rules with dns-fakeip',
    () {
      final config = createBuilder(
        dnsFakeIpEnabled: true,
        useRussiaRouteData: false,
        adBlockEnabled: false,
      ).build();

      expect(config['dns'], contains('rules'));
      final dnsRules = (config['dns']['rules'] as List)
          .cast<Map<String, dynamic>>();
      expect(dnsRules, hasLength(1));
      expect(dnsRules.first['action'], 'route');
      expect(dnsRules.first['server'], 'dns-fakeip');
      expect(dnsRules.first['query_type'], ['A', 'AAAA']);
    },
  );
}
