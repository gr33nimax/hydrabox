import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/app/app_background_tasks.dart';
import 'package:meow_client/app/deep_link_import.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/data/adblock/ad_block_rule_set_service.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/data/routing/russia_route_data_service.dart';
import 'package:meow_client/data/subscription/happ_crypto_link.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/data/update/app_update_service.dart';
import 'package:meow_client/features/home/home_page.dart';
import 'package:meow_client/features/home/traffic_dashboard_page.dart';
import 'package:meow_client/features/proxies/proxies_page.dart';
import 'package:meow_client/features/proxies/proxy_panel_shell.dart';
import 'package:meow_client/features/settings/settings_about_page.dart';
import 'package:meow_client/features/settings/settings_dns_page.dart';
import 'package:meow_client/features/settings/settings_experimental_page.dart';
import 'package:meow_client/features/settings/settings_general_page.dart';
import 'package:meow_client/features/settings/settings_inbound_page.dart';
import 'package:meow_client/features/settings/settings_logs_page.dart';
import 'package:meow_client/features/settings/settings_page.dart';
import 'package:meow_client/features/settings/settings_routing_page.dart';
import 'package:meow_client/features/settings/settings_subscriptions_page.dart';
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
  starting,
  connected,
  stopping,
  recovering,
  failed,
}

class _MeowClientState extends State<MeowClient> with WidgetsBindingObserver {
  static const _clientVersionLabel = '0.1.1';
  static final RegExp _quickTileCountryCodePattern = RegExp(r'^[A-Z]{2}$');
  static const _lowestProxyTag = lowestProxyTag;
  static const _urlTestStatusUnavailable = 'unavailable';
  static const _derivedCacheBuildDebounce = Duration(milliseconds: 160);
  static const _coolUrlTestIntervalSeconds = 900;
  static const _coolUrlTestConcurrency = 4;
  static const _coolUrlTestUnavailableCheckIntervalSeconds = 30;
  static const _coolLocationLookupLimit = 0;
  static const _coolLocationLookupConcurrency = 2;
  static const _coolNetworkHeartbeatIntervalSeconds = 180;
  static const _subscriptionOperationSoftWarningDelay = Duration(seconds: 15);
  static const _subscriptionOperationTimeout = Duration(seconds: 30);
  static const _androidImageCacheMaximumBytes = 48 * 1024 * 1024;
  static const _androidImageCacheMaximumEntries = 80;
  static const _balancedUrlTestIntervalSeconds = 300;
  static const _balancedUrlTestConcurrency = 8;
  static const _balancedUrlTestUnavailableCheckIntervalSeconds = 15;
  static const _balancedLocationLookupLimit = 8;
  static const _balancedLocationLookupConcurrency = 4;
  static const _balancedNetworkHeartbeatIntervalSeconds = 60;
  static const _performanceUrlTestIntervalSeconds = 180;
  static const _performanceUrlTestConcurrency = 30;
  static const _performanceUrlTestUnavailableCheckIntervalSeconds = 5;
  static const _performanceLocationLookupLimit = 12;
  static const _performanceLocationLookupConcurrency = 16;
  static const _performanceNetworkHeartbeatIntervalSeconds = 30;
  static const _balancedTrafficUiUpdateInterval = Duration(seconds: 1);
  static const _subscriptionAutoRefreshMinDelay = Duration(seconds: 30);
  static const _subscriptionAutoRefreshMaxDelay = Duration(hours: 6);
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late ThemeData _lightTheme;
  late ThemeData _darkTheme;
  late ThemeData _amoledTheme;
  StreamSubscription<DeepLinkImportRequest>? _deepLinkImportSubscription;
  AppSettingsStore? _store;
  Timer? _subscriptionAutoRefreshTimer;
  Timer? _urlTestFallbackTimer;
  Timer? _invalidOutboundRetryTimer;
  Timer? _activeOutboundIpRefreshTimer;
  Timer? _locationLookupTimer;
  Timer? _derivedCacheBuildTimer;
  Timer? _trafficUiUpdateTimer;
  Timer? _resumeForegroundSyncTimer;
  Timer? _networkReconnectWatchdogTimer;
  Timer? _postConnectUrlTestTimer;
  StreamSubscription<Map<String, dynamic>>? _singboxEventsSubscription;
  bool _autoRefreshInFlight = false;
  bool _ownsStore = false;
  bool _ready = false;
  bool _onboardingCompleted = false;
  bool _connected = false;
  bool _runtimeErrorDialogVisible = false;
  bool _noValidOutboundsDialogVisible = false;
  bool _trafficAvailable = false;
  bool _urlTestInFlight = false;
  bool _urlTestMethodInFlight = false;
  bool _activeProfileRefreshInFlight = false;
  bool _allProfilesRefreshInFlight = false;
  bool _singleOutboundPingRefreshScheduled = false;
  bool _starting = false;
  bool _runtimeTransitionInProgress = false;
  bool _invalidOutboundRetryScheduled = false;
  bool _deepLinkImportInFlight = false;
  bool _locationLookupInFlight = false;
  bool _proxyPanelInteractionActive = false;
  bool _retryRuntimeOnResume = false;
  String _activeProfileId = '';
  String _selectedProxyTag = '';
  String? _lastRuntimeError;
  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.system;
  AppThemePreference _themePreference = AppThemePreference.system;
  String _accentColorHex = 'default';
  AppPerformanceMode _performanceMode = AppPerformanceMode.cool;
  bool _hapticEnabled = true;
  bool _hideServerIp = false;
  bool _progressiveBlurEnabled = false;
  bool _vpnInboundEnabled = true;
  int _vpnMtu = 1500;
  bool _vpnStrictRoute = true;
  TunImplementationPreference _vpnTunImplementation =
      TunImplementationPreference.mixed;
  bool _proxyInboundEnabled = false;
  bool _proxyAllowLan = false;
  String _proxyMixedListen = '127.0.0.1';
  int _proxyMixedPort = 1080;
  String _dnsDirectPreset = 'cloudflare';
  String _dnsDirectResolver = 'udp://1.1.1.1';
  String _dnsProxyPreset = 'cloudflare';
  String _dnsProxyResolver = 'https://dns.cloudflare.com/dns-query';
  bool _dnsPreferIpv6 = false;
  String _urlTestUrl = 'https://www.gstatic.com/generate_204';
  int _urlTestIntervalSeconds = _coolUrlTestIntervalSeconds;
  int _urlTestTimeoutSeconds = 15;
  int _urlTestConcurrency = _coolUrlTestConcurrency;
  int _urlTestUnavailableCheckIntervalSeconds =
      _coolUrlTestUnavailableCheckIntervalSeconds;
  int _locationLookupLimit = _coolLocationLookupLimit;
  int _locationLookupTimeoutSeconds = 6;
  int _locationLookupConcurrency = _coolLocationLookupConcurrency;
  int _locationLookupActiveRequests = 0;
  int _locationLookupGeneration = 0;
  bool _locationLookupRefreshRequested = false;
  String _lastLocationLookupSignature = '';
  final Queue<Completer<bool>> _locationLookupWaiters =
      Queue<Completer<bool>>();
  bool _blockLeaks = false;
  bool _adBlockEnabled = false;
  AdBlockRuleSetStatus _adBlockStatus =
      const AdBlockRuleSetStatus.unavailable();
  bool _useRussiaRouteData = false;
  RussiaRouteDataStatus _russiaRouteDataStatus =
      const RussiaRouteDataStatus.unavailable();
  bool _bypassLocalNetwork = true;
  SplitRoutingMode _splitRoutingMode = SplitRoutingMode.disabled;
  List<String> _splitRoutingPackages = const <String>[];
  List<Map<String, dynamic>> _installedAppsCache =
      const <Map<String, dynamic>>[];
  Future<List<Map<String, dynamic>>>? _installedAppsWarmupFuture;
  String _singBoxLogLevel = 'warning';
  bool _experimentalTcpFastOpen = true;
  bool _experimentalTcpMultiPath = false;
  bool _experimentalInterruptExistingConnections = true;
  bool _experimentalUrlTestStrictTolerance = true;
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
  int? _lowestLatency;
  int _runtimeConfigApplyGeneration = 0;
  int _derivedCacheBuildGeneration = 0;
  int _singboxConfigBuildGeneration = 0;
  int _activeSubscriptionHydrationGeneration = 0;
  Future<String?>? _singboxConfigPathFuture;
  bool _derivedCacheBuildInFlight = false;
  bool _derivedCacheBuildQueued = false;
  String? _runtimeLowestOutboundTag;
  final Map<String, String> _runtimeLowestSelections = <String, String>{};
  String? _lastEmptyAfterDropInvalidWarningSubscriptionId;
  final Set<String> _excludedRuntimeOutboundTags = <String>{};
  Map<int, String>? _lastStartedProxyOutboundTagsByIndex;
  Map<String, dynamic>? _lastStartedConfig;
  String? _pendingMutationExcludedTag;
  String? _pendingRuntimeSelectTag;
  String? _pendingRuntimeSelectPreviousTag;
  Timer? _pendingRuntimeSelectTimer;
  int _runtimeSelectGeneration = 0;
  final Map<String, int> _runtimeLatencies = <String, int>{};
  final Map<String, DateTime> _activeOutboundIpRefreshAttempts =
      <String, DateTime>{};
  final Set<String> _unavailableLatencyTags = <String>{};
  final Map<String, String> _latencyErrors = <String, String>{};
  final Map<String, String> _runtimeGroupSelections = <String, String>{};
  final Map<String, Map<String, int>> _pendingLatestPingSaves =
      <String, Map<String, int>>{};
  Timer? _latestPingSaveTimer;
  bool _latestPingSaveInFlight = false;
  bool _latestPingSaveRequested = false;
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
  int _activeOutboundIpRefreshToken = 0;
  int _postConnectUrlTestGeneration = 0;
  static const _activeOutboundIpRefreshMinInterval = Duration(minutes: 5);
  int _groupsEventsSinceLastDiagnosticsLog = 0;
  DateTime? _lastGroupsDiagnosticsLogAt;
  Set<String> _preloadedProxyFlagCodes = const <String>{};
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  AppConnectionPhase _connectionPhase = AppConnectionPhase.idle;

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

  bool get _russiaRouteProxiesEnabled =>
      _useRussiaRouteData && _russiaRouteDataStatus.available;

  bool get _markAllServersRussia =>
      _activeSubscription?.markAllServersRussia ?? false;

  String? _runtimeLowestOutboundTagFor(String lowestTag) {
    final selected = _runtimeLowestSelections[lowestTag];
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }
    if (lowestTag == _lowestProxyTag) {
      return _runtimeLowestOutboundTag;
    }
    return null;
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
        _pendingRuntimeSelectTag != null &&
        _pendingRuntimeSelectTag == proxy.tag;
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
    final next = <String, ProxyRuntimeVisualState>{
      for (final proxy in _activeProxiesCache)
        proxy.tag: _runtimeVisualStateFor(proxy),
      for (final children in _activeGroupChildrenByTagCache.values)
        for (final proxy in children) proxy.tag: _runtimeVisualStateFor(proxy),
    };
    final displayProxy = _displayProxyCache;
    if (displayProxy != null) {
      next[displayProxy.tag] = _runtimeVisualStateFor(displayProxy);
    }
    _proxyRuntimeVisualStates.replaceAll(next);
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
    final runtimeLatency = _runtimeLatencies[proxy.tag];
    final latencyUnavailable = _unavailableLatencyTags.contains(proxy.tag);
    final latencyError = _latencyErrors[proxy.tag];
    final parentGroupTag = proxy.parentGroupTag;
    final highlightedByGroupUrlTest =
        parentGroupTag != null &&
        _runtimeGroupSelections[parentGroupTag] == proxy.tag;
    final highlightedByLowest =
        isLowestProxyTag(_selectedProxyTag) &&
        _activeRuntimeLowestOutboundTag() == proxy.tag;
    final highlightedByMixed = mixedOutboundTags.contains(proxy.tag);
    return proxy.copyWith(
      latency: runtimeLatency,
      clearLatency: runtimeLatency == null && latencyUnavailable,
      latencyFresh: runtimeLatency != null || proxy.latencyFresh,
      latencyChecking: _urlTestInFlight,
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
    WidgetsBinding.instance.addObserver(this);
    _configureImageCacheForAndroid();
    _refreshThemeCache();
    _startDeepLinkHandling();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscriptionAutoRefreshTimer?.cancel();
    _urlTestFallbackTimer?.cancel();
    _invalidOutboundRetryTimer?.cancel();
    _activeOutboundIpRefreshTimer?.cancel();
    _latestPingSaveTimer?.cancel();
    _locationLookupTimer?.cancel();
    _resumeForegroundSyncTimer?.cancel();
    _networkReconnectWatchdogTimer?.cancel();
    _postConnectUrlTestTimer?.cancel();
    _pendingRuntimeSelectTimer?.cancel();
    _locationLookupRefreshRequested = false;
    for (final waiter in _locationLookupWaiters) {
      if (!waiter.isCompleted) {
        waiter.complete(false);
      }
    }
    _locationLookupWaiters.clear();
    _derivedCacheBuildTimer?.cancel();
    _trafficUiUpdateTimer?.cancel();
    _singboxEventsSubscription?.cancel();
    _deepLinkImportSubscription?.cancel();
    final store = _store;
    if (_ownsStore && store != null) {
      unawaited(store.close());
    }
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

    cache.clear();
    cache.clearLiveImages();
    _configureImageCacheForAndroid();

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
          'trafficSamplesBefore=$samplesBefore',
    );
  }

  void _queueLatestPingSave(String subscriptionId, Map<String, int?> delays) {
    if (subscriptionId.isEmpty || delays.isEmpty) {
      return;
    }
    final pending = _pendingLatestPingSaves.putIfAbsent(
      subscriptionId,
      () => <String, int>{},
    );
    var changed = false;
    for (final entry in delays.entries) {
      final tag = entry.key.trim();
      final delay = entry.value;
      if (tag.isEmpty || delay == null || delay <= 0) {
        continue;
      }
      if (pending[tag] == delay) {
        continue;
      }
      pending[tag] = delay;
      changed = true;
    }
    if (!changed) {
      return;
    }
    _latestPingSaveTimer?.cancel();
    _latestPingSaveTimer = Timer(
      const Duration(milliseconds: 900),
      _flushLatestPingSaves,
    );
  }

  void _flushLatestPingSaves() {
    _latestPingSaveTimer?.cancel();
    _latestPingSaveTimer = null;
    if (_latestPingSaveInFlight) {
      _latestPingSaveRequested = true;
      return;
    }
    if (_pendingLatestPingSaves.isEmpty) {
      return;
    }
    final batches = <String, Map<String, int>>{
      for (final entry in _pendingLatestPingSaves.entries)
        entry.key: Map<String, int>.from(entry.value),
    };
    _pendingLatestPingSaves.clear();
    _latestPingSaveInFlight = true;
    unawaited(() async {
      try {
        for (final entry in batches.entries) {
          await SubscriptionStore.saveOutboundRuntimeInfoInBackground(
            entry.key,
            latestPings: entry.value,
          );
        }
      } catch (error, stackTrace) {
        AppLogStore.warning(
          'subscription',
          'Failed to persist URLTest latency: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      } finally {
        _latestPingSaveInFlight = false;
        if (_latestPingSaveRequested || _pendingLatestPingSaves.isNotEmpty) {
          _latestPingSaveRequested = false;
          _flushLatestPingSaves();
        }
      }
    }());
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
    _pendingDeepLinkImport = request;
    if (!_ready || !_onboardingCompleted || _deepLinkImportInFlight) {
      return;
    }
    unawaited(_drainPendingDeepLinkImports());
  }

  Future<void> _drainPendingDeepLinkImports() async {
    if (_deepLinkImportInFlight) {
      return;
    }

    while (mounted && _ready && _onboardingCompleted) {
      final request = _pendingDeepLinkImport;
      if (request == null) {
        return;
      }

      final context = _navigatorKey.currentContext;
      if (context == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _ready && _onboardingCompleted) {
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
      final confirmed = await _showDeepLinkImportSheet(
        context,
        request,
        preview,
      );
      if (confirmed != true) {
        return;
      }
      if (!context.mounted) {
        return;
      }

      final createdResult = await _runSubscriptionOperationWithWarning(
        SubscriptionStore.addFromUrl(
          preview.resolvedUrl,
          customName: request.name,
          requestInfo: preview.requestInfo,
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

  Future<bool?> _showDeepLinkImportSheet(
    BuildContext context,
    DeepLinkImportRequest request,
    _DeepLinkImportPreview preview,
  ) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<bool>(
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

  Future<void> _refreshAllSubscriptions() async {
    if (_allProfilesRefreshInFlight || _activeProfileRefreshInFlight) {
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final refreshable = _subscriptions
        .where(
          (subscription) =>
              !SubscriptionStore.isLocalFileImportUrl(subscription.url),
        )
        .toList(growable: false);
    if (refreshable.isEmpty) {
      _showAppSnackBar(l10n.refreshActiveSubscriptionUnavailable);
      return;
    }

    _haptic();
    final activeBefore = _activeSubscription;
    final activeBeforeFingerprint = activeBefore == null
        ? null
        : _subscriptionRuntimeFingerprint(activeBefore);
    var refreshed = 0;
    var failed = 0;
    var activeRuntimeChanged = false;
    String? activePreferredTag;
    setState(() {
      _allProfilesRefreshInFlight = true;
    });
    try {
      for (final subscription in refreshable) {
        try {
          final updated = await _runSubscriptionOperationWithWarning(
            SubscriptionStore.refresh(
              subscription.id,
              operationTimeout: _subscriptionOperationTimeout,
            ),
            slowMessage: l10n.subscriptionOperationSlowWarning,
            timeoutMessage: l10n.subscriptionOperationTimeout,
          );
          refreshed++;
          if (updated.id == _activeProfileId &&
              activeBeforeFingerprint != null) {
            activeRuntimeChanged =
                activeBeforeFingerprint !=
                _subscriptionRuntimeFingerprint(updated);
            activePreferredTag = _validSelectedProxyTagForSubscription(
              updated,
              _selectedProxyTag,
            );
          }
        } catch (error) {
          failed++;
          final displayError = _userFacingSubscriptionError(error, l10n);
          AppLogStore.warning(
            'subscription',
            'Refresh all skipped subscription=${subscription.id}: '
                '$displayError',
          );
        }
      }
      await _reloadSubscriptions(
        preferredSubscriptionId: _activeProfileId,
        preferredProxyTag: activePreferredTag,
        resetRuntimeState: activeRuntimeChanged,
        restartRuntimeOnApply: _connected && activeRuntimeChanged,
        urlTestAfterApply: _connected && activeRuntimeChanged,
      );
      if (!mounted) {
        return;
      }
      _showAppSnackBar(l10n.subscriptionsRefreshAllComplete(refreshed, failed));
    } finally {
      if (mounted) {
        setState(() {
          _allProfilesRefreshInFlight = false;
        });
      }
    }
  }

  String _validSelectedProxyTagForSubscription(
    Subscription subscription,
    String preferredTag,
  ) {
    final normalized = preferredTag.trim();
    final liveOutbounds = subscription.outbounds
        .where((outbound) => !outbound.info.deleted)
        .toList(growable: false);
    if (liveOutbounds.isEmpty) {
      return '';
    }
    if (normalized.isEmpty) {
      return liveOutbounds.length == 1
          ? liveOutbounds.first.tag
          : lowestProxyTag;
    }
    if (isLowestProxyTag(normalized) || isMixedProxyTag(normalized)) {
      return normalized;
    }
    for (final outbound in liveOutbounds) {
      if (outbound.tag == normalized) {
        return normalized;
      }
    }
    return liveOutbounds.length == 1 ? liveOutbounds.first.tag : lowestProxyTag;
  }

  String _subscriptionRuntimeFingerprint(Subscription subscription) {
    return jsonEncode(
      _stableRuntimeFingerprintValue({
        'selected': subscription.selectedProxyTag,
        'outbounds': [
          for (final outbound in subscription.outbounds)
            if (!outbound.info.deleted)
              {'tag': outbound.tag, 'config': outbound.config},
        ],
        'groups': [for (final group in subscription.groups) group.toMap()],
      }),
    );
  }

  Object? _stableRuntimeFingerprintValue(Object? value) {
    if (value is Map) {
      final result = <String, Object?>{};
      final entries =
          value.entries
              .map((entry) => MapEntry(entry.key.toString(), entry.value))
              .toList(growable: false)
            ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in entries) {
        result[entry.key] = _stableRuntimeFingerprintValue(entry.value);
      }
      return result;
    }
    if (value is Iterable) {
      return value.map(_stableRuntimeFingerprintValue).toList(growable: false);
    }
    return value;
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
      debugPrint('Failed to bootstrap app, using defaults: $error');
      debugPrintStack(stackTrace: stackTrace);
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
        urlTestIntervalSeconds: _coolUrlTestIntervalSeconds,
        urlTestTimeoutSeconds: 15,
        urlTestConcurrency: _coolUrlTestConcurrency,
        urlTestUnavailableCheckIntervalSeconds:
            _coolUrlTestUnavailableCheckIntervalSeconds,
        locationLookupLimit: _coolLocationLookupLimit,
        locationLookupTimeoutSeconds: 6,
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
        ? const _ResolvedSubscriptions(
            subscriptions: <Subscription>[],
            normalized: _NormalizedSelection(
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
      _ready = true;
      _onboardingCompleted = state.onboardingCompleted;
      _subscriptions = subscriptions;
      _activeProfileId = normalized.activeSubscriptionId;
      _selectedProxyTag = normalized.selectedProxyTag;
      _locale = state.localeCode == 'system' ? null : Locale(state.localeCode);
      _themePreference = state.themePreference;
      _themeMode = switch (state.themePreference) {
        AppThemePreference.dark => ThemeMode.dark,
        AppThemePreference.amoled => ThemeMode.dark,
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
      };
      _accentColorHex = _normalizeAccentColorHex(state.accentColorHex);
      _performanceMode = state.performanceMode;
      _hapticEnabled = state.hapticEnabled;
      _hideServerIp = state.hideServerIp;
      _progressiveBlurEnabled = progressiveBlurEnabled;
      _vpnInboundEnabled = state.vpnInboundEnabled;
      _vpnMtu = state.vpnMtu;
      _vpnStrictRoute = state.vpnStrictRoute;
      _vpnTunImplementation = state.vpnTunImplementation;
      _proxyInboundEnabled = state.proxyInboundEnabled;
      _proxyAllowLan = state.proxyAllowLan;
      _proxyMixedListen = state.proxyMixedListen;
      _proxyMixedPort = state.proxyMixedPort;
      _dnsDirectPreset = state.dnsDirectPreset;
      _dnsDirectResolver = state.dnsDirectResolver;
      _dnsProxyPreset = state.dnsProxyPreset;
      _dnsProxyResolver = state.dnsProxyResolver;
      _dnsPreferIpv6 = state.dnsPreferIpv6;
      _urlTestUrl = state.urlTestUrl;
      _urlTestIntervalSeconds = state.urlTestIntervalSeconds;
      _urlTestTimeoutSeconds = state.urlTestTimeoutSeconds;
      _urlTestConcurrency = state.urlTestConcurrency;
      _urlTestUnavailableCheckIntervalSeconds =
          state.urlTestUnavailableCheckIntervalSeconds;
      _locationLookupLimit = state.locationLookupLimit.clamp(0, 50).toInt();
      _locationLookupTimeoutSeconds = state.locationLookupTimeoutSeconds
          .clamp(2, 30)
          .toInt();
      _locationLookupConcurrency = state.locationLookupConcurrency
          .clamp(1, 60)
          .toInt();
      _applyPerformanceModePreset(_performanceMode);
      _blockLeaks = state.blockLeaks;
      _adBlockEnabled = state.adBlockEnabled;
      _adBlockStatus = adBlockStatus;
      _useRussiaRouteData = state.useRussiaRouteData;
      _russiaRouteDataStatus = russiaRouteDataStatus;
      _bypassLocalNetwork = state.bypassLocalNetwork;
      _splitRoutingMode = state.splitRoutingMode;
      _splitRoutingPackages = List<String>.from(state.splitRoutingPackages);
      _singBoxLogLevel = state.singBoxLogLevel;
      _experimentalTcpFastOpen = state.experimentalTcpFastOpen;
      _experimentalTcpMultiPath = state.experimentalTcpMultiPath;
      _experimentalInterruptExistingConnections =
          state.experimentalInterruptExistingConnections;
      _experimentalUrlTestStrictTolerance =
          state.experimentalUrlTestStrictTolerance;
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
        unawaited(
          AppUpdateService.instance.checkForUpdates(
            currentVersion: _clientVersionLabel,
          ),
        );
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

    if (normalized.activeSubscriptionId != state.activeProfileId ||
        normalized.selectedProxyTag != state.selectedProxyTag) {
      _saveStateSoon();
    }
  }

  Future<void> _persistState() async {
    final store = _store;
    if (store == null) return;
    await store.saveState(
      AppSettingsState(
        onboardingCompleted: _onboardingCompleted,
        activeProfileId: _activeProfileId,
        selectedProxyTag: _selectedProxyTag,
        localeCode: _locale?.languageCode ?? 'system',
        themePreference: _themePreference,
        accentColorHex: _accentColorHex,
        hapticEnabled: _hapticEnabled,
        hideServerIp: _hideServerIp,
        progressiveBlurEnabled: _progressiveBlurEnabled,
        progressiveBlurConfigured: true,
        performanceMode: _performanceMode,
        vpnInboundEnabled: _vpnInboundEnabled,
        vpnMtu: _vpnMtu,
        vpnStrictRoute: _vpnStrictRoute,
        vpnTunImplementation: _vpnTunImplementation,
        proxyInboundEnabled: _proxyInboundEnabled,
        proxyAllowLan: _proxyAllowLan,
        proxyMixedListen: _proxyMixedListen,
        proxyMixedPort: _proxyMixedPort,
        dnsDirectPreset: _dnsDirectPreset,
        dnsDirectResolver: _dnsDirectResolver,
        dnsProxyPreset: _dnsProxyPreset,
        dnsProxyResolver: _dnsProxyResolver,
        dnsPreferIpv6: _dnsPreferIpv6,
        urlTestUrl: _urlTestUrl,
        urlTestIntervalSeconds: _urlTestIntervalSeconds,
        urlTestTimeoutSeconds: _urlTestTimeoutSeconds,
        urlTestConcurrency: _urlTestConcurrency,
        urlTestUnavailableCheckIntervalSeconds:
            _urlTestUnavailableCheckIntervalSeconds,
        locationLookupLimit: _locationLookupLimit,
        locationLookupTimeoutSeconds: _locationLookupTimeoutSeconds,
        locationLookupConcurrency: _locationLookupConcurrency,
        blockLeaks: _blockLeaks,
        adBlockEnabled: _adBlockEnabled,
        useRussiaRouteData: _useRussiaRouteData,
        bypassLocalNetwork: _bypassLocalNetwork,
        splitRoutingMode: _splitRoutingMode,
        splitRoutingPackages: _splitRoutingPackages,
        singBoxLogLevel: _singBoxLogLevel,
        experimentalTcpFastOpen: _experimentalTcpFastOpen,
        experimentalTcpMultiPath: _experimentalTcpMultiPath,
        experimentalInterruptExistingConnections:
            _experimentalInterruptExistingConnections,
        experimentalUrlTestStrictTolerance: _experimentalUrlTestStrictTolerance,
      ),
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

  bool get _coolMode => _performanceMode == AppPerformanceMode.cool;

  bool get _foregroundLifecycleActive =>
      _appLifecycleState == AppLifecycleState.resumed;

  bool get _balancedMode =>
      _performanceMode == AppPerformanceMode.cool ||
      _performanceMode == AppPerformanceMode.balanced;

  bool get _connectionBusy => switch (_connectionPhase) {
    AppConnectionPhase.preparing ||
    AppConnectionPhase.starting ||
    AppConnectionPhase.stopping ||
    AppConnectionPhase.recovering => true,
    _ => false,
  };

  bool get _effectiveProgressiveBlurEnabled => false;

  int get _networkHeartbeatIntervalSeconds => _balancedMode
      ? (_coolMode
            ? _coolNetworkHeartbeatIntervalSeconds
            : _balancedNetworkHeartbeatIntervalSeconds)
      : _performanceNetworkHeartbeatIntervalSeconds;

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
    _connected = phase == AppConnectionPhase.connected;
    if (_connected && !wasConnected) {
      _connectedSince = DateTime.now();
    } else if (!_connected &&
        (phase == AppConnectionPhase.idle ||
            phase == AppConnectionPhase.failed)) {
      _connectedSince = null;
    }
    _starting = switch (phase) {
      AppConnectionPhase.preparing ||
      AppConnectionPhase.starting ||
      AppConnectionPhase.recovering => true,
      _ => false,
    };
    _runtimeTransitionInProgress = switch (phase) {
      AppConnectionPhase.preparing ||
      AppConnectionPhase.starting ||
      AppConnectionPhase.stopping ||
      AppConnectionPhase.recovering => true,
      _ => false,
    };
    _invalidOutboundRetryScheduled = retryScheduled;
  }

  void _suspendForegroundWork() {
    _resumeForegroundSyncTimer?.cancel();
    _subscriptionAutoRefreshTimer?.cancel();
    _activeOutboundIpRefreshTimer?.cancel();
    _activeOutboundIpRefreshToken++;
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
    _urlTestFallbackTimer?.cancel();
    _urlTestFallbackTimer = null;
    if (_invalidOutboundRetryScheduled) {
      _retryRuntimeOnResume = true;
    }
    _invalidOutboundRetryTimer?.cancel();
    _invalidOutboundRetryTimer = null;
    _invalidOutboundRetryScheduled = false;
  }

  void _resumeForegroundWork() {
    if (!_ready) {
      return;
    }
    _resumeForegroundSyncTimer?.cancel();
    _startSubscriptionAutoRefresh();
    _resumeForegroundSyncTimer = Timer(const Duration(milliseconds: 350), () {
      _resumeForegroundSyncTimer = null;
      if (!mounted || !_foregroundLifecycleActive) {
        return;
      }
      unawaited(_syncRuntimeState());
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
      if (_retryRuntimeOnResume && !_connected) {
        _retryRuntimeOnResume = false;
        _scheduleInvalidOutboundRetry('resume lifecycle retry');
      } else {
        _retryRuntimeOnResume = false;
      }
    });
  }

  void _applyPerformanceModePreset(AppPerformanceMode mode) {
    switch (mode) {
      case AppPerformanceMode.cool:
        _urlTestIntervalSeconds = _coolUrlTestIntervalSeconds;
        _urlTestConcurrency = _coolUrlTestConcurrency;
        _urlTestUnavailableCheckIntervalSeconds =
            _coolUrlTestUnavailableCheckIntervalSeconds;
        _locationLookupLimit = _coolLocationLookupLimit;
        _locationLookupConcurrency = _coolLocationLookupConcurrency;
        break;
      case AppPerformanceMode.balanced:
        _urlTestIntervalSeconds = _balancedUrlTestIntervalSeconds;
        _urlTestConcurrency = _balancedUrlTestConcurrency;
        _urlTestUnavailableCheckIntervalSeconds =
            _balancedUrlTestUnavailableCheckIntervalSeconds;
        _locationLookupLimit = _balancedLocationLookupLimit;
        _locationLookupConcurrency = _balancedLocationLookupConcurrency;
        break;
      case AppPerformanceMode.performance:
        _urlTestIntervalSeconds = _performanceUrlTestIntervalSeconds;
        _urlTestConcurrency = _performanceUrlTestConcurrency;
        _urlTestUnavailableCheckIntervalSeconds =
            _performanceUrlTestUnavailableCheckIntervalSeconds;
        _locationLookupLimit = _performanceLocationLookupLimit;
        _locationLookupConcurrency = _performanceLocationLookupConcurrency;
        break;
    }
    _lastLocationLookupSignature = '';
  }

  void _setPerformanceMode(AppPerformanceMode mode) {
    if (_performanceMode == mode) {
      return;
    }
    setState(() {
      _performanceMode = mode;
      _applyPerformanceModePreset(mode);
    });
    _emitCurrentConfigLog('performance mode changed');
    _saveStateSoon();
    _scheduleBestOutboundLocationRefresh();
    unawaited(_syncRuntimePerformanceFlags());
  }

  Future<void> _syncRuntimePerformanceFlags() {
    return SingboxRuntime.instance.setRuntimeFlags(
      wakeLockEnabled: _balancedMode ? false : null,
      networkHeartbeatEnabled: true,
      networkHeartbeatIntervalSeconds: _networkHeartbeatIntervalSeconds,
      performanceMode: _performanceMode.name,
    );
  }

  void _startSubscriptionAutoRefresh() {
    _subscriptionAutoRefreshTimer?.cancel();
    if (!_foregroundLifecycleActive || !_ready || _subscriptions.isEmpty) {
      return;
    }
    final delay = _nextSubscriptionAutoRefreshDelay();
    if (delay == null) {
      return;
    }
    _subscriptionAutoRefreshTimer = Timer(delay, () {
      _subscriptionAutoRefreshTimer = null;
      unawaited(_runSubscriptionAutoRefresh());
    });
  }

  Duration? _nextSubscriptionAutoRefreshDelay() {
    final now = DateTime.now().millisecondsSinceEpoch;
    int? nextDueAt;
    for (final subscription in _subscriptions) {
      if (subscription.disableAutoUpdate ||
          subscription.autoRefreshMinutes <= 0) {
        continue;
      }
      final dueAt =
          subscription.lastUpdated +
          subscription.autoRefreshMinutes * Duration.millisecondsPerMinute;
      if (nextDueAt == null || dueAt < nextDueAt) {
        nextDueAt = dueAt;
      }
    }
    if (nextDueAt == null) {
      return null;
    }
    final delayMs = (nextDueAt - now)
        .clamp(
          _subscriptionAutoRefreshMinDelay.inMilliseconds,
          _subscriptionAutoRefreshMaxDelay.inMilliseconds,
        )
        .toInt();
    return Duration(milliseconds: delayMs);
  }

  Future<void> _runSubscriptionAutoRefresh() async {
    if (_autoRefreshInFlight) {
      return;
    }
    if (!_ready || _subscriptions.isEmpty || !_foregroundLifecycleActive) {
      _startSubscriptionAutoRefresh();
      return;
    }
    final dueSubscriptions = _subscriptions
        .where((subscription) => subscription.needsRefresh)
        .toList(growable: false);
    if (dueSubscriptions.isEmpty) {
      _startSubscriptionAutoRefresh();
      return;
    }
    AppLogStore.info(
      'subscription refresh',
      'auto-refresh begin due=${dueSubscriptions.length} '
          'ids=${dueSubscriptions.map((s) => s.id).take(6).join(', ')}\n'
          '${_outboundDebugSnapshot(reason: 'before auto-refresh')}',
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
              if (updated.id == activeBefore?.id) {
                refreshedActiveSubscription = updated;
              }
            } catch (error) {
              AppLogStore.warning(
                'subscription refresh',
                'refresh failed id=${subscription.id} name=${subscription.name}: $error',
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
      AppLogStore.info(
        'subscription refresh',
        'auto-refresh done\n'
            '${_outboundDebugSnapshot(reason: 'after auto-refresh')}',
      );
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
    if (_connected) {
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
          setState(() {
            _setConnectionPhase(AppConnectionPhase.connected);
          });
          _showAppSnackBar(AppLocalizations.of(context).vpnStopFailed);
          return;
        }
      }
      setState(() {
        _setConnectionPhase(AppConnectionPhase.idle);
        _activeOutboundIpRefreshToken++;
        _activeOutboundIpRefreshTimer?.cancel();
        _activeOutboundIpRefreshAttempts.clear();
        _locationLookupGeneration++;
        _locationLookupTimer?.cancel();
        _locationLookupInFlight = false;
        _locationLookupRefreshRequested = false;
        _cancelQueuedLocationLookups();
        _excludedRuntimeOutboundTags.clear();
        _clearLastStartedBuildCache();
        _invalidOutboundRetryScheduled = false;
        _invalidOutboundRetryTimer?.cancel();
        _urlTestInFlight = false;
        _urlTestMethodInFlight = false;
        _urlTestFallbackTimer?.cancel();
        _lowestLatency = null;
        _runtimeLowestOutboundTag = null;
        _runtimeLowestSelections.clear();
        _runtimeLatencies.clear();
        _unavailableLatencyTags.clear();
        _latencyErrors.clear();
        _singleOutboundPingRefreshScheduled = false;
        _postConnectUrlTestGeneration++;
        _postConnectUrlTestTimer?.cancel();
        _applyRuntimeStateToDerivedCaches();
      });
      unawaited(_syncQuickSettingsTileLabel());
      return;
    }

    if (_starting || _invalidOutboundRetryScheduled) {
      return;
    }
    AppLogStore.info(
      'sing-box',
      'manual start requested source=$source\n'
          '${_outboundDebugSnapshot(reason: 'manual start')}',
    );

    setState(() {
      _setConnectionPhase(AppConnectionPhase.preparing);
    });

    final granted = await SingboxRuntime.instance.prepareVpn(
      requiresVpn: _vpnInboundEnabled,
    );
    if (!granted || !mounted) {
      setState(() {
        _setConnectionPhase(AppConnectionPhase.idle);
      });
      return;
    }

    final build = await _buildCurrentSingboxConfigInBackground(
      returnConfig: true,
    );
    if (build == null || !mounted) {
      if (mounted) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.idle);
        });
      }
      return;
    }
    if (!_applyStartupValidationResult(build, 'manual start')) {
      _discardPreparedConfigCandidate(build);
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
        : ++_runtimeSelectGeneration;
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
          if (!mounted || selectionGeneration != _runtimeSelectGeneration) {
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
          if (!mounted || selectionGeneration != _runtimeSelectGeneration) {
            return;
          }
          AppLogStore.error(
            'proxy',
            'Failed to select proxy "$tag" via command API: $error. '
                'Restarting runtime with selected tag.',
          );
          try {
            await _emitCurrentConfigLogAsync(
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

  void _triggerSelectedProxyUrlTest({bool showChecking = true}) {
    if (!_connected || _urlTestInFlight || _urlTestMethodInFlight) {
      return;
    }
    if (showChecking && mounted) {
      setState(() {
        _urlTestInFlight = true;
        _urlTestFallbackTimer?.cancel();
        _applyRuntimeStateToDerivedCaches();
      });
    }
    _urlTestMethodInFlight = true;
    unawaited(() async {
      try {
        _logLibboxCall(
          'urlTest',
          'reason=selected proxy quick check group=select',
        );
        await SingboxRuntime.instance.urlTest(groupTag: 'select');
        if (showChecking) {
          _urlTestFallbackTimer = Timer(const Duration(seconds: 15), () {
            if (!mounted) return;
            setState(() {
              _urlTestInFlight = false;
              _applyRuntimeStateToDerivedCaches();
            });
          });
        }
      } catch (error) {
        AppLogStore.warning(
          'proxy',
          'Failed to run selected proxy URLTest: $error',
        );
        if (showChecking && mounted) {
          setState(() {
            _urlTestInFlight = false;
            _applyRuntimeStateToDerivedCaches();
          });
        }
      } finally {
        _urlTestMethodInFlight = false;
      }
    }());
  }

  void _schedulePostConnectSelectedProxyUrlTest({
    required String reason,
    Duration delay = const Duration(milliseconds: 2500),
  }) {
    if (!_foregroundLifecycleActive || _selectedProxyTag.trim().isEmpty) {
      return;
    }
    final generation = ++_postConnectUrlTestGeneration;
    _postConnectUrlTestTimer?.cancel();
    _postConnectUrlTestTimer = Timer(delay, () {
      if (!mounted ||
          generation != _postConnectUrlTestGeneration ||
          !_connected ||
          !_foregroundLifecycleActive ||
          _runtimeTransitionInProgress ||
          _urlTestInFlight ||
          _urlTestMethodInFlight) {
        return;
      }
      AppLogStore.info(
        'proxy',
        'post-connect selected proxy URLTest reason=$reason '
            'selected=$_selectedProxyTag',
      );
      _triggerSelectedProxyUrlTest();
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
        _emitCurrentConfigLogAsync(
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
        _emitCurrentConfigLogAsync(
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
    setState(() {
      _locale = localeCode == 'system' ? null : Locale(localeCode);
    });
    _saveStateSoon();
  }

  void _setThemePreference(AppThemePreference preference) {
    setState(() {
      _themePreference = preference;
      _themeMode = switch (preference) {
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
        AppThemePreference.amoled => ThemeMode.dark,
        AppThemePreference.system => ThemeMode.system,
      };
    });
    _saveStateSoon();
  }

  void _setHapticEnabled(bool value) {
    setState(() {
      _hapticEnabled = value;
    });
    _saveStateSoon();
  }

  void _setHideServerIp(bool value) {
    setState(() {
      _hideServerIp = value;
    });
    _publishTrafficDashboardSnapshot();
    _saveStateSoon();
  }

  void _setAccentColor(String hex) {
    setState(() {
      _accentColorHex = _normalizeAccentColorHex(hex);
      _refreshThemeCache();
    });
    _saveStateSoon();
  }

  void _setVpnInboundEnabled(bool value) {
    setState(() {
      _vpnInboundEnabled = value;
    });
    _emitCurrentConfigLog('vpn inbound changed');
    _saveStateSoon();
  }

  void _setVpnMtu(int value) {
    setState(() {
      _vpnMtu = value;
    });
    _emitCurrentConfigLog('vpn mtu changed');
    _saveStateSoon();
  }

  void _setVpnStrictRoute(bool value) {
    setState(() {
      _vpnStrictRoute = value;
    });
    _emitCurrentConfigLog('vpn strict route changed');
    _saveStateSoon();
  }

  void _setVpnTunImplementation(TunImplementationPreference value) {
    setState(() {
      _vpnTunImplementation = value;
    });
    _emitCurrentConfigLog('vpn tun implementation changed');
    _saveStateSoon();
  }

  void _setProxyInboundEnabled(bool value) {
    setState(() {
      _proxyInboundEnabled = value;
    });
    _emitCurrentConfigLog('proxy inbound changed');
    _saveStateSoon();
  }

  void _setProxyAllowLan(bool value) {
    setState(() {
      _proxyAllowLan = value;
      _proxyMixedListen = value ? '0.0.0.0' : '127.0.0.1';
    });
    _emitCurrentConfigLog('proxy allow lan changed');
    _saveStateSoon();
  }

  void _setProxyMixedPort(int value) {
    setState(() {
      _proxyMixedPort = value;
    });
    _emitCurrentConfigLog('proxy port changed');
    _saveStateSoon();
  }

  void _setDnsDirectPreset(String value) {
    setState(() {
      _dnsDirectPreset = value;
    });
    _syncDnsPresetValue(isDirect: true);
    _emitCurrentConfigLog('dns direct preset changed');
    _saveStateSoon();
  }

  void _setDnsDirectResolver(String value) {
    setState(() {
      _dnsDirectResolver = value;
    });
    _emitCurrentConfigLog('dns direct resolver changed');
    _saveStateSoon();
  }

  void _setDnsProxyPreset(String value) {
    setState(() {
      _dnsProxyPreset = value;
    });
    _syncDnsPresetValue(isDirect: false);
    _emitCurrentConfigLog('dns proxy preset changed');
    _saveStateSoon();
  }

  void _setDnsProxyResolver(String value) {
    setState(() {
      _dnsProxyResolver = value;
    });
    _emitCurrentConfigLog('dns proxy resolver changed');
    _saveStateSoon();
  }

  void _setDnsPreferIpv6(bool value) {
    setState(() {
      _dnsPreferIpv6 = value;
    });
    _emitCurrentConfigLog('dns ip preference changed');
    _saveStateSoon();
  }

  void _setUrlTestUrl(String value) {
    setState(() {
      _urlTestUrl = value.trim().isEmpty
          ? 'https://www.gstatic.com/generate_204'
          : value.trim();
    });
    _emitCurrentConfigLog('urltest url changed');
    _saveStateSoon();
  }

  void _setUrlTestIntervalSeconds(int value) {
    setState(() {
      _urlTestIntervalSeconds = value <= 0
          ? (_balancedMode
                ? _balancedUrlTestIntervalSeconds
                : _performanceUrlTestIntervalSeconds)
          : value;
    });
    _emitCurrentConfigLog('urltest interval changed');
    _saveStateSoon();
  }

  void _setUrlTestTimeoutSeconds(int value) {
    setState(() {
      _urlTestTimeoutSeconds = value <= 0 ? 15 : value;
    });
    _emitCurrentConfigLog('urltest timeout changed');
    _saveStateSoon();
  }

  void _setUrlTestConcurrency(int value) {
    setState(() {
      _urlTestConcurrency = value <= 0
          ? (_balancedMode
                ? _balancedUrlTestConcurrency
                : _performanceUrlTestConcurrency)
          : value;
    });
    _emitCurrentConfigLog('urltest concurrency changed');
    _saveStateSoon();
  }

  void _setUrlTestUnavailableCheckIntervalSeconds(int value) {
    setState(() {
      _urlTestUnavailableCheckIntervalSeconds = value <= 0
          ? (_balancedMode
                ? _balancedUrlTestUnavailableCheckIntervalSeconds
                : _performanceUrlTestUnavailableCheckIntervalSeconds)
          : value;
    });
    _emitCurrentConfigLog('urltest unavailable check interval changed');
    _saveStateSoon();
  }

  void _setLocationLookupLimit(int value) {
    setState(() {
      _locationLookupLimit = value.clamp(0, 50).toInt();
      _lastLocationLookupSignature = '';
    });
    _saveStateSoon();
    _scheduleBestOutboundLocationRefresh();
  }

  void _setLocationLookupTimeoutSeconds(int value) {
    setState(() {
      _locationLookupTimeoutSeconds = value.clamp(2, 30).toInt();
      _lastLocationLookupSignature = '';
    });
    _saveStateSoon();
    _scheduleBestOutboundLocationRefresh();
  }

  void _setLocationLookupConcurrency(int value) {
    setState(() {
      _locationLookupConcurrency = value.clamp(1, 60).toInt();
      _lastLocationLookupSignature = '';
    });
    _pumpLocationLookupWaiters();
    _saveStateSoon();
    _scheduleBestOutboundLocationRefresh();
  }

  void _syncDnsPresetValue({required bool isDirect}) {
    const directPresets = {
      'device': 'device://network',
      'cloudflare': 'udp://1.1.1.1',
      'cloudflare_doh': 'https://dns.cloudflare.com/dns-query',
    };
    const proxyPresets = {
      'device': 'device://network',
      'cloudflare': 'udp://1.1.1.1',
      'cloudflare_doh': 'https://dns.cloudflare.com/dns-query',
    };
    final preset = isDirect ? _dnsDirectPreset : _dnsProxyPreset;
    if (preset == 'custom') {
      return;
    }
    final value = isDirect ? directPresets[preset] : proxyPresets[preset];
    if (value == null) {
      return;
    }
    if (isDirect) {
      _dnsDirectResolver = value;
    } else {
      _dnsProxyResolver = value;
    }
  }

  Color? get _seedColor {
    if (_accentColorHex == 'default') return _dynamicLightScheme?.primary;
    final parsed = int.tryParse(_accentColorHex, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }

  String _normalizeAccentColorHex(String hex) => switch (hex) {
    'dynamic-2' || 'dynamic-3' => 'default',
    _ => hex,
  };

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
    );
    final subscriptions = resolved.subscriptions;
    final normalized = resolved.normalized;

    if (!mounted) {
      return;
    }

    final nextActiveId = normalized.activeSubscriptionId;
    final activeChanged = nextActiveId != _activeProfileId;
    final shouldResetRuntimeState = activeChanged || resetRuntimeState;
    final previousSelectedTag = _selectedProxyTag;

    setState(() {
      _subscriptions = subscriptions;
      _activeProfileId = nextActiveId;
      _selectedProxyTag = normalized.selectedProxyTag;
      _lastEmptyAfterDropInvalidWarningSubscriptionId = null;
      if (shouldResetRuntimeState) {
        _runtimeLatencies.clear();
        _unavailableLatencyTags.clear();
        _latencyErrors.clear();
        _runtimeGroupSelections.clear();
        _lowestLatency = null;
        _runtimeLowestOutboundTag = null;
        _runtimeLowestSelections.clear();
        _urlTestInFlight = false;
        _urlTestFallbackTimer?.cancel();
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
        preserveRuntimeState: !shouldResetRuntimeState,
        applyRuntime: applyRuntime,
        restartRuntimeOnApply: restartRuntimeOnApply,
        urlTestAfterApply: urlTestAfterApply,
      );
    } else if (applyRuntime) {
      _emitCurrentConfigLog(
        'subscriptions reloaded',
        restartRuntime: restartRuntimeOnApply,
      );
    } else {
      unawaited(
        _logCurrentSingboxConfig('subscriptions reloaded (runtime skipped)'),
      );
    }
    if (activeChanged || previousSelectedTag != normalized.selectedProxyTag) {
      _saveStateSoon();
    }
  }

  _ResolvedSubscriptions _resolveSubscriptionMetadata({
    required String activeSubscriptionId,
    required String selectedProxyTag,
  }) {
    final metadataSubscriptions = SubscriptionStore.getAllMetadata();
    if (metadataSubscriptions.isEmpty) {
      return const _ResolvedSubscriptions(
        subscriptions: <Subscription>[],
        normalized: _NormalizedSelection(
          activeSubscriptionId: '',
          selectedProxyTag: '',
        ),
      );
    }

    var resolvedActiveSubscription = metadataSubscriptions.first;
    for (final subscription in metadataSubscriptions) {
      if (subscription.id == activeSubscriptionId) {
        resolvedActiveSubscription = subscription;
        break;
      }
    }
    final resolvedSelectedProxyTag =
        resolvedActiveSubscription.selectedProxyTag.isNotEmpty
        ? resolvedActiveSubscription.selectedProxyTag
        : selectedProxyTag;
    return _ResolvedSubscriptions(
      subscriptions: metadataSubscriptions,
      normalized: _NormalizedSelection(
        activeSubscriptionId: resolvedActiveSubscription.id,
        selectedProxyTag: resolvedSelectedProxyTag,
      ),
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
      setState(() {
        _subscriptions = resolved.subscriptions;
        _activeProfileId = normalized.activeSubscriptionId;
        _selectedProxyTag = normalized.selectedProxyTag;
        if (shouldResetRuntimeState) {
          _runtimeLatencies.clear();
          _unavailableLatencyTags.clear();
          _latencyErrors.clear();
          _runtimeGroupSelections.clear();
          _lowestLatency = null;
          _runtimeLowestOutboundTag = null;
          _runtimeLowestSelections.clear();
          _urlTestInFlight = false;
          _urlTestFallbackTimer?.cancel();
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
        await _emitCurrentConfigLogAsync(
          'subscriptions reloaded',
          restartRuntime: restartRuntimeOnApply,
        );
        if (urlTestAfterApply && mounted && _connected) {
          _triggerSelectedProxyUrlTest(showChecking: true);
        }
      } else {
        unawaited(
          _logCurrentSingboxConfig('subscriptions reloaded (runtime skipped)'),
        );
      }
      if (activeChanged || previousSelectedTag != normalized.selectedProxyTag) {
        _saveStateSoon();
      }
    }());
  }

  Future<_ResolvedSubscriptions> _resolveSubscriptions({
    required String activeSubscriptionId,
    required String selectedProxyTag,
    required bool preserveRuntimeState,
  }) async {
    final metadataSubscriptions = SubscriptionStore.getAllMetadata();
    if (metadataSubscriptions.isEmpty) {
      return const _ResolvedSubscriptions(
        subscriptions: <Subscription>[],
        normalized: _NormalizedSelection(
          activeSubscriptionId: '',
          selectedProxyTag: '',
        ),
      );
    }

    String hydratedSubscriptionId = activeSubscriptionId;
    if (!metadataSubscriptions.any(
      (subscription) => subscription.id == hydratedSubscriptionId,
    )) {
      hydratedSubscriptionId = metadataSubscriptions.first.id;
    }

    final activeMetadata = metadataSubscriptions.firstWhere(
      (subscription) => subscription.id == hydratedSubscriptionId,
    );
    final hydrated = await _hydrateActiveSubscriptionAndBuildProxyCache(
      activeMetadata,
      selectedProxyTag: selectedProxyTag,
      preserveRuntimeState: preserveRuntimeState,
    );
    final subscriptions = metadataSubscriptions
        .map(
          (subscription) => subscription.id == hydrated.subscription.id
              ? hydrated.subscription
              : subscription,
        )
        .toList(growable: false);

    return _ResolvedSubscriptions(
      subscriptions: subscriptions,
      normalized: hydrated.normalized,
      proxyCache: hydrated.proxyCache,
    );
  }

  Future<_HydratedActiveSubscription>
  _hydrateActiveSubscriptionAndBuildProxyCache(
    Subscription metadata, {
    required String selectedProxyTag,
    required bool preserveRuntimeState,
  }) {
    final metadataMap = metadata.toMetadataMap();
    final payloadJson = SubscriptionStore.payloadJsonFor(metadata.id);
    final lowestLatency = preserveRuntimeState ? _lowestLatency : null;
    final runtimeLowestOutboundTag = preserveRuntimeState
        ? _runtimeLowestOutboundTag
        : null;
    final runtimeLowestSelections = preserveRuntimeState
        ? Map<String, String>.from(_runtimeLowestSelections)
        : <String, String>{};
    final urlTestInFlight = preserveRuntimeState ? _urlTestInFlight : false;
    final runtimeLatencies = preserveRuntimeState
        ? Map<String, int>.from(_runtimeLatencies)
        : <String, int>{};
    final unavailableLatencyTags = preserveRuntimeState
        ? Set<String>.from(_unavailableLatencyTags)
        : <String>{};
    final latencyErrors = preserveRuntimeState
        ? Map<String, String>.from(_latencyErrors)
        : <String, String>{};
    final runtimeGroupSelections = preserveRuntimeState
        ? Map<String, String>.from(_runtimeGroupSelections)
        : <String, String>{};
    final russiaRouteProxiesEnabled = _russiaRouteProxiesEnabled;
    final markAllServersRussia = metadata.markAllServersRussia;

    return Isolate.run(() {
      final metadataSubscription = Subscription.fromMetadataMap(metadataMap);
      final subscription = payloadJson == null
          ? metadataSubscription
          : SubscriptionStore.hydratePayloadJson(
              metadataSubscription,
              payloadJson,
            );
      final normalized = _normalizeActiveSubscriptionSelection(
        subscription,
        selectedProxyTag: selectedProxyTag,
        russiaRouteProxiesEnabled: russiaRouteProxiesEnabled,
      );
      final proxyCache = buildProxyCache(
        ProxyCacheBuildInput(
          subscription: subscription,
          selectedProxyTag: normalized.selectedProxyTag,
          lowestLatency: lowestLatency,
          runtimeLowestOutboundTag: runtimeLowestOutboundTag,
          runtimeLowestSelections: runtimeLowestSelections,
          urlTestInFlight: urlTestInFlight,
          runtimeLatencies: runtimeLatencies,
          unavailableLatencyTags: unavailableLatencyTags,
          latencyErrors: latencyErrors,
          runtimeGroupSelections: runtimeGroupSelections,
          russiaRouteProxiesEnabled: russiaRouteProxiesEnabled,
          markAllServersRussia: markAllServersRussia,
        ),
      );
      return _HydratedActiveSubscription(
        subscription: subscription,
        normalized: normalized,
        proxyCache: proxyCache,
      );
    }, debugName: 'meow-active-subscription');
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
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    final selectedSubscriptionId = await navigator.push<String>(
      MaterialPageRoute<String>(
        allowSnapshotting: false,
        builder: (context) => SubscriptionsPage(
          activeSubscriptionId: _activeProfileId,
          openAddOnStart: openAddOnStart,
          hapticEnabled: _hapticEnabled,
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }

    if (selectedSubscriptionId != null &&
        selectedSubscriptionId.isNotEmpty &&
        selectedSubscriptionId != _activeProfileId) {
      _haptic();
    }

    await _reloadSubscriptions(
      preferredSubscriptionId: selectedSubscriptionId ?? _activeProfileId,
      preferredProxyTag: selectedSubscriptionId == null
          ? _selectedProxyTag
          : '',
    );
  }

  Future<void> _showSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    unawaited(_warmInstalledApps());
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
    final future = SingboxRuntime.instance
        .getInstalledApps()
        .then((items) {
          _installedAppsCache = items;
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
          onAccentColorChanged: _setAccentColor,
          onHapticChanged: _setHapticEnabled,
          onHideServerIpChanged: _setHideServerIp,
          onPerformanceModeChanged: _setPerformanceMode,
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
          onVpnInboundEnabledChanged: _setVpnInboundEnabled,
          onVpnMtuChanged: _setVpnMtu,
          onVpnStrictRouteChanged: _setVpnStrictRoute,
          onVpnTunImplementationChanged: _setVpnTunImplementation,
          onProxyInboundEnabledChanged: _setProxyInboundEnabled,
          onProxyAllowLanChanged: _setProxyAllowLan,
          onProxyMixedPortChanged: _setProxyMixedPort,
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
          onDirectPresetChanged: _setDnsDirectPreset,
          onDirectResolverChanged: _setDnsDirectResolver,
          onProxyPresetChanged: _setDnsProxyPreset,
          onProxyResolverChanged: _setDnsProxyResolver,
          onPreferIpv6Changed: _setDnsPreferIpv6,
        ),
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
    setState(() {
      _blockLeaks = value;
    });
    _emitCurrentConfigLog('block leaks changed');
    _saveStateSoon();
  }

  void _setAdBlockEnabled(bool value) {
    if (value == _adBlockEnabled) {
      return;
    }
    setState(() {
      _adBlockEnabled = value;
    });
    _emitCurrentConfigLog('adblock changed');
    _saveStateSoon();
  }

  Future<AdBlockRuleSetStatus> _downloadAdBlockRuleSet() async {
    final status = await AdBlockRuleSetService.instance.downloadLatest();
    if (!mounted) {
      return status;
    }
    setState(() {
      _adBlockStatus = status;
    });
    _emitCurrentConfigLog('adblock rule-set updated');
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
    _emitCurrentConfigLog('adblock rule-set deleted');
    _saveStateSoon();
    return status;
  }

  void _setRussiaRouteDataEnabled(bool value) {
    if (value == _useRussiaRouteData) {
      return;
    }
    setState(() {
      _useRussiaRouteData = value;
    });
    _emitCurrentConfigLog('russia route data changed');
    _saveStateSoon();
  }

  Future<RussiaRouteDataStatus> _installRussiaRouteData() async {
    final status = await RussiaRouteDataService.instance.ensureUpdated(
      force: true,
    );
    if (!mounted) {
      return status;
    }
    setState(() {
      _russiaRouteDataStatus = status;
    });
    _emitCurrentConfigLog('russia route data prepared');
    return status;
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
    _emitCurrentConfigLog('russia route data deleted');
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
        _emitCurrentConfigLog('russia route data updated');
      }
    } catch (error) {
      AppLogStore.warning('routes', 'russia route update check failed: $error');
    }
  }

  void _setBypassLocalNetwork(bool value) {
    setState(() {
      _bypassLocalNetwork = value;
    });
    _emitCurrentConfigLog('bypass local network changed');
    _saveStateSoon();
  }

  void _setSplitRoutingMode(SplitRoutingMode value) {
    if (value == _splitRoutingMode) {
      return;
    }
    setState(() {
      _splitRoutingMode = value;
    });
    _emitCurrentConfigLog('split routing mode changed');
    _saveStateSoon();
  }

  void _setSplitRoutingPackages(List<String> value) {
    final normalized = normalizeSplitRoutingPackages(value);
    if (_splitRoutingPackages.join('\n') == normalized.join('\n')) {
      return;
    }
    setState(() {
      _splitRoutingPackages = normalized;
    });
    _emitCurrentConfigLog('split routing packages changed');
    _saveStateSoon();
  }

  void _setSingBoxLogLevel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized == _singBoxLogLevel) {
      return;
    }
    setState(() {
      _singBoxLogLevel = normalized;
    });
    unawaited(_applySingBoxLogLevelChange());
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
    final status = await SingboxRuntime.instance.status();
    final running = status['running'] == true;
    if (running) {
      setState(() {
        _setConnectionPhase(AppConnectionPhase.starting);
      });
    }
    final build = await _buildCurrentSingboxConfigInBackground(
      prepareConfig: running,
      returnConfig: running,
    );
    if (build == null) {
      if (running && mounted) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.connected);
        });
      }
      return;
    }
    if (running &&
        !_applyStartupValidationResult(build, 'sing-box log level changed')) {
      _discardPreparedConfigCandidate(build);
      if (mounted) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.failed);
        });
      }
      _showNoValidOutboundsWarning();
      return;
    }
    _recordBuiltConfigLog('sing-box log level changed', build);
    if (!running) {
      return;
    }
    final generation = ++_runtimeConfigApplyGeneration;
    await _restartRuntimeWithConfig(
      build: build,
      useVpn: _vpnInboundEnabled,
      generation: generation,
    );
  }

  void _setExperimentalTcpFastOpen(bool value) {
    setState(() {
      _experimentalTcpFastOpen = value;
    });
    _emitCurrentConfigLog('experimental tcp fast open changed');
    _saveStateSoon();
  }

  void _setExperimentalTcpMultiPath(bool value) {
    setState(() {
      _experimentalTcpMultiPath = value;
    });
    _emitCurrentConfigLog('experimental tcp multipath changed');
    _saveStateSoon();
  }

  void _setExperimentalInterruptExistingConnections(bool value) {
    setState(() {
      _experimentalInterruptExistingConnections = value;
    });
    _emitCurrentConfigLog(
      'experimental interrupt existing connections changed',
    );
    _saveStateSoon();
  }

  void _setExperimentalUrlTestStrictTolerance(bool value) {
    setState(() {
      _experimentalUrlTestStrictTolerance = value;
    });
    _emitCurrentConfigLog('experimental urltest strict tolerance changed');
    _saveStateSoon();
  }

  Future<void> _showRoutingSettingsPage() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsRoutingPage(
          currentBlockLeaks: _blockLeaks,
          currentAdBlockEnabled: _adBlockEnabled,
          currentAdBlockStatus: _adBlockStatus,
          currentRussiaRouteDataEnabled: _useRussiaRouteData,
          currentRussiaRouteDataStatus: _russiaRouteDataStatus,
          currentBypassLocalNetwork: _bypassLocalNetwork,
          currentSplitRoutingMode: _splitRoutingMode,
          currentSplitRoutingPackages: _splitRoutingPackages,
          initialInstalledApps: _installedAppsCache,
          preloadInstalledApps: _warmInstalledApps,
          onBlockLeaksChanged: _setBlockLeaks,
          onAdBlockEnabledChanged: _setAdBlockEnabled,
          onDownloadAdBlockRuleSet: _downloadAdBlockRuleSet,
          onDeleteAdBlockRuleSet: _deleteAdBlockRuleSet,
          onRussiaRouteDataEnabledChanged: _setRussiaRouteDataEnabled,
          onInstallRussiaRouteData: _installRussiaRouteData,
          onDeleteRussiaRouteData: _deleteRussiaRouteData,
          onBypassLocalNetworkChanged: _setBypassLocalNetwork,
          onSplitRoutingModeChanged: _setSplitRoutingMode,
          onSplitRoutingPackagesChanged: _setSplitRoutingPackages,
        ),
      ),
    );
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
          onTcpFastOpenChanged: _setExperimentalTcpFastOpen,
          onTcpMultiPathChanged: _setExperimentalTcpMultiPath,
          onInterruptExistingConnectionsChanged:
              _setExperimentalInterruptExistingConnections,
          onUrlTestStrictToleranceChanged:
              _setExperimentalUrlTestStrictTolerance,
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
    if (_urlTestInFlight ||
        _urlTestMethodInFlight ||
        (!_foregroundLifecycleActive && !haptic)) {
      return;
    }
    if (haptic) {
      _haptic();
    }
    _urlTestMethodInFlight = true;
    if (mounted) {
      setState(() {
        _urlTestInFlight = true;
        _urlTestFallbackTimer?.cancel();
        _applyRuntimeStateToDerivedCaches();
      });
      unawaited(_syncQuickSettingsTileLabel());
    }
    try {
      _logLibboxCall('urlTest', 'reason=manual/global urltest group=select');
      await SingboxRuntime.instance.urlTest(groupTag: 'select');
      _urlTestFallbackTimer = Timer(const Duration(seconds: 15), () {
        if (!mounted) return;
        setState(() {
          _urlTestInFlight = false;
          _applyRuntimeStateToDerivedCaches();
        });
        unawaited(_syncQuickSettingsTileLabel());
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _urlTestInFlight = false;
          _applyRuntimeStateToDerivedCaches();
        });
        unawaited(_syncQuickSettingsTileLabel());
      }
      rethrow;
    } finally {
      _urlTestMethodInFlight = false;
    }
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
        await _runUrlTest(haptic: false);
      } catch (_) {
      } finally {
        _singleOutboundPingRefreshScheduled = false;
      }
    }());
  }

  void _emitCurrentConfigLog(String reason, {bool restartRuntime = true}) {
    unawaited(
      _emitCurrentConfigLogAsync(reason, restartRuntime: restartRuntime),
    );
  }

  Future<void> _emitCurrentConfigLogAsync(
    String reason, {
    required bool restartRuntime,
  }) async {
    final applyToRuntime = _connected || _runtimeTransitionInProgress;
    final generation = applyToRuntime ? ++_runtimeConfigApplyGeneration : 0;
    if (applyToRuntime && mounted) {
      setState(() {
        _setConnectionPhase(AppConnectionPhase.starting);
      });
    }
    final build = await _buildCurrentSingboxConfigInBackground(
      prepareConfig: applyToRuntime,
      returnConfig: applyToRuntime,
    );
    if (build == null) {
      if (applyToRuntime &&
          mounted &&
          generation == _runtimeConfigApplyGeneration) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.connected);
        });
      }
      return;
    }
    if (applyToRuntime && !_applyStartupValidationResult(build, reason)) {
      _discardPreparedConfigCandidate(build);
      if (mounted && generation == _runtimeConfigApplyGeneration) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.failed);
        });
      }
      _showNoValidOutboundsWarning();
      return;
    }
    _recordBuiltConfigLog(reason, build);
    if (!applyToRuntime) {
      return;
    }
    await _applyRuntimeConfig(
      build: build,
      useVpn: _vpnInboundEnabled,
      restartRuntime: restartRuntime,
      generation: generation,
    );
  }

  Future<void> _applyRuntimeConfig({
    required SingboxConfigBuildResult build,
    required bool useVpn,
    required bool restartRuntime,
    required int generation,
  }) async {
    try {
      if (restartRuntime) {
        await _restartRuntimeWithConfig(
          build: build,
          useVpn: useVpn,
          generation: generation,
        );
      } else {
        if (!mounted || generation != _runtimeConfigApplyGeneration) {
          return;
        }
        setState(() {
          _setConnectionPhase(AppConnectionPhase.starting);
        });
        await _applyRuntimeBuild(build, useVpn: useVpn, restartCore: false);
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 500),
            _syncRuntimeState,
          ),
        );
      }
    } catch (error) {
      AppLogStore.error('sing-box', 'Failed to apply config: $error');
      if (mounted) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.failed);
        });
      }
    }
  }

  Future<void> _restartRuntimeWithConfig({
    required SingboxConfigBuildResult build,
    required bool useVpn,
    required int generation,
  }) async {
    if (!mounted || generation != _runtimeConfigApplyGeneration) {
      return;
    }
    setState(() {
      _setConnectionPhase(AppConnectionPhase.stopping);
    });
    _logLibboxCall(
      'stop',
      'reason=config_changed before runtime restart useVpn=$useVpn',
    );
    await SingboxRuntime.instance.stop(reason: 'config_changed');
    if (!mounted || generation != _runtimeConfigApplyGeneration) {
      return;
    }
    final granted = await SingboxRuntime.instance.prepareVpn(
      requiresVpn: useVpn,
    );
    if (!granted || !mounted || generation != _runtimeConfigApplyGeneration) {
      if (mounted) {
        setState(() {
          _setConnectionPhase(AppConnectionPhase.idle);
        });
      }
      return;
    }
    await _startRuntimeWithBuild(build, useVpn: useVpn);
  }

  Future<void> _startRuntimeWithBuild(
    SingboxConfigBuildResult build, {
    required bool useVpn,
  }) async {
    _cacheLastStartedBuild(build);
    if (build.hasPreparedConfig) {
      await _promotePreparedConfigBuild(build);
      _logLibboxCall(
        'startPrepared',
        'reason=start runtime useVpn=$useVpn configOutbounds=${build.configOutboundCount}',
      );
      return SingboxRuntime.instance.startPrepared(useVpn: useVpn);
    }
    _logLibboxCall(
      'start',
      'reason=start runtime useVpn=$useVpn configOutbounds=${build.configOutboundCount} configChars=${build.configLength}',
    );
    return SingboxRuntime.instance.start(
      config: build.configJson,
      useVpn: useVpn,
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

  int _beginRuntimeProxySelectionGuard(String tag, String previousTag) {
    final generation = ++_runtimeSelectGeneration;
    _pendingRuntimeSelectTag = tag;
    _pendingRuntimeSelectPreviousTag = previousTag;
    _publishProxyRuntimeVisualStates();
    _pendingRuntimeSelectTimer?.cancel();
    _pendingRuntimeSelectTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted ||
          generation != _runtimeSelectGeneration ||
          _pendingRuntimeSelectTag != tag) {
        return;
      }
      AppLogStore.warning(
        'proxy',
        'runtime did not confirm selected outbound tag=$tag '
            'previous=${_pendingRuntimeSelectPreviousTag ?? '<none>'}; '
            'restarting runtime with local selection',
      );
      unawaited(() async {
        try {
          if (_connected) {
            await _emitCurrentConfigLogAsync(
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
          _clearRuntimeProxySelectionGuard(generation: generation);
        }
      }());
    });
    return generation;
  }

  void _clearRuntimeProxySelectionGuard({int? generation}) {
    if (generation != null && generation != _runtimeSelectGeneration) {
      return;
    }
    _pendingRuntimeSelectTimer?.cancel();
    _pendingRuntimeSelectTimer = null;
    _pendingRuntimeSelectTag = null;
    _pendingRuntimeSelectPreviousTag = null;
    _publishProxyRuntimeVisualStates();
  }

  Future<void> _applyRuntimeBuild(
    SingboxConfigBuildResult build, {
    required bool useVpn,
    required bool restartCore,
  }) async {
    _cacheLastStartedBuild(build);
    if (build.hasPreparedConfig) {
      await _promotePreparedConfigBuild(build);
      _logLibboxCall(
        'applyPreparedConfig',
        'reason=apply runtime useVpn=$useVpn restartCore=$restartCore configOutbounds=${build.configOutboundCount}',
      );
      return SingboxRuntime.instance.applyPreparedConfig(
        useVpn: useVpn,
        restartCore: restartCore,
      );
    }
    _logLibboxCall(
      'applyConfig',
      'reason=apply runtime useVpn=$useVpn restartCore=$restartCore configOutbounds=${build.configOutboundCount} configChars=${build.configLength}',
    );
    return SingboxRuntime.instance.applyConfig(
      config: build.configJson,
      useVpn: useVpn,
      restartCore: restartCore,
    );
  }

  Future<void> _persistSelectedProxyConfigSnapshot({
    required String reason,
    required int generation,
  }) async {
    if (!mounted || generation != _runtimeSelectGeneration) {
      return;
    }
    try {
      final build = await _buildCurrentSingboxConfigInBackground(
        returnConfig: false,
      );
      if (build == null || !mounted || generation != _runtimeSelectGeneration) {
        if (build != null) {
          _discardPreparedConfigCandidate(build);
        }
        return;
      }
      await _promotePreparedConfigBuild(build);
      _cacheLastStartedBuild(build);
      _recordBuiltConfigLog(reason, build);
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

  Future<String?> _ensureSingboxConfigPath() {
    return _singboxConfigPathFuture ??= SingboxRuntime.instance.getConfigPath();
  }

  Future<SingboxConfigBuildResult?> _buildCurrentSingboxConfigInBackground({
    bool dropStale = true,
    bool prepareConfig = true,
    bool returnConfig = false,
  }) async {
    if (!await _ensureActiveSubscriptionHydratedForRuntime()) {
      return null;
    }
    final generation = ++_singboxConfigBuildGeneration;
    final configPath = prepareConfig ? await _ensureSingboxConfigPath() : null;
    if (!mounted) {
      return null;
    }
    if (dropStale && generation != _singboxConfigBuildGeneration) {
      return null;
    }
    final stagedConfigPath = configPath == null
        ? null
        : '$configPath.pending.$generation';
    final input = _currentSingboxConfigBuildInput(
      outputConfigPath: stagedConfigPath,
      returnConfig: returnConfig || (prepareConfig && configPath == null),
    );
    late final SingboxConfigBuildResult result;
    try {
      result = await buildSingboxConfigInBackground(input);
    } catch (_) {
      _deletePreparedConfigCandidate(stagedConfigPath);
      rethrow;
    }
    if (!mounted) {
      _deletePreparedConfigCandidate(stagedConfigPath);
      return null;
    }
    if (dropStale && generation != _singboxConfigBuildGeneration) {
      _deletePreparedConfigCandidate(stagedConfigPath);
      return null;
    }
    return result;
  }

  Future<void> _promotePreparedConfigBuild(
    SingboxConfigBuildResult build,
  ) async {
    if (!build.hasPreparedConfig) {
      return;
    }
    final targetPath = await _ensureSingboxConfigPath();
    if (targetPath == null || targetPath.trim().isEmpty) {
      throw StateError('Prepared config target path is unavailable.');
    }
    _promotePreparedConfigCandidate(
      sourcePath: build.configPath!,
      targetPath: targetPath,
    );
  }

  void _promotePreparedConfigCandidate({
    required String sourcePath,
    required String targetPath,
  }) {
    if (sourcePath == targetPath) {
      return;
    }
    final source = File(sourcePath);
    final target = File(targetPath);
    target.parent.createSync(recursive: true);
    try {
      source.renameSync(target.path);
      return;
    } on FileSystemException {
      if (target.existsSync()) {
        target.deleteSync();
      }
    }
    source.renameSync(target.path);
  }

  void _deletePreparedConfigCandidate(String? path) {
    if (path == null || path.trim().isEmpty) {
      return;
    }
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  void _discardPreparedConfigCandidate(SingboxConfigBuildResult build) {
    if (!build.hasPreparedConfig) {
      return;
    }
    _deletePreparedConfigCandidate(build.configPath);
  }

  Future<void> _logCurrentSingboxConfig(String reason) async {
    final build = await _buildCurrentSingboxConfigInBackground(
      prepareConfig: false,
    );
    if (build == null) {
      return;
    }
    _recordBuiltConfigLog(reason, build);
  }

  void _recordBuiltConfigLog(String reason, SingboxConfigBuildResult build) {
    if (build.configJson.isNotEmpty) {
      final decoded = jsonDecode(build.configJson);
      if (decoded is Map<String, dynamic>) {
        AppLogStore.config(reason, decoded);
        return;
      }
    }
    if (build.hasReturnedConfig) {
      AppLogStore.config(reason, build.plan.config);
      return;
    }
    AppLogStore.info(
      'sing-box config ($reason)',
      'config omitted: ${build.configOutboundCount} outbounds, '
          '${build.configInboundCount} inbounds, '
          '${build.configRouteRuleCount} route rules, '
          '${build.configLength} chars',
    );
  }

  SingboxConfigBuildInput _currentSingboxConfigBuildInput({
    String? outputConfigPath,
    required bool returnConfig,
  }) {
    return SingboxConfigBuildInput(
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
      dnsDirectResolver: _dnsDirectResolver,
      dnsProxyResolver: _dnsProxyResolver,
      dnsPreferIpv6: _dnsPreferIpv6,
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
      russiaGeositeRuBlockedPath: _russiaRouteDataStatus.geositeRuBlockedPath,
      russiaGeositeRuAvailableOnlyInsidePath:
          _russiaRouteDataStatus.geositeRuAvailableOnlyInsidePath,
      russiaGeoipRuBlockedPath: _russiaRouteDataStatus.geoipRuBlockedPath,
      russiaCuratedDirectServicesPath:
          _russiaRouteDataStatus.curatedDirectServicesPath,
      russiaAiServicesPath: _russiaRouteDataStatus.aiServicesPath,
      bypassLocalNetwork: _bypassLocalNetwork,
      splitRoutingMode: _splitRoutingMode,
      splitRoutingPackages: _splitRoutingPackages,
      logLevel: _singBoxLogLevel,
      tcpFastOpenEnabled: _experimentalTcpFastOpen,
      tcpMultiPathEnabled: _experimentalTcpMultiPath,
      interruptExistingConnections: _experimentalInterruptExistingConnections,
      urlTestStrictTolerance: _experimentalUrlTestStrictTolerance,
      markAllServersRussia: _activeSubscription?.markAllServersRussia ?? false,
      snowtunBinaryPath: null,
      snowtunProtectPath: null,
      outputConfigPath: outputConfigPath,
      returnConfig: returnConfig,
    );
  }

  void _startSingboxEvents() {
    _singboxEventsSubscription?.cancel();
    _singboxEventsSubscription = SingboxRuntime.instance.events.listen((event) {
      final type = event['type'] as String? ?? '';
      switch (type) {
        case 'state':
          final running = event['running'] == true;
          final error = event['error']?.toString();
          final hasError = error != null && error.isNotEmpty;
          final wasRetryScheduled = _invalidOutboundRetryScheduled;
          if (!mounted) return;
          var shouldSyncQuickSettingsTile = false;
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
                retryScheduled:
                    keepConnecting && _invalidOutboundRetryScheduled,
              );
            }
            if (!running && !keepConnecting) {
              shouldSyncQuickSettingsTile = true;
              _activeOutboundIpRefreshToken++;
              _activeOutboundIpRefreshTimer?.cancel();
              _activeOutboundIpRefreshAttempts.clear();
              _locationLookupGeneration++;
              _locationLookupTimer?.cancel();
              _locationLookupInFlight = false;
              _locationLookupRefreshRequested = false;
              _cancelQueuedLocationLookups();
              _resetTrafficDashboardData();
              _urlTestInFlight = false;
              _urlTestMethodInFlight = false;
              _urlTestFallbackTimer?.cancel();
              _lowestLatency = null;
              _runtimeLowestOutboundTag = null;
              _runtimeLowestSelections.clear();
              _runtimeLatencies.clear();
              _unavailableLatencyTags.clear();
              _latencyErrors.clear();
              _singleOutboundPingRefreshScheduled = false;
              _postConnectUrlTestGeneration++;
              _postConnectUrlTestTimer?.cancel();
              _applyRuntimeStateToDerivedCaches();
            }
          });
          _publishTrafficDashboardSnapshot();
          if (shouldSyncQuickSettingsTile) {
            unawaited(_syncQuickSettingsTileLabel());
          }
          if (hasError) {
            unawaited(_handleRuntimeError(error, wasRetryScheduled));
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
          break;
        case 'status':
          _handleTrafficStatusEvent(event);
          break;
        case 'network':
          _handleRuntimeNetworkEvent(event);
          break;
        case 'groups':
          final groups = (event['groups'] as List?) ?? const [];
          _applyGroupUpdates(groups);
          break;
        case 'nativeLog':
          final level = (event['level']?.toString() ?? 'info').toLowerCase();
          final message = event['message']?.toString() ?? '';
          if (message.isEmpty) return;
          final normalizedLevel = switch (level) {
            'warn' => 'warning',
            'trace' => 'debug',
            _ => level,
          };
          final effectiveLevel =
              AppLogStore.inferLevel(message) ?? normalizedLevel;
          if (!_shouldRecordSingBoxLog(effectiveLevel)) {
            return;
          }
          AppLogStore.ingest(
            'sing-box',
            message,
            fallbackLevel: switch (effectiveLevel) {
              'error' => 'error',
              'debug' => 'debug',
              'warning' => 'warning',
              _ => 'info',
            },
            trustFallbackLevel: true,
          );
          break;
        case 'logLevel':
          final level = (event['level'] as num?)?.toInt();
          if (level == null) break;
          break;
        case 'logs':
          final logs = (event['logs'] as List?) ?? const [];
          final batch = <AppLogEntry>[];
          for (final entry in logs) {
            final map = Map<String, dynamic>.from(entry as Map);
            final level = (map['level'] as num?)?.toInt() ?? 0;
            final message = map['message']?.toString() ?? '';
            if (message.isEmpty) continue;
            final fallbackLevel = switch (level) {
              >= 4 => 'error',
              3 => 'warning',
              2 => 'info',
              _ => 'debug',
            };
            final effectiveLevel =
                AppLogStore.inferLevel(message) ?? fallbackLevel;
            if (!_shouldRecordSingBoxLog(effectiveLevel)) {
              continue;
            }
            batch.add(
              AppLogEntry(
                timestamp: DateTime.now(),
                level: effectiveLevel,
                title: 'sing-box',
                message: AppLogStore.normalizeMessage(message),
              ),
            );
          }
          AppLogStore.appendBatch(batch);
          break;
        default:
          break;
      }
    });
    unawaited(_syncRuntimeState());
  }

  void _handleTrafficStatusEvent(Map<String, dynamic> event) {
    if (!_foregroundLifecycleActive) {
      return;
    }
    if (!_balancedMode) {
      _applyTrafficStatusEvent(event);
      return;
    }
    _pendingTrafficStatusEvent = event;
    final now = DateTime.now();
    final elapsed = now.difference(_lastTrafficUiUpdateAt);
    if (elapsed >= _balancedTrafficUiUpdateInterval) {
      _flushPendingTrafficStatusEvent();
      return;
    }
    _trafficUiUpdateTimer ??= Timer(
      _balancedTrafficUiUpdateInterval - elapsed,
      () {
        _trafficUiUpdateTimer = null;
        _flushPendingTrafficStatusEvent();
      },
    );
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
    AppLogStore.info(
      'network',
      'default network changed: $reason'
          '${interfaceName == null || interfaceName.isEmpty ? '' : ' ($interfaceName)'}',
    );
    if (!_connected ||
        !_foregroundLifecycleActive ||
        _runtimeTransitionInProgress) {
      return;
    }
    if (reason == 'default_interface') {
      _schedulePostConnectSelectedProxyUrlTest(
        reason: 'default_interface_changed',
        delay: const Duration(milliseconds: 900),
      );
    }
    final generation = ++_networkReconnectGeneration;
    _networkReconnectWatchdogTimer?.cancel();
    _networkReconnectWatchdogTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted ||
          generation != _networkReconnectGeneration ||
          !_connected ||
          !_foregroundLifecycleActive ||
          _runtimeTransitionInProgress) {
        return;
      }
      final lastStatusEventAt = _lastRuntimeStatusEventAt;
      if (lastStatusEventAt != null && lastStatusEventAt.isAfter(now)) {
        return;
      }
      AppLogStore.warning(
        'network',
        'no fresh runtime status after network change; restarting runtime',
      );
      unawaited(
        _emitCurrentConfigLogAsync(
          'network changed watchdog restart',
          restartRuntime: true,
        ),
      );
    });
  }

  Future<void> _syncRuntimeState() async {
    try {
      final status = await SingboxRuntime.instance.status();
      if (!mounted || !_foregroundLifecycleActive) return;
      final running = status['running'] == true;
      final now = DateTime.now();
      setState(() {
        _setConnectionPhase(
          running
              ? AppConnectionPhase.connected
              : (_runtimeTransitionInProgress || _invalidOutboundRetryScheduled
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
        if (!running) {
          _resetTrafficDashboardData();
          _postConnectUrlTestGeneration++;
          _postConnectUrlTestTimer?.cancel();
          _postConnectUrlTestTimer = null;
        } else {
          _recordTrafficSample(now);
        }
      });
      _publishTrafficDashboardSnapshot();
      if (running) {
        _scheduleActiveOutboundIpRefresh();
        _schedulePostConnectSelectedProxyUrlTest(
          reason: 'runtime_sync_running',
        );
      }
    } catch (_) {
      // Ignore transient sync failures: live EventChannel events still drive state.
    }
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
        _setConnectionPhase(AppConnectionPhase.failed);
      });
    } else {
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
      final build = await _buildCurrentSingboxConfigInBackground(
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
    if (_invalidOutboundRetryScheduled) {
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
    _invalidOutboundRetryTimer?.cancel();
    _invalidOutboundRetryTimer = Timer(const Duration(milliseconds: 300), () {
      AppLogStore.info('sing-box', reason);
      unawaited(() async {
        try {
          await SingboxRuntime.instance.stop(reason: 'invalid_outbound_retry');
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (await _tryFastRetryViaMutation(reason)) {
          return;
        }
        final build = await _buildCurrentSingboxConfigInBackground(
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
        if (!_applyStartupValidationResult(build, reason)) {
          _discardPreparedConfigCandidate(build);
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

  Future<bool> _tryFastRetryViaMutation(String reason) async {
    final cachedConfig = _lastStartedConfig;
    final cachedIndexMap = _lastStartedProxyOutboundTagsByIndex;
    final excludedTag = _pendingMutationExcludedTag;
    if (cachedConfig == null || cachedIndexMap == null || excludedTag == null) {
      return false;
    }
    final configPath = await _ensureSingboxConfigPath();
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

    final delays = <String, int?>{};
    final statuses = <String, String>{};
    final errors = <String, String>{};
    final times = <String, int>{};
    String? runtimeSelected;
    final subscriptionGroupTags = activeSubscription.groups
        .map((group) => group.tag)
        .toSet();
    final groupSelections = Map<String, String>.fromEntries(
      _runtimeGroupSelections.entries.where(
        (entry) => subscriptionGroupTags.contains(entry.key),
      ),
    );
    final lowestSelections = Map<String, String>.fromEntries(
      _runtimeLowestSelections.entries.where(
        (entry) => isLowestProxyTag(entry.key),
      ),
    );

    for (final rawGroup in rawGroups) {
      if (rawGroup is! Map) {
        continue;
      }
      final group = Map<String, dynamic>.from(rawGroup);
      final tag = group['tag']?.toString() ?? '';
      if (tag == 'select') {
        runtimeSelected = group['selected']?.toString();
      } else if (isLowestProxyTag(tag)) {
        final selected = group['selected']?.toString() ?? '';
        if (selected.isNotEmpty && !isLowestProxyTag(selected)) {
          lowestSelections[tag] = selected;
        } else {
          lowestSelections.remove(tag);
        }
      } else if (subscriptionGroupTags.contains(tag)) {
        final selected = group['selected']?.toString() ?? '';
        if (selected.isNotEmpty) {
          groupSelections[tag] = selected;
        }
      }
      final items = (group['items'] as List?) ?? const [];
      for (final rawItem in items) {
        if (rawItem is! Map) {
          continue;
        }
        final item = Map<String, dynamic>.from(rawItem);
        final itemTag = item['tag']?.toString() ?? '';
        if (itemTag.isEmpty || isLowestProxyTag(itemTag)) {
          continue;
        }
        final status = (item['status']?.toString() ?? '').trim().toLowerCase();
        final error = (item['error']?.toString() ?? '').trim();
        final delay = (item['delay'] as num?)?.toInt();
        final time = (item['time'] as num?)?.toInt();
        final currentTime = times[itemTag];
        final nextTime = time != null && time > 0 ? time : null;
        final shouldReplace =
            currentTime == null ||
            (nextTime != null && nextTime >= currentTime);
        if (!shouldReplace) {
          continue;
        }
        if (status.isNotEmpty) {
          statuses[itemTag] = status;
        } else {
          statuses.remove(itemTag);
        }
        if (error.isNotEmpty) {
          errors[itemTag] = error;
        } else {
          errors.remove(itemTag);
        }
        if (nextTime != null) {
          times[itemTag] = nextTime;
        }
        delays[itemTag] = delay != null && delay > 0 ? delay : null;
      }
    }
    final persistableDelays = <String, int?>{
      for (final entry in delays.entries)
        if (_activeOutboundByTagLookup.containsKey(entry.key))
          entry.key: entry.value,
    };
    _queueLatestPingSave(activeSubscription.id, persistableDelays);

    if (delays.isEmpty &&
        statuses.isEmpty &&
        runtimeSelected == null &&
        _mapEquals(_runtimeLowestSelections, lowestSelections) &&
        _mapEquals(_runtimeGroupSelections, groupSelections)) {
      return;
    }

    final nextRuntimeLatencies = Map<String, int>.from(_runtimeLatencies);
    final nextUnavailableLatencyTags = Set<String>.from(
      _unavailableLatencyTags,
    );
    final nextLatencyErrors = Map<String, String>.from(_latencyErrors);
    final touchedTags = <String>{
      ...delays.keys,
      ...statuses.keys,
      ...errors.keys,
    };
    for (final tag in touchedTags) {
      final status = statuses[tag];
      if (status == _urlTestStatusUnavailable) {
        if (_isTransientLatencyError(errors[tag])) {
          nextUnavailableLatencyTags.remove(tag);
          nextLatencyErrors.remove(tag);
          continue;
        }
        nextRuntimeLatencies.remove(tag);
        nextUnavailableLatencyTags.add(tag);
        nextLatencyErrors[tag] = errors[tag] ?? '';
        continue;
      }
      if (statuses.containsKey(tag)) {
        nextUnavailableLatencyTags.remove(tag);
        nextLatencyErrors.remove(tag);
      }
      if (delays.containsKey(tag)) {
        final delay = delays[tag];
        if (delay != null && delay > 0) {
          nextRuntimeLatencies[tag] = delay;
          nextUnavailableLatencyTags.remove(tag);
          nextLatencyErrors.remove(tag);
        }
      }
    }

    int? lowestLatency;
    for (final entry in nextRuntimeLatencies.entries) {
      if (nextUnavailableLatencyTags.contains(entry.key)) {
        continue;
      }
      final delay = entry.value;
      if (lowestLatency == null || delay < lowestLatency) {
        lowestLatency = delay;
      }
    }

    final pendingRuntimeSelectTag = _pendingRuntimeSelectTag;
    final runtimeSelectionConfirmsPending =
        pendingRuntimeSelectTag != null &&
        runtimeSelected == pendingRuntimeSelectTag;
    final runtimeSelectionIsStaleDuringPending =
        pendingRuntimeSelectTag != null &&
        runtimeSelected != null &&
        runtimeSelected.isNotEmpty &&
        runtimeSelected != pendingRuntimeSelectTag &&
        _selectedProxyTag == pendingRuntimeSelectTag;
    if (runtimeSelectionConfirmsPending) {
      _clearRuntimeProxySelectionGuard();
    } else if (runtimeSelectionIsStaleDuringPending) {
      AppLogStore.info(
        'proxy',
        'ignored stale runtime selected outbound tag=$runtimeSelected '
            'while pending tag=$pendingRuntimeSelectTag',
      );
    }

    final runtimeSelectionChanged =
        !runtimeSelectionIsStaleDuringPending &&
        runtimeSelected != null &&
        runtimeSelected.isNotEmpty &&
        !isLowestProxyTag(runtimeSelected) &&
        !isLowestProxyTag(_selectedProxyTag) &&
        _selectedProxyTag != runtimeSelected;
    final latencyStateChanged =
        _lowestLatency != lowestLatency ||
        _urlTestInFlight ||
        !_intMapEquals(_runtimeLatencies, nextRuntimeLatencies) ||
        !_setEquals(_unavailableLatencyTags, nextUnavailableLatencyTags) ||
        !_mapEquals(_latencyErrors, nextLatencyErrors) ||
        !_mapEquals(_runtimeLowestSelections, lowestSelections) ||
        !_mapEquals(_runtimeGroupSelections, groupSelections);
    final realOutboundRuntimeStateChanged =
        touchedTags.any(_activeOutboundByTagLookup.containsKey) ||
        !_mapEquals(_runtimeLowestSelections, lowestSelections) ||
        !_mapEquals(_runtimeGroupSelections, groupSelections);

    if (!runtimeSelectionChanged && !latencyStateChanged) {
      return;
    }
    final nextRuntimeLowestOutboundTag = lowestSelections[_lowestProxyTag];
    final shouldRebuildProxyCache =
        (runtimeSelectionChanged && !_proxyCacheContainsTag(runtimeSelected)) ||
        lowestSelections.values.any((tag) => !_proxyCacheContainsTag(tag)) ||
        groupSelections.entries.any(
          (entry) =>
              _visibleGroupProxyCacheMissingChild(entry.key, entry.value),
        );
    final lowestSelectionsChanged = !_mapEquals(
      _runtimeLowestSelections,
      lowestSelections,
    );
    final groupSelectionsChanged = !_mapEquals(
      _runtimeGroupSelections,
      groupSelections,
    );
    final currentActiveTag = _currentResolvedActiveOutboundTag();
    final activeProxyTouched =
        currentActiveTag != null && touchedTags.contains(currentActiveTag);
    final requiresRootRebuild =
        runtimeSelectionChanged ||
        lowestSelectionsChanged ||
        groupSelectionsChanged ||
        activeProxyTouched ||
        _urlTestInFlight;

    void applyRuntimeUpdates() {
      _runtimeLatencies
        ..clear()
        ..addAll(nextRuntimeLatencies);
      _unavailableLatencyTags
        ..clear()
        ..addAll(nextUnavailableLatencyTags);
      _latencyErrors
        ..clear()
        ..addAll(nextLatencyErrors);
      _runtimeGroupSelections
        ..clear()
        ..addAll(groupSelections);
      _runtimeLowestSelections
        ..clear()
        ..addAll(lowestSelections);
      _lowestLatency = lowestLatency;
      _runtimeLowestOutboundTag = nextRuntimeLowestOutboundTag;
      _urlTestInFlight = false;
      _urlTestFallbackTimer?.cancel();
      if (runtimeSelectionChanged) {
        _setSelectedProxyTagLocally(runtimeSelected!);
      }
      _applyRuntimeStateToDerivedCaches();
    }

    if (requiresRootRebuild) {
      setState(applyRuntimeUpdates);
    } else {
      applyRuntimeUpdates();
    }
    if (shouldRebuildProxyCache) {
      _rebuildDerivedCaches();
    }
    unawaited(_syncQuickSettingsTileLabel());
    if (_connected) {
      final nextActiveOutboundTag = _currentResolvedActiveOutboundTag();
      if (nextActiveOutboundTag != null &&
          nextActiveOutboundTag != previousActiveOutboundTag) {
        _scheduleActiveOutboundIpRefresh();
      }
      if (realOutboundRuntimeStateChanged) {
        _scheduleBestOutboundLocationRefresh();
      }
    }
  }

  bool _isTransientLatencyError(String? error) {
    final text = error?.toLowerCase() ?? '';
    if (text.isEmpty) {
      return false;
    }
    return text.contains('no available network interface') ||
        text.contains('network is unreachable') ||
        text.contains('no route to host') ||
        text.contains('temporary failure in name resolution');
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
    Duration delay = const Duration(milliseconds: 900),
  }) {
    _activeOutboundIpRefreshTimer?.cancel();
    _activeOutboundIpRefreshToken++;
    if (!_connected || !_foregroundLifecycleActive) {
      return;
    }

    final activeSubscription = _activeSubscription;
    final activeOutbound = _currentResolvedActiveOutbound();
    if (activeSubscription == null || activeOutbound == null) {
      return;
    }

    final requestToken = _activeOutboundIpRefreshToken;
    final subscriptionId = activeSubscription.id;
    final outboundTag = activeOutbound.tag;
    _activeOutboundIpRefreshTimer = Timer(delay, () {
      unawaited(
        _refreshActiveOutboundIp(
          requestToken: requestToken,
          subscriptionId: subscriptionId,
          outboundTag: outboundTag,
        ),
      );
    });
  }

  Future<void> _refreshActiveOutboundIp({
    required int requestToken,
    required String subscriptionId,
    required String outboundTag,
  }) async {
    if (!_connected ||
        !_foregroundLifecycleActive ||
        requestToken != _activeOutboundIpRefreshToken) {
      return;
    }
    final activeSubscription = _activeSubscription;
    final activeOutbound = _currentResolvedActiveOutbound();
    if (activeSubscription == null ||
        activeSubscription.id != subscriptionId ||
        activeOutbound == null ||
        activeOutbound.tag != outboundTag) {
      return;
    }
    final refreshKey = '$subscriptionId\n$outboundTag';
    final now = DateTime.now();
    final lastAttempt = _activeOutboundIpRefreshAttempts[refreshKey];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _activeOutboundIpRefreshMinInterval &&
        _hasResolvedExternalLocation(activeOutbound)) {
      return;
    }
    _activeOutboundIpRefreshAttempts[refreshKey] = now;

    final resolved = await _fetchExternalIpInfo(outboundTag: outboundTag);
    if (resolved == null ||
        !_connected ||
        !mounted ||
        requestToken != _activeOutboundIpRefreshToken) {
      return;
    }

    final latestSubscription = _activeSubscription;
    final latestActiveOutbound = _currentResolvedActiveOutbound();
    if (latestSubscription == null ||
        latestSubscription.id != subscriptionId ||
        latestActiveOutbound == null ||
        latestActiveOutbound.tag != outboundTag) {
      return;
    }

    await _applyResolvedExternalIpInfos(
      subscriptionId: latestSubscription.id,
      resolvedByTag: {outboundTag: resolved},
    );
  }

  Future<_ResolvedExternalIpInfo?> _fetchExternalIpInfo({
    required String outboundTag,
  }) async {
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
    } catch (_) {
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
    if (!_foregroundLifecycleActive) {
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

  bool _setEquals(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final value in left) {
      if (!right.contains(value)) {
        return false;
      }
    }
    return true;
  }

  bool _mapEquals(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  bool _intMapEquals(Map<String, int> left, Map<String, int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
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
    return subscription.copyWith(selectedProxyTag: tag);
  }

  List<Subscription> _replaceSubscription(Subscription updated) {
    return _subscriptions
        .map(
          (subscription) =>
              subscription.id == updated.id ? updated : subscription,
        )
        .toList(growable: false);
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
            onboardingCompleted: _onboardingCompleted,
            loading: const Scaffold(
              key: ValueKey('loading'),
              body: Center(child: CircularProgressIndicator()),
            ),
            welcome: WelcomePage(
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
                onHideServerIpChanged: _setHideServerIp,
                onOpenSubscriptions: _showSubscriptionsPage,
                onAddSubscription: () =>
                    _showSubscriptionsPage(openAddOnStart: true),
                onOpenSettings: _showSettingsPage,
                onOpenTrafficDashboard: () =>
                    unawaited(_showTrafficDashboard()),
                onRefreshActiveSubscription: canRefreshActiveSubscription
                    ? _refreshActiveSubscription
                    : null,
                activeProfileRefreshing: _activeProfileRefreshInFlight,
                showActiveProfileRefreshAction: activeSubscription != null,
                brandName: 'Etonify',
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
                    onRefreshAllSubscriptions: _refreshAllSubscriptions,
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

class _NormalizedSelection {
  const _NormalizedSelection({
    required this.activeSubscriptionId,
    required this.selectedProxyTag,
  });

  final String activeSubscriptionId;
  final String selectedProxyTag;
}

class _ResolvedSubscriptions {
  const _ResolvedSubscriptions({
    required this.subscriptions,
    required this.normalized,
    this.proxyCache,
  });

  final List<Subscription> subscriptions;
  final _NormalizedSelection normalized;
  final ProxyCacheBuildResult? proxyCache;
}

class _HydratedActiveSubscription {
  const _HydratedActiveSubscription({
    required this.subscription,
    required this.normalized,
    required this.proxyCache,
  });

  final Subscription subscription;
  final _NormalizedSelection normalized;
  final ProxyCacheBuildResult proxyCache;
}

_NormalizedSelection _normalizeActiveSubscriptionSelection(
  Subscription activeSubscription, {
  required String selectedProxyTag,
  required bool russiaRouteProxiesEnabled,
}) {
  Outbound? selectedOutbound;
  Outbound? checkedOutbound;
  final visibleOutbounds = <Outbound>[];
  final visibleOutboundTags = <String>{};
  for (final outbound in activeSubscription.outbounds) {
    if (outbound.info.deleted || outbound.config['_group_only'] == true) {
      continue;
    }
    visibleOutbounds.add(outbound);
    visibleOutboundTags.add(outbound.tag);
    checkedOutbound ??= outbound.info.checked ? outbound : null;
  }
  final effectiveSelectedProxyTag =
      activeSubscription.selectedProxyTag.isNotEmpty
      ? activeSubscription.selectedProxyTag
      : selectedProxyTag;
  final proxyChainTags = activeSubscription.proxyChains
      .map((chain) => chain.tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet();
  if (proxyChainTags.contains(effectiveSelectedProxyTag)) {
    return _NormalizedSelection(
      activeSubscriptionId: activeSubscription.id,
      selectedProxyTag: effectiveSelectedProxyTag,
    );
  }
  if (visibleOutbounds.length == 1) {
    final singleTag = visibleOutbounds.single.tag;
    if (effectiveSelectedProxyTag.isEmpty ||
        isLowestProxyTag(effectiveSelectedProxyTag) ||
        isMixedProxyTag(effectiveSelectedProxyTag) ||
        !visibleOutboundTags.contains(effectiveSelectedProxyTag)) {
      return _NormalizedSelection(
        activeSubscriptionId: activeSubscription.id,
        selectedProxyTag: singleTag,
      );
    }
  }
  if (isMixedProxyTag(effectiveSelectedProxyTag) &&
      visibleOutbounds.isNotEmpty) {
    return _NormalizedSelection(
      activeSubscriptionId: activeSubscription.id,
      selectedProxyTag: mixedProxyTag,
    );
  }
  if (isLowestProxyTag(effectiveSelectedProxyTag) &&
      visibleOutbounds.isNotEmpty) {
    return _NormalizedSelection(
      activeSubscriptionId: activeSubscription.id,
      selectedProxyTag: effectiveSelectedProxyTag,
    );
  }
  for (final group in activeSubscription.groups) {
    if (group.tag == effectiveSelectedProxyTag &&
        group.outboundTags.any(visibleOutboundTags.contains)) {
      return _NormalizedSelection(
        activeSubscriptionId: activeSubscription.id,
        selectedProxyTag: group.tag,
      );
    }
  }
  for (final outbound in visibleOutbounds) {
    if (outbound.tag == effectiveSelectedProxyTag) {
      selectedOutbound = outbound;
      break;
    }
  }
  selectedOutbound ??= checkedOutbound;
  selectedOutbound ??= visibleOutbounds.isNotEmpty
      ? visibleOutbounds.first
      : null;

  return _NormalizedSelection(
    activeSubscriptionId: activeSubscription.id,
    selectedProxyTag: selectedOutbound?.tag ?? '',
  );
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        isHapp
                            ? l10n.deepLinkImportHappCancelAction
                            : l10n.cancel,
                      ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        isHapp
                            ? l10n.deepLinkImportHappSendHwidAction
                            : copy.importAction,
                      ),
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
