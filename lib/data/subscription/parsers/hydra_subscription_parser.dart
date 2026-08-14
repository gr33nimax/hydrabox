import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hydrabox/core/hydra_profile_identity.dart';

import 'singbox_config_parser.dart';

class HydraParsedProfile {
  const HydraParsedProfile({
    required this.id,
    required this.resourceId,
    required this.name,
    required this.entrypointSection,
    required this.entrypointTag,
    required this.runtimeTag,
    this.enabled = true,
    this.requiredFeatures = const [],
  });

  final String id;
  final String resourceId;
  final String name;
  final String entrypointSection;
  final String entrypointTag;
  final String runtimeTag;
  final bool enabled;
  final List<String> requiredFeatures;

  Map<String, dynamic> toMap() => {
    'id': id,
    'resource_id': resourceId,
    'name': name,
    'entrypoint_section': entrypointSection,
    'entrypoint_tag': entrypointTag,
    'runtime_tag': runtimeTag,
    'enabled': enabled,
    if (requiredFeatures.isNotEmpty) 'required_features': requiredFeatures,
  };

  factory HydraParsedProfile.fromMap(Map<String, dynamic> map) {
    return HydraParsedProfile(
      id: map['id']?.toString() ?? '',
      resourceId: map['resource_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      entrypointSection: map['entrypoint_section']?.toString() ?? '',
      entrypointTag: map['entrypoint_tag']?.toString() ?? '',
      runtimeTag: map['runtime_tag']?.toString() ?? '',
      enabled: map['enabled'] != false,
      requiredFeatures: (map['required_features'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}

class HydraParsedSubscription {
  const HydraParsedSubscription({
    required this.outbounds,
    required this.profiles,
    required this.resourceConfigs,
    required this.defaultProfileId,
    required this.sourceMetadata,
    this.bodyMeta = const {},
  });

  final List<Map<String, dynamic>> outbounds;
  final List<HydraParsedProfile> profiles;
  final Map<String, Map<String, dynamic>> resourceConfigs;
  final String defaultProfileId;
  final Map<String, dynamic> sourceMetadata;
  final Map<String, String> bodyMeta;

  Map<String, dynamic>? get defaultResourceConfig {
    for (final profile in profiles) {
      if (profile.id == defaultProfileId) {
        return resourceConfigs[profile.resourceId];
      }
    }
    return null;
  }
}

/// Parses the client projection of an already HydraCore-validated v2 document.
///
/// HydraCore remains authoritative for schema, native config, reference and
/// permission validation. These checks are intentionally repeated at the
/// projection boundary so a non-native test host cannot silently weaken the
/// contract. Permissions are accepted automatically when they exactly match
/// the resource authority; there is no user-consent or pending-grant state.
class HydraSubscriptionParser {
  HydraSubscriptionParser._();

  static const apiVersion = 'hydra.io/subscription/v2';
  static const sourceFormat = 'hydra-subscription-v2';
  static String _clientVersion = '0.0.0';

  /// Configured from Android package metadata during bootstrap.
  ///
  /// Keeping the version outside this parser prevents release policy from
  /// drifting away from the actual APK version.
  static void configureClientVersion(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^v'), '');
    _clientVersion = normalized.isEmpty ? '0.0.0' : normalized;
  }
  static const maxPlaintextBytes = 12 * 1024 * 1024;

  static const supportedPermissions = {
    'network.outbound',
    'network.endpoint.wireguard',
    'network.inbound.call',
  };

  static const supportedClientFeatures = {
    'automatic-permissions',
    'multi-resource',
    'secure-storage',
    'subscription-jwe',
  };

  static const supportedOutboundTypes = {
    'socks',
    'http',
    'vmess',
    'trojan',
    'naive',
    'shadowtls',
    'vless',
    'mieru',
    'anytls',
    'trusttunnel',
    'hysteria',
    'hysteria2',
    'tuic',
    'sudoku',
    'snell',
    'call',
  };

  static bool isSupportedSourceFormat(dynamic value) =>
      value?.toString() == sourceFormat;

  static bool looksLike(String content) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('{')) return false;
    try {
      final value = jsonDecode(trimmed);
      if (value is! Map) return false;
      final api = value['api_version']?.toString() ?? '';
      if (api == apiVersion) return true;
      if (value.containsKey('api_version') && value['kind'] == 'Subscription') {
        return true;
      }
      return value.containsKey('protected');
    } on FormatException {
      return trimmed.contains(apiVersion);
    }
  }

  static HydraParsedSubscription parse(String content) {
    if (utf8.encode(content).length > maxPlaintextBytes) {
      throw const FormatException('Hydra subscription exceeds 12 MiB');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('Hydra subscription must be a JSON object');
    }
    final root = Map<String, dynamic>.from(decoded);
    final discriminator = root['api_version']?.toString() ?? '';
    if (discriminator != apiVersion || root['kind'] != 'Subscription') {
      if (_looksLikeJweMap(root)) {
        throw const FormatException(
          'Encrypted Hydra subscriptions must be opened by HydraCore first',
        );
      }
      throw const FormatException('Unsupported Hydra Subscription contract');
    }

    final identity = _requiredMap(root, 'identity');
    final validity = _requiredMap(root, 'validity');
    final requirements = _requiredMap(root, 'requirements');
    final coreRequirements = _requiredMap(requirements, 'core');
    final requiredCoreApi = coreRequirements['api_version'];
    if (coreRequirements['id'] != 'io.hydrabox.hydracore' ||
        requiredCoreApi is! int ||
        requiredCoreApi < 1 ||
        requiredCoreApi > 2 ||
        coreRequirements['remote_policy'] != 2) {
      throw const FormatException(
        'Hydra subscription requires an incompatible HydraCore contract',
      );
    }
    final clientRequirements = _requiredMap(requirements, 'client');
    if (clientRequirements['subscription_contract'] != 2) {
      throw const FormatException(
        'Hydra subscription requires an incompatible client contract',
      );
    }
    _validateClientFeatures(clientRequirements['features']);
    final minimumClientVersion =
        clientRequirements['min_version']?.toString() ?? '';
    if (minimumClientVersion.isNotEmpty &&
        _compareSemver(_clientVersion, minimumClientVersion) < 0) {
      throw FormatException(
        'Hydra subscription requires HydraBox $minimumClientVersion or newer',
      );
    }
    _validateValidity(validity);

    final resourcesRaw = root['resources'];
    final profilesRaw = root['profiles'];
    if (resourcesRaw is! List || resourcesRaw.isEmpty) {
      throw const FormatException('Hydra subscription has no resources');
    }
    if (profilesRaw is! List || profilesRaw.isEmpty) {
      throw const FormatException('Hydra subscription has no profiles');
    }

    final resourceConfigs = <String, Map<String, dynamic>>{};
    final permissionsByResource = <String, List<String>>{};
    final parsedOutbounds = <Map<String, dynamic>>[];
    for (var index = 0; index < resourcesRaw.length; index++) {
      final resource = _asMap(resourcesRaw[index], 'resources[$index]');
      final id = _requiredString(resource, 'id', 'resources[$index]');
      if (resourceConfigs.containsKey(id)) {
        throw FormatException('Duplicate Hydra resource id "$id"');
      }
      if (resource['format'] != 'sing-box-json') {
        throw FormatException('Unsupported Hydra resource format for "$id"');
      }
      final document = _requiredMap(resource, 'document');
      final inferred = _inferPermissions(document);
      final declared = _stringList(
        resource['requested_permissions'],
        'resources[$index].requested_permissions',
      );
      final declaredSet = declared.toSet();
      if (declared.length != declaredSet.length ||
          !supportedPermissions.containsAll(declaredSet) ||
          declaredSet.length != inferred.length ||
          !declaredSet.containsAll(inferred)) {
        throw FormatException(
          'Hydra resource "$id" requested_permissions do not exactly match '
          'its authority',
        );
      }
      resourceConfigs[id] = _cloneMap(document);
      permissionsByResource[id] = List.unmodifiable(declared);

      final projection = SingboxConfigParser.parse(jsonEncode(document));
      for (final outbound in projection) {
        final tag = outbound['tag']?.toString() ?? '';
        parsedOutbounds.add({
          ...outbound,
          '_source_scope': id,
          '_hydra_source_section': 'outbounds',
          '_hydra_original_tag': tag,
        });
      }
      final endpoints = document['endpoints'];
      if (endpoints is List) {
        for (final endpoint in endpoints.whereType<Map>()) {
          final value = Map<String, dynamic>.from(endpoint);
          final tag = value['tag']?.toString() ?? '';
          parsedOutbounds.add({
            ...value,
            '_name': tag,
            '_source_scope': id,
            '_hydra_source_section': 'endpoints',
            '_hydra_original_tag': tag,
          });
        }
      }
    }

    final profiles = <HydraParsedProfile>[];
    final profileIds = <String>{};
    for (var index = 0; index < profilesRaw.length; index++) {
      final profile = _asMap(profilesRaw[index], 'profiles[$index]');
      final id = _requiredString(profile, 'id', 'profiles[$index]');
      if (!profileIds.add(id)) {
        throw FormatException('Duplicate Hydra profile id "$id"');
      }
      final resourceId = _requiredString(
        profile,
        'resource',
        'profiles[$index]',
      );
      final document = resourceConfigs[resourceId];
      if (document == null) {
        throw FormatException(
          'Hydra profile "$id" references an unknown resource',
        );
      }
      final entrypoint = _requiredMap(profile, 'entrypoint');
      final section = _requiredString(
        entrypoint,
        'section',
        'profiles[$index].entrypoint',
      );
      final tag = _requiredString(
        entrypoint,
        'tag',
        'profiles[$index].entrypoint',
      );
      if (section != 'outbounds' && section != 'endpoints') {
        throw FormatException('Hydra profile "$id" has an invalid entrypoint');
      }
      if (!_documentContainsTag(document, section, tag)) {
        throw FormatException(
          'Hydra profile "$id" entrypoint is missing from resource '
          '"$resourceId"',
        );
      }
      profiles.add(
        HydraParsedProfile(
          id: id,
          resourceId: resourceId,
          name: _localizedText(profile['name']),
          entrypointSection: section,
          entrypointTag: tag,
          runtimeTag: HydraProfileIdentity.runtimeTag(
            profileId: id,
            resourceId: resourceId,
          ),
          enabled: profile['enabled'] != false,
          requiredFeatures: _stringList(
            profile['required_features'],
            'profiles[$index].required_features',
          ),
        ),
      );
      _validateClientFeatures(profile['required_features']);
    }

    final enabled = profiles.where((profile) => profile.enabled).toList();
    if (enabled.isEmpty) {
      throw const FormatException('Hydra subscription has no enabled profile');
    }
    final requestedDefault = root['default_profile']?.toString() ?? '';
    final defaultProfileId = requestedDefault.isEmpty
        ? enabled.first.id
        : requestedDefault;
    if (!enabled.any((profile) => profile.id == defaultProfileId)) {
      throw const FormatException(
        'Hydra default_profile must reference an enabled profile',
      );
    }

    final display = root['display'] is Map
        ? Map<String, dynamic>.from(root['display'] as Map)
        : const <String, dynamic>{};
    final update = root['update'] is Map
        ? Map<String, dynamic>.from(root['update'] as Map)
        : const <String, dynamic>{};
    final metadata = <String, dynamic>{
      'format': sourceFormat,
      'api_version': apiVersion,
      'issuer': identity['issuer']?.toString() ?? '',
      'subscription_id': identity['id']?.toString() ?? '',
      'channel': identity['channel']?.toString() ?? 'stable',
      'sequence': identity['sequence'],
      'payload_sha256': sha256.convert(utf8.encode(content)).toString(),
      'issued_at': validity['issued_at'],
      if (validity['not_before'] != null) 'not_before': validity['not_before'],
      if (validity['expires_at'] != null) 'expires_at': validity['expires_at'],
      'requirements': _cloneMap(requirements),
      if (update.isNotEmpty) 'update': _cloneMap(update),
      'permissions': permissionsByResource,
      'permissions_automatic': true,
      'default_profile': defaultProfileId,
    };
    final displayName = _optionalLocalizedText(display['name']);
    return HydraParsedSubscription(
      outbounds: parsedOutbounds,
      profiles: profiles,
      resourceConfigs: resourceConfigs,
      defaultProfileId: defaultProfileId,
      sourceMetadata: metadata,
      bodyMeta: {'profile-title': ?displayName},
    );
  }

  static Set<String> _inferPermissions(Map<String, dynamic> document) {
    final result = <String>{};
    if (_validateTypedSection(
      document['outbounds'],
      section: 'outbounds',
      allowedTypes: supportedOutboundTypes,
    )) {
      result.add('network.outbound');
    }
    if (_validateTypedSection(
      document['endpoints'],
      section: 'endpoints',
      allowedTypes: const {'wireguard'},
    )) {
      result.add('network.endpoint.wireguard');
    }
    if (_validateTypedSection(
      document['inbounds'],
      section: 'inbounds',
      allowedTypes: const {'call'},
    )) {
      result.add('network.inbound.call');
    }
    return result;
  }

  static bool _validateTypedSection(
    dynamic value, {
    required String section,
    required Set<String> allowedTypes,
  }) {
    if (value == null) return false;
    if (value is! List) {
      throw FormatException('Hydra resource $section must be an array');
    }
    for (var index = 0; index < value.length; index++) {
      final entry = value[index];
      if (entry is! Map) {
        throw FormatException('Hydra resource $section[$index] is invalid');
      }
      final type = entry['type']?.toString().trim().toLowerCase() ?? '';
      if (!allowedTypes.contains(type)) {
        throw FormatException(
          'Hydra resource $section[$index] type "$type" is not supported',
        );
      }
    }
    return value.isNotEmpty;
  }

  static void _validateClientFeatures(dynamic value) {
    final requested = _stringList(value, 'requirements.client.features');
    final unknown = requested
        .where((feature) => !supportedClientFeatures.contains(feature))
        .toList(growable: false);
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Hydra subscription requires unsupported client features: '
        '${unknown.join(', ')}',
      );
    }
  }

  static int _compareSemver(String left, String right) {
    List<Object> parts(String value) {
      final normalized = value.trim().replaceFirst(RegExp(r'^v'), '');
      final match = RegExp(
        r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
      ).firstMatch(normalized);
      if (match == null) {
        throw FormatException('Invalid semantic version "$value"');
      }
      return <Object>[
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        match.group(4) ?? '',
      ];
    }

    final a = parts(left);
    final b = parts(right);
    for (var index = 0; index < 3; index++) {
      final comparison = (a[index] as int).compareTo(b[index] as int);
      if (comparison != 0) return comparison;
    }
    final aPre = a[3] as String;
    final bPre = b[3] as String;
    if (aPre.isEmpty || bPre.isEmpty) {
      if (aPre == bPre) return 0;
      return aPre.isEmpty ? 1 : -1;
    }
    final aParts = aPre.split('.');
    final bParts = bPre.split('.');
    for (
      var index = 0;
      index < aParts.length || index < bParts.length;
      index++
    ) {
      if (index >= aParts.length) return -1;
      if (index >= bParts.length) return 1;
      final av = aParts[index];
      final bv = bParts[index];
      final an = int.tryParse(av);
      final bn = int.tryParse(bv);
      final comparison = an != null && bn != null
          ? an.compareTo(bn)
          : an != null
          ? -1
          : bn != null
          ? 1
          : av.compareTo(bv);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static void _validateValidity(Map<String, dynamic> validity) {
    final issuedAt = DateTime.tryParse(validity['issued_at']?.toString() ?? '');
    if (issuedAt == null) {
      throw const FormatException('Hydra issued_at is invalid');
    }
    final now = DateTime.now().toUtc();
    final notBefore = DateTime.tryParse(
      validity['not_before']?.toString() ?? '',
    );
    if (notBefore != null && now.isBefore(notBefore.toUtc())) {
      throw const FormatException('Hydra subscription is not active yet');
    }
    final expiresAt = DateTime.tryParse(
      validity['expires_at']?.toString() ?? '',
    );
    if (expiresAt != null && !now.isBefore(expiresAt.toUtc())) {
      throw const FormatException('Hydra subscription has expired');
    }
  }

  static bool _documentContainsTag(
    Map<String, dynamic> document,
    String section,
    String tag,
  ) {
    final entries = document[section];
    return entries is List &&
        entries.whereType<Map>().any((entry) => entry['tag'] == tag);
  }

  static Map<String, dynamic> _requiredMap(
    Map<dynamic, dynamic> map,
    String key,
  ) {
    final value = map[key];
    if (value is! Map) throw FormatException('Hydra field "$key" is required');
    return Map<String, dynamic>.from(value);
  }

  static Map<String, dynamic> _asMap(dynamic value, String field) {
    if (value is! Map) throw FormatException('Hydra $field must be an object');
    return Map<String, dynamic>.from(value);
  }

  static String _requiredString(
    Map<dynamic, dynamic> map,
    String key,
    String field,
  ) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty || value != value.trim()) {
      throw FormatException('Hydra $field.$key is invalid');
    }
    return value;
  }

  static List<String> _stringList(dynamic value, String field) {
    if (value == null) return const [];
    if (value is! List || value.any((entry) => entry is! String)) {
      throw FormatException('Hydra $field must be a string array');
    }
    return value.cast<String>().toList(growable: false);
  }

  static String _localizedText(dynamic value) {
    final result = _optionalLocalizedText(value);
    if (result == null) {
      throw const FormatException('Hydra localized text is invalid');
    }
    return result;
  }

  static String? _optionalLocalizedText(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is Map) {
      final fallback = value['default'];
      if (fallback is String && fallback.trim().isNotEmpty) return fallback;
    }
    return null;
  }

  static bool looksLikeJwe(String content) {
    try {
      final value = jsonDecode(content);
      return value is Map && _looksLikeJweMap(value);
    } on FormatException {
      return false;
    }
  }

  static bool _looksLikeJweMap(Map<dynamic, dynamic> root) =>
      root.containsKey('protected') &&
      root.containsKey('iv') &&
      root.containsKey('ciphertext') &&
      root.containsKey('tag');

  static Map<String, dynamic> _cloneMap(Map<dynamic, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}
