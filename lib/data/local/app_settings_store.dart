import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';

enum AppThemePreference { system, light, dark, amoled }

enum TunImplementationPreference { mixed, system, gvisor }

enum SplitRoutingMode { disabled, proxySelected, bypassSelected }

enum AppPerformanceMode { cool, balanced, performance }

class AppSettingsState {
  const AppSettingsState({
    required this.onboardingCompleted,
    required this.activeProfileId,
    required this.selectedProxyTag,
    required this.localeCode,
    required this.themePreference,
    required this.accentColorHex,
    required this.hapticEnabled,
    required this.hideServerIp,
    required this.progressiveBlurEnabled,
    this.progressiveBlurConfigured = false,
    this.performanceMode = AppPerformanceMode.cool,
    required this.vpnInboundEnabled,
    required this.vpnMtu,
    required this.vpnStrictRoute,
    required this.vpnTunImplementation,
    required this.proxyInboundEnabled,
    required this.proxyAllowLan,
    required this.proxyMixedListen,
    required this.proxyMixedPort,
    required this.dnsDirectPreset,
    required this.dnsDirectResolver,
    required this.dnsProxyPreset,
    required this.dnsProxyResolver,
    required this.dnsPreferIpv6,
    required this.urlTestUrl,
    required this.urlTestIntervalSeconds,
    required this.urlTestTimeoutSeconds,
    required this.urlTestConcurrency,
    required this.urlTestUnavailableCheckIntervalSeconds,
    required this.locationLookupLimit,
    required this.locationLookupTimeoutSeconds,
    required this.locationLookupConcurrency,
    required this.blockLeaks,
    required this.adBlockEnabled,
    required this.useRussiaRouteData,
    required this.bypassLocalNetwork,
    required this.splitRoutingMode,
    required this.splitRoutingPackages,
    required this.singBoxLogLevel,
    required this.experimentalTcpFastOpen,
    required this.experimentalTcpMultiPath,
    required this.experimentalInterruptExistingConnections,
    required this.experimentalUrlTestStrictTolerance,
  });

  final bool onboardingCompleted;
  final String activeProfileId;
  final String selectedProxyTag;
  final String localeCode;
  final AppThemePreference themePreference;
  final String accentColorHex; // e.g. "2D5BFF" or "default"
  final bool hapticEnabled;
  final bool hideServerIp;
  final bool progressiveBlurEnabled;
  final bool progressiveBlurConfigured;
  final AppPerformanceMode performanceMode;
  final bool vpnInboundEnabled;
  final int vpnMtu;
  final bool vpnStrictRoute;
  final TunImplementationPreference vpnTunImplementation;
  final bool proxyInboundEnabled;
  final bool proxyAllowLan;
  final String proxyMixedListen;
  final int proxyMixedPort;
  final String dnsDirectPreset;
  final String dnsDirectResolver;
  final String dnsProxyPreset;
  final String dnsProxyResolver;
  final bool dnsPreferIpv6;
  final String urlTestUrl;
  final int urlTestIntervalSeconds;
  final int urlTestTimeoutSeconds;
  final int urlTestConcurrency;
  final int urlTestUnavailableCheckIntervalSeconds;
  final int locationLookupLimit;
  final int locationLookupTimeoutSeconds;
  final int locationLookupConcurrency;
  final bool blockLeaks;
  final bool adBlockEnabled;
  final bool useRussiaRouteData;
  final bool bypassLocalNetwork;
  final SplitRoutingMode splitRoutingMode;
  final List<String> splitRoutingPackages;
  final String singBoxLogLevel;
  final bool experimentalTcpFastOpen;
  final bool experimentalTcpMultiPath;
  final bool experimentalInterruptExistingConnections;
  final bool experimentalUrlTestStrictTolerance;

  AppSettingsState copyWith({
    bool? onboardingCompleted,
    String? activeProfileId,
    String? selectedProxyTag,
    String? localeCode,
    AppThemePreference? themePreference,
    String? accentColorHex,
    bool? hapticEnabled,
    bool? hideServerIp,
    bool? progressiveBlurEnabled,
    bool? progressiveBlurConfigured,
    AppPerformanceMode? performanceMode,
    bool? vpnInboundEnabled,
    int? vpnMtu,
    bool? vpnStrictRoute,
    TunImplementationPreference? vpnTunImplementation,
    bool? proxyInboundEnabled,
    bool? proxyAllowLan,
    String? proxyMixedListen,
    int? proxyMixedPort,
    String? dnsDirectPreset,
    String? dnsDirectResolver,
    String? dnsProxyPreset,
    String? dnsProxyResolver,
    bool? dnsPreferIpv6,
    String? urlTestUrl,
    int? urlTestIntervalSeconds,
    int? urlTestTimeoutSeconds,
    int? urlTestConcurrency,
    int? urlTestUnavailableCheckIntervalSeconds,
    int? locationLookupLimit,
    int? locationLookupTimeoutSeconds,
    int? locationLookupConcurrency,
    bool? blockLeaks,
    bool? adBlockEnabled,
    bool? useRussiaRouteData,
    bool? bypassLocalNetwork,
    SplitRoutingMode? splitRoutingMode,
    List<String>? splitRoutingPackages,
    String? singBoxLogLevel,
    bool? experimentalTcpFastOpen,
    bool? experimentalTcpMultiPath,
    bool? experimentalInterruptExistingConnections,
    bool? experimentalUrlTestStrictTolerance,
  }) {
    return AppSettingsState(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      selectedProxyTag: selectedProxyTag ?? this.selectedProxyTag,
      localeCode: localeCode ?? this.localeCode,
      themePreference: themePreference ?? this.themePreference,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      hideServerIp: hideServerIp ?? this.hideServerIp,
      progressiveBlurEnabled:
          progressiveBlurEnabled ?? this.progressiveBlurEnabled,
      progressiveBlurConfigured:
          progressiveBlurConfigured ?? this.progressiveBlurConfigured,
      performanceMode: performanceMode ?? this.performanceMode,
      vpnInboundEnabled: vpnInboundEnabled ?? this.vpnInboundEnabled,
      vpnMtu: vpnMtu ?? this.vpnMtu,
      vpnStrictRoute: vpnStrictRoute ?? this.vpnStrictRoute,
      vpnTunImplementation: vpnTunImplementation ?? this.vpnTunImplementation,
      proxyInboundEnabled: proxyInboundEnabled ?? this.proxyInboundEnabled,
      proxyAllowLan: proxyAllowLan ?? this.proxyAllowLan,
      proxyMixedListen: proxyMixedListen ?? this.proxyMixedListen,
      proxyMixedPort: proxyMixedPort ?? this.proxyMixedPort,
      dnsDirectPreset: dnsDirectPreset ?? this.dnsDirectPreset,
      dnsDirectResolver: dnsDirectResolver ?? this.dnsDirectResolver,
      dnsProxyPreset: dnsProxyPreset ?? this.dnsProxyPreset,
      dnsProxyResolver: dnsProxyResolver ?? this.dnsProxyResolver,
      dnsPreferIpv6: dnsPreferIpv6 ?? this.dnsPreferIpv6,
      urlTestUrl: urlTestUrl ?? this.urlTestUrl,
      urlTestIntervalSeconds:
          urlTestIntervalSeconds ?? this.urlTestIntervalSeconds,
      urlTestTimeoutSeconds:
          urlTestTimeoutSeconds ?? this.urlTestTimeoutSeconds,
      urlTestConcurrency: urlTestConcurrency ?? this.urlTestConcurrency,
      urlTestUnavailableCheckIntervalSeconds:
          urlTestUnavailableCheckIntervalSeconds ??
          this.urlTestUnavailableCheckIntervalSeconds,
      locationLookupLimit: locationLookupLimit ?? this.locationLookupLimit,
      locationLookupTimeoutSeconds:
          locationLookupTimeoutSeconds ?? this.locationLookupTimeoutSeconds,
      locationLookupConcurrency:
          locationLookupConcurrency ?? this.locationLookupConcurrency,
      blockLeaks: blockLeaks ?? this.blockLeaks,
      adBlockEnabled: adBlockEnabled ?? this.adBlockEnabled,
      useRussiaRouteData: useRussiaRouteData ?? this.useRussiaRouteData,
      bypassLocalNetwork: bypassLocalNetwork ?? this.bypassLocalNetwork,
      splitRoutingMode: splitRoutingMode ?? this.splitRoutingMode,
      splitRoutingPackages: splitRoutingPackages ?? this.splitRoutingPackages,
      singBoxLogLevel: singBoxLogLevel ?? this.singBoxLogLevel,
      experimentalTcpFastOpen:
          experimentalTcpFastOpen ?? this.experimentalTcpFastOpen,
      experimentalTcpMultiPath:
          experimentalTcpMultiPath ?? this.experimentalTcpMultiPath,
      experimentalInterruptExistingConnections:
          experimentalInterruptExistingConnections ??
          this.experimentalInterruptExistingConnections,
      experimentalUrlTestStrictTolerance:
          experimentalUrlTestStrictTolerance ??
          this.experimentalUrlTestStrictTolerance,
    );
  }
}

abstract class AppSettingsStore {
  static const boxName = 'app_state';

  static const _onboardingCompletedKey = 'onboarding_completed';
  static const _activeProfileIdKey = 'active_profile_id';
  static const _selectedProxyTagKey = 'selected_proxy_tag';
  static const _localeCodeKey = 'locale_code';
  static const _themePreferenceKey = 'theme_preference';
  static const _accentColorHexKey = 'accent_color_hex';
  static const _hapticEnabledKey = 'haptic_enabled';
  static const _hideServerIpKey = 'hide_server_ip';
  static const _progressiveBlurEnabledKey = 'progressive_blur_enabled';
  static const _performanceModeKey = 'performance_mode';
  static const _vpnInboundEnabledKey = 'vpn_inbound_enabled';
  static const _vpnMtuKey = 'vpn_mtu';
  static const _vpnStrictRouteKey = 'vpn_strict_route';
  static const _vpnTunImplementationKey = 'vpn_tun_implementation';
  static const _proxyInboundEnabledKey = 'proxy_inbound_enabled';
  static const _proxyAllowLanKey = 'proxy_allow_lan';
  static const _proxyMixedListenKey = 'proxy_mixed_listen';
  static const _proxyMixedPortKey = 'proxy_mixed_port';
  static const _dnsDirectPresetKey = 'dns_direct_preset';
  static const _dnsDirectResolverKey = 'dns_direct_resolver';
  static const _dnsProxyPresetKey = 'dns_proxy_preset';
  static const _dnsProxyResolverKey = 'dns_proxy_resolver';
  static const _dnsPreferIpv6Key = 'dns_prefer_ipv6';
  static const _urlTestUrlKey = 'urltest_url';
  static const _urlTestIntervalSecondsKey = 'urltest_interval_seconds';
  static const _urlTestTimeoutSecondsKey = 'urltest_timeout_seconds';
  static const _urlTestConcurrencyKey = 'urltest_concurrency';
  static const _urlTestUnavailableCheckIntervalSecondsKey =
      'urltest_unavailable_check_interval_seconds';
  static const _locationLookupLimitKey = 'location_lookup_limit';
  static const _locationLookupTimeoutSecondsKey =
      'location_lookup_timeout_seconds';
  static const _locationLookupConcurrencyKey = 'location_lookup_concurrency';
  static const _blockLeaksKey = 'block_leaks';
  static const _adBlockEnabledKey = 'ad_block_enabled';
  static const _useRussiaRouteDataKey = 'use_russia_route_data';
  static const _bypassLocalNetworkKey = 'bypass_local_network';
  static const _splitRoutingModeKey = 'split_routing_mode';
  static const _splitRoutingPackagesKey = 'split_routing_packages';
  static const _singBoxLogLevelKey = 'singbox_log_level';
  static const _experimentalTcpFastOpenKey = 'experimental_tcp_fast_open';
  static const _experimentalTcpMultiPathKey = 'experimental_tcp_multi_path';
  static const _experimentalInterruptExistingConnectionsKey =
      'experimental_interrupt_existing_connections';
  static const _experimentalUrlTestStrictToleranceKey =
      'experimental_urltest_strict_tolerance';

  Future<AppSettingsState> loadState();

  Future<void> saveState(AppSettingsState state);

  Future<void> close();

  AppSettingsState mapState(Map<String, dynamic> map) {
    bool boolValue(String key, {required bool defaultValue}) {
      final raw = map[key]?.toString();
      if (raw == null) {
        return defaultValue;
      }
      return raw == '1';
    }

    List<String> packageListValue(String key) {
      final raw = map[key]?.toString() ?? '';
      final values = <String>[];
      final seen = <String>{};
      for (final segment in raw.split(RegExp(r'[\n,;]'))) {
        final value = segment.trim();
        if (value.isEmpty || !seen.add(value)) {
          continue;
        }
        values.add(value);
      }
      return values;
    }

    final performanceMode = switch (map[_performanceModeKey]) {
      'cool' => AppPerformanceMode.cool,
      'performance' => AppPerformanceMode.performance,
      'balanced' => AppPerformanceMode.balanced,
      _ => AppPerformanceMode.cool,
    };
    final cool = performanceMode == AppPerformanceMode.cool;
    final balanced = performanceMode == AppPerformanceMode.balanced;

    return AppSettingsState(
      onboardingCompleted: boolValue(
        _onboardingCompletedKey,
        defaultValue: false,
      ),
      activeProfileId: map[_activeProfileIdKey] ?? '',
      selectedProxyTag: map[_selectedProxyTagKey] ?? '',
      localeCode: map[_localeCodeKey] ?? 'system',
      themePreference: switch (map[_themePreferenceKey]) {
        'system' => AppThemePreference.system,
        'dark' => AppThemePreference.dark,
        'light' => AppThemePreference.light,
        'amoled' => AppThemePreference.amoled,
        _ => AppThemePreference.system,
      },
      accentColorHex: map[_accentColorHexKey] ?? 'default',
      hapticEnabled: boolValue(_hapticEnabledKey, defaultValue: true),
      hideServerIp: boolValue(_hideServerIpKey, defaultValue: false),
      progressiveBlurEnabled: boolValue(
        _progressiveBlurEnabledKey,
        defaultValue: false,
      ),
      progressiveBlurConfigured: map.containsKey(_progressiveBlurEnabledKey),
      performanceMode: performanceMode,
      vpnInboundEnabled: boolValue(_vpnInboundEnabledKey, defaultValue: true),
      vpnMtu: _vpnMtuValue(map[_vpnMtuKey]),
      vpnStrictRoute: boolValue(_vpnStrictRouteKey, defaultValue: true),
      vpnTunImplementation: switch (map[_vpnTunImplementationKey]) {
        'system' => TunImplementationPreference.system,
        'gvisor' => TunImplementationPreference.gvisor,
        'mixed' => TunImplementationPreference.mixed,
        _ => TunImplementationPreference.mixed,
      },
      proxyInboundEnabled: boolValue(
        _proxyInboundEnabledKey,
        defaultValue: false,
      ),
      proxyAllowLan: boolValue(_proxyAllowLanKey, defaultValue: false),
      proxyMixedListen:
          map[_proxyMixedListenKey]?.toString() ??
          (boolValue(_proxyAllowLanKey, defaultValue: false)
              ? '0.0.0.0'
              : '127.0.0.1'),
      proxyMixedPort:
          int.tryParse(map[_proxyMixedPortKey]?.toString() ?? '') ?? 1080,
      dnsDirectPreset: map[_dnsDirectPresetKey]?.toString() ?? 'cloudflare',
      dnsDirectResolver:
          map[_dnsDirectResolverKey]?.toString() ?? 'udp://1.1.1.1',
      dnsProxyPreset: map[_dnsProxyPresetKey]?.toString() ?? 'cloudflare',
      dnsProxyResolver:
          map[_dnsProxyResolverKey]?.toString() ??
          'https://dns.cloudflare.com/dns-query',
      dnsPreferIpv6: map[_dnsPreferIpv6Key] == '1',
      urlTestUrl:
          map[_urlTestUrlKey]?.toString() ??
          'https://www.gstatic.com/generate_204',
      urlTestIntervalSeconds:
          int.tryParse(map[_urlTestIntervalSecondsKey]?.toString() ?? '') ??
          (cool
              ? 900
              : balanced
              ? 300
              : 180),
      urlTestTimeoutSeconds:
          int.tryParse(map[_urlTestTimeoutSecondsKey]?.toString() ?? '') ?? 15,
      urlTestConcurrency:
          int.tryParse(map[_urlTestConcurrencyKey]?.toString() ?? '') ??
          (cool
              ? 4
              : balanced
              ? 8
              : 30),
      urlTestUnavailableCheckIntervalSeconds:
          int.tryParse(
            map[_urlTestUnavailableCheckIntervalSecondsKey]?.toString() ?? '',
          ) ??
          (cool
              ? 30
              : balanced
              ? 15
              : 5),
      locationLookupLimit:
          int.tryParse(map[_locationLookupLimitKey]?.toString() ?? '') ??
          (cool
              ? 0
              : balanced
              ? 8
              : 12),
      locationLookupTimeoutSeconds:
          int.tryParse(
            map[_locationLookupTimeoutSecondsKey]?.toString() ?? '',
          ) ??
          6,
      locationLookupConcurrency:
          int.tryParse(map[_locationLookupConcurrencyKey]?.toString() ?? '') ??
          (cool
              ? 2
              : balanced
              ? 4
              : 16),
      blockLeaks: boolValue(_blockLeaksKey, defaultValue: false),
      adBlockEnabled: boolValue(_adBlockEnabledKey, defaultValue: false),
      useRussiaRouteData: boolValue(
        _useRussiaRouteDataKey,
        defaultValue: false,
      ),
      bypassLocalNetwork: boolValue(_bypassLocalNetworkKey, defaultValue: true),
      splitRoutingMode: switch (map[_splitRoutingModeKey]) {
        'proxy_selected' => SplitRoutingMode.proxySelected,
        'bypass_selected' => SplitRoutingMode.bypassSelected,
        'disabled' => SplitRoutingMode.disabled,
        _ => SplitRoutingMode.disabled,
      },
      splitRoutingPackages: packageListValue(_splitRoutingPackagesKey),
      singBoxLogLevel: map[_singBoxLogLevelKey]?.toString() ?? 'warning',
      experimentalTcpFastOpen: boolValue(
        _experimentalTcpFastOpenKey,
        defaultValue: true,
      ),
      experimentalTcpMultiPath: boolValue(
        _experimentalTcpMultiPathKey,
        defaultValue: false,
      ),
      experimentalInterruptExistingConnections: boolValue(
        _experimentalInterruptExistingConnectionsKey,
        defaultValue: true,
      ),
      experimentalUrlTestStrictTolerance: boolValue(
        _experimentalUrlTestStrictToleranceKey,
        defaultValue: true,
      ),
    );
  }

  int _vpnMtuValue(Object? rawValue) {
    final value = int.tryParse(rawValue?.toString() ?? '');
    if (value == null || value == 3400) {
      return 1500;
    }
    return value;
  }

  Map<String, dynamic> stateToMap(AppSettingsState state) {
    return {
      _onboardingCompletedKey: state.onboardingCompleted ? '1' : '0',
      _activeProfileIdKey: state.activeProfileId,
      _selectedProxyTagKey: state.selectedProxyTag,
      _localeCodeKey: state.localeCode,
      _themePreferenceKey: state.themePreference.name,
      _accentColorHexKey: state.accentColorHex,
      _hapticEnabledKey: state.hapticEnabled ? '1' : '0',
      _hideServerIpKey: state.hideServerIp ? '1' : '0',
      _progressiveBlurEnabledKey: state.progressiveBlurEnabled ? '1' : '0',
      _performanceModeKey: state.performanceMode.name,
      _vpnInboundEnabledKey: state.vpnInboundEnabled ? '1' : '0',
      _vpnMtuKey: state.vpnMtu.toString(),
      _vpnStrictRouteKey: state.vpnStrictRoute ? '1' : '0',
      _vpnTunImplementationKey: state.vpnTunImplementation.name,
      _proxyInboundEnabledKey: state.proxyInboundEnabled ? '1' : '0',
      _proxyAllowLanKey: state.proxyAllowLan ? '1' : '0',
      _proxyMixedListenKey: state.proxyMixedListen,
      _proxyMixedPortKey: state.proxyMixedPort.toString(),
      _dnsDirectPresetKey: state.dnsDirectPreset,
      _dnsDirectResolverKey: state.dnsDirectResolver,
      _dnsProxyPresetKey: state.dnsProxyPreset,
      _dnsProxyResolverKey: state.dnsProxyResolver,
      _dnsPreferIpv6Key: state.dnsPreferIpv6 ? '1' : '0',
      _urlTestUrlKey: state.urlTestUrl,
      _urlTestIntervalSecondsKey: state.urlTestIntervalSeconds.toString(),
      _urlTestTimeoutSecondsKey: state.urlTestTimeoutSeconds.toString(),
      _urlTestConcurrencyKey: state.urlTestConcurrency.toString(),
      _urlTestUnavailableCheckIntervalSecondsKey: state
          .urlTestUnavailableCheckIntervalSeconds
          .toString(),
      _locationLookupLimitKey: state.locationLookupLimit.toString(),
      _locationLookupTimeoutSecondsKey: state.locationLookupTimeoutSeconds
          .toString(),
      _locationLookupConcurrencyKey: state.locationLookupConcurrency.toString(),
      _blockLeaksKey: state.blockLeaks ? '1' : '0',
      _adBlockEnabledKey: state.adBlockEnabled ? '1' : '0',
      _useRussiaRouteDataKey: state.useRussiaRouteData ? '1' : '0',
      _bypassLocalNetworkKey: state.bypassLocalNetwork ? '1' : '0',
      _splitRoutingModeKey: switch (state.splitRoutingMode) {
        SplitRoutingMode.disabled => 'disabled',
        SplitRoutingMode.proxySelected => 'proxy_selected',
        SplitRoutingMode.bypassSelected => 'bypass_selected',
      },
      _splitRoutingPackagesKey: state.splitRoutingPackages.join('\n'),
      _singBoxLogLevelKey: state.singBoxLogLevel,
      _experimentalTcpFastOpenKey: state.experimentalTcpFastOpen ? '1' : '0',
      _experimentalTcpMultiPathKey: state.experimentalTcpMultiPath ? '1' : '0',
      _experimentalInterruptExistingConnectionsKey:
          state.experimentalInterruptExistingConnections ? '1' : '0',
      _experimentalUrlTestStrictToleranceKey:
          state.experimentalUrlTestStrictTolerance ? '1' : '0',
    };
  }
}

class HiveAppSettingsStore extends AppSettingsStore {
  HiveAppSettingsStore._(this._box);

  final Box<dynamic> _box;
  static bool _hiveInitialized = false;

  static String _androidFilesDirPath() {
    final context = androidApplicationContext;
    final contextClass = context.jClass;
    final getFilesDir = contextClass.instanceMethodId(
      'getFilesDir',
      '()Ljava/io/File;',
    );
    final filesDir = getFilesDir.call(context, JObject.type, []);
    final fileClass = filesDir.jClass;
    final getAbsolutePath = fileClass.instanceMethodId(
      'getAbsolutePath',
      '()Ljava/lang/String;',
    );
    final path = getAbsolutePath
        .call(filesDir, JString.type, [])
        .toDartString(releaseOriginal: true);

    fileClass.release();
    filesDir.release();
    contextClass.release();
    context.release();

    return path;
  }

  /// Call once before [open], ideally in main() before runApp.
  static Future<void> initHive() async {
    if (_hiveInitialized) return;
    if (Platform.isAndroid) {
      final filesDir = _androidFilesDirPath();
      Hive.init('$filesDir/meow_hive');
    } else {
      await Hive.initFlutter('meow_hive');
    }
    _hiveInitialized = true;
  }

  static Future<HiveAppSettingsStore> open() async {
    // Safety: ensure Hive is initialized even if caller forgot.
    await initHive();

    // If the box is already open, just reuse it.
    if (Hive.isBoxOpen(AppSettingsStore.boxName)) {
      final box = Hive.box<dynamic>(AppSettingsStore.boxName);
      return HiveAppSettingsStore._(box);
    }

    try {
      final box = await Hive.openBox<dynamic>(AppSettingsStore.boxName);
      return HiveAppSettingsStore._(box);
    } catch (error, stackTrace) {
      debugPrint('[HiveAppSettingsStore] Failed to open box: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<AppSettingsState> loadState() async {
    final raw = _box.toMap().map(
      (key, value) => MapEntry(key.toString(), value),
    );
    return mapState(raw);
  }

  @override
  Future<void> saveState(AppSettingsState state) async {
    final map = stateToMap(state);
    await _box.putAll(map);
    await _box.flush();
  }

  @override
  Future<void> close() => _box.close();
}

class MemoryAppSettingsStore extends AppSettingsStore {
  MemoryAppSettingsStore([AppSettingsState? initialState])
    : _state =
          initialState ??
          const AppSettingsState(
            onboardingCompleted: false,
            activeProfileId: '',
            selectedProxyTag: '',
            localeCode: 'system',
            themePreference: AppThemePreference.system,
            accentColorHex: 'default',
            hapticEnabled: true,
            hideServerIp: false,
            progressiveBlurEnabled: false,
            progressiveBlurConfigured: false,
            performanceMode: AppPerformanceMode.cool,
            vpnInboundEnabled: true,
            vpnMtu: 1500,
            vpnStrictRoute: true,
            vpnTunImplementation: TunImplementationPreference.mixed,
            proxyInboundEnabled: false,
            proxyAllowLan: false,
            proxyMixedListen: '127.0.0.1',
            proxyMixedPort: 1080,
            dnsDirectPreset: 'cloudflare',
            dnsDirectResolver: 'udp://1.1.1.1',
            dnsProxyPreset: 'cloudflare',
            dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
            dnsPreferIpv6: false,
            urlTestUrl: 'https://www.gstatic.com/generate_204',
            urlTestIntervalSeconds: 900,
            urlTestTimeoutSeconds: 15,
            urlTestConcurrency: 4,
            urlTestUnavailableCheckIntervalSeconds: 30,
            locationLookupLimit: 0,
            locationLookupTimeoutSeconds: 6,
            locationLookupConcurrency: 2,
            blockLeaks: false,
            adBlockEnabled: false,
            useRussiaRouteData: false,
            bypassLocalNetwork: true,
            splitRoutingMode: SplitRoutingMode.disabled,
            splitRoutingPackages: <String>[],
            singBoxLogLevel: 'warning',
            experimentalTcpFastOpen: true,
            experimentalTcpMultiPath: false,
            experimentalInterruptExistingConnections: true,
            experimentalUrlTestStrictTolerance: true,
          );

  AppSettingsState _state;

  @override
  Future<AppSettingsState> loadState() async => _state;

  @override
  Future<void> saveState(AppSettingsState state) async {
    _state = state;
  }

  @override
  Future<void> close() async {}
}
