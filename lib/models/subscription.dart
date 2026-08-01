/// Parsed subscription header info (subscription-userinfo, profile-title, etc.)
class SubscriptionInfo {
  const SubscriptionInfo({
    this.title,
    this.upload,
    this.download,
    this.total,
    this.expire,
    this.happCryptoLink,
    this.supportUrl,
    this.webPageUrl,
    this.newUrl,
    this.ignoreSubscriptionMoved = false,
    this.updateIntervalHours,
    this.perAppProxyMode,
    this.perAppProxyList,
    this.customUserAgent,
    this.customRequestHeader,
    this.requireHwid = false,
    this.customHwid,
  });

  final String? title;
  final int? upload; // bytes
  final int? download; // bytes
  final int? total; // bytes
  final int? expire; // unix timestamp seconds
  final String? happCryptoLink;
  final String? supportUrl;
  final String? webPageUrl;
  final String? newUrl;
  final bool ignoreSubscriptionMoved;
  final int? updateIntervalHours;
  final String? perAppProxyMode; // off / on / bypass
  final List<String>? perAppProxyList; // package IDs
  final String? customUserAgent;
  final String? customRequestHeader; // raw Header: value lines
  final bool requireHwid;
  final String? customHwid;

  int get consumed => (upload ?? 0) + (download ?? 0);

  double get ratio {
    if (total == null || total! <= 0) return 0;
    return (consumed / total!).clamp(0.0, 1.0);
  }

  int? get remainingDays {
    if (expire == null || expire! <= 0) return null;
    final expireDate = DateTime.fromMillisecondsSinceEpoch(expire! * 1000);
    final now = DateTime.now();
    final diff = expireDate.difference(now).inDays;
    return diff < 0 ? 0 : diff;
  }

  Map<String, dynamic> toMap() => {
    if (title != null) 'title': title,
    if (upload != null) 'upload': upload,
    if (download != null) 'download': download,
    if (total != null) 'total': total,
    if (expire != null) 'expire': expire,
    if (happCryptoLink != null) 'happ_crypto_link': happCryptoLink,
    if (supportUrl != null) 'support_url': supportUrl,
    if (webPageUrl != null) 'web_page_url': webPageUrl,
    if (newUrl != null) 'new_url': newUrl,
    if (ignoreSubscriptionMoved) 'ignore_subscription_moved': true,
    if (updateIntervalHours != null)
      'update_interval_hours': updateIntervalHours,
    if (perAppProxyMode != null) 'per_app_proxy_mode': perAppProxyMode,
    if (perAppProxyList != null) 'per_app_proxy_list': perAppProxyList,
    if (customUserAgent != null) 'custom_user_agent': customUserAgent,
    if (customRequestHeader != null)
      'custom_request_header': customRequestHeader,
    if (requireHwid) 'require_hwid': true,
    if (customHwid != null) 'custom_hwid': customHwid,
  };

  factory SubscriptionInfo.fromMap(Map<String, dynamic> map) {
    return SubscriptionInfo(
      title: map['title'] as String?,
      upload: map['upload'] as int?,
      download: map['download'] as int?,
      total: map['total'] as int?,
      expire: map['expire'] as int?,
      happCryptoLink: map['happ_crypto_link'] as String?,
      supportUrl: map['support_url'] as String?,
      webPageUrl: map['web_page_url'] as String?,
      newUrl: map['new_url'] as String?,
      ignoreSubscriptionMoved: map['ignore_subscription_moved'] == true,
      updateIntervalHours: map['update_interval_hours'] as int?,
      perAppProxyMode: map['per_app_proxy_mode'] as String?,
      perAppProxyList: (map['per_app_proxy_list'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      customUserAgent: map['custom_user_agent'] as String?,
      customRequestHeader: map['custom_request_header'] as String?,
      requireHwid: map['require_hwid'] == true,
      customHwid: map['custom_hwid'] as String?,
    );
  }

  SubscriptionInfo copyWith({
    String? title,
    int? upload,
    int? download,
    int? total,
    int? expire,
    String? happCryptoLink,
    String? supportUrl,
    String? webPageUrl,
    String? newUrl,
    bool? ignoreSubscriptionMoved,
    int? updateIntervalHours,
    String? perAppProxyMode,
    List<String>? perAppProxyList,
    String? customUserAgent,
    String? customRequestHeader,
    bool? requireHwid,
    String? customHwid,
  }) {
    return SubscriptionInfo(
      title: title ?? this.title,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      total: total ?? this.total,
      expire: expire ?? this.expire,
      happCryptoLink: happCryptoLink ?? this.happCryptoLink,
      supportUrl: supportUrl ?? this.supportUrl,
      webPageUrl: webPageUrl ?? this.webPageUrl,
      newUrl: newUrl ?? this.newUrl,
      ignoreSubscriptionMoved:
          ignoreSubscriptionMoved ?? this.ignoreSubscriptionMoved,
      updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
      perAppProxyMode: perAppProxyMode ?? this.perAppProxyMode,
      perAppProxyList: perAppProxyList ?? this.perAppProxyList,
      customUserAgent: customUserAgent ?? this.customUserAgent,
      customRequestHeader: customRequestHeader ?? this.customRequestHeader,
      requireHwid: requireHwid ?? this.requireHwid,
      customHwid: customHwid ?? this.customHwid,
    );
  }
}

/// Info about a single outbound's test results
class OutboundInfo {
  const OutboundInfo({
    this.checked = false,
    this.deleted = false,
    this.externalIp,
    this.country,
    this.exitCountry,
    this.latestPing,
  });

  final bool checked;
  final bool deleted;
  final String? externalIp;

  /// Country encoded by the subscription/name and used for server grouping.
  final String? country;

  /// Country observed through the proxy exit IP. It must not replace [country].
  final String? exitCountry;
  final int? latestPing; // ms, null = not tested

  Map<String, dynamic> toMap() => {
    'checked': checked,
    if (deleted) 'deleted': true,
    if (externalIp != null) 'external_ip': externalIp,
    if (country != null) 'country': country,
    if (exitCountry != null) 'exit_country': exitCountry,
  };

  factory OutboundInfo.fromMap(Map<String, dynamic> map) {
    return OutboundInfo(
      checked: map['checked'] == true,
      deleted: map['deleted'] == true,
      externalIp: map['external_ip'] as String?,
      country: map['country'] as String?,
      exitCountry: map['exit_country'] as String?,
      // Latency is runtime-only. Persisted values are stale after reconnects
      // and must not be presented as a fresh proxy measurement.
      latestPing: null,
    );
  }

  OutboundInfo copyWith({
    bool? checked,
    bool? deleted,
    String? externalIp,
    String? country,
    String? exitCountry,
    int? latestPing,
  }) {
    return OutboundInfo(
      checked: checked ?? this.checked,
      deleted: deleted ?? this.deleted,
      externalIp: externalIp ?? this.externalIp,
      country: country ?? this.country,
      exitCountry: exitCountry ?? this.exitCountry,
      latestPing: latestPing ?? this.latestPing,
    );
  }
}

/// A single parsed outbound (stored as sing-box outbound JSON)
class Outbound {
  const Outbound({
    required this.tag,
    required this.name,
    required this.config,
    this.info = const OutboundInfo(),
  });

  final String tag;
  final String name;
  final Map<String, dynamic> config; // raw sing-box outbound JSON
  final OutboundInfo info;

  /// The protocol type extracted from config (vmess, vless, trojan, etc.)
  String get type => (config['type'] as String?) ?? 'unknown';

  /// Server address from config
  String get server => (config['server'] as String?) ?? '';

  /// Server port from config
  int get port => (config['server_port'] as int?) ?? 0;

  Map<String, dynamic> toMap() => {
    'tag': tag,
    'name': name,
    'config': config,
    'info': info.toMap(),
  };

  factory Outbound.fromMap(Map<String, dynamic> map) {
    return Outbound(
      tag: map['tag'] as String? ?? '',
      name: map['name'] as String? ?? '',
      config: Map<String, dynamic>.from(map['config'] as Map? ?? {}),
      info: map['info'] is Map
          ? OutboundInfo.fromMap(Map<String, dynamic>.from(map['info'] as Map))
          : const OutboundInfo(),
    );
  }

  Outbound copyWith({
    String? tag,
    String? name,
    Map<String, dynamic>? config,
    OutboundInfo? info,
  }) {
    return Outbound(
      tag: tag ?? this.tag,
      name: name ?? this.name,
      config: config ?? this.config,
      info: info ?? this.info,
    );
  }
}

/// URL test configuration — from subscription or user settings
class UrlTestConfig {
  const UrlTestConfig({
    this.url,
    this.method,
    this.intervalSeconds,
    this.timeoutSeconds,
    this.concurrency,
    this.unavailableCheckIntervalSeconds,
  });

  final String? url; // null = use app default
  final String? method; // null = sing-box default
  final int? intervalSeconds; // null = use app default
  final int? timeoutSeconds; // null = use app default
  final int? concurrency; // null = use app default
  final int? unavailableCheckIntervalSeconds; // null = use app default

  Map<String, dynamic> toMap() => {
    if (url != null) 'url': url,
    if (method != null) 'method': method,
    if (intervalSeconds != null) 'interval': intervalSeconds,
    if (timeoutSeconds != null) 'timeout': timeoutSeconds,
    if (concurrency != null) 'concurrency': concurrency,
    if (unavailableCheckIntervalSeconds != null)
      'unavailable_check_interval': unavailableCheckIntervalSeconds,
  };

  factory UrlTestConfig.fromMap(Map<String, dynamic> map) {
    int? intValue(String key) => (map[key] as num?)?.toInt();
    return UrlTestConfig(
      url: map['url'] as String?,
      method: map['method'] as String?,
      intervalSeconds: intValue('interval'),
      timeoutSeconds: intValue('timeout'),
      concurrency: intValue('concurrency'),
      unavailableCheckIntervalSeconds: intValue('unavailable_check_interval'),
    );
  }
}

/// A UI/runtime proxy group backed by a sing-box urltest outbound.
class SubscriptionGroup {
  const SubscriptionGroup({
    required this.tag,
    required this.name,
    required this.outboundTags,
    this.type = 'urltest',
    this.country,
    this.urlTestConfig = const UrlTestConfig(),
  });

  final String tag;
  final String name;
  final String type;
  final String? country;
  final List<String> outboundTags;
  final UrlTestConfig urlTestConfig;

  Map<String, dynamic> toMap() => {
    'tag': tag,
    'name': name,
    'type': type,
    if (country != null) 'country': country,
    'outbounds': outboundTags,
    'urltest_config': urlTestConfig.toMap(),
  };

  factory SubscriptionGroup.fromMap(Map<String, dynamic> map) {
    return SubscriptionGroup(
      tag: map['tag'] as String? ?? '',
      name: map['name'] as String? ?? '',
      type: map['type'] as String? ?? 'urltest',
      country: map['country']?.toString(),
      outboundTags: (map['outbounds'] as List? ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.trim().isNotEmpty)
          .toList(growable: false),
      urlTestConfig: map['urltest_config'] is Map
          ? UrlTestConfig.fromMap(
              Map<String, dynamic>.from(map['urltest_config'] as Map),
            )
          : const UrlTestConfig(),
    );
  }

  SubscriptionGroup copyWith({
    String? tag,
    String? name,
    String? type,
    String? country,
    List<String>? outboundTags,
    UrlTestConfig? urlTestConfig,
  }) {
    return SubscriptionGroup(
      tag: tag ?? this.tag,
      name: name ?? this.name,
      type: type ?? this.type,
      country: country ?? this.country,
      outboundTags: outboundTags ?? this.outboundTags,
      urlTestConfig: urlTestConfig ?? this.urlTestConfig,
    );
  }
}

/// Stable UI identity declared by HydraBox Subscription v1.
///
/// A profile points at a native sing-box outbound or endpoint but is not
/// itself a native runtime object. [runtimeTag] is the resolved compatibility
/// projection used by the existing selector pipeline.
class SubscriptionProfile {
  const SubscriptionProfile({
    required this.id,
    required this.name,
    required this.entrypointSection,
    required this.entrypointTag,
    required this.runtimeTag,
    this.enabled = true,
    this.country,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String entrypointSection;
  final String entrypointTag;
  final String runtimeTag;
  final bool enabled;
  final String? country;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'entrypoint_section': entrypointSection,
    'entrypoint_tag': entrypointTag,
    'runtime_tag': runtimeTag,
    'enabled': enabled,
    if (country != null) 'country': country,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  factory SubscriptionProfile.fromMap(Map<String, dynamic> map) {
    return SubscriptionProfile(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      entrypointSection: map['entrypoint_section'] as String? ?? '',
      entrypointTag: map['entrypoint_tag'] as String? ?? '',
      runtimeTag:
          map['runtime_tag'] as String? ??
          map['entrypoint_tag'] as String? ??
          '',
      enabled: map['enabled'] != false,
      country: map['country']?.toString(),
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? const {}),
    );
  }
}

/// A user-defined outbound clone that dials through another outbound first.
class SubscriptionProxyChain {
  const SubscriptionProxyChain({
    required this.tag,
    required this.name,
    required this.targetTag,
    required this.detourTag,
    this.targetSubscriptionId = '',
    this.targetName = '',
    this.targetCountry = '',
    this.targetConfig = const {},
  });

  final String tag;
  final String name;
  final String targetTag;
  final String detourTag;
  final String targetSubscriptionId;
  final String targetName;
  final String targetCountry;
  final Map<String, dynamic> targetConfig;

  Map<String, dynamic> toMap() => {
    'tag': tag,
    'name': name,
    'target_tag': targetTag,
    'detour_tag': detourTag,
    if (targetSubscriptionId.isNotEmpty)
      'target_subscription_id': targetSubscriptionId,
    if (targetName.isNotEmpty) 'target_name': targetName,
    if (targetCountry.isNotEmpty) 'target_country': targetCountry,
    if (targetConfig.isNotEmpty) 'target_config': targetConfig,
  };

  factory SubscriptionProxyChain.fromMap(Map<String, dynamic> map) {
    return SubscriptionProxyChain(
      tag: map['tag'] as String? ?? '',
      name: map['name'] as String? ?? '',
      targetTag: map['target_tag'] as String? ?? '',
      detourTag: map['detour_tag'] as String? ?? '',
      targetSubscriptionId: map['target_subscription_id'] as String? ?? '',
      targetName: map['target_name'] as String? ?? '',
      targetCountry: map['target_country'] as String? ?? '',
      targetConfig: Map<String, dynamic>.from(
        map['target_config'] as Map? ?? {},
      ),
    );
  }

  SubscriptionProxyChain copyWith({
    String? tag,
    String? name,
    String? targetTag,
    String? detourTag,
    String? targetSubscriptionId,
    String? targetName,
    String? targetCountry,
    Map<String, dynamic>? targetConfig,
  }) {
    return SubscriptionProxyChain(
      tag: tag ?? this.tag,
      name: name ?? this.name,
      targetTag: targetTag ?? this.targetTag,
      detourTag: detourTag ?? this.detourTag,
      targetSubscriptionId: targetSubscriptionId ?? this.targetSubscriptionId,
      targetName: targetName ?? this.targetName,
      targetCountry: targetCountry ?? this.targetCountry,
      targetConfig: targetConfig ?? this.targetConfig,
    );
  }
}

/// Full subscription model
class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.selectedProxyTag = '',
    this.selectedProfileId = '',
    this.sortOrder,
    this.lastUpdated = 0,
    this.disableAutoUpdate = false,
    this.markAllServersRussia = false,
    this.autoRefreshMinutes = 360,
    this.cachedVisibleProxyCount = -1,
    this.hasRawPayload = false,
    this.payloadStorageKey = '',
    this.rawContent = '',
    this.outbounds = const [],
    this.groups = const [],
    this.profiles = const [],
    this.proxyChains = const [],
    this.nativeConfig,
    this.sourceMetadata = const {},
    this.urlTestConfig = const UrlTestConfig(),
    this.info,
  });

  final String id;
  final String name;
  final String url;
  final String selectedProxyTag;
  final String selectedProfileId;
  final int? sortOrder;
  final int lastUpdated; // ms since epoch
  final bool disableAutoUpdate;
  final bool markAllServersRussia;
  final int autoRefreshMinutes; // 0 = disabled
  final int cachedVisibleProxyCount; // -1 = summary not cached yet
  final bool hasRawPayload;

  /// Internal encrypted-Hive payload generation selected by metadata.
  /// Empty means the legacy payload key equals [id].
  final String payloadStorageKey;
  final String rawContent; // raw response body
  final List<Outbound> outbounds;
  final List<SubscriptionGroup> groups;
  final List<SubscriptionProfile> profiles;
  final List<SubscriptionProxyChain> proxyChains;
  final Map<String, dynamic>? nativeConfig;
  final Map<String, dynamic> sourceMetadata;
  final UrlTestConfig urlTestConfig;
  final SubscriptionInfo? info;

  bool get needsRefresh {
    if (disableAutoUpdate || autoRefreshMinutes <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastUpdated) > autoRefreshMinutes * 60 * 1000;
  }

  Map<String, dynamic> toMetadataMap() {
    final payloadLoaded = rawContent.isNotEmpty || outbounds.isNotEmpty;
    final visibleProxyCount = payloadLoaded
        ? outbounds
              .where((outbound) => !outbound.info.deleted)
              .where((outbound) => outbound.config['_group_only'] != true)
              .length
        : cachedVisibleProxyCount;
    final rawPayloadAvailable = payloadLoaded
        ? rawContent.trim().length > 16
        : hasRawPayload;
    return {
      'id': id,
      'name': name,
      'url': url,
      if (selectedProxyTag.isNotEmpty) 'selected_proxy_tag': selectedProxyTag,
      if (selectedProfileId.isNotEmpty)
        'selected_profile_id': selectedProfileId,
      if (sortOrder != null) 'sort_order': sortOrder,
      'last_updated': lastUpdated,
      'disable_auto_update': disableAutoUpdate,
      if (markAllServersRussia) 'mark_all_servers_russia': true,
      'auto_refresh_minutes': autoRefreshMinutes,
      if (visibleProxyCount >= 0) 'visible_proxy_count': visibleProxyCount,
      if (rawPayloadAvailable) 'has_raw_payload': true,
      if (payloadStorageKey.isNotEmpty) 'payload_ref': payloadStorageKey,
      if (proxyChains.isNotEmpty)
        'proxy_chains': proxyChains.map((chain) => chain.toMap()).toList(),
      if (sourceMetadata.isNotEmpty)
        'source_metadata': _sourceMetadataSummary(sourceMetadata),
      'urltest_config': urlTestConfig.toMap(),
      if (info != null) 'info': info!.toMap(),
    };
  }

  Map<String, dynamic> toPayloadMap() => {
    'raw_content': rawContent,
    'outbounds': outbounds.map((o) => o.toMap()).toList(),
    if (groups.isNotEmpty) 'groups': groups.map((g) => g.toMap()).toList(),
    if (profiles.isNotEmpty)
      'profiles': profiles.map((profile) => profile.toMap()).toList(),
    if (nativeConfig != null) 'native_config': nativeConfig,
    if (sourceMetadata.isNotEmpty) 'source_metadata': sourceMetadata,
  };

  Map<String, dynamic> toMap() => {...toMetadataMap(), ...toPayloadMap()};

  factory Subscription.fromMetadataMap(Map<String, dynamic> map) {
    return Subscription(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unnamed',
      url: map['url'] as String? ?? '',
      selectedProxyTag: map['selected_proxy_tag'] as String? ?? '',
      selectedProfileId: map['selected_profile_id'] as String? ?? '',
      sortOrder: map['sort_order'] as int?,
      lastUpdated: map['last_updated'] as int? ?? 0,
      disableAutoUpdate: map['disable_auto_update'] == true,
      markAllServersRussia: map['mark_all_servers_russia'] == true,
      autoRefreshMinutes: map['auto_refresh_minutes'] as int? ?? 360,
      cachedVisibleProxyCount: map['visible_proxy_count'] as int? ?? -1,
      hasRawPayload: map['has_raw_payload'] == true,
      payloadStorageKey: map['payload_ref'] as String? ?? '',
      proxyChains:
          (map['proxy_chains'] as List?)
              ?.map(
                (entry) => SubscriptionProxyChain.fromMap(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .where(
                (chain) =>
                    chain.tag.trim().isNotEmpty &&
                    chain.targetTag.trim().isNotEmpty &&
                    chain.detourTag.trim().isNotEmpty,
              )
              .toList(growable: false) ??
          const [],
      sourceMetadata: Map<String, dynamic>.from(
        map['source_metadata'] as Map? ?? const {},
      ),
      urlTestConfig: map['urltest_config'] is Map
          ? UrlTestConfig.fromMap(
              Map<String, dynamic>.from(map['urltest_config'] as Map),
            )
          : const UrlTestConfig(),
      info: map['info'] is Map
          ? SubscriptionInfo.fromMap(
              Map<String, dynamic>.from(map['info'] as Map),
            )
          : null,
    );
  }

  factory Subscription.fromMap(Map<String, dynamic> map) {
    final metadata = Subscription.fromMetadataMap(map);
    return metadata.copyWith(
      rawContent: map['raw_content'] as String? ?? '',
      outbounds:
          (map['outbounds'] as List?)
              ?.map(
                (e) => Outbound.fromMap(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          [],
      groups:
          (map['groups'] as List?)
              ?.map(
                (e) => SubscriptionGroup.fromMap(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .where((group) => group.tag.isNotEmpty)
              .toList() ??
          [],
      profiles:
          (map['profiles'] as List?)
              ?.map(
                (e) => SubscriptionProfile.fromMap(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .where((profile) => profile.id.isNotEmpty)
              .toList(growable: false) ??
          const [],
      nativeConfig: map['native_config'] is Map
          ? Map<String, dynamic>.from(map['native_config'] as Map)
          : null,
      sourceMetadata: Map<String, dynamic>.from(
        map['source_metadata'] as Map? ?? metadata.sourceMetadata,
      ),
    );
  }

  Subscription copyWith({
    String? id,
    String? name,
    String? url,
    String? selectedProxyTag,
    String? selectedProfileId,
    int? sortOrder,
    int? lastUpdated,
    bool? disableAutoUpdate,
    bool? markAllServersRussia,
    int? autoRefreshMinutes,
    int? cachedVisibleProxyCount,
    bool? hasRawPayload,
    String? payloadStorageKey,
    String? rawContent,
    List<Outbound>? outbounds,
    List<SubscriptionGroup>? groups,
    List<SubscriptionProfile>? profiles,
    List<SubscriptionProxyChain>? proxyChains,
    Map<String, dynamic>? nativeConfig,
    bool clearNativeConfig = false,
    Map<String, dynamic>? sourceMetadata,
    UrlTestConfig? urlTestConfig,
    SubscriptionInfo? info,
  }) {
    return Subscription(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      selectedProxyTag: selectedProxyTag ?? this.selectedProxyTag,
      selectedProfileId:
          selectedProfileId ??
          (selectedProxyTag == null
              ? this.selectedProfileId
              : _profileIdForRuntimeTag(
                  profiles ?? this.profiles,
                  selectedProxyTag,
                )),
      sortOrder: sortOrder ?? this.sortOrder,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      disableAutoUpdate: disableAutoUpdate ?? this.disableAutoUpdate,
      markAllServersRussia: markAllServersRussia ?? this.markAllServersRussia,
      autoRefreshMinutes: autoRefreshMinutes ?? this.autoRefreshMinutes,
      cachedVisibleProxyCount:
          cachedVisibleProxyCount ?? this.cachedVisibleProxyCount,
      hasRawPayload: hasRawPayload ?? this.hasRawPayload,
      payloadStorageKey: payloadStorageKey ?? this.payloadStorageKey,
      rawContent: rawContent ?? this.rawContent,
      outbounds: outbounds ?? this.outbounds,
      groups: groups ?? this.groups,
      profiles: profiles ?? this.profiles,
      proxyChains: proxyChains ?? this.proxyChains,
      nativeConfig: clearNativeConfig
          ? null
          : nativeConfig ?? this.nativeConfig,
      sourceMetadata: sourceMetadata ?? this.sourceMetadata,
      urlTestConfig: urlTestConfig ?? this.urlTestConfig,
      info: info ?? this.info,
    );
  }

  @override
  String toString() =>
      'Subscription($name, ${outbounds.length} outbounds, updated: $lastUpdated)';

  static String _profileIdForRuntimeTag(
    List<SubscriptionProfile> profiles,
    String tag,
  ) {
    for (final profile in profiles) {
      if (profile.enabled && profile.runtimeTag == tag) {
        return profile.id;
      }
    }
    return '';
  }
}

Map<String, dynamic> _sourceMetadataSummary(Map<String, dynamic> source) {
  const trustStateKeys = {
    'format',
    'issuer',
    'subscription_id',
    'channel',
    'sequence',
    'issued_at',
    'not_before',
    'expires_at',
    'default_profile_id',
    'encrypted',
    'key_id',
    'payload_sha256',
    'trust_blocked',
    'trust_block_reason',
  };
  return <String, dynamic>{
    for (final entry in source.entries)
      if (trustStateKeys.contains(entry.key)) entry.key: entry.value,
  };
}
