import 'dart:convert';

/// Extracts selectable outbounds and endpoints from a sing-box JSON
/// configuration.
///
/// If the subscription server returns a full sing-box config, this parser
/// extracts the relevant outbounds (filtering out meta types like
/// `direct`, `block` and `dns`). Native `selector`/`urltest` groups are retained
/// when their members come from providers. Top-level endpoints are represented
/// as app entries with `_etonify_source_section: endpoints`; the runtime builder
/// restores them to `endpoints` instead of emitting invalid endpoint objects in
/// `outbounds`.
class SingboxConfigParser {
  SingboxConfigParser._();

  static const _metaTypes = {'direct', 'block', 'dns', 'selector', 'urltest'};

  /// Returns `true` if [content] looks like a sing-box configuration.
  static bool canParse(String content) {
    try {
      final json = jsonDecode(content);
      if (json is Map) {
        return _isSingboxConfigMap(Map<String, dynamic>.from(json));
      }
      if (json is List) {
        return json.any((entry) {
          if (entry is! Map) return false;
          return _isSingboxConfigMap(Map<String, dynamic>.from(entry));
        });
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Parses sing-box JSON config and returns proxy outbound maps.
  /// Each returned map has `_name` set from the outbound `tag`.
  /// Protocol-specific validation is intentionally deferred to libbox.
  static List<Map<String, dynamic>> parse(String content) {
    final results = <Map<String, dynamic>>[];
    final document = decodeDocument(content);
    if (document != null) {
      _appendParsedConfig(document, results);
    }
    return results;
  }

  /// Decodes a single native document or combines an array of native
  /// documents using recursive map merge and list concatenation.
  ///
  /// Subscription providers sometimes publish an array of complete profiles.
  /// The app presents their selectable entries together, so their raw
  /// inbounds, endpoints, DNS, providers and services must use the same
  /// combined index space at runtime.
  static Map<String, dynamic>? decodeDocument(String content) {
    final decoded = jsonDecode(content);
    if (decoded is Map) {
      return _cloneJsonMap(decoded);
    }
    if (decoded is! List) {
      return null;
    }
    final documents = <Map<String, dynamic>>[];
    for (final entry in decoded) {
      if (entry is Map) {
        documents.add(_cloneJsonMap(entry));
      }
    }
    _scopeArrayDocumentTags(documents);
    Map<String, dynamic>? combined;
    for (final document in documents) {
      combined = combined == null
          ? document
          : _mergeJsonMaps(combined, document);
    }
    return combined;
  }

  static Map<String, dynamic> _mergeJsonMaps(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final result = _cloneJsonMap(first);
    for (final entry in second.entries) {
      final existing = result[entry.key];
      if (existing is Map && entry.value is Map) {
        result[entry.key] = _mergeJsonMaps(
          _cloneJsonMap(existing),
          _cloneJsonMap(entry.value as Map),
        );
      } else if (existing is List && entry.value is List) {
        result[entry.key] = <dynamic>[
          ...existing.map(_cloneJsonValue),
          ...(entry.value as List).map(_cloneJsonValue),
        ];
      } else {
        result[entry.key] = _cloneJsonValue(entry.value);
      }
    }
    return result;
  }

  static Map<String, dynamic> _cloneJsonMap(Map source) {
    return {
      for (final entry in source.entries)
        entry.key.toString(): _cloneJsonValue(entry.value),
    };
  }

  static dynamic _cloneJsonValue(dynamic value) {
    if (value is Map) {
      return _cloneJsonMap(value);
    }
    if (value is List) {
      return value.map(_cloneJsonValue).toList(growable: true);
    }
    return value;
  }

  static void _scopeArrayDocumentTags(List<Map<String, dynamic>> documents) {
    if (documents.length < 2) {
      return;
    }
    final outboundTagDocuments = <String, Set<int>>{};
    final providerTagDocuments = <String, Set<int>>{};
    final usedOutboundTags = <String>{};
    final usedProviderTags = <String>{};

    void collectTags(
      Map<String, dynamic> document,
      int documentIndex,
      Iterable<String> sections,
      Map<String, Set<int>> occurrences,
      Set<String> usedTags,
    ) {
      for (final section in sections) {
        final entries = document[section];
        if (entries is! List) continue;
        for (final entry in entries) {
          if (entry is! Map) continue;
          final tag = entry['tag']?.toString().trim() ?? '';
          if (tag.isEmpty) continue;
          usedTags.add(tag);
          occurrences.putIfAbsent(tag, () => <int>{}).add(documentIndex);
        }
      }
    }

    for (var i = 0; i < documents.length; i++) {
      collectTags(
        documents[i],
        i,
        const {'outbounds', 'endpoints'},
        outboundTagDocuments,
        usedOutboundTags,
      );
      collectTags(
        documents[i],
        i,
        const {'providers'},
        providerTagDocuments,
        usedProviderTags,
      );
    }

    String scopedTag(String tag, int documentIndex, Set<String> usedTags) {
      final base = '$tag@profile-${documentIndex + 1}';
      var candidate = base;
      var suffix = 2;
      while (usedTags.contains(candidate)) {
        candidate = '$base-$suffix';
        suffix++;
      }
      usedTags.add(candidate);
      return candidate;
    }

    final outboundRemappings = <int, Map<String, String>>{};
    for (final occurrence in outboundTagDocuments.entries) {
      if (occurrence.value.length < 2) continue;
      for (final documentIndex in occurrence.value) {
        outboundRemappings.putIfAbsent(
          documentIndex,
          () => <String, String>{},
        )[occurrence.key] = scopedTag(
          occurrence.key,
          documentIndex,
          usedOutboundTags,
        );
      }
    }
    final providerRemappings = <int, Map<String, String>>{};
    for (final occurrence in providerTagDocuments.entries) {
      if (occurrence.value.length < 2) continue;
      for (final documentIndex in occurrence.value) {
        providerRemappings.putIfAbsent(
          documentIndex,
          () => <String, String>{},
        )[occurrence.key] = scopedTag(
          occurrence.key,
          documentIndex,
          usedProviderTags,
        );
      }
    }

    for (var i = 0; i < documents.length; i++) {
      final outboundRemapping = outboundRemappings[i];
      if (outboundRemapping != null) {
        remapCoreOutboundTags(documents[i], outboundRemapping);
      }
      final providerRemapping = providerRemappings[i];
      if (providerRemapping != null) {
        _remapCoreProviderTags(documents[i], providerRemapping);
      }
    }
  }

  /// Remaps the shared outbound/endpoint tag namespace and its references.
  ///
  /// Complete config arrays use this before concatenation, and the runtime
  /// builder uses the same implementation when an app-owned reserved tag must
  /// be renamed. Keeping this contextual avoids corrupting inbound or DNS tag
  /// namespaces that happen to use the same string.
  static void remapCoreOutboundTags(
    Map<String, dynamic> config,
    Map<String, String> remapping,
  ) {
    for (final section in const {'outbounds', 'endpoints'}) {
      final entries = config[section];
      if (entries is! List) continue;
      for (final entry in entries) {
        if (entry is! Map) continue;
        final original = entry['tag']?.toString() ?? '';
        final replacement = remapping[original];
        if (replacement != null) {
          entry['tag'] = replacement;
        }
        _remapOutboundReferenceValues(entry, remapping);
      }
    }

    final route = config['route'];
    if (route is Map) {
      _remapCoreReferenceValues(
        route,
        remapping,
        stringKeys: const {
          'final',
          'outbound',
          'detour',
          'download_detour',
          'upload_detour',
          'endpoint',
        },
        listKeys: const {'outbound'},
      );
    }
    final dns = config['dns'];
    if (dns is Map) {
      _remapCoreReferenceValues(
        dns,
        remapping,
        stringKeys: const {
          'outbound',
          'detour',
          'download_detour',
          'upload_detour',
          'endpoint',
        },
        listKeys: const {'outbound'},
      );
    }
    for (final section in const {'providers', 'services'}) {
      _remapCoreReferenceValues(
        config[section],
        remapping,
        stringKeys: const {
          'outbound',
          'detour',
          'download_detour',
          'upload_detour',
          'endpoint',
          'verify_client_endpoint',
        },
        listKeys: const {'outbounds', 'verify_client_endpoint'},
      );
    }
    _remapCoreReferenceValues(
      config['experimental'],
      remapping,
      stringKeys: const {
        'outbound',
        'detour',
        'download_detour',
        'upload_detour',
        'endpoint',
        'external_ui_download_detour',
      },
      listKeys: const {'outbounds'},
    );
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

  static void _remapCoreProviderTags(
    Map<String, dynamic> config,
    Map<String, String> remapping,
  ) {
    final providers = config['providers'];
    if (providers is List) {
      for (final provider in providers) {
        if (provider is! Map) continue;
        final original = provider['tag']?.toString() ?? '';
        final replacement = remapping[original];
        if (replacement != null) {
          provider['tag'] = replacement;
        }
      }
    }
    _remapCoreReferenceValues(
      <dynamic>[config['outbounds'], config['endpoints']],
      remapping,
      stringKeys: const {'providers'},
      listKeys: const {'providers'},
    );
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

  static bool _isSingboxConfigMap(Map<String, dynamic> json) {
    bool hasTypedEntry(dynamic value) {
      return value is List &&
          value.any(
            (entry) =>
                entry is Map &&
                entry['type'] is String &&
                (entry['type'] as String).trim().isNotEmpty,
          );
    }

    for (final section in const {
      'outbounds',
      'endpoints',
      'inbounds',
      'providers',
      'services',
    }) {
      if (hasTypedEntry(json[section])) {
        return true;
      }
    }
    final dns = json['dns'];
    return dns is Map && hasTypedEntry(dns['servers']);
  }

  static void _appendParsedConfig(
    Map<String, dynamic> json,
    List<Map<String, dynamic>> results,
  ) {
    final outbounds = json['outbounds'];
    if (outbounds is List) {
      for (var sourceIndex = 0; sourceIndex < outbounds.length; sourceIndex++) {
        final entry = outbounds[sourceIndex];
        if (entry is! Map) continue;
        var outbound = Map<String, dynamic>.from(entry);
        final type = outbound['type']?.toString().trim() ?? '';
        if (type.isEmpty) continue;
        final providerBackedGroup =
            (type == 'selector' || type == 'urltest') &&
            _usesProviders(outbound);
        if (_metaTypes.contains(type) && !providerBackedGroup) continue;
        if (type == 'wireguard') {
          outbound = _migrateLegacyWireGuardOutbound(outbound);
        }
        final tag = outbound['tag']?.toString().trim() ?? '';
        outbound['_name'] = tag.isNotEmpty ? tag : '$type-${results.length}';
        // The 1.13 core only supports WireGuard as an endpoint. Preserve the
        // legacy options but route them to the endpoint section at runtime.
        outbound['_etonify_source_section'] = type == 'wireguard'
            ? 'endpoints'
            : 'outbounds';
        outbound['_etonify_source_index'] = sourceIndex;
        outbound['_etonify_source_index_section'] = 'outbounds';
        if (tag.isNotEmpty) {
          outbound['_etonify_original_tag'] = tag;
        }
        results.add(outbound);
      }
    }

    final endpoints = json['endpoints'];
    if (endpoints is List) {
      for (var sourceIndex = 0; sourceIndex < endpoints.length; sourceIndex++) {
        final entry = endpoints[sourceIndex];
        if (entry is! Map) continue;
        var endpoint = Map<String, dynamic>.from(entry);
        final type = endpoint['type']?.toString().trim() ?? '';
        if (type.isEmpty) continue;
        if (type == 'wireguard') {
          endpoint = _normalizeWireGuardEndpoint(endpoint);
        }

        final tag = endpoint['tag']?.toString().trim() ?? '';
        endpoint['_name'] = tag.isNotEmpty
            ? tag
            : '$type-endpoint-${results.length}';
        endpoint['_etonify_source_section'] = 'endpoints';
        endpoint['_etonify_source_index'] = sourceIndex;
        endpoint['_etonify_source_index_section'] = 'endpoints';
        if (tag.isNotEmpty) {
          endpoint['_etonify_original_tag'] = tag;
        }
        results.add(endpoint);
      }
    }
  }

  static Map<String, dynamic> _migrateLegacyWireGuardOutbound(
    Map<String, dynamic> source,
  ) {
    final endpoint = Map<String, dynamic>.from(source);
    final legacyReserved = endpoint.remove('reserved');

    void rename(String legacyKey, String endpointKey) {
      if (!endpoint.containsKey(endpointKey) &&
          endpoint.containsKey(legacyKey)) {
        endpoint[endpointKey] = endpoint[legacyKey];
      }
      endpoint.remove(legacyKey);
    }

    rename('system_interface', 'system');
    rename('interface_name', 'name');
    rename('local_address', 'address');

    final existingPeers = endpoint['peers'];
    if (existingPeers is! List || existingPeers.isEmpty) {
      endpoint.remove('peers');
      final peer = <String, dynamic>{};

      void moveToPeer(String legacyKey, String peerKey) {
        if (endpoint.containsKey(legacyKey)) {
          peer[peerKey] = endpoint.remove(legacyKey);
        }
      }

      moveToPeer('server', 'address');
      moveToPeer('server_port', 'port');
      moveToPeer('peer_public_key', 'public_key');
      moveToPeer('pre_shared_key', 'pre_shared_key');
      moveToPeer('allowed_ips', 'allowed_ips');
      moveToPeer(
        'persistent_keepalive_interval',
        'persistent_keepalive_interval',
      );
      if (legacyReserved != null && !_isZeroWireGuardReserved(legacyReserved)) {
        // Keep a non-zero override visible so validation can reject it
        // explicitly. Silently dropping these bytes would connect to a
        // different peer configuration.
        peer['reserved'] = _cloneJsonValue(legacyReserved);
      }
      if (peer.isNotEmpty) {
        peer.putIfAbsent(
          'allowed_ips',
          () => const <String>['0.0.0.0/0', '::/0'],
        );
        endpoint['peers'] = <Map<String, dynamic>>[peer];
      }
    } else {
      for (final key in const {
        'server',
        'server_port',
        'peer_public_key',
        'pre_shared_key',
        'allowed_ips',
        'persistent_keepalive_interval',
      }) {
        endpoint.remove(key);
      }
      endpoint['peers'] = existingPeers
          .map((entry) {
            if (entry is! Map) {
              return _cloneJsonValue(entry);
            }
            final peer = _cloneJsonMap(entry);

            void renamePeer(String legacyKey, String endpointKey) {
              if (!peer.containsKey(endpointKey) &&
                  peer.containsKey(legacyKey)) {
                peer[endpointKey] = peer[legacyKey];
              }
              peer.remove(legacyKey);
            }

            renamePeer('server', 'address');
            renamePeer('server_port', 'port');
            renamePeer('peer_public_key', 'public_key');
            peer.putIfAbsent(
              'allowed_ips',
              () => const <String>['0.0.0.0/0', '::/0'],
            );
            return peer;
          })
          .toList(growable: true);
      final peers = endpoint['peers'];
      if (legacyReserved != null && !_isZeroWireGuardReserved(legacyReserved)) {
        if (peers is List &&
            peers.length == 1 &&
            peers.single is Map &&
            !(peers.single as Map).containsKey('reserved')) {
          final peer = _cloneJsonMap(peers.single as Map);
          peer['reserved'] = _cloneJsonValue(legacyReserved);
          endpoint['peers'] = <Map<String, dynamic>>[peer];
        } else {
          endpoint['reserved'] = _cloneJsonValue(legacyReserved);
        }
      }
    }

    // The endpoint API owns both TCP and UDP routing and has no GSO switch.
    endpoint.remove('network');
    endpoint.remove('gso');
    return _normalizeWireGuardEndpoint(endpoint);
  }

  static bool _usesProviders(Map<String, dynamic> outbound) {
    if (outbound['use_all_providers'] == true) {
      return true;
    }
    final providers = outbound['providers'];
    return (providers is String && providers.trim().isNotEmpty) ||
        (providers is List &&
            providers.any((entry) => entry.toString().trim().isNotEmpty));
  }

  static Map<String, dynamic> _normalizeWireGuardEndpoint(
    Map<String, dynamic> source,
  ) {
    final endpoint = _cloneJsonMap(source);
    if (_isZeroWireGuardReserved(endpoint['reserved'])) {
      endpoint.remove('reserved');
    }
    final peers = endpoint['peers'];
    if (peers is List) {
      endpoint['peers'] = peers
          .map((entry) {
            if (entry is! Map) {
              return _cloneJsonValue(entry);
            }
            final peer = _cloneJsonMap(entry);
            if (_isZeroWireGuardReserved(peer['reserved'])) {
              peer.remove('reserved');
            }
            return peer;
          })
          .toList(growable: true);
    }
    return endpoint;
  }

  static bool _isZeroWireGuardReserved(dynamic value) {
    return value is List &&
        value.length == 3 &&
        value.every((entry) => entry is int && entry == 0);
  }
}
