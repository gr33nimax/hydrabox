import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/app/active_proxy_ip_controller.dart';
import 'package:meow_client/app/app_background_tasks.dart';
import 'package:meow_client/app/app_settings_controller.dart';
import 'package:meow_client/app/deep_link_import.dart';
import 'package:meow_client/app/fast_exit_ip_lookup.dart';
import 'package:meow_client/app/latency_coordinator.dart';
import 'package:meow_client/app/proxy_runtime_controller.dart';
import 'package:meow_client/app/proxy_selection_controller.dart';
import 'package:meow_client/app/runtime_lifecycle_controller.dart';
import 'package:meow_client/app/runtime_event_controller.dart';
import 'package:meow_client/app/runtime_recovery_policy.dart';
import 'package:meow_client/app/singbox_config_coordinator.dart';
import 'package:meow_client/app/subscription_runtime_controller.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/data/adblock/ad_block_rule_set_service.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/data/routing/russia_route_data_service.dart';
import 'package:meow_client/data/subscription/happ_crypto_link.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/data/update/app_update_service.dart';
import 'package:meow_client/features/home/home_page.dart';
import 'package:meow_client/features/home/traffic_dashboard_page.dart';
import 'package:meow_client/features/legal/legal_consent_page.dart';
import 'package:meow_client/features/proxies/proxies_page.dart';
import 'package:meow_client/features/proxies/proxy_panel_shell.dart';
import 'package:meow_client/features/settings/changelog_sheet.dart';
import 'package:meow_client/features/settings/settings_about_page.dart';
import 'package:meow_client/features/settings/settings_backup_page.dart';
import 'package:meow_client/features/settings/settings_dns_page.dart';
import 'package:meow_client/features/settings/settings_experimental_page.dart';
import 'package:meow_client/features/settings/settings_general_page.dart';
import 'package:meow_client/features/settings/settings_inbound_page.dart';
import 'package:meow_client/features/settings/settings_logs_page.dart';
import 'package:meow_client/features/settings/settings_page.dart';
import 'package:meow_client/features/settings/settings_routing_page.dart';
import 'package:meow_client/features/settings/settings_subscriptions_page.dart';
import 'package:meow_client/features/settings/settings_update_page.dart';
import 'package:meow_client/features/subscriptions/subscriptions_page.dart';
import 'package:meow_client/features/welcome/welcome_page.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/models/app_view_models.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/runtime_start_error.dart';
import 'package:meow_client/singbox/singbox_config_builder.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';
import 'package:meow_client/theme/demo_app_theme.dart';
import 'package:meow_client/widgets/app_scroll_effects.dart';
import 'package:meow_client/widgets/app_visual_effects.dart';
import 'package:meow_client/widgets/country_flag_badge.dart';

class MeowClient extends StatefulWidget {
  const MeowClient({super.key, this.store});

  final AppSettingsStore? store;

  @override
  State<MeowClient> createState() => _MeowClientState();
}

enum AppConnectionPhase {
  idle,
  preparing,
  configuring,
  reconfiguring,
  starting,
  connected,
  stopping,
  recovering,
  failed,
}

class _MeowClientState extends State<MeowClient> with WidgetsBindingObserver {
  static const _fallbackClientVersionLabel = '0.2.1';
  static const _requiredLegalVersion = '0.2.1';
  static final RegExp _quickTileCountryCodePattern = RegExp(r'^[A-Z]{2}$');
  static const _lowestProxyTag = lowestProxyTag;
  static const _derivedCacheBuildDebounce = Duration(milliseconds: 160);
  static const _defaultUrlTestTimeoutSeconds = 15;
  static const _defaultLocationLookupTimeoutSeconds = 5;
  static const _coolUrlTestIntervalSeconds = 1800;
  static const _coolUrlTestConcurrency = 30;
  static const _coolUrlTestUnavailableCheckIntervalSeconds = 10;
  static const _coolLocationLookupLimit = 2;
  static const _coolLocationLookupConcurrency = 2;
  static const _coolNetworkHeartbeatIntervalSeconds = 240;
  static const _economyNetworkHeartbeatIntervalSeconds = 300;
  static const _trafficUiUpdateInterval = Duration(seconds: 1);
  static const _networkRecoveryProbeDelay = Duration(seconds: 1);
  static const _networkRecoveryDecisionDelay = Duration(seconds: 18);
  static const _networkRecoveryDecisionRetryDelay = Duration(seconds: 4);
  static const _networkRecoveryMaxUrlTestWait = Duration(seconds: 45);
  static const _networkRecoveryRestartCooldown = Duration(seconds: 60);
  static const _networkRecoveryWindow = Duration(minutes: 10);
  static const _networkRecoveryMaxRestartsPerWindow = 2;
  static const _runtimeInterfaceIssueWindow = Duration(seconds: 8);
  static const _runtimeInterfaceIssueThreshold = 4;
  static const _runtimeInterfaceIssueRecoveryCooldown = Duration(seconds: 12);
  static const _runtimeRecoveryStatusLogInterval = Duration(seconds: 5);
  static const _subscriptionOperationSoftWarningDelay = Duration(seconds: 15);
  static const _subscriptionOperationTimeout = Duration(seconds: 30);
  static const _androidImageCacheMaximumBytes = 48 * 1024 * 1024;
  static const _androidImageCacheMaximumEntries = 80;
  static const _subscriptionAutoRefreshMinDelay = Duration(seconds: 30);
  static const _subscriptionAutoRefreshMaxDelay = Duration(hours: 6);
  static const _splitRoutingTemporarilyDisabled = false;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late ThemeData _lightTheme;
  late ThemeData _darkTheme;
  late ThemeData _amoledTheme;
  StreamSubscription<DeepLinkImportRequest>? _deepLinkImportSubscription;
  AppSettingsStore? _store;
  Timer? _subscriptionAutoRefreshTimer;
  Timer? _invalidOutboundRetryTimer;
  Timer? _locationLookupTimer;
  Timer? _derivedCacheBuildTimer;
  Timer? _trafficUiUpdateTimer;
  Timer? _resumeForegroundSyncTimer;
  Timer? _networkReconnectWatchdogTimer;
  Timer? _postConnectUrlTestTimer;
  Timer? _networkRecoveryDecisionTimer;
  Timer? _latencyFinalizeTimer;
  bool _autoRefreshInFlight = false;
  bool _ownsStore = false;
  bool _ready = false;
  bool _onboardingCompleted = false;
  String _acceptedLegalVersion = '';
  int? _acceptedLegalAtMillis;
  bool _connected = false;
  bool _runtimeErrorDialogVisible = false;
  bool _noValidOutboundsDialogVisible = false;
  bool _trafficAvailable = false;
  bool _activeProfileRefreshInFlight = false;
  bool _singleOutboundPingRefreshScheduled = false;
  bool _starting = false;
  bool _runtimeTransitionInProgress = false;
  bool _startAfterStopRequested = false;
  bool _invalidOutboundRetryScheduled = false;
  bool _runtimeDesiredByUser = false;
  bool _deepLinkImportInFlight = false;
  bool _locationLookupInFlight = false;
  bool _proxyPanelInteractionActive = false;
  bool _retryRuntimeOnResume = false;
  int _invalidOutboundRetryGeneration = 0;
  int _latencySessionGeneration = 0;
  String _activeProfileId = '';
  String _selectedProxyTag = '';
  String _clientVersionLabel = _fallbackClientVersionLabel;
  int _clientVersionCode = 0;
  String _clientPackageName = '';
  String? _lastUpdateCleanupNoticeVersion;
  bool _updateCleanupInFlight = false;
  String? _lastRuntimeError;
  final AppSettingsController _settings = AppSettingsController();
  int _locationLookupActiveRequests = 0;
  int _locationLookupGeneration = 0;
  bool _locationLookupRefreshRequested = false;
  String _lastLocationLookupSignature = '';
  final Queue<Completer<bool>> _locationLookupWaiters =
      Queue<Completer<bool>>();
  AdBlockRuleSetStatus _adBlockStatus =
      const AdBlockRuleSetStatus.unavailable();
  RussiaRouteDataStatus _russiaRouteDataStatus =
      const RussiaRouteDataStatus.unavailable();
  List<Map<String, dynamic>> _installedAppsCache =
      const <Map<String, dynamic>>[];
  Future<List<Map<String, dynamic>>>? _installedAppsWarmupFuture;
  int _installedAppsCacheGeneration = 0;
  int _downlinkBytesPerSecond = 0;
  int _uplinkBytesPerSecond = 0;
  int _uplinkTotalBytes = 0;
  int _downlinkTotalBytes = 0;
  DateTime? _connectedSince;
  List<TrafficSample> _trafficSamples = const <TrafficSample>[];
  bool _trafficDashboardOpen = false;
  final ValueNotifier<TrafficDashboardSnapshot> _trafficDashboardSnapshot =
      ValueNotifier<TrafficDashboardSnapshot>(TrafficDashboardSnapshot.empty);
  Map<String, dynamic>? _pendingTrafficStatusEvent;
  DateTime _lastTrafficUiUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastRuntimeStatusEventAt;
  int _networkReconnectGeneration = 0;
  int _networkInterfaceGeneration = 0;
  DateTime? _lastRecoveryRestartAt;
  final Queue<DateTime> _networkRecoveryRestartHistory = Queue<DateTime>();
  DateTime? _lastRuntimeInterfaceIssueRecoveryAt;
  final Queue<DateTime> _runtimeInterfaceIssueTimes = Queue<DateTime>();
  int _derivedCacheBuildGeneration = 0;
  int _activeSubscriptionHydrationGeneration = 0;
  bool _derivedCacheBuildInFlight = false;
  bool _derivedCacheBuildQueued = false;
  String? _lastEmptyAfterDropInvalidWarningSubscriptionId;
  final Set<String> _excludedRuntimeOutboundTags = <String>{};
  Map<int, String>? _lastStartedProxyOutboundTagsByIndex;
  Map<String, dynamic>? _lastStartedConfig;
  String? _pendingMutationExcludedTag;
  ActiveProxyIpSnapshot _activeProxyIp = const ActiveProxyIpSnapshot.idle();
  final ProxySelectionController _proxySelection = ProxySelectionController();
  final ActiveProxyIpController _activeProxyIpController =
      ActiveProxyIpController();
  final RuntimeLifecycleController _runtimeLifecycle =
      RuntimeLifecycleController();
  late final SingboxConfigCoordinator _configCoordinator;
  late final RuntimeEventController _runtimeEvents;
  final ProxyRuntimeController _proxyRuntime = ProxyRuntimeController();
  late final LatencyCoordinator _latencyCoordinator;
  final SubscriptionRuntimeController _subscriptionRuntime =
      SubscriptionRuntimeController(
        autoRefreshMinDelay: _subscriptionAutoRefreshMinDelay,
        autoRefreshMaxDelay: _subscriptionAutoRefreshMaxDelay,
      );
  List<Subscription> _subscriptions = const [];
  AppProfileSummary? _activeProfileCache;
  AppProxySummary? _displayProxyCache;
  List<AppProxySummary> _activeProxiesCache = const [];
  final ProxyRuntimeVisualStore _proxyRuntimeVisualStates =
      ProxyRuntimeVisualStore();
  Map<String, List<AppProxySummary>> _activeGroupChildrenByTagCache =
      const <String, List<AppProxySummary>>{};
  int _activeTopLevelProxiesCount = 0;
  Subscription? _activeLookupSubscription;
  List<Outbound> _activeVisibleOutboundsLookup = const [];
  Map<String, Outbound> _activeOutboundByTagLookup = const {};
  Map<String, SubscriptionGroup> _activeGroupByTagLookup = const {};
  final Map<String, Subscription> _proxyChainTargetSourceCache = {};
  DeepLinkImportRequest? _pendingDeepLinkImport;
  String? _lastQuickSettingsTileLabel;
  ColorScheme? _dynamicLightScheme;
  ColorScheme? _dynamicDarkScheme;
  int _postConnectUrlTestGeneration = 0;
  int _groupsEventsSinceLastDiagnosticsLog = 0;
  DateTime? _lastGroupsDiagnosticsLogAt;
  DateTime? _lastRuntimeRecoveryStatusLogAt;
  Set<String> _preloadedProxyFlagCodes = const <String>{};
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  AppConnectionPhase _connectionPhase = AppConnectionPhase.idle;

  bool get _legalAccepted => _acceptedLegalVersion == _requiredLegalVersion;

  Subscription? get _activeSubscription {
    for (final subscription in _subscriptions) {
      if (subscription.id == _activeProfileId) {
        return subscription;
      }
    }
    return null;
  }

  AppProfileSummary? get _activeProfile {
    return _activeProfileCache;
  }

  Locale? get _locale =>
      _settings.localeCode == 'system' ? null : Locale(_settings.localeCode);
  ThemeMode get _themeMode => _settings.themeMode;
  AppThemePreference get _themePreference => _settings.themePreference;
  String get _accentColorHex => _settings.accentColorHex;
  AppPerformanceMode get _performanceMode => _settings.performanceMode;
  bool get _memoryLimitEnabled => _settings.memoryLimitEnabled;
  bool get _memoryLimitWarningDismissed =>
      _settings.memoryLimitWarningDismissed;
  AppUpdateInstallMode get _updateInstallMode => _settings.updateInstallMode;
  TlsFragmentationMode get _tlsFragmentationMode =>
      _settings.tlsFragmentationMode;
  bool get _hapticEnabled => _settings.hapticEnabled;
  bool get _hideServerIp => _settings.hideServerIp;
  bool get _vpnInboundEnabled => _settings.vpnInboundEnabled;
  int get _vpnMtu => _settings.vpnMtu;
  bool get _vpnStrictRoute => _settings.vpnStrictRoute;
  TunImplementationPreference get _vpnTunImplementation =>
      _settings.vpnTunImplementation;
  bool get _proxyInboundEnabled => _settings.proxyInboundEnabled;
  bool get _proxyAllowLan => _settings.proxyAllowLan;
  String get _proxyMixedListen => _settings.proxyMixedListen;
  int get _proxyMixedPort => _settings.proxyMixedPort;
  String get _proxyPassword => _settings.proxyPassword;
  String get _dnsDirectPreset => _settings.dnsDirectPreset;
  String get _dnsDirectResolver => _settings.dnsDirectResolver;
  String get _dnsProxyPreset => _settings.dnsProxyPreset;
  String get _dnsProxyResolver => _settings.dnsProxyResolver;
  bool get _dnsPreferIpv6 => _settings.dnsPreferIpv6;
  String get _russiaDnsDirectResolver => _settings.russiaDnsDirectResolver;
  String get _urlTestUrl => _settings.urlTestUrl;
  int get _urlTestIntervalSeconds => _settings.urlTestIntervalSeconds;
  int get _urlTestTimeoutSeconds => _settings.urlTestTimeoutSeconds;
  int get _urlTestConcurrency => _settings.urlTestConcurrency;
  int get _urlTestUnavailableCheckIntervalSeconds =>
      _settings.urlTestUnavailableCheckIntervalSeconds;
  int get _locationLookupLimit => _settings.locationLookupLimit;
  int get _locationLookupTimeoutSeconds =>
      _settings.locationLookupTimeoutSeconds;
  int get _locationLookupConcurrency => _settings.locationLookupConcurrency;
  bool get _blockLeaks => _settings.blockLeaks;
  bool get _adBlockEnabled => _settings.adBlockEnabled;
  set _adBlockEnabled(bool value) => _settings.adBlockEnabled = value;
  bool get _useRussiaRouteData => _settings.useRussiaRouteData;
  set _useRussiaRouteData(bool value) => _settings.useRussiaRouteData = value;
  bool get _bypassLocalNetwork => _settings.bypassLocalNetwork;
  SplitRoutingMode get _splitRoutingMode => _splitRoutingTemporarilyDisabled
      ? SplitRoutingMode.disabled
      : _settings.splitRoutingMode;
  List<String> get _splitRoutingPackages => _splitRoutingTemporarilyDisabled
      ? const <String>[]
      : _settings.splitRoutingPackages;
  String get _singBoxLogLevel => _settings.singBoxLogLevel;
  bool get _experimentalTcpFastOpen => _settings.experimentalTcpFastOpen;
  bool get _experimentalTcpMultiPath => _settings.experimentalTcpMultiPath;
  bool get _experimentalInterruptExistingConnections =>
      _settings.experimentalInterruptExistingConnections;
  bool get _experimentalUrlTestStrictTolerance =>
      _settings.experimentalUrlTestStrictTolerance;

  bool get _urlTestInFlight => _latencyCoordinator.isRunning;
  bool get _urlTestMethodInFlight => _latencyCoordinator.isRunning;
  bool get _manualUrlTestInFlight =>
      _latencyCoordinator.kind == LatencySessionKind.full;

  int? get _lowestLatency => _proxyRuntime.lowestLatency;
  set _lowestLatency(int? value) => _proxyRuntime.lowestLatency = value;

  String? get _runtimeLowestOutboundTag =>
      _proxyRuntime.runtimeLowestOutboundTag;
  set _runtimeLowestOutboundTag(String? value) =>
      _proxyRuntime.runtimeLowestOutboundTag = value;

  Map<String, String> get _runtimeLowestSelections =>
      _proxyRuntime.runtimeLowestSelections;

  Map<String, int> get _runtimeLatencies => _proxyRuntime.runtimeLatencies;

  Set<String> get _unavailableLatencyTags =>
      _proxyRuntime.unavailableLatencyTags;

  Map<String, String> get _latencyErrors => _proxyRuntime.latencyErrors;

  Map<String, int> get _latencyFailureCounts =>
      _proxyRuntime.latencyFailureCounts;

  Map<String, String> get _runtimeGroupSelections =>
      _proxyRuntime.runtimeGroupSelections;

  bool get _russiaRouteProxiesEnabled =>
      _useRussiaRouteData && _russiaRouteDataStatus.available;

  bool get _markAllServersRussia =>
      _activeSubscription?.markAllServersRussia ?? false;

  String? _runtimeLowestOutboundTagFor(String lowestTag) {
    return _proxyRuntime.runtimeLowestOutboundTagFor(lowestTag);
  }

  String? _activeRuntimeLowestOutboundTag() {
    if (!isLowestProxyTag(_selectedProxyTag)) {
      return null;
    }
    return _runtimeLowestOutboundTagFor(_selectedProxyTag);
  }

  Set<String> _activeMixedRuntimeLowestTags() {
    if (!isMixedProxyTag(_selectedProxyTag)) {
      return const <String>{};
    }
    _ensureActiveLookupCaches();
    final visibleOutbounds = _activeVisibleOutboundsLookup;
    if (visibleOutbounds.isEmpty) {
      return const <String>{};
    }
    final tags = <String>{};
    for (final lowestTag in lowestProxyTags) {
      final eligibleOutbounds = _lowestEligibleOutbounds(
        lowestTag,
        visibleOutbounds,
      );
      tags.add(eligibleOutbounds.isEmpty ? lowestProxyTag : lowestTag);
    }
    return tags;
  }

  Set<String> _activeMixedRuntimeOutboundTags() {
    if (!isMixedProxyTag(_selectedProxyTag)) {
      return const <String>{};
    }
    _ensureActiveLookupCaches();
    final visibleOutbounds = _activeVisibleOutboundsLookup;
    if (visibleOutbounds.isEmpty) {
      return const <String>{};
    }
    final tags = <String>{};
    final defaultEligible = _lowestEligibleOutbounds(
      lowestProxyTag,
      visibleOutbounds,
    );
    final defaultSelected = defaultEligible.isEmpty
        ? null
        : _lowestSelectedOutbound(lowestProxyTag, defaultEligible);
    for (final lowestTag in lowestProxyTags) {
      final runtimeSelectedTag = _runtimeLowestOutboundTagFor(lowestTag);
      if (runtimeSelectedTag != null && runtimeSelectedTag.isNotEmpty) {
        tags.add(runtimeSelectedTag);
      }
      final eligibleOutbounds = _lowestEligibleOutbounds(
        lowestTag,
        visibleOutbounds,
      );
      final selected = eligibleOutbounds.isEmpty
          ? defaultSelected
          : _lowestSelectedOutbound(lowestTag, eligibleOutbounds);
      if (selected != null) {
        tags.add(selected.tag);
      }
    }
    return tags;
  }

  List<Outbound> _lowestEligibleOutbounds(
    String lowestTag,
    List<Outbound> visibleOutbounds,
  ) {
    return visibleOutbounds
        .where(
          (outbound) => lowestProxyAllowsCountry(
            lowestTag,
            _effectiveOutboundCountry(outbound),
          ),
        )
        .toList(growable: false);
  }

  Outbound? _lowestSelectedOutbound(
    String lowestTag,
    List<Outbound> visibleOutbounds,
  ) {
    final runtimeSelectedTag = _runtimeLowestOutboundTagFor(lowestTag);
    if (runtimeSelectedTag != null && runtimeSelectedTag.isNotEmpty) {
      for (final outbound in visibleOutbounds) {
        if (outbound.tag == runtimeSelectedTag) {
          return outbound;
        }
      }
    }

    Outbound? bestOutbound;
    int? bestLatency;
    for (final outbound in visibleOutbounds) {
      if (_unavailableLatencyTags.contains(outbound.tag)) {
        continue;
      }
      final latency =
          _runtimeLatencies[outbound.tag] ?? outbound.info.latestPing;
      if (latency == null) {
        continue;
      }
      if (bestLatency == null || latency < bestLatency) {
        bestLatency = latency;
        bestOutbound = outbound;
      }
    }
    return bestOutbound ?? visibleOutbounds.first;
  }

  void _rebuildDerivedCaches() {
    ++_derivedCacheBuildGeneration;
    final subscription = _activeSubscription;
    if (subscription == null) {
      _derivedCacheBuildTimer?.cancel();
      _derivedCacheBuildTimer = null;
      _derivedCacheBuildQueued = false;
      _activeProfileCache = null;
      _displayProxyCache = null;
      _activeProxiesCache = const [];
      _activeGroupChildrenByTagCache = const <String, List<AppProxySummary>>{};
      _activeTopLevelProxiesCount = 0;
      _publishProxyRuntimeVisualStates();
      _publishTrafficDashboardSnapshot();
      unawaited(_syncQuickSettingsTileLabel());
      return;
    }
    _derivedCacheBuildQueued = true;
    _derivedCacheBuildTimer?.cancel();
    _derivedCacheBuildTimer = Timer(
      _derivedCacheBuildDebounce,
      _runDerivedCacheBuild,
    );
  }

  void _runDerivedCacheBuild() {
    _derivedCacheBuildTimer?.cancel();
    _derivedCacheBuildTimer = null;
    if (_derivedCacheBuildInFlight) {
      _derivedCacheBuildQueued = true;
      return;
    }
    final subscription = _activeSubscription;
    if (subscription == null) {
      _derivedCacheBuildQueued = false;
      _activeProfileCache = null;
      _displayProxyCache = null;
      _activeProxiesCache = const [];
      _activeGroupChildrenByTagCache = const <String, List<AppProxySummary>>{};
      _activeTopLevelProxiesCount = 0;
      _publishProxyRuntimeVisualStates();
      _publishTrafficDashboardSnapshot();
      unawaited(_syncQuickSettingsTileLabel());
      return;
    }

    final generation = _derivedCacheBuildGeneration;
    final input = _currentProxyCacheBuildInput(subscription);
    _derivedCacheBuildQueued = false;
    _derivedCacheBuildInFlight = true;
    unawaited(() async {
      try {
        final result = await buildProxyCacheInBackground(input);
        if (mounted && generation == _derivedCacheBuildGeneration) {
          setState(() {
            _activeProfileCache = result.activeProfile;
            _displayProxyCache = result.displayProxy;
            _activeProxiesCache = result.activeProxies;
            _activeGroupChildrenByTagCache = result.groupChildrenByTag;
            _activeTopLevelProxiesCount = result.totalTopLevelProxyCount;
          });
          _publishProxyRuntimeVisualStates();
          _publishTrafficDashboardSnapshot();
          _preloadProxyFlags();
          unawaited(_syncQuickSettingsTileLabel());
        }
      } finally {
        _derivedCacheBuildInFlight = false;
      }
      if (!mounted) {
        return;
      }
      if (_derivedCacheBuildQueued ||
          generation != _derivedCacheBuildGeneration) {
        _derivedCacheBuildQueued = false;
        _derivedCacheBuildTimer?.cancel();
        _derivedCacheBuildTimer = Timer(
          _derivedCacheBuildDebounce,
          _runDerivedCacheBuild,
        );
      }
    }());
  }

  ProxyCacheBuildInput _currentProxyCacheBuildInput(
    Subscription? subscription,
  ) {
    return ProxyCacheBuildInput(
      subscription: subscription,
      selectedProxyTag: _selectedProxyTag,
      lowestLatency: _lowestLatency,
      runtimeLowestOutboundTag: _runtimeLowestOutboundTag,
      runtimeLowestSelections: Map<String, String>.from(
        _runtimeLowestSelections,
      ),
      urlTestInFlight: _urlTestInFlight,
      runtimeLatencies: Map<String, int>.from(_runtimeLatencies),
      unavailableLatencyTags: Set<String>.from(_unavailableLatencyTags),
      latencyErrors: Map<String, String>.from(_latencyErrors),
      runtimeGroupSelections: Map<String, String>.from(_runtimeGroupSelections),
      russiaRouteProxiesEnabled: _russiaRouteProxiesEnabled,
      markAllServersRussia: subscription?.markAllServersRussia ?? false,
    );
  }

  AppProxySummary? get _displayProxy {
    return _displayProxyCache;
  }

  List<AppProxySummary> get _activeProxies {
    return _activeProxiesCache;
  }

  Map<String, List<AppProxySummary>> get _activeGroupChildrenByTag {
    return _activeGroupChildrenByTagCache;
  }

  ProxyRuntimeVisualState _runtimeVisualStateFor(AppProxySummary proxy) {
    final selecting =
        _connected &&
        _proxySelection.pendingRuntimeSelectTag != null &&
        _proxySelection.pendingRuntimeSelectTag == proxy.tag;
    return ProxyRuntimeVisualState(
      latency: proxy.latency,
      latencyFresh: proxy.latencyFresh,
      latencyChecking: proxy.latencyChecking,
      latencyUnavailable: proxy.latencyUnavailable,
      latencyError: proxy.latencyError,
      highlighted: proxy.highlighted,
      selecting: selecting,
    );
  }

  void _publishProxyRuntimeVisualStates() {
    final summariesByTag = <String, AppProxySummary>{
      for (final proxy in _activeProxiesCache) proxy.tag: proxy,
      for (final children in _activeGroupChildrenByTagCache.values)
        for (final proxy in children) proxy.tag: proxy,
    };
    final displayProxy = _displayProxyCache;
    if (displayProxy != null) {
      summariesByTag[displayProxy.tag] = displayProxy;
    }
    final mixedLowestTags = _activeMixedRuntimeLowestTags();
    final mixedOutboundTags = _activeMixedRuntimeOutboundTags();
    ProxyRuntimeVisualState runtimeStateFor(AppProxySummary proxy) {
      final runtimeProxy = _withRuntimeProxyState(
        proxy,
        summariesByTag,
        mixedLowestTags: mixedLowestTags,
        mixedOutboundTags: mixedOutboundTags,
      );
      return _runtimeVisualStateFor(runtimeProxy);
    }

    final next = <String, ProxyRuntimeVisualState>{
      for (final proxy in _activeProxiesCache)
        proxy.tag: runtimeStateFor(proxy),
      for (final children in _activeGroupChildrenByTagCache.values)
        for (final proxy in children) proxy.tag: runtimeStateFor(proxy),
    };
    if (displayProxy != null) {
      next[displayProxy.tag] = runtimeStateFor(displayProxy);
    }
    _proxyRuntimeVisualStates.replaceAll(next);
  }

  Future<bool> _networkInterfaceUsable({String reason = 'dart_check'}) async {
    try {
      final state = await SingboxRuntime.instance.getNetworkInterfaceState();
      if (state.usable) {
        _networkInterfaceGeneration = state.generation;
      }
      return state.usable;
    } catch (error) {
      AppLogStore.warning(
        'network',
        'failed to query network interface reason=$reason error=$error',
      );
      return false;
    }
  }

  bool _canRunNetworkRecoveryRestart() {
    final now = DateTime.now();
    if (_lastRecoveryRestartAt != null &&
        now.difference(_lastRecoveryRestartAt!) <
            _networkRecoveryRestartCooldown) {
      return false;
    }
    while (_networkRecoveryRestartHistory.isNotEmpty &&
        now.difference(_networkRecoveryRestartHistory.first) >
            _networkRecoveryWindow) {
      _networkRecoveryRestartHistory.removeFirst();
    }
    return _networkRecoveryRestartHistory.length <
        _networkRecoveryMaxRestartsPerWindow;
  }

  void _recordNetworkRecoveryRestart() {
    final now = DateTime.now();
    _lastRecoveryRestartAt = now;
    _networkRecoveryRestartHistory.addLast(now);
  }

  void _clearRuntimeInterfaceIssueWindow() {
    _runtimeInterfaceIssueTimes.clear();
    _lastRuntimeInterfaceIssueRecoveryAt = null;
  }

  void _handleRuntimeLogIssue(String reason, String message) {
    if (!mounted ||
        !_connected ||
        !_foregroundLifecycleActive ||
        _runtimeTransitionInProgress) {
      return;
    }
    final now = DateTime.now();
    _runtimeInterfaceIssueTimes.addLast(now);
    while (_runtimeInterfaceIssueTimes.isNotEmpty &&
        now.difference(_runtimeInterfaceIssueTimes.first) >
            _runtimeInterfaceIssueWindow) {
      _runtimeInterfaceIssueTimes.removeFirst();
    }
    final issueCount = _runtimeInterfaceIssueTimes.length;
    if (issueCount < _runtimeInterfaceIssueThreshold) {
      return;
    }
    if (_lastRuntimeInterfaceIssueRecoveryAt != null &&
        now.difference(_lastRuntimeInterfaceIssueRecoveryAt!) <
            _runtimeInterfaceIssueRecoveryCooldown) {
      return;
    }
    _lastRuntimeInterfaceIssueRecoveryAt = now;
    _runtimeInterfaceIssueTimes.clear();
    final shortMessage = message.length > 180
        ? message.substring(0, 180)
        : message;
    AppLogStore.warning(
      'network',
      'runtime_interface_issue_detected reason=$reason count=$issueCount '
          'selected=$_selectedProxyTag message=$shortMessage',
    );
    _scheduleNetworkRecovery(
      reason: reason,
      networkGeneration: _networkInterfaceGeneration,
      changedAt: now,
      forceRestartOnDecision: true,
    );
  }

  void _scheduleNetworkRecovery({
    required String reason,
    required int networkGeneration,
    DateTime? changedAt,
    bool forceRestartOnDecision = false,
  }) {
    if (!mounted ||
        !_connected ||
        !_foregroundLifecycleActive ||
        _runtimeTransitionInProgress) {
      return;
    }
    final startedAt = changedAt ?? DateTime.now();
    final generation = ++_networkReconnectGeneration;
    _networkReconnectWatchdogTimer?.cancel();
    _networkRecoveryDecisionTimer?.cancel();
    _networkReconnectWatchdogTimer = Timer(_networkRecoveryProbeDelay, () {
      if (!mounted ||
          generation != _networkReconnectGeneration ||
          !_connected ||
          !_foregroundLifecycleActive ||
          _runtimeTransitionInProgress) {
        return;
      }
      _triggerSelectedProxyUrlTest(showChecking: false, ignoreCooldown: true);
    });
    _networkRecoveryDecisionTimer = Timer(_networkRecoveryDecisionDelay, () {
      unawaited(
        _decideNetworkRecovery(
          reason: reason,
          generation: generation,
          networkGeneration: networkGeneration,
          changedAt: startedAt,
          forceRestartOnDecision: forceRestartOnDecision,
        ),
      );
    });
  }

  Future<void> _decideNetworkRecovery({
    required String reason,
    required int generation,
    required int networkGeneration,
    required DateTime changedAt,
    bool forceRestartOnDecision = false,
  }) async {
    if (!mounted ||
        generation != _networkReconnectGeneration ||
        !_connected ||
        !_foregroundLifecycleActive ||
        _runtimeTransitionInProgress) {
      return;
    }
    final statusFresh =
        _lastRuntimeStatusEventAt != null &&
        !_lastRuntimeStatusEventAt!.isBefore(changedAt);
    if (!forceRestartOnDecision && statusFresh && _trafficAvailable) {
      return;
    }
    final urlTestRunning = _urlTestMethodInFlight || _urlTestInFlight;
    if (urlTestRunning &&
        DateTime.now().difference(changedAt) < _networkRecoveryMaxUrlTestWait) {
      AppLogStore.info(
        'network',
        'recovery decision delayed reason=$reason '
            'networkGeneration=$networkGeneration selected=$_selectedProxyTag '
            'urlTestInFlight=$_urlTestInFlight '
            'urlTestMethodInFlight=$_urlTestMethodInFlight',
      );
      _networkRecoveryDecisionTimer?.cancel();
      _networkRecoveryDecisionTimer = Timer(
        _networkRecoveryDecisionRetryDelay,
        () {
          unawaited(
            _decideNetworkRecovery(
              reason: reason,
              generation: generation,
              networkGeneration: networkGeneration,
              changedAt: changedAt,
              forceRestartOnDecision: forceRestartOnDecision,
            ),
          );
        },
      );
      return;
    }
    if (!await _networkInterfaceUsable(reason: 'network_recovery_decision')) {
      AppLogStore.warning(
        'network',
        'recovery skipped reason=$reason networkGeneration=$networkGeneration '
            'selected=$_selectedProxyTag error=no_interface',
      );
      return;
    }
    final selectedTag = _currentResolvedActiveOutboundTag();
    final selectedRuntimeLatency = selectedTag == null
        ? null
        : _runtimeLatencies[selectedTag];
    final selectedRuntimeUnavailable =
        selectedTag != null && _unavailableLatencyTags.contains(selectedTag);
    if (!forceRestartOnDecision &&
        selectedRuntimeLatency != null &&
        !selectedRuntimeUnavailable) {
      return;
    }
    final selectedBad =
        forceRestartOnDecision ||
        selectedTag == null ||
        selectedRuntimeUnavailable ||
        selectedRuntimeLatency == null;
    if (!selectedBad && statusFresh) {
      return;
    }
    if (!_canRunNetworkRecoveryRestart()) {
      AppLogStore.warning(
        'network',
        'recovery restart suppressed reason=$reason '
            'networkGeneration=$networkGeneration selected=$selectedTag',
      );
      return;
    }
    _recordNetworkRecoveryRestart();
    AppLogStore.warning(
      'network',
      'recovery_restart reason=$reason '
          'networkGeneration=$networkGeneration selected=$selectedTag '
          'force=$forceRestartOnDecision',
    );
    await _configCoordinator.emitCurrentConfigLogAsync(
      'network recovery restart ($reason)',
      restartRuntime: true,
    );
  }

  void _preloadProxyFlags() {
    final codes = <String>{
      for (final proxy in _activeProxiesCache) proxy.countryCode,
      for (final children in _activeGroupChildrenByTagCache.values)
        for (final proxy in children) proxy.countryCode,
      if (_displayProxyCache != null) _displayProxyCache!.countryCode,
    }.map(CountryFlagBadge.circleFlagCodeFor).whereType<String>().toSet();
    if (codes.isEmpty || setEquals(codes, _preloadedProxyFlagCodes)) {
      return;
    }
    _preloadedProxyFlagCodes = codes;
    unawaited(CountryFlagBadge.preload(codes));
  }

  Outbound? _outboundForProxyTag(String tag) {
    final subscription = _activeSubscription;
    if (subscription == null) {
      return null;
    }
    for (final outbound in subscription.outbounds) {
      if (outbound.tag == tag && !outbound.info.deleted) {
        return outbound;
      }
    }
    return null;
  }

  Future<List<AppProfileSummary>> _loadProxyChainTargetSources() async {
    final activeId = _activeProfileId;
    final sources = _subscriptions
        .map(
          (subscription) => AppProfileSummary(
            id: subscription.id,
            name: subscription.name.trim().isEmpty
                ? 'Unnamed'
                : subscription.name.trim(),
            consumed: subscription.info?.consumed.toDouble() ?? 0,
            total: subscription.info?.total?.toDouble() ?? 0,
            remainingDays: subscription.info?.remainingDays,
            outboundsCount: subscription.outbounds
                .where((outbound) => !outbound.info.deleted)
                .where((outbound) => !_isGroupOnlyOutbound(outbound))
                .length,
            sourceLabel: '',
          ),
        )
        .toList(growable: false);
    sources.sort((a, b) {
      if (a.id == activeId) return -1;
      if (b.id == activeId) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sources;
  }

  Future<List<AppProxySummary>> _loadProxyChainTargetsForSource(
    String subscriptionId,
  ) async {
    final normalizedId = subscriptionId.trim();
    if (normalizedId.isEmpty) {
      return const [];
    }
    var subscription = _proxyChainTargetSourceCache[normalizedId];
    if (subscription == null) {
      for (final metadata in _subscriptions) {
        if (metadata.id != normalizedId) {
          continue;
        }
        subscription = metadata.outbounds.isNotEmpty
            ? metadata
            : await SubscriptionStore.withPayloadInBackground(metadata);
        _proxyChainTargetSourceCache[normalizedId] = subscription;
        break;
      }
    }
    if (subscription == null) {
      return const [];
    }
    return subscription.outbounds
        .where((outbound) => !outbound.info.deleted)
        .where((outbound) => !_isGroupOnlyOutbound(outbound))
        .map(
          (outbound) => _proxyChainTargetSummary(
            subscription: subscription!,
            outbound: outbound,
          ),
        )
        .toList(growable: false);
  }

  AppProxySummary _proxyChainTargetSummary({
    required Subscription subscription,
    required Outbound outbound,
  }) {
    final protocolLabel = _protocolLabel(outbound.config, outbound.type);
    final endpointLabel = _endpointLabel(outbound);
    final outboundName = outbound.name.trim().isEmpty
        ? outbound.tag
        : outbound.name.trim();
    final subscriptionName = subscription.name.trim();
    return AppProxySummary(
      tag: _proxyChainTargetRef(subscription.id, outbound.tag),
      displayName: subscriptionName.isEmpty
          ? outboundName
          : '$subscriptionName · $outboundName',
      countryCode: _normalizeCountryCode(outbound.info.country),
      type: outbound.type,
      server: outbound.server,
      port: outbound.port,
      detailText: '$protocolLabel · $endpointLabel',
      ip: outbound.info.externalIp?.trim() ?? '',
      latency: outbound.info.latestPing,
      latencyFresh: false,
      latencyChecking: false,
      latencyUnavailable: false,
      latencyError: null,
      protocolLabel: protocolLabel,
      endpointLabel: endpointLabel,
    );
  }

  String _proxyChainTargetRef(String subscriptionId, String outboundTag) =>
      '$subscriptionId\n$outboundTag';

  ({Subscription subscription, Outbound outbound})? _resolveProxyChainTarget(
    String targetRef,
  ) {
    final normalized = targetRef.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final parts = normalized.split('\n');
    if (parts.length >= 2) {
      final subscriptionId = parts.first.trim();
      final outboundTag = parts.sublist(1).join('\n').trim();
      final cached = _proxyChainTargetSourceCache[subscriptionId];
      if (cached != null) {
        for (final outbound in cached.outbounds) {
          if (outbound.tag == outboundTag && !outbound.info.deleted) {
            return (subscription: cached, outbound: outbound);
          }
        }
      }
      for (final metadata in _subscriptions) {
        if (metadata.id != subscriptionId) {
          continue;
        }
        var subscription = metadata;
        if (subscription.outbounds.isEmpty) {
          final payloadJson = SubscriptionStore.payloadJsonFor(subscription.id);
          if (payloadJson != null) {
            subscription = SubscriptionStore.hydratePayloadJson(
              subscription,
              payloadJson,
            );
          }
        }
        for (final outbound in subscription.outbounds) {
          if (outbound.tag == outboundTag && !outbound.info.deleted) {
            return (subscription: subscription, outbound: outbound);
          }
        }
      }
      return null;
    }
    _ensureActiveLookupCaches();
    final outbound = _activeOutboundByTagLookup[normalized];
    final subscription = _activeSubscription;
    if (subscription == null || outbound == null) {
      return null;
    }
    return (subscription: subscription, outbound: outbound);
  }

  SubscriptionProxyChain? _proxyChainForTag(String tag) {
    final subscription = _activeSubscription;
    if (subscription == null) {
      return null;
    }
    final normalizedTag = tag.trim();
    for (final chain in subscription.proxyChains) {
      if (chain.tag == normalizedTag) {
        return chain;
      }
    }
    return null;
  }

  bool _isProxyChainTag(String tag) => _proxyChainForTag(tag) != null;

  void _applyProxyCacheBuildResult(ProxyCacheBuildResult result) {
    ++_derivedCacheBuildGeneration;
    _derivedCacheBuildTimer?.cancel();
    _derivedCacheBuildTimer = null;
    _derivedCacheBuildQueued = false;
    _activeProfileCache = result.activeProfile;
    _displayProxyCache = result.displayProxy;
    _activeProxiesCache = result.activeProxies;
    _activeGroupChildrenByTagCache = result.groupChildrenByTag;
    _activeTopLevelProxiesCount = result.totalTopLevelProxyCount;
    _publishProxyRuntimeVisualStates();
    _publishTrafficDashboardSnapshot();
    _preloadProxyFlags();
  }

  void _applyMetadataActiveProfile(
    List<Subscription> subscriptions,
    String activeSubscriptionId, {
    required bool clearProxyCache,
  }) {
    Subscription? activeSubscription;
    for (final subscription in subscriptions) {
      if (subscription.id == activeSubscriptionId) {
        activeSubscription = subscription;
        break;
      }
    }
    _activeProfileCache = activeSubscription == null
        ? null
        : _metadataProfileSummary(activeSubscription);
    _publishTrafficDashboardSnapshot();
    if (!clearProxyCache) {
      return;
    }
    ++_derivedCacheBuildGeneration;
    _derivedCacheBuildTimer?.cancel();
    _derivedCacheBuildTimer = null;
    _derivedCacheBuildQueued = false;
    _displayProxyCache = null;
    _activeProxiesCache = const [];
    _activeGroupChildrenByTagCache = const <String, List<AppProxySummary>>{};
    _activeTopLevelProxiesCount = 0;
    _publishProxyRuntimeVisualStates();
    _publishTrafficDashboardSnapshot();
  }

  AppProfileSummary _metadataProfileSummary(Subscription subscription) {
    final info = subscription.info;
    return AppProfileSummary(
      id: subscription.id,
      name: subscription.name,
      consumed: info?.consumed.toDouble() ?? 0,
      total: info?.total?.toDouble() ?? 0,
      remainingDays: info?.remainingDays,
      outboundsCount: subscription.outbounds
          .where((outbound) => !outbound.info.deleted)
          .where((outbound) => outbound.config['_group_only'] != true)
          .length,
      sourceLabel: '',
    );
  }

  void _applyRuntimeStateToDerivedCaches() {
    if (_activeProxiesCache.isEmpty && _displayProxyCache == null) {
      return;
    }
    final previousSummariesByTag = <String, AppProxySummary>{
      for (final proxy in _activeProxiesCache) proxy.tag: proxy,
      for (final children in _activeGroupChildrenByTagCache.values)
        for (final proxy in children) proxy.tag: proxy,
    };
    final previousDisplayProxy = _displayProxyCache;
    if (previousDisplayProxy != null) {
      previousSummariesByTag[previousDisplayProxy.tag] = previousDisplayProxy;
    }
    final mixedLowestTags = _activeMixedRuntimeLowestTags();
    final mixedOutboundTags = _activeMixedRuntimeOutboundTags();
    _activeProxiesCache = _activeProxiesCache
        .map(
          (proxy) => _withRuntimeProxyState(
            proxy,
            previousSummariesByTag,
            mixedLowestTags: mixedLowestTags,
            mixedOutboundTags: mixedOutboundTags,
          ),
        )
        .toList(growable: false);
    _activeGroupChildrenByTagCache = {
      for (final entry in _activeGroupChildrenByTagCache.entries)
        entry.key: entry.value
            .map(
              (proxy) => _withRuntimeProxyState(
                proxy,
                previousSummariesByTag,
                mixedLowestTags: mixedLowestTags,
                mixedOutboundTags: mixedOutboundTags,
              ),
            )
            .toList(growable: false),
    };
    final summariesByTag = <String, AppProxySummary>{
      for (final proxy in _activeProxiesCache) proxy.tag: proxy,
      for (final children in _activeGroupChildrenByTagCache.values)
        for (final proxy in children) proxy.tag: proxy,
    };
    final currentDisplay = _displayProxyCache;
    if (currentDisplay != null) {
      summariesByTag[currentDisplay.tag] = currentDisplay;
    }
    _displayProxyCache = currentDisplay == null
        ? null
        : _withRuntimeProxyState(
            currentDisplay,
            summariesByTag,
            mixedLowestTags: mixedLowestTags,
            mixedOutboundTags: mixedOutboundTags,
          );
    _publishProxyRuntimeVisualStates();
    _publishTrafficDashboardSnapshot();
  }

  AppProxySummary? _displayProxyForSelectedTag(String tag) {
    final normalizedTag = tag.trim();
    if (normalizedTag.isEmpty) {
      return null;
    }
    final currentDisplay = _displayProxyCache;
    if (currentDisplay != null && currentDisplay.tag == normalizedTag) {
      return currentDisplay;
    }
    for (final proxy in _activeProxiesCache) {
      if (proxy.tag == normalizedTag) {
        return proxy;
      }
    }

    _ensureActiveLookupCaches();
    if (isMixedProxyTag(normalizedTag)) {
      return _displaySummaryForMixedProxy();
    }
    if (isLowestProxyTag(normalizedTag)) {
      final eligibleOutbounds = _lowestEligibleOutbounds(
        normalizedTag,
        _activeVisibleOutboundsLookup,
      );
      final defaultOutbounds = _lowestEligibleOutbounds(
        lowestProxyTag,
        _activeVisibleOutboundsLookup,
      );
      if (eligibleOutbounds.isEmpty && defaultOutbounds.isEmpty) {
        return null;
      }
      final selectedOutbound = _lowestSelectedOutbound(
        normalizedTag,
        eligibleOutbounds.isEmpty ? defaultOutbounds : eligibleOutbounds,
      );
      if (selectedOutbound == null) {
        return null;
      }
      final selectedSummary = _displaySummaryForOutbound(selectedOutbound);
      return selectedSummary.copyWith(
        tag: normalizedTag,
        displayName: lowestProxyDisplayName(
          normalizedTag,
          selectedSummary.displayName,
        ),
        detailText: 'URLTest · ${selectedSummary.displayName}',
        protocolLabel: 'URLTest · ${selectedSummary.protocolLabel}',
        highlighted: true,
      );
    }

    final group = _activeGroupByTagLookup[normalizedTag];
    if (group != null) {
      return _displaySummaryForGroup(group);
    }
    final chain = _proxyChainForTag(normalizedTag);
    if (chain != null) {
      return _displaySummaryForProxyChain(chain);
    }
    final outbound = _activeOutboundByTagLookup[normalizedTag];
    if (outbound != null) {
      return _displaySummaryForOutbound(outbound);
    }
    return null;
  }

  AppProxySummary? _displaySummaryForProxyChain(SubscriptionProxyChain chain) {
    final tag = chain.tag.trim();
    final target = _targetOutboundForProxyChain(chain);
    if (tag.isEmpty || target == null) {
      return null;
    }
    final targetSummary = _displaySummaryForOutbound(target);
    final detourName = _proxyDisplayNameForTag(chain.detourTag);
    final runtimeLatency = _runtimeLatencies[tag];
    final latencyUnavailable = _unavailableLatencyTags.contains(tag);
    final latencyError = _latencyErrors[tag];
    return targetSummary.copyWith(
      tag: tag,
      displayName: chain.name.trim().isEmpty
          ? '$detourName -> ${targetSummary.displayName}'
          : chain.name.trim(),
      detailText: 'Chain · $detourName -> ${targetSummary.displayName}',
      protocolLabel: 'Chain · ${targetSummary.protocolLabel}',
      countryCode: _normalizeCountryCode(target.info.country).isNotEmpty
          ? _normalizeCountryCode(target.info.country)
          : _normalizeCountryCode(chain.targetCountry),
      latency: runtimeLatency ?? targetSummary.latency,
      clearLatency:
          runtimeLatency == null &&
          targetSummary.latency == null &&
          latencyUnavailable,
      latencyFresh: runtimeLatency != null || targetSummary.latencyFresh,
      latencyChecking: _urlTestInFlight,
      latencyUnavailable: latencyUnavailable,
      latencyError: latencyError,
      clearLatencyError: latencyError == null,
      highlighted: _selectedProxyTag == tag,
    );
  }

  AppProxySummary _displaySummaryForOutbound(Outbound outbound) {
    final protocolLabel = _protocolLabel(outbound.config, outbound.type);
    final endpointLabel = _endpointLabel(outbound);
    final runtimeLatency = _runtimeLatencies[outbound.tag];
    final latencyUnavailable = _unavailableLatencyTags.contains(outbound.tag);
    return AppProxySummary(
      tag: outbound.tag,
      displayName: outbound.name.trim().isEmpty ? outbound.tag : outbound.name,
      countryCode: _effectiveOutboundCountry(outbound),
      type: outbound.type,
      server: outbound.server,
      port: outbound.port,
      detailText: '$protocolLabel · $endpointLabel',
      ip: outbound.info.externalIp?.trim() ?? '',
      latency: runtimeLatency ?? outbound.info.latestPing,
      latencyFresh: runtimeLatency != null || outbound.info.latestPing != null,
      latencyChecking: _urlTestInFlight,
      latencyUnavailable: latencyUnavailable,
      latencyError: _latencyErrors[outbound.tag],
      protocolLabel: protocolLabel,
      endpointLabel: endpointLabel,
      highlighted: _selectedProxyTag == outbound.tag,
    );
  }

  AppProxySummary _displaySummaryForGroup(SubscriptionGroup group) {
    final visibleChildTags = group.outboundTags
        .where((tag) => _activeOutboundByTagLookup.containsKey(tag))
        .toList(growable: false);
    final selectedChild = _selectedGroupOutbound(group);
    final selectedSummary = selectedChild == null
        ? null
        : _displaySummaryForOutbound(selectedChild);
    final selectedCountry = selectedSummary?.countryCode.trim() ?? '';
    final groupCountry = _markAllServersRussia
        ? 'RU'
        : _normalizeCountryCode(group.country);
    final selectedChildName =
        selectedSummary?.displayName ?? selectedChild?.name.trim();
    final hasSelectedChild =
        selectedChildName != null && selectedChildName.isNotEmpty;
    final childCount = visibleChildTags.isEmpty
        ? group.outboundTags.length
        : visibleChildTags.length;
    return AppProxySummary(
      tag: group.tag,
      displayName: group.name.trim().isEmpty ? group.tag : group.name,
      countryCode: selectedCountry.isNotEmpty ? selectedCountry : groupCountry,
      type: 'urltest',
      server: '',
      port: 0,
      detailText: hasSelectedChild
          ? 'URLTest · $selectedChildName'
          : 'URLTest · $childCount outbounds',
      ip: selectedSummary?.ip ?? '',
      latency: selectedSummary?.latency,
      latencyFresh: selectedSummary?.latencyFresh ?? false,
      latencyChecking:
          _urlTestInFlight || (selectedSummary?.latencyChecking ?? false),
      latencyUnavailable: selectedSummary?.latencyUnavailable ?? false,
      latencyError: selectedSummary?.latencyError,
      protocolLabel: hasSelectedChild
          ? 'URLTest · $selectedChildName'
          : 'URLTest · $childCount outbounds',
      endpointLabel: selectedSummary?.endpointLabel ?? '',
      isGroup: true,
      childCount: childCount,
      selectedChildTag: selectedChild?.tag,
      selectedChildName: selectedChildName,
      highlighted: true,
    );
  }

  AppProxySummary? _displaySummaryForMixedProxy() {
    if (_activeVisibleOutboundsLookup.isEmpty) {
      return null;
    }
    final eligibleOutbounds = _lowestEligibleOutbounds(
      lowestProxyTag,
      _activeVisibleOutboundsLookup,
    );
    if (eligibleOutbounds.isEmpty) {
      return null;
    }
    final selectedOutbound = _lowestSelectedOutbound(
      lowestProxyTag,
      eligibleOutbounds,
    );
    final selectedSummary = selectedOutbound == null
        ? null
        : _displaySummaryForOutbound(selectedOutbound);
    return AppProxySummary(
      tag: mixedProxyTag,
      displayName: 'mixed',
      countryCode: selectedSummary?.countryCode ?? '',
      type: 'selector',
      server: '',
      port: 0,
      detailText: 'AI -> lowest · free · TG/RU blocked -> lowest · open',
      ip: selectedSummary?.ip ?? '',
      latency: selectedSummary?.latency ?? _lowestLatency,
      latencyFresh: selectedSummary?.latencyFresh ?? (_lowestLatency != null),
      latencyChecking: _urlTestInFlight,
      latencyUnavailable: selectedSummary?.latencyUnavailable ?? false,
      latencyError: selectedSummary?.latencyError,
      protocolLabel: 'Routing',
      endpointLabel: selectedSummary?.endpointLabel ?? '',
      childTags: const [lowestProxyTag, lowestOpenProxyTag, lowestFreeProxyTag],
      childCount: 3,
      highlighted: _selectedProxyTag == mixedProxyTag,
    );
  }

  AppProxySummary _withRuntimeProxyState(
    AppProxySummary proxy,
    Map<String, AppProxySummary> summariesByTag, {
    Set<String> mixedLowestTags = const <String>{},
    Set<String> mixedOutboundTags = const <String>{},
  }) {
    if (isMixedProxyTag(proxy.tag)) {
      final selectedLowest =
          summariesByTag[lowestProxyTag] ?? _displaySummaryForMixedProxy();
      if (selectedLowest == null) {
        return proxy.copyWith(
          latency: _lowestLatency,
          clearLatency: _lowestLatency == null,
          latencyFresh: _lowestLatency != null,
          latencyChecking: _urlTestInFlight,
          highlighted: proxy.tag == _selectedProxyTag,
        );
      }
      return proxy.copyWith(
        countryCode: selectedLowest.countryCode,
        ip: selectedLowest.ip,
        ipChecking: selectedLowest.ipChecking,
        latency: selectedLowest.latency ?? _lowestLatency,
        clearLatency: selectedLowest.latency == null && _lowestLatency == null,
        latencyFresh: selectedLowest.latencyFresh || _lowestLatency != null,
        latencyChecking: _urlTestInFlight || selectedLowest.latencyChecking,
        latencyUnavailable: selectedLowest.latencyUnavailable,
        latencyError: selectedLowest.latencyError,
        clearLatencyError: selectedLowest.latencyError == null,
        endpointLabel: selectedLowest.endpointLabel,
        highlighted: proxy.tag == _selectedProxyTag,
      );
    }

    if (isLowestProxyTag(proxy.tag)) {
      final selectedTag = _runtimeLowestOutboundTagFor(proxy.tag);
      final selected = selectedTag == null ? null : summariesByTag[selectedTag];
      final highlightedByMixed = mixedLowestTags.contains(proxy.tag);
      if (selected == null) {
        return proxy.copyWith(
          displayName: lowestProxyBaseLabel(proxy.tag),
          latency: _lowestLatency,
          clearLatency: _lowestLatency == null,
          latencyFresh: _lowestLatency != null,
          latencyChecking: _urlTestInFlight,
          latencyUnavailable:
              _lowestLatency == null &&
              !_urlTestInFlight &&
              _unavailableLatencyTags.isNotEmpty,
          highlighted: proxy.tag == _selectedProxyTag || highlightedByMixed,
        );
      }
      final selectedWithRuntime = _withDirectRuntimeProxyState(
        selected,
        mixedOutboundTags: mixedOutboundTags,
      );
      return proxy.copyWith(
        displayName: lowestProxyDisplayName(
          proxy.tag,
          selectedWithRuntime.displayName,
        ),
        countryCode: selectedWithRuntime.countryCode,
        type: selectedWithRuntime.type,
        detailText: 'URLTest · ${selectedWithRuntime.displayName}',
        ip: selectedWithRuntime.ip,
        ipChecking: selectedWithRuntime.ipChecking,
        latency: selectedWithRuntime.latency ?? _lowestLatency,
        clearLatency:
            selectedWithRuntime.latency == null && _lowestLatency == null,
        latencyFresh:
            selectedWithRuntime.latencyFresh || _lowestLatency != null,
        latencyChecking:
            _urlTestInFlight || selectedWithRuntime.latencyChecking,
        latencyUnavailable: selectedWithRuntime.latencyUnavailable,
        latencyError: selectedWithRuntime.latencyError,
        clearLatencyError: selectedWithRuntime.latencyError == null,
        protocolLabel: 'URLTest · ${selectedWithRuntime.protocolLabel}',
        endpointLabel: selectedWithRuntime.endpointLabel,
        highlighted: proxy.tag == _selectedProxyTag || highlightedByMixed,
      );
    }

    if (proxy.isGroup) {
      final fullChildTags = _fullChildTagsForProxy(proxy);
      final runtimeSelected = _runtimeGroupSelections[proxy.tag];
      final selectedChildTag =
          runtimeSelected != null && fullChildTags.contains(runtimeSelected)
          ? runtimeSelected
          : proxy.selectedChildTag;
      final selectedChild = selectedChildTag == null
          ? null
          : summariesByTag[selectedChildTag];
      final selectedChildWithRuntime = selectedChild == null
          ? null
          : _withDirectRuntimeProxyState(
              selectedChild,
              mixedOutboundTags: mixedOutboundTags,
            );
      final selectedCountry =
          selectedChildWithRuntime?.countryCode.trim() ?? '';
      final selectedChildName =
          selectedChildWithRuntime?.displayName ?? proxy.selectedChildName;
      final hasSelectedChild =
          selectedChildName != null && selectedChildName.isNotEmpty;
      final childCount = proxy.childCount > 0
          ? proxy.childCount
          : proxy.childTags.length;
      final childSelectedByUser = _tagsContain(
        fullChildTags,
        _selectedProxyTag,
      );
      final childSelectedByLowest = _tagsContain(
        fullChildTags,
        _activeRuntimeLowestOutboundTag(),
      );
      final selectedByLowest =
          isLowestProxyTag(_selectedProxyTag) &&
          _activeRuntimeLowestOutboundTag() == proxy.tag;
      final selectedByMixed = mixedOutboundTags.contains(proxy.tag);
      final childSelectedByMixed = mixedOutboundTags.any(
        fullChildTags.contains,
      );
      final unavailable =
          selectedChildWithRuntime?.latencyUnavailable ??
          proxy.latencyUnavailable;
      return proxy.copyWith(
        countryCode: selectedCountry.isNotEmpty
            ? selectedCountry
            : proxy.countryCode,
        detailText: hasSelectedChild
            ? 'URLTest · $selectedChildName'
            : 'URLTest · $childCount outbounds',
        ip: selectedChildWithRuntime?.ip ?? proxy.ip,
        ipChecking: selectedChildWithRuntime?.ipChecking ?? false,
        latency: selectedChildWithRuntime?.latency,
        clearLatency: selectedChildWithRuntime?.latency == null,
        latencyFresh: selectedChildWithRuntime?.latencyFresh ?? false,
        latencyChecking:
            _urlTestInFlight ||
            (selectedChildWithRuntime?.latencyChecking ?? false),
        latencyUnavailable: unavailable,
        latencyError: selectedChildWithRuntime?.latencyError,
        clearLatencyError: selectedChildWithRuntime?.latencyError == null,
        protocolLabel: hasSelectedChild
            ? 'URLTest · $selectedChildName'
            : 'URLTest · $childCount outbounds',
        endpointLabel:
            selectedChildWithRuntime?.endpointLabel ?? proxy.endpointLabel,
        selectedChildTag: selectedChildTag,
        clearSelectedChildTag: selectedChildTag == null,
        selectedChildName: selectedChildName,
        clearSelectedChildName: selectedChildName == null,
        highlighted:
            _selectedProxyTag == proxy.tag ||
            childSelectedByUser ||
            selectedByLowest ||
            selectedByMixed ||
            (isLowestProxyTag(_selectedProxyTag) && childSelectedByLowest) ||
            childSelectedByMixed,
      );
    }

    return _withDirectRuntimeProxyState(
      proxy,
      mixedOutboundTags: mixedOutboundTags,
    );
  }

  AppProxySummary _withDirectRuntimeProxyState(
    AppProxySummary proxy, {
    Set<String> mixedOutboundTags = const <String>{},
  }) {
    final selectedRuntimeUrlTestChecking = _latencyCoordinator.isChecking(
      proxy.tag,
    );
    final runtimeLatency = _runtimeLatencies[proxy.tag];
    final latencyUnavailable =
        ProxyRuntimeController.effectiveLatencyUnavailable(
          urlTestUnavailable: _unavailableLatencyTags.contains(proxy.tag),
          endpointFallbackReachable: false,
        );
    final latencyError = ProxyRuntimeController.effectiveLatencyError(
      urlTestError: _latencyErrors[proxy.tag],
      endpointFallbackReachable: false,
    );
    final parentGroupTag = proxy.parentGroupTag;
    final highlightedByGroupUrlTest =
        parentGroupTag != null &&
        _runtimeGroupSelections[parentGroupTag] == proxy.tag;
    final highlightedByLowest =
        isLowestProxyTag(_selectedProxyTag) &&
        _activeRuntimeLowestOutboundTag() == proxy.tag;
    final highlightedByMixed = mixedOutboundTags.contains(proxy.tag);
    final shouldClearLatency = runtimeLatency == null && latencyUnavailable;
    final activeIpMatches =
        _connected && _activeProxyIp.outboundTag == proxy.tag;
    final activeIpOverride = activeIpMatches && _activeProxyIp.hasKnownIp
        ? _activeProxyIp.ip
        : null;
    final activeIpChecking =
        activeIpMatches && _activeProxyIp.state == ActiveProxyIpState.checking;
    return proxy.copyWith(
      ip: activeIpOverride,
      ipChecking: activeIpChecking,
      latency: runtimeLatency,
      clearLatency: shouldClearLatency,
      latencyFresh: runtimeLatency != null && latencyError == null,
      latencyChecking: _manualUrlTestInFlight || selectedRuntimeUrlTestChecking,
      latencyUnavailable: latencyUnavailable,
      latencyError: latencyError,
      clearLatencyError: latencyError == null,
      highlighted:
          highlightedByGroupUrlTest ||
          highlightedByLowest ||
          highlightedByMixed ||
          _selectedProxyTag == proxy.tag,
    );
  }

  List<String> _fullChildTagsForProxy(AppProxySummary proxy) {
    _ensureActiveLookupCaches();
    final group = _activeGroupByTagLookup[proxy.tag];
    return group?.outboundTags ?? proxy.childTags;
  }

  bool _tagsContain(List<String> tags, String? tag) {
    final normalized = tag?.trim() ?? '';
    if (normalized.isEmpty) {
      return false;
    }
    return tags.contains(normalized);
  }

  bool _proxyCacheContainsTag(String? tag) {
    final normalized = tag?.trim() ?? '';
    if (normalized.isEmpty) {
      return false;
    }
    if (_displayProxyCache?.tag == normalized) {
      return true;
    }
    for (final proxy in _activeProxiesCache) {
      if (proxy.tag == normalized) {
        return true;
      }
    }
    for (final children in _activeGroupChildrenByTagCache.values) {
      for (final proxy in children) {
        if (proxy.tag == normalized) {
          return true;
        }
      }
    }
    return false;
  }

  bool _visibleGroupProxyCacheMissingChild(String groupTag, String childTag) {
    final normalizedGroupTag = groupTag.trim();
    final normalizedChildTag = childTag.trim();
    if (normalizedGroupTag.isEmpty || normalizedChildTag.isEmpty) {
      return false;
    }
    for (final proxy in _activeProxiesCache) {
      if (!proxy.isGroup || proxy.tag != normalizedGroupTag) {
        continue;
      }
      final cachedChildren = _activeGroupChildrenByTagCache[normalizedGroupTag];
      if (cachedChildren == null) {
        return !proxy.childTags.contains(normalizedChildTag);
      }
      return !cachedChildren.any((child) => child.tag == normalizedChildTag);
    }
    return false;
  }

  void _ensureActiveLookupCaches() {
    final subscription = _activeSubscription;
    if (identical(subscription, _activeLookupSubscription)) {
      return;
    }
    _activeLookupSubscription = subscription;
    if (subscription == null) {
      _activeVisibleOutboundsLookup = const [];
      _activeOutboundByTagLookup = const {};
      _activeGroupByTagLookup = const {};
      return;
    }
    final visibleOutbounds = <Outbound>[];
    final outboundByTag = <String, Outbound>{};
    for (final outbound in subscription.outbounds) {
      if (outbound.info.deleted) {
        continue;
      }
      outboundByTag[outbound.tag] = outbound;
      if (_isGroupOnlyOutbound(outbound)) {
        continue;
      }
      visibleOutbounds.add(outbound);
    }
    _activeVisibleOutboundsLookup = visibleOutbounds;
    _activeOutboundByTagLookup = outboundByTag;
    _activeGroupByTagLookup = {
      for (final group in subscription.groups) group.tag: group,
    };
  }

  bool _isGroupOnlyOutbound(Outbound outbound) {
    return outbound.config['_group_only'] == true;
  }

  bool get _resolvingLowestProxy {
    if (!_connected || !isLowestProxyTag(_selectedProxyTag)) {
      return false;
    }
    final proxy = _displayProxy;
    final waitingForPing =
        proxy != null &&
        !proxy.latencyUnavailable &&
        (proxy.latencyChecking || !proxy.latencyFresh || proxy.latency == null);
    return _urlTestInFlight ||
        waitingForPing ||
        _currentResolvedActiveOutbound() == null;
  }

  String? _countryFlagEmoji(String? countryCode) {
    final normalizedCode = countryCode?.trim().toUpperCase() ?? '';
    if (!_quickTileCountryCodePattern.hasMatch(normalizedCode)) {
      return null;
    }
    final resolvedCode = switch (normalizedCode) {
      'UK' => 'GB',
      _ => normalizedCode,
    };
    final codeUnits = resolvedCode.codeUnits
        .map((unit) => 0x1F1A5 + unit)
        .toList(growable: false);
    return String.fromCharCodes(codeUnits);
  }

  String? _buildQuickSettingsTileLabel() {
    final proxyName = _displayProxy?.displayName.trim();
    if (proxyName != null && proxyName.isNotEmpty) {
      final flag = _countryFlagEmoji(_displayProxy?.countryCode);
      final normalizedName = isLowestProxyTag(_displayProxy?.tag ?? '')
          ? 'Авто'
          : proxyName;
      return flag == null ? normalizedName : '$flag $normalizedName';
    }
    final profileName = _activeProfile?.name.trim();
    if (profileName != null && profileName.isNotEmpty) {
      return profileName;
    }
    return null;
  }

  Future<void> _syncQuickSettingsTileLabel() async {
    final nextLabel = _buildQuickSettingsTileLabel();
    if (_lastQuickSettingsTileLabel == nextLabel) {
      return;
    }
    _lastQuickSettingsTileLabel = nextLabel;
    await SingboxRuntime.instance.setQuickSettingsTileLabel(nextLabel);
  }

  @override
  void initState() {
    super.initState();
    _latencyCoordinator = LatencyCoordinator(
      runTest: (request) => SingboxRuntime.instance.urlTest(
        groupTag: request.groupTag,
        targetOutboundTag: request.targetOutboundTag,
        priorityOutboundTag: request.priorityOutboundTag,
        excludeOutboundTag: request.excludeOutboundTag,
        url: request.url,
        timeoutMillis: request.timeoutMillis,
        concurrency: request.concurrency,
        deadlineMillis: request.deadlineMillis,
        force: request.force,
      ),
      isConnected: () => _connected,
      isForeground: () => _foregroundLifecycleActive,
      activeOutboundTag: () => _currentResolvedActiveOutboundTag() ?? '',
      testUrl: () => _urlTestUrl,
      outboundCount: () {
        _ensureActiveLookupCaches();
        return _activeVisibleOutboundsLookup.length;
      },
      onSessionChanged: (running, kind, targetTag) {
        if (!mounted) return;
        if (running) {
          _latencyFinalizeTimer?.cancel();
          _latencySessionGeneration++;
          _proxyRuntime.beginLatencySession();
        } else if (kind != null) {
          final generation = _latencySessionGeneration;
          _latencyFinalizeTimer?.cancel();
          _latencyFinalizeTimer = Timer(const Duration(milliseconds: 180), () {
            if (!mounted ||
                generation != _latencySessionGeneration ||
                _latencyCoordinator.isRunning) {
              return;
            }
            _ensureActiveLookupCaches();
            final changed = _proxyRuntime.finishLatencySession(
              kind == LatencySessionKind.active && targetTag.isNotEmpty
                  ? <String>[targetTag]
                  : _activeOutboundByTagLookup.keys,
            );
            if (changed) {
              setState(_applyRuntimeStateToDerivedCaches);
            }
          });
        }
        setState(_applyRuntimeStateToDerivedCaches);
        unawaited(_syncQuickSettingsTileLabel());
      },
    );
    _configCoordinator = SingboxConfigCoordinator(
      readSnapshot: _currentSingboxConfigSnapshot,
      isMounted: () => mounted,
      ensureActiveSubscriptionHydrated:
          _ensureActiveSubscriptionHydratedForRuntime,
      runtimeLifecycle: _runtimeLifecycle,
      applyStartupValidationResult: _applyStartupValidationResult,
      showNoValidOutboundsWarning: _showNoValidOutboundsWarning,
      setPhase: _setConfigCoordinatorPhase,
      showRuntimeFailure: _showRuntimeConfigFailure,
      logCall: _logLibboxCall,
      trimRuntimeStartMemory: _trimRuntimeStartMemory,
      onRuntimeLifecycleTimeout: _handleRuntimeLifecycleTimeout,
      cacheStartedBuild: _cacheLastStartedBuild,
      schedulePostConnectSelectedProxyUrlTest:
          _schedulePostConnectSelectedProxyUrlTest,
      syncRuntimeState: _syncRuntimeState,
    );
    _runtimeEvents = RuntimeEventController(
      events: SingboxRuntime.instance.events,
      onState: _handleRuntimeStateEvent,
      onStatus: _handleTrafficStatusEvent,
      onNetwork: _handleRuntimeNetworkEvent,
      onGroups: _applyGroupUpdates,
      shouldRecordLog: _shouldRecordSingBoxLog,
      onRuntimeLogIssue: _handleRuntimeLogIssue,
    );
    WidgetsBinding.instance.addObserver(this);
    _configureImageCacheForAndroid();
    _refreshThemeCache();
    _startDeepLinkHandling();
    unawaited(_refreshAppVersionInfo());
    unawaited(_bootstrap());
  }

  Future<AppVersionInfo> _readAppVersionInfo() async {
    try {
      final info = await SingboxRuntime.instance.getAppVersionInfo();
      if (info.versionName.trim().isEmpty) {
        return const AppVersionInfo(
          packageName: '',
          versionName: _fallbackClientVersionLabel,
          versionCode: 0,
        );
      }
      return info;
    } catch (error) {
      AppLogStore.warning('app version', 'Failed to read app version: $error');
      return const AppVersionInfo(
        packageName: '',
        versionName: _fallbackClientVersionLabel,
        versionCode: 0,
      );
    }
  }

  Future<void> _refreshAppVersionInfo() async {
    final info = await _readAppVersionInfo();
    if (!mounted) return;
    final nextVersion = info.displayVersion;
    final nextBuildNumber = info.updateBuildNumber;
    if (_clientVersionLabel == nextVersion &&
        _clientVersionCode == nextBuildNumber &&
        _clientPackageName == info.packageName) {
      return;
    }
    setState(() {
      _clientVersionLabel = nextVersion;
      _clientVersionCode = nextBuildNumber;
      _clientPackageName = info.packageName;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscriptionAutoRefreshTimer?.cancel();
    _latencyCoordinator.dispose();
    _invalidOutboundRetryTimer?.cancel();
    _locationLookupTimer?.cancel();
    _resumeForegroundSyncTimer?.cancel();
    _networkReconnectWatchdogTimer?.cancel();
    _postConnectUrlTestTimer?.cancel();
    _networkRecoveryDecisionTimer?.cancel();
    _latencyFinalizeTimer?.cancel();
    _runtimeLifecycle.dispose();
    _activeProxyIpController.dispose();
    _proxySelection.dispose();
    _locationLookupRefreshRequested = false;
    for (final waiter in _locationLookupWaiters) {
      if (!waiter.isCompleted) {
        waiter.complete(false);
      }
    }
    _locationLookupWaiters.clear();
    _derivedCacheBuildTimer?.cancel();
    _trafficUiUpdateTimer?.cancel();
    unawaited(_runtimeEvents.dispose());
    _deepLinkImportSubscription?.cancel();
    final store = _store;
    if (_ownsStore && store != null) {
      unawaited(store.close());
    }
    _proxyRuntime.dispose();
    _proxyRuntimeVisualStates.dispose();
    _trafficDashboardSnapshot.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_appLifecycleState == state) {
      return;
    }
    _appLifecycleState = state;
    if (_foregroundLifecycleActive) {
      _resumeForegroundWork();
    } else {
      _suspendForegroundWork();
    }
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    _runMemoryPressureCleanup('system_memory_pressure');
  }

  void _configureImageCacheForAndroid() {
    if (!Platform.isAndroid) {
      return;
    }
    final cache = PaintingBinding.instance.imageCache;
    if (cache.maximumSizeBytes > _androidImageCacheMaximumBytes) {
      cache.maximumSizeBytes = _androidImageCacheMaximumBytes;
    }
    if (cache.maximumSize > _androidImageCacheMaximumEntries) {
      cache.maximumSize = _androidImageCacheMaximumEntries;
    }
  }

  void _runMemoryPressureCleanup(String reason) {
    final cache = PaintingBinding.instance.imageCache;
    final imageBytesBefore = cache.currentSizeBytes;
    final imageEntriesBefore = cache.currentSize;
    final proxyCacheBefore = _activeProxiesCache.length;
    final groupCacheBefore = _activeGroupChildrenByTagCache.length;
    final samplesBefore = _trafficSamples.length;
    final installedAppsBefore = _installedAppsCache.length;

    cache.clear();
    cache.clearLiveImages();
    _configureImageCacheForAndroid();
    clearInstalledAppIconCache();
    _clearInstalledAppsCache();

    ++_derivedCacheBuildGeneration;
    _derivedCacheBuildTimer?.cancel();
    _derivedCacheBuildTimer = null;
    _derivedCacheBuildQueued = false;
    _derivedCacheBuildInFlight = false;
    _proxyChainTargetSourceCache.clear();
    _activeProxiesCache = const <AppProxySummary>[];
    _displayProxyCache = null;
    _activeGroupChildrenByTagCache = const <String, List<AppProxySummary>>{};
    if (!_connected) {
      _resetTrafficDashboardData();
    } else if (_trafficSamples.length > 60) {
      _trafficSamples = List<TrafficSample>.unmodifiable(
        _trafficSamples.skip(_trafficSamples.length - 60),
      );
    }
    _trafficDashboardSnapshot.value = _currentTrafficDashboardSnapshot();

    if (mounted) {
      setState(() {});
      _rebuildDerivedCaches();
    }

    AppLogStore.info(
      'memory cleanup',
      'reason=$reason imageBytesBefore=$imageBytesBefore '
          'imageEntriesBefore=$imageEntriesBefore '
          'proxyRowsBefore=$proxyCacheBefore groupCachesBefore=$groupCacheBefore '
          'trafficSamplesBefore=$samplesBefore '
          'installedAppsBefore=$installedAppsBefore',
    );
  }

  int _proxyPanelVisibleRows() {
    final total = _activeTopLevelProxiesCount;
    if (total <= 0) {
      return _activeProfileCache == null ? 0 : 1;
    }
    return total > 50 ? 51 : total;
  }

  Future<void> _startDeepLinkHandling() async {
    _deepLinkImportSubscription = DeepLinkImportBridge.stream.listen(
      _enqueueDeepLinkImport,
    );

    final initialRequest = await DeepLinkImportBridge.getInitialRequest();
    if (!mounted || initialRequest == null) {
      return;
    }
    _enqueueDeepLinkImport(initialRequest);
  }

  void _enqueueDeepLinkImport(DeepLinkImportRequest request) {
    if (_ready && _onboardingCompleted && !_legalAccepted) {
      _showAppSnackBar(_legalImportBlockedMessage());
      return;
    }
    _pendingDeepLinkImport = request;
    if (!_ready ||
        !_onboardingCompleted ||
        !_legalAccepted ||
        _deepLinkImportInFlight) {
      return;
    }
    unawaited(_drainPendingDeepLinkImports());
  }

  Future<void> _drainPendingDeepLinkImports() async {
    if (_deepLinkImportInFlight) {
      return;
    }

    if (_pendingDeepLinkImport != null && !_legalAccepted) {
      _pendingDeepLinkImport = null;
      _showAppSnackBar(_legalImportBlockedMessage());
      return;
    }

    while (mounted && _ready && _onboardingCompleted && _legalAccepted) {
      final request = _pendingDeepLinkImport;
      if (request == null) {
        return;
      }

      final context = _navigatorKey.currentContext;
      if (context == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _ready && _onboardingCompleted && _legalAccepted) {
            unawaited(_drainPendingDeepLinkImports());
          }
        });
        return;
      }

      _pendingDeepLinkImport = null;
      _deepLinkImportInFlight = true;
      try {
        await _handleDeepLinkImport(request);
      } finally {
        _deepLinkImportInFlight = false;
      }
    }
  }

  Future<void> _handleDeepLinkImport(DeepLinkImportRequest request) async {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      _pendingDeepLinkImport = request;
      return;
    }
    final l10n = AppLocalizations.of(context);
    final copy = _deepLinkImportCopy(context);

    if (!HappCryptoLinkDecoder.isSupportedSubscriptionUrl(request.url)) {
      _showAppSnackBar(l10n.invalidUrl);
      return;
    }

    try {
      final preview = await _buildDeepLinkImportPreview(request);
      if (!context.mounted) {
        return;
      }
      final decision = await _showDeepLinkImportSheet(
        context,
        request,
        preview,
      );
      if (decision == null) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      final requestInfo = switch (decision) {
        _DeepLinkImportDecision.sendHwid => preview.requestInfo,
        _DeepLinkImportDecision.importWithoutHwid =>
          preview.requestInfo?.copyWith(requireHwid: false),
        _DeepLinkImportDecision.import => preview.requestInfo,
      };

      final createdResult = await _runSubscriptionOperationWithWarning(
        SubscriptionStore.addFromUrl(
          preview.resolvedUrl,
          customName: request.name,
          requestInfo: requestInfo,
          operationTimeout: _subscriptionOperationTimeout,
        ),
        slowMessage: l10n.subscriptionOperationSlowWarning,
        timeoutMessage: l10n.subscriptionOperationTimeout,
      );
      final created = createdResult.subscription;
      await _reloadSubscriptions();
      if (!mounted) {
        return;
      }
      _showAppSnackBar(
        createdResult.hasWarning
            ? l10n.subscriptionSavedWithFetchWarning
            : copy.imported(created.name),
      );
      await _offerLikelyHwidFix(created);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showAppSnackBar(_userFacingSubscriptionError(error, l10n));
    }
  }

  String _legalImportBlockedMessage() {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return 'Accept Terms and Privacy Policy before importing subscriptions.';
    }
    return AppLocalizations.of(context).legalImportBlockedMessage;
  }

  Future<_DeepLinkImportPreview> _buildDeepLinkImportPreview(
    DeepLinkImportRequest request,
  ) async {
    if (HappCryptoLinkDecoder.isSupportedLink(request.url)) {
      final prepared = await HappCryptoLinkDecoder.prepare(request.url);
      return _DeepLinkImportPreview(
        sourceUrl: request.url,
        resolvedUrl: prepared.resolvedUrl,
        requestInfo: prepared.requestInfo,
      );
    }

    final isHappDeepLink = request.isHapp;

    return _DeepLinkImportPreview(
      sourceUrl: request.url,
      resolvedUrl: request.url,
      requestInfo: isHappDeepLink
          ? HappCryptoLinkDecoder.happRequestInfo()
          : null,
    );
  }

  Future<_DeepLinkImportDecision?> _showDeepLinkImportSheet(
    BuildContext context,
    DeepLinkImportRequest request,
    _DeepLinkImportPreview preview,
  ) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<_DeepLinkImportDecision>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _DeepLinkImportSheet(
        request: request,
        preview: preview,
        copy: _deepLinkImportCopy(context),
        l10n: l10n,
      ),
    );
  }

  _DeepLinkImportCopy _deepLinkImportCopy(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _DeepLinkImportCopy(
      title: l10n.deepLinkImportTitle,
      message: l10n.deepLinkImportMessage,
      nameLabel: l10n.deepLinkImportNameLabel,
      importAction: l10n.deepLinkImportAction,
      importedTextBuilder: l10n.deepLinkImportSuccess,
    );
  }

  void _showAppSnackBar(String message) {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  AppLocalizations? get _currentLocalizations {
    final context = _navigatorKey.currentContext;
    return context == null
        ? null
        : Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  String get _vpnStartFailedMessage =>
      _currentLocalizations?.vpnStartFailed ?? 'Failed to start VPN.';

  String get _vpnStartTimedOutMessage =>
      _currentLocalizations?.vpnStartTimedOut ??
      'VPN did not start within 15 seconds. Startup was stopped.';

  String get _vpnStopFailedMessage =>
      _currentLocalizations?.vpnStopFailed ?? 'Failed to stop VPN.';

  Future<void> _checkForClientUpdatesIfDue() async {
    await _refreshAppVersionInfo();
    await _cleanupInstalledUpdateArtifactsIfNeeded(showSnackBar: true);
    final result = await AppUpdateService.instance.checkForUpdates(
      currentVersion: _clientVersionLabel,
      currentBuildNumber: _clientVersionCode,
    );
    if (!mounted ||
        (result.status != AppUpdateStatus.updateAvailable &&
            result.status != AppUpdateStatus.downloaded)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showUpdateAvailableSnackBar(result);
    });
  }

  Future<void> _cleanupInstalledUpdateArtifactsIfNeeded({
    bool showSnackBar = false,
  }) async {
    if (_updateCleanupInFlight || _clientVersionLabel.trim().isEmpty) {
      return;
    }
    _updateCleanupInFlight = true;
    try {
      final result = await AppUpdateService.instance
          .cleanupInstalledUpdateArtifacts(
            currentVersion: _clientVersionLabel,
            currentBuildNumber: _clientVersionCode,
          );
      if (!result.changed) {
        return;
      }
      AppLogStore.info(
        'updates',
        'installed update cleanup files=${result.deletedFiles} '
            'metadataChanged=${result.metadataChanged} '
            'installedAtLeastLatest=${result.installedAtLeastLatest} '
            'current=$_clientVersionLabel+$_clientVersionCode',
      );
      if (!showSnackBar ||
          !result.installedAtLeastLatest ||
          result.deletedFiles <= 0) {
        return;
      }
      final versionKey = '$_clientVersionLabel+$_clientVersionCode';
      if (_lastUpdateCleanupNoticeVersion == versionKey) {
        return;
      }
      _lastUpdateCleanupNoticeVersion = versionKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _navigatorKey.currentContext;
        if (!mounted || context == null) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).updatesDeleteCachedApkDone(result.deletedFiles),
            ),
          ),
        );
      });
    } catch (error) {
      AppLogStore.warning('updates', 'installed update cleanup failed: $error');
    } finally {
      _updateCleanupInFlight = false;
    }
  }

  void _showUpdateAvailableSnackBar(AppUpdateCheckResult result) {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final version = result.info?.displayVersion;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          version == null
              ? l10n.updatesAvailableSnack
              : l10n.updatesAvailableSnackVersion(version),
        ),
        action: SnackBarAction(
          label: l10n.updatesOpenAction,
          onPressed: () => unawaited(_showUpdateSettingsPage()),
        ),
      ),
    );
  }

  Future<T> _runSubscriptionOperationWithWarning<T>(
    Future<T> operation, {
    required String slowMessage,
    required String timeoutMessage,
  }) async {
    var completed = false;
    final slowTimer = Timer(_subscriptionOperationSoftWarningDelay, () {
      if (!completed && mounted) {
        _showAppSnackBar(slowMessage);
      }
    });
    try {
      return await operation;
    } on TimeoutException {
      throw _LocalizedSubscriptionError(timeoutMessage);
    } finally {
      completed = true;
      slowTimer.cancel();
    }
  }

  String _userFacingSubscriptionError(Object error, AppLocalizations l10n) {
    if (error is _LocalizedSubscriptionError) {
      return error.message;
    }
    if (error is TimeoutException) {
      return l10n.subscriptionOperationTimeout;
    }
    if (error is UnsupportedHappCryptoLinkException) {
      return l10n.happCryptUnsupportedMessage;
    }
    return error.toString();
  }

  Future<void> _refreshActiveSubscription() async {
    if (_activeProfileRefreshInFlight) {
      return;
    }
    final subscription = _activeSubscription;
    final context = _navigatorKey.currentContext;
    if (subscription == null || context == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (SubscriptionStore.isLocalFileImportUrl(subscription.url)) {
      _showAppSnackBar(l10n.refreshActiveSubscriptionUnavailable);
      return;
    }

    _haptic();
    final beforeFingerprint = _subscriptionRuntimeFingerprint(subscription);
    setState(() {
      _activeProfileRefreshInFlight = true;
    });
    try {
      final updated = await _runSubscriptionOperationWithWarning(
        SubscriptionStore.refresh(
          subscription.id,
          operationTimeout: _subscriptionOperationTimeout,
        ),
        slowMessage: l10n.subscriptionOperationSlowWarning,
        timeoutMessage: l10n.subscriptionOperationTimeout,
      );
      final afterFingerprint = _subscriptionRuntimeFingerprint(updated);
      final runtimeChanged = beforeFingerprint != afterFingerprint;
      final preferredTag = _validSelectedProxyTagForSubscription(
        updated,
        _selectedProxyTag,
      );
      await _reloadSubscriptions(
        preferredSubscriptionId: updated.id,
        preferredProxyTag: preferredTag,
        resetRuntimeState: runtimeChanged,
        restartRuntimeOnApply: _connected && runtimeChanged,
        urlTestAfterApply: _connected && runtimeChanged,
      );
      if (!mounted) {
        return;
      }
      _showAppSnackBar(l10n.activeSubscriptionRefreshComplete(updated.name));
      if (!SubscriptionStore.isLocalFileImportUrl(updated.url)) {
        await _offerLikelyHwidFix(updated);
      }
    } catch (error) {
      if (mounted) {
        _showAppSnackBar(_userFacingSubscriptionError(error, l10n));
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeProfileRefreshInFlight = false;
        });
      }
    }
  }

  String _validSelectedProxyTagForSubscription(
    Subscription subscription,
    String preferredTag,
  ) {
    return _proxySelection.validSelectedProxyTagForSubscription(
      subscription,
      preferredTag,
    );
  }

  String _subscriptionRuntimeFingerprint(Subscription subscription) {
    return _subscriptionRuntime.subscriptionRuntimeFingerprint(subscription);
  }

  String? _subscriptionRuntimeFingerprintFromStore(String subscriptionId) {
    return _subscriptionRuntime.subscriptionRuntimeFingerprintFromStore(
      subscriptionId: subscriptionId,
      loadSubscription: SubscriptionStore.get,
    );
  }

  String _subscriptionsMetadataFingerprint() {
    return _subscriptionRuntime.subscriptionsMetadataFingerprint(
      SubscriptionStore.getAllMetadata(),
    );
  }

  Future<void> _showTrafficDashboard() async {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    _trafficDashboardOpen = true;
    _publishTrafficDashboardSnapshot(force: true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: true,
        isDismissible: true,
        useSafeArea: false,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.32,
          maxChildSize: 0.94,
          builder: (context, scrollController) => TrafficDashboardPage(
            snapshotListenable: _trafficDashboardSnapshot,
            scrollController: scrollController,
          ),
        ),
      );
    } finally {
      _trafficDashboardOpen = false;
      _trafficSamples = const <TrafficSample>[];
      _trafficDashboardSnapshot.value = TrafficDashboardSnapshot.empty;
    }
  }

  Future<void> _offerLikelyHwidFix(Subscription subscription) async {
    if (!SubscriptionStore.likelyRequiresHwidEnable(subscription)) {
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.subscriptionLikelyRequiresHwidTitle),
        content: Text(l10n.subscriptionLikelyRequiresHwidMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(dialogContext).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.subscriptionLikelyRequiresHwidAction),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _enableHwidAndRefreshSubscription(subscription.id);
  }

  Future<void> _enableHwidAndRefreshSubscription(String subscriptionId) async {
    final current = SubscriptionStore.get(subscriptionId);
    if (current == null) {
      return;
    }
    final wasActive = current.id == _activeProfileId;
    final beforeFingerprint = _subscriptionRuntimeFingerprint(current);
    final info = current.info ?? const SubscriptionInfo();
    await SubscriptionStore.save(
      current.copyWith(info: info.copyWith(requireHwid: true)),
    );
    if (!mounted) {
      return;
    }
    final currentContext = _navigatorKey.currentContext;
    if (currentContext == null || !currentContext.mounted) {
      return;
    }
    final l10n = AppLocalizations.of(currentContext);
    final updated = await _runSubscriptionOperationWithWarning(
      SubscriptionStore.refresh(
        subscriptionId,
        operationTimeout: _subscriptionOperationTimeout,
      ),
      slowMessage: l10n.subscriptionOperationSlowWarning,
      timeoutMessage: l10n.subscriptionOperationTimeout,
    );
    final runtimeChanged =
        wasActive &&
        beforeFingerprint != _subscriptionRuntimeFingerprint(updated);
    await _reloadSubscriptions(
      preferredSubscriptionId: updated.id,
      preferredProxyTag: wasActive
          ? _validSelectedProxyTagForSubscription(updated, _selectedProxyTag)
          : null,
      resetRuntimeState: runtimeChanged,
      restartRuntimeOnApply: _connected && runtimeChanged,
      urlTestAfterApply: _connected && runtimeChanged,
    );
    if (!mounted) {
      return;
    }
    _showAppSnackBar(l10n.subscriptionHwidEnabledAndUpdated);
    if (SubscriptionStore.likelyRequiresHwidEnable(updated)) {
      _offerLikelyHwidFix(updated);
    }
  }

  Future<void> _bootstrap() async {
    AppSettingsStore? store;
    var ownsStore = false;
    late AppSettingsState state;
    var adBlockStatus = const AdBlockRuleSetStatus.unavailable();
    var russiaRouteDataStatus = const RussiaRouteDataStatus.unavailable();
    final appVersionInfo = await _readAppVersionInfo();
    final useInMemoryBootstrap = widget.store is MemoryAppSettingsStore;
    try {
      if (useInMemoryBootstrap) {
        store = widget.store!;
      } else {
        await HiveAppSettingsStore.initHive();
        await SubscriptionStore.init();
        store = widget.store ?? await HiveAppSettingsStore.open();
        ownsStore = widget.store == null;
      }
      state = await store.loadState();
      try {
        adBlockStatus = await AdBlockRuleSetService.instance.loadStatus();
      } catch (_) {
        adBlockStatus = const AdBlockRuleSetStatus.unavailable();
      }
      try {
        russiaRouteDataStatus = await RussiaRouteDataService.instance
            .loadStatus();
      } catch (_) {
        russiaRouteDataStatus = const RussiaRouteDataStatus.unavailable();
      }
    } catch (error, stackTrace) {
      AppLogStore.error(
        'bootstrap',
        'Failed to bootstrap app, using in-memory defaults: '
            '$error\n$stackTrace',
      );
      if (widget.store == null && store != null) {
        try {
          await store.close();
        } catch (_) {}
      }
      store = MemoryAppSettingsStore();
      ownsStore = widget.store == null;
      state = const AppSettingsState(
        onboardingCompleted: false,
        activeProfileId: '',
        selectedProxyTag: '',
        localeCode: 'system',
        themePreference: AppThemePreference.system,
        accentColorHex: 'default',
        hapticEnabled: true,
        hideServerIp: false,
        progressiveBlurEnabled: false,
        performanceMode: AppPerformanceMode.standard,
        tlsFragmentationMode: TlsFragmentationMode.disabled,
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
        russiaDnsDirectResolver: defaultRussiaDnsDirectResolver,
        urlTestUrl: defaultUrlTestUrl,
        urlTestIntervalSeconds: _coolUrlTestIntervalSeconds,
        urlTestTimeoutSeconds: _defaultUrlTestTimeoutSeconds,
        urlTestConcurrency: _coolUrlTestConcurrency,
        urlTestUnavailableCheckIntervalSeconds:
            _coolUrlTestUnavailableCheckIntervalSeconds,
        locationLookupLimit: _coolLocationLookupLimit,
        locationLookupTimeoutSeconds: _defaultLocationLookupTimeoutSeconds,
        locationLookupConcurrency: _coolLocationLookupConcurrency,
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
    }

    const progressiveBlurEnabled = false;

    final resolvedSubscriptions = useInMemoryBootstrap
        ? const ResolvedSubscriptions(
            subscriptions: <Subscription>[],
            normalized: SubscriptionRuntimeSelection(
              activeSubscriptionId: '',
              selectedProxyTag: '',
            ),
          )
        : _resolveSubscriptionMetadata(
            activeSubscriptionId: state.activeProfileId,
            selectedProxyTag: state.selectedProxyTag,
          );
    final subscriptions = resolvedSubscriptions.subscriptions;
    final normalized = resolvedSubscriptions.normalized;

    if (!mounted) {
      if (ownsStore) {
        await store.close();
      }
      return;
    }

    setState(() {
      _store = store;
      _ownsStore = ownsStore;
      _clientVersionLabel = appVersionInfo.displayVersion;
      _clientVersionCode = appVersionInfo.updateBuildNumber;
      _clientPackageName = appVersionInfo.packageName;
      _ready = true;
      _onboardingCompleted = state.onboardingCompleted;
      _acceptedLegalVersion = state.acceptedLegalVersion;
      _acceptedLegalAtMillis = state.acceptedLegalAtMillis;
      _subscriptions = subscriptions;
      _activeProfileId = normalized.activeSubscriptionId;
      _selectedProxyTag = normalized.selectedProxyTag;
      _settings.applyState(
        state,
        progressiveBlurEnabledOverride: progressiveBlurEnabled,
      );
      _adBlockStatus = adBlockStatus;
      _russiaRouteDataStatus = russiaRouteDataStatus;
      _setConnectionPhase(AppConnectionPhase.idle);
      _refreshThemeCache();
      _applyMetadataActiveProfile(
        subscriptions,
        normalized.activeSubscriptionId,
        clearProxyCache: true,
      );
    });
    unawaited(_syncQuickSettingsTileLabel());
    AppLogStore.info('sing-box', 'startup');
    unawaited(_syncRuntimePerformanceFlags());
    _startSingboxEvents();
    if (_foregroundLifecycleActive) {
      _startSubscriptionAutoRefresh();
      unawaited(_updateRussiaRouteDataIfDue());
      if (!useInMemoryBootstrap) {
        unawaited(_checkForClientUpdatesIfDue());
      }
    }
    if (!useInMemoryBootstrap && subscriptions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scheduleActiveSubscriptionHydration(
          activeSubscriptionId: normalized.activeSubscriptionId,
          selectedProxyTag: normalized.selectedProxyTag,
          preserveRuntimeState: false,
          applyRuntime: false,
        );
      });
    }
    if (_pendingDeepLinkImport != null && _onboardingCompleted) {
      unawaited(_drainPendingDeepLinkImports());
    }

    final inboundSettingsMigrated =
        (!state.vpnInboundEnabled && !state.proxyInboundEnabled) ||
        state.proxyMixedListen !=
            (state.proxyAllowLan ? '0.0.0.0' : '127.0.0.1') ||
        (state.proxyAllowLan && !isValidProxyPassword(state.proxyPassword));
    if (normalized.activeSubscriptionId != state.activeProfileId ||
        normalized.selectedProxyTag != state.selectedProxyTag ||
        inboundSettingsMigrated) {
      _saveStateSoon();
    }
  }

  AppSettingsState _currentSettingsState() {
    return _settings.toState(
      onboardingCompleted: _onboardingCompleted,
      acceptedLegalVersion: _acceptedLegalVersion,
      acceptedLegalAtMillis: _acceptedLegalAtMillis,
      activeProfileId: _activeProfileId,
      selectedProxyTag: _selectedProxyTag,
    );
  }

  Future<void> _persistState() async {
    final store = _store;
    if (store == null) return;
    await store.saveState(_currentSettingsState());
  }

  Future<void> _applyImportedSettingsState(AppSettingsState state) async {
    setState(() {
      _settings.applyState(state, progressiveBlurEnabledOverride: false);
      _refreshThemeCache();
    });
    await _persistState();
    await _syncRuntimePerformanceFlags();
    _configCoordinator.emitCurrentConfigLog(
      'settings backup imported',
      restartRuntime: _connected,
    );
  }

  Future<void> _importBackupSubscriptions(
    List<Subscription> importedSubscriptions,
  ) async {
    if (importedSubscriptions.isEmpty) {
      return;
    }
    final existing = SubscriptionStore.getAll();
    final byIdentity = <String, Subscription>{};
    for (final subscription in existing) {
      if (subscription.id.trim().isNotEmpty) {
        byIdentity['id:${subscription.id}'] = subscription;
      }
      if (subscription.url.trim().isNotEmpty) {
        byIdentity['url:${subscription.url}'] = subscription;
      }
    }
    final nextSortOrder =
        existing
            .map((subscription) => subscription.sortOrder ?? 0)
            .fold<int>(0, max) +
        1;
    var appended = 0;
    for (final imported in importedSubscriptions) {
      final matched =
          byIdentity['id:${imported.id}'] ??
          (imported.url.trim().isEmpty
              ? null
              : byIdentity['url:${imported.url}']);
      final normalized = matched == null
          ? imported.copyWith(
              sortOrder: imported.sortOrder ?? nextSortOrder + appended++,
            )
          : imported.copyWith(
              id: matched.id,
              sortOrder: matched.sortOrder,
              selectedProxyTag: imported.selectedProxyTag.isNotEmpty
                  ? imported.selectedProxyTag
                  : matched.selectedProxyTag,
            );
      await SubscriptionStore.save(normalized);
    }
    await _reloadSubscriptions(
      preferredSubscriptionId: _activeProfileId,
      preferredProxyTag: _selectedProxyTag,
      applyRuntime: false,
    );
  }

  void _haptic() {
    if (_hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  void _saveStateSoon() {
    unawaited(_persistState());
  }

  void _applySettingsChange(AppSettingsChange Function() mutate) {
    late final AppSettingsChange change;
    setState(() {
      change = mutate();
      if (change.refreshTheme) {
        _refreshThemeCache();
      }
      if (change.scheduleLocationRefresh) {
        _lastLocationLookupSignature = '';
      }
    });
    if (!change.changed) {
      return;
    }
    if (change.publishTraffic) {
      _publishTrafficDashboardSnapshot();
    }
    final configReason = change.configReason;
    if (configReason != null) {
      _configCoordinator.emitCurrentConfigLog(
        configReason,
        restartRuntime: change.restartRuntime,
        forceFullServiceRestart: change.forceFullServiceRestart,
      );
    }
    _saveStateSoon();
    if (change.pumpLocationLookupWaiters) {
      _pumpLocationLookupWaiters();
    }
    if (change.scheduleLocationRefresh) {
      _scheduleBestOutboundLocationRefresh();
    }
    if (change.syncRuntimePerformanceFlags) {
      unawaited(_syncRuntimePerformanceFlags());
    }
  }

  bool get _coolMode => _settings.coolMode;

  bool get _economyMode => _settings.economyMode;

  bool get _foregroundLifecycleActive =>
      _appLifecycleState == AppLifecycleState.resumed;

  bool get _balancedMode => _settings.balancedMode;

  bool get _connectionBusy => switch (_connectionPhase) {
    AppConnectionPhase.preparing ||
    AppConnectionPhase.configuring ||
    AppConnectionPhase.reconfiguring ||
    AppConnectionPhase.starting ||
    AppConnectionPhase.stopping ||
    AppConnectionPhase.recovering => true,
    _ => false,
  };

  String _connectionButtonStatusLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_resolvingLowestProxy) {
      return l10n.connectionStageSelectingProxy;
    }
    return switch (_connectionPhase) {
      AppConnectionPhase.preparing => l10n.connectionStagePreparing,
      AppConnectionPhase.configuring => l10n.connectionStageConfiguring,
      AppConnectionPhase.reconfiguring => l10n.connectionStageConfiguring,
      AppConnectionPhase.starting => l10n.connectionStageStarting,
      AppConnectionPhase.stopping => l10n.connectionStageStopping,
      AppConnectionPhase.recovering => l10n.connectionStageRecovering,
      AppConnectionPhase.connected => l10n.connected,
      _ => l10n.tapToConnect,
    };
  }

  bool get _effectiveProgressiveBlurEnabled => false;

  int get _networkHeartbeatIntervalSeconds => _economyMode
      ? _economyNetworkHeartbeatIntervalSeconds
      : _coolNetworkHeartbeatIntervalSeconds;

  void _recordTrafficSample(DateTime now) {
    if (!_trafficDashboardOpen || !_connected || !_trafficAvailable) {
      return;
    }
    final cutoff = now.subtract(const Duration(minutes: 5));
    final next = <TrafficSample>[
      for (final sample in _trafficSamples)
        if (!sample.timestamp.isBefore(cutoff)) sample,
      TrafficSample(
        timestamp: now,
        downlinkBps: _downlinkBytesPerSecond,
        uplinkBps: _uplinkBytesPerSecond,
        totalBytes: _uplinkTotalBytes + _downlinkTotalBytes,
      ),
    ];
    if (next.length > 180) {
      _trafficSamples = List<TrafficSample>.unmodifiable(
        next.skip(next.length - 180),
      );
    } else {
      _trafficSamples = List<TrafficSample>.unmodifiable(next);
    }
  }

  void _resetTrafficDashboardData() {
    _uplinkBytesPerSecond = 0;
    _downlinkBytesPerSecond = 0;
    _uplinkTotalBytes = 0;
    _downlinkTotalBytes = 0;
    _trafficAvailable = false;
    _trafficSamples = const <TrafficSample>[];
  }

  TrafficDashboardSnapshot _currentTrafficDashboardSnapshot() {
    return TrafficDashboardSnapshot(
      connected: _connected,
      connecting: _connectionBusy,
      trafficAvailable: _trafficAvailable,
      hideServerIp: _hideServerIp,
      downlinkBps: _connected && _trafficAvailable
          ? _downlinkBytesPerSecond
          : 0,
      uplinkBps: _connected && _trafficAvailable ? _uplinkBytesPerSecond : 0,
      uplinkTotalBytes: _connected && _trafficAvailable ? _uplinkTotalBytes : 0,
      downlinkTotalBytes: _connected && _trafficAvailable
          ? _downlinkTotalBytes
          : 0,
      connectedSince: _connected ? _connectedSince : null,
      activeProfile: _activeProfile,
      activeProxy: _displayProxy,
      samples: _trafficSamples,
    );
  }

  void _publishTrafficDashboardSnapshot({bool force = false}) {
    if (!_trafficDashboardOpen && !force) {
      return;
    }
    final snapshot = _currentTrafficDashboardSnapshot();
    if (_trafficDashboardSnapshot.value != snapshot) {
      _trafficDashboardSnapshot.value = snapshot;
    }
  }

  void _setConnectionPhase(
    AppConnectionPhase phase, {
    bool retryScheduled = false,
  }) {
    final wasConnected = _connected;
    _connectionPhase = phase;
    _connected =
        phase == AppConnectionPhase.connected ||
        phase == AppConnectionPhase.reconfiguring;
    if (_connected && !wasConnected) {
      _connectedSince = DateTime.now();
    } else if (!_connected &&
        (phase == AppConnectionPhase.idle ||
            phase == AppConnectionPhase.failed)) {
      _connectedSince = null;
      _resetActiveProxyIpState();
    }
    _starting = switch (phase) {
      AppConnectionPhase.preparing ||
      AppConnectionPhase.configuring ||
      AppConnectionPhase.reconfiguring ||
      AppConnectionPhase.starting ||
      AppConnectionPhase.recovering => true,
      _ => false,
    };
    _runtimeTransitionInProgress = switch (phase) {
      AppConnectionPhase.preparing ||
      AppConnectionPhase.configuring ||
      AppConnectionPhase.reconfiguring ||
      AppConnectionPhase.starting ||
      AppConnectionPhase.stopping ||
      AppConnectionPhase.recovering => true,
      _ => false,
    };
    if (!_connected) {
      _clearRuntimeInterfaceIssueWindow();
    }
    if (phase == AppConnectionPhase.connected ||
        phase == AppConnectionPhase.idle ||
        phase == AppConnectionPhase.failed ||
        phase == AppConnectionPhase.stopping) {
      _runtimeLifecycle.cancelStartWatchdog();
    }
    if (_runtimeTransitionInProgress) {
      _proxyRuntime.beginTransition();
    } else {
      _proxyRuntime.endTransition();
    }
    _invalidOutboundRetryScheduled = retryScheduled;
  }

  void _applyActiveProxyIpSnapshot(ActiveProxyIpSnapshot snapshot) {
    _activeProxyIp = snapshot;
    _applyRuntimeStateToDerivedCaches();
  }

  void _publishActiveProxyIpSnapshot(ActiveProxyIpSnapshot snapshot) {
    if (!mounted) {
      _activeProxyIp = snapshot;
      return;
    }
    setState(() {
      _applyActiveProxyIpSnapshot(snapshot);
    });
  }

  void _resetActiveProxyIpState({bool rebuild = true}) {
    _activeProxyIpController.reset(
      onSnapshot: (snapshot) {
        _activeProxyIp = snapshot;
        if (rebuild) {
          _applyRuntimeStateToDerivedCaches();
        }
      },
    );
  }

  void _suspendForegroundWork() {
    unawaited(_syncRuntimeUiForeground(false));
    _resumeForegroundSyncTimer?.cancel();
    _subscriptionAutoRefreshTimer?.cancel();
    _activeProxyIpController.cancelPending();
    _locationLookupTimer?.cancel();
    _locationLookupGeneration++;
    _locationLookupInFlight = false;
    _locationLookupRefreshRequested = false;
    _cancelQueuedLocationLookups();
    _trafficUiUpdateTimer?.cancel();
    _trafficUiUpdateTimer = null;
    _pendingTrafficStatusEvent = null;
    _postConnectUrlTestGeneration++;
    _postConnectUrlTestTimer?.cancel();
    _postConnectUrlTestTimer = null;
    _latencyCoordinator.cancel();
    _networkReconnectWatchdogTimer?.cancel();
    _networkReconnectWatchdogTimer = null;
    _networkRecoveryDecisionTimer?.cancel();
    _networkRecoveryDecisionTimer = null;
    if (_invalidOutboundRetryScheduled && _runtimeDesiredByUser) {
      _retryRuntimeOnResume = true;
    }
    _invalidOutboundRetryTimer?.cancel();
    _invalidOutboundRetryTimer = null;
    _invalidOutboundRetryScheduled = false;
  }

  void _resumeForegroundWork() {
    unawaited(_syncRuntimeUiForeground(true));
    if (!mounted || !_ready) {
      return;
    }
    _resumeForegroundSyncTimer?.cancel();
    _startSubscriptionAutoRefresh();
    _resumeForegroundSyncTimer = Timer(const Duration(milliseconds: 350), () {
      _resumeForegroundSyncTimer = null;
      if (!mounted || !_foregroundLifecycleActive) {
        return;
      }
      unawaited(
        _refreshAppVersionInfo().then(
          (_) => _cleanupInstalledUpdateArtifactsIfNeeded(showSnackBar: true),
        ),
      );
      unawaited(_reconcileRuntimeAfterResume());
      if (_connected) {
        _scheduleActiveOutboundIpRefresh(
          delay: const Duration(milliseconds: 700),
        );
        if (_locationLookupLimit > 0) {
          _scheduleBestOutboundLocationRefresh(
            delay: _coolMode
                ? const Duration(seconds: 1)
                : const Duration(seconds: 8),
          );
        }
      }
      if (_retryRuntimeOnResume && !_connected && _runtimeDesiredByUser) {
        _retryRuntimeOnResume = false;
        _scheduleInvalidOutboundRetry('resume lifecycle retry');
      } else {
        _retryRuntimeOnResume = false;
      }
    });
  }

  Future<void> _syncRuntimeUiForeground(bool foreground) async {
    try {
      await SingboxRuntime.instance.setRuntimeUiForeground(foreground);
    } catch (error) {
      AppLogStore.warning(
        'runtime',
        'failed to sync UI foreground=$foreground: $error',
      );
    }
  }

  Future<void> _reconcileRuntimeAfterResume() async {
    AppLogStore.info('runtime', 'resume reconcile start');
    await _syncRuntimePerformanceFlags();
    await _syncRuntimeState();
    if (!_connected || !_foregroundLifecycleActive) {
      return;
    }
    final networkReady = await _networkInterfaceUsable(
      reason: 'resume_reconcile',
    );
    if (!networkReady) {
      _retryRuntimeOnResume = true;
      AppLogStore.warning(
        'runtime',
        'resume reconcile postponed: no usable network interface',
      );
      return;
    }
    _scheduleNetworkRecovery(
      reason: 'resume_reconcile',
      networkGeneration: _networkInterfaceGeneration,
    );
    _schedulePostConnectSelectedProxyUrlTest(
      reason: 'resume_reconcile',
      delay: const Duration(milliseconds: 450),
      ignoreCooldown: true,
    );
  }

  void _setPerformanceMode(AppPerformanceMode mode) {
    _applySettingsChange(() => _settings.setPerformanceMode(mode));
  }

  void _setMemoryLimitEnabled(bool value, {bool warningDismissed = false}) {
    final previousEnabled = _memoryLimitEnabled;
    final previousDismissed = _memoryLimitWarningDismissed;
    _applySettingsChange(
      () => _settings.setMemoryLimitEnabled(
        value,
        warningDismissed: warningDismissed,
      ),
    );
    if (previousEnabled == _memoryLimitEnabled &&
        previousDismissed == _memoryLimitWarningDismissed) {
      return;
    }
    AppLogStore.info(
      'runtime',
      'memory limit setting changed enabled=$_memoryLimitEnabled '
          'warningDismissed=$_memoryLimitWarningDismissed',
    );
  }

  void _setUpdateInstallMode(AppUpdateInstallMode mode) {
    _applySettingsChange(() => _settings.setUpdateInstallMode(mode));
  }

  Future<void> _syncRuntimePerformanceFlags() {
    return SingboxRuntime.instance.setRuntimeFlags(
      wakeLockEnabled: _balancedMode ? false : null,
      networkHeartbeatEnabled: true,
      networkHeartbeatIntervalSeconds: _networkHeartbeatIntervalSeconds,
      performanceMode: _performanceMode.name,
      memoryLimitEnabled: _memoryLimitEnabled,
    );
  }

  void _startSubscriptionAutoRefresh() {
    _subscriptionAutoRefreshTimer?.cancel();
    _subscriptionAutoRefreshTimer = null;
    if (!mounted ||
        !_foregroundLifecycleActive ||
        !_ready ||
        _subscriptions.isEmpty) {
      return;
    }
    final delay = _nextSubscriptionAutoRefreshDelay();
    if (delay == null) {
      return;
    }
    _subscriptionAutoRefreshTimer = Timer(delay, () {
      _subscriptionAutoRefreshTimer = null;
      if (!mounted) {
        return;
      }
      unawaited(_runSubscriptionAutoRefresh());
    });
  }

  Duration? _nextSubscriptionAutoRefreshDelay() {
    return _subscriptionRuntime.nextAutoRefreshDelay(_subscriptions);
  }

  Future<void> _runSubscriptionAutoRefresh() async {
    if (_autoRefreshInFlight) {
      return;
    }
    if (!_ready || _subscriptions.isEmpty || !_foregroundLifecycleActive) {
      _startSubscriptionAutoRefresh();
      return;
    }
    final dueSubscriptions = _subscriptionRuntime.dueAutoRefreshSubscriptions(
      _subscriptions,
    );
    if (dueSubscriptions.isEmpty) {
      _startSubscriptionAutoRefresh();
      return;
    }
    AppLogStore.info(
      'subscription refresh',
      'auto-refresh begin due=${dueSubscriptions.length} '
          'ids=${dueSubscriptions.map((s) => s.id).take(6).join(', ')}',
    );
    _autoRefreshInFlight = true;
    try {
      final activeBefore = _activeSubscription;
      final activeBeforeFingerprint = activeBefore == null
          ? null
          : _subscriptionRuntimeFingerprint(activeBefore);
      Subscription? refreshedActiveSubscription;
      final refreshLimit = _coolMode
          ? 1
          : _balancedMode
          ? 2
          : dueSubscriptions.length;
      for (
        var offset = 0;
        offset < dueSubscriptions.length;
        offset += refreshLimit
      ) {
        final batch = dueSubscriptions.skip(offset).take(refreshLimit);
        await Future.wait(
          batch.map((subscription) async {
            try {
              AppLogStore.info(
                'subscription refresh',
                'refreshing id=${subscription.id} name=${subscription.name}',
              );
              final updated = await SubscriptionStore.refresh(subscription.id);
              _subscriptionRuntime.clearAutoRefreshFailure(subscription.id);
              if (updated.id == activeBefore?.id) {
                refreshedActiveSubscription = updated;
              }
            } catch (error) {
              final backoff = _subscriptionRuntime.recordAutoRefreshFailure(
                subscription.id,
              );
              AppLogStore.warning(
                'subscription refresh',
                'refresh failed id=${subscription.id} name=${subscription.name} '
                    'failures=${backoff.failures} '
                    'backoff=${backoff.backoffMinutes}m: $error',
              );
            }
          }),
        );
      }
      final activeRuntimeChanged =
          refreshedActiveSubscription != null &&
          activeBeforeFingerprint != null &&
          activeBeforeFingerprint !=
              _subscriptionRuntimeFingerprint(refreshedActiveSubscription!);
      await _reloadSubscriptions(
        preferredSubscriptionId: refreshedActiveSubscription?.id,
        preferredProxyTag: refreshedActiveSubscription == null
            ? null
            : _validSelectedProxyTagForSubscription(
                refreshedActiveSubscription!,
                _selectedProxyTag,
              ),
        applyRuntime: activeRuntimeChanged,
        resetRuntimeState: activeRuntimeChanged,
        restartRuntimeOnApply: _connected && activeRuntimeChanged,
        urlTestAfterApply: _connected && activeRuntimeChanged,
      );
      AppLogStore.info('subscription refresh', 'auto-refresh done');
    } finally {
      _autoRefreshInFlight = false;
      _startSubscriptionAutoRefresh();
    }
  }

  String _outboundDebugSnapshot({required String reason}) {
    final subscription = _activeSubscription;
    if (subscription == null) {
      return 'outbound snapshot reason=$reason activeSubscription=null';
    }
    final outbounds = subscription.outbounds;
    final sample = outbounds
        .take(14)
        .map((outbound) {
          final type = outbound.type;
          final deleted = outbound.info.deleted ? ' deleted' : '';
          final groupOnly = outbound.config['_group_only'] == true
              ? ' groupOnly'
              : '';
          final detour = outbound.config['detour']?.toString().trim() ?? '';
          final detourText = detour.isEmpty ? '' : ' detour=$detour';
          return '${outbound.tag}($type$deleted$groupOnly$detourText)';
        })
        .join(', ');
    return 'outbound snapshot reason=$reason '
        'sub=${subscription.id} selected=$_selectedProxyTag '
        'outbounds=${outbounds.length} groups=${subscription.groups.length} '
        'chains=${subscription.proxyChains.length}'
        '${sample.isEmpty ? '' : '\nsample: $sample'}';
  }

  void _logLibboxCall(String method, String detail) {
    AppLogStore.info(
      'libbox call',
      '$method $detail\n${_outboundDebugSnapshot(reason: method)}',
    );
  }

  void _completeOnboarding() {
    setState(() {
      _onboardingCompleted = true;
    });
    _saveStateSoon();
    if (_pendingDeepLinkImport != null && _legalAccepted) {
      unawaited(_drainPendingDeepLinkImports());
    }
  }

  void _acceptLegalDocuments() {
    setState(() {
      _acceptedLegalVersion = _requiredLegalVersion;
      _acceptedLegalAtMillis = DateTime.now().millisecondsSinceEpoch;
    });
    _saveStateSoon();
    if (_pendingDeepLinkImport != null) {
      unawaited(_drainPendingDeepLinkImports());
    }
  }

  void _resetOnboarding() {
    setState(() {
      _onboardingCompleted = false;
    });
    _saveStateSoon();
  }

  Future<void> _toggleConnection({String source = 'unknown'}) async {
    _haptic();
    if (_connectionPhase == AppConnectionPhase.stopping) {
      _startAfterStopRequested = true;
      AppLogStore.info(
        'runtime',
        'connection start queued while stopping source=$source',
      );
      return;
    }
    final activeOrRequested =
        _connected ||
        _runtimeDesiredByUser ||
        _connectionPhase == AppConnectionPhase.preparing ||
        _connectionPhase == AppConnectionPhase.configuring ||
        _connectionPhase == AppConnectionPhase.starting ||
        _connectionPhase == AppConnectionPhase.recovering ||
        _connectionPhase == AppConnectionPhase.reconfiguring;
    if (activeOrRequested) {
      _cancelAutomaticRuntimeRecovery('explicit_user_stop');
      _runtimeDesiredByUser = false;
      if (mounted) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.stopping);
        });
      } else {
        _setConnectionPhase(AppConnectionPhase.stopping);
      }
      var stopFailed = false;
      try {
        await SingboxRuntime.instance
            .stop(reason: 'toggle_connection')
            .timeout(const Duration(seconds: 7));
      } catch (error, stackTrace) {
        stopFailed = true;
        AppLogStore.error(
          'sing-box',
          'native stop failed reason=toggle_connection error=$error\n'
              '$stackTrace',
        );
      }
      if (!mounted) return;
      if (stopFailed) {
        final status = await SingboxRuntime.instance
            .status()
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => const <String, dynamic>{'running': true},
            )
            .catchError((_) => const <String, dynamic>{'running': true});
        if (!mounted) return;
        if (status['running'] == true) {
          _runtimeDesiredByUser = true;
          _startAfterStopRequested = false;
          setState(() {
            _setConnectionPhase(AppConnectionPhase.connected);
          });
          _showAppSnackBar(_vpnStopFailedMessage);
          return;
        }
      }
      final startAfterStop = _startAfterStopRequested;
      _startAfterStopRequested = false;
      _latencyCoordinator.configureAuto(null);
      _latencyCoordinator.cancel();
      setState(() {
        _setConnectionPhase(AppConnectionPhase.idle);
        _resetActiveProxyIpState();
        _locationLookupGeneration++;
        _locationLookupTimer?.cancel();
        _locationLookupInFlight = false;
        _locationLookupRefreshRequested = false;
        _cancelQueuedLocationLookups();
        _excludedRuntimeOutboundTags.clear();
        _clearLastStartedBuildCache();
        _invalidOutboundRetryScheduled = false;
        _invalidOutboundRetryTimer?.cancel();
        _lowestLatency = null;
        _runtimeLowestOutboundTag = null;
        _runtimeLowestSelections.clear();
        _runtimeLatencies.clear();
        _unavailableLatencyTags.clear();
        _latencyErrors.clear();
        _latencyFailureCounts.clear();
        _singleOutboundPingRefreshScheduled = false;
        _postConnectUrlTestGeneration++;
        _postConnectUrlTestTimer?.cancel();
        _networkReconnectWatchdogTimer?.cancel();
        _networkReconnectWatchdogTimer = null;
        _networkRecoveryDecisionTimer?.cancel();
        _networkRecoveryDecisionTimer = null;
        _applyRuntimeStateToDerivedCaches();
      });
      unawaited(_syncQuickSettingsTileLabel());
      if (startAfterStop && mounted) {
        AppLogStore.info(
          'runtime',
          'connection queued start after stop source=$source',
        );
        await _startConnection(source: 'queued_after_stop:$source');
      }
      return;
    }

    await _startConnection(source: source);
  }

  Future<void> _startConnection({required String source}) async {
    if (_runtimeTransitionInProgress ||
        _starting ||
        _invalidOutboundRetryScheduled) {
      return;
    }
    AppLogStore.info(
      'sing-box',
      'manual start requested source=$source\n'
          '${_outboundDebugSnapshot(reason: 'manual start')}',
    );
    _trimRuntimeStartMemory('before_runtime_start');

    if (!_vpnInboundEnabled && !_proxyInboundEnabled) {
      _showAppSnackBar(AppLocalizations.of(context).inboundNoneEnabled);
      return;
    }

    if (_vpnInboundEnabled &&
        _splitRoutingMode != SplitRoutingMode.disabled &&
        normalizeSplitRoutingPackages(_splitRoutingPackages).isEmpty) {
      _showAppSnackBar(AppLocalizations.of(context).splitRoutingEmptyWhitelist);
      return;
    }

    _runtimeDesiredByUser = true;
    setState(() {
      _setConnectionPhase(AppConnectionPhase.preparing);
    });

    final granted = await SingboxRuntime.instance.prepareVpn(
      requiresVpn: _vpnInboundEnabled,
    );
    if (!mounted) {
      return;
    }
    if (!granted) {
      _runtimeDesiredByUser = false;
      setState(() {
        _setConnectionPhase(AppConnectionPhase.idle);
      });
      return;
    }

    await _synchronizeSelectedProxyBeforeStart();
    if (!mounted) {
      return;
    }
    setState(() {
      _setConnectionPhase(AppConnectionPhase.configuring);
    });

    final build = await _configCoordinator
        .buildCurrentSingboxConfigInBackground(returnConfig: true);
    if (build == null || !mounted) {
      if (mounted) {
        _runtimeDesiredByUser = false;
        setState(() {
          _setConnectionPhase(AppConnectionPhase.idle);
        });
      }
      return;
    }
    if (!_applyStartupValidationResult(build, 'manual start')) {
      _configCoordinator.discardPreparedConfigCandidate(build);
      _runtimeDesiredByUser = false;
      if (mounted) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.failed);
        });
      }
      _showNoValidOutboundsWarning();
      return;
    }
    if (mounted) {
      setState(() {
        _setConnectionPhase(AppConnectionPhase.starting);
      });
    }
    await _startRuntimeWithBuild(build, useVpn: _vpnInboundEnabled);
  }

  void _selectProxy(String tag) {
    final activeSubscription = _activeSubscription;
    if (activeSubscription == null || _selectedProxyTag == tag) {
      return;
    }

    final previousTag = _selectedProxyTag;
    final previousProxy = _displayProxyForSelectedTag(previousTag);
    final requestedProxy = _displayProxyForSelectedTag(tag);
    AppLogStore.info(
      'proxy',
      'user requested new outbound '
          'from=${previousTag.isEmpty ? '<none>' : previousTag}'
          '${previousProxy == null ? '' : ' (${previousProxy.displayName})'} '
          'to=$tag'
          '${requestedProxy == null ? '' : ' (${requestedProxy.displayName})'} '
          'subscription=${activeSubscription.id} '
          'connected=$_connected',
    );
    _haptic();
    final updatedSubscription = _withSelectedOutbound(activeSubscription, tag);
    final selectionGeneration = _connected
        ? _beginRuntimeProxySelectionGuard(tag, previousTag)
        : _beginLocalProxySelection();
    setState(() {
      _subscriptions = _replaceSubscription(updatedSubscription);
      _activeLookupSubscription = null;
      _selectedProxyTag = tag;
      _displayProxyCache =
          _displayProxyForSelectedTag(tag) ?? _displayProxyCache;
      _applyRuntimeStateToDerivedCaches();
    });
    AppLogStore.info(
      'proxy',
      'local selected outbound updated tag=$tag '
          'display=${_displayProxyCache?.displayName ?? tag}',
    );
    unawaited(_syncQuickSettingsTileLabel());
    _saveStateSoon();
    unawaited(
      _persistSelectedProxySelection(
        updatedSubscription,
        generation: selectionGeneration,
        prepareConfigSnapshot: !_connected,
      ),
    );
    if (_connected) {
      unawaited(() async {
        try {
          _logLibboxCall(
            'selectOutbound',
            'reason=user proxy select group=select outbound=$tag',
          );
          final startedAt = DateTime.now();
          await SingboxRuntime.instance
              .selectOutbound(groupTag: 'select', outboundTag: tag)
              .timeout(const Duration(seconds: 3));
          if (!mounted ||
              !_proxySelection.isCurrentGeneration(selectionGeneration)) {
            return;
          }
          AppLogStore.info(
            'libbox call',
            'selectOutbound done group=select outbound=$tag '
                'elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds}',
          );
          await _persistSelectedProxyConfigSnapshot(
            reason: 'proxy selection persisted',
            generation: selectionGeneration,
          );
          _clearRuntimeProxySelectionGuard(generation: selectionGeneration);
          _scheduleActiveOutboundIpRefresh();
          _schedulePostConnectSelectedProxyUrlTest(
            reason: 'proxy_selected',
            delay: const Duration(milliseconds: 1200),
          );
        } catch (error) {
          if (!mounted ||
              !_proxySelection.isCurrentGeneration(selectionGeneration)) {
            return;
          }
          AppLogStore.error(
            'proxy',
            'Failed to select proxy "$tag" via command API: $error. '
                'Restarting runtime with selected tag.',
          );
          try {
            await _configCoordinator.emitCurrentConfigLogAsync(
              'proxy selection fallback restart',
              restartRuntime: true,
            );
          } catch (restartError) {
            AppLogStore.error(
              'proxy',
              'Failed to restart runtime after proxy selection error: '
                  '$restartError',
            );
            _showAppSnackBar('Failed to select proxy: $error');
          }
        }
      }());
    }
  }

  Future<void> _persistSelectedProxySelection(
    Subscription updatedSubscription, {
    required int generation,
    required bool prepareConfigSnapshot,
  }) async {
    try {
      await Future.wait<void>([
        SubscriptionStore.saveMetadata(updatedSubscription),
        _persistState(),
      ]);
      if (prepareConfigSnapshot) {
        await _persistSelectedProxyConfigSnapshot(
          reason: 'pre-start proxy selection persisted',
          generation: generation,
        );
      }
    } catch (error) {
      AppLogStore.error(
        'proxy',
        'Failed to persist selected outbound '
            'tag=${updatedSubscription.selectedProxyTag}: $error',
      );
    }
  }

  Future<void> _synchronizeSelectedProxyBeforeStart() async {
    final activeSubscription = _activeSubscription;
    if (activeSubscription == null) {
      return;
    }
    var tag = _selectedProxyTag.trim();
    if (tag.isEmpty && activeSubscription.selectedProxyTag.trim().isNotEmpty) {
      tag = activeSubscription.selectedProxyTag.trim();
      if (mounted) {
        setState(() {
          _selectedProxyTag = tag;
          _displayProxyCache =
              _displayProxyForSelectedTag(tag) ?? _displayProxyCache;
          _applyRuntimeStateToDerivedCaches();
        });
      } else {
        _selectedProxyTag = tag;
      }
    }
    if (tag.isEmpty) {
      await _persistState();
      return;
    }
    if (activeSubscription.selectedProxyTag == tag) {
      await Future.wait<void>([
        SubscriptionStore.saveMetadata(activeSubscription),
        _persistState(),
      ]);
      return;
    }
    final updatedSubscription = _withSelectedOutbound(activeSubscription, tag);
    if (mounted) {
      setState(() {
        _subscriptions = _replaceSubscription(updatedSubscription);
        _activeLookupSubscription = null;
        _applyRuntimeStateToDerivedCaches();
      });
    } else {
      _subscriptions = _replaceSubscription(updatedSubscription);
      _activeLookupSubscription = null;
    }
    AppLogStore.info(
      'proxy',
      'start selection sync active=${updatedSubscription.id} '
          'selected=$tag previous=${activeSubscription.selectedProxyTag}',
    );
    await Future.wait<void>([
      SubscriptionStore.saveMetadata(updatedSubscription),
      _persistState(),
    ]);
  }

  void _triggerSelectedProxyUrlTest({
    bool showChecking = true,
    bool ignoreCooldown = false,
  }) {
    if (!_connected || !_foregroundLifecycleActive) return;
    unawaited(_latencyCoordinator.runActive(reason: 'selected_proxy'));
  }

  void _schedulePostConnectSelectedProxyUrlTest({
    required String reason,
    Duration delay = const Duration(milliseconds: 2500),
    bool ignoreCooldown = false,
  }) {
    if (!mounted ||
        !_foregroundLifecycleActive ||
        _selectedProxyTag.trim().isEmpty) {
      return;
    }
    final generation = ++_postConnectUrlTestGeneration;
    _postConnectUrlTestTimer?.cancel();
    _postConnectUrlTestTimer = Timer(delay, () {
      if (!mounted ||
          generation != _postConnectUrlTestGeneration ||
          !_connected ||
          !_foregroundLifecycleActive ||
          _runtimeTransitionInProgress) {
        return;
      }
      if (reason == 'resume_reconcile' || reason == 'runtime_sync_running') {
        AppLogStore.debug(
          'latency',
          'automatic test skipped on foreground reconciliation reason=$reason',
        );
        return;
      }
      AppLogStore.info(
        'proxy',
        'post-connect selected proxy URLTest reason=$reason '
            'selected=$_selectedProxyTag ignoreCooldown=$ignoreCooldown',
      );
      if (reason == 'runtime_running') {
        // The stable libbox URLTest groups run once on startup and own their
        // 30-minute interval. Starting another selector-wide test here races
        // that native session and duplicates every HTTP probe.
        _latencyCoordinator.configureAuto(null);
        AppLogStore.debug(
          'latency',
          'startup test owned by native URLTest groups',
        );
      } else {
        unawaited(_latencyCoordinator.runActive(reason: reason));
      }
    });
  }

  Future<void> _addProxyChain(String detourTag, String targetRef) async {
    final subscription = _activeSubscription;
    if (subscription == null) {
      return;
    }
    _ensureActiveLookupCaches();
    final resolvedTarget = _resolveProxyChainTarget(targetRef);
    if (resolvedTarget == null) {
      return;
    }
    final target = resolvedTarget.outbound;
    final detour = detourTag.trim();
    if (detour.isEmpty) {
      return;
    }
    final tag = _newProxyChainTag(subscription);
    final targetName = target.name.trim().isEmpty
        ? target.tag
        : target.name.trim();
    final chain = SubscriptionProxyChain(
      tag: tag,
      name: 'chain · $targetName',
      targetTag: target.tag,
      detourTag: detour,
      targetSubscriptionId: resolvedTarget.subscription.id,
      targetName: targetName,
      targetCountry: _normalizeCountryCode(target.info.country),
      targetConfig: Map<String, dynamic>.from(target.config),
    );
    await _upsertProxyChain(subscription, chain, selectAfterApply: false);
  }

  Future<void> _changeProxyChainDetour(
    String chainTag,
    String detourTag,
  ) async {
    final subscription = _activeSubscription;
    final existing = _proxyChainForTag(chainTag);
    if (subscription == null || existing == null) {
      return;
    }
    final detour = detourTag.trim();
    if (detour.isEmpty) {
      return;
    }
    final updated = existing.copyWith(detourTag: detour);
    await _upsertProxyChain(subscription, updated, selectAfterApply: false);
  }

  Future<void> _renameProxyChain(String chainTag, String name) async {
    final subscription = _activeSubscription;
    final existing = _proxyChainForTag(chainTag);
    if (subscription == null || existing == null) {
      return;
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName == existing.name) {
      return;
    }
    final updatedChain = existing.copyWith(name: normalizedName);
    final updated = subscription.copyWith(
      proxyChains: [
        for (final chain in subscription.proxyChains)
          chain.tag == existing.tag ? updatedChain : chain,
      ],
    );
    setState(() {
      _subscriptions = _replaceSubscription(updated);
      _activeLookupSubscription = null;
      _displayProxyCache =
          _displayProxyForSelectedTag(_selectedProxyTag) ?? _displayProxyCache;
      _applyRuntimeStateToDerivedCaches();
    });
    _saveStateSoon();
    unawaited(SubscriptionStore.saveMetadata(updated));
    _rebuildDerivedCaches();
  }

  Future<void> _removeProxyChain(String chainTag) async {
    final subscription = _activeSubscription;
    if (subscription == null) {
      return;
    }
    final normalizedTag = chainTag.trim();
    if (normalizedTag.isEmpty) {
      return;
    }
    final nextChains = subscription.proxyChains
        .where((chain) => chain.tag != normalizedTag)
        .toList(growable: false);
    var nextSelectedTag = _selectedProxyTag;
    if (nextSelectedTag == normalizedTag) {
      _ensureActiveLookupCaches();
      nextSelectedTag = '';
      for (final proxy in _activeVisibleOutboundsLookup) {
        if (proxy.tag != normalizedTag) {
          nextSelectedTag = proxy.tag;
          break;
        }
      }
    }
    final updated = subscription.copyWith(
      proxyChains: nextChains,
      selectedProxyTag: nextSelectedTag,
    );
    setState(() {
      _subscriptions = _replaceSubscription(updated);
      _activeLookupSubscription = null;
      _selectedProxyTag = nextSelectedTag;
      _displayProxyCache =
          _displayProxyForSelectedTag(nextSelectedTag) ?? _displayProxyCache;
      _applyRuntimeStateToDerivedCaches();
    });
    _saveStateSoon();
    unawaited(SubscriptionStore.saveMetadata(updated));
    _rebuildDerivedCaches();
    if (_connected) {
      AppLogStore.info(
        'proxy chain',
        'proxy chain removed; applying runtime config tag=$normalizedTag '
            'selected=$nextSelectedTag',
      );
      unawaited(
        _configCoordinator.emitCurrentConfigLogAsync(
          'proxy_chain_removed',
          restartRuntime: false,
        ),
      );
    }
  }

  Future<void> _upsertProxyChain(
    Subscription subscription,
    SubscriptionProxyChain chain, {
    required bool selectAfterApply,
  }) async {
    _ensureActiveLookupCaches();
    final target = _targetOutboundForProxyChain(chain);
    if (target == null) {
      return;
    }
    final config = SingboxConfigBuilder.buildProxyChainOutboundConfig(
      chain: chain,
      target: target,
      snowtunBinaryPath: null,
      snowtunProtectPath: null,
      vpnInboundEnabled: _vpnInboundEnabled,
      tcpFastOpenEnabled: _experimentalTcpFastOpen,
      tcpMultiPathEnabled: _experimentalTcpMultiPath,
      tlsFragmentationMode: _tlsFragmentationMode,
    );
    if (config == null) {
      return;
    }
    final chains = [
      for (final existing in subscription.proxyChains)
        if (existing.tag != chain.tag) existing,
      chain,
    ];
    final updated = subscription.copyWith(
      proxyChains: chains,
      selectedProxyTag: selectAfterApply
          ? chain.tag
          : subscription.selectedProxyTag,
    );
    setState(() {
      _subscriptions = _replaceSubscription(updated);
      _activeLookupSubscription = null;
      if (selectAfterApply) {
        _selectedProxyTag = chain.tag;
      }
      _displayProxyCache =
          _displayProxyForSelectedTag(_selectedProxyTag) ?? _displayProxyCache;
      _applyRuntimeStateToDerivedCaches();
    });
    _saveStateSoon();
    unawaited(SubscriptionStore.saveMetadata(updated));
    _rebuildDerivedCaches();
    if (_connected) {
      AppLogStore.info(
        'proxy chain',
        'proxy chain upserted; applying runtime config tag=${chain.tag} '
            'detour=${chain.detourTag} target=${chain.targetTag}',
      );
      unawaited(
        _configCoordinator.emitCurrentConfigLogAsync(
          'proxy_chain_upserted',
          restartRuntime: false,
        ),
      );
    }
    if (selectAfterApply) {
      _triggerSelectedProxyUrlTest(showChecking: false);
    }
  }

  String _newProxyChainTag(Subscription subscription) {
    final usedTags = <String>{
      ...subscription.outbounds.map((outbound) => outbound.tag),
      ...subscription.groups.map((group) => group.tag),
      ...subscription.proxyChains.map((chain) => chain.tag),
      lowestProxyTag,
      lowestOpenProxyTag,
      lowestFreeProxyTag,
      mixedProxyTag,
      'select',
      'direct',
    };
    final base = 'chain-${DateTime.now().millisecondsSinceEpoch}';
    var tag = base;
    var index = 2;
    while (usedTags.contains(tag)) {
      tag = '$base-$index';
      index++;
    }
    return tag;
  }

  Outbound? _snapshotOutboundForProxyChain(SubscriptionProxyChain chain) {
    if (chain.targetConfig.isEmpty || chain.targetTag.trim().isEmpty) {
      return null;
    }
    final config = Map<String, dynamic>.from(chain.targetConfig);
    config['tag'] = chain.targetTag.trim();
    return Outbound(
      tag: chain.targetTag.trim(),
      name: chain.targetName.trim().isEmpty
          ? chain.targetTag.trim()
          : chain.targetName.trim(),
      config: config,
      info: OutboundInfo(country: chain.targetCountry),
    );
  }

  Outbound? _targetOutboundForProxyChain(SubscriptionProxyChain chain) {
    final activeId = _activeSubscription?.id ?? '';
    final targetSubscriptionId = chain.targetSubscriptionId.trim();
    if (targetSubscriptionId.isNotEmpty && targetSubscriptionId != activeId) {
      return _snapshotOutboundForProxyChain(chain);
    }
    return _activeOutboundByTagLookup[chain.targetTag] ??
        _snapshotOutboundForProxyChain(chain);
  }

  String _proxyDisplayNameForTag(String tag) {
    final normalized = tag.trim();
    if (normalized.isEmpty) {
      return '';
    }
    return _displayProxyForSelectedTag(normalized)?.displayName ??
        (isMixedProxyTag(normalized)
            ? 'mixed'
            : isLowestProxyTag(normalized)
            ? lowestProxyBaseLabel(normalized)
            : normalized);
  }

  void _setLocale(String localeCode) {
    _applySettingsChange(() => _settings.setLocale(localeCode));
  }

  void _setThemePreference(AppThemePreference preference) {
    _applySettingsChange(() => _settings.setThemePreference(preference));
  }

  void _setHapticEnabled(bool value) {
    _applySettingsChange(() => _settings.setHapticEnabled(value));
  }

  void _setHideServerIp(bool value) {
    _applySettingsChange(() => _settings.setHideServerIp(value));
  }

  void _setAccentColor(String hex) {
    _applySettingsChange(() => _settings.setAccentColor(hex));
  }

  void _setVpnMtu(int value) {
    _applySettingsChange(() => _settings.setVpnMtu(value));
  }

  void _setVpnStrictRoute(bool value) {
    _applySettingsChange(() => _settings.setVpnStrictRoute(value));
  }

  void _setVpnTunImplementation(TunImplementationPreference value) {
    _applySettingsChange(() => _settings.setVpnTunImplementation(value));
  }

  void _setProxyInboundEnabled(bool value) {
    _applySettingsChange(() => _settings.setProxyInboundEnabled(value));
  }

  void _setProxyAllowLan(bool value) {
    _applySettingsChange(() => _settings.setProxyAllowLan(value));
  }

  void _setProxyMixedPort(int value) {
    _applySettingsChange(() => _settings.setProxyMixedPort(value));
  }

  void _setInboundConnectionMode(InboundConnectionMode value) {
    _applySettingsChange(() => _settings.setInboundConnectionMode(value));
  }

  void _setProxyPassword(String value) {
    _applySettingsChange(() => _settings.setProxyPassword(value));
  }

  void _setDnsDirectPreset(String value) {
    _applySettingsChange(() => _settings.setDnsDirectPreset(value));
  }

  void _setDnsDirectResolver(String value) {
    _applySettingsChange(() => _settings.setDnsDirectResolver(value));
  }

  void _setDnsProxyPreset(String value) {
    _applySettingsChange(() => _settings.setDnsProxyPreset(value));
  }

  void _setDnsProxyResolver(String value) {
    _applySettingsChange(() => _settings.setDnsProxyResolver(value));
  }

  void _setDnsPreferIpv6(bool value) {
    _applySettingsChange(() => _settings.setDnsPreferIpv6(value));
  }

  void _setRussiaDnsDirectResolver(String value) {
    _applySettingsChange(() => _settings.setRussiaDnsDirectResolver(value));
  }

  void _setUrlTestUrl(String value) {
    _applySettingsChange(() => _settings.setUrlTestUrl(value));
  }

  void _setUrlTestIntervalSeconds(int value) {
    _applySettingsChange(() => _settings.setUrlTestIntervalSeconds(value));
  }

  void _setUrlTestTimeoutSeconds(int value) {
    _applySettingsChange(() => _settings.setUrlTestTimeoutSeconds(value));
  }

  void _setUrlTestConcurrency(int value) {
    _applySettingsChange(() => _settings.setUrlTestConcurrency(value));
  }

  void _setUrlTestUnavailableCheckIntervalSeconds(int value) {
    _applySettingsChange(
      () => _settings.setUrlTestUnavailableCheckIntervalSeconds(value),
    );
  }

  void _setLocationLookupLimit(int value) {
    _applySettingsChange(() => _settings.setLocationLookupLimit(value));
  }

  void _setLocationLookupTimeoutSeconds(int value) {
    _applySettingsChange(
      () => _settings.setLocationLookupTimeoutSeconds(value),
    );
  }

  void _setLocationLookupConcurrency(int value) {
    _applySettingsChange(() => _settings.setLocationLookupConcurrency(value));
  }

  Color? get _seedColor {
    if (_accentColorHex == 'default') return _dynamicLightScheme?.primary;
    final parsed = int.tryParse(_accentColorHex, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }

  void _refreshThemeCache() {
    final useDynamicScheme =
        _accentColorHex == 'default' && _dynamicLightScheme != null;
    final seedColor = _seedColor;

    if (useDynamicScheme) {
      _lightTheme = buildDemoTheme(
        Brightness.light,
        dynamicLightScheme: _dynamicLightScheme,
        dynamicDarkScheme: _dynamicDarkScheme,
      );
      _darkTheme = buildDemoTheme(
        Brightness.dark,
        dynamicLightScheme: _dynamicLightScheme,
        dynamicDarkScheme: _dynamicDarkScheme,
      );
      _amoledTheme = buildAmoledTheme(
        dynamicLightScheme: _dynamicLightScheme,
        dynamicDarkScheme: _dynamicDarkScheme,
      );
    } else {
      _lightTheme = buildDemoTheme(Brightness.light, seedColor: seedColor);
      _darkTheme = buildDemoTheme(Brightness.dark, seedColor: seedColor);
      _amoledTheme = buildAmoledTheme(seedColor: seedColor);
    }
  }

  Future<void> _reloadSubscriptions({
    String? preferredSubscriptionId,
    String? preferredProxyTag,
    bool applyRuntime = true,
    bool resetRuntimeState = false,
    bool restartRuntimeOnApply = false,
    bool urlTestAfterApply = false,
  }) async {
    final resolved = _resolveSubscriptionMetadata(
      activeSubscriptionId: preferredSubscriptionId ?? _activeProfileId,
      selectedProxyTag: preferredProxyTag ?? _selectedProxyTag,
      preferSelectedProxyTag: preferredProxyTag?.trim().isNotEmpty == true,
    );
    final subscriptions = resolved.subscriptions;
    final normalized = resolved.normalized;

    if (!mounted) {
      return;
    }

    final nextActiveId = normalized.activeSubscriptionId;
    final activeChanged = nextActiveId != _activeProfileId;
    final shouldResetRuntimeState = activeChanged || resetRuntimeState;
    final preserveLatencyDuringReload =
        resetRuntimeState && !activeChanged && _connected;
    final previousSelectedTag = _selectedProxyTag;
    if (shouldResetRuntimeState) {
      _latencyCoordinator.cancel();
    }

    setState(() {
      _subscriptions = subscriptions;
      _activeProfileId = nextActiveId;
      _selectedProxyTag = normalized.selectedProxyTag;
      _lastEmptyAfterDropInvalidWarningSubscriptionId = null;
      if (shouldResetRuntimeState) {
        if (!preserveLatencyDuringReload) {
          _runtimeLatencies.clear();
          _unavailableLatencyTags.clear();
          _latencyErrors.clear();
          _latencyFailureCounts.clear();
        }
        _runtimeGroupSelections.clear();
        _lowestLatency = null;
        _runtimeLowestOutboundTag = null;
        _runtimeLowestSelections.clear();
        _clearLastStartedBuildCache();
      }
      _applyMetadataActiveProfile(
        subscriptions,
        normalized.activeSubscriptionId,
        clearProxyCache: shouldResetRuntimeState || _activeProfileCache == null,
      );
    });
    unawaited(_syncQuickSettingsTileLabel());
    if (_connected) {
      _scheduleActiveOutboundIpRefresh();
    }
    if (subscriptions.isNotEmpty) {
      _scheduleActiveSubscriptionHydration(
        activeSubscriptionId: normalized.activeSubscriptionId,
        selectedProxyTag: normalized.selectedProxyTag,
        preserveRuntimeState:
            !shouldResetRuntimeState || preserveLatencyDuringReload,
        applyRuntime: applyRuntime,
        restartRuntimeOnApply: restartRuntimeOnApply,
        urlTestAfterApply: urlTestAfterApply,
      );
    } else if (applyRuntime) {
      _configCoordinator.emitCurrentConfigLog(
        'subscriptions reloaded',
        restartRuntime: restartRuntimeOnApply,
      );
    } else {
      unawaited(
        _configCoordinator.logCurrentSingboxConfig(
          'subscriptions reloaded (runtime skipped)',
        ),
      );
    }
    if (activeChanged || previousSelectedTag != normalized.selectedProxyTag) {
      _saveStateSoon();
    }
  }

  ResolvedSubscriptions _resolveSubscriptionMetadata({
    required String activeSubscriptionId,
    required String selectedProxyTag,
    bool preferSelectedProxyTag = false,
  }) {
    return _subscriptionRuntime.resolveMetadata(
      metadataSubscriptions: SubscriptionStore.getAllMetadata(),
      activeSubscriptionId: activeSubscriptionId,
      selectedProxyTag: selectedProxyTag,
      preferSelectedProxyTag: preferSelectedProxyTag,
    );
  }

  void _scheduleActiveSubscriptionHydration({
    required String activeSubscriptionId,
    required String selectedProxyTag,
    required bool preserveRuntimeState,
    required bool applyRuntime,
    bool restartRuntimeOnApply = false,
    bool urlTestAfterApply = false,
  }) {
    final generation = ++_activeSubscriptionHydrationGeneration;
    unawaited(() async {
      final resolved = await _resolveSubscriptions(
        activeSubscriptionId: activeSubscriptionId,
        selectedProxyTag: selectedProxyTag,
        preserveRuntimeState: preserveRuntimeState,
      );
      if (!mounted || generation != _activeSubscriptionHydrationGeneration) {
        return;
      }
      final normalized = resolved.normalized;
      final activeStillExpected =
          _activeProfileId == activeSubscriptionId ||
          _activeProfileId == normalized.activeSubscriptionId;
      if (!activeStillExpected) {
        return;
      }

      final previousActiveId = _activeProfileId;
      final previousSelectedTag = _selectedProxyTag;
      final activeChanged = normalized.activeSubscriptionId != previousActiveId;
      final shouldResetRuntimeState = activeChanged || !preserveRuntimeState;
      final preserveLatencyDuringReload =
          !preserveRuntimeState && !activeChanged && _connected;
      if (shouldResetRuntimeState) {
        _latencyCoordinator.cancel();
      }
      setState(() {
        _subscriptions = resolved.subscriptions;
        _activeProfileId = normalized.activeSubscriptionId;
        _selectedProxyTag = normalized.selectedProxyTag;
        if (shouldResetRuntimeState) {
          if (!preserveLatencyDuringReload) {
            _runtimeLatencies.clear();
            _unavailableLatencyTags.clear();
            _latencyErrors.clear();
            _latencyFailureCounts.clear();
          }
          _runtimeGroupSelections.clear();
          _lowestLatency = null;
          _runtimeLowestOutboundTag = null;
          _runtimeLowestSelections.clear();
        }
        final proxyCache = resolved.proxyCache;
        if (proxyCache != null) {
          _applyProxyCacheBuildResult(proxyCache);
        } else {
          _applyMetadataActiveProfile(
            resolved.subscriptions,
            normalized.activeSubscriptionId,
            clearProxyCache: shouldResetRuntimeState,
          );
        }
      });
      unawaited(_syncQuickSettingsTileLabel());
      if (_connected) {
        _scheduleActiveOutboundIpRefresh();
      }
      if (applyRuntime) {
        await _configCoordinator.emitCurrentConfigLogAsync(
          'subscriptions reloaded',
          restartRuntime: restartRuntimeOnApply,
        );
        if (urlTestAfterApply && mounted && _connected) {
          _triggerSelectedProxyUrlTest(showChecking: true);
        }
      } else {
        unawaited(
          _configCoordinator.logCurrentSingboxConfig(
            'subscriptions reloaded (runtime skipped)',
          ),
        );
      }
      if (activeChanged || previousSelectedTag != normalized.selectedProxyTag) {
        _saveStateSoon();
      }
    }());
  }

  SubscriptionRuntimeSnapshot _currentSubscriptionRuntimeSnapshot({
    required bool preserveRuntimeState,
  }) {
    if (!preserveRuntimeState) {
      return const SubscriptionRuntimeSnapshot();
    }
    return SubscriptionRuntimeSnapshot(
      lowestLatency: _lowestLatency,
      runtimeLowestOutboundTag: _runtimeLowestOutboundTag,
      runtimeLowestSelections: Map<String, String>.from(
        _runtimeLowestSelections,
      ),
      urlTestInFlight: _urlTestInFlight,
      runtimeLatencies: Map<String, int>.from(_runtimeLatencies),
      unavailableLatencyTags: Set<String>.from(_unavailableLatencyTags),
      latencyErrors: Map<String, String>.from(_latencyErrors),
      runtimeGroupSelections: Map<String, String>.from(_runtimeGroupSelections),
    );
  }

  Future<ResolvedSubscriptions> _resolveSubscriptions({
    required String activeSubscriptionId,
    required String selectedProxyTag,
    required bool preserveRuntimeState,
  }) async {
    return _subscriptionRuntime.resolveSubscriptions(
      metadataSubscriptions: SubscriptionStore.getAllMetadata(),
      activeSubscriptionId: activeSubscriptionId,
      selectedProxyTag: selectedProxyTag,
      preserveRuntimeState: preserveRuntimeState,
      runtimeSnapshot: _currentSubscriptionRuntimeSnapshot(
        preserveRuntimeState: preserveRuntimeState,
      ),
      russiaRouteProxiesEnabled: _russiaRouteProxiesEnabled,
      payloadJsonFor: SubscriptionStore.payloadJsonFor,
    );
  }

  Future<HydratedActiveSubscription>
  _hydrateActiveSubscriptionAndBuildProxyCache(
    Subscription metadata, {
    required String selectedProxyTag,
    required bool preferSelectedProxyTag,
    required bool preserveRuntimeState,
  }) {
    return _subscriptionRuntime.hydrateActiveSubscriptionAndBuildProxyCache(
      metadata: metadata,
      selectedProxyTag: selectedProxyTag,
      preferSelectedProxyTag: preferSelectedProxyTag,
      preserveRuntimeState: preserveRuntimeState,
      runtimeSnapshot: _currentSubscriptionRuntimeSnapshot(
        preserveRuntimeState: preserveRuntimeState,
      ),
      russiaRouteProxiesEnabled: _russiaRouteProxiesEnabled,
      payloadJson: SubscriptionStore.payloadJsonFor(metadata.id),
    );
  }

  Future<bool> _ensureActiveSubscriptionHydratedForRuntime() async {
    final activeSubscription = _activeSubscription;
    if (activeSubscription == null || activeSubscription.outbounds.isNotEmpty) {
      return true;
    }
    final generation = ++_activeSubscriptionHydrationGeneration;
    final hydrated = await _hydrateActiveSubscriptionAndBuildProxyCache(
      activeSubscription,
      selectedProxyTag: _selectedProxyTag,
      preferSelectedProxyTag: _selectedProxyTag.trim().isNotEmpty,
      preserveRuntimeState: true,
    );
    if (!mounted || generation != _activeSubscriptionHydrationGeneration) {
      return false;
    }
    if (_activeProfileId != activeSubscription.id) {
      return false;
    }
    setState(() {
      _subscriptions = _replaceSubscription(hydrated.subscription);
      _selectedProxyTag = hydrated.normalized.selectedProxyTag;
      _applyProxyCacheBuildResult(hydrated.proxyCache);
    });
    unawaited(_syncQuickSettingsTileLabel());
    return true;
  }

  Future<void> _showSubscriptionsPage({bool openAddOnStart = false}) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final beforeMetadataFingerprint = _subscriptionsMetadataFingerprint();
    final beforeActiveRuntimeFingerprint =
        _subscriptionRuntimeFingerprintFromStore(_activeProfileId);
    final subscriptionPageResult = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SubscriptionsPage(
        activeSubscriptionId: _activeProfileId,
        openAddOnStart: openAddOnStart,
        hapticEnabled: _hapticEnabled,
      ),
    );
    final selectedSubscriptionId = subscriptionPageResult is String
        ? subscriptionPageResult
        : null;

    if (mounted) {
      setState(() {});
    }

    final openedWithoutSelection =
        selectedSubscriptionId == null || selectedSubscriptionId.isEmpty;
    if (openedWithoutSelection) {
      final afterMetadataFingerprint = _subscriptionsMetadataFingerprint();
      final afterActiveRuntimeFingerprint =
          _subscriptionRuntimeFingerprintFromStore(_activeProfileId);
      final subscriptionsChanged =
          beforeMetadataFingerprint != afterMetadataFingerprint;
      final activeRuntimeChanged =
          beforeActiveRuntimeFingerprint != afterActiveRuntimeFingerprint;
      if (!subscriptionsChanged && !activeRuntimeChanged) {
        AppLogStore.info(
          'subscription',
          'subscriptions page closed without changes; runtime reload skipped',
        );
        return;
      }
      await _reloadSubscriptions(
        preferredSubscriptionId: _activeProfileId,
        preferredProxyTag: _selectedProxyTag,
        applyRuntime: activeRuntimeChanged,
        resetRuntimeState: activeRuntimeChanged,
        restartRuntimeOnApply: _connected && activeRuntimeChanged,
        urlTestAfterApply: _connected && activeRuntimeChanged,
      );
      return;
    }

    if (selectedSubscriptionId != _activeProfileId) {
      _haptic();
    }

    await _reloadSubscriptions(
      preferredSubscriptionId: selectedSubscriptionId,
      preferredProxyTag: '',
    );
  }

  Future<void> _showSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsPage(
          currentLocaleLabel: switch (_locale?.languageCode) {
            'ru' => AppLocalizations.of(context).languageRussian,
            'en' => AppLocalizations.of(context).languageEnglish,
            _ => AppLocalizations.of(context).languageSystem,
          },
          currentThemeLabel: switch (_themePreference) {
            AppThemePreference.light => AppLocalizations.of(context).themeLight,
            AppThemePreference.dark => AppLocalizations.of(context).themeDark,
            AppThemePreference.amoled => AppLocalizations.of(
              context,
            ).themeAmoled,
            AppThemePreference.system => AppLocalizations.of(
              context,
            ).themeSystem,
          },
          onOpenGeneral: _showGeneralSettingsPage,
          onOpenDns: _showDnsSettingsPage,
          onOpenSubscriptions: _showSubscriptionsSettingsPage,
          onOpenInbound: _showInboundSettingsPage,
          onOpenRouting: _showRoutingSettingsPage,
          onOpenBackup: _showBackupSettingsPage,
          onOpenExperimental: _showExperimentalSettingsPage,
          onOpenLogs: _showLogsPage,
          onOpenAbout: _showAboutSettingsPage,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _warmInstalledApps() {
    final inFlight = _installedAppsWarmupFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final generation = _installedAppsCacheGeneration;
    final future = SingboxRuntime.instance
        .getInstalledApps()
        .then((items) {
          if (generation == _installedAppsCacheGeneration) {
            _installedAppsCache = items;
          }
          _installedAppsWarmupFuture = null;
          return items;
        })
        .catchError((error) {
          _installedAppsWarmupFuture = null;
          throw error;
        });
    _installedAppsWarmupFuture = future;
    return future;
  }

  void _clearInstalledAppsCache() {
    _installedAppsCacheGeneration++;
    _installedAppsWarmupFuture = null;
    _installedAppsCache = const <Map<String, dynamic>>[];
    clearInstalledAppIconCache();
  }

  void _trimRuntimeStartMemory(String reason) {
    final installedAppsBefore = _installedAppsCache.length;
    final cache = PaintingBinding.instance.imageCache;
    final imageBytesBefore = cache.currentSizeBytes;
    final imageEntriesBefore = cache.currentSize;

    _clearInstalledAppsCache();
    clearInstalledAppIconCache();
    cache.clear();
    cache.clearLiveImages();
    _configureImageCacheForAndroid();

    if (installedAppsBefore > 0 ||
        imageBytesBefore > 0 ||
        imageEntriesBefore > 0) {
      AppLogStore.info(
        'memory cleanup',
        'reason=$reason imageBytesBefore=$imageBytesBefore '
            'imageEntriesBefore=$imageEntriesBefore '
            'installedAppsBefore=$installedAppsBefore',
      );
    }
  }

  Future<void> _showGeneralSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsGeneralPage(
          currentLocaleCode: _locale?.languageCode ?? 'system',
          currentThemePreference: _themePreference,
          currentAccentColorHex: _accentColorHex,
          dynamicLightScheme: _dynamicLightScheme,
          onLocaleChanged: _setLocale,
          onThemePreferenceChanged: _setThemePreference,
          currentHapticEnabled: _hapticEnabled,
          currentHideServerIp: _hideServerIp,
          currentPerformanceMode: _performanceMode,
          currentMemoryLimitEnabled: _memoryLimitEnabled,
          currentMemoryLimitWarningDismissed: _memoryLimitWarningDismissed,
          currentUpdateInstallMode: _updateInstallMode,
          onAccentColorChanged: _setAccentColor,
          onHapticChanged: _setHapticEnabled,
          onHideServerIpChanged: _setHideServerIp,
          onPerformanceModeChanged: _setPerformanceMode,
          onMemoryLimitChanged: _setMemoryLimitEnabled,
          onUpdateInstallModeChanged: _setUpdateInstallMode,
        ),
      ),
    );
  }

  Future<void> _showInboundSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsInboundPage(
          currentVpnInboundEnabled: _vpnInboundEnabled,
          currentVpnMtu: _vpnMtu,
          currentVpnStrictRoute: _vpnStrictRoute,
          currentVpnTunImplementation: _vpnTunImplementation,
          currentProxyInboundEnabled: _proxyInboundEnabled,
          currentProxyAllowLan: _proxyAllowLan,
          currentProxyMixedListen: _proxyMixedListen,
          currentProxyMixedPort: _proxyMixedPort,
          currentProxyPassword: _proxyPassword,
          onVpnMtuChanged: _setVpnMtu,
          onVpnStrictRouteChanged: _setVpnStrictRoute,
          onVpnTunImplementationChanged: _setVpnTunImplementation,
          onProxyInboundEnabledChanged: _setProxyInboundEnabled,
          onProxyAllowLanChanged: _setProxyAllowLan,
          onProxyMixedPortChanged: _setProxyMixedPort,
          onConnectionModeChanged: _setInboundConnectionMode,
          onProxyPasswordChanged: _setProxyPassword,
        ),
      ),
    );
  }

  Future<void> _showDnsSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsDnsPage(
          currentDirectPreset: _dnsDirectPreset,
          currentDirectResolver: _dnsDirectResolver,
          currentProxyPreset: _dnsProxyPreset,
          currentProxyResolver: _dnsProxyResolver,
          currentPreferIpv6: _dnsPreferIpv6,
          currentRussiaDnsDirectResolver: _russiaDnsDirectResolver,
          currentRussiaRouteDataEnabled: _useRussiaRouteData,
          onDirectPresetChanged: _setDnsDirectPreset,
          onDirectResolverChanged: _setDnsDirectResolver,
          onProxyPresetChanged: _setDnsProxyPreset,
          onProxyResolverChanged: _setDnsProxyResolver,
          onPreferIpv6Changed: _setDnsPreferIpv6,
          onRussiaDnsDirectResolverChanged: _setRussiaDnsDirectResolver,
        ),
      ),
    );
  }

  Future<void> _showBackupSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    final store = _store;
    if (navigator == null || store == null) return;
    await _refreshAppVersionInfo();
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsBackupPage(
          store: store,
          settingsState: _currentSettingsState(),
          clientVersion: _clientVersionLabel,
          loadSubscriptions: SubscriptionStore.getAll,
          onImportSettings: _applyImportedSettingsState,
          onImportSubscriptions: _importBackupSubscriptions,
        ),
      ),
    );
  }

  Future<void> _showUpdateSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await _refreshAppVersionInfo();
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsUpdatePage(
          currentVersion: _clientVersionLabel,
          installMode: _updateInstallMode,
          onInstallModeChanged: _setUpdateInstallMode,
        ),
      ),
    );
  }

  Future<void> _showChangelogSheet() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    unawaited(_refreshAppVersionInfo());
    await showModalBottomSheet<void>(
      context: navigator.context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChangelogSheet(
        currentVersion: _clientVersionLabel,
        currentBuildNumber: _clientVersionCode,
      ),
    );
  }

  Future<void> _showSubscriptionsSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsSubscriptionsPage(
          currentConfig: UrlTestConfig(
            url: _urlTestUrl,
            intervalSeconds: _urlTestIntervalSeconds,
            timeoutSeconds: _urlTestTimeoutSeconds,
            concurrency: _urlTestConcurrency,
            unavailableCheckIntervalSeconds:
                _urlTestUnavailableCheckIntervalSeconds,
          ),
          currentLocationLookupLimit: _locationLookupLimit,
          currentLocationLookupTimeoutSeconds: _locationLookupTimeoutSeconds,
          currentLocationLookupConcurrency: _locationLookupConcurrency,
          onChanged: (value) async {
            _setUrlTestUrl(value.url ?? '');
            _setUrlTestIntervalSeconds(value.intervalSeconds ?? 180);
            _setUrlTestTimeoutSeconds(value.timeoutSeconds ?? 15);
            _setUrlTestConcurrency(value.concurrency ?? 30);
            _setUrlTestUnavailableCheckIntervalSeconds(
              value.unavailableCheckIntervalSeconds ?? 5,
            );
          },
          onLocationLookupLimitChanged: _setLocationLookupLimit,
          onLocationLookupTimeoutSecondsChanged:
              _setLocationLookupTimeoutSeconds,
          onLocationLookupConcurrencyChanged: _setLocationLookupConcurrency,
        ),
      ),
    );
  }

  Future<void> _showAboutSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await _refreshAppVersionInfo();
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsAboutPage(
          versionLabel: _clientVersionLabel,
          onShowOnboarding: _resetOnboarding,
        ),
      ),
    );
  }

  void _setBlockLeaks(bool value) {
    _applySettingsChange(() => _settings.setBlockLeaks(value));
  }

  void _setAdBlockEnabled(bool value) {
    _applySettingsChange(() => _settings.setAdBlockEnabled(value));
  }

  Future<AdBlockRuleSetStatus> _downloadAdBlockRuleSet() async {
    final status = await AdBlockRuleSetService.instance.downloadLatest();
    if (!mounted) {
      return status;
    }
    setState(() {
      _adBlockStatus = status;
    });
    _configCoordinator.emitCurrentConfigLog('adblock rule-set updated');
    return status;
  }

  Future<AdBlockRuleSetStatus> _deleteAdBlockRuleSet() async {
    final status = await AdBlockRuleSetService.instance.deleteRuleSet();
    if (!mounted) {
      return status;
    }
    setState(() {
      _adBlockStatus = status;
      if (!status.available) {
        _adBlockEnabled = false;
      }
    });
    _configCoordinator.emitCurrentConfigLog('adblock rule-set deleted');
    _saveStateSoon();
    return status;
  }

  void _setRussiaRouteDataEnabled(bool value) {
    _applySettingsChange(() => _settings.setRussiaRouteDataEnabled(value));
  }

  Future<RussiaRouteDataStatus> _installRussiaRouteData() async {
    final hadInstalledData = _russiaRouteDataStatus.available;
    final status = hadInstalledData
        ? await RussiaRouteDataService.instance.ensureUpdated(force: true)
        : await RussiaRouteDataService.instance.ensureBundledInstalled();
    if (!mounted) {
      return status;
    }
    setState(() {
      _russiaRouteDataStatus = status;
    });
    _configCoordinator.emitCurrentConfigLog('russia route data prepared');
    if (!hadInstalledData) {
      unawaited(_updateRussiaRouteDataIfDue());
    }
    return status;
  }

  Future<RussiaRouteUpdateCheck> _checkRussiaRouteDataUpdate() {
    return RussiaRouteDataService.instance.checkForUpdate();
  }

  Future<RussiaRouteDataStatus> _deleteRussiaRouteData() async {
    final status = await RussiaRouteDataService.instance.deleteInstalled();
    if (mounted) {
      setState(() {
        _russiaRouteDataStatus = status;
        _useRussiaRouteData = false;
      });
    }
    unawaited(_persistState());
    _configCoordinator.emitCurrentConfigLog('russia route data deleted');
    return status;
  }

  Future<void> _updateRussiaRouteDataIfDue() async {
    final current = _russiaRouteDataStatus;
    if (!current.available || !current.needsDailyUpdate) {
      return;
    }
    try {
      final status = await RussiaRouteDataService.instance.ensureUpdated();
      if (!mounted) {
        return;
      }
      final changed =
          status.versionTag != current.versionTag ||
          status.domainListCommunityUpdatedAtMillis !=
              current.domainListCommunityUpdatedAtMillis;
      setState(() {
        _russiaRouteDataStatus = status;
      });
      if (changed && _useRussiaRouteData) {
        _configCoordinator.emitCurrentConfigLog('russia route data updated');
      }
    } catch (error) {
      AppLogStore.warning('routes', 'russia route update check failed: $error');
    }
  }

  void _setBypassLocalNetwork(bool value) {
    _applySettingsChange(() => _settings.setBypassLocalNetwork(value));
  }

  void _setSplitRoutingMode(SplitRoutingMode value) {
    if (_splitRoutingTemporarilyDisabled) {
      _applySettingsChange(
        () => _settings.setSplitRoutingMode(SplitRoutingMode.disabled),
      );
      return;
    }
    _applySettingsChange(() => _settings.setSplitRoutingMode(value));
  }

  void _setSplitRoutingPackages(List<String> value) {
    if (_splitRoutingTemporarilyDisabled) {
      _applySettingsChange(
        () => _settings.setSplitRoutingPackages(const <String>[]),
      );
      return;
    }
    _applySettingsChange(() => _settings.setSplitRoutingPackages(value));
  }

  void _setSingBoxLogLevel(String value) {
    var changed = false;
    _applySettingsChange(() {
      final change = _settings.setSingBoxLogLevel(value);
      changed = change.changed;
      return change;
    });
    if (changed) {
      unawaited(_applySingBoxLogLevelChange());
    }
  }

  bool _shouldRecordSingBoxLog(String level) {
    final normalized = level.trim().toLowerCase();
    const priorities = <String, int>{
      'trace': 0,
      'debug': 1,
      'info': 2,
      'warn': 3,
      'warning': 3,
      'error': 4,
    };
    final current = priorities[_singBoxLogLevel] ?? 2;
    final incoming = priorities[normalized] ?? 2;
    return incoming >= current;
  }

  Future<void> _applySingBoxLogLevelChange() async {
    await _persistState();
    await _configCoordinator.emitCurrentConfigLogAsync(
      'sing-box log level changed',
      restartRuntime: true,
      applyWhenNativeRunning: true,
    );
  }

  void _setExperimentalTcpFastOpen(bool value) {
    _applySettingsChange(() => _settings.setExperimentalTcpFastOpen(value));
  }

  void _setExperimentalTcpMultiPath(bool value) {
    _applySettingsChange(() => _settings.setExperimentalTcpMultiPath(value));
  }

  void _setExperimentalInterruptExistingConnections(bool value) {
    _applySettingsChange(
      () => _settings.setExperimentalInterruptExistingConnections(value),
    );
  }

  void _setExperimentalUrlTestStrictTolerance(bool value) {
    _applySettingsChange(
      () => _settings.setExperimentalUrlTestStrictTolerance(value),
    );
  }

  void _setTlsFragmentationMode(TlsFragmentationMode value) {
    _applySettingsChange(() => _settings.setTlsFragmentationMode(value));
  }

  Future<void> _showRoutingSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    unawaited(() async {
      try {
        await _warmInstalledApps();
      } catch (error) {
        AppLogStore.warning('split routing', 'app list preload failed: $error');
      }
    }());
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => SettingsRoutingPage(
            currentBlockLeaks: _blockLeaks,
            currentAdBlockEnabled: _adBlockEnabled,
            currentAdBlockStatus: _adBlockStatus,
            currentRussiaRouteDataEnabled: _useRussiaRouteData,
            currentRussiaRouteDataStatus: _russiaRouteDataStatus,
            currentBypassLocalNetwork: _bypassLocalNetwork,
            currentVpnInboundEnabled: _vpnInboundEnabled,
            currentSplitRoutingMode: _splitRoutingMode,
            currentSplitRoutingPackages: _splitRoutingPackages,
            initialInstalledApps: _installedAppsCache,
            preloadInstalledApps: _warmInstalledApps,
            onBlockLeaksChanged: _setBlockLeaks,
            onAdBlockEnabledChanged: _setAdBlockEnabled,
            onDownloadAdBlockRuleSet: _downloadAdBlockRuleSet,
            onDeleteAdBlockRuleSet: _deleteAdBlockRuleSet,
            onRussiaRouteDataEnabledChanged: _setRussiaRouteDataEnabled,
            onCheckRussiaRouteDataUpdate: _checkRussiaRouteDataUpdate,
            onInstallRussiaRouteData: _installRussiaRouteData,
            onDeleteRussiaRouteData: _deleteRussiaRouteData,
            onBypassLocalNetworkChanged: _setBypassLocalNetwork,
            onSplitRoutingModeChanged: _setSplitRoutingMode,
            onSplitRoutingPackagesChanged: _setSplitRoutingPackages,
          ),
        ),
      );
    } finally {
      _clearInstalledAppsCache();
    }
  }

  Future<void> _showExperimentalSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsExperimentalPage(
          currentTcpFastOpen: _experimentalTcpFastOpen,
          currentTcpMultiPath: _experimentalTcpMultiPath,
          currentInterruptExistingConnections:
              _experimentalInterruptExistingConnections,
          currentUrlTestStrictTolerance: _experimentalUrlTestStrictTolerance,
          currentTlsFragmentationMode: _tlsFragmentationMode,
          onTcpFastOpenChanged: _setExperimentalTcpFastOpen,
          onTcpMultiPathChanged: _setExperimentalTcpMultiPath,
          onInterruptExistingConnectionsChanged:
              _setExperimentalInterruptExistingConnections,
          onUrlTestStrictToleranceChanged:
              _setExperimentalUrlTestStrictTolerance,
          onTlsFragmentationModeChanged: _setTlsFragmentationMode,
        ),
      ),
    );
  }

  Future<void> _showLogsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsLogsPage(
          currentSingBoxLogLevel: _singBoxLogLevel,
          onSingBoxLogLevelChanged: _setSingBoxLogLevel,
        ),
      ),
    );
  }

  Future<void> _runUrlTest({bool haptic = true}) async {
    if (!_connected || !_foregroundLifecycleActive) {
      return;
    }
    if (_latencyCoordinator.isRunning) {
      final context = _navigatorKey.currentContext;
      if (context != null) {
        _showAppSnackBar(AppLocalizations.of(context).checkingLatency);
      }
      return;
    }
    if (haptic) {
      _haptic();
    }
    await _latencyCoordinator.runFull(reason: 'manual');
  }

  void _scheduleSingleOutboundPingRefresh() {
    if (!_foregroundLifecycleActive) {
      return;
    }
    _ensureActiveLookupCaches();
    final activeSubscription = _activeSubscription;
    if (activeSubscription == null ||
        activeSubscription.proxyChains.isNotEmpty) {
      return;
    }
    final visibleOutbounds = _activeVisibleOutboundsLookup;
    if (visibleOutbounds.length != 1) {
      return;
    }
    final outboundTag = visibleOutbounds.single.tag;
    if (_runtimeLatencies.containsKey(outboundTag)) {
      return;
    }
    if (_singleOutboundPingRefreshScheduled) {
      return;
    }
    _singleOutboundPingRefreshScheduled = true;
    unawaited(() async {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted || !_connected) {
          return;
        }
        _ensureActiveLookupCaches();
        if (_activeVisibleOutboundsLookup.length != 1 ||
            _activeVisibleOutboundsLookup.single.tag != outboundTag) {
          return;
        }
        _schedulePostConnectSelectedProxyUrlTest(
          reason: 'single_outbound_ping',
          delay: const Duration(milliseconds: 900),
        );
      } catch (_) {
      } finally {
        _singleOutboundPingRefreshScheduled = false;
      }
    }());
  }

  Future<void> _handleRuntimeLifecycleTimeout(
    RuntimeLifecycleResult result,
  ) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _setConnectionPhase(AppConnectionPhase.failed);
    });
    _showAppSnackBar(_vpnStartTimedOutMessage);
  }

  Future<void> _startRuntimeWithBuild(
    SingboxConfigBuildResult build, {
    required bool useVpn,
  }) async {
    final result = await _configCoordinator.startRuntimeWithBuild(
      build,
      useVpn: useVpn,
    );
    if (!mounted) {
      return;
    }
    if (result.success) {
      return;
    }
    _runtimeDesiredByUser = false;
    setState(() {
      _setConnectionPhase(AppConnectionPhase.failed);
    });
    _showAppSnackBar(
      result.timedOut ? _vpnStartTimedOutMessage : _vpnStartFailedMessage,
    );
  }

  void _setConfigCoordinatorPhase(SingboxConfigCoordinatorPhase phase) {
    if (!mounted) {
      return;
    }
    setState(() {
      _setConnectionPhase(switch (phase) {
        SingboxConfigCoordinatorPhase.reconfiguring =>
          AppConnectionPhase.reconfiguring,
        SingboxConfigCoordinatorPhase.stopping => AppConnectionPhase.stopping,
        SingboxConfigCoordinatorPhase.connected => AppConnectionPhase.connected,
        SingboxConfigCoordinatorPhase.failed => AppConnectionPhase.failed,
      });
    });
  }

  void _showRuntimeConfigFailure({required bool timedOut}) {
    _showAppSnackBar(
      timedOut ? _vpnStartTimedOutMessage : _vpnStartFailedMessage,
    );
  }

  void _setSelectedProxyTagLocally(String tag) {
    final activeSubscription = _activeSubscription;
    if (activeSubscription != null &&
        activeSubscription.selectedProxyTag != tag) {
      final updatedSubscription = _withSelectedOutbound(
        activeSubscription,
        tag,
      );
      _subscriptions = _replaceSubscription(updatedSubscription);
      _activeLookupSubscription = null;
    }
    _selectedProxyTag = tag;
    _displayProxyCache = _displayProxyForSelectedTag(tag) ?? _displayProxyCache;
  }

  int _beginLocalProxySelection() {
    final hadPending = _proxySelection.hasPendingRuntimeSelection;
    final generation = _proxySelection.beginLocalSelection();
    if (hadPending) {
      _publishProxyRuntimeVisualStates();
    }
    return generation;
  }

  int _beginRuntimeProxySelectionGuard(String tag, String previousTag) {
    final generation = _proxySelection.beginRuntimeSelection(
      tag: tag,
      previousTag: previousTag,
      onTimeout: _handleRuntimeProxySelectionTimeout,
    );
    _publishProxyRuntimeVisualStates();
    return generation;
  }

  void _handleRuntimeProxySelectionTimeout(ProxySelectionTimeout timeout) {
    if (!mounted || !_proxySelection.isCurrentGeneration(timeout.generation)) {
      return;
    }
    AppLogStore.warning(
      'proxy',
      'runtime did not confirm selected outbound tag=${timeout.tag} '
          'previous=${timeout.previousTag ?? '<none>'}; '
          'restarting runtime with local selection',
    );
    unawaited(() async {
      try {
        if (_connected) {
          await _configCoordinator.emitCurrentConfigLogAsync(
            'proxy selection confirmation timeout',
            restartRuntime: true,
          );
        }
      } catch (error) {
        AppLogStore.error(
          'proxy',
          'Failed to restart runtime after selection confirmation timeout: '
              '$error',
        );
      } finally {
        _clearRuntimeProxySelectionGuard(generation: timeout.generation);
      }
    }());
  }

  void _clearRuntimeProxySelectionGuard({int? generation}) {
    if (_proxySelection.clearRuntimeSelection(generation: generation)) {
      _publishProxyRuntimeVisualStates();
    }
  }

  Future<void> _persistSelectedProxyConfigSnapshot({
    required String reason,
    required int generation,
  }) async {
    if (!mounted || !_proxySelection.isCurrentGeneration(generation)) {
      return;
    }
    try {
      final build = await _configCoordinator
          .buildCurrentSingboxConfigInBackground(returnConfig: false);
      if (build == null ||
          !mounted ||
          !_proxySelection.isCurrentGeneration(generation)) {
        if (build != null) {
          _configCoordinator.discardPreparedConfigCandidate(build);
        }
        return;
      }
      await _configCoordinator.promotePreparedConfigBuild(build);
      _cacheLastStartedBuild(build);
      _configCoordinator.recordBuiltConfigLog(reason, build);
    } catch (error) {
      AppLogStore.warning(
        'proxy',
        'Failed to persist selected proxy config snapshot: $error',
      );
    }
  }

  void _cacheLastStartedBuild(SingboxConfigBuildResult build) {
    _lastStartedProxyOutboundTagsByIndex = Map<int, String>.from(
      build.plan.proxyOutboundTagsByIndex,
    );
    _lastStartedConfig = build.plan.config.isEmpty ? null : build.plan.config;
  }

  void _clearLastStartedBuildCache() {
    _lastStartedProxyOutboundTagsByIndex = null;
    _lastStartedConfig = null;
    _pendingMutationExcludedTag = null;
  }

  SingboxConfigCoordinatorSnapshot _currentSingboxConfigSnapshot() {
    final routeData = _russiaRouteDataStatus;
    return SingboxConfigCoordinatorSnapshot(
      connected: _connected,
      runtimeTransitionInProgress: _runtimeTransitionInProgress,
      activeSubscription: _activeSubscription,
      selectedProxyTag: _selectedProxyTag,
      excludedOutboundTags: Set<String>.from(_excludedRuntimeOutboundTags),
      vpnInboundEnabled: _vpnInboundEnabled,
      vpnMtu: _vpnMtu,
      vpnStrictRoute: _vpnStrictRoute,
      vpnTunImplementation: _vpnTunImplementation,
      proxyInboundEnabled: _proxyInboundEnabled,
      proxyMixedListen: _proxyMixedListen,
      proxyMixedPort: _proxyMixedPort,
      proxyPassword: _proxyPassword,
      dnsDirectResolver: _dnsDirectResolver,
      dnsProxyResolver: _dnsProxyResolver,
      dnsPreferIpv6: _dnsPreferIpv6,
      russiaDnsDirectResolver: _russiaDnsDirectResolver,
      urlTestUrl: _urlTestUrl,
      urlTestIntervalSeconds: _urlTestIntervalSeconds,
      urlTestTimeoutSeconds: _urlTestTimeoutSeconds,
      urlTestConcurrency: _urlTestConcurrency,
      urlTestUnavailableCheckIntervalSeconds:
          _urlTestUnavailableCheckIntervalSeconds,
      blockLeaks: _blockLeaks,
      adBlockEnabled: _adBlockEnabled,
      adBlockBlockRuleSetPath: _adBlockStatus.blockRuleSetPath,
      adBlockAllowRuleSetPath: _adBlockStatus.allowRuleSetPath,
      useRussiaRouteData: _useRussiaRouteData,
      routeDataAvailable: routeData.available,
      routeDataSourceKind: routeData.sourceKind,
      routeDataRelease: routeData.releaseTag ?? routeData.versionTag,
      russiaGeositeRuBlockedPath: routeData.geositeRuBlockedPath,
      russiaGeositeRuAvailableOnlyInsidePath:
          routeData.geositeRuAvailableOnlyInsidePath,
      russiaGeositeCategoryRuPath: routeData.geositeCategoryRuPath,
      russiaGeoipRuBlockedPath: routeData.geoipRuBlockedPath,
      russiaGeoipRuWhitelistPath: routeData.geoipRuWhitelistPath,
      russiaGeoipRuPath: routeData.geoipRuPath,
      russiaCuratedDirectServicesPath: routeData.curatedDirectServicesPath,
      russiaAiServicesPath: routeData.aiServicesPath,
      bypassLocalNetwork: _bypassLocalNetwork,
      splitRoutingMode: _splitRoutingMode,
      splitRoutingPackages: _splitRoutingPackages,
      logLevel: _singBoxLogLevel,
      tcpFastOpenEnabled: _experimentalTcpFastOpen,
      tcpMultiPathEnabled: _experimentalTcpMultiPath,
      tlsFragmentationMode: _tlsFragmentationMode,
      interruptExistingConnections: _experimentalInterruptExistingConnections,
      urlTestStrictTolerance: _experimentalUrlTestStrictTolerance,
      markAllServersRussia: _activeSubscription?.markAllServersRussia ?? false,
    );
  }

  void _startSingboxEvents() {
    _runtimeEvents.start();
    unawaited(_syncRuntimeState());
  }

  void _handleRuntimeStateEvent(RuntimeStateEvent event) {
    final running = event.running;
    final error = event.error;
    final hasError = event.hasError;
    final wasRetryScheduled = _invalidOutboundRetryScheduled;
    if (!mounted) return;
    var shouldSyncQuickSettingsTile = false;
    var shouldCancelLatency = false;
    setState(() {
      final keepStateDuringError =
          hasError &&
          (_runtimeTransitionInProgress ||
              _invalidOutboundRetryScheduled ||
              _starting);
      final keepConnecting =
          !running &&
          (!hasError || keepStateDuringError) &&
          (_runtimeTransitionInProgress ||
              _invalidOutboundRetryScheduled ||
              _starting);
      if (running) {
        _runtimeDesiredByUser = true;
        _setConnectionPhase(AppConnectionPhase.connected);
        _lastLocationLookupSignature = '';
      } else if (hasError) {
        if (keepStateDuringError) {
          _setConnectionPhase(
            AppConnectionPhase.recovering,
            retryScheduled: _invalidOutboundRetryScheduled,
          );
        } else {
          _setConnectionPhase(AppConnectionPhase.failed);
        }
      } else {
        _setConnectionPhase(
          keepConnecting
              ? (_invalidOutboundRetryScheduled
                    ? AppConnectionPhase.recovering
                    : AppConnectionPhase.starting)
              : AppConnectionPhase.idle,
          retryScheduled: keepConnecting && _invalidOutboundRetryScheduled,
        );
      }
      if (!running && !keepConnecting) {
        shouldCancelLatency = true;
        shouldSyncQuickSettingsTile = true;
        _resetActiveProxyIpState();
        _locationLookupGeneration++;
        _locationLookupTimer?.cancel();
        _locationLookupInFlight = false;
        _locationLookupRefreshRequested = false;
        _cancelQueuedLocationLookups();
        _resetTrafficDashboardData();
        _lowestLatency = null;
        _runtimeLowestOutboundTag = null;
        _runtimeLowestSelections.clear();
        _runtimeLatencies.clear();
        _unavailableLatencyTags.clear();
        _latencyErrors.clear();
        _latencyFailureCounts.clear();
        _singleOutboundPingRefreshScheduled = false;
        _postConnectUrlTestGeneration++;
        _postConnectUrlTestTimer?.cancel();
        _networkReconnectWatchdogTimer?.cancel();
        _networkReconnectWatchdogTimer = null;
        _networkRecoveryDecisionTimer?.cancel();
        _networkRecoveryDecisionTimer = null;
        _applyRuntimeStateToDerivedCaches();
      }
    });
    if (shouldCancelLatency) {
      _latencyCoordinator.configureAuto(null);
      _latencyCoordinator.cancel();
    }
    _publishTrafficDashboardSnapshot();
    if (shouldSyncQuickSettingsTile) {
      unawaited(_syncQuickSettingsTileLabel());
    }
    if (hasError) {
      unawaited(_handleRuntimeError(error ?? '', wasRetryScheduled));
    } else if (running) {
      _scheduleActiveOutboundIpRefresh();
      _schedulePostConnectSelectedProxyUrlTest(reason: 'runtime_running');
      if (!_coolMode) {
        _scheduleBestOutboundLocationRefresh(
          delay: _balancedMode
              ? const Duration(seconds: 8)
              : const Duration(seconds: 3),
        );
      }
      _scheduleSingleOutboundPingRefresh();
    }
  }

  void _handleTrafficStatusEvent(Map<String, dynamic> event) {
    if (!mounted || !_foregroundLifecycleActive) {
      return;
    }
    if (!_balancedMode) {
      _applyTrafficStatusEvent(event);
      return;
    }
    _pendingTrafficStatusEvent = event;
    final now = DateTime.now();
    final elapsed = now.difference(_lastTrafficUiUpdateAt);
    if (elapsed >= _trafficUiUpdateInterval) {
      _flushPendingTrafficStatusEvent();
      return;
    }
    _trafficUiUpdateTimer ??= Timer(_trafficUiUpdateInterval - elapsed, () {
      _trafficUiUpdateTimer = null;
      _flushPendingTrafficStatusEvent();
    });
  }

  void _flushPendingTrafficStatusEvent() {
    final event = _pendingTrafficStatusEvent;
    if (event == null) {
      return;
    }
    _pendingTrafficStatusEvent = null;
    _applyTrafficStatusEvent(event);
  }

  void _applyTrafficStatusEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final now = DateTime.now();
    _lastRuntimeStatusEventAt = now;
    final uplink = (event['uplink'] as num?)?.toInt() ?? 0;
    final downlink = (event['downlink'] as num?)?.toInt() ?? 0;
    final uplinkTotal = (event['uplinkTotal'] as num?)?.toInt() ?? 0;
    final downlinkTotal = (event['downlinkTotal'] as num?)?.toInt() ?? 0;
    final trafficAvailable = event['trafficAvailable'] == true;
    if (_uplinkBytesPerSecond == uplink &&
        _downlinkBytesPerSecond == downlink &&
        _uplinkTotalBytes == uplinkTotal &&
        _downlinkTotalBytes == downlinkTotal &&
        _trafficAvailable == trafficAvailable) {
      return;
    }
    _lastTrafficUiUpdateAt = now;
    setState(() {
      _uplinkBytesPerSecond = uplink;
      _downlinkBytesPerSecond = downlink;
      _uplinkTotalBytes = uplinkTotal;
      _downlinkTotalBytes = downlinkTotal;
      _trafficAvailable = trafficAvailable;
      _recordTrafficSample(now);
    });
    _publishTrafficDashboardSnapshot();
  }

  void _handleRuntimeNetworkEvent(Map<String, dynamic> event) {
    final now = DateTime.now();
    final reason = event['reason']?.toString() ?? 'network';
    final interfaceName = event['interfaceName']?.toString();
    final interfaceIndex = (event['interfaceIndex'] as num?)?.toInt() ?? 0;
    final networkGeneration =
        (event['networkGeneration'] as num?)?.toInt() ??
        ++_networkInterfaceGeneration;
    AppLogStore.info(
      'network',
      'default network changed: $reason'
          '${interfaceName == null || interfaceName.isEmpty ? '' : ' ($interfaceName)'} '
          'networkGeneration=$networkGeneration selected=$_selectedProxyTag',
    );
    _networkInterfaceGeneration = networkGeneration;
    if (reason == 'default_interface' &&
        interfaceName != null &&
        interfaceName.isNotEmpty &&
        interfaceIndex > 0) {
    } else {
      _postConnectUrlTestGeneration++;
      _postConnectUrlTestTimer?.cancel();
      _postConnectUrlTestTimer = null;
      _activeProxyIpController.cancelRetry();
      AppLogStore.warning(
        'network',
        'default interface unavailable reason=$reason '
            'networkGeneration=$networkGeneration selected=$_selectedProxyTag',
      );
    }
    if (!_connected || _runtimeTransitionInProgress) {
      return;
    }
    if (!_foregroundLifecycleActive) {
      _retryRuntimeOnResume = true;
      return;
    }
    if (reason == 'default_interface' &&
        interfaceName != null &&
        interfaceName.isNotEmpty &&
        interfaceIndex > 0) {
      _scheduleNetworkRecovery(
        reason: 'default_interface_changed',
        networkGeneration: networkGeneration,
        changedAt: now,
      );
      _schedulePostConnectSelectedProxyUrlTest(
        reason: 'default_interface_changed',
        delay: const Duration(milliseconds: 900),
      );
      return;
    }
    _networkReconnectWatchdogTimer?.cancel();
    _networkReconnectWatchdogTimer = null;
    _networkRecoveryDecisionTimer?.cancel();
    _networkRecoveryDecisionTimer = null;
  }

  Future<void> _syncRuntimeState() async {
    try {
      final status = await SingboxRuntime.instance.status();
      if (!mounted || !_foregroundLifecycleActive) return;
      final running = status['running'] == true;
      final recordedServiceAlive = status['recordedServiceAlive'] == true;
      final runtimeIntentFresh = status['runtimeIntentFresh'] == true;
      final activeRuntimeOwner = status['activeRuntimeOwner'] == true;
      final nativeRecoveryPending = nativeRuntimeRecoveryPending(
        running: running,
        recordedServiceAlive: recordedServiceAlive,
        activeRuntimeOwner: activeRuntimeOwner,
        runtimeIntentFresh: runtimeIntentFresh,
      );
      final localTransitionPending =
          _starting ||
          _invalidOutboundRetryScheduled ||
          _runtimeLifecycle.startWatchdogActive;
      if (nativeRecoveryPending) {
        _logRuntimeRecoveryStatus(status);
      }
      final now = DateTime.now();
      setState(() {
        if (running) {
          _runtimeDesiredByUser = true;
        }
        _setConnectionPhase(
          running
              ? AppConnectionPhase.connected
              : (nativeRecoveryPending ||
                        localTransitionPending ||
                        _invalidOutboundRetryScheduled
                    ? AppConnectionPhase.recovering
                    : AppConnectionPhase.idle),
          retryScheduled: !running && _invalidOutboundRetryScheduled,
        );
        _uplinkBytesPerSecond = (status['uplink'] as num?)?.toInt() ?? 0;
        _downlinkBytesPerSecond = (status['downlink'] as num?)?.toInt() ?? 0;
        _uplinkTotalBytes = (status['uplinkTotal'] as num?)?.toInt() ?? 0;
        _downlinkTotalBytes = (status['downlinkTotal'] as num?)?.toInt() ?? 0;
        _trafficAvailable =
            _uplinkBytesPerSecond > 0 ||
            _downlinkBytesPerSecond > 0 ||
            _uplinkTotalBytes > 0 ||
            _downlinkTotalBytes > 0;
        if (running) {
          _recordTrafficSample(now);
        } else if (!nativeRecoveryPending) {
          _resetTrafficDashboardData();
          _postConnectUrlTestGeneration++;
          _postConnectUrlTestTimer?.cancel();
          _postConnectUrlTestTimer = null;
        }
      });
      _publishTrafficDashboardSnapshot();
      if (running &&
          await _networkInterfaceUsable(reason: 'runtime_sync_running')) {
        _scheduleActiveOutboundIpRefresh();
        _schedulePostConnectSelectedProxyUrlTest(
          reason: 'runtime_sync_running',
          delay: const Duration(milliseconds: 600),
          ignoreCooldown: true,
        );
      } else if (running) {
        AppLogStore.warning(
          'runtime',
          'runtime sync running but interface is not usable yet',
        );
      }
    } catch (_) {
      // Ignore transient sync failures: live EventChannel events still drive state.
    }
  }

  void _logRuntimeRecoveryStatus(Map<String, dynamic> status) {
    final now = DateTime.now();
    final previous = _lastRuntimeRecoveryStatusLogAt;
    if (previous != null &&
        now.difference(previous) < _runtimeRecoveryStatusLogInterval) {
      return;
    }
    _lastRuntimeRecoveryStatusLogAt = now;
    AppLogStore.warning(
      'runtime',
      'runtime sync pending native recovery '
          'running=${status['running']} '
          'recordedAlive=${status['recordedServiceAlive']} '
          'recordedMode=${status['recordedServiceMode'] ?? ''} '
          'intentFresh=${status['runtimeIntentFresh']} '
          'intentMode=${status['runtimeIntentMode'] ?? ''} '
          'intentReason=${status['runtimeIntentReason'] ?? ''} '
          'intent=${status['runtimeIntentState'] ?? ''} '
          'service=${status['recordedServiceState'] ?? ''}',
    );
  }

  Future<void> _handleRuntimeError(String error, bool wasRetryScheduled) async {
    AppLogStore.error('sing-box', error);
    if (wasRetryScheduled && _isTransientConfigRetryError(error)) {
      AppLogStore.warning(
        'sing-box',
        'Retrying after transient config decode failure: $error',
      );
      _invalidOutboundRetryScheduled = false;
      _invalidOutboundRetryTimer?.cancel();
      _scheduleInvalidOutboundRetry(
        'retry after transient config decode failure',
      );
      return;
    }
    if (wasRetryScheduled) {
      _invalidOutboundRetryScheduled = false;
      _invalidOutboundRetryTimer?.cancel();
    }
    if (await _tryRecoverFromInvalidOutbound(error)) {
      if (mounted) {
        setState(() {
          _setConnectionPhase(
            AppConnectionPhase.recovering,
            retryScheduled: true,
          );
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _runtimeDesiredByUser = false;
        _setConnectionPhase(AppConnectionPhase.failed);
      });
    } else {
      _runtimeDesiredByUser = false;
      _setConnectionPhase(AppConnectionPhase.failed);
    }
    if (_lastRuntimeError != error) {
      _lastRuntimeError = error;
      unawaited(_showCoreStartFailedDialog(error));
    }
  }

  Future<bool> _tryRecoverFromInvalidOutbound(String error) async {
    final runtimeError = parseRuntimeInvalidOutboundError(error);
    if (runtimeError == null) {
      return false;
    }
    String? tag =
        _lastStartedProxyOutboundTagsByIndex?[runtimeError.outboundIndex];
    if (tag == null) {
      // Cache miss: fall back to a one-off build to map index→tag.
      final build = await _configCoordinator
          .buildCurrentSingboxConfigInBackground(
            dropStale: false,
            prepareConfig: false,
          );
      if (build == null) {
        return false;
      }
      tag = build.plan.proxyOutboundTagsByIndex[runtimeError.outboundIndex];
    }
    if (tag == null || _excludedRuntimeOutboundTags.contains(tag)) {
      return false;
    }
    _excludedRuntimeOutboundTags.add(tag);
    _pendingMutationExcludedTag = tag;
    AppLogStore.warning(
      'sing-box',
      'Skipping invalid outbound "$tag": ${runtimeError.reason}',
    );
    _warnIfNoOutboundsRemainAfterDropInvalid();
    _scheduleInvalidOutboundRetry('retry without invalid outbound $tag');
    return true;
  }

  bool _isTransientConfigRetryError(String error) {
    final normalized = error.toLowerCase();
    return normalized.contains('decode config: unexpected eof');
  }

  void _warnIfNoOutboundsRemainAfterDropInvalid() {
    final subscription = _activeSubscription;
    if (subscription == null) {
      return;
    }
    final hasRemainingOutbounds = subscription.outbounds.any(
      (outbound) =>
          !outbound.info.deleted &&
          !_excludedRuntimeOutboundTags.contains(outbound.tag),
    );
    if (hasRemainingOutbounds) {
      if (_lastEmptyAfterDropInvalidWarningSubscriptionId == subscription.id) {
        _lastEmptyAfterDropInvalidWarningSubscriptionId = null;
      }
      return;
    }
    if (_lastEmptyAfterDropInvalidWarningSubscriptionId == subscription.id) {
      return;
    }
    _lastEmptyAfterDropInvalidWarningSubscriptionId = subscription.id;
    final context = _navigatorKey.currentContext;
    final message = context == null
        ? 'No valid outbounds remain after drop invalid.'
        : AppLocalizations.of(context).noValidOutboundsAfterDropInvalidWarning;
    AppLogStore.warning('subscription', message);
    if (context != null) {
      unawaited(
        _showNoValidOutboundsDialog(
          title: AppLocalizations.of(context).noValidOutboundsTitle,
          message: AppLocalizations.of(
            context,
          ).noValidOutboundsAfterDropInvalidMessage,
        ),
      );
    }
  }

  bool _applyStartupValidationResult(
    SingboxConfigBuildResult build,
    String reason,
  ) {
    if (build.invalidOutboundCount > 0) {
      final sample = build.invalidOutbounds
          .take(5)
          .map((outbound) {
            final label = outbound.name.trim().isEmpty
                ? outbound.tag
                : outbound.name.trim();
            return '"$label": ${outbound.reason}';
          })
          .join('; ');
      final sampleText = sample.isEmpty ? 'no sample' : sample;
      final suffix = build.invalidOutboundCount > build.invalidOutbounds.length
          ? '; +${build.invalidOutboundCount - build.invalidOutbounds.length} more'
          : '';
      AppLogStore.warning(
        'sing-box',
        'Skipped ${build.invalidOutboundCount} invalid outbounds before start ($reason): $sampleText$suffix',
      );
      if (build.selectedProxyInvalid) {
        _selectedProxyTag = _lowestProxyTag;
      }
    }
    return build.startableOutboundCount > 0;
  }

  void _scheduleInvalidOutboundRetry(String reason) {
    if (!mounted || _invalidOutboundRetryScheduled || !_runtimeDesiredByUser) {
      return;
    }
    if (!_foregroundLifecycleActive) {
      _retryRuntimeOnResume = true;
      return;
    }
    _retryRuntimeOnResume = false;
    if (mounted) {
      setState(() {
        _setConnectionPhase(
          AppConnectionPhase.recovering,
          retryScheduled: true,
        );
      });
    } else {
      _setConnectionPhase(AppConnectionPhase.recovering, retryScheduled: true);
    }
    final retryGeneration = ++_invalidOutboundRetryGeneration;
    _invalidOutboundRetryTimer?.cancel();
    _invalidOutboundRetryTimer = Timer(const Duration(milliseconds: 300), () {
      _invalidOutboundRetryTimer = null;
      if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
        return;
      }
      AppLogStore.info('sing-box', reason);
      unawaited(() async {
        try {
          await SingboxRuntime.instance.stop(reason: 'invalid_outbound_retry');
        } catch (_) {}
        if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
          return;
        }
        if (await _tryFastRetryViaMutation(reason, retryGeneration)) {
          return;
        }
        if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
          return;
        }
        final build = await _configCoordinator
            .buildCurrentSingboxConfigInBackground(
              dropStale: false,
              returnConfig: true,
            );
        if (build == null) {
          if (mounted) {
            setState(() {
              _setConnectionPhase(AppConnectionPhase.failed);
            });
          } else {
            _setConnectionPhase(AppConnectionPhase.failed);
          }
          return;
        }
        if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
          _configCoordinator.discardPreparedConfigCandidate(build);
          return;
        }
        if (!_applyStartupValidationResult(build, reason)) {
          _configCoordinator.discardPreparedConfigCandidate(build);
          if (mounted) {
            setState(() {
              _setConnectionPhase(AppConnectionPhase.failed);
            });
          } else {
            _setConnectionPhase(AppConnectionPhase.failed);
          }
          _showNoValidOutboundsWarning();
          return;
        }
        await _startRuntimeWithBuild(build, useVpn: _vpnInboundEnabled);
      }());
    });
  }

  bool _automaticRuntimeRecoveryCurrent(int generation) {
    return mounted &&
        _runtimeDesiredByUser &&
        _invalidOutboundRetryScheduled &&
        generation == _invalidOutboundRetryGeneration;
  }

  void _cancelAutomaticRuntimeRecovery(String reason) {
    final hadPendingRecovery =
        _invalidOutboundRetryScheduled || _retryRuntimeOnResume;
    _invalidOutboundRetryGeneration++;
    _retryRuntimeOnResume = false;
    _invalidOutboundRetryScheduled = false;
    _invalidOutboundRetryTimer?.cancel();
    _invalidOutboundRetryTimer = null;
    if (hadPendingRecovery) {
      AppLogStore.info('runtime', 'automatic recovery cancelled: $reason');
    }
  }

  Future<bool> _tryFastRetryViaMutation(
    String reason,
    int retryGeneration,
  ) async {
    if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
      return true;
    }
    final cachedConfig = _lastStartedConfig;
    final cachedIndexMap = _lastStartedProxyOutboundTagsByIndex;
    final excludedTag = _pendingMutationExcludedTag;
    if (cachedConfig == null || cachedIndexMap == null || excludedTag == null) {
      return false;
    }
    final configPath = await _configCoordinator.ensureSingboxConfigPath();
    if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
      return true;
    }
    if (configPath == null || configPath.trim().isEmpty) {
      return false;
    }
    final ConfigMutationResult mutation;
    try {
      mutation = await mutateSingboxConfigInBackground(
        ConfigMutationInput(
          config: cachedConfig,
          proxyOutboundTagsByIndex: cachedIndexMap,
          tagToRemove: excludedTag,
          outputPath: configPath,
        ),
      );
    } catch (error) {
      AppLogStore.warning(
        'sing-box',
        'Fast retry mutation failed for "$excludedTag", falling back to rebuild: $error',
      );
      return false;
    }
    if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
      return true;
    }
    _pendingMutationExcludedTag = null;
    _lastStartedConfig = mutation.config;
    _lastStartedProxyOutboundTagsByIndex = mutation.proxyOutboundTagsByIndex;
    if (mutation.startableProxyCount == 0) {
      if (mounted) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.failed);
        });
      } else {
        _setConnectionPhase(AppConnectionPhase.failed);
      }
      _showNoValidOutboundsWarning();
      return true;
    }
    final route = mutation.config['route'] as Map<String, dynamic>?;
    final routeRules = (route?['rules'] as List?) ?? const [];
    final inbounds = (mutation.config['inbounds'] as List?) ?? const [];
    final build = SingboxConfigBuildResult(
      plan: SingboxBuildPlan(
        config: mutation.config,
        proxyOutboundTagsByIndex: mutation.proxyOutboundTagsByIndex,
        visibleProxyOutboundCount: mutation.startableProxyCount,
      ),
      configJson: '',
      configPath: mutation.configPath,
      configLength: 0,
      configOutboundCount: mutation.outboundCount,
      configInboundCount: inbounds.length,
      configRouteRuleCount: routeRules.length,
      invalidOutbounds: const <InvalidStartupOutbound>[],
      invalidOutboundCount: 0,
      selectedProxyInvalid: false,
      startableOutboundCount: mutation.startableProxyCount,
    );
    AppLogStore.info(
      'sing-box',
      'Fast retry: applied in-memory mutation excluding "$excludedTag" '
          '(${mutation.outboundCount} outbounds remain)',
    );
    if (!_automaticRuntimeRecoveryCurrent(retryGeneration)) {
      return true;
    }
    await _startRuntimeWithBuild(build, useVpn: _vpnInboundEnabled);
    return true;
  }

  void _showNoValidOutboundsWarning() {
    final context = _navigatorKey.currentContext;
    final message = context == null
        ? 'No valid outbounds remain in the selected subscription.'
        : AppLocalizations.of(context).noValidOutboundsWarning;
    AppLogStore.warning('subscription', message);
    if (context != null) {
      unawaited(
        _showNoValidOutboundsDialog(
          title: AppLocalizations.of(context).noValidOutboundsTitle,
          message: AppLocalizations.of(context).noValidOutboundsMessage,
        ),
      );
    }
  }

  Future<void> _showNoValidOutboundsDialog({
    required String title,
    required String message,
  }) async {
    if (_noValidOutboundsDialogVisible) {
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context == null || !mounted) {
      return;
    }
    _noValidOutboundsDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(dialogContext).close),
            ),
          ],
        ),
      );
    } finally {
      _noValidOutboundsDialogVisible = false;
    }
  }

  Future<void> _showCoreStartFailedDialog(String message) async {
    if (_runtimeErrorDialogVisible) {
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context == null || !mounted) {
      return;
    }
    _runtimeErrorDialogVisible = true;
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.coreStartFailedTitle),
        content: Text(l10n.coreStartFailedMessage(message)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_showLogsPage());
            },
            child: Text(l10n.logsTitle),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
    _runtimeErrorDialogVisible = false;
  }

  void _applyGroupUpdates(List<dynamic> rawGroups) {
    if (kDebugMode) {
      developer.Timeline.timeSync(
        'MeowClient._applyGroupUpdates',
        () => _applyGroupUpdatesImpl(rawGroups),
        arguments: <String, Object?>{'groups': rawGroups.length},
      );
      return;
    }
    _applyGroupUpdatesImpl(rawGroups);
  }

  void _applyGroupUpdatesImpl(List<dynamic> rawGroups) {
    _recordGroupsDiagnostics(rawGroups.length);
    final activeSubscription = _activeSubscription;
    if (activeSubscription == null || rawGroups.isEmpty || !mounted) {
      return;
    }
    final previousActiveOutboundTag = _connected
        ? _currentResolvedActiveOutboundTag()
        : null;
    _ensureActiveLookupCaches();

    final result = _proxyRuntime.applyGroupUpdates(
      ProxyRuntimeGroupUpdateInput(
        rawGroups: rawGroups,
        activeSubscription: activeSubscription,
        selectedProxyTag: _selectedProxyTag,
        pendingRuntimeSelectTag: _proxySelection.pendingRuntimeSelectTag,
        runtimeSelectionUpdatesAllowed: _proxySelection
            .runtimeSelectionUpdatesAllowed(
              connected: _connected,
              connectionStable:
                  _connectionPhase == AppConnectionPhase.connected,
              transitionInProgress: _runtimeTransitionInProgress,
            ),
        currentResolvedActiveOutboundTag: previousActiveOutboundTag,
        activeOutboundTags: _activeOutboundByTagLookup.keys.toSet(),
        latencySessionRunning: _latencyCoordinator.isRunning,
        proxyCacheContainsTag: _proxyCacheContainsTag,
        visibleGroupProxyCacheMissingChild: _visibleGroupProxyCacheMissingChild,
      ),
    );
    if (!result.changed) {
      return;
    }

    void applyRuntimeUpdates() {
      if (result.shouldClearRuntimeProxySelectionGuard) {
        _clearRuntimeProxySelectionGuard();
      }
      final selectedTag = result.selectedProxyTagToApply;
      if (selectedTag != null) {
        _setSelectedProxyTagLocally(selectedTag);
      }
      if (result.requiresRootRebuild) {
        _applyRuntimeStateToDerivedCaches();
      } else {
        _publishProxyRuntimeVisualStates();
      }
    }

    if (result.requiresRootRebuild) {
      setState(applyRuntimeUpdates);
    } else {
      applyRuntimeUpdates();
    }
    if (result.shouldRebuildProxyCache) {
      _rebuildDerivedCaches();
    }
    unawaited(_syncQuickSettingsTileLabel());
    if (_connected) {
      final nextActiveOutboundTag = _currentResolvedActiveOutboundTag();
      if (nextActiveOutboundTag != null &&
          nextActiveOutboundTag != previousActiveOutboundTag) {
        _scheduleActiveOutboundIpRefresh();
      }
      if (result.realOutboundRuntimeStateChanged) {
        _scheduleBestOutboundLocationRefresh();
      }
    }
  }

  void _recordGroupsDiagnostics(int groupCount) {
    if (!kDebugMode) {
      return;
    }
    _groupsEventsSinceLastDiagnosticsLog++;
    final now = DateTime.now();
    final previous = _lastGroupsDiagnosticsLogAt;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 5)) {
      return;
    }
    _lastGroupsDiagnosticsLogAt = now;
    debugPrint(
      'Meow diagnostics: groupsEvents=$_groupsEventsSinceLastDiagnosticsLog '
      'groups=$groupCount activeProxies=${_activeProxiesCache.length}',
    );
    _groupsEventsSinceLastDiagnosticsLog = 0;
  }

  Outbound? _currentResolvedActiveOutbound() {
    _ensureActiveLookupCaches();
    final visibleOutbounds = _activeVisibleOutboundsLookup;
    if (visibleOutbounds.isEmpty) {
      return null;
    }
    final selectedLowestTag = isMixedProxyTag(_selectedProxyTag)
        ? lowestProxyTag
        : _selectedProxyTag;
    if (isLowestProxyTag(selectedLowestTag)) {
      final eligibleOutbounds = _lowestEligibleOutbounds(
        selectedLowestTag,
        visibleOutbounds,
      );
      final defaultOutbounds = _lowestEligibleOutbounds(
        lowestProxyTag,
        visibleOutbounds,
      );
      if (eligibleOutbounds.isEmpty && defaultOutbounds.isEmpty) {
        return null;
      }
      final runtimeLowestOutboundTag = _runtimeLowestOutboundTagFor(
        selectedLowestTag,
      );
      final hasResolvedLowest =
          (runtimeLowestOutboundTag?.isNotEmpty ?? false) ||
          _runtimeLatencies.isNotEmpty ||
          _unavailableLatencyTags.isNotEmpty;
      if (!hasResolvedLowest) {
        return null;
      }
      if (runtimeLowestOutboundTag != null &&
          runtimeLowestOutboundTag.isNotEmpty) {
        final outbound = _activeOutboundByTagLookup[runtimeLowestOutboundTag];
        final effectiveOutbounds = eligibleOutbounds.isEmpty
            ? defaultOutbounds
            : eligibleOutbounds;
        if (outbound != null && effectiveOutbounds.contains(outbound)) {
          return outbound;
        }
      }
      return _lowestSelectedOutbound(
        selectedLowestTag,
        eligibleOutbounds.isEmpty ? defaultOutbounds : eligibleOutbounds,
      );
    }
    final selectedGroup = _subscriptionGroupForTag(_selectedProxyTag);
    if (selectedGroup != null) {
      return _selectedGroupOutbound(selectedGroup);
    }
    final selectedChain = _proxyChainForTag(_selectedProxyTag);
    if (selectedChain != null) {
      final target = _targetOutboundForProxyChain(selectedChain);
      if (target != null) {
        return target.copyWith(tag: selectedChain.tag);
      }
    }
    return _activeOutboundByTagLookup[_selectedProxyTag] ??
        _checkedOutboundFromVisibleOutbounds() ??
        visibleOutbounds.first;
  }

  SubscriptionGroup? _subscriptionGroupForTag(String tag) {
    _ensureActiveLookupCaches();
    return _activeGroupByTagLookup[tag];
  }

  Outbound? _selectedGroupOutbound(SubscriptionGroup group) {
    final runtimeSelectedTag = _runtimeGroupSelections[group.tag];
    if (runtimeSelectedTag != null &&
        group.outboundTags.contains(runtimeSelectedTag)) {
      final outbound = _activeOutboundByTagLookup[runtimeSelectedTag];
      if (outbound != null) {
        return outbound;
      }
    }

    Outbound? firstChild;
    Outbound? bestChild;
    int? bestLatency;
    for (final tag in group.outboundTags) {
      final outbound = _activeOutboundByTagLookup[tag];
      if (outbound == null) {
        continue;
      }
      firstChild ??= outbound;
      if (_unavailableLatencyTags.contains(tag)) {
        continue;
      }
      final latency = _runtimeLatencies[tag] ?? outbound.info.latestPing;
      if (latency == null) {
        continue;
      }
      if (bestLatency == null || latency < bestLatency) {
        bestLatency = latency;
        bestChild = outbound;
      }
    }
    return bestChild ?? firstChild;
  }

  String? _currentResolvedActiveOutboundTag() {
    return _currentResolvedActiveOutbound()?.tag;
  }

  void _scheduleActiveOutboundIpRefresh({
    Duration delay = const Duration(milliseconds: 120),
    bool forceRefresh = false,
  }) {
    _activeProxyIpController.schedule(
      delay: delay,
      forceRefresh: forceRefresh,
      isConnected: () => _connected,
      isForegroundActive: () => _foregroundLifecycleActive,
      currentTarget: _currentActiveProxyIpTarget,
      networkUsable: (reason) => _networkInterfaceUsable(reason: reason),
      resolveExternalIp: _resolveActiveProxyIp,
      persistResult: _persistActiveProxyIpResult,
      onSnapshot: _publishActiveProxyIpSnapshot,
    );
  }

  void _refreshActiveProxyIp() {
    if (!_connected) {
      return;
    }
    _scheduleActiveOutboundIpRefresh(delay: Duration.zero, forceRefresh: true);
  }

  ActiveProxyIpTarget? _currentActiveProxyIpTarget() {
    final activeSubscription = _activeSubscription;
    final activeOutbound = _currentResolvedActiveOutbound();
    if (activeSubscription == null || activeOutbound == null) {
      return null;
    }
    return ActiveProxyIpTarget(
      subscriptionId: activeSubscription.id,
      outboundTag: activeOutbound.tag,
      cachedIp: activeOutbound.info.externalIp?.trim(),
      cachedCountryCode: _normalizeCountryCode(activeOutbound.info.country),
      hasCachedLocation: _hasResolvedExternalLocation(activeOutbound),
    );
  }

  Future<ActiveProxyIpResolveResult?> _resolveActiveProxyIp(
    String outboundTag,
  ) async {
    final resolved = await _fetchExternalIpInfo(outboundTag: outboundTag);
    if (resolved == null) {
      return null;
    }
    return ActiveProxyIpResolveResult(
      ip: resolved.ip,
      countryCode: resolved.countryCode,
    );
  }

  Future<void> _persistActiveProxyIpResult(
    ActiveProxyIpTarget target,
    ActiveProxyIpResolveResult result,
  ) async {
    final latestSubscription = _activeSubscription;
    final latestActiveOutbound = _currentResolvedActiveOutbound();
    if (latestSubscription == null ||
        latestSubscription.id != target.subscriptionId ||
        latestActiveOutbound == null ||
        latestActiveOutbound.tag != target.outboundTag) {
      return;
    }
    await _applyResolvedExternalIpInfos(
      subscriptionId: target.subscriptionId,
      resolvedByTag: {
        target.outboundTag: _ResolvedExternalIpInfo(
          ip: result.ip,
          countryCode: result.countryCode,
        ),
      },
    );
  }

  Future<_ResolvedExternalIpInfo?> _fetchExternalIpInfo({
    required String outboundTag,
  }) async {
    if (outboundTag == _currentResolvedActiveOutboundTag()) {
      final result = await lookupFastExitIp();
      if (result == null) {
        AppLogStore.warning(
          'proxy',
          'active_ip_lookup_result tag=$outboundTag error=fast_lookup_failed',
        );
        return null;
      }
      AppLogStore.info(
        'proxy',
        'active_ip_lookup_result tag=$outboundTag status=known '
            'source=${result.source}',
      );
      return _ResolvedExternalIpInfo(
        ip: result.ip,
        countryCode: _normalizeCountryCode(result.countryCode),
      );
    }
    final slot = await _acquireLocationLookupSlot();
    if (slot == null) {
      return null;
    }
    final lookup = SingboxRuntime.instance.lookupOutboundExternalInfo(
      outboundTag: outboundTag,
    );
    unawaited(
      lookup.whenComplete(slot.release).then<void>((_) {}, onError: (_) {}),
    );
    try {
      final response = await lookup.timeout(
        Duration(seconds: _locationLookupTimeoutSeconds),
      );
      return _ResolvedExternalIpInfo.fromResponse(
        response,
        normalizeCountryCode: _normalizeCountryCode,
      );
    } on TimeoutException {
      AppLogStore.warning(
        'proxy',
        'active_ip_lookup_result tag=$outboundTag error=timeout',
      );
      return null;
    } catch (error) {
      AppLogStore.warning(
        'proxy',
        'active_ip_lookup_result tag=$outboundTag error=core_error '
            'detail=$error',
      );
      return null;
    }
  }

  Future<_LocationLookupSlot?> _acquireLocationLookupSlot() async {
    if (_locationLookupActiveRequests >= _locationLookupConcurrency) {
      final waiter = Completer<bool>();
      _locationLookupWaiters.add(waiter);
      final acquired = await waiter.future;
      if (!acquired || !mounted) {
        return null;
      }
    } else {
      _locationLookupActiveRequests++;
    }
    return _LocationLookupSlot(_releaseLocationLookupSlot);
  }

  void _releaseLocationLookupSlot() {
    _locationLookupActiveRequests = max(0, _locationLookupActiveRequests - 1);
    _pumpLocationLookupWaiters();
  }

  void _pumpLocationLookupWaiters() {
    while (_locationLookupWaiters.isNotEmpty &&
        _locationLookupActiveRequests < _locationLookupConcurrency) {
      final waiter = _locationLookupWaiters.removeFirst();
      if (waiter.isCompleted) {
        continue;
      }
      _locationLookupActiveRequests++;
      waiter.complete(true);
    }
  }

  void _cancelQueuedLocationLookups() {
    while (_locationLookupWaiters.isNotEmpty) {
      final waiter = _locationLookupWaiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete(false);
      }
    }
  }

  Future<void> _applyResolvedExternalIpInfos({
    required String subscriptionId,
    required Map<String, _ResolvedExternalIpInfo> resolvedByTag,
  }) async {
    if (resolvedByTag.isEmpty ||
        !_connected ||
        !mounted ||
        _markAllServersRussia) {
      return;
    }
    final latestSubscription = _activeSubscription;
    if (latestSubscription == null || latestSubscription.id != subscriptionId) {
      return;
    }
    var subscriptionChanged = false;
    final runtimeUrlTestRemovals = <String, Set<String>>{};
    final updatedSubscription = latestSubscription.copyWith(
      outbounds: latestSubscription.outbounds
          .map((outbound) {
            final resolved = resolvedByTag[outbound.tag];
            if (resolved == null) {
              return outbound;
            }
            final nextCountry = resolved.countryCode ?? outbound.info.country;
            final nextInfo = outbound.info.copyWith(
              externalIp: resolved.ip,
              country: nextCountry,
            );
            if (nextInfo.externalIp == outbound.info.externalIp &&
                nextInfo.country == outbound.info.country) {
              return outbound;
            }
            if (_russiaRouteProxiesEnabled && !_markAllServersRussia) {
              for (final lowestTag in lowestProxyTags.skip(1)) {
                final wasAllowed = lowestProxyAllowsCountry(
                  lowestTag,
                  outbound.info.country,
                );
                final isAllowed = lowestProxyAllowsCountry(
                  lowestTag,
                  nextCountry,
                );
                if (wasAllowed && !isAllowed) {
                  (runtimeUrlTestRemovals[lowestTag] ??= <String>{}).add(
                    outbound.tag,
                  );
                }
              }
            }
            subscriptionChanged = true;
            return outbound.copyWith(info: nextInfo);
          })
          .toList(growable: false),
    );
    if (!subscriptionChanged || !mounted) {
      return;
    }
    setState(() {
      _subscriptions = _replaceSubscription(updatedSubscription);
      _rebuildDerivedCaches();
    });
    await SubscriptionStore.saveOutboundRuntimeInfoInBackground(
      updatedSubscription.id,
      externalInfos: {
        for (final entry in resolvedByTag.entries)
          entry.key: {
            'external_ip': entry.value.ip,
            'country': entry.value.countryCode,
          },
      },
    );
    _removeRuntimeUrlTestOutbounds(runtimeUrlTestRemovals);
  }

  void _removeRuntimeUrlTestOutbounds(Map<String, Set<String>> removals) {
    if (!_connected || removals.isEmpty) {
      return;
    }
    for (final entry in removals.entries) {
      final groupTag = entry.key;
      final outboundTags = entry.value.toList(growable: false);
      if (outboundTags.isEmpty) {
        continue;
      }
      unawaited(() async {
        try {
          _logLibboxCall(
            'removeUrlTestOutbounds',
            'reason=runtime URLTest member cleanup group=$groupTag count=${outboundTags.length} tags=${outboundTags.take(12).join(', ')}',
          );
          await SingboxRuntime.instance.removeUrlTestOutbounds(
            groupTag: groupTag,
            outboundTags: outboundTags,
          );
        } catch (error) {
          AppLogStore.warning(
            'sing-box',
            'Failed to update $groupTag URLTest members: $error',
          );
        }
      }());
    }
  }

  void _scheduleBestOutboundLocationRefresh({
    Duration delay = const Duration(seconds: 1),
  }) {
    if (!mounted || !_foregroundLifecycleActive) {
      _locationLookupTimer?.cancel();
      _locationLookupRefreshRequested = false;
      return;
    }
    if (_locationLookupInFlight) {
      _locationLookupRefreshRequested = true;
      return;
    }
    _locationLookupTimer?.cancel();
    final generation = ++_locationLookupGeneration;
    if (!_connected || _locationLookupLimit <= 0 || _markAllServersRussia) {
      _locationLookupRefreshRequested = false;
      return;
    }
    final effectiveDelay = _proxyPanelInteractionActive
        ? delay + const Duration(seconds: 3)
        : delay;
    _locationLookupTimer = Timer(effectiveDelay, () {
      unawaited(_refreshBestOutboundLocations(generation: generation));
    });
  }

  Future<void> _refreshBestOutboundLocations({required int generation}) async {
    if (_locationLookupInFlight ||
        !_connected ||
        !_foregroundLifecycleActive ||
        !mounted ||
        generation != _locationLookupGeneration ||
        _locationLookupLimit <= 0 ||
        _markAllServersRussia) {
      return;
    }
    if (_proxyPanelInteractionActive) {
      _scheduleBestOutboundLocationRefresh(delay: const Duration(seconds: 3));
      return;
    }
    final activeSubscription = _activeSubscription;
    if (activeSubscription == null) {
      return;
    }
    final targets = _bestOutboundsForLocationLookup();
    if (targets.isEmpty) {
      return;
    }
    final targetTags = targets
        .take(_locationLookupLimit)
        .where((outbound) => !_hasResolvedExternalLocation(outbound))
        .map((outbound) => outbound.tag)
        .toList(growable: false);
    if (targetTags.isEmpty) {
      return;
    }
    final signature =
        '${activeSubscription.id}|$_locationLookupLimit|'
        '${targetTags.map((tag) => '$tag:${_runtimeLatencies[tag] ?? _activeOutboundByTagLookup[tag]?.info.latestPing ?? ''}').join('|')}';
    if (signature == _lastLocationLookupSignature) {
      return;
    }
    _lastLocationLookupSignature = signature;
    _locationLookupInFlight = true;
    try {
      final resolvedByTag = await _fetchExternalIpInfoBatch(
        targetTags,
        subscriptionId: activeSubscription.id,
        generation: generation,
      );
      if (resolvedByTag.isEmpty ||
          !_connected ||
          !mounted ||
          generation != _locationLookupGeneration) {
        return;
      }
      await _applyResolvedExternalIpInfos(
        subscriptionId: activeSubscription.id,
        resolvedByTag: resolvedByTag,
      );
    } finally {
      final refreshRequested = _locationLookupRefreshRequested;
      _locationLookupRefreshRequested = false;
      _locationLookupInFlight = false;
      if (mounted &&
          _connected &&
          (refreshRequested || generation != _locationLookupGeneration) &&
          _locationLookupLimit > 0) {
        _scheduleBestOutboundLocationRefresh(
          delay: _proxyPanelInteractionActive
              ? const Duration(seconds: 3)
              : Duration.zero,
        );
      }
    }
  }

  Future<Map<String, _ResolvedExternalIpInfo>> _fetchExternalIpInfoBatch(
    List<String> outboundTags, {
    required String subscriptionId,
    required int generation,
  }) async {
    final resolvedByTag = <String, _ResolvedExternalIpInfo>{};
    var nextIndex = 0;
    final workerCount = min(outboundTags.length, _locationLookupConcurrency);
    Future<void> worker() async {
      while (mounted &&
          _connected &&
          generation == _locationLookupGeneration &&
          _activeSubscription?.id == subscriptionId) {
        final index = nextIndex;
        nextIndex++;
        if (index >= outboundTags.length) {
          return;
        }
        final tag = outboundTags[index];
        final resolved = await _fetchExternalIpInfo(outboundTag: tag);
        if (resolved != null) {
          resolvedByTag[tag] = resolved;
        }
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    return resolvedByTag;
  }

  List<Outbound> _bestOutboundsForLocationLookup() {
    _ensureActiveLookupCaches();
    final outbounds = _activeVisibleOutboundsLookup
        .where(
          (outbound) =>
              !_unavailableLatencyTags.contains(outbound.tag) &&
              (_runtimeLatencies[outbound.tag] != null ||
                  outbound.info.latestPing != null),
        )
        .toList(growable: false);
    outbounds.sort((left, right) {
      final leftLatency =
          _runtimeLatencies[left.tag] ?? left.info.latestPing ?? (1 << 30);
      final rightLatency =
          _runtimeLatencies[right.tag] ?? right.info.latestPing ?? (1 << 30);
      if (leftLatency != rightLatency) {
        return leftLatency.compareTo(rightLatency);
      }
      return left.name.compareTo(right.name);
    });
    return outbounds;
  }

  bool _hasResolvedExternalLocation(Outbound outbound) {
    if (_markAllServersRussia) {
      return true;
    }
    final externalIp = outbound.info.externalIp?.trim() ?? '';
    if (externalIp.isEmpty) {
      return false;
    }
    return _normalizeCountryCode(outbound.info.country).isNotEmpty;
  }

  String _normalizeCountryCode(String? countryCode) {
    final normalized = countryCode?.trim().toUpperCase() ?? '';
    return RegExp(r'^[A-Z]{2}$').hasMatch(normalized) ? normalized : '';
  }

  String _effectiveOutboundCountry(Outbound outbound) {
    return _markAllServersRussia
        ? 'RU'
        : _normalizeCountryCode(outbound.info.country);
  }

  String _protocolLabel(Map<String, dynamic> config, String fallbackType) {
    final parts = <String>[
      fallbackType.toUpperCase(),
      ...[_securityLabel(config), _transportLabel(config)].whereType<String>(),
    ];
    return parts.join(' · ');
  }

  String? _securityLabel(Map<String, dynamic> config) {
    final tls = config['tls'];
    if (tls is Map) {
      final reality = tls['reality'];
      if (reality is Map && reality['enabled'] == true) {
        return 'REALITY';
      }
      if (tls['enabled'] == true) {
        return 'TLS';
      }
    }

    final security = (config['security'] as String?)?.trim();
    if (security == null ||
        security.isEmpty ||
        security.toLowerCase() == 'none') {
      return null;
    }
    return security.toUpperCase();
  }

  String? _transportLabel(Map<String, dynamic> config) {
    final transport = config['transport'];
    if (transport is Map) {
      final type = (transport['type'] as String?)?.trim();
      if (type != null && type.isNotEmpty) {
        return type.toUpperCase();
      }
    }
    return null;
  }

  String _endpointLabel(Outbound outbound) {
    if (outbound.server.isEmpty) {
      return outbound.tag;
    }
    if (outbound.port <= 0) {
      return outbound.server;
    }
    return '${outbound.server}:${outbound.port}';
  }

  Outbound? _checkedOutboundFromVisibleOutbounds() {
    for (final outbound in _activeVisibleOutboundsLookup) {
      if (outbound.info.checked) {
        return outbound;
      }
    }
    return null;
  }

  Subscription _withSelectedOutbound(Subscription subscription, String tag) {
    return _proxySelection.withSelectedOutbound(subscription, tag);
  }

  List<Subscription> _replaceSubscription(Subscription updated) {
    return _proxySelection.replaceSubscription(_subscriptions, updated);
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        if (lightDynamic != _dynamicLightScheme ||
            darkDynamic != _dynamicDarkScheme) {
          _dynamicLightScheme = lightDynamic;
          _dynamicDarkScheme = darkDynamic;
          if (_accentColorHex == 'default') {
            _refreshThemeCache();
          }
        }
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Etonify',
          theme: _lightTheme,
          darkTheme: _themePreference == AppThemePreference.amoled
              ? _amoledTheme
              : _darkTheme,
          themeMode: _themeMode,
          locale: _locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          localeResolutionCallback: (locale, supportedLocales) {
            final forcedLocale = _locale;
            if (forcedLocale != null) {
              return forcedLocale;
            }
            if (locale?.languageCode.toLowerCase() == 'ru') {
              return const Locale('ru');
            }
            return const Locale('en');
          },
          builder: (context, child) {
            final theme = Theme.of(context);
            final brightness = theme.brightness;
            final overlayStyle = SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
              statusBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: brightness == Brightness.dark
                  ? Brightness.dark
                  : Brightness.light,
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlayStyle,
              child: AppVisualEffects(
                progressiveBlurEnabled: _effectiveProgressiveBlurEnabled,
                hapticEnabled: _hapticEnabled,
                child: AppScrollEffects(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          home: ProxyPanelShell(
            ready: _ready,
            onboardingCompleted: _onboardingCompleted && _legalAccepted,
            loading: const Scaffold(
              key: ValueKey('loading'),
              body: Center(child: CircularProgressIndicator()),
            ),
            welcome: _onboardingCompleted
                ? LegalConsentPage(
                    key: const ValueKey('legal-consent'),
                    requiredVersion: _requiredLegalVersion,
                    onAccept: _acceptLegalDocuments,
                  )
                : WelcomePage(
                    key: const ValueKey('welcome'),
                    onContinue: _completeOnboarding,
                    brandName: 'Etonify',
                    versionLabel: _clientVersionLabel,
                  ),
            visibleRows: _proxyPanelVisibleRows(),
            hasActiveProfile: _activeProfileCache != null,
            resetListKey: _activeProfileId,
            onInteractionActiveChanged: (active) {
              if (_proxyPanelInteractionActive == active) {
                return;
              }
              setState(() {
                _proxyPanelInteractionActive = active;
              });
            },
            homeBuilder: (context, metrics, gestures) {
              final activeSubscription = _activeSubscription;
              final canRefreshActiveSubscription =
                  activeSubscription != null &&
                  !SubscriptionStore.isLocalFileImportUrl(
                    activeSubscription.url,
                  );
              return HomePage(
                connected: _connected,
                connecting: _connectionBusy,
                resolvingProxy: _resolvingLowestProxy,
                connectionStatusLabel: _connectionButtonStatusLabel(context),
                activeProfile: _activeProfile,
                activeProxy: _displayProxy,
                hideServerIp: _hideServerIp,
                hapticEnabled: _hapticEnabled,
                speedBytesPerSecond: _connected && _trafficAvailable
                    ? _downlinkBytesPerSecond.toDouble()
                    : 0,
                trafficBytes: _connected && _trafficAvailable
                    ? (_uplinkTotalBytes + _downlinkTotalBytes).toDouble()
                    : 0,
                onToggleConnection: () => unawaited(
                  _toggleConnection(source: 'home.connection_button'),
                ),
                onRefreshLatency: () => unawaited(_runUrlTest()),
                onRefreshActiveProxyIp: _refreshActiveProxyIp,
                onHideServerIpChanged: _setHideServerIp,
                onOpenSubscriptions: _showSubscriptionsPage,
                onAddSubscription: () =>
                    _showSubscriptionsPage(openAddOnStart: true),
                onOpenSettings: _showSettingsPage,
                onOpenChangelog: () => unawaited(_showChangelogSheet()),
                onOpenTrafficDashboard: () =>
                    unawaited(_showTrafficDashboard()),
                onRefreshActiveSubscription: canRefreshActiveSubscription
                    ? _refreshActiveSubscription
                    : null,
                activeProfileRefreshing: _activeProfileRefreshInFlight,
                showActiveProfileRefreshAction: activeSubscription != null,
                brandName: 'Etonify',
                versionLabel: _clientVersionLabel,
                bottomInset: metrics.bottomInset + proxyPanelMinHeight + 20,
                onProxyPanelInteractionStart: gestures.onInteractionStart,
                onProxyPanelDragUpdate: gestures.onDragUpdate,
                onProxyPanelDragEnd: gestures.onDragEnd,
                showActiveProxyFooter: false,
              );
            },
            sheetBuilder:
                (
                  context,
                  metrics,
                  metricsListenable,
                  scrollController,
                  gestures,
                ) {
                  return ProxiesPage(
                    proxies: _activeProxies,
                    groupChildrenByTag: _activeGroupChildrenByTag,
                    totalTopLevelProxies: _activeTopLevelProxiesCount,
                    selectedTag: _selectedProxyTag,
                    activeProxy: _displayProxy,
                    activeProxyHideIp: _hideServerIp,
                    connected: _connected,
                    hapticEnabled: _hapticEnabled,
                    speedBytesPerSecond: _connected && _trafficAvailable
                        ? _downlinkBytesPerSecond.toDouble()
                        : 0,
                    trafficBytes: _connected && _trafficAvailable
                        ? (_uplinkTotalBytes + _downlinkTotalBytes).toDouble()
                        : 0,
                    progressiveBlurEnabled: _effectiveProgressiveBlurEnabled,
                    onSelected: _selectProxy,
                    onUrlTest: _runUrlTest,
                    onActiveProxyIpRefresh: _refreshActiveProxyIp,
                    outboundForTag: _outboundForProxyTag,
                    loadProxyChainTargetSources: _loadProxyChainTargetSources,
                    loadProxyChainTargetsForSource:
                        _loadProxyChainTargetsForSource,
                    onAddProxyChain: _addProxyChain,
                    onChangeProxyChainDetour: _changeProxyChainDetour,
                    onRenameProxyChain: _renameProxyChain,
                    onRemoveProxyChain: _removeProxyChain,
                    isProxyChainTag: _isProxyChainTag,
                    onActiveProxyHideIpChanged: _setHideServerIp,
                    runtimeStates: _proxyRuntimeVisualStates,
                    embedded: true,
                    sheetMetricsListenable: metricsListenable,
                    scrollController: scrollController,
                    sheetAtMaxExtent: metrics.atMaxExtent,
                    sheetCanFillScreen: metrics.canFillScreen,
                    sheetExtent: metrics.progress,
                    collapsedSheetExtent: 0,
                    expandedHeaderExtent: 1,
                    sheetCornerRadius: proxyPanelScreenCornerRadius,
                    collapseOnAnyDownwardDrag:
                        metrics.collapseOnAnyDownwardDrag,
                    onInteractionStart: gestures.onInteractionStart,
                    onHeaderDragUpdate: gestures.onDragUpdate,
                    onHeaderDragEnd: gestures.onDragEnd,
                    onHeaderTap: gestures.onHeaderTap,
                  );
                },
          ),
        );
      },
    );
  }
}

class _DeepLinkImportCopy {
  const _DeepLinkImportCopy({
    required this.title,
    required this.message,
    required this.nameLabel,
    required this.importAction,
    required this.importedTextBuilder,
  });

  final String title;
  final String message;
  final String nameLabel;
  final String importAction;
  final String Function(String name) importedTextBuilder;

  String imported(String name) {
    return importedTextBuilder(name);
  }
}

class _ResolvedExternalIpInfo {
  const _ResolvedExternalIpInfo({required this.ip, this.countryCode});

  final String ip;
  final String? countryCode;

  static _ResolvedExternalIpInfo? fromResponse(
    Map<String, dynamic> response, {
    required String Function(String? value) normalizeCountryCode,
  }) {
    final ip =
        (response['ip']?.toString() ?? response['query']?.toString() ?? '')
            .trim();
    if (ip.isEmpty) {
      return null;
    }
    final normalizedCountry = normalizeCountryCode(
      response['countryCode']?.toString() ??
          response['country_code']?.toString() ??
          response['cc']?.toString(),
    );
    return _ResolvedExternalIpInfo(
      ip: ip,
      countryCode: normalizedCountry.isEmpty ? null : normalizedCountry,
    );
  }
}

class _LocationLookupSlot {
  _LocationLookupSlot(this._onRelease);

  final VoidCallback _onRelease;
  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _onRelease();
  }
}

class _LocalizedSubscriptionError implements Exception {
  const _LocalizedSubscriptionError(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DeepLinkImportPreview {
  const _DeepLinkImportPreview({
    required this.sourceUrl,
    required this.resolvedUrl,
    required this.requestInfo,
  });

  final String sourceUrl;
  final String resolvedUrl;
  final SubscriptionInfo? requestInfo;

  bool get isHapp =>
      requestInfo?.happCryptoLink != null ||
      requestInfo?.requireHwid == true ||
      requestInfo?.customUserAgent?.trim().isNotEmpty == true;
}

class _DeepLinkImportSheet extends StatelessWidget {
  const _DeepLinkImportSheet({
    required this.request,
    required this.preview,
    required this.copy,
    required this.l10n,
  });

  final DeepLinkImportRequest request;
  final _DeepLinkImportPreview preview;
  final _DeepLinkImportCopy copy;
  final AppLocalizations l10n;

  String _summarizeSourceUrl(String value) {
    if (value.length <= 72) {
      return value;
    }
    return '${value.substring(0, 72)}...';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = request.name;
    final isHapp = preview.isHapp;
    final happInfo = preview.requestInfo;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(copy.title, style: theme.textTheme.titleLarge),
                      const Gap(12),
                      Text(copy.message, style: theme.textTheme.bodyLarge),
                      if (isHapp) ...[
                        const Gap(12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: .10,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            l10n.deepLinkImportHappBadge,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const Gap(16),
                      SizedBox(
                        width: double.infinity,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (name != null && name.isNotEmpty) ...[
                                  Text(
                                    copy.nameLabel,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const Gap(4),
                                  Text(name, style: theme.textTheme.titleSmall),
                                  const Gap(12),
                                ],
                                if (isHapp) ...[
                                  Text(
                                    l10n.deepLinkImportResolvedUrlLabel,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const Gap(4),
                                  SelectableText(
                                    preview.resolvedUrl,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const Gap(16),
                                  Text(
                                    l10n.deepLinkImportSourceLabel,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const Gap(4),
                                  Text(
                                    _summarizeSourceUrl(preview.sourceUrl),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ] else ...[
                                  Text(
                                    l10n.subscriptionUrl,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const Gap(4),
                                  SelectableText(
                                    preview.sourceUrl,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isHapp) ...[
                        const Gap(12),
                        SizedBox(
                          width: double.infinity,
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                l10n.deepLinkImportHappNotice,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        ),
                        const Gap(12),
                        SizedBox(
                          width: double.infinity,
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.deepLinkImportHwidLabel,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const Gap(4),
                                  Text(
                                    l10n.deepLinkImportHwidValue,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const Gap(12),
                                  Text(
                                    l10n.deepLinkImportUserAgentLabel,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const Gap(4),
                                  SelectableText(
                                    happInfo?.customUserAgent ??
                                        happLatestUserAgent,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Gap(16),
              if (isHapp)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_DeepLinkImportDecision.sendHwid),
                      child: Text(l10n.deepLinkImportHappSendHwidAction),
                    ),
                    const Gap(8),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_DeepLinkImportDecision.importWithoutHwid),
                      child: Text(l10n.deepLinkImportHappWithoutHwidAction),
                    ),
                    const Gap(8),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(_DeepLinkImportDecision.import),
                        child: Text(copy.importAction),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DeepLinkImportDecision { import, sendHwid, importWithoutHwid }
