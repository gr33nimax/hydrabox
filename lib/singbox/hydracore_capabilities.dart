import 'dart:convert';

enum UrlTestCompletionModel { rpcCompletion, groupEvents }

/// Strict projection of `HydraCoreCapabilities()` API v2.
class HydraCoreCapabilities {
  const HydraCoreCapabilities({
    required this.apiVersion,
    this.coreId = hydraCoreId,
    this.coreName = 'HydraCore',
    this.coreRole = 'client',
    required this.coreVersion,
    this.supportsTargetedUrlTest = true,
    this.supportsPreconnectUrlTest = true,
    this.supportsGroupUrlTestSessions = true,
    this.supportsStructuredProbeErrors = true,
    this.supportsOutboundExternalInfo = true,
    this.supportsOutboundExternalInfoFallback = true,
    this.supportsMixedRoutingOutbound = true,
    this.supportsUrlTestTimeout = true,
    this.supportsUrlTestConcurrency = true,
    this.supportsUrlTestDeadline = true,
    this.supportsUrlTestForce = true,
    this.supportsUrlTestUnavailableCheckInterval = true,
    this.supportsUrlTestMethod = true,
    this.supportsUrlTestInterruptDelayThreshold = true,
    this.urlTestCompletionModel = UrlTestCompletionModel.rpcCompletion,
    this.supportsConfigCheck = true,
    this.supportsCloseConnections = true,
    this.supportsRealitySpiderX = true,
    this.supportsRuntimeSnapshot = true,
    this.supportsRuntimeEvents = true,
    this.supportsManagedUrlTestSessions = true,
    this.supportsSubscriptionJwe = true,
    this.supportsXhttp = true,
    this.supportsVlessEncryption = true,
    this.supportsRmux = true,
    this.supportsCall = true,
    this.supportsCallVkParasite = true,
    this.supportsCallVkParasiteClient = true,
    this.supportsCallVkParasiteServer = false,
    this.supportsCallVkTelemetry = true,
    this.supportsCallVkEightLaneKcp = true,
    this.supportsCallVkPreKcpAdmission = true,
    this.supportsCallVkRelayFlowControl = true,
    this.callVkParasiteWireMin = 5,
    this.callVkParasiteWireMax = 5,
    this.amneziaVersion = 3,
    this.tunStacks = const {'system', 'gvisor', 'mixed'},
    this.inboundProtocols = const <String>{},
    this.outboundProtocols = const <String>{},
    this.endpointProtocols = const <String>{},
    this.callPlatforms = const <String>{},
    this.callModes = const {'vk_parasite'},
    this.validationProfiles = const {'local', 'remote_v2'},
    this.subscriptionContracts = const {2},
    this.subscriptionMediaTypes = const {
      'application/vnd.hydra.subscription+json',
      'application/jose+json',
    },
    this.remotePolicyVersion = supportedRemotePolicyVersion,
    this.remoteSafeTopLevelFields = const {
      r'$schema',
      'inbounds',
      'outbounds',
      'endpoints',
    },
    this.remoteSafeInboundTypes = const <String>{},
    this.remoteSafeOutboundTypes = const <String>{},
    this.remoteSafeEndpointTypes = const {'wireguard'},
    this.remoteSafeDnsServerTypes = const <String>{},
    this.remoteSafeProviderTypes = const <String>{},
    this.reservedTagPrefixes = const {'__hydra.'},
    this.runtimeVersion = 1,
    this.snapshotSchemaVersion = 1,
    this.minimumEventIntervalMillis = 250,
    this.maximumEventIntervalMillis = 30000,
    this.retainedUrlTestSessions = 64,
  });

  static const hydraCoreId = 'io.hydrabox.hydracore';
  static const supportedApiVersion = 2;
  static const supportedRemotePolicyVersion = 2;

  /// Expected release surface used by pure-Dart code and test fakes.
  static const requiredV2 = HydraCoreCapabilities(
    apiVersion: supportedApiVersion,
    coreVersion: 'v1.13.16-extended-hydracore.11-debug.14',
    outboundProtocols: {
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
    },
    endpointProtocols: {'wireguard'},
    callPlatforms: {'vk'},
    remoteSafeOutboundTypes: {
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
    },
  );

  static HydraCoreCapabilities parseStrict(String? raw) {
    final normalized = raw?.trim() ?? '';
    if (normalized.isEmpty) {
      throw const FormatException('HydraCore capabilities are unavailable');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(normalized);
    } on FormatException {
      throw const FormatException('HydraCore capabilities are invalid JSON');
    }
    if (decoded is! Map) {
      throw const FormatException('HydraCore capabilities must be an object');
    }
    final root = _stringMap(decoded);
    final identity = _requiredMap(root, 'identity');
    final features = _requiredMap(root, 'features');
    final protocols = _requiredMap(root, 'protocols');
    final remotePolicy = _requiredMap(root, 'remote_policy');
    final runtime = _requiredMap(root, 'runtime');
    final capabilities = HydraCoreCapabilities(
      apiVersion: _requiredInt(root, 'api_version'),
      coreId: _requiredString(identity, 'core_id'),
      coreName: _requiredString(identity, 'core_name'),
      coreRole: _requiredString(identity, 'role'),
      coreVersion: _requiredString(identity, 'core_version'),
      supportsTargetedUrlTest: _requiredBool(features, 'targeted_url_test'),
      supportsPreconnectUrlTest: _requiredBool(features, 'preconnect_url_test'),
      supportsGroupUrlTestSessions: _requiredBool(
        features,
        'group_url_test_sessions',
      ),
      supportsStructuredProbeErrors: _requiredBool(
        features,
        'structured_probe_errors',
      ),
      supportsOutboundExternalInfo: _requiredBool(
        features,
        'outbound_external_info',
      ),
      supportsOutboundExternalInfoFallback: _requiredBool(
        features,
        'outbound_external_info_fallback',
      ),
      supportsConfigCheck: _requiredBool(features, 'config_validation'),
      supportsRuntimeSnapshot: _requiredBool(features, 'runtime_snapshot'),
      supportsRuntimeEvents: _requiredBool(features, 'runtime_events'),
      supportsManagedUrlTestSessions: _requiredBool(
        features,
        'managed_url_test_sessions',
      ),
      supportsSubscriptionJwe: _requiredBool(features, 'subscription_jwe'),
      supportsXhttp: _requiredBool(features, 'xhttp'),
      supportsVlessEncryption: _requiredBool(features, 'vless_encryption'),
      supportsRmux: _requiredBool(features, 'rmux'),
      supportsCall: _requiredBool(features, 'call'),
      supportsCallVkParasite: _requiredBool(features, 'call_vk_parasite'),
      supportsCallVkParasiteClient: _requiredBool(
        features,
        'call_vk_parasite_client',
      ),
      supportsCallVkParasiteServer: _requiredBool(
        features,
        'call_vk_parasite_server',
      ),
      supportsCallVkTelemetry: _requiredBool(features, 'call_vk_telemetry'),
      supportsCallVkEightLaneKcp: _requiredBool(
        features,
        'call_vk_eight_lane_kcp',
      ),
      supportsCallVkPreKcpAdmission: _requiredBool(
        features,
        'call_vk_pre_kcp_admission',
      ),
      supportsCallVkRelayFlowControl: _requiredBool(
        features,
        'call_vk_relay_flow_control',
      ),
      callVkParasiteWireMin: _requiredInt(
        _requiredMap(protocols, 'call_vk_parasite_wire'),
        'min',
      ),
      callVkParasiteWireMax: _requiredInt(
        _requiredMap(protocols, 'call_vk_parasite_wire'),
        'max',
      ),
      amneziaVersion: _requiredInt(features, 'amnezia_version'),
      tunStacks: _requiredStringSet(root, 'tun_stacks'),
      inboundProtocols: _requiredStringSet(protocols, 'inbounds'),
      outboundProtocols: _requiredStringSet(protocols, 'outbounds'),
      endpointProtocols: _requiredStringSet(protocols, 'endpoints'),
      callPlatforms: _requiredStringSet(protocols, 'call_platforms'),
      callModes: _requiredStringSet(protocols, 'call_modes'),
      validationProfiles: _requiredStringSet(root, 'validation_profiles'),
      subscriptionContracts: _requiredIntSet(root, 'subscription_contracts'),
      subscriptionMediaTypes: _requiredStringSet(
        root,
        'subscription_media_types',
        lowerCase: false,
      ),
      remotePolicyVersion: _requiredInt(remotePolicy, 'version'),
      remoteSafeTopLevelFields: _requiredStringSet(
        remotePolicy,
        'safe_top_level_fields',
        lowerCase: false,
      ),
      remoteSafeInboundTypes: _requiredStringSet(
        remotePolicy,
        'safe_inbound_types',
      ),
      remoteSafeOutboundTypes: _requiredStringSet(
        remotePolicy,
        'safe_outbound_types',
      ),
      remoteSafeEndpointTypes: _requiredStringSet(
        remotePolicy,
        'safe_endpoint_types',
      ),
      remoteSafeDnsServerTypes: _requiredStringSet(
        remotePolicy,
        'safe_dns_server_types',
      ),
      remoteSafeProviderTypes: _requiredStringSet(
        remotePolicy,
        'safe_provider_types',
      ),
      reservedTagPrefixes: _requiredStringSet(
        remotePolicy,
        'reserved_tag_prefixes',
        lowerCase: false,
      ),
      runtimeVersion: _requiredInt(runtime, 'version'),
      snapshotSchemaVersion: _requiredInt(runtime, 'snapshot_schema_version'),
      minimumEventIntervalMillis: _requiredInt(
        runtime,
        'minimum_event_interval_millis',
      ),
      maximumEventIntervalMillis: _requiredInt(
        runtime,
        'maximum_event_interval_millis',
      ),
      retainedUrlTestSessions: _requiredInt(
        runtime,
        'retained_url_test_sessions',
      ),
    );
    if (!capabilities.isCompatibleRelease) {
      throw const FormatException('Installed HydraCore is incompatible');
    }
    return capabilities;
  }

  final int apiVersion;
  final String coreId;
  final String coreName;
  final String coreRole;
  final String coreVersion;
  final bool supportsTargetedUrlTest;
  final bool supportsPreconnectUrlTest;
  final bool supportsGroupUrlTestSessions;
  final bool supportsStructuredProbeErrors;
  final bool supportsOutboundExternalInfo;
  final bool supportsOutboundExternalInfoFallback;
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
  final bool supportsRuntimeSnapshot;
  final bool supportsRuntimeEvents;
  final bool supportsManagedUrlTestSessions;
  final bool supportsSubscriptionJwe;
  final bool supportsXhttp;
  final bool supportsVlessEncryption;
  final bool supportsRmux;
  final bool supportsCall;
  final bool supportsCallVkParasite;
  final bool supportsCallVkParasiteClient;
  final bool supportsCallVkParasiteServer;
  final bool supportsCallVkTelemetry;
  final bool supportsCallVkEightLaneKcp;
  final bool supportsCallVkPreKcpAdmission;
  final bool supportsCallVkRelayFlowControl;
  final int callVkParasiteWireMin;
  final int callVkParasiteWireMax;
  final int amneziaVersion;
  final Set<String> tunStacks;
  final Set<String> inboundProtocols;
  final Set<String> outboundProtocols;
  final Set<String> endpointProtocols;
  final Set<String> callPlatforms;
  final Set<String> callModes;
  final Set<String> validationProfiles;
  final Set<int> subscriptionContracts;
  final Set<String> subscriptionMediaTypes;
  final int remotePolicyVersion;
  final Set<String> remoteSafeTopLevelFields;
  final Set<String> remoteSafeInboundTypes;
  final Set<String> remoteSafeOutboundTypes;
  final Set<String> remoteSafeEndpointTypes;
  final Set<String> remoteSafeDnsServerTypes;
  final Set<String> remoteSafeProviderTypes;
  final Set<String> reservedTagPrefixes;
  final int runtimeVersion;
  final int snapshotSchemaVersion;
  final int minimumEventIntervalMillis;
  final int maximumEventIntervalMillis;
  final int retainedUrlTestSessions;

  bool get hasVersionedContract =>
      apiVersion == supportedApiVersion && coreId == hydraCoreId;

  bool get hasRemoteSafetyManifest =>
      hasVersionedContract &&
      remotePolicyVersion == supportedRemotePolicyVersion &&
      remoteSafeTopLevelFields.containsAll(const {
        r'$schema',
        'inbounds',
        'outbounds',
        'endpoints',
      }) &&
      reservedTagPrefixes.contains('__hydra.');

  bool get isCompatibleRelease =>
      hasRemoteSafetyManifest &&
      supportsConfigCheck &&
      supportsRuntimeSnapshot &&
      supportsRuntimeEvents &&
      supportsManagedUrlTestSessions &&
      supportsSubscriptionJwe &&
      supportsCall &&
      supportsCallVkParasite &&
      supportsCallVkParasiteClient &&
      !supportsCallVkParasiteServer &&
      supportsCallVkTelemetry &&
      supportsCallVkEightLaneKcp &&
      supportsCallVkPreKcpAdmission &&
      supportsCallVkRelayFlowControl &&
      coreRole == 'client' &&
      callVkParasiteWireMin == 5 &&
      callVkParasiteWireMax == 5 &&
      callPlatforms.length == 1 &&
      callPlatforms.contains('vk') &&
      callModes.length == 1 &&
      callModes.contains('vk_parasite') &&
      supportsRmux &&
      amneziaVersion >= 3 &&
      subscriptionContracts.contains(2) &&
      validationProfiles.containsAll(const {'local', 'remote_v2'}) &&
      runtimeVersion == 1 &&
      snapshotSchemaVersion == 1;

  bool supportsTunStack(String value) =>
      tunStacks.contains(value.trim().toLowerCase());
}

Map<String, Object?> _stringMap(Map<dynamic, dynamic> value) =>
    value.map((key, item) => MapEntry(key.toString(), item));

Map<String, Object?> _requiredMap(Map<String, Object?> value, String key) {
  final nested = value[key];
  if (nested is! Map) throw FormatException('Missing HydraCore field: $key');
  return _stringMap(nested);
}

String _requiredString(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item is! String || item.trim().isEmpty) {
    throw FormatException('Missing HydraCore string: $key');
  }
  return item.trim();
}

int _requiredInt(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item is! int) throw FormatException('Missing HydraCore integer: $key');
  return item;
}

bool _requiredBool(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item is! bool) throw FormatException('Missing HydraCore boolean: $key');
  return item;
}

Set<String> _requiredStringSet(
  Map<String, Object?> value,
  String key, {
  bool lowerCase = true,
}) {
  final item = value[key];
  if (item is! List || item.any((entry) => entry is! String)) {
    throw FormatException('Missing HydraCore string list: $key');
  }
  return Set<String>.unmodifiable(
    item
        .cast<String>()
        .map((entry) {
          final trimmed = entry.trim();
          return lowerCase ? trimmed.toLowerCase() : trimmed;
        })
        .where((entry) => entry.isNotEmpty),
  );
}

Set<int> _requiredIntSet(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item is! List || item.any((entry) => entry is! int)) {
    throw FormatException('Missing HydraCore integer list: $key');
  }
  return Set<int>.unmodifiable(item.cast<int>());
}
