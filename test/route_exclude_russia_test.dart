import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/domain/models/subscription.dart';
import 'package:hydrabox/singbox/singbox_config_builder.dart';

void main() {
  const sampleSubscription = Subscription(
    id: 'sub-exclude-test',
    name: 'Exclude RU Test Sub',
    url: 'https://example.com/sub',
    outbounds: [],
  );

  SingboxConfigBuilder createBuilder({
    required bool routeExcludeRussiaEnabled,
    required bool useRussiaRouteData,
  }) {
    return SingboxConfigBuilder(
      activeSubscription: sampleSubscription,
      selectedProxyTag: 'proxy-1',
      cacheId: 'sub-exclude-test',
      vpnInboundEnabled: true,
      vpnMtu: 9000,
      vpnStrictRoute: true,
      vpnTunImplementation: TunImplementationPreference.mixed,
      proxyInboundEnabled: false,
      proxyMixedListen: '127.0.0.1',
      proxyMixedPort: 1080,
      dnsDirectResolver: 'udp://1.1.1.1',
      dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
      dnsPreferIpv6: false,
      dnsFakeIpEnabled: false,
      russiaDnsDirectResolver: defaultRussiaDnsDirectResolver,
      urlTestUrl: defaultUrlTestUrl,
      urlTestIntervalSeconds: 1800,
      urlTestTimeoutSeconds: 15,
      urlTestConcurrency: 8,
      urlTestUnavailableCheckIntervalSeconds: 120,
      blockLeaks: false,
      adBlockEnabled: false,
      useRussiaRouteData: useRussiaRouteData,
      routeExcludeRussiaEnabled: routeExcludeRussiaEnabled,
      russiaGeositeRuBlockedPath:
          useRussiaRouteData ? '/tmp/geosite-ru-blocked.srs' : null,
      russiaGeositeRuAvailableOnlyInsidePath:
          useRussiaRouteData ? '/tmp/geosite-ru-available-only-inside.srs' : null,
      russiaGeositeCategoryRuPath:
          useRussiaRouteData ? '/tmp/geosite-category-ru.srs' : null,
      russiaGeoipRuBlockedPath:
          useRussiaRouteData ? '/tmp/geoip-ru-blocked.srs' : null,
      russiaGeoipRuWhitelistPath:
          useRussiaRouteData ? '/tmp/geoip-ru-whitelist.srs' : null,
      russiaGeoipRuPath: useRussiaRouteData ? '/tmp/geoip-ru.srs' : null,
      russiaCuratedDirectServicesPath:
          useRussiaRouteData ? '/tmp/geosite-ru-available-only-inside.srs' : null,
      russiaAiServicesPath:
          useRussiaRouteData ? '/tmp/geosite-ru-blocked.srs' : null,
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

  test('TUN inbound includes route_exclude_address_set when routeExcludeRussiaEnabled and useRussiaRouteData are both true', () {
    final config = createBuilder(
      routeExcludeRussiaEnabled: true,
      useRussiaRouteData: true,
    ).build();

    final inbounds = (config['inbounds'] as List).cast<Map<String, dynamic>>();
    final tunInbound = inbounds.firstWhere((i) => i['type'] == 'tun');
    expect(tunInbound['route_exclude_address_set'], ['ru-geoip-ru']);
  });

  test('TUN inbound omits route_exclude_address_set when routeExcludeRussiaEnabled is false', () {
    final config = createBuilder(
      routeExcludeRussiaEnabled: false,
      useRussiaRouteData: true,
    ).build();

    final inbounds = (config['inbounds'] as List).cast<Map<String, dynamic>>();
    final tunInbound = inbounds.firstWhere((i) => i['type'] == 'tun');
    expect(tunInbound.containsKey('route_exclude_address_set'), isFalse);
  });

  test('TUN inbound omits route_exclude_address_set when useRussiaRouteData is false even if routeExcludeRussiaEnabled is true', () {
    final config = createBuilder(
      routeExcludeRussiaEnabled: true,
      useRussiaRouteData: false,
    ).build();

    final inbounds = (config['inbounds'] as List).cast<Map<String, dynamic>>();
    final tunInbound = inbounds.firstWhere((i) => i['type'] == 'tun');
    expect(tunInbound.containsKey('route_exclude_address_set'), isFalse);
  });

  test('AppSettingsStore maps and exports routeExcludeRussiaEnabled', () {
    final defaultMap = <String, String>{
      'route_exclude_russia_enabled': '1',
    };
    final state = AppSettingsStore.mapToState(defaultMap);
    expect(state.routeExcludeRussiaEnabled, isTrue);

    final exportedMap = AppSettingsStore.stateToMap(state);
    expect(exportedMap['route_exclude_russia_enabled'], '1');
    expect(AppSettingsStore.safeExportKeys.contains('route_exclude_russia_enabled'), isTrue);

    final disabledMap = <String, String>{
      'route_exclude_russia_enabled': '0',
    };
    final disabledState = AppSettingsStore.mapToState(disabledMap);
    expect(disabledState.routeExcludeRussiaEnabled, isFalse);
  });
}
