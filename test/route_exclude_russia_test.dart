import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:hydrabox/singbox/singbox_config_builder.dart';

String _russiaRuleSetPath(String fileName) {
  return '${Directory.current.path}/assets/route_data/russia/$fileName';
}

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
      russiaGeositeRuBlockedPath: useRussiaRouteData
          ? _russiaRuleSetPath('geosite-ru-blocked.srs')
          : null,
      russiaGeositeRuAvailableOnlyInsidePath: useRussiaRouteData
          ? _russiaRuleSetPath('geosite-ru-available-only-inside.srs')
          : null,
      russiaGeositeCategoryRuPath: useRussiaRouteData
          ? _russiaRuleSetPath('geosite-category-ru.srs')
          : null,
      russiaGeoipRuBlockedPath: useRussiaRouteData
          ? _russiaRuleSetPath('geoip-ru-blocked.srs')
          : null,
      russiaGeoipRuWhitelistPath: useRussiaRouteData
          ? _russiaRuleSetPath('geoip-ru-whitelist.srs')
          : null,
      russiaGeoipRuPath: useRussiaRouteData
          ? _russiaRuleSetPath('geoip-ru.srs')
          : null,
      russiaCuratedDirectServicesPath: useRussiaRouteData
          ? _russiaRuleSetPath('geosite-ru-available-only-inside.srs')
          : null,
      russiaAiServicesPath: useRussiaRouteData
          ? _russiaRuleSetPath('geosite-ru-blocked.srs')
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
    'TUN inbound includes route_exclude_address_set when routeExcludeRussiaEnabled and useRussiaRouteData are both true',
    () {
      final config = createBuilder(
        routeExcludeRussiaEnabled: true,
        useRussiaRouteData: true,
      ).build();

      final inbounds = (config['inbounds'] as List)
          .cast<Map<String, dynamic>>();
      final tunInbound = inbounds.firstWhere((i) => i['type'] == 'tun');
      expect(tunInbound['route_exclude_address_set'], ['ru-geoip-ru']);
    },
  );

  test(
    'TUN inbound omits route_exclude_address_set when routeExcludeRussiaEnabled is false',
    () {
      final config = createBuilder(
        routeExcludeRussiaEnabled: false,
        useRussiaRouteData: true,
      ).build();

      final inbounds = (config['inbounds'] as List)
          .cast<Map<String, dynamic>>();
      final tunInbound = inbounds.firstWhere((i) => i['type'] == 'tun');
      expect(tunInbound.containsKey('route_exclude_address_set'), isFalse);
    },
  );

  test(
    'TUN inbound omits route_exclude_address_set when useRussiaRouteData is false even if routeExcludeRussiaEnabled is true',
    () {
      final config = createBuilder(
        routeExcludeRussiaEnabled: true,
        useRussiaRouteData: false,
      ).build();

      final inbounds = (config['inbounds'] as List)
          .cast<Map<String, dynamic>>();
      final tunInbound = inbounds.firstWhere((i) => i['type'] == 'tun');
      expect(tunInbound.containsKey('route_exclude_address_set'), isFalse);
    },
  );

  test('AppSettingsStore maps and exports routeExcludeRussiaEnabled', () {
    final store = _TestSettingsStore();
    final defaultMap = <String, String>{'route_exclude_russia_enabled': '1'};
    final state = store.mapState(defaultMap);
    expect(state.routeExcludeRussiaEnabled, isTrue);

    final exportedMap = store.stateToMap(state);
    expect(exportedMap['route_exclude_russia_enabled'], '1');
    expect(
      AppSettingsStore.safeExportKeys.contains('route_exclude_russia_enabled'),
      isTrue,
    );

    final disabledMap = <String, String>{'route_exclude_russia_enabled': '0'};
    final disabledState = store.mapState(disabledMap);
    expect(disabledState.routeExcludeRussiaEnabled, isFalse);
  });
}

final class _TestSettingsStore extends AppSettingsStore {
  @override
  Future<void> close() async {}

  @override
  Future<AppSettingsState> loadState() async => mapState(const {});

  @override
  Future<void> saveState(AppSettingsState state) async {}
}
