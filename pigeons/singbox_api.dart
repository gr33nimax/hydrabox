import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/singbox/singbox_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/app/src/main/kotlin/com/etonify/meow_client/generated/SingboxApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.etonify.meow_client.generated'),
  ),
)
class RuntimeFlagsMessage {
  RuntimeFlagsMessage({
    this.wakeLockEnabled,
    this.networkHeartbeatEnabled,
    this.networkHeartbeatIntervalSeconds,
    this.performanceMode,
  });

  bool? wakeLockEnabled;
  bool? networkHeartbeatEnabled;
  int? networkHeartbeatIntervalSeconds;
  String? performanceMode;
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
  void urlTest(String groupTag);

  @async
  void removeUrlTestOutbounds(String groupTag, List<String?> outboundTags);

  @async
  Map<String?, Object?> status();

  @async
  Map<String?, Object?> lookupOutboundExternalInfo(String outboundTag);

  @async
  String? exportLogs(String content, String suggestedName);

  @async
  String getAndroidId();

  @async
  Map<String?, Object?> getSubscriptionRequestDeviceInfo();

  @async
  Map<String?, Object?> getPlatformDeviceInfo();

  @async
  String getCoreVersion();

  @async
  Map<String?, Object?> getPerformanceSnapshot();

  @async
  Map<String?, Object?> getHappCrypt5Support();

  @async
  List<Map<String?, Object?>?> getInstalledApps();

  @async
  void setQuickSettingsTileLabel(String label);

  @async
  void ensureExecutable(String path);

  @async
  Map<String?, Object?> getSnowtunModuleStatus(
    String splitName,
    String nativeLibraryName,
  );

  @async
  void installSnowtunModule(
    String apkPath,
    String expectedPackageName,
    String splitName,
  );

  @async
  void removeSnowtunModule(String splitName);

  @async
  void requestInstallPackagesPermission();
}
