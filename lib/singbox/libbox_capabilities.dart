import 'dart:convert';

enum UrlTestCompletionModel { rpcCompletion, groupEvents }

/// Describes the native features available to this client build.
class LibboxCapabilities {
  const LibboxCapabilities({
    required this.apiVersion,
    this.coreId = '',
    this.coreName = '',
    required this.coreVersion,
    this.upstreamProject = '',
    required this.supportsTargetedUrlTest,
    this.supportsPreconnectUrlTest = false,
    required this.supportsGroupUrlTestSessions,
    required this.supportsStructuredProbeErrors,
    required this.supportsOutboundExternalInfo,
    required this.supportsMixedRoutingOutbound,
    required this.supportsUrlTestTimeout,
    required this.supportsUrlTestConcurrency,
    required this.supportsUrlTestDeadline,
    required this.supportsUrlTestForce,
    required this.supportsUrlTestUnavailableCheckInterval,
    required this.supportsUrlTestMethod,
    required this.supportsUrlTestInterruptDelayThreshold,
    required this.urlTestCompletionModel,
    required this.supportsConfigCheck,
    required this.supportsCloseConnections,
    required this.supportsRealitySpiderX,
    required this.tunStacks,
    this.remotePolicyVersion = 0,
    this.remoteSafeTopLevelFields = const <String>{},
    this.remoteSafeOutboundTypes = const <String>{},
    this.remoteSafeEndpointTypes = const <String>{},
    this.remoteSafeDnsServerTypes = const <String>{},
    this.remoteSafeProviderTypes = const <String>{},
  });

  static const hydraCoreId = 'io.hydrabox.hydracore';
  static const supportedApiVersion = 1;
  static const supportedRemotePolicyVersion = 1;

  static const bundledLegacy = LibboxCapabilities(
    apiVersion: 0,
    coreVersion: '',
    supportsTargetedUrlTest: false,
    supportsGroupUrlTestSessions: false,
    supportsStructuredProbeErrors: false,
    supportsOutboundExternalInfo: false,
    supportsMixedRoutingOutbound: false,
    supportsUrlTestTimeout: false,
    supportsUrlTestConcurrency: false,
    supportsUrlTestDeadline: false,
    supportsUrlTestForce: false,
    supportsUrlTestUnavailableCheckInterval: false,
    supportsUrlTestMethod: false,
    supportsUrlTestInterruptDelayThreshold: false,
    urlTestCompletionModel: UrlTestCompletionModel.groupEvents,
    supportsConfigCheck: false,
    supportsCloseConnections: false,
    // The unversioned libbox bundled with Etonify 0.2.1 accepted spider_x.
    supportsRealitySpiderX: true,
    tunStacks: <String>{'system', 'gvisor', 'mixed'},
    // An unavailable/malformed capability handshake is not a trusted remote
    // execution contract. Legacy local configurations still use these feature
    // defaults, while HydraBox activation fails closed until the exact installed
    // HydraCore publishes a versioned policy and config validator.
  );

  /// Parses the versioned HydraCore contract (and its legacy Etonify alias).
  ///
  /// Every optional capability fails closed. An absent bridge, malformed JSON,
  /// or an unversioned document preserves the behavior of the bundled legacy
  /// core instead of guessing what a replacement core supports.
  static LibboxCapabilities parseOrLegacy(String? raw) {
    final normalized = raw?.trim() ?? '';
    if (normalized.isEmpty) return bundledLegacy;
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is! Map) return bundledLegacy;
      final json = decoded.map((key, value) => MapEntry(key.toString(), value));
      final apiVersion = _readInt(json, 'api_version');
      if (apiVersion <= 0) return bundledLegacy;
      final completionModel = switch (_readString(
        json,
        'url_test_completion_model',
      )) {
        'rpc_completion' => UrlTestCompletionModel.rpcCompletion,
        _ => UrlTestCompletionModel.groupEvents,
      };
      return LibboxCapabilities(
        apiVersion: apiVersion,
        coreId: _readString(json, 'core_id'),
        coreName: _readString(json, 'core_name'),
        coreVersion: _readString(json, 'core_version'),
        upstreamProject: _readString(json, 'upstream_project'),
        supportsTargetedUrlTest: _readBool(json, 'supports_targeted_url_test'),
        supportsPreconnectUrlTest: _readBool(
          json,
          'supports_preconnect_url_test',
        ),
        supportsGroupUrlTestSessions: _readBool(
          json,
          'supports_group_url_test_sessions',
        ),
        supportsStructuredProbeErrors: _readBool(
          json,
          'supports_structured_probe_errors',
        ),
        supportsOutboundExternalInfo: _readBool(
          json,
          'supports_outbound_external_info',
        ),
        supportsMixedRoutingOutbound: _readBool(
          json,
          'supports_mixed_routing_outbound',
        ),
        supportsUrlTestTimeout: _readBool(json, 'supports_url_test_timeout'),
        supportsUrlTestConcurrency: _readBool(
          json,
          'supports_url_test_concurrency',
        ),
        supportsUrlTestDeadline: _readBool(json, 'supports_url_test_deadline'),
        supportsUrlTestForce: _readBool(json, 'supports_url_test_force'),
        supportsUrlTestUnavailableCheckInterval: _readBool(
          json,
          'supports_url_test_unavailable_check_interval',
        ),
        supportsUrlTestMethod: _readBool(json, 'supports_url_test_method'),
        supportsUrlTestInterruptDelayThreshold: _readBool(
          json,
          'supports_url_test_interrupt_delay_threshold',
        ),
        urlTestCompletionModel: completionModel,
        supportsConfigCheck: _readBool(json, 'supports_config_check'),
        supportsCloseConnections: _readBool(json, 'supports_close_connections'),
        supportsRealitySpiderX: _readBool(json, 'supports_reality_spider_x'),
        tunStacks: _readStringSet(json, 'tun_stacks'),
        remotePolicyVersion: _readInt(json, 'remote_policy_version'),
        remoteSafeTopLevelFields: _readStringSet(
          json,
          'remote_safe_top_level_fields',
        ),
        remoteSafeOutboundTypes: _readStringSet(
          json,
          'remote_safe_outbound_types',
        ),
        remoteSafeEndpointTypes: _readStringSet(
          json,
          'remote_safe_endpoint_types',
        ),
        remoteSafeDnsServerTypes: _readStringSet(
          json,
          'remote_safe_dns_server_types',
        ),
        remoteSafeProviderTypes: _readStringSet(
          json,
          'remote_safe_provider_types',
        ),
      );
    } on FormatException {
      return bundledLegacy;
    } on TypeError {
      return bundledLegacy;
    }
  }

  static bool _readBool(Map<String, Object?> json, String key) =>
      json[key] == true;

  static int _readInt(Map<String, Object?> json, String key) {
    final value = json[key];
    return value is int ? value : 0;
  }

  static String _readString(Map<String, Object?> json, String key) {
    final value = json[key];
    return value is String ? value.trim() : '';
  }

  static Set<String> _readStringSet(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! List) return const <String>{};
    return Set<String>.unmodifiable(
      value
          .whereType<String>()
          .map((entry) => entry.trim().toLowerCase())
          .where((entry) => entry.isNotEmpty),
    );
  }

  final int apiVersion;
  final String coreId;
  final String coreName;
  final String coreVersion;
  final String upstreamProject;
  final bool supportsTargetedUrlTest;
  final bool supportsPreconnectUrlTest;
  final bool supportsGroupUrlTestSessions;
  final bool supportsStructuredProbeErrors;
  final bool supportsOutboundExternalInfo;
  final bool supportsMixedRoutingOutbound;
  final bool supportsUrlTestTimeout;
  final bool supportsUrlTestConcurrency;
  final bool supportsUrlTestDeadline;
  final bool supportsUrlTestForce;
  final bool supportsUrlTestUnavailableCheckInterval;
  final bool supportsUrlTestMethod;
  final bool supportsUrlTestInterruptDelayThreshold;
  final UrlTestCompletionModel urlTestCompletionModel;
  final bool supportsConfigCheck;
  final bool supportsCloseConnections;
  final bool supportsRealitySpiderX;
  final Set<String> tunStacks;
  final int remotePolicyVersion;
  final Set<String> remoteSafeTopLevelFields;
  final Set<String> remoteSafeOutboundTypes;
  final Set<String> remoteSafeEndpointTypes;
  final Set<String> remoteSafeDnsServerTypes;
  final Set<String> remoteSafeProviderTypes;

  bool get hasVersionedContract => apiVersion == supportedApiVersion;

  bool supportsTunStack(String value) =>
      tunStacks.contains(value.trim().toLowerCase());

  bool get hasRemoteSafetyManifest =>
      hasVersionedContract &&
      remotePolicyVersion == supportedRemotePolicyVersion &&
      remoteSafeTopLevelFields.isNotEmpty;
}
