import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';

import '../hydrabox_subscription_crypto.dart';
import '../strict_json.dart';
import 'singbox_config_parser.dart';

class HydraBoxParsedProfile {
  const HydraBoxParsedProfile({
    required this.id,
    required this.name,
    required this.entrypointSection,
    required this.entrypointTag,
    required this.enabled,
    this.country,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String entrypointSection;
  final String entrypointTag;
  final bool enabled;
  final String? country;

  /// Full profile object, including optional extensions, for forward-compatible
  /// persistence. Runtime selection uses the typed fields above.
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'entrypoint_section': entrypointSection,
    'entrypoint_tag': entrypointTag,
    'enabled': enabled,
    if (country != null) 'country': country,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  factory HydraBoxParsedProfile.fromMap(Map<String, dynamic> map) {
    return HydraBoxParsedProfile(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      entrypointSection: map['entrypoint_section']?.toString() ?? '',
      entrypointTag: map['entrypoint_tag']?.toString() ?? '',
      enabled: map['enabled'] != false,
      country: map['country']?.toString(),
      metadata: map['metadata'] is Map
          ? _cloneMap(map['metadata'] as Map)
          : const {},
    );
  }
}

class HydraBoxParsedSubscription {
  const HydraBoxParsedSubscription({
    required this.outbounds,
    required this.nativeConfig,
    required this.profiles,
    required this.defaultProfileId,
    required this.bodyMeta,
    required this.sourceMetadata,
  });

  final List<Map<String, dynamic>> outbounds;
  final Map<String, dynamic> nativeConfig;
  final List<HydraBoxParsedProfile> profiles;
  final String? defaultProfileId;
  final Map<String, String> bodyMeta;
  final Map<String, dynamic> sourceMetadata;
}

/// Parser for the explicit-profile HydraBox Subscription v1 format.
///
/// `profiles` is the only source of selectable UI entries. The nested native
/// sing-box document remains opaque and is retained in full for HydraCore
/// validation and runtime assembly.
class HydraBoxSubscriptionParser {
  HydraBoxSubscriptionParser._();

  static const apiVersion = 'hydrabox.io/subscription/v1';
  static const kind = 'SubscriptionData';
  static const _maxOuterBytes = 16 * 1024 * 1024;
  static const _maxPlaintextBytes = 12 * 1024 * 1024;
  static const _maxProfiles = 4096;
  static const _maxIdLength = 128;
  static const _maxTagLength = 512;
  static const _maxSafeInteger = 9007199254740991;
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$');
  static final RegExp _extensionNamePattern = RegExp(
    r'^(?:[A-Za-z0-9-]+\.)+[A-Za-z0-9-]+(?:/[A-Za-z0-9._-]+)*$',
  );
  static final RegExp _rfc3339Pattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
    r'(?:\.(\d+))?(Z|[+-](\d{2}):(\d{2}))$',
  );
  static const _knownEnvelopeKeys = {
    'api_version',
    'kind',
    'issuer',
    'subscription_id',
    'channel',
    'sequence',
    'issued_at',
    'not_before',
    'expires_at',
    'default_profile_id',
    'metadata',
    'compatibility',
    'update',
    'runtime',
    'profiles',
    'required_extensions',
    'extensions',
  };
  static const _knownRuntimeKeys = {
    'format',
    'ownership',
    'document',
    'extensions',
  };
  static const _knownProfileKeys = {
    'id',
    'name',
    'description',
    'entrypoint',
    'enabled',
    'country',
    'tags',
    'required_features',
    'extensions',
  };
  static const _nonProfileOutboundTypes = {'direct', 'block', 'dns'};
  static const _appOwnedDnsServerTags = {
    'dns-remote',
    'dns-direct',
    'dns-ru-direct',
    'dns-local',
  };
  static const _appOwnedRouteRuleSetTags = {
    'ru-direct-services',
    'ru-geosite-ru-blocked',
    'ru-geosite-ru-available-only-inside',
    'ru-geosite-category-ru',
    'ru-geoip-ru-blocked',
    'ru-geoip-ru-whitelist',
    'ru-geoip-ru',
    'adblock-allow',
    'adblock-block',
  };
  static bool looksLike(String content) {
    if (HydraBoxJweCodec.looksLike(content)) return true;
    final members = scanTopLevelJsonObjectForDetection(
      content,
      memberNames: const {'api_version', 'kind'},
      stringValueKeys: const {'api_version', 'kind'},
    );
    final versions = members['api_version'] ?? const <String?>[];
    final kinds = members['kind'] ?? const <String?>[];
    return versions.any((value) => value?.startsWith('hydrabox.io/') == true) ||
        kinds.any((value) => value == kind) ||
        versions.length > 1 ||
        kinds.length > 1;
  }

  /// Re-applies the non-local-authority policy to a hydrated/native document.
  /// Runtime builders use this defense-in-depth boundary so serialized backup
  /// projections can never bypass the strict wire parser.
  static void validateRemoteRuntimeDocumentSafety(Map<String, dynamic> config) {
    _validateRuntimeDocumentSafety(config);
    _indexNativeEntries(config);
  }

  static HydraBoxParsedSubscription parse(
    String content, {
    String? decryptionKey,
  }) {
    if (utf8.encode(content).length > _maxOuterBytes) {
      throw const FormatException(
        'HydraBox subscription response is too large',
      );
    }
    var plaintext = content;
    var encrypted = false;
    String? keyId;
    if (HydraBoxJweCodec.looksLike(content)) {
      if (decryptionKey == null ||
          decryptionKey.isEmpty ||
          decryptionKey != decryptionKey.trim()) {
        throw const FormatException(
          'Encrypted HydraBox subscription requires an hbx-key',
        );
      }
      keyId = HydraBoxJweCodec.keyId(content);
      plaintext = HydraBoxJweCodec.decrypt(content, encodedKey: decryptionKey);
      encrypted = true;
    }
    if (utf8.encode(plaintext).length > _maxPlaintextBytes) {
      throw const FormatException(
        'HydraBox subscription plaintext is too large',
      );
    }

    final decoded = decodeStrictJson(plaintext);
    if (decoded is! Map) {
      throw const FormatException(
        'HydraBox subscription payload must be a JSON object',
      );
    }
    final document = Map<String, dynamic>.from(decoded);
    _validateEnvelope(document);

    final runtime = _requiredMap(document, 'runtime');
    _rejectUnknownKeys(runtime, _knownRuntimeKeys, field: 'runtime');
    _rejectExplicitNulls(runtime, _knownRuntimeKeys, field: 'runtime');
    _validateExtensionsMap(runtime['extensions'], field: 'runtime.extensions');
    if (runtime['format'] != 'sing-box-json') {
      throw const FormatException(
        'HydraBox v1 supports runtime.format "sing-box-json" only',
      );
    }
    _validateRuntimeOwnership(runtime['ownership']);
    final nativeConfig = _cloneMap(_requiredMap(runtime, 'document'));
    _validateRuntimeDocumentSafety(nativeConfig);
    final nativeEntries = _indexNativeEntries(nativeConfig);

    final rawProfiles = document['profiles'];
    if (rawProfiles is! List) {
      throw const FormatException('profiles must be an array');
    }
    if (rawProfiles.length > _maxProfiles) {
      throw const FormatException(
        'HydraBox subscription has too many profiles',
      );
    }

    final profileIds = <String>{};
    final profileEntrypoints = <String>{};
    final profiles = <HydraBoxParsedProfile>[];
    for (var index = 0; index < rawProfiles.length; index++) {
      final value = rawProfiles[index];
      if (value is! Map) {
        throw FormatException('profiles[$index] must be an object');
      }
      final profileMap = Map<String, dynamic>.from(value);
      _rejectUnknownKeys(
        profileMap,
        _knownProfileKeys,
        field: 'profiles[$index]',
      );
      _rejectExplicitNulls(
        profileMap,
        _knownProfileKeys,
        field: 'profiles[$index]',
      );
      final id = _validateId(profileMap['id'], field: 'profiles[$index].id');
      if (!profileIds.add(id)) {
        throw FormatException('Duplicate HydraBox profile id "$id"');
      }
      final name = _localizedDefault(
        profileMap['name'],
        field: 'profiles[$index].name',
      );
      if (profileMap.containsKey('description')) {
        _localizedDefault(
          profileMap['description'],
          field: 'profiles[$index].description',
        );
      }
      final enabledValue = profileMap['enabled'];
      if (enabledValue != null && enabledValue is! bool) {
        throw FormatException('profiles[$index].enabled must be a boolean');
      }
      final enabled = enabledValue != false;
      final entrypoint = _requiredMap(profileMap, 'entrypoint');
      _rejectUnknownKeys(entrypoint, const {
        'section',
        'tag',
      }, field: 'profiles[$index].entrypoint');
      _rejectExplicitNulls(entrypoint, const {
        'section',
        'tag',
      }, field: 'profiles[$index].entrypoint');
      final sectionValue = entrypoint['section'];
      final section = sectionValue is String ? sectionValue : '';
      if (section != 'outbounds' && section != 'endpoints') {
        throw FormatException(
          'profiles[$index].entrypoint.section must be '
          '"outbounds" or "endpoints"',
        );
      }
      final tag = _validateNativeTag(
        entrypoint['tag'],
        field: 'profiles[$index].entrypoint.tag',
      );
      if (tag.startsWith('__hydrabox.') || isReservedProxyTag(tag)) {
        throw FormatException(
          'Profile "$id" uses the reserved runtime tag "$tag"',
        );
      }
      final entryKey = _entryKey(section, tag);
      if (!profileEntrypoints.add(entryKey)) {
        throw FormatException(
          'Multiple HydraBox profiles reference $section tag "$tag"',
        );
      }
      final nativeEntry = nativeEntries[entryKey];
      if (nativeEntry == null) {
        throw FormatException(
          'Profile "$id" entrypoint $section tag "$tag" does not exist',
        );
      }
      final type = nativeEntry['type']?.toString().trim().toLowerCase() ?? '';
      if (type.isEmpty || _nonProfileOutboundTypes.contains(type)) {
        throw FormatException(
          'Profile "$id" entrypoint type "$type" is not directly selectable',
        );
      }
      if (section == 'outbounds' && type == 'wireguard') {
        throw FormatException(
          'Profile "$id" must reference a WireGuard endpoint, not the '
          'removed legacy outbound form',
        );
      }

      final countryValue = profileMap['country'];
      final country = _normalizeCountry(
        countryValue is String ? countryValue : null,
      );
      if (countryValue != null && country == null) {
        throw FormatException(
          'profiles[$index].country must be a two-letter code',
        );
      }
      _validateStringList(
        profileMap['tags'],
        field: 'profiles[$index].tags',
        maxItemLength: 128,
      );
      _validateStringList(
        profileMap['required_features'],
        field: 'profiles[$index].required_features',
        maxItemLength: 256,
      );
      _validateExtensionsMap(
        profileMap['extensions'],
        field: 'profiles[$index].extensions',
      );
      profiles.add(
        HydraBoxParsedProfile(
          id: id,
          name: name,
          entrypointSection: section,
          entrypointTag: tag,
          enabled: enabled,
          country: country,
          metadata: _cloneMap(profileMap),
        ),
      );
    }

    final defaultProfileId = document.containsKey('default_profile_id')
        ? _validateId(
            document['default_profile_id'],
            field: 'default_profile_id',
          )
        : null;
    if (defaultProfileId != null) {
      final profile = profiles
          .where((candidate) => candidate.id == defaultProfileId)
          .firstOrNull;
      if (profile == null) {
        throw const FormatException(
          'default_profile_id does not reference a profile',
        );
      }
      if (!profile.enabled) {
        throw const FormatException(
          'default_profile_id references a disabled profile',
        );
      }
    }

    final parsedOutbounds = SingboxConfigParser.parse(
      jsonEncode(nativeConfig),
      includeGroupOutbounds: true,
    );
    final profilesByEntrypoint = <String, HydraBoxParsedProfile>{
      for (final profile in profiles)
        if (profile.enabled)
          _entryKey(profile.entrypointSection, profile.entrypointTag): profile,
    };
    final resolvedProfiles = <String>{};
    for (final outbound in parsedOutbounds) {
      final sourceSection =
          outbound['_etonify_source_index_section']?.toString() ??
          outbound['_etonify_source_section']?.toString() ??
          '';
      final originalTag =
          outbound['_etonify_original_tag']?.toString().trim() ?? '';
      final profile =
          profilesByEntrypoint[_entryKey(sourceSection, originalTag)];
      if (profile == null) {
        // Explicit profiles, rather than graph inference, define visibility.
        outbound['_group_only'] = true;
        continue;
      }
      outbound.remove('_group_only');
      outbound['_name'] = profile.name;
      outbound['_hydrabox_profile_id'] = profile.id;
      if (profile.country != null) {
        outbound['_country_override'] = profile.country;
      }
      resolvedProfiles.add(profile.id);
    }
    final missingProfiles = profilesByEntrypoint.values
        .where((profile) => !resolvedProfiles.contains(profile.id))
        .map((profile) => profile.id)
        .toList(growable: false);
    if (missingProfiles.isNotEmpty) {
      throw FormatException(
        'Profile "${missingProfiles.first}" could not be materialized',
      );
    }

    final metadata = document['metadata'] is Map
        ? Map<String, dynamic>.from(document['metadata'] as Map)
        : const <String, dynamic>{};
    final title = metadata['name'] == null
        ? null
        : _localizedDefault(metadata['name'], field: 'metadata.name');
    final update = document['update'] is Map
        ? Map<String, dynamic>.from(document['update'] as Map)
        : const <String, dynamic>{};
    final intervalSeconds = (update['minimum_interval_seconds'] as num?)
        ?.toInt();
    final bodyMeta = <String, String>{
      if (title != null && title.isNotEmpty) 'profile-title': title,
      if (metadata['support_url'] is String)
        'support-url': metadata['support_url'] as String,
      if (metadata['homepage'] is String)
        'profile-web-page-url': metadata['homepage'] as String,
      if (intervalSeconds != null && intervalSeconds > 0)
        'profile-update-interval': ((intervalSeconds / 3600).ceil().clamp(
          1,
          168,
        )).toString(),
    };

    return HydraBoxParsedSubscription(
      outbounds: parsedOutbounds,
      nativeConfig: nativeConfig,
      profiles: profiles,
      defaultProfileId: defaultProfileId,
      bodyMeta: bodyMeta,
      sourceMetadata: {
        'format': apiVersion,
        'issuer': document['issuer'],
        'subscription_id': document['subscription_id'],
        'channel': document['channel'] ?? 'stable',
        'sequence': document['sequence'],
        if (document['issued_at'] != null) 'issued_at': document['issued_at'],
        if (document['not_before'] != null)
          'not_before': document['not_before'],
        if (document['expires_at'] != null)
          'expires_at': document['expires_at'],
        if (defaultProfileId != null && defaultProfileId.isNotEmpty)
          'default_profile_id': defaultProfileId,
        'encrypted': encrypted,
        'device_binding': encrypted,
        'key_id': ?keyId,
        'payload_sha256': sha256.convert(utf8.encode(plaintext)).toString(),
        if (document['extensions'] is Map)
          'extensions': _cloneMap(document['extensions'] as Map),
        if (document['compatibility'] is Map)
          'compatibility': _cloneMap(document['compatibility'] as Map),
        if (document['update'] is Map)
          'update': _cloneMap(document['update'] as Map),
      },
    );
  }

  static void _validateEnvelope(Map<String, dynamic> document) {
    final api = document['api_version']?.toString() ?? '';
    if (api != apiVersion) {
      throw FormatException('Unsupported HydraBox api_version "$api"');
    }
    if (document['kind'] != kind) {
      throw FormatException('HydraBox kind must equal "$kind"');
    }
    _rejectUnknownKeys(document, _knownEnvelopeKeys, field: 'envelope');
    _rejectExplicitNulls(document, _knownEnvelopeKeys, field: 'envelope');

    final issuerRaw = document['issuer'];
    final issuerValue = issuerRaw is String ? issuerRaw : '';
    final issuer = Uri.tryParse(issuerValue);
    if (issuer == null ||
        issuerValue != issuerValue.trim() ||
        !issuerValue.startsWith('https://') ||
        issuer.scheme != 'https' ||
        issuer.host.isEmpty ||
        issuer.userInfo.isNotEmpty ||
        RegExp(r'^https://[^/?#]*@').hasMatch(issuerValue) ||
        (issuer.path.isNotEmpty && issuer.path != '/') ||
        issuer.hasQuery ||
        issuer.hasFragment) {
      throw const FormatException('issuer must be an HTTPS origin URL');
    }
    _validateId(document['subscription_id'], field: 'subscription_id');
    _validateId(document['channel'] ?? 'stable', field: 'channel');

    final sequence = document['sequence'];
    if (sequence is! int || sequence < 0 || sequence > _maxSafeInteger) {
      throw const FormatException(
        'sequence must be an integer between 0 and 2^53-1',
      );
    }
    final issuedAt = _validateTimestamp(
      document,
      'issued_at',
      required: true,
    )!.toUtc();
    final notBefore =
        _validateTimestamp(document, 'not_before')?.toUtc() ?? issuedAt;
    final expiresAt = _validateTimestamp(document, 'expires_at')?.toUtc();
    if (notBefore.isBefore(issuedAt.subtract(const Duration(minutes: 10)))) {
      throw const FormatException('not_before is earlier than issued_at');
    }
    if (expiresAt != null && !expiresAt.isAfter(notBefore)) {
      throw const FormatException('expires_at must be after not_before');
    }

    _validateMetadata(document['metadata']);
    _validateCompatibility(document['compatibility']);
    _validateUpdate(document['update']);
    final extensions = _validateExtensionsMap(
      document['extensions'],
      field: 'extensions',
    );
    final requiredExtensions = _validateStringList(
      document['required_extensions'],
      field: 'required_extensions',
      maxItemLength: 256,
    );
    for (final name in requiredExtensions) {
      _validateExtensionName(name, field: 'required_extensions');
      if (!extensions.containsKey(name)) {
        throw FormatException(
          'Required extension "$name" has no extensions entry',
        );
      }
      // v1 has no built-in must-understand extension handlers yet.
      throw FormatException('Unsupported required extension "$name"');
    }
  }

  static void _validateMetadata(dynamic value) {
    if (value == null) return;
    if (value is! Map) {
      throw const FormatException('metadata must be an object');
    }
    final metadata = Map<String, dynamic>.from(value);
    _rejectUnknownKeys(metadata, const {
      'name',
      'description',
      'homepage',
      'support_url',
      'tags',
      'extensions',
    }, field: 'metadata');
    _rejectExplicitNulls(metadata, const {
      'name',
      'description',
      'homepage',
      'support_url',
      'tags',
      'extensions',
    }, field: 'metadata');
    if (metadata.containsKey('name')) {
      _localizedDefault(metadata['name'], field: 'metadata.name');
    }
    if (metadata.containsKey('description')) {
      _localizedDefault(metadata['description'], field: 'metadata.description');
    }
    for (final key in const ['homepage', 'support_url']) {
      final raw = metadata[key];
      if (raw == null) continue;
      _validateHttpUrl(raw, field: 'metadata.$key', requireHttps: true);
    }
    _validateStringList(
      metadata['tags'],
      field: 'metadata.tags',
      maxItemLength: 128,
    );
    _validateExtensionsMap(
      metadata['extensions'],
      field: 'metadata.extensions',
    );
  }

  static void _validateCompatibility(dynamic value) {
    if (value == null) return;
    if (value is! Map) {
      throw const FormatException('compatibility must be an object');
    }
    final compatibility = Map<String, dynamic>.from(value);
    _rejectUnknownKeys(compatibility, const {
      'client',
      'core',
      'extensions',
    }, field: 'compatibility');
    _rejectExplicitNulls(compatibility, const {
      'client',
      'core',
      'extensions',
    }, field: 'compatibility');
    final clientValue = compatibility['client'];
    if (clientValue != null) {
      if (clientValue is! Map) {
        throw const FormatException('compatibility.client must be an object');
      }
      final client = Map<String, dynamic>.from(clientValue);
      _rejectUnknownKeys(client, const {
        'min_version',
        'required_features',
      }, field: 'compatibility.client');
      _rejectExplicitNulls(client, const {
        'min_version',
        'required_features',
      }, field: 'compatibility.client');
      final minVersion = client['min_version'];
      if (minVersion != null &&
          (minVersion is! String || minVersion.trim().isEmpty)) {
        throw const FormatException(
          'compatibility.client.min_version must be a non-empty string',
        );
      }
      _validateStringList(
        client['required_features'],
        field: 'compatibility.client.required_features',
        maxItemLength: 256,
      );
    }
    final coreValue = compatibility['core'];
    if (coreValue != null) {
      if (coreValue is! Map) {
        throw const FormatException('compatibility.core must be an object');
      }
      final core = Map<String, dynamic>.from(coreValue);
      _rejectUnknownKeys(core, const {
        'id',
        'version_range',
        'required_features',
      }, field: 'compatibility.core');
      _rejectExplicitNulls(core, const {
        'id',
        'version_range',
        'required_features',
      }, field: 'compatibility.core');
      if (core['id'] != null && core['id'] != 'io.hydrabox.hydracore') {
        throw const FormatException(
          'compatibility.core.id must equal "io.hydrabox.hydracore"',
        );
      }
      final versionRange = core['version_range'];
      if (versionRange != null &&
          (versionRange is! String || versionRange.trim().isEmpty)) {
        throw const FormatException(
          'compatibility.core.version_range must be a non-empty string',
        );
      }
      _validateStringList(
        core['required_features'],
        field: 'compatibility.core.required_features',
        maxItemLength: 256,
      );
    }
    _validateExtensionsMap(
      compatibility['extensions'],
      field: 'compatibility.extensions',
    );
  }

  static void _validateUpdate(dynamic value) {
    if (value == null) return;
    if (value is! Map) {
      throw const FormatException('update must be an object');
    }
    final update = Map<String, dynamic>.from(value);
    _rejectUnknownKeys(update, const {
      'url',
      'minimum_interval_seconds',
      'extensions',
    }, field: 'update');
    _rejectExplicitNulls(update, const {
      'url',
      'minimum_interval_seconds',
      'extensions',
    }, field: 'update');
    if (!update.containsKey('url')) {
      throw const FormatException('update.url is required');
    }
    _validateHttpUrl(update['url'], field: 'update.url', requireHttps: true);
    final interval = update['minimum_interval_seconds'];
    if (interval != null &&
        (interval is! int || interval < 900 || interval > 604800)) {
      throw const FormatException(
        'update.minimum_interval_seconds must be 900..604800',
      );
    }
    _validateExtensionsMap(update['extensions'], field: 'update.extensions');
  }

  static void _validateRuntimeOwnership(dynamic value) {
    if (value == null) return;
    if (value is! Map) {
      throw const FormatException('runtime.ownership must be an object');
    }
    final ownership = Map<String, dynamic>.from(value);
    const allowed = {
      'inbounds': 'client',
      'route_final': 'selected-profile',
      'dns': 'merge-safe',
      'route_rules': 'merge-safe',
      'log': 'client-overlay',
      'global': 'client-overlay',
    };
    if (ownership.length != allowed.length ||
        !allowed.keys.every(ownership.containsKey)) {
      throw const FormatException(
        'runtime.ownership must contain all fixed v1 ownership fields',
      );
    }
    for (final entry in ownership.entries) {
      final expected = allowed[entry.key];
      if (expected == null) {
        throw FormatException('Unknown runtime.ownership field "${entry.key}"');
      }
      if (entry.value != expected) {
        throw FormatException(
          'runtime.ownership.${entry.key} must equal "$expected"',
        );
      }
    }
  }

  /// Rejects runtime capabilities that would let a remote subscription open
  /// listeners, start services, enable experimental controllers, or consume
  /// local files/processes without an explicit user-consent boundary.
  ///
  /// Protocol objects remain lossless in storage. Activation additionally
  /// applies the installed HydraCore's versioned type manifest and reference
  /// graph policy, so unknown future types are retained but fail closed until
  /// explicitly classified by a compatible core.
  static void _validateRuntimeDocumentSafety(Map<String, dynamic> config) {
    const securitySensitiveTopLevelKeys = {
      'inbounds',
      'outbounds',
      'endpoints',
      'services',
      'experimental',
      'providers',
      'log',
      'ntp',
      'route',
      'dns',
      'global',
    };
    final seenFoldedTopLevelKeys = <String>{};
    for (final rawKey in config.keys) {
      final key = rawKey.toString();
      final folded = key.toLowerCase();
      if (!securitySensitiveTopLevelKeys.contains(folded)) continue;
      if (key != folded || !seenFoldedTopLevelKeys.add(folded)) {
        throw FormatException(
          'runtime.document.$key uses an ambiguous case-insensitive core '
          'field name; use canonical "$folded" exactly once',
        );
      }
    }

    void rejectSection(String key) {
      if (config.containsKey(key)) {
        throw FormatException(
          'runtime.document.$key requires an explicit local consent grant',
        );
      }
    }

    rejectSection('inbounds');
    rejectSection('services');
    rejectSection('experimental');

    bool hasValue(dynamic value) {
      if (value == null || value == false) return false;
      if (value is num) return value != 0;
      if (value is String) return value.trim().isNotEmpty;
      if (value is List) return value.isNotEmpty;
      if (value is Map) return value.isNotEmpty;
      return true;
    }

    void rejectField(Map value, String key, String field) {
      if (hasValue(value[key])) {
        throw FormatException('$field.$key requires explicit local consent');
      }
    }

    final log = config['log'];
    if (log != null && log is! Map) {
      throw const FormatException('runtime.document.log must be an object');
    }
    if (log is Map) {
      rejectField(log, 'output', 'runtime.document.log');
    }
    final global = config['global'];
    if (global != null && global is! Map) {
      throw const FormatException('runtime.document.global must be an object');
    }

    final ntp = config['ntp'];
    if (ntp != null && ntp is! Map) {
      throw const FormatException('runtime.document.ntp must be an object');
    }
    if (ntp is Map) {
      rejectField(ntp, 'write_to_system', 'runtime.document.ntp');
      rejectField(ntp, 'bind_interface', 'runtime.document.ntp');
      rejectField(ntp, 'routing_mark', 'runtime.document.ntp');
      rejectField(ntp, 'netns', 'runtime.document.ntp');
    }

    void rejectLocalBackedEntries(dynamic value, String field) {
      if (value == null) return;
      if (value is! List) {
        throw FormatException('$field must be an array');
      }
      for (var index = 0; index < value.length; index++) {
        final entry = value[index];
        if (entry is! Map) {
          throw FormatException('$field[$index] must be an object');
        }
        final normalized = Map<String, dynamic>.from(entry);
        for (final rawKey in normalized.keys) {
          final key = rawKey.toString();
          final folded = key.toLowerCase();
          if (const {'type', 'tag', 'path', 'url'}.contains(folded) &&
              key != folded) {
            throw FormatException(
              '$field[$index].$key must use canonical field name "$folded"',
            );
          }
        }
        final type = normalized['type'];
        final normalizedType = type is String ? type.trim().toLowerCase() : '';
        if (type != null && type is! String) {
          throw FormatException('$field[$index].type must be a string');
        }
        if (normalizedType == 'local') {
          throw FormatException(
            '$field[$index] local resources require explicit consent',
          );
        }
        if (!const {'', 'inline', 'remote'}.contains(normalizedType)) {
          throw FormatException(
            '$field[$index] provider/resource type "$normalizedType" '
            'requires an updated permission policy',
          );
        }
        if (normalizedType == 'remote') {
          _validateHttpUrl(
            normalized['url'],
            field: '$field[$index].url',
            requireHttps: true,
          );
        }
        final path = normalized['path'];
        if (path != null && path.toString().trim().isNotEmpty) {
          throw FormatException(
            '$field[$index].path requires explicit local consent',
          );
        }
      }
    }

    void rejectClientOwnedTags(
      dynamic value, {
      required String field,
      required Set<String> reservedTags,
    }) {
      if (value == null) return;
      if (value is! List) {
        throw FormatException('$field must be an array');
      }
      final seenTags = <String>{};
      for (var index = 0; index < value.length; index++) {
        final entry = value[index];
        if (entry is! Map) {
          throw FormatException('$field[$index] must be an object');
        }
        final rawTag = entry['tag'];
        if (rawTag == null) continue;
        final tag = _validateNativeTag(rawTag, field: '$field[$index].tag');
        if (!seenTags.add(tag)) {
          throw FormatException('Duplicate $field tag "$tag"');
        }
        if (tag.startsWith('__hydrabox.') || reservedTags.contains(tag)) {
          throw FormatException(
            '$field[$index].tag "$tag" is reserved by HydraBox',
          );
        }
      }
    }

    const localIdentityRuleKeys = {
      'process_name',
      'process_path',
      'process_path_regex',
      'package_name',
      'user',
      'user_id',
      'network_type',
      'network_is_expensive',
      'network_is_constrained',
      'wifi_ssid',
      'wifi_bssid',
      'interface_address',
      'network_interface_address',
      'default_interface_address',
      'preferred_by',
    };

    void rejectLocalIdentityRuleFields(dynamic value, String field) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          if (localIdentityRuleKeys.contains(key.toLowerCase())) {
            throw FormatException(
              '$field.$key requires explicit local inspection consent',
            );
          }
          rejectLocalIdentityRuleFields(entry.value, '$field.$key');
        }
      } else if (value is List) {
        for (var index = 0; index < value.length; index++) {
          rejectLocalIdentityRuleFields(value[index], '$field[$index]');
        }
      }
    }

    rejectLocalBackedEntries(config['providers'], 'runtime.document.providers');
    final route = config['route'];
    if (route != null && route is! Map) {
      throw const FormatException('runtime.document.route must be an object');
    }
    if (route is Map) {
      for (final rawKey in route.keys) {
        final key = rawKey.toString();
        final folded = key.toLowerCase();
        if (const {
              'rule_set',
              'geoip',
              'geosite',
              'find_process',
              'auto_detect_interface',
              'override_android_vpn',
              'default_interface',
              'default_mark',
            }.contains(folded) &&
            key != folded) {
          throw FormatException(
            'runtime.document.route.$key must use canonical field name '
            '"$folded"',
          );
        }
      }
      rejectLocalBackedEntries(
        route['rule_set'],
        'runtime.document.route.rule_set',
      );
      rejectClientOwnedTags(
        route['rule_set'],
        field: 'runtime.document.route.rule_set',
        reservedTags: _appOwnedRouteRuleSetTags,
      );
      rejectLocalIdentityRuleFields(
        route['rules'],
        'runtime.document.route.rules',
      );
      rejectLocalIdentityRuleFields(
        route['rule_set'],
        'runtime.document.route.rule_set',
      );
      for (final key in const ['geoip', 'geosite']) {
        final database = route[key];
        if (database == null) continue;
        if (database is! Map) {
          throw FormatException(
            'runtime.document.route.$key must be an object',
          );
        }
        rejectField(database, 'path', 'runtime.document.route.$key');
        if (database['download_url'] != null) {
          _validateHttpUrl(
            database['download_url'],
            field: 'runtime.document.route.$key.download_url',
            requireHttps: true,
          );
        }
      }
      for (final key in const [
        'find_process',
        'auto_detect_interface',
        'override_android_vpn',
        'default_interface',
        'default_mark',
      ]) {
        rejectField(route, key, 'runtime.document.route');
      }
    }

    final dns = config['dns'];
    if (dns != null && dns is! Map) {
      throw const FormatException('runtime.document.dns must be an object');
    }
    if (dns is Map) {
      for (final rawKey in dns.keys) {
        final key = rawKey.toString();
        if (key.toLowerCase() == 'servers' && key != 'servers') {
          throw FormatException(
            'runtime.document.dns.$key must use canonical field name '
            '"servers"',
          );
        }
      }
      final servers = dns['servers'];
      rejectLocalIdentityRuleFields(dns['rules'], 'runtime.document.dns.rules');
      if (servers != null && servers is! List) {
        throw const FormatException(
          'runtime.document.dns.servers must be an array',
        );
      }
      if (servers is List) {
        final seenServerTags = <String>{};
        for (var index = 0; index < servers.length; index++) {
          final server = servers[index];
          if (server is! Map) {
            throw FormatException(
              'runtime.document.dns.servers[$index] must be an object',
            );
          }
          for (final rawKey in server.keys) {
            final key = rawKey.toString();
            final folded = key.toLowerCase();
            if (const {'type', 'tag', 'path'}.contains(folded) &&
                key != folded) {
              throw FormatException(
                'runtime.document.dns.servers[$index].$key must use '
                'canonical field name "$folded"',
              );
            }
          }
          final type = server['type']?.toString().trim().toLowerCase() ?? '';
          final rawTag = server['tag'];
          if (rawTag != null) {
            final tag = _validateNativeTag(
              rawTag,
              field: 'runtime.document.dns.servers[$index].tag',
            );
            if (!seenServerTags.add(tag)) {
              throw FormatException(
                'Duplicate runtime.document.dns server tag "$tag"',
              );
            }
            if (tag.startsWith('__hydrabox.') ||
                _appOwnedDnsServerTags.contains(tag)) {
              throw FormatException(
                'DNS server tag "$tag" is reserved by HydraBox',
              );
            }
          }
          if (type == 'hosts') {
            rejectField(server, 'path', 'runtime.document.dns.servers[$index]');
          }
          if (type == 'dhcp') {
            throw FormatException(
              'runtime.document.dns.servers[$index] DHCP access requires '
              'explicit local consent',
            );
          }
        }
      }
    }

    const localCapabilityKeys = {
      'bind_interface',
      'default_interface',
      'default_mark',
      'binary_path',
      'certificate_path',
      'config_path',
      'client_certificate_path',
      'client_key_path',
      'command',
      'database_path',
      'data_directory',
      'executable',
      'inet4_bind_address',
      'inet6_bind_address',
      'key_path',
      'net_ns',
      'netns',
      'network_namespace',
      'output',
      'plugin',
      'plugin_opts',
      'plugin_path',
      'pre_shared_key_path',
      'private_key_path',
      'relay_server_port',
      'routing_mark',
      'script',
      'socket_path',
      'state_directory',
      'storage_path',
      'system_interface_mtu',
      'system_interface_name',
      'working_directory',
      'network_type',
      'network_strategy',
      'fallback_network_type',
      'network_interface',
      'interface_name',
    };
    const presenceLocalCapabilityKeys = {
      // A zero listen port still requests an ephemeral local listener.
      'listen',
      'listen_port',
      'listen_ports',
    };
    const privilegedBooleanKeys = {
      'auto_detect_interface',
      'bind_address_no_port',
      'disable_pauses',
      'find_process',
      'override_android_vpn',
      'system',
      'system_interface',
      'write_to_system',
    };

    void walk(dynamic value, String field) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          final normalizedKey = key.toLowerCase();
          final child = entry.value;
          final reservedLocalSuffix =
              normalizedKey.endsWith('_path') ||
              normalizedKey.endsWith('_file') ||
              normalizedKey.endsWith('_directory') ||
              normalizedKey.endsWith('_socket') ||
              normalizedKey.endsWith('_database');
          if (presenceLocalCapabilityKeys.contains(normalizedKey) &&
              value.containsKey(entry.key) &&
              child != null) {
            throw FormatException(
              '$field.$key requires explicit local consent',
            );
          }
          if ((localCapabilityKeys.contains(normalizedKey) ||
                  reservedLocalSuffix) &&
              hasValue(child)) {
            throw FormatException(
              '$field.$key requires explicit local consent',
            );
          }
          if (privilegedBooleanKeys.contains(normalizedKey) && child == true) {
            throw FormatException(
              '$field.$key requires explicit local consent',
            );
          }
          walk(child, '$field.$key');
        }
      } else if (value is List) {
        for (var index = 0; index < value.length; index++) {
          walk(value[index], '$field[$index]');
        }
      }
    }

    walk(config, 'runtime.document');
  }

  static Map<String, Map<String, dynamic>> _indexNativeEntries(
    Map<String, dynamic> config,
  ) {
    final result = <String, Map<String, dynamic>>{};
    final sharedTags = <String>{};
    for (final section in const {'outbounds', 'endpoints'}) {
      final entries = config[section];
      if (entries == null) continue;
      if (entries is! List) {
        throw FormatException('runtime.document.$section must be an array');
      }
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        if (entry is! Map) {
          throw FormatException(
            'runtime.document.$section[$index] must be an object',
          );
        }
        final normalized = Map<String, dynamic>.from(entry);
        for (final rawKey in normalized.keys) {
          final key = rawKey.toString();
          final folded = key.toLowerCase();
          if (const {'type', 'tag'}.contains(folded) && key != folded) {
            throw FormatException(
              'runtime.document.$section[$index].$key must use canonical '
              'field name "$folded"',
            );
          }
        }
        final typeValue = normalized['type'];
        final type = typeValue is String ? typeValue : '';
        if (type.isEmpty ||
            type != type.trim() ||
            type.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
          throw FormatException(
            'runtime.document.$section[$index].type is required',
          );
        }
        final normalizedType = type.toLowerCase();
        if (section == 'endpoints' && normalizedType == 'wireguard') {
          for (final rawKey in normalized.keys) {
            final key = rawKey.toString();
            if (key.toLowerCase() == 'amnezia' && key != 'amnezia') {
              throw FormatException(
                'runtime.document.$section[$index].$key must use canonical '
                'field name "amnezia"',
              );
            }
          }
          final amnezia = normalized['amnezia'];
          if (amnezia != null && amnezia is! Map) {
            throw FormatException(
              'runtime.document.$section[$index].amnezia must be an object',
            );
          }
        }
        if (section == 'outbounds' &&
            const {'tor', 'parser'}.contains(normalizedType)) {
          throw FormatException(
            'runtime.document.$section[$index] type "$type" requires '
            'explicit local execution consent',
          );
        }
        if (section == 'endpoints' &&
            const {
              'tailscale',
              'vpn-client',
              'vpn-server',
            }.contains(normalizedType)) {
          throw FormatException(
            'runtime.document.$section[$index] type "$type" requires '
            'explicit local or reverse-tunnel consent',
          );
        }
        final tag = _validateNativeTag(
          normalized['tag'],
          field: 'runtime.document.$section[$index].tag',
        );
        if (!sharedTags.add(tag)) {
          throw FormatException(
            'Duplicate runtime tag "$tag" across outbounds/endpoints',
          );
        }
        if (tag.startsWith('__hydrabox.') || isReservedProxyTag(tag)) {
          throw FormatException(
            'Runtime tag "$tag" is reserved by the HydraBox client',
          );
        }
        result[_entryKey(section, tag)] = normalized;
      }
    }
    return result;
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> source,
    String key,
  ) {
    final value = source[key];
    if (value is! Map) {
      throw FormatException('$key must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  static void _rejectUnknownKeys(
    Map<String, dynamic> value,
    Set<String> allowed, {
    required String field,
  }) {
    final unknown = value.keys
        .where((key) => !allowed.contains(key))
        .firstOrNull;
    if (unknown != null) {
      throw FormatException(
        'Unknown HydraBox $field field "$unknown"; use extensions',
      );
    }
  }

  static void _rejectExplicitNulls(
    Map<String, dynamic> value,
    Set<String> known, {
    required String field,
  }) {
    for (final key in known) {
      if (value.containsKey(key) && value[key] == null) {
        throw FormatException('$field.$key must be omitted instead of null');
      }
    }
  }

  static List<String> _validateStringList(
    dynamic value, {
    required String field,
    required int maxItemLength,
  }) {
    if (value == null) return const [];
    if (value is! List) {
      throw FormatException('$field must be an array');
    }
    final result = <String>[];
    final unique = <String>{};
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! String ||
          item.trim().isEmpty ||
          item.length > maxItemLength) {
        throw FormatException('$field[$index] must be a non-empty string');
      }
      if (!unique.add(item)) {
        throw FormatException('$field contains duplicate value "$item"');
      }
      result.add(item);
    }
    return result;
  }

  static Map<String, dynamic> _validateExtensionsMap(
    dynamic value, {
    required String field,
  }) {
    if (value == null) return const {};
    if (value is! Map) {
      throw FormatException('$field must be an object');
    }
    final extensions = Map<String, dynamic>.from(value);
    for (final name in extensions.keys) {
      _validateExtensionName(name, field: field);
    }
    return extensions;
  }

  static void _validateExtensionName(String value, {required String field}) {
    if (value.isEmpty ||
        value.length > 256 ||
        !_extensionNamePattern.hasMatch(value)) {
      throw FormatException('$field contains invalid extension name "$value"');
    }
  }

  static Uri _validateHttpUrl(
    dynamic value, {
    required String field,
    required bool requireHttps,
  }) {
    if (value is! String ||
        value.isEmpty ||
        value != value.trim() ||
        (requireHttps && !value.startsWith('https://'))) {
      throw FormatException('$field must be a URL');
    }
    final uri = Uri.tryParse(value);
    final validScheme = requireHttps
        ? uri?.scheme == 'https'
        : uri?.scheme == 'https' || uri?.scheme == 'http';
    if (uri == null ||
        !validScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'^https?://[^/?#]*@').hasMatch(value) ||
        uri.hasFragment) {
      throw FormatException(
        '$field must be an ${requireHttps ? "HTTPS" : "HTTP(S)"} URL '
        'without userinfo or fragment',
      );
    }
    return uri;
  }

  static String _validateId(dynamic value, {required String field}) {
    final normalized = value is String ? value : '';
    if (normalized.isEmpty ||
        normalized != normalized.trim() ||
        normalized.length > _maxIdLength ||
        !_idPattern.hasMatch(normalized)) {
      throw FormatException('$field is not a valid HydraBox identifier');
    }
    return normalized;
  }

  static String _validateNativeTag(dynamic value, {required String field}) {
    final tag = value is String ? value : '';
    if (tag.isEmpty ||
        tag != tag.trim() ||
        tag.length > _maxTagLength ||
        tag.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      throw FormatException('$field is invalid');
    }
    return tag;
  }

  static String _localizedDefault(dynamic value, {required String field}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.value is! String || (entry.value as String).trim().isEmpty) {
          throw FormatException('$field translations must be strings');
        }
      }
      final defaultValue = value['default'];
      if (defaultValue is String && defaultValue.trim().isNotEmpty) {
        return defaultValue.trim();
      }
    }
    throw FormatException('$field must contain non-empty default text');
  }

  static DateTime? _validateTimestamp(
    Map<String, dynamic> document,
    String key, {
    bool required = false,
  }) {
    final value = document[key];
    if (value == null && !required) return null;
    final match = value is String ? _rfc3339Pattern.firstMatch(value) : null;
    if (match == null) {
      throw FormatException('$key must be an RFC 3339 timestamp');
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final offsetHour = match.group(9) == null ? 0 : int.parse(match.group(9)!);
    final offsetMinute = match.group(10) == null
        ? 0
        : int.parse(match.group(10)!);
    final leapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final daysInMonth = switch (month) {
      2 => leapYear ? 29 : 28,
      4 || 6 || 9 || 11 => 30,
      >= 1 && <= 12 => 31,
      _ => 0,
    };
    if (day < 1 ||
        day > daysInMonth ||
        hour > 23 ||
        minute > 59 ||
        second > 59 ||
        offsetHour > 23 ||
        offsetMinute > 59) {
      throw FormatException('$key must be an RFC 3339 timestamp');
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$key must be an RFC 3339 timestamp');
    }
    return parsed;
  }

  static String? _normalizeCountry(String? value) {
    final normalized = value?.trim().toUpperCase() ?? '';
    return RegExp(r'^[A-Z]{2}$').hasMatch(normalized) ? normalized : null;
  }

  static String _entryKey(String section, String tag) => '$section\u0000$tag';
}

Map<String, dynamic> _cloneMap(Map source) => {
  for (final entry in source.entries)
    entry.key.toString(): _cloneValue(entry.value),
};

dynamic _cloneValue(dynamic value) {
  if (value is Map) return _cloneMap(value);
  if (value is List) return value.map(_cloneValue).toList(growable: true);
  return value;
}
