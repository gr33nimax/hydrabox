import 'dart:io';
import 'dart:math';

import 'package:hydrabox/core/lowest_proxy_groups.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/data/subscription/hydra_subscription_time.dart';
import 'package:hydrabox/data/subscription/parsers/hydra_subscription_parser.dart';
import 'package:hydrabox/data/subscription/parsers/singbox_config_parser.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:hydrabox/singbox/hydra_proxy_chain_resolver.dart';
import 'package:hydrabox/singbox/hydracore_capabilities.dart';

class SingboxConfigBuilder {
  static const List<String> _russiaDirectDomainSuffixes = ['ru', 'su', 'рф'];
  static const String _snowtunProtectPath =
      '@io.hydrabox.client.snowtun.protect';
  static const int _maxHydraBoxWireGuardWorkers = 64;
  static const int _maxHydraBoxWireGuardBuffersPerPool = 4096;
  static const int _maxHydraBoxAmneziaJunkPacketCount = 128;
  static const int _maxHydraBoxAmneziaPacketPaddingBytes = 65535;
  static const int _maxHydraBoxAmneziaHandshakeJunkBytes = 4 * 1024 * 1024;
  static const Set<String> _nonServerOutboundTypes = {
    'direct',
    'block',
    'dns',
    'selector',
    'urltest',
    'fallback',
    'failover',
    'bond',
    'bandwidth-limiter',
    'connection-limiter',
    'traffic-limiter',
    'rate-limiter',
    'parser',
    'tor',
    'masque',
    'openvpn',
    'wireguard',
  };

  static const Set<String> _removedCoreOutboundTypes = {
    'dns',
    'shadowsocksr',
    'wireguard',
  };

  static const Set<String> _removedCoreInboundTypes = {'shadowsocksr'};

  static const Set<String> _dialOverrideOutboundTypes = {
    'socks',
    'http',
    'shadowsocks',
    'vmess',
    'trojan',
    'naive',
    'hysteria',
    'hysteria2',
    'tuic',
    'anytls',
    'vless',
    'mieru',
    'ssh',
    'shadowtls',
    'masque',
    'openvpn',
    'trusttunnel',
    'sudoku',
    'snell',
  };

  const SingboxConfigBuilder({
    required this.activeSubscription,
    required this.selectedProxyTag,
    this.excludedOutboundTags = const <String>{},
    required this.vpnInboundEnabled,
    required this.vpnMtu,
    required this.vpnStrictRoute,
    required this.vpnTunImplementation,
    required this.proxyInboundEnabled,
    required this.proxyMixedListen,
    required this.proxyMixedPort,
    this.proxyUsername = defaultProxyUsername,
    this.proxyPassword = '',
    required this.dnsDirectResolver,
    required this.dnsProxyResolver,
    required this.dnsPreferIpv6,
    this.dnsFakeIpEnabled = false,
    this.russiaDnsDirectResolver = defaultRussiaDnsDirectResolver,
    required this.urlTestUrl,
    required this.urlTestIntervalSeconds,
    required this.urlTestTimeoutSeconds,
    required this.urlTestConcurrency,
    required this.urlTestUnavailableCheckIntervalSeconds,
    required this.blockLeaks,
    required this.adBlockEnabled,
    this.adBlockBlockRuleSetPath,
    this.adBlockAllowRuleSetPath,
    required this.useRussiaRouteData,
    this.russiaGeositeRuBlockedPath,
    this.russiaGeositeRuAvailableOnlyInsidePath,
    this.russiaGeositeCategoryRuPath,
    this.russiaGeoipRuBlockedPath,
    this.russiaGeoipRuWhitelistPath,
    this.russiaGeoipRuPath,
    this.russiaCuratedDirectServicesPath,
    this.russiaAiServicesPath,
    required this.bypassLocalNetwork,
    required this.splitRoutingMode,
    required this.splitRoutingPackages,
    required this.logLevel,
    required this.tcpFastOpenEnabled,
    required this.tcpMultiPathEnabled,
    required this.tlsFragmentationMode,
    required this.interruptExistingConnections,
    required this.urlTestStrictTolerance,
    required this.markAllServersRussia,
    this.capabilities = HydraCoreCapabilities.requiredV2,
    this.snowtunBinaryPath,
    this.snowtunProtectPath,
    this.cacheId = '',
  });

  final Subscription? activeSubscription;
  final String selectedProxyTag;
  final Set<String> excludedOutboundTags;
  final bool vpnInboundEnabled;
  final int vpnMtu;
  final bool vpnStrictRoute;
  final TunImplementationPreference vpnTunImplementation;
  final bool proxyInboundEnabled;
  final String proxyMixedListen;
  final int proxyMixedPort;
  final String proxyUsername;
  final String proxyPassword;
  final String dnsDirectResolver;
  final String dnsProxyResolver;
  final bool dnsPreferIpv6;
  final bool dnsFakeIpEnabled;
  final String russiaDnsDirectResolver;
  final String urlTestUrl;
  final int urlTestIntervalSeconds;
  final int urlTestTimeoutSeconds;
  final int urlTestConcurrency;
  final int urlTestUnavailableCheckIntervalSeconds;
  final bool blockLeaks;
  final bool adBlockEnabled;
  final String? adBlockBlockRuleSetPath;
  final String? adBlockAllowRuleSetPath;
  final bool useRussiaRouteData;
  final String? russiaGeositeRuBlockedPath;
  final String? russiaGeositeRuAvailableOnlyInsidePath;
  final String? russiaGeositeCategoryRuPath;
  final String? russiaGeoipRuBlockedPath;
  final String? russiaGeoipRuWhitelistPath;
  final String? russiaGeoipRuPath;
  final String? russiaCuratedDirectServicesPath;
  final String? russiaAiServicesPath;
  final bool bypassLocalNetwork;
  final SplitRoutingMode splitRoutingMode;
  final List<String> splitRoutingPackages;
  final String logLevel;
  final bool tcpFastOpenEnabled;
  final bool tcpMultiPathEnabled;
  final TlsFragmentationMode tlsFragmentationMode;
  final bool interruptExistingConnections;
  final bool urlTestStrictTolerance;
  final bool markAllServersRussia;
  final HydraCoreCapabilities capabilities;
  final String? snowtunBinaryPath;
  final String? snowtunProtectPath;
  final String cacheId;

  Map<String, dynamic> build() {
    return buildPlan().config;
  }

  SingboxBuildPlan buildPlan() {
    if (proxyInboundEnabled &&
        (!isValidProxyUsername(proxyUsername) ||
            !isValidProxyPassword(proxyPassword))) {
      throw StateError('Local proxy requires valid access credentials');
    }
    final strictHydraBox = HydraSubscriptionParser.isSupportedSourceFormat(
      activeSubscription?.sourceMetadata['format'],
    );
    if (strictHydraBox) {
      if (activeSubscription?.sourceMetadata['trust_blocked'] == true) {
        throw StateError(
          'HydraBox activation is blocked because its durable publisher trust '
          'tuple conflicts with another stored subscription',
        );
      }
      try {
        HydraSubscriptionTimePolicy.validate(
          activeSubscription!.sourceMetadata,
        );
      } on FormatException catch (error) {
        throw StateError('HydraBox activation is blocked: ${error.message}');
      }
      _validateHydraBoxProjectionTagIdentity();
      _validateHydraBoxRemoteSafetyManifest();
    }
    final outbounds = _visibleOutbounds();
    final coreTagRemapping = _coreTagRemapping();
    if (strictHydraBox && coreTagRemapping.isNotEmpty) {
      throw StateError(
        'HydraBox native runtime tags must remain stable; refusing unsafe '
        'opaque-reference remapping',
      );
    }
    final endpointOutbounds = outbounds
        .where(_isEndpointBacked)
        .toList(growable: false);
    final regularOutbounds = outbounds
        .where((outbound) => !_isEndpointBacked(outbound))
        .toList(growable: false);
    final outboundTags = outbounds
        .map((outbound) => outbound.tag)
        .toList(growable: false);
    final groupOnlyOutboundTags = outbounds
        .where(_isGroupOnlyOutbound)
        .map((outbound) => outbound.tag)
        .toSet();
    final selectableOutboundTags = outbounds
        .where((outbound) => !groupOnlyOutboundTags.contains(outbound.tag))
        .map((outbound) => outbound.tag)
        .toList(growable: false);
    final visibleGroups = _visibleGroups(outboundTags.toSet());
    final russiaRouteDataActive =
        useRussiaRouteData &&
        _validRuleSetPath(russiaGeositeRuBlockedPath) &&
        _validRuleSetPath(russiaGeositeRuAvailableOnlyInsidePath) &&
        _validRuleSetPath(russiaGeositeCategoryRuPath) &&
        _validRuleSetPath(russiaGeoipRuBlockedPath) &&
        _validRuleSetPath(russiaGeoipRuWhitelistPath) &&
        _validRuleSetPath(russiaGeoipRuPath);
    final russiaCuratedDirectServicesActive =
        useRussiaRouteData &&
        _validRuleSetPath(russiaCuratedDirectServicesPath);
    final defaultLowestOutboundTags = _lowestOutboundTagsFor(
      lowestProxyTag,
      outbounds,
      visibleGroups,
    );
    final urlTestAvailable =
        selectableOutboundTags.length > 1 ||
        visibleGroups.any(_isSetbackUrlTestGroup);
    final lowestOutboundTags =
        urlTestAvailable && defaultLowestOutboundTags.isNotEmpty
        ? <String, List<String>>{lowestProxyTag: defaultLowestOutboundTags}
        : <String, List<String>>{};
    final availableLowestTags = lowestProxyTags
        .where(lowestOutboundTags.containsKey)
        .toList(growable: false);
    final groupTags = visibleGroups
        .map((group) => group.tag)
        .toList(growable: false);
    final chainBuild = _visibleProxyChainOutbounds(
      visibleOutbounds: outbounds,
      selectableBaseTags: <String>{
        ...availableLowestTags,
        ...groupTags,
        ...selectableOutboundTags,
      },
      tagRemapping: coreTagRemapping,
    );
    final chainOutbounds = chainBuild.outbounds;
    final chainTags = chainOutbounds
        .map((outbound) => outbound['tag']?.toString() ?? '')
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    final selectableTags = <String>[
      ...availableLowestTags,
      ...groupTags,
      ...chainTags,
      ...selectableOutboundTags,
    ];
    final hasProxies = selectableTags.isNotEmpty;
    final normalizedSplitRoutingPackages = _normalizedSplitRoutingPackages();
    final tunSplitActive =
        vpnInboundEnabled &&
        splitRoutingMode != SplitRoutingMode.disabled &&
        normalizedSplitRoutingPackages.isNotEmpty;
    final tunIncludePackages =
        splitRoutingMode == SplitRoutingMode.proxySelected && tunSplitActive
        ? normalizedSplitRoutingPackages
        : const <String>[];
    final tunExcludePackages =
        splitRoutingMode == SplitRoutingMode.bypassSelected && tunSplitActive
        ? normalizedSplitRoutingPackages
        : const <String>[];
    final adBlockActive =
        adBlockEnabled && _validRuleSetPath(adBlockBlockRuleSetPath);
    final adBlockAllowActive =
        adBlockActive && _validRuleSetPath(adBlockAllowRuleSetPath);
    final normalizedSelectedProxyTag = normalizeProxySelectionTag(
      _nativeSelectionTag(selectedProxyTag),
    );
    final selectorDefault = hasProxies
        ? (normalizedSelectedProxyTag.isNotEmpty &&
                  selectableTags.contains(normalizedSelectedProxyTag)
              ? normalizedSelectedProxyTag
              : availableLowestTags.isNotEmpty
              ? lowestProxyTag
              : selectableTags.first)
        : 'direct';
    final routeFinal = hasProxies ? 'select' : 'direct';
    final dnsFinal = hasProxies ? 'dns-remote' : 'dns-direct';
    final dnsRemoteDetour = hasProxies
        ? _dnsRemoteDetourFor(
            selectorDefault,
            selectableTags.toSet(),
            chainBuild.nativeDetoursByChainTag,
          )
        : 'direct';

    final generatedConfig = <String, dynamic>{
      'log': {'level': logLevel},
      'dns': {
        'servers': [
          _buildDnsServer(
            tag: 'dns-remote',
            value: dnsProxyResolver,
            detour: dnsRemoteDetour,
          ),
          _buildDnsServer(
            tag: 'dns-direct',
            value: dnsDirectResolver,
            detour: 'direct',
          ),
          if (russiaRouteDataActive)
            _buildDnsServer(
              tag: 'dns-ru-direct',
              value: _normalizedResolver(
                russiaDnsDirectResolver,
                defaultRussiaDnsDirectResolver,
              ),
              detour: 'direct',
            ),
          const <String, Object>{'type': 'local', 'tag': 'dns-local'},
          if (dnsFakeIpEnabled)
            <String, Object>{
              'type': 'fakeip',
              'tag': 'dns-fakeip',
              'inet4_range': '198.18.0.0/15',
              if (dnsPreferIpv6) 'inet6_range': 'fc00::/18',
            },
        ],
        if (russiaRouteDataActive ||
            russiaCuratedDirectServicesActive ||
            adBlockActive ||
            dnsFakeIpEnabled)
          'rules': [
            if (russiaRouteDataActive)
              {
                'rule_set': 'ru-geosite-ru-blocked',
                'action': 'route',
                'server': dnsFinal,
              },
            if (russiaRouteDataActive)
              {
                'domain_suffix': _russiaDirectDomainSuffixes,
                'action': 'route',
                'server': 'dns-ru-direct',
              },
            if (russiaCuratedDirectServicesActive)
              {
                'rule_set': 'ru-direct-services',
                'action': 'route',
                'server': russiaRouteDataActive
                    ? 'dns-ru-direct'
                    : 'dns-direct',
              },
            if (russiaRouteDataActive)
              {
                'rule_set': 'ru-geosite-ru-available-only-inside',
                'action': 'route',
                'server': 'dns-ru-direct',
              },
            if (russiaRouteDataActive)
              {
                'rule_set': 'ru-geosite-category-ru',
                'action': 'route',
                'server': 'dns-ru-direct',
              },
            if (adBlockAllowActive)
              {
                'rule_set': 'adblock-allow',
                'action': 'route',
                'server': dnsFinal,
              },
            if (adBlockActive)
              {
                'rule_set': 'adblock-block',
                'action': 'reject',
                'method': 'default',
              },
            if (dnsFakeIpEnabled)
              {
                'query_type': ['A', 'AAAA'],
                'action': 'route',
                'server': 'dns-fakeip',
              },
          ],
        'final': dnsFinal,
        'independent_cache': true,
        'cache_capacity': 4096,
        // Android applications issue AAAA queries independently. Leaving the
        // strategy unset (or merely preferring IPv4) still returns IPv6
        // answers, so a browser can select an unreachable IPv6 destination
        // through a proxy whose exit has no working IPv6 route. Default to a
        // fail-safe IPv4-only answer set; the existing preference switch opts
        // back into dual-stack operation with IPv6 first.
        'strategy': dnsPreferIpv6 ? 'prefer_ipv6' : 'ipv4_only',
      },
      'inbounds': [
        if (vpnInboundEnabled)
          {
            'type': 'tun',
            'tag': 'tun-in',
            'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
            'mtu': max(vpnMtu, 1280),
            'auto_route': true,
            'strict_route': vpnStrictRoute,
            'stack': vpnTunImplementation.name,
            'udp_timeout': '2m',
            if (tunIncludePackages.isNotEmpty)
              'include_package': tunIncludePackages,
            if (tunExcludePackages.isNotEmpty)
              'exclude_package': tunExcludePackages,
          },
        if (proxyInboundEnabled)
          {
            'type': 'mixed',
            'tag': 'mixed-in',
            'listen': proxyMixedListen,
            'listen_port': proxyMixedPort,
            'users': [
              {'username': proxyUsername, 'password': proxyPassword},
            ],
          },
      ],
      if (endpointOutbounds.isNotEmpty)
        'endpoints': endpointOutbounds
            .map((outbound) => _buildEndpoint(outbound, coreTagRemapping))
            .toList(),
      'outbounds': [
        if (hasProxies)
          {
            'type': 'selector',
            'tag': 'select',
            'outbounds': selectableTags,
            'default': selectorDefault,
            'interrupt_exist_connections': interruptExistingConnections,
          }
        else
          {
            'type': 'selector',
            'tag': 'select',
            'outbounds': ['direct'],
            'default': 'direct',
          },
        if (hasProxies)
          ...availableLowestTags.map(
            (tag) => _buildLowestOutbound(tag, lowestOutboundTags[tag]!),
          ),
        if (hasProxies)
          ...visibleGroups.map(
            (group) => _buildProxyGroupOutbound(group, outboundTags.toSet()),
          ),
        ...chainOutbounds,
        ...regularOutbounds.map(
          (outbound) => _buildProxyOutbound(outbound, coreTagRemapping),
        ),
        {
          'type': 'direct',
          'tag': 'direct',
          'tcp_fast_open': tcpFastOpenEnabled,
          'tcp_multi_path': tcpMultiPathEnabled,
        },
      ],
      'route': {
        'auto_detect_interface': true,
        // Proxy endpoint hostnames must be resolved before a proxy exists.
        // Using the user-selected direct resolver here makes startup depend
        // on public UDP/DoT reachability and can create a bootstrap failure.
        // Android's current network DNS is the reliable bootstrap resolver;
        // user DNS choices still handle routed application queries above.
        'default_domain_resolver': 'dns-local',
        if (russiaRouteDataActive ||
            russiaCuratedDirectServicesActive ||
            adBlockActive)
          'rule_set': [
            if (russiaCuratedDirectServicesActive)
              {
                'type': 'local',
                'tag': 'ru-direct-services',
                'format': 'binary',
                'path': russiaCuratedDirectServicesPath,
              },
            if (russiaRouteDataActive) ...[
              {
                'type': 'local',
                'tag': 'ru-geosite-ru-blocked',
                'format': 'binary',
                'path': russiaGeositeRuBlockedPath,
              },
              {
                'type': 'local',
                'tag': 'ru-geosite-ru-available-only-inside',
                'format': 'binary',
                'path': russiaGeositeRuAvailableOnlyInsidePath,
              },
              {
                'type': 'local',
                'tag': 'ru-geosite-category-ru',
                'format': 'binary',
                'path': russiaGeositeCategoryRuPath,
              },
              {
                'type': 'local',
                'tag': 'ru-geoip-ru-blocked',
                'format': 'binary',
                'path': russiaGeoipRuBlockedPath,
              },
              {
                'type': 'local',
                'tag': 'ru-geoip-ru-whitelist',
                'format': 'binary',
                'path': russiaGeoipRuWhitelistPath,
              },
              {
                'type': 'local',
                'tag': 'ru-geoip-ru',
                'format': 'binary',
                'path': russiaGeoipRuPath,
              },
            ],
            if (adBlockAllowActive)
              {
                'type': 'local',
                'tag': 'adblock-allow',
                'path': adBlockAllowRuleSetPath,
              },
            if (adBlockActive)
              {
                'type': 'local',
                'tag': 'adblock-block',
                'path': adBlockBlockRuleSetPath,
              },
          ],
        'rules': [
          {'action': 'sniff'},
          {
            'type': 'logical',
            'mode': 'or',
            'rules': [
              {'protocol': 'dns'},
              {'port': 53},
            ],
            'action': 'hijack-dns',
          },
          if (vpnInboundEnabled)
            {
              'inbound': 'tun-in',
              'network': 'icmp',
              'ip_cidr': '172.19.0.2/32',
              'action': 'reject',
              'method': 'drop',
            },
          if (blockLeaks) {'protocol': 'stun', 'action': 'reject'},
          if (bypassLocalNetwork) {'ip_is_private': true, 'outbound': 'direct'},
          if (adBlockAllowActive)
            {'rule_set': 'adblock-allow', 'outbound': routeFinal},
          if (adBlockActive) {'rule_set': 'adblock-block', 'action': 'reject'},
          if (russiaRouteDataActive)
            {
              'rule_set': ['ru-geosite-ru-blocked', 'ru-geoip-ru-blocked'],
              'outbound': hasProxies ? 'select' : 'direct',
            },
          if (russiaRouteDataActive)
            {
              'domain_suffix': _russiaDirectDomainSuffixes,
              'outbound': 'direct',
            },
          if (russiaRouteDataActive)
            {
              'rule_set': 'ru-geosite-ru-available-only-inside',
              'outbound': 'direct',
            },
          if (russiaRouteDataActive)
            {'rule_set': 'ru-geosite-category-ru', 'outbound': 'direct'},
          if (russiaCuratedDirectServicesActive)
            {'rule_set': 'ru-direct-services', 'outbound': 'direct'},
          if (dnsFakeIpEnabled && russiaRouteDataActive)
            {'action': 'resolve', 'server': 'dns-local'},
          if (russiaRouteDataActive)
            {
              'rule_set': ['ru-geoip-ru-whitelist', 'ru-geoip-ru'],
              'outbound': 'direct',
            },
        ],
        'final': routeFinal,
      },
      'experimental': {
        'cache_file': {
          'enabled': true,
          'store_rdrc': true,
          if (dnsFakeIpEnabled) 'store_fakeip': true,
          if (cacheId.isNotEmpty) 'cache_id': cacheId,
        },
      },
    };
    final rawCoreConfig = _readRawSingboxConfig();
    final mergedConfig = _mergeRawCoreConfig(generatedConfig, rawCoreConfig);
    final regularOutboundTags = regularOutbounds
        .map((outbound) => outbound.tag)
        .toSet();
    final proxyOutboundIndexes = <int, String>{};
    final mergedOutbounds = _asObjectList(mergedConfig['outbounds']);
    for (var i = 0; i < mergedOutbounds.length; i++) {
      final tag = mergedOutbounds[i]['tag']?.toString() ?? '';
      if (regularOutboundTags.contains(tag)) {
        proxyOutboundIndexes[i] = tag;
      }
    }
    return SingboxBuildPlan(
      config: mergedConfig,
      proxyOutboundTagsByIndex: proxyOutboundIndexes,
      visibleProxyOutboundCount: selectableOutboundTags.length,
      hasRawCoreConfig: rawCoreConfig != null,
      allowsZeroSelectableEntries:
          rawCoreConfig != null &&
          !_rawDocumentHasSelectableEntries(rawCoreConfig),
    );
  }

  /// Reconciles the app-managed runtime sections with a complete sing-box
  /// document supplied by a user/subscription.
  ///
  /// The generated config still owns the Android TUN/proxy inbounds, selector,
  /// routing safety rules and normalized proxy entries. Protocol objects and
  /// safe opaque sections remain lossless so HydraCore can add protocol types
  /// without requiring a matching Flutter release. Remote HydraBox documents
  /// cannot inject listeners, services, or experimental controllers until a
  /// separate local consent boundary exists.
  Map<String, dynamic> _mergeRawCoreConfig(
    Map<String, dynamic> generated,
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) {
      return generated;
    }

    final strictHydraBox = HydraSubscriptionParser.isSupportedSourceFormat(
      activeSubscription?.sourceMetadata['format'],
    );
    final merged = _cloneJsonMap(raw);
    if (strictHydraBox) {
      merged.remove('services');
      merged.remove('experimental');
    }

    // Generated scalar sections are authoritative for app-owned settings,
    // while unknown top-level sections remain from the source document.
    for (final entry in generated.entries) {
      if (entry.key == 'dns' ||
          entry.key == 'route' ||
          entry.key == 'endpoints' ||
          entry.key == 'inbounds' ||
          entry.key == 'outbounds') {
        continue;
      }
      if (strictHydraBox &&
          (entry.key == 'log' || entry.key == 'global') &&
          raw[entry.key] is Map &&
          entry.value is Map) {
        merged[entry.key] = _mergeConfigMap(
          raw[entry.key],
          entry.value,
          listKeys: const <String>{},
        );
      } else {
        merged[entry.key] = _cloneJsonValue(entry.value);
      }
    }

    merged['dns'] = _mergeConfigMap(
      raw['dns'],
      generated['dns'],
      listKeys: const {'servers', 'rules', 'rule_set'},
      generatedFirst: strictHydraBox,
    );
    merged['route'] = _mergeConfigMap(
      raw['route'],
      generated['route'],
      listKeys: const {'rules', 'rule_set'},
      generatedFirst: strictHydraBox,
    );

    if (strictHydraBox) {
      return _mergeStrictHydraBoxNativeSections(
        merged: merged,
        raw: raw,
        generated: generated,
      );
    }

    final managedEndpointIndexes = _managedRawSourceIndexes('endpoints');
    final managedEndpointTags = _managedRawSourceTags('endpoints');
    final generatedEndpoints = _asObjectList(generated['endpoints']);
    final generatedEndpointTags = generatedEndpoints
        .map((entry) => entry['tag']?.toString())
        .whereType<String>()
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final rawEndpoints = _withoutManagedCoreEntries(
      raw['endpoints'],
      const <String>{},
      replacedIndexes: managedEndpointIndexes,
      replacedTags: managedEndpointTags,
    );
    merged['endpoints'] = _mergeTaggedObjectLists(
      rawEndpoints,
      generatedEndpoints,
      replaceTags: {...generatedEndpointTags, ...managedEndpointTags},
    );

    final rawInbounds = strictHydraBox
        ? const <Map<String, dynamic>>[]
        : _withoutManagedCoreEntries(raw['inbounds'], _removedCoreInboundTypes);
    final generatedInbounds = _asObjectList(generated['inbounds']);
    final generatedInboundTags = generatedInbounds
        .map((entry) => entry['tag']?.toString())
        .whereType<String>()
        .where((tag) => tag.isNotEmpty)
        .toSet();
    merged['inbounds'] = _mergeTaggedObjectLists(
      rawInbounds,
      generatedInbounds,
      replaceTags: generatedInboundTags,
    );

    final managedOutboundIndexes = _managedRawSourceIndexes('outbounds');
    final managedOutboundTags = _managedRawSourceTags('outbounds');
    final rawOutbounds = _withoutManagedCoreEntries(
      raw['outbounds'],
      _removedCoreOutboundTypes,
      replacedIndexes: managedOutboundIndexes,
      replacedTags: managedOutboundTags,
    );
    final generatedOutbounds = _asObjectList(generated['outbounds']);
    final generatedOutboundTags = generatedOutbounds
        .map((entry) => entry['tag']?.toString())
        .whereType<String>()
        .where((tag) => tag.isNotEmpty)
        .toSet();
    merged['outbounds'] = _mergeTaggedObjectLists(
      rawOutbounds,
      generatedOutbounds,
      replaceTags: {...generatedOutboundTags, ...managedOutboundTags},
    );

    return merged;
  }

  /// Keeps HydraBox protocol objects raw-authoritative.
  ///
  /// The native document is the provider's graph and HydraCore owns its
  /// schema. Parsed outbound models are UI projections only; replacing native
  /// entries with those projections would make a future parser normalization
  /// capable of changing an otherwise opaque field. The app therefore adds
  /// only its own selector/direct/group/chain wrappers around the exact raw
  /// outbounds/endpoints. Any namespace collision is rejected instead of
  /// guessed or recursively rewritten.
  Map<String, dynamic> _mergeStrictHydraBoxNativeSections({
    required Map<String, dynamic> merged,
    required Map<String, dynamic> raw,
    required Map<String, dynamic> generated,
  }) {
    List<Map<String, dynamic>> strictRawEntries(dynamic value, String section) {
      if (value == null) return <Map<String, dynamic>>[];
      if (value is! List) {
        throw StateError('HydraBox native $section must remain an array');
      }
      final result = <Map<String, dynamic>>[];
      for (var index = 0; index < value.length; index++) {
        final rawEntry = value[index];
        if (rawEntry is! Map) {
          throw StateError(
            'HydraBox native $section[$index] must remain an object',
          );
        }
        final entry = _cloneJsonMap(rawEntry);
        final type = entry['type'];
        final tag = entry['tag'];
        if (type is! String ||
            type.isEmpty ||
            type != type.trim() ||
            type.contains(RegExp(r'[\x00-\x1F\x7F]')) ||
            tag is! String ||
            tag.isEmpty ||
            tag != tag.trim() ||
            tag.length > 512 ||
            tag.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
          throw StateError(
            'HydraBox native $section[$index] identity is corrupt',
          );
        }
        result.add(entry);
      }
      return result;
    }

    final rawInbounds = strictRawEntries(raw['inbounds'], 'inbounds');
    final rawOutbounds = strictRawEntries(raw['outbounds'], 'outbounds');
    final rawEndpoints = strictRawEntries(raw['endpoints'], 'endpoints');
    final rawOutboundTagValues = rawOutbounds
        .map((entry) => entry['tag']?.toString() ?? '')
        .toList(growable: false);
    final rawEndpointTagValues = rawEndpoints
        .map((entry) => entry['tag']?.toString() ?? '')
        .toList(growable: false);
    final rawOutboundTags = rawOutboundTagValues.toSet();
    final rawEndpointTags = rawEndpointTagValues.toSet();
    final rawTags = <String>{};
    for (final tag in <String>[
      ...rawInbounds.map((entry) => entry['tag']?.toString() ?? ''),
      ...rawOutboundTagValues,
      ...rawEndpointTagValues,
    ]) {
      if (tag.isEmpty ||
          tag.startsWith('__hydrabox.') ||
          isReservedProxyTag(tag) ||
          !rawTags.add(tag)) {
        throw StateError(
          'HydraBox native runtime tag namespace is invalid or collides with '
          'a client-owned tag',
        );
      }
    }

    final managedOutboundTags = _managedRawSourceTags('outbounds');
    final managedEndpointTags = _managedRawSourceTags('endpoints');
    if (!rawOutboundTags.containsAll(managedOutboundTags) ||
        !rawEndpointTags.containsAll(managedEndpointTags)) {
      throw StateError(
        'HydraBox persisted native projections no longer match the raw '
        'runtime document',
      );
    }

    List<Map<String, dynamic>> appOwnedEntries(
      dynamic generatedValue,
      Set<String> managedTags,
    ) {
      final result = <Map<String, dynamic>>[];
      final projectionCounts = <String, int>{};
      for (final entry in _asObjectList(generatedValue)) {
        final tag = entry['tag']?.toString() ?? '';
        if (managedTags.contains(tag)) {
          projectionCounts[tag] = (projectionCounts[tag] ?? 0) + 1;
          continue;
        }
        if (tag.isEmpty || rawTags.contains(tag)) {
          throw StateError(
            'HydraBox app-owned runtime entry collides with an opaque native '
            'tag',
          );
        }
        result.add(entry);
      }
      if (projectionCounts.values.any((count) => count > 1)) {
        throw StateError('HydraBox native runtime projection is ambiguous');
      }
      return result;
    }

    final appEndpoints = appOwnedEntries(
      generated['endpoints'],
      managedEndpointTags,
    );
    final appOutbounds = appOwnedEntries(
      generated['outbounds'],
      managedOutboundTags,
    );
    final appInbounds = appOwnedEntries(
      generated['inbounds'],
      const <String>{},
    );
    final assembledTags = <String>{...rawTags};
    for (final entry in <Map<String, dynamic>>[
      ...appInbounds,
      ...appEndpoints,
      ...appOutbounds,
    ]) {
      final tag = entry['tag']?.toString() ?? '';
      if (!assembledTags.add(tag)) {
        throw StateError('HydraBox assembled runtime tag "$tag" is duplicate');
      }
    }

    merged['endpoints'] = <Map<String, dynamic>>[
      ...rawEndpoints.map(_cloneJsonMap),
      ...appEndpoints.map(_cloneJsonMap),
    ];
    merged['inbounds'] = <Map<String, dynamic>>[
      ...rawInbounds.map(_cloneJsonMap),
      ...appInbounds.map(_cloneJsonMap),
    ];
    merged['outbounds'] = <Map<String, dynamic>>[
      ...rawOutbounds.map(_cloneJsonMap),
      ...appOutbounds.map(_cloneJsonMap),
    ];
    return merged;
  }

  Map<String, dynamic>? _readRawSingboxConfig() {
    final strictHydraBox = HydraSubscriptionParser.isSupportedSourceFormat(
      activeSubscription?.sourceMetadata['format'],
    );
    try {
      final embedded = activeSubscription?.activeNativeConfig;
      if (strictHydraBox && embedded == null) {
        throw StateError(
          'HydraBox native runtime payload is not hydrated; refusing a '
          'generated-only fallback',
        );
      }
      final decoded = embedded == null
          ? _decodeRawSubscriptionConfig()
          : _cloneJsonMap(embedded);
      if (decoded == null) {
        return null;
      }
      final config = _cloneJsonMap(decoded);
      final tagRemapping = _coreTagRemapping();
      if (tagRemapping.isNotEmpty) {
        if (strictHydraBox) {
          throw StateError('HydraBox native runtime tags cannot be remapped');
        }
        _remapRawCoreTags(config, tagRemapping);
      }
      if (!strictHydraBox && !_hasTypedCoreSection(config)) {
        return null;
      }
      return config;
    } on FormatException {
      if (strictHydraBox) rethrow;
      return null;
    } on TypeError {
      if (strictHydraBox) rethrow;
      return null;
    }
  }

  /// Converts the app-owned profile identity to the entrypoint tag inside the
  /// one isolated native resource selected by that profile.
  String _nativeSelectionTag(String appSelectionTag) {
    final subscription = activeSubscription;
    if (subscription == null || subscription.resourceConfigs.isEmpty) {
      return appSelectionTag;
    }
    if (isLowestProxyTag(appSelectionTag)) {
      final activeProfile = HydraProxyChainResolver.activeProfile(subscription);
      final entrypoint = activeProfile?.entrypointTag.trim() ?? '';
      if (entrypoint.isNotEmpty) {
        return entrypoint;
      }
    }
    return subscription.nativeEntrypointTagForRuntimeTag(appSelectionTag);
  }

  Map<String, dynamic>? _decodeRawSubscriptionConfig() {
    final rawContent = activeSubscription?.rawContent.trim() ?? '';
    if (rawContent.isEmpty ||
        !(rawContent.startsWith('{') || rawContent.startsWith('['))) {
      return null;
    }
    return SingboxConfigParser.decodeDocument(rawContent);
  }

  Map<String, String> _coreTagRemapping() {
    final candidates = <String, Set<String>>{};
    for (final outbound in _activeResourceOutbounds()) {
      final sourceSection =
          outbound.config['_hydra_source_section']?.toString() ?? '';
      if (sourceSection != 'outbounds' && sourceSection != 'endpoints') {
        continue;
      }
      final original =
          outbound.config['_hydra_original_tag']?.toString().trim() ?? '';
      final current = outbound.tag.trim();
      if (original.isEmpty || current.isEmpty) {
        continue;
      }
      candidates.putIfAbsent(original, () => <String>{}).add(current);
    }
    return {
      for (final entry in candidates.entries)
        if (entry.value.length == 1 && entry.value.single != entry.key)
          entry.key: entry.value.single,
    };
  }

  void _validateHydraBoxProjectionTagIdentity() {
    final seen = <String>{};
    for (final outbound in _activeResourceOutbounds()) {
      final sourceSection =
          outbound.config['_hydra_source_index_section']?.toString() ??
          outbound.config['_hydra_source_section']?.toString() ??
          '';
      if (sourceSection != 'outbounds' && sourceSection != 'endpoints') {
        continue;
      }
      final original = outbound.config['_hydra_original_tag']?.toString() ?? '';
      final current = outbound.tag;
      final projectedConfigTag = outbound.config['tag']?.toString() ?? '';
      if (original.isEmpty ||
          original != original.trim() ||
          current.isEmpty ||
          current != original ||
          projectedConfigTag != original ||
          !seen.add('$sourceSection\u0000$original')) {
        throw StateError(
          'HydraBox persisted native projection changed tag identity',
        );
      }
    }
  }

  void _validateHydraBoxRemoteSafetyManifest() {
    final native = activeSubscription?.activeNativeConfig;
    if (native == null) {
      throw StateError(
        'HydraBox native runtime payload is not hydrated for remote-policy '
        'validation',
      );
    }
    if (!capabilities.hasVersionedContract ||
        capabilities.coreId != HydraCoreCapabilities.hydraCoreId ||
        !capabilities.supportsConfigCheck) {
      throw StateError(
        'HydraBox activation requires a versioned HydraCore capability '
        'contract with native config validation',
      );
    }
    if (!capabilities.hasRemoteSafetyManifest) {
      throw StateError(
        'The installed HydraCore does not publish a remote-safety manifest',
      );
    }

    for (final rawKey in native.keys) {
      final key = rawKey.toString();
      if (!capabilities.remoteSafeTopLevelFields.contains(key)) {
        throw StateError(
          'HydraCore remote policy ${capabilities.remotePolicyVersion} does '
          'not classify runtime.document.$key as remote-safe',
        );
      }
    }

    void validateTypedEntries(
      dynamic value, {
      required String field,
      required Set<String> safeTypes,
      String emptyType = '',
    }) {
      if (value == null) return;
      if (value is! List) {
        throw StateError('$field must be an array');
      }
      for (var index = 0; index < value.length; index++) {
        final entry = value[index];
        if (entry is! Map) {
          throw StateError('$field[$index] must be an object');
        }
        final rawType = entry['type'];
        final type = rawType == null
            ? emptyType
            : rawType.toString().trim().toLowerCase();
        if (type.isEmpty || !safeTypes.contains(type)) {
          throw StateError(
            '$field[$index] type "${type.isEmpty ? '<missing>' : type}" is '
            'not classified remote-safe by the installed HydraCore',
          );
        }
      }
    }

    if (capabilities.remotePolicyVersion != 2) {
      throw StateError(
        'Hydra Subscription v2 requires HydraCore remote policy v2',
      );
    }

    if (capabilities.remotePolicyVersion == 2) {
      const v2TopLevelFields = {
        r'$schema',
        'inbounds',
        'outbounds',
        'endpoints',
      };
      const v2EndpointTypes = {'wireguard'};
      for (final rawKey in native.keys) {
        final key = rawKey.toString();
        if (!v2TopLevelFields.contains(key)) {
          throw StateError(
            'runtime.document.$key is not part of Hydra remote policy v2',
          );
        }
      }
      validateTypedEntries(
        native['inbounds'],
        field: 'runtime.document.inbounds',
        safeTypes: const {'call'},
      );
      validateTypedEntries(
        native['outbounds'],
        field: 'runtime.document.outbounds',
        safeTypes: HydraSubscriptionParser.supportedOutboundTypes,
      );
      validateTypedEntries(
        native['endpoints'],
        field: 'runtime.document.endpoints',
        safeTypes: v2EndpointTypes,
      );
      _validateHydraWireGuardResourceLimits(native);
      _validateHydraReferenceGraph(native);
    }

    validateTypedEntries(
      native['inbounds'],
      field: 'runtime.document.inbounds',
      safeTypes: capabilities.remoteSafeInboundTypes,
    );
    validateTypedEntries(
      native['outbounds'],
      field: 'runtime.document.outbounds',
      safeTypes: capabilities.remoteSafeOutboundTypes,
    );
    validateTypedEntries(
      native['endpoints'],
      field: 'runtime.document.endpoints',
      safeTypes: capabilities.remoteSafeEndpointTypes,
    );
    validateTypedEntries(
      native['providers'],
      field: 'runtime.document.providers',
      safeTypes: capabilities.remoteSafeProviderTypes,
      emptyType: 'inline',
    );
    final route = native['route'];
    if (route is Map) {
      validateTypedEntries(
        route['rule_set'],
        field: 'runtime.document.route.rule_set',
        safeTypes: capabilities.remoteSafeProviderTypes,
        emptyType: 'inline',
      );
    }
    final dns = native['dns'];
    if (dns is Map) {
      validateTypedEntries(
        dns['servers'],
        field: 'runtime.document.dns.servers',
        safeTypes: capabilities.remoteSafeDnsServerTypes,
      );
    }
  }

  static void _validateHydraWireGuardResourceLimits(
    Map<String, dynamic> native,
  ) {
    final endpoints = native['endpoints'];
    if (endpoints == null) return;
    if (endpoints is! List) {
      throw StateError('runtime.document.endpoints must be an array');
    }

    int boundedInteger(
      Map endpoint,
      String key, {
      required String field,
      required int maximum,
    }) {
      final raw = endpoint[key];
      if (raw == null) return 0;
      if (raw is! int || raw < 0 || raw > maximum) {
        throw StateError('$field must be an integer between 0 and $maximum');
      }
      return raw;
    }

    for (var index = 0; index < endpoints.length; index++) {
      final rawEndpoint = endpoints[index];
      if (rawEndpoint is! Map ||
          rawEndpoint['type']?.toString().trim().toLowerCase() != 'wireguard') {
        continue;
      }
      final field = 'runtime.document.endpoints[$index]';
      boundedInteger(
        rawEndpoint,
        'workers',
        field: '$field.workers',
        maximum: _maxHydraBoxWireGuardWorkers,
      );
      boundedInteger(
        rawEndpoint,
        'preallocated_buffers_per_pool',
        field: '$field.preallocated_buffers_per_pool',
        maximum: _maxHydraBoxWireGuardBuffersPerPool,
      );

      final rawAmnezia = rawEndpoint['amnezia'];
      if (rawAmnezia == null) continue;
      if (rawAmnezia is! Map) {
        throw StateError('$field.amnezia must be an object');
      }
      final jc = boundedInteger(
        rawAmnezia,
        'jc',
        field: '$field.amnezia.jc',
        maximum: _maxHydraBoxAmneziaJunkPacketCount,
      );
      final jmin = boundedInteger(
        rawAmnezia,
        'jmin',
        field: '$field.amnezia.jmin',
        maximum: _maxHydraBoxAmneziaPacketPaddingBytes,
      );
      final jmax = boundedInteger(
        rawAmnezia,
        'jmax',
        field: '$field.amnezia.jmax',
        maximum: _maxHydraBoxAmneziaPacketPaddingBytes,
      );
      if (jmin > jmax) {
        throw StateError('$field.amnezia.jmin must not exceed jmax');
      }
      if (jc * jmax > _maxHydraBoxAmneziaHandshakeJunkBytes) {
        throw StateError(
          '$field.amnezia junk burst exceeds '
          '$_maxHydraBoxAmneziaHandshakeJunkBytes bytes',
        );
      }
      for (final key in const ['s1', 's2', 's3', 's4']) {
        boundedInteger(
          rawAmnezia,
          key,
          field: '$field.amnezia.$key',
          maximum: _maxHydraBoxAmneziaPacketPaddingBytes,
        );
      }
    }
  }

  static void _validateHydraReferenceGraph(Map<String, dynamic> native) {
    final entriesByTag = <String, Map<String, dynamic>>{};
    for (final section in const {'outbounds', 'endpoints'}) {
      final entries = native[section];
      if (entries == null) continue;
      if (entries is! List) {
        throw StateError('runtime.document.$section must be an array');
      }
      for (var index = 0; index < entries.length; index++) {
        final raw = entries[index];
        if (raw is! Map) {
          throw StateError(
            'runtime.document.$section[$index] must be an object',
          );
        }
        final entry = Map<String, dynamic>.from(raw);
        final tag = entry['tag'];
        if (tag is! String || tag.isEmpty || entriesByTag.containsKey(tag)) {
          throw StateError(
            'runtime.document.$section[$index] must have one unique exact tag',
          );
        }
        entriesByTag[tag] = entry;
      }
    }

    final edges = <String, Set<String>>{
      for (final tag in entriesByTag.keys) tag: <String>{},
    };
    const scalarReferenceKeys = {
      'detour',
      'download_detour',
      'upload_detour',
      'outbound',
      'endpoint',
    };
    const compositeReferenceKeys = {'outbounds', 'default'};

    void walk(dynamic value, String ownerTag, String field) {
      if (value is Map) {
        for (final rawEntry in value.entries) {
          final key = rawEntry.key.toString();
          final folded = key.toLowerCase();
          final child = rawEntry.value;
          if (folded == 'domain_resolver' && child != null) {
            throw StateError(
              '$field.$key is not available in this remote policy because DNS '
              'ownership remains local to HydraBox',
            );
          }
          if (scalarReferenceKeys.contains(folded)) {
            if (key != folded ||
                child is! String ||
                child.isEmpty ||
                !entriesByTag.containsKey(child)) {
              throw StateError(
                '$field.$key must reference an exact tag from the same remote '
                'outbounds/endpoints graph',
              );
            }
            edges[ownerTag]!.add(child);
          }
          if (compositeReferenceKeys.contains(folded) && child != null) {
            throw StateError(
              '$field.$key embeds an executable reference graph, which remote '
              'policy v1 classifies as non-leaf',
            );
          }
          walk(child, ownerTag, '$field.$key');
        }
      } else if (value is List) {
        for (var index = 0; index < value.length; index++) {
          walk(value[index], ownerTag, '$field[$index]');
        }
      }
    }

    for (final entry in entriesByTag.entries) {
      walk(entry.value, entry.key, 'runtime.document[${entry.key}]');
    }

    final visiting = <String>{};
    final visited = <String>{};
    bool visit(String tag) {
      if (visited.contains(tag)) return false;
      if (!visiting.add(tag)) return true;
      for (final target in edges[tag] ?? const <String>{}) {
        if (visit(target)) return true;
      }
      visiting.remove(tag);
      visited.add(tag);
      return false;
    }

    for (final tag in entriesByTag.keys) {
      if (visit(tag)) {
        throw StateError(
          'HydraBox remote policy rejects cyclic outbound/endpoint detours',
        );
      }
    }
  }

  static void _remapRawCoreTags(
    Map<String, dynamic> config,
    Map<String, String> remapping,
  ) {
    SingboxConfigParser.remapCoreOutboundTags(config, remapping);
  }

  static void _remapOutboundReferenceValues(
    dynamic value,
    Map<String, String> remapping,
  ) {
    _remapCoreReferenceValues(
      value,
      remapping,
      stringKeys: const {
        'outbound',
        'detour',
        'download_detour',
        'upload_detour',
        'endpoint',
        'default',
      },
      listKeys: const {'outbounds'},
    );
  }

  static bool _hasTypedCoreSection(Map<String, dynamic> config) {
    bool hasTypedEntry(dynamic value) {
      return value is List &&
          value.any(
            (entry) =>
                entry is Map &&
                (entry['type']?.toString().trim().isNotEmpty ?? false),
          );
    }

    for (final section in const {
      'outbounds',
      'endpoints',
      'inbounds',
      'providers',
      'services',
    }) {
      if (hasTypedEntry(config[section])) {
        return true;
      }
    }
    final dns = config['dns'];
    return dns is Map && hasTypedEntry(dns['servers']);
  }

  static bool _rawDocumentHasSelectableEntries(Map<String, dynamic> config) {
    const nonSelectableOutboundTypes = {
      'direct',
      'block',
      'dns',
      'selector',
      'urltest',
    };
    final outbounds = config['outbounds'];
    if (outbounds is List) {
      for (final entry in outbounds) {
        if (entry is! Map) continue;
        final type = entry['type']?.toString().trim().toLowerCase() ?? '';
        if ((type == 'selector' || type == 'urltest') &&
            _rawGroupUsesProviders(entry)) {
          return true;
        }
        if (type.isNotEmpty && !nonSelectableOutboundTypes.contains(type)) {
          return true;
        }
      }
    }
    final endpoints = config['endpoints'];
    return endpoints is List &&
        endpoints.any(
          (entry) =>
              entry is Map &&
              (entry['type']?.toString().trim().isNotEmpty ?? false),
        );
  }

  static bool _rawGroupUsesProviders(Map entry) {
    if (entry['use_all_providers'] == true) {
      return true;
    }
    final providers = entry['providers'];
    return (providers is String && providers.trim().isNotEmpty) ||
        (providers is List &&
            providers.any((value) => value.toString().trim().isNotEmpty));
  }

  Set<int> _managedRawSourceIndexes(String section) {
    final indexes = <int>{};
    for (final outbound in _activeResourceOutbounds()) {
      final sourceIndexSection =
          outbound.config['_hydra_source_index_section']?.toString() ??
          outbound.config['_hydra_source_section']?.toString() ??
          '';
      if (sourceIndexSection != section) {
        continue;
      }
      final value = outbound.config['_hydra_source_index'];
      final index = value is int
          ? value
          : int.tryParse(value?.toString() ?? '');
      if (index != null && index >= 0) {
        indexes.add(index);
      }
    }
    return indexes;
  }

  Set<String> _managedRawSourceTags(String section) {
    final tags = <String>{};
    for (final outbound in _activeResourceOutbounds()) {
      final sourceIndexSection =
          outbound.config['_hydra_source_index_section']?.toString() ??
          outbound.config['_hydra_source_section']?.toString() ??
          '';
      if (sourceIndexSection != section) {
        continue;
      }
      final original =
          outbound.config['_hydra_original_tag']?.toString().trim() ?? '';
      final current = outbound.tag.trim();
      if (original.isNotEmpty) {
        tags.add(original);
      }
      if (current.isNotEmpty) {
        tags.add(current);
      }
    }
    return tags;
  }

  static void _remapCoreReferenceValues(
    dynamic value,
    Map<String, String> remapping, {
    Set<String> stringKeys = const <String>{},
    Set<String> listKeys = const <String>{},
  }) {
    if (value is Map) {
      for (final keyValue in value.keys.toList(growable: false)) {
        final key = keyValue.toString();
        final child = value[keyValue];
        if (child is String && stringKeys.contains(key)) {
          value[keyValue] = remapping[child] ?? child;
          continue;
        }
        if (child is List && listKeys.contains(key)) {
          for (var i = 0; i < child.length; i++) {
            final item = child[i];
            if (item is String) {
              child[i] = remapping[item] ?? item;
            } else {
              _remapCoreReferenceValues(
                item,
                remapping,
                stringKeys: stringKeys,
                listKeys: listKeys,
              );
            }
          }
          continue;
        }
        _remapCoreReferenceValues(
          child,
          remapping,
          stringKeys: stringKeys,
          listKeys: listKeys,
        );
      }
      return;
    }
    if (value is List) {
      for (final child in value) {
        _remapCoreReferenceValues(
          child,
          remapping,
          stringKeys: stringKeys,
          listKeys: listKeys,
        );
      }
    }
  }

  static Map<String, dynamic> _cloneJsonMap(Map source) {
    final cloned = _cloneJsonValue(source);
    return cloned is Map<String, dynamic> ? cloned : <String, dynamic>{};
  }

  static dynamic _cloneJsonValue(dynamic value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        result[entry.key.toString()] = _cloneJsonValue(entry.value);
      }
      return result;
    }
    if (value is List) {
      return value.map(_cloneJsonValue).toList(growable: true);
    }
    return value;
  }

  static List<Map<String, dynamic>> _asObjectList(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((entry) => _cloneJsonMap(entry))
        .where((entry) => entry.isNotEmpty)
        .toList(growable: true);
  }

  static List<Map<String, dynamic>> _withoutManagedCoreEntries(
    dynamic value,
    Set<String> removedTypes, {
    Set<int> replacedIndexes = const <int>{},
    Set<String> replacedTags = const <String>{},
  }) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < value.length; index++) {
      if (replacedIndexes.contains(index)) {
        continue;
      }
      final valueEntry = value[index];
      if (valueEntry is! Map) {
        continue;
      }
      final entry = _cloneJsonMap(valueEntry);
      final type = entry['type']?.toString().trim().toLowerCase() ?? '';
      final tag = entry['tag']?.toString() ?? '';
      if (removedTypes.contains(type) ||
          (tag.isNotEmpty && replacedTags.contains(tag))) {
        continue;
      }
      result.add(entry);
    }
    return result;
  }

  static List<Map<String, dynamic>> _mergeTaggedObjectLists(
    dynamic raw,
    List<Map<String, dynamic>> generated, {
    required Set<String> replaceTags,
  }) {
    final result = <Map<String, dynamic>>[];
    final indexByTag = <String, int>{};
    for (final entry in _asObjectList(raw)) {
      final tag = entry['tag']?.toString() ?? '';
      if (tag.isNotEmpty && replaceTags.contains(tag)) {
        continue;
      }
      if (tag.isNotEmpty && indexByTag.containsKey(tag)) {
        continue;
      }
      if (tag.isNotEmpty) {
        indexByTag[tag] = result.length;
      }
      result.add(entry);
    }
    for (final entry in generated) {
      final tag = entry['tag']?.toString() ?? '';
      final existingIndex = tag.isEmpty ? null : indexByTag[tag];
      if (existingIndex != null) {
        result[existingIndex] = _cloneJsonMap(entry);
      } else {
        if (tag.isNotEmpty) {
          indexByTag[tag] = result.length;
        }
        result.add(_cloneJsonMap(entry));
      }
    }
    return result;
  }

  static Map<String, dynamic> _mergeConfigMap(
    dynamic raw,
    dynamic generated, {
    required Set<String> listKeys,
    bool generatedFirst = false,
  }) {
    final result = raw is Map ? _cloneJsonMap(raw) : <String, dynamic>{};
    if (generated is! Map) {
      return result;
    }
    for (final entry in generated.entries) {
      final key = entry.key.toString();
      if (!listKeys.contains(key)) {
        result[key] = _cloneJsonValue(entry.value);
        continue;
      }
      final generatedList = _asObjectList(entry.value);
      if (entry.value is! List) {
        result[key] = _cloneJsonValue(entry.value);
        continue;
      }
      final generatedTags = generatedList
          .map((item) => item['tag']?.toString())
          .whereType<String>()
          .where((tag) => tag.isNotEmpty)
          .toSet();
      if (!generatedFirst) {
        result[key] = _mergeTaggedObjectLists(
          result[key],
          generatedList,
          replaceTags: generatedTags,
        );
        continue;
      }
      final rawEntries = _asObjectList(result[key]);
      final seenTags = <String>{...generatedTags};
      result[key] = <Map<String, dynamic>>[
        ...generatedList.map(_cloneJsonMap),
        for (final entry in rawEntries)
          if (entry['tag']?.toString().isEmpty ?? true)
            _cloneJsonMap(entry)
          else if (seenTags.add(entry['tag'].toString()))
            _cloneJsonMap(entry),
      ];
    }
    return result;
  }

  bool _validRuleSetPath(String? path) {
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    try {
      final file = File(normalized);
      return file.existsSync() && file.lengthSync() > 4;
    } on FileSystemException {
      return false;
    }
  }

  List<String> _normalizedSplitRoutingPackages() {
    return normalizeSplitRoutingPackages(splitRoutingPackages);
  }

  List<Outbound> _visibleOutbounds() {
    final subscription = activeSubscription;
    if (subscription == null) {
      return const [];
    }
    return _activeResourceOutbounds()
        .where((outbound) => !outbound.info.deleted)
        .where((outbound) => !excludedOutboundTags.contains(outbound.tag))
        .where(_isUsableOutbound)
        .toList(growable: false);
  }

  Iterable<Outbound> _activeResourceOutbounds() {
    final subscription = activeSubscription;
    if (subscription == null) return const <Outbound>[];
    if (subscription.resourceConfigs.isEmpty) return subscription.outbounds;
    final activeProfile = HydraProxyChainResolver.activeProfile(subscription);
    final activeResourceId = activeProfile?.resourceId.trim() ?? '';
    if (activeResourceId.isEmpty) return const <Outbound>[];
    return subscription.outbounds.where((outbound) {
      final scope = outbound.config['_source_scope']?.toString() ?? '';
      return scope == activeResourceId;
    });
  }

  List<SubscriptionGroup> _visibleGroups(Set<String> visibleOutboundTags) {
    final subscription = activeSubscription;
    if (subscription == null || visibleOutboundTags.isEmpty) {
      return const [];
    }
    return subscription.groups
        .map((group) {
          final memberTags = group.outboundTags
              .where(visibleOutboundTags.contains)
              .toList(growable: false);
          if (memberTags.length < 2) {
            return null;
          }
          return group.copyWith(outboundTags: memberTags);
        })
        .whereType<SubscriptionGroup>()
        .toList(growable: false);
  }

  bool _isUsableOutbound(Outbound outbound) {
    if (outbound.type == 'snowtun') {
      final confId = (outbound.config['conf_id'] as String?)?.trim() ?? '';
      final transport =
          outbound.config['transport']?.toString().trim().toLowerCase() ?? '';
      final binaryPath = snowtunBinaryPath?.trim() ?? '';
      return confId.isNotEmpty && transport == 'xtun' && binaryPath.isNotEmpty;
    }
    final type = outbound.type.trim().toLowerCase();
    if (type.isEmpty) {
      return false;
    }
    if (_isEndpointBacked(outbound)) {
      return true;
    }
    if (outbound.config['_hydra_core_passthrough'] == true) {
      return true;
    }
    if (_hasValidServer(outbound.config)) {
      return true;
    }
    if (_nonServerOutboundTypes.contains(type)) {
      return true;
    }
    // Extended group/endpoint protocols can be valid without a top-level
    // `server` (for example a bond of nested outbounds or a parser source).
    if (outbound.config['outbounds'] is List ||
        outbound.config['endpoint'] != null ||
        outbound.config['providers'] is List) {
      return true;
    }
    // A complete sing-box document is validated by libbox itself. Do not
    // discard a newly introduced protocol merely because this Flutter build
    // does not know where its endpoint fields live.
    if (_readRawSingboxConfig() != null) {
      return true;
    }
    return false;
  }

  bool _isGroupOnlyOutbound(Outbound outbound) {
    return outbound.config['_group_only'] == true;
  }

  bool _isEndpointBacked(Outbound outbound) {
    return outbound.config['_hydra_source_section'] == 'endpoints';
  }

  /// Check if the outbound has a valid server address (valid IP or FQDN).
  /// Filters out garbage like `server: "admin"` that can't be resolved
  /// and poisons the entire urltest group.
  bool _hasValidServer(Map<String, dynamic> config) {
    final server = _resolveServerAddress(config);
    if (server.isEmpty) return false;
    // IPv4/IPv6 literal — always ok
    if (_looksLikeIp(server)) return true;
    // Domain must have at least one dot (FQDN)
    return server.contains('.');
  }

  /// Resolve the effective server address from config (same logic as
  /// _normalizeServerAddress but returns the value instead of mutating).
  static String _resolveServerAddress(Map<String, dynamic> config) {
    final current = (config['server'] as String?)?.trim() ?? '';
    if (current.isNotEmpty && current != '0.0.0.0') return current;

    final tls = config['tls'];
    if (tls is Map) {
      final sn = (tls['server_name'] as String?)?.trim() ?? '';
      if (sn.isNotEmpty) return sn;
    }

    final transport = config['transport'];
    if (transport is Map) {
      final headers = transport['headers'];
      if (headers is Map) {
        final hostHeader = (headers['Host'] ?? headers['host']) as Object?;
        final host = switch (hostHeader) {
          final String v => v.trim(),
          final List<dynamic> v when v.isNotEmpty => v.first.toString().trim(),
          _ => '',
        };
        if (host.isNotEmpty) return host;
      }
    }
    return '';
  }

  static bool _looksLikeIp(String s) {
    // IPv4: digits and dots, must have at least one dot (e.g. 1.2.3.4)
    // IPv6: hex digits and colons, must have at least one colon (e.g. ::1)
    // Bracketed IPv6: [::1]
    if (s.contains('.') && RegExp(r'^\d{1,3}(\.\d{1,3}){1,3}$').hasMatch(s)) {
      return true;
    }
    if (s.contains(':') && RegExp(r'^[\da-fA-F:[\]]+$').hasMatch(s)) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> _buildProxyOutbound(
    Outbound outbound,
    Map<String, String> tagRemapping,
  ) {
    final corePassthrough = outbound.config['_hydra_core_passthrough'] == true;
    final config = corePassthrough
        ? _cloneJsonMap(outbound.config)
        : Map<String, dynamic>.from(outbound.config);
    _removeAppOutboundMetadata(config);
    config['tag'] = outbound.tag;
    _remapOutboundReferenceValues(config, tagRemapping);
    // A complete sing-box document already uses the native core schema.
    // Share-link repairs and app-level dial/TLS overrides can introduce fields
    // that do not exist on extended types (for example MASQUE has no `server`).
    // Keep this boundary lossless and let libbox validate it.
    if (corePassthrough) {
      return config;
    }
    _normalizeStableOutboundSchema(config);
    if (outbound.type == 'snowtun') {
      final binaryPath = snowtunBinaryPath?.trim();
      if (binaryPath == null || binaryPath.isEmpty) {
        return config;
      }
      config['binary_path'] = binaryPath;
      final protectPath = snowtunProtectPath?.trim();
      if (vpnInboundEnabled &&
          Platform.isAndroid &&
          protectPath != null &&
          protectPath.isNotEmpty) {
        config['protect_path'] = protectPath;
      }
      final transport = config['transport']?.toString().trim().toLowerCase();
      if (transport != null && transport.isNotEmpty) {
        config['transport'] = transport;
      }
    }
    _normalizeServerAddress(config);
    _ensureRealityUtls(
      config,
      supportsSpiderX: _supportsCoreConfigExtension(
        capabilities.supportsRealitySpiderX,
      ),
    );
    _applyTlsFragmentation(config, tlsFragmentationMode);
    _applyDialOverrides(config);
    return config;
  }

  Map<String, dynamic> _buildEndpoint(
    Outbound outbound,
    Map<String, String> tagRemapping,
  ) {
    final config = _cloneJsonMap(outbound.config);
    _removeAppOutboundMetadata(config);
    config['tag'] = outbound.tag;
    _remapOutboundReferenceValues(config, tagRemapping);
    return config;
  }

  void _applyDialOverrides(Map<String, dynamic> config) {
    final type = config['type']?.toString().trim().toLowerCase() ?? '';
    if (_dialOverrideOutboundTypes.contains(type)) {
      config['tcp_fast_open'] = tcpFastOpenEnabled;
      config['tcp_multi_path'] = tcpMultiPathEnabled;
    }
  }

  String _dnsRemoteDetourFor(
    String selectorDefault,
    Set<String> selectableTags,
    Map<String, String> nativeDetoursByChainTag,
  ) {
    final subscription = activeSubscription;
    if (subscription != null && subscription.resourceConfigs.isEmpty) {
      for (final chain in subscription.proxyChains) {
        if (chain.tag == selectorDefault) {
          final detour = chain.detourTag.trim();
          return selectableTags.contains(detour) ? detour : 'select';
        }
      }
      for (final chain in subscription.proxyChains) {
        final detour = chain.detourTag.trim();
        if (selectableTags.contains(detour)) {
          return detour;
        }
      }
      return 'select';
    }
    final selectedChainDetour = nativeDetoursByChainTag[selectorDefault];
    if (selectedChainDetour != null &&
        selectableTags.contains(selectedChainDetour)) {
      return selectedChainDetour;
    }
    for (final detour in nativeDetoursByChainTag.values) {
      if (selectableTags.contains(detour)) {
        return detour;
      }
    }
    return 'select';
  }

  static Map<String, dynamic>? buildProxyChainOutboundConfig({
    required SubscriptionProxyChain chain,
    required Outbound target,
    required String? snowtunBinaryPath,
    required String? snowtunProtectPath,
    required bool vpnInboundEnabled,
    required bool tcpFastOpenEnabled,
    required bool tcpMultiPathEnabled,
    required TlsFragmentationMode tlsFragmentationMode,
    bool supportsRealitySpiderX = true,
    Map<String, String> tagRemapping = const <String, String>{},
  }) {
    final tag = chain.tag.trim();
    final detourTag = chain.detourTag.trim();
    if (tag.isEmpty || detourTag.isEmpty || target.type == 'direct') {
      return null;
    }
    final corePassthrough = target.config['_hydra_core_passthrough'] == true;
    final config = corePassthrough
        ? _cloneJsonMap(target.config)
        : Map<String, dynamic>.from(target.config);
    _removeAppOutboundMetadata(config);
    config['tag'] = tag;
    config['detour'] = detourTag;
    config.remove('domain_resolver');
    _remapOutboundReferenceValues(config, tagRemapping);
    if (corePassthrough) {
      return config;
    }
    _normalizeStableOutboundSchema(config);
    if (target.type == 'snowtun') {
      final binaryPath = snowtunBinaryPath?.trim();
      if (binaryPath == null || binaryPath.isEmpty) {
        return null;
      }
      config['binary_path'] = binaryPath;
      final protectPath = snowtunProtectPath?.trim();
      if (vpnInboundEnabled &&
          Platform.isAndroid &&
          protectPath != null &&
          protectPath.isNotEmpty) {
        config['protect_path'] = protectPath;
      }
      final transport = config['transport']?.toString().trim().toLowerCase();
      if (transport != null && transport.isNotEmpty) {
        config['transport'] = transport;
      }
    }
    _normalizeServerAddress(config);
    _ensureRealityUtls(config, supportsSpiderX: supportsRealitySpiderX);
    _applyTlsFragmentation(config, tlsFragmentationMode);
    final targetType = config['type']?.toString().trim().toLowerCase() ?? '';
    if (_dialOverrideOutboundTypes.contains(targetType)) {
      config['tcp_fast_open'] = tcpFastOpenEnabled;
      config['tcp_multi_path'] = tcpMultiPathEnabled;
    }
    return config;
  }

  static void _removeAppOutboundMetadata(Map<String, dynamic> config) {
    config.remove('_group_only');
    config.remove('_hydra_core_passthrough');
    config.remove('_hydra_source_section');
    config.remove('_hydra_source_index');
    config.remove('_hydra_source_index_section');
    config.remove('_hydra_original_tag');
    config.remove('_source_scope');
    config.removeWhere((key, _) => key.startsWith('_hydrabox_'));
  }

  _ProxyChainBuildResult _visibleProxyChainOutbounds({
    required List<Outbound> visibleOutbounds,
    required Set<String> selectableBaseTags,
    required Map<String, String> tagRemapping,
  }) {
    final subscription = activeSubscription;
    if (subscription == null || subscription.proxyChains.isEmpty) {
      return _ProxyChainBuildResult.empty;
    }
    final outboundByTag = {
      for (final outbound in visibleOutbounds) outbound.tag: outbound,
    };
    final result = <Map<String, dynamic>>[];
    final nativeDetoursByChainTag = <String, String>{};
    final seen = <String>{};
    final hydraResources = subscription.resourceConfigs.isNotEmpty;
    final activeHydraProfile = hydraResources
        ? HydraProxyChainResolver.activeProfile(subscription)
        : null;
    for (final chain in subscription.proxyChains) {
      final tag = chain.tag.trim();
      late final Outbound target;
      late final String nativeDetourTag;
      if (hydraResources) {
        if (tag.isEmpty) {
          throw StateError('Hydra proxy chain has an empty runtime tag');
        }
        if (!seen.add(tag)) {
          throw StateError('Duplicate Hydra proxy chain runtime tag "$tag"');
        }
        final owner = HydraProxyChainResolver.ownerProfile(
          subscription: subscription,
          chain: chain,
        );
        if (owner.resourceId.trim() !=
            (activeHydraProfile?.resourceId.trim() ?? '')) {
          // Every chain is validated above, but only the owner resource may
          // materialize it. A valid chain owned by another isolated native
          // document must not block or silently bind to the active document.
          continue;
        }
        if (selectableBaseTags.contains(tag)) {
          throw StateError(
            'Hydra proxy chain runtime tag "$tag" collides with a native '
            'selectable entry',
          );
        }
        final resolution = HydraProxyChainResolver.resolve(
          subscription: subscription,
          chain: chain,
          activeResourceOutbounds: visibleOutbounds,
          selectableBaseTags: selectableBaseTags,
        );
        target = resolution.target;
        nativeDetourTag = resolution.nativeDetourTag;
      } else {
        final legacyTarget = _targetOutboundForChain(chain, outboundByTag);
        if (tag.isEmpty ||
            legacyTarget == null ||
            _isEndpointBacked(legacyTarget) ||
            !seen.add(tag) ||
            !selectableBaseTags.contains(chain.detourTag.trim())) {
          continue;
        }
        target = legacyTarget;
        nativeDetourTag = chain.detourTag.trim();
      }
      final config = buildProxyChainOutboundConfig(
        chain: chain.copyWith(detourTag: nativeDetourTag),
        target: target,
        snowtunBinaryPath: snowtunBinaryPath,
        snowtunProtectPath: snowtunProtectPath,
        vpnInboundEnabled: vpnInboundEnabled,
        tcpFastOpenEnabled: tcpFastOpenEnabled,
        tcpMultiPathEnabled: tcpMultiPathEnabled,
        tlsFragmentationMode: tlsFragmentationMode,
        supportsRealitySpiderX: _supportsCoreConfigExtension(
          capabilities.supportsRealitySpiderX,
        ),
        tagRemapping: tagRemapping,
      );
      if (config != null) {
        result.add(config);
        nativeDetoursByChainTag[tag] = nativeDetourTag;
      } else if (hydraResources) {
        throw StateError(
          'Hydra proxy chain "$tag" could not be represented as a native '
          'outbound',
        );
      }
    }
    return _ProxyChainBuildResult(
      outbounds: result,
      nativeDetoursByChainTag: nativeDetoursByChainTag,
    );
  }

  Outbound? _targetOutboundForChain(
    SubscriptionProxyChain chain,
    Map<String, Outbound> outboundByTag,
  ) {
    final targetSubscriptionId = chain.targetSubscriptionId.trim();
    final activeSubscriptionId = activeSubscription?.id ?? '';
    if (targetSubscriptionId.isNotEmpty &&
        targetSubscriptionId != activeSubscriptionId) {
      return _snapshotOutboundFor(chain);
    }
    return outboundByTag[chain.targetTag.trim()] ?? _snapshotOutboundFor(chain);
  }

  Outbound? _snapshotOutboundFor(SubscriptionProxyChain chain) {
    if (chain.targetConfig.isEmpty) {
      return null;
    }
    final targetTag = chain.targetTag.trim();
    if (targetTag.isEmpty) {
      return null;
    }
    final config = Map<String, dynamic>.from(chain.targetConfig);
    config['tag'] = targetTag;
    final outbound = Outbound(
      tag: targetTag,
      name: chain.targetName.trim().isEmpty ? targetTag : chain.targetName,
      config: config,
    );
    return _isUsableOutbound(outbound) ? outbound : null;
  }

  List<String> _lowestOutboundTagsFor(
    String tag,
    List<Outbound> outbounds,
    List<SubscriptionGroup> groups,
  ) {
    final outboundTags = outbounds.map((outbound) => outbound.tag).toSet();
    final groupedCandidateChildTags = <String>{};
    final groupCandidateTags = <String>[];

    for (final group in groups) {
      if (!_isSetbackUrlTestGroup(group)) {
        continue;
      }
      final visibleChildTags = group.outboundTags
          .where(outboundTags.contains)
          .toList(growable: false);
      if (visibleChildTags.length < 2) {
        continue;
      }
      groupedCandidateChildTags.addAll(visibleChildTags);
      if (lowestProxyAllowsCountry(tag, group.country)) {
        groupCandidateTags.add(group.tag);
      }
    }

    final leafCandidateTags = outbounds
        .where(
          (outbound) =>
              !_isGroupOnlyOutbound(outbound) &&
              !groupedCandidateChildTags.contains(outbound.tag) &&
              lowestProxyAllowsCountry(
                tag,
                markAllServersRussia ? 'RU' : outbound.info.country,
              ),
        )
        .map((outbound) => outbound.tag)
        .toList(growable: false);

    return [...groupCandidateTags, ...leafCandidateTags];
  }

  bool _isSetbackUrlTestGroup(SubscriptionGroup group) {
    final type = group.type.trim();
    if (type.isNotEmpty && type != 'urltest') {
      return false;
    }
    return group.urlTestConfig.method?.trim().toLowerCase() == 'setback';
  }

  Map<String, dynamic> _buildLowestOutbound(String tag, List<String> tags) {
    return {
      'type': 'urltest',
      'tag': tag,
      'outbounds': tags,
      'url': activeSubscription?.urlTestConfig.url ?? urlTestUrl,
      'interval': _urltestInterval(
        activeSubscription?.urlTestConfig.intervalSeconds ??
            urlTestIntervalSeconds,
      ),
      'idle_timeout': _urltestInterval(
        activeSubscription?.urlTestConfig.intervalSeconds ??
            urlTestIntervalSeconds,
      ),
      'tolerance': _urltestTolerance(),
      'interrupt_exist_connections': false,
    };
  }

  Map<String, dynamic> _buildProxyGroupOutbound(
    SubscriptionGroup group,
    Set<String> visibleOutboundTags,
  ) {
    final memberTags = group.outboundTags
        .where(visibleOutboundTags.contains)
        .toList(growable: false);
    return {
      'type': 'urltest',
      'tag': group.tag,
      'outbounds': memberTags,
      'url': activeSubscription?.urlTestConfig.url ?? urlTestUrl,
      'interval': _urltestInterval(
        activeSubscription?.urlTestConfig.intervalSeconds ??
            urlTestIntervalSeconds,
      ),
      'idle_timeout': _urltestInterval(
        activeSubscription?.urlTestConfig.intervalSeconds ??
            urlTestIntervalSeconds,
      ),
      'tolerance': _urltestTolerance(),
      'interrupt_exist_connections': false,
    };
  }

  bool _supportsCoreConfigExtension(bool advertised) =>
      !capabilities.hasVersionedContract || advertised;

  String _urltestInterval(int? seconds) {
    final safeSeconds = seconds == null || seconds <= 0 ? 180 : seconds;
    return '${safeSeconds}s';
  }

  int _urltestTolerance() {
    return urlTestStrictTolerance ? 1 : 50;
  }

  static String? defaultSnowtunProtectPath() {
    if (!Platform.isAndroid) {
      return null;
    }
    return _snowtunProtectPath;
  }

  String _normalizedResolver(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  Map<String, dynamic> _buildDnsServer({
    required String tag,
    required String value,
    String? detour,
  }) {
    final trimmed = normalizeDnsResolverInput(value);
    if (trimmed == 'device://network') {
      return {'type': 'local', 'tag': tag};
    }
    if (trimmed.isEmpty) {
      throw FormatException('DNS resolver is empty for $tag');
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty) {
      throw FormatException('Unsupported DNS resolver "$trimmed" for $tag');
    }

    switch (uri.scheme) {
      case 'udp':
      case 'tcp':
        if (uri.host.isEmpty) {
          throw FormatException('DNS resolver host is empty for $tag');
        }
        return {
          'type': uri.scheme,
          'tag': tag,
          'server': uri.host,
          'server_port': uri.hasPort ? uri.port : 53,
          ..._dnsDialFields(server: uri.host, detour: detour),
        };
      case 'tls':
        if (uri.host.isEmpty) {
          throw FormatException('DNS resolver host is empty for $tag');
        }
        return {
          'type': 'tls',
          'tag': tag,
          'server': uri.host,
          'server_port': uri.hasPort ? uri.port : 853,
          ..._dnsDialFields(server: uri.host, detour: detour),
        };
      case 'https':
        if (uri.host.isEmpty) {
          throw FormatException('DNS resolver host is empty for $tag');
        }
        return {
          'type': 'https',
          'tag': tag,
          'server': uri.host,
          'server_port': uri.hasPort ? uri.port : 443,
          if (uri.path.isNotEmpty && uri.path != '/') 'path': uri.path,
          ..._dnsDialFields(server: uri.host, detour: detour),
        };
      default:
        throw FormatException('Unsupported DNS resolver "$trimmed" for $tag');
    }
  }

  Map<String, String> _dnsDialFields({required String server, String? detour}) {
    final normalizedDetour = _normalizeDnsDetour(detour);
    final fields = <String, String>{};
    if (normalizedDetour != null) {
      fields['detour'] = normalizedDetour;
    }
    if (InternetAddress.tryParse(server) == null) {
      // A DNS server cannot resolve its own hostname through the final DNS
      // route. Use Android's current-network resolver solely for bootstrap,
      // while preserving the requested proxy detour for the DNS connection.
      fields['domain_resolver'] = 'dns-local';
    }
    return fields;
  }

  String? _normalizeDnsDetour(String? detour) {
    final trimmed = detour?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'direct') {
      return null;
    }
    return trimmed;
  }

  static void _ensureRealityUtls(
    Map<String, dynamic> config, {
    required bool supportsSpiderX,
  }) {
    final tls = config['tls'];
    if (tls is! Map) {
      return;
    }
    final tlsMap = Map<String, dynamic>.from(tls);
    final reality = tlsMap['reality'];
    if (reality is Map && reality['enabled'] == true) {
      final realityMap = Map<String, dynamic>.from(reality);
      if (!supportsSpiderX) {
        realityMap.remove('spider_x');
      }
      final shortId = _normalizeRealityShortId(realityMap['short_id']);
      if (shortId != null) {
        realityMap['short_id'] = shortId;
      }
      tlsMap['reality'] = realityMap;
      final utls = tlsMap['utls'];
      if (utls is! Map || utls['enabled'] != true) {
        tlsMap['utls'] = const {'enabled': true, 'fingerprint': 'chrome'};
      } else {
        final utlsMap = Map<String, dynamic>.from(utls);
        final fingerprint = (utlsMap['fingerprint'] as String?)?.trim() ?? '';
        if (fingerprint.isEmpty) {
          utlsMap['fingerprint'] = 'chrome';
        } else {
          utlsMap['fingerprint'] = fingerprint.toLowerCase();
        }
        tlsMap['utls'] = utlsMap;
      }
      tlsMap['enabled'] = true;
      config['tls'] = tlsMap;
    }
  }

  static void _applyTlsFragmentation(
    Map<String, dynamic> config,
    TlsFragmentationMode mode,
  ) {
    if (mode == TlsFragmentationMode.disabled) {
      return;
    }
    final tls = config['tls'];
    if (tls is! Map || tls['enabled'] != true) {
      return;
    }
    final tlsMap = Map<String, dynamic>.from(tls);
    switch (mode) {
      case TlsFragmentationMode.disabled:
        break;
      case TlsFragmentationMode.record:
        tlsMap.remove('fragment');
        tlsMap.remove('fragment_fallback_delay');
        tlsMap['record_fragment'] = true;
      case TlsFragmentationMode.fragment:
        tlsMap.remove('record_fragment');
        tlsMap['fragment'] = true;
        tlsMap['fragment_fallback_delay'] = '300ms';
    }
    config['tls'] = tlsMap;
  }

  static String? _normalizeRealityShortId(dynamic value) {
    if (value is! String) {
      return null;
    }
    for (final candidate in value.split(',')) {
      final normalized = candidate.trim();
      if (normalized.isEmpty) {
        return '';
      }
      if (_isValidRealityShortId(normalized)) {
        return normalized.toLowerCase();
      }
      return null;
    }
    return null;
  }

  static bool _isValidRealityShortId(String value) {
    if (value.length.isOdd || value.length > 16) {
      return false;
    }
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      final isHex =
          (code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x46) ||
          (code >= 0x61 && code <= 0x66);
      if (!isHex) {
        return false;
      }
    }
    return true;
  }

  static void _normalizeServerAddress(Map<String, dynamic> config) {
    final currentServer = (config['server'] as String?)?.trim() ?? '';
    if (currentServer.isNotEmpty && currentServer != '0.0.0.0') {
      return;
    }

    final tls = config['tls'];
    if (tls is Map) {
      final serverName = (tls['server_name'] as String?)?.trim() ?? '';
      if (serverName.isNotEmpty) {
        config['server'] = serverName;
        return;
      }
    }

    final transport = config['transport'];
    if (transport is Map) {
      final headers = transport['headers'];
      if (headers is Map) {
        final hostHeader = (headers['Host'] ?? headers['host']) as Object?;
        final host = switch (hostHeader) {
          final String value => value.trim(),
          final List<dynamic> values when values.isNotEmpty =>
            values.first.toString().trim(),
          _ => '',
        };
        if (host.isNotEmpty) {
          config['server'] = host;
        }
      }
    }
  }

  static void _normalizeStableOutboundSchema(Map<String, dynamic> config) {
    final type = config['type']?.toString().trim().toLowerCase();
    final encryption = config['encryption']?.toString().trim().toLowerCase();
    if (type == 'vless' && encryption == 'none') {
      // VLESS does not expose a configurable encryption field in sing-box.
      // Legacy parsers stored `encryption: none`; omitting it is equivalent
      // and keeps the config accepted by strict stable-core decoders. Extended
      // VLESS encryption values are real protocol options and must survive.
      config.remove('encryption');
    }
  }
}

class _ProxyChainBuildResult {
  const _ProxyChainBuildResult({
    required this.outbounds,
    required this.nativeDetoursByChainTag,
  });

  static const empty = _ProxyChainBuildResult(
    outbounds: <Map<String, dynamic>>[],
    nativeDetoursByChainTag: <String, String>{},
  );

  final List<Map<String, dynamic>> outbounds;
  final Map<String, String> nativeDetoursByChainTag;
}

class SingboxBuildPlan {
  const SingboxBuildPlan({
    required this.config,
    required this.proxyOutboundTagsByIndex,
    required this.visibleProxyOutboundCount,
    this.hasRawCoreConfig = false,
    this.allowsZeroSelectableEntries = false,
  });

  final Map<String, dynamic> config;
  final Map<int, String> proxyOutboundTagsByIndex;
  final int visibleProxyOutboundCount;
  final bool hasRawCoreConfig;
  final bool allowsZeroSelectableEntries;
}
