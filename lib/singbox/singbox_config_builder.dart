import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/data/subscription/parsers/singbox_config_parser.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/libbox_capabilities.dart';

class SingboxConfigBuilder {
  static const List<String> _russiaDirectDomainSuffixes = ['ru', 'su', 'рф'];
  static const String _snowtunProtectPath =
      '@com.etonify.meow_client.snowtun.protect';
  static const int _urltestInterruptDelayThresholdMs = 300;
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
    this.capabilities = LibboxCapabilities.bundledLegacy,
    this.snowtunBinaryPath,
    this.snowtunProtectPath,
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
  final LibboxCapabilities capabilities;
  final String? snowtunBinaryPath;
  final String? snowtunProtectPath;

  Map<String, dynamic> build() {
    return buildPlan().config;
  }

  SingboxBuildPlan buildPlan() {
    if (proxyInboundEnabled &&
        (!isValidProxyUsername(proxyUsername) ||
            !isValidProxyPassword(proxyPassword))) {
      throw StateError('Local proxy requires valid access credentials');
    }
    final outbounds = _visibleOutbounds();
    final coreTagRemapping = _coreTagRemapping();
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
    final chainOutbounds = _visibleProxyChainOutbounds(
      visibleOutbounds: outbounds,
      selectableBaseTags: <String>{
        ...availableLowestTags,
        ...groupTags,
        ...selectableOutboundTags,
      },
      tagRemapping: coreTagRemapping,
    );
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
    final hasProxies = outboundTags.isNotEmpty;
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
      selectedProxyTag,
    );
    final selectorDefault = hasProxies
        ? (normalizedSelectedProxyTag.isNotEmpty &&
                  selectableTags.contains(normalizedSelectedProxyTag)
              ? normalizedSelectedProxyTag
              : availableLowestTags.isNotEmpty
              ? lowestProxyTag
              : outboundTags.first)
        : 'direct';
    final routeFinal = hasProxies ? 'select' : 'direct';
    final dnsFinal = hasProxies ? 'dns-remote' : 'dns-direct';
    final dnsRemoteDetour = hasProxies
        ? _dnsRemoteDetourFor(selectorDefault, selectableTags.toSet())
        : 'direct';

    final generatedConfig = <String, dynamic>{
      'log': {'level': logLevel},
      if (_supportsLegacyUrlTestConfigExtensions)
        'global': {
          'urltest_concurrency_limit': _urltestConcurrency(
            activeSubscription?.urlTestConfig.concurrency ?? urlTestConcurrency,
          ),
        },
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
        ],
        if (russiaRouteDataActive ||
            russiaCuratedDirectServicesActive ||
            adBlockActive)
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
          ],
        'final': dnsFinal,
        'independent_cache': true,
        'cache_capacity': 4096,
        if (dnsPreferIpv6) 'strategy': 'prefer_ipv6',
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
          if (russiaRouteDataActive)
            {
              'rule_set': ['ru-geoip-ru-whitelist', 'ru-geoip-ru'],
              'outbound': 'direct',
            },
        ],
        'final': routeFinal,
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
      visibleProxyOutboundCount: outbounds.length,
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
  /// routing safety rules and normalized proxy entries.  Every other section
  /// from the source document (endpoints, services, providers, custom DNS
  /// transports, extra inbounds and meta outbounds) is retained verbatim.
  /// This is the compatibility boundary that lets the app consume protocols
  /// added by the extended core without a matching Flutter release.
  Map<String, dynamic> _mergeRawCoreConfig(
    Map<String, dynamic> generated,
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) {
      return generated;
    }

    final merged = _cloneJsonMap(raw);

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
      merged[entry.key] = _cloneJsonValue(entry.value);
    }

    merged['dns'] = _mergeConfigMap(
      raw['dns'],
      generated['dns'],
      listKeys: const {'servers', 'rules', 'rule_set'},
    );
    merged['route'] = _mergeConfigMap(
      raw['route'],
      generated['route'],
      listKeys: const {'rules', 'rule_set'},
    );

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

    final rawInbounds = _withoutManagedCoreEntries(
      raw['inbounds'],
      _removedCoreInboundTypes,
    );
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

  Map<String, dynamic>? _readRawSingboxConfig() {
    final rawContent = activeSubscription?.rawContent.trim() ?? '';
    if (rawContent.isEmpty ||
        !(rawContent.startsWith('{') || rawContent.startsWith('['))) {
      return null;
    }
    try {
      final decoded = SingboxConfigParser.decodeDocument(rawContent);
      if (decoded == null) {
        return null;
      }
      final config = _cloneJsonMap(decoded);
      final tagRemapping = _coreTagRemapping();
      if (tagRemapping.isNotEmpty) {
        _remapRawCoreTags(config, tagRemapping);
      }
      if (!_hasTypedCoreSection(config)) {
        return null;
      }
      return config;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Map<String, String> _coreTagRemapping() {
    final candidates = <String, Set<String>>{};
    for (final outbound
        in activeSubscription?.outbounds ?? const <Outbound>[]) {
      final sourceSection =
          outbound.config['_etonify_source_section']?.toString() ?? '';
      if (sourceSection != 'outbounds' && sourceSection != 'endpoints') {
        continue;
      }
      final original =
          outbound.config['_etonify_original_tag']?.toString().trim() ?? '';
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
    for (final outbound
        in activeSubscription?.outbounds ?? const <Outbound>[]) {
      final sourceIndexSection =
          outbound.config['_etonify_source_index_section']?.toString() ??
          outbound.config['_etonify_source_section']?.toString() ??
          '';
      if (sourceIndexSection != section) {
        continue;
      }
      final value = outbound.config['_etonify_source_index'];
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
    for (final outbound
        in activeSubscription?.outbounds ?? const <Outbound>[]) {
      final sourceIndexSection =
          outbound.config['_etonify_source_index_section']?.toString() ??
          outbound.config['_etonify_source_section']?.toString() ??
          '';
      if (sourceIndexSection != section) {
        continue;
      }
      final original =
          outbound.config['_etonify_original_tag']?.toString().trim() ?? '';
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
      result[key] = _mergeTaggedObjectLists(
        result[key],
        generatedList,
        replaceTags: generatedList
            .map((item) => item['tag']?.toString())
            .whereType<String>()
            .where((tag) => tag.isNotEmpty)
            .toSet(),
      );
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
    return subscription.outbounds
        .where((outbound) => !outbound.info.deleted)
        .where((outbound) => !excludedOutboundTags.contains(outbound.tag))
        .where(_isUsableOutbound)
        .toList(growable: false);
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
    if (outbound.config['_etonify_core_passthrough'] == true) {
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
    return outbound.config['_etonify_source_section'] == 'endpoints';
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
    final corePassthrough =
        outbound.config['_etonify_core_passthrough'] == true;
    final config = corePassthrough
        ? _cloneJsonMap(outbound.config)
        : Map<String, dynamic>.from(outbound.config);
    config.remove('_group_only');
    config.remove('_etonify_core_passthrough');
    config.remove('_etonify_source_section');
    config.remove('_etonify_source_index');
    config.remove('_etonify_source_index_section');
    config.remove('_etonify_original_tag');
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
    config.remove('_group_only');
    config.remove('_etonify_core_passthrough');
    config.remove('_etonify_source_section');
    config.remove('_etonify_source_index');
    config.remove('_etonify_source_index_section');
    config.remove('_etonify_original_tag');
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
  ) {
    final subscription = activeSubscription;
    if (subscription == null) {
      return 'select';
    }
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
    final corePassthrough = target.config['_etonify_core_passthrough'] == true;
    final config = corePassthrough
        ? _cloneJsonMap(target.config)
        : Map<String, dynamic>.from(target.config);
    config.remove('_etonify_core_passthrough');
    config.remove('_etonify_source_section');
    config.remove('_etonify_source_index');
    config.remove('_etonify_source_index_section');
    config.remove('_etonify_original_tag');
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

  List<Map<String, dynamic>> _visibleProxyChainOutbounds({
    required List<Outbound> visibleOutbounds,
    required Set<String> selectableBaseTags,
    required Map<String, String> tagRemapping,
  }) {
    final subscription = activeSubscription;
    if (subscription == null || subscription.proxyChains.isEmpty) {
      return const [];
    }
    final outboundByTag = {
      for (final outbound in visibleOutbounds) outbound.tag: outbound,
    };
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final chain in subscription.proxyChains) {
      final tag = chain.tag.trim();
      final target = _targetOutboundForChain(chain, outboundByTag);
      if (tag.isEmpty ||
          target == null ||
          _isEndpointBacked(target) ||
          !seen.add(tag) ||
          !selectableBaseTags.contains(chain.detourTag.trim())) {
        continue;
      }
      final config = buildProxyChainOutboundConfig(
        chain: chain,
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
      }
    }
    return result;
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
      if (_supportsLegacyUrlTestConfigExtensions)
        'timeout': _urltestTimeout(
          activeSubscription?.urlTestConfig.timeoutSeconds ??
              urlTestTimeoutSeconds,
        ),
      if (_supportsLegacyUrlTestConfigExtensions)
        'concurrency': _urltestConcurrency(
          activeSubscription?.urlTestConfig.concurrency ?? urlTestConcurrency,
        ),
      if (_supportsLegacyUrlTestConfigExtensions)
        'unavailable_check_interval': _urltestUnavailableInterval(
          activeSubscription?.urlTestConfig.unavailableCheckIntervalSeconds ??
              urlTestUnavailableCheckIntervalSeconds,
        ),
      'tolerance': _urltestTolerance(),
      'interrupt_exist_connections': false,
      if (_supportsLegacyUrlTestConfigExtensions)
        'interrupt_delay_threshold': _urltestInterruptDelayThresholdMs,
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
      if (_supportsLegacyUrlTestConfigExtensions)
        ...?_urltestMethodEntry(group.urlTestConfig.method),
      'url': activeSubscription?.urlTestConfig.url ?? urlTestUrl,
      'interval': _urltestInterval(
        activeSubscription?.urlTestConfig.intervalSeconds ??
            urlTestIntervalSeconds,
      ),
      'idle_timeout': _urltestInterval(
        activeSubscription?.urlTestConfig.intervalSeconds ??
            urlTestIntervalSeconds,
      ),
      if (_supportsLegacyUrlTestConfigExtensions)
        'timeout': _urltestTimeout(
          activeSubscription?.urlTestConfig.timeoutSeconds ??
              urlTestTimeoutSeconds,
        ),
      if (_supportsLegacyUrlTestConfigExtensions)
        'concurrency': _urltestConcurrency(
          activeSubscription?.urlTestConfig.concurrency ?? urlTestConcurrency,
        ),
      if (_supportsLegacyUrlTestConfigExtensions)
        'unavailable_check_interval': _urltestUnavailableInterval(
          activeSubscription?.urlTestConfig.unavailableCheckIntervalSeconds ??
              urlTestUnavailableCheckIntervalSeconds,
        ),
      'tolerance': _urltestTolerance(),
      'interrupt_exist_connections': false,
      if (_supportsLegacyUrlTestConfigExtensions)
        'interrupt_delay_threshold': _urltestInterruptDelayThresholdMs,
    };
  }

  bool _supportsCoreConfigExtension(bool advertised) =>
      !capabilities.hasVersionedContract || advertised;

  // The old bundled core exposed URLTest tuning as custom JSON fields. The
  // versioned Etonify core exposes the same controls through URLTestWithOptions
  // while intentionally retaining the upstream sing-box config schema.
  bool get _supportsLegacyUrlTestConfigExtensions =>
      !capabilities.hasVersionedContract;

  String _urltestInterval(int? seconds) {
    final safeSeconds = seconds == null || seconds <= 0 ? 180 : seconds;
    return '${safeSeconds}s';
  }

  String _urltestTimeout(int? seconds) {
    final safeSeconds = seconds == null || seconds <= 0 ? 15 : seconds;
    return '${safeSeconds}s';
  }

  int _urltestConcurrency(int? value) {
    return (value == null || value <= 0 ? 8 : value).clamp(1, 8);
  }

  String _urltestUnavailableInterval(int? seconds) {
    final safeSeconds = (seconds == null || seconds <= 0 ? 120 : seconds).clamp(
      120,
      3600,
    );
    return '${safeSeconds}s';
  }

  int _urltestTolerance() {
    return urlTestStrictTolerance ? 1 : 50;
  }

  String? _urltestMethod(String? value) {
    final method = value?.trim();
    if (method == null || method.isEmpty) {
      return null;
    }
    return method;
  }

  Map<String, dynamic>? _urltestMethodEntry(String? value) {
    final method = _urltestMethod(value);
    return method == null ? null : {'method': method};
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
    if (normalizedDetour != null) {
      return {'detour': normalizedDetour};
    }
    if (InternetAddress.tryParse(server) == null) {
      // A direct encrypted DNS server cannot resolve its own hostname. Use
      // Android's current-network resolver solely for this bootstrap lookup.
      return const {'domain_resolver': 'dns-local'};
    }
    return const {};
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
