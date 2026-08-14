import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/singbox/singbox_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/app/src/main/kotlin/io/hydrabox/client/generated/SingboxApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.hydrabox.client.generated'),
  ),
)
class RuntimeFlagsMessage {
  RuntimeFlagsMessage({
    this.wakeLockEnabled,
    this.networkHeartbeatEnabled,
    this.networkHeartbeatIntervalSeconds,
    this.performanceMode,
    this.memoryLimitEnabled,
  });

  bool? wakeLockEnabled;
  bool? networkHeartbeatEnabled;
  int? networkHeartbeatIntervalSeconds;
  String? performanceMode;
  bool? memoryLimitEnabled;
}

class NetworkInterfaceStateMessage {
  NetworkInterfaceStateMessage({
    required this.available,
    this.interfaceName,
    required this.interfaceIndex,
    required this.generation,
    this.reason,
    required this.updatedAtMillis,
  });

  bool available;
  String? interfaceName;
  int interfaceIndex;
  int generation;
  String? reason;
  int updatedAtMillis;
}

class UrlTestRequestMessage {
  UrlTestRequestMessage({
    required this.groupTag,
    required this.targetOutboundTag,
    required this.priorityOutboundTag,
    required this.excludeOutboundTag,
    required this.url,
    required this.timeoutMillis,
    required this.concurrency,
    required this.deadlineMillis,
    required this.force,
  });

  String groupTag;
  String targetOutboundTag;
  String priorityOutboundTag;
  String excludeOutboundTag;
  String url;
  int timeoutMillis;
  int concurrency;
  int deadlineMillis;
  bool force;
}

class PreconnectUrlTestRequestMessage {
  PreconnectUrlTestRequestMessage({
    required this.config,
    required this.groupTag,
    required this.targetOutboundTag,
    required this.url,
    required this.timeoutMillis,
    required this.deadlineMillis,
  });

  String config;
  String groupTag;
  String targetOutboundTag;
  String url;
  int timeoutMillis;
  int deadlineMillis;
}

class PreconnectUrlTestResultMessage {
  PreconnectUrlTestResultMessage({
    required this.tag,
    required this.delayMillis,
    required this.timeSeconds,
    required this.status,
    required this.error,
    required this.errorCode,
  });

  String tag;
  int delayMillis;
  int timeSeconds;
  String status;
  String error;
  String errorCode;
}

class CoreBundleSlotMessage {
  CoreBundleSlotMessage({
    required this.releaseSequence,
    required this.version,
    required this.abi,
    required this.sha256,
  });

  int releaseSequence;
  String version;
  String abi;
  String sha256;
}

class CoreManagerStateMessage {
  CoreManagerStateMessage({
    required this.embeddedVersion,
    this.active,
    this.previous,
    this.candidate,
    required this.trustedKeyRingAvailable,
    required this.usingEmbeddedFallback,
    required this.runtimeDisconnected,
  });

  String embeddedVersion;
  CoreBundleSlotMessage? active;
  CoreBundleSlotMessage? previous;
  CoreBundleSlotMessage? candidate;
  bool trustedKeyRingAvailable;
  bool usingEmbeddedFallback;
  bool runtimeDisconnected;
}

class CheckedCoreReleaseMessage {
  CheckedCoreReleaseMessage({
    required this.releaseId,
    required this.releaseSequence,
    required this.version,
    required this.publishedAt,
    required this.coreApiMajor,
    required this.coreApiMinor,
    required this.artifactSizeBytes,
  });

  int releaseId;
  int releaseSequence;
  String version;
  String publishedAt;
  int coreApiMajor;
  int coreApiMinor;
  int artifactSizeBytes;
}

class CoreCandidateProbeMessage {
  CoreCandidateProbeMessage({
    required this.healthy,
    required this.candidate,
    required this.validatedFixtureCount,
    this.errorCode,
  });

  bool healthy;
  CoreBundleSlotMessage candidate;
  int validatedFixtureCount;
  String? errorCode;
}

@HostApi()
abstract class CoreManagerHostApi {
  @async
  CoreManagerStateMessage getState();

  @async
  CheckedCoreReleaseMessage checkLatest();

  @async
  CoreBundleSlotMessage downloadChecked();

  @async
  CoreCandidateProbeMessage probeCandidate();

  @async
  CoreManagerStateMessage activateCandidate();

  @async
  CoreManagerStateMessage rollback();
}

@HostApi()
abstract class SingboxHostApi {
  @async
  bool prepareVpn(bool requiresVpn);

  @async
  Map<String?, Object?> vpnPermissionStatus();

  @async
  void start(String config, bool useVpn);

  @async
  void startPrepared(bool useVpn);

  @async
  void applyConfig(String config, bool useVpn, bool restartCore);

  @async
  void applyPreparedConfig(bool useVpn, bool restartCore);

  @async
  String getConfigPath();

  @async
  Map<String?, Object?> getRuntimeFlags();

  @async
  void setRuntimeFlags(RuntimeFlagsMessage flags);

  @async
  void reload();

  @async
  void stop(String reason);

  @async
  void selectOutbound(String groupTag, String outboundTag);

  @async
  void addOutbound(String selectorTag, String outboundJson);

  @async
  void removeOutbound(String selectorTag, String outboundTag);

  @async
  void urlTest(UrlTestRequestMessage request);

  @async
  Map<String?, Object?> startManagedUrlTest(UrlTestRequestMessage request);

  @async
  Map<String?, Object?> getManagedUrlTestSession(String sessionId);

  @async
  Map<String?, Object?> cancelManagedUrlTest(String sessionId);

  @async
  Map<String?, Object?> getRuntimeSnapshot();

  @async
  PreconnectUrlTestResultMessage preconnectUrlTest(
    PreconnectUrlTestRequestMessage request,
  );

  @async
  void cancelPreconnectUrlTest();

  @async
  void removeUrlTestOutbounds(String groupTag, List<String?> outboundTags);

  @async
  Map<String?, Object?> status();

  @async
  Map<String?, Object?> lookupOutboundExternalInfo(String outboundTag);

  @async
  NetworkInterfaceStateMessage getNetworkInterfaceState();

  @async
  String? exportLogs(String content, String suggestedName);

  @async
  String getAndroidId();

  @async
  String getHydraDeviceId(String canonicalOrigin);

  @async
  Map<String?, Object?> getSubscriptionRequestDeviceInfo();

  @async
  Map<String?, Object?> getPlatformDeviceInfo();

  @async
  Map<String?, Object?> getAppVersionInfo();

  @async
  String getCoreVersion();

  @async
  String getCoreCapabilities();

  @async
  String getHydraCoreBuildInfo();

  @async
  String validateHydraConfig(String content, String profile);

  @async
  String validateHydraSubscription(String content);

  @async
  String inspectHydraSubscription(String content);

  @async
  String openHydraSubscriptionJwe(String envelope, String keyBase64Url);

  @async
  String validateHydraSubscriptionJwe(String envelope, String keyBase64Url);

  @async
  String inspectHydraSubscriptionJwe(String envelope, String keyBase64Url);

  @async
  void checkConfig(String config);

  @async
  Map<String?, Object?> getPerformanceSnapshot();

  @async
  Map<String?, Object?> getHappCrypt5Support();

  @async
  List<Map<String?, Object?>?> getInstalledApps();

  @async
  void setQuickSettingsTileLabel(String label);
}
