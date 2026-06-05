import 'dart:io';
import 'dart:math';

import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/models/subscription.dart';

class SingboxConfigBuilder {
  static const String _snowtunProtectPath =
      '@com.etonify.meow_client.snowtun.protect';
  static const String _telegramServicesRuleSetTag = 'telegram-services';
  static const int _urltestInterruptDelayThresholdMs = 300;
  static const List<String> _telegramIpCidrs = [
    '91.108.4.0/22',
    '91.108.8.0/22',
    '91.108.12.0/22',
    '91.108.16.0/22',
    '91.108.20.0/22',
    '91.108.56.0/22',
    '149.154.160.0/20',
    '2001:67c:4e8::/48',
    '2001:b28:f23d::/48',
    '2001:b28:f23f::/48',
    '2001:b28:f242::/48',
  ];
  static const List<String> _telegramDomainSuffixes = [
    't.me',
    'tdesktop.com',
    'telegra.ph',
    'telegram.dog',
    'telegram.me',
    'telegram.org',
  ];

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
    required this.dnsDirectResolver,
    required this.dnsProxyResolver,
    required this.dnsPreferIpv6,
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
    this.russiaGeoipRuBlockedPath,
    this.russiaCuratedDirectServicesPath,
    this.russiaAiServicesPath,
    required this.bypassLocalNetwork,
    required this.splitRoutingMode,
    required this.splitRoutingPackages,
    required this.logLevel,
    required this.tcpFastOpenEnabled,
    required this.tcpMultiPathEnabled,
    required this.interruptExistingConnections,
    required this.urlTestStrictTolerance,
    required this.markAllServersRussia,
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
  final String dnsDirectResolver;
  final String dnsProxyResolver;
  final bool dnsPreferIpv6;
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
  final String? russiaGeoipRuBlockedPath;
  final String? russiaCuratedDirectServicesPath;
  final String? russiaAiServicesPath;
  final bool bypassLocalNetwork;
  final SplitRoutingMode splitRoutingMode;
  final List<String> splitRoutingPackages;
  final String logLevel;
  final bool tcpFastOpenEnabled;
  final bool tcpMultiPathEnabled;
  final bool interruptExistingConnections;
  final bool urlTestStrictTolerance;
  final bool markAllServersRussia;
  final String? snowtunBinaryPath;
  final String? snowtunProtectPath;

  Map<String, dynamic> build() {
    return buildPlan().config;
  }

  SingboxBuildPlan buildPlan() {
    final outbounds = _visibleOutbounds();
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
        (russiaGeositeRuBlockedPath?.trim().isNotEmpty ?? false) &&
        (russiaGeositeRuAvailableOnlyInsidePath?.trim().isNotEmpty ?? false) &&
        (russiaGeoipRuBlockedPath?.trim().isNotEmpty ?? false);
    final russiaCuratedDirectServicesActive =
        useRussiaRouteData &&
        (russiaCuratedDirectServicesPath?.trim().isNotEmpty ?? false);
    final russiaAiServicesActive =
        russiaRouteDataActive &&
        (russiaAiServicesPath?.trim().isNotEmpty ?? false);
    final defaultLowestOutboundTags = _lowestOutboundTagsFor(
      lowestProxyTag,
      outbounds,
      visibleGroups,
    );
    final urlTestAvailable =
        selectableOutboundTags.length > 1 ||
        visibleGroups.any(_isSetbackUrlTestGroup);
    final lowestOutboundTags = urlTestAvailable
        ? ({
            for (final tag in lowestProxyTags)
              tag: _lowestOutboundTagsFor(tag, outbounds, visibleGroups).isEmpty
                  ? defaultLowestOutboundTags
                  : _lowestOutboundTagsFor(tag, outbounds, visibleGroups),
          }..removeWhere((_, tags) => tags.isEmpty))
        : <String, List<String>>{};
    final availableLowestTags = lowestProxyTags
        .where(lowestOutboundTags.containsKey)
        .toList(growable: false);
    final mixedProxyAvailable =
        lowestOutboundTags.containsKey(lowestProxyTag) &&
        lowestOutboundTags.containsKey(lowestOpenProxyTag) &&
        lowestOutboundTags.containsKey(lowestFreeProxyTag);
    final telegramServicesActive = mixedProxyAvailable;
    final groupTags = visibleGroups
        .map((group) => group.tag)
        .toList(growable: false);
    final chainOutbounds = _visibleProxyChainOutbounds(
      visibleOutbounds: outbounds,
      selectableBaseTags: <String>{
        ...availableLowestTags,
        if (mixedProxyAvailable) mixedProxyTag,
        ...groupTags,
        ...selectableOutboundTags,
      },
    );
    final chainTags = chainOutbounds
        .map((outbound) => outbound['tag']?.toString() ?? '')
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    final selectableTags = <String>[
      ...availableLowestTags,
      if (mixedProxyAvailable) mixedProxyTag,
      ...groupTags,
      ...chainTags,
      ...selectableOutboundTags,
    ];
    final hasProxies = outboundTags.isNotEmpty;
    final normalizedSplitRoutingPackages = _normalizedSplitRoutingPackages();
    final splitRoutingActive =
        splitRoutingMode != SplitRoutingMode.disabled &&
        normalizedSplitRoutingPackages.isNotEmpty;
    final tunIncludePackages =
        splitRoutingMode == SplitRoutingMode.proxySelected && splitRoutingActive
        ? normalizedSplitRoutingPackages
        : const <String>[];
    final tunExcludePackages =
        splitRoutingMode == SplitRoutingMode.bypassSelected &&
            splitRoutingActive
        ? normalizedSplitRoutingPackages
        : const <String>[];
    final adBlockActive =
        adBlockEnabled && (adBlockBlockRuleSetPath?.trim().isNotEmpty ?? false);
    final adBlockAllowActive =
        adBlockActive && (adBlockAllowRuleSetPath?.trim().isNotEmpty ?? false);
    final selectorDefault = hasProxies
        ? (selectedProxyTag.isNotEmpty &&
                  selectableTags.contains(selectedProxyTag)
              ? selectedProxyTag
              : availableLowestTags.isNotEmpty
              ? lowestProxyTag
              : outboundTags.first)
        : 'direct';
    final proxyOutboundIndexes = <int, String>{};
    final proxyStartIndex = hasProxies
        ? 1 +
              availableLowestTags.length +
              (mixedProxyAvailable ? 1 : 0) +
              visibleGroups.length +
              chainOutbounds.length
        : 1;
    for (var i = 0; i < outbounds.length; i++) {
      proxyOutboundIndexes[proxyStartIndex + i] = outbounds[i].tag;
    }

    final routeFinal = switch (splitRoutingMode) {
      SplitRoutingMode.proxySelected when splitRoutingActive => 'direct',
      _ => hasProxies ? 'select' : 'direct',
    };
    final dnsFinal = hasProxies ? 'dns-remote' : 'dns-direct';
    final dnsRemoteDetour = hasProxies
        ? _dnsRemoteDetourFor(selectorDefault, selectableTags.toSet())
        : 'direct';

    return SingboxBuildPlan(
      config: {
        'log': {'level': logLevel},
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
            const <String, Object>{'type': 'local', 'tag': 'dns-local'},
          ],
          if (russiaRouteDataActive ||
              russiaCuratedDirectServicesActive ||
              adBlockActive)
            'rules': [
              if (russiaCuratedDirectServicesActive)
                {
                  'rule_set': 'ru-direct-services',
                  'action': 'route',
                  'server': 'dns-direct',
                },
              if (russiaRouteDataActive)
                {
                  'rule_set': 'ru-geosite-ru-available-only-inside',
                  'action': 'route',
                  'server': 'dns-direct',
                },
              if (russiaRouteDataActive)
                {
                  'rule_set': 'ru-geosite-ru-blocked',
                  'action': 'route',
                  'server': dnsFinal,
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
              'address': ['172.19.0.1/30'],
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
            },
        ],
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
          if (hasProxies && mixedProxyAvailable)
            _buildMixedOutbound(
              russiaAiServicesActive: russiaAiServicesActive,
              russiaRouteDataActive: russiaRouteDataActive,
              telegramServicesActive: telegramServicesActive,
            ),
          if (hasProxies)
            ...visibleGroups.map(
              (group) => _buildProxyGroupOutbound(group, outboundTags.toSet()),
            ),
          ...chainOutbounds,
          ...outbounds.map(_buildProxyOutbound),
          {
            'type': 'direct',
            'tag': 'direct',
            'tcp_fast_open': tcpFastOpenEnabled,
            'tcp_multi_path': tcpMultiPathEnabled,
          },
        ],
        'route': {
          'auto_detect_interface': true,
          'default_domain_resolver': 'dns-direct',
          if (russiaRouteDataActive ||
              russiaCuratedDirectServicesActive ||
              russiaAiServicesActive ||
              telegramServicesActive ||
              adBlockActive)
            'rule_set': [
              if (telegramServicesActive)
                {
                  'tag': _telegramServicesRuleSetTag,
                  'rules': [
                    {
                      'ip_cidr': _telegramIpCidrs,
                      'domain_suffix': _telegramDomainSuffixes,
                    },
                  ],
                },
              if (russiaAiServicesActive)
                {
                  'type': 'local',
                  'tag': 'ru-ai-services',
                  'format': 'binary',
                  'path': russiaAiServicesPath,
                },
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
                  'tag': 'ru-geoip-ru-blocked',
                  'format': 'binary',
                  'path': russiaGeoipRuBlockedPath,
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
            if (blockLeaks) {'protocol': 'stun', 'action': 'reject'},
            if (splitRoutingActive)
              {
                'package_name': normalizedSplitRoutingPackages,
                'outbound': switch (splitRoutingMode) {
                  SplitRoutingMode.proxySelected =>
                    hasProxies ? 'select' : 'direct',
                  SplitRoutingMode.bypassSelected => 'direct',
                  SplitRoutingMode.disabled => hasProxies ? 'select' : 'direct',
                },
              },
            if (russiaRouteDataActive)
              {
                'rule_set': 'ru-geosite-ru-available-only-inside',
                'outbound': 'direct',
              },
            if (russiaCuratedDirectServicesActive)
              {'rule_set': 'ru-direct-services', 'outbound': 'direct'},
            if (russiaRouteDataActive)
              {
                'rule_set': ['ru-geosite-ru-blocked', 'ru-geoip-ru-blocked'],
                'outbound': hasProxies ? 'select' : 'direct',
              },
            if (adBlockAllowActive)
              {'rule_set': 'adblock-allow', 'outbound': routeFinal},
            if (adBlockActive)
              {'rule_set': 'adblock-block', 'action': 'reject'},
            if (bypassLocalNetwork)
              {'ip_is_private': true, 'outbound': 'direct'},
          ],
          'final': routeFinal,
        },
      },
      proxyOutboundTagsByIndex: proxyOutboundIndexes,
      visibleProxyOutboundCount: outbounds.length,
    );
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
    return _hasValidServer(outbound.config);
  }

  bool _isGroupOnlyOutbound(Outbound outbound) {
    return outbound.config['_group_only'] == true;
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

  Map<String, dynamic> _buildProxyOutbound(Outbound outbound) {
    final config = Map<String, dynamic>.from(outbound.config);
    config.remove('_group_only');
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
    _ensureRealityUtls(config);
    config['tag'] = outbound.tag;
    config['tcp_fast_open'] = tcpFastOpenEnabled;
    config['tcp_multi_path'] = tcpMultiPathEnabled;
    return config;
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
  }) {
    final tag = chain.tag.trim();
    final detourTag = chain.detourTag.trim();
    if (tag.isEmpty || detourTag.isEmpty || target.type == 'direct') {
      return null;
    }
    final config = Map<String, dynamic>.from(target.config);
    config['tag'] = tag;
    config['detour'] = detourTag;
    config.remove('domain_resolver');
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
    _ensureRealityUtls(config);
    config['tcp_fast_open'] = tcpFastOpenEnabled;
    config['tcp_multi_path'] = tcpMultiPathEnabled;
    return config;
  }

  List<Map<String, dynamic>> _visibleProxyChainOutbounds({
    required List<Outbound> visibleOutbounds,
    required Set<String> selectableBaseTags,
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
      'timeout': _urltestTimeout(
        activeSubscription?.urlTestConfig.timeoutSeconds ??
            urlTestTimeoutSeconds,
      ),
      'concurrency': _urltestConcurrency(
        activeSubscription?.urlTestConfig.concurrency ?? urlTestConcurrency,
      ),
      'unavailable_check_interval': _urltestInterval(
        activeSubscription?.urlTestConfig.unavailableCheckIntervalSeconds ??
            urlTestUnavailableCheckIntervalSeconds,
      ),
      'tolerance': _urltestTolerance(),
      'interrupt_exist_connections': false,
      'interrupt_delay_threshold': _urltestInterruptDelayThresholdMs,
    };
  }

  Map<String, dynamic> _buildMixedOutbound({
    required bool russiaAiServicesActive,
    required bool russiaRouteDataActive,
    required bool telegramServicesActive,
  }) {
    return {
      'type': 'mixed',
      'tag': mixedProxyTag,
      'outbounds': [lowestProxyTag, lowestOpenProxyTag, lowestFreeProxyTag],
      'default': lowestProxyTag,
      'setback_to_default': true,
      'rules': [
        if (russiaAiServicesActive)
          {'rule_set': 'ru-ai-services', 'outbound': lowestFreeProxyTag},
        if (telegramServicesActive)
          {
            'rule_set': _telegramServicesRuleSetTag,
            'outbound': lowestOpenProxyTag,
          },
        if (russiaRouteDataActive)
          {
            'rule_set': ['ru-geosite-ru-blocked', 'ru-geoip-ru-blocked'],
            'outbound': lowestOpenProxyTag,
          },
      ],
      'interrupt_exist_connections': interruptExistingConnections,
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
      ...?_urltestMethodEntry(group.urlTestConfig.method),
      'url': activeSubscription?.urlTestConfig.url ?? urlTestUrl,
      'interval': _urltestInterval(
        activeSubscription?.urlTestConfig.intervalSeconds ??
            urlTestIntervalSeconds,
      ),
      'timeout': _urltestTimeout(
        activeSubscription?.urlTestConfig.timeoutSeconds ??
            urlTestTimeoutSeconds,
      ),
      'concurrency': _urltestConcurrency(
        activeSubscription?.urlTestConfig.concurrency ?? urlTestConcurrency,
      ),
      'unavailable_check_interval': _urltestInterval(
        activeSubscription?.urlTestConfig.unavailableCheckIntervalSeconds ??
            urlTestUnavailableCheckIntervalSeconds,
      ),
      'tolerance': _urltestTolerance(),
      'interrupt_exist_connections': false,
      'interrupt_delay_threshold': _urltestInterruptDelayThresholdMs,
    };
  }

  String _urltestInterval(int? seconds) {
    final safeSeconds = seconds == null || seconds <= 0 ? 180 : seconds;
    return '${safeSeconds}s';
  }

  String _urltestTimeout(int? seconds) {
    final safeSeconds = seconds == null || seconds <= 0 ? 15 : seconds;
    return '${safeSeconds}s';
  }

  int _urltestConcurrency(int? value) {
    return value == null || value <= 0 ? 30 : value;
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

  Map<String, dynamic> _buildDnsServer({
    required String tag,
    required String value,
    String? detour,
  }) {
    final trimmed = value.trim();
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
          ...?switch (_normalizeDnsDetour(detour)) {
            final value? => {'detour': value},
            null => null,
          },
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
          ...?switch (_normalizeDnsDetour(detour)) {
            final value? => {'detour': value},
            null => null,
          },
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
          ...?switch (_normalizeDnsDetour(detour)) {
            final value? => {'detour': value},
            null => null,
          },
        };
      default:
        throw FormatException('Unsupported DNS resolver "$trimmed" for $tag');
    }
  }

  String? _normalizeDnsDetour(String? detour) {
    final trimmed = detour?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'direct') {
      return null;
    }
    return trimmed;
  }

  static void _ensureRealityUtls(Map<String, dynamic> config) {
    final tls = config['tls'];
    if (tls is! Map) {
      return;
    }
    final tlsMap = Map<String, dynamic>.from(tls);
    final reality = tlsMap['reality'];
    if (reality is Map && reality['enabled'] == true) {
      final realityMap = Map<String, dynamic>.from(reality);
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
}

class SingboxBuildPlan {
  const SingboxBuildPlan({
    required this.config,
    required this.proxyOutboundTagsByIndex,
    required this.visibleProxyOutboundCount,
  });

  final Map<String, dynamic> config;
  final Map<int, String> proxyOutboundTagsByIndex;
  final int visibleProxyOutboundCount;
}
