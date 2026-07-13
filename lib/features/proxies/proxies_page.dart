import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:meow_client/core/demo_utils.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/core/widgets/app_notice.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/app_view_models.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/widgets/country_flag_badge.dart';
import 'package:meow_client/widgets/ip_refresh_dots.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

import 'proxy_list_ordering.dart';
import 'proxy_panel_shell.dart';

const _kProxyListPreviewLimit = 50;
const _kProxySheetHeaderHeight = 108.0;
const _kProxySheetCompactHeaderHeight = 72.0;
const _kProxySheetListTopReserve = 148.0;
const _kProxyGroupSheetListTopReserve = 144.0;
const _kProxySheetRowExtent = 72.0;
const _kProxySheetHeaderCollapseDistance = 48.0;
const _kProxySheetCarryMinVelocity = 1200.0;
const _kProxySheetCarryMinDistance = 32.0;
const _kProxySheetCarryMinResidualVelocity = 90.0;
const _kProxySheetFrictionDrag = 0.135;
const _kProxySheetMaxSpringTransferVelocity = 5000.0;
const _kProxySheetHeaderBlurStart = 0.0;

enum _ProxyChainAction { edit, rename, remove }

String _proxySortLabel(AppLocalizations l10n, ProxySort sort) => switch (sort) {
  ProxySort.source => l10n.sortByDefault,
  ProxySort.latency => l10n.sortByLatency,
  ProxySort.name => l10n.sortByName,
  ProxySort.country => l10n.sortByCountry,
};

IconData _proxySortIcon(ProxySort sort) => switch (sort) {
  ProxySort.source => FluentIcons.list_24_regular,
  ProxySort.latency => FluentIcons.timer_24_regular,
  ProxySort.name => FluentIcons.text_sort_ascending_24_regular,
  ProxySort.country => FluentIcons.globe_24_regular,
};

Future<void> _showProxySortPicker(
  BuildContext context, {
  required AppLocalizations l10n,
  required ProxySort current,
  required ValueChanged<ProxySort> onSelected,
}) async {
  final result = await showModalBottomSheet<ProxySort>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(l10n.sort, style: theme.textTheme.titleLarge),
              ),
              RadioGroup<ProxySort>(
                groupValue: current,
                onChanged: (value) => Navigator.of(context).pop(value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final sort in ProxySort.values)
                      RadioListTile<ProxySort>(
                        value: sort,
                        secondary: Icon(_proxySortIcon(sort)),
                        title: Text(_proxySortLabel(l10n, sort)),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (result != null && result != current) {
    onSelected(result);
  }
}

@immutable
class ProxyRuntimeVisualState {
  const ProxyRuntimeVisualState({
    this.latency,
    this.latencyFresh = false,
    this.latencyChecking = false,
    this.latencyUnavailable = false,
    this.latencyError,
    this.highlighted = false,
    this.selecting = false,
  });

  final int? latency;
  final bool latencyFresh;
  final bool latencyChecking;
  final bool latencyUnavailable;
  final String? latencyError;
  final bool highlighted;
  final bool selecting;

  @override
  bool operator ==(Object other) {
    return other is ProxyRuntimeVisualState &&
        other.latency == latency &&
        other.latencyFresh == latencyFresh &&
        other.latencyChecking == latencyChecking &&
        other.latencyUnavailable == latencyUnavailable &&
        other.latencyError == latencyError &&
        other.highlighted == highlighted &&
        other.selecting == selecting;
  }

  @override
  int get hashCode => Object.hash(
    latency,
    latencyFresh,
    latencyChecking,
    latencyUnavailable,
    latencyError,
    highlighted,
    selecting,
  );
}

class ProxyRuntimeVisualStore {
  final Map<String, ValueNotifier<ProxyRuntimeVisualState?>> _notifiers =
      <String, ValueNotifier<ProxyRuntimeVisualState?>>{};
  Map<String, ProxyRuntimeVisualState> _states =
      const <String, ProxyRuntimeVisualState>{};

  ValueListenable<ProxyRuntimeVisualState?> listenableFor(String tag) {
    return _notifiers.putIfAbsent(
      tag,
      () => ValueNotifier<ProxyRuntimeVisualState?>(_states[tag]),
    );
  }

  void replaceAll(Map<String, ProxyRuntimeVisualState> next) {
    final previousKeys = _states.keys.toSet();
    _states = Map.unmodifiable(next);
    final changed = <String>{...previousKeys, ...next.keys};
    for (final tag in changed) {
      final notifier = _notifiers[tag];
      if (notifier == null) {
        continue;
      }
      final value = next[tag];
      if (notifier.value != value) {
        notifier.value = value;
      }
    }
  }

  ProxyRuntimeVisualState? valueFor(String tag) => _states[tag];

  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
  }
}

class _ProxyLatencyLabel extends StatelessWidget {
  const _ProxyLatencyLabel({
    required this.text,
    required this.color,
    required this.checking,
    required this.emphasized,
    this.tooltip,
  });

  final String text;
  final Color color;
  final bool checking;
  final bool emphasized;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: color,
      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
    );
    if (checking) {
      return Center(child: _LatencyDots(color: color));
    }
    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: Text(
        text,
        key: ValueKey(text),
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    final message = tooltip?.trim();
    if (message == null || message.isEmpty) {
      return child;
    }
    return Tooltip(message: message, child: child);
  }
}

String _latencyErrorLabel(String? error) {
  final text = error?.trim();
  if (text == null || text.isEmpty) {
    return '-';
  }
  final normalized = text.toLowerCase();
  if (normalized.contains('tls') || normalized.contains('handshake')) {
    return 'TLS';
  }
  if (normalized.contains('timeout') || normalized.contains('deadline')) {
    return 'timeout';
  }
  if (normalized.contains('refused')) {
    return 'refused';
  }
  if (normalized.contains('eof')) {
    return 'EOF';
  }
  if (normalized.contains('dns') ||
      normalized.contains('lookup') ||
      normalized.contains('resolve')) {
    return 'DNS';
  }
  if (normalized.contains('network is unreachable') ||
      normalized.contains('no route')) {
    return 'network';
  }
  return 'error';
}

String? _latencyErrorTooltip(String? error) {
  final text = error?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text.length <= 180 ? text : '${text.substring(0, 177)}...';
}

class _LatencyDots extends StatefulWidget {
  const _LatencyDots({required this.color});

  final Color color;

  @override
  State<_LatencyDots> createState() => _LatencyDotsState();
}

class _LatencyDotsState extends State<_LatencyDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: widget.color,
      fontWeight: FontWeight.w700,
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final count = (_controller.value * 3).floor() + 1;
        final visibleCount = count > 3 ? 3 : count;
        return Text(
          '.' * visibleCount,
          key: ValueKey(visibleCount),
          textAlign: TextAlign.center,
          style: style,
        );
      },
    );
  }
}

class ProxiesPage extends StatefulWidget {
  const ProxiesPage({
    super.key,
    required this.proxies,
    this.totalTopLevelProxies,
    required this.selectedTag,
    this.activeProxy,
    this.activeProxyHideIp = false,
    required this.connected,
    this.hapticEnabled = true,
    this.speedBytesPerSecond = 0,
    this.trafficBytes = 0,
    this.trafficListenable,
    this.initialSort = ProxySort.source,
    this.onSortChanged,
    required this.progressiveBlurEnabled,
    required this.onSelected,
    required this.onUrlTest,
    this.outboundForTag,
    this.loadProxyChainTargetSources,
    this.loadProxyChainTargetsForSource,
    this.onAddProxyChain,
    this.onChangeProxyChainDetour,
    this.onRenameProxyChain,
    this.onRemoveProxyChain,
    this.isProxyChainTag,
    this.onActiveProxyHideIpChanged,
    this.onActiveProxyIpRefresh,
    this.embedded = false,
    this.sheetMetricsListenable,
    this.scrollController,
    this.sheetAtMaxExtent = false,
    this.sheetCanFillScreen = false,
    this.sheetExtent = 0,
    this.collapsedSheetExtent = 0,
    this.expandedHeaderExtent = 1,
    this.sheetCornerRadius = 0,
    this.collapseOnAnyDownwardDrag = false,
    this.onInteractionStart,
    this.onHeaderDragUpdate,
    this.onHeaderDragEnd,
    this.onHeaderTap,
    this.runtimeStates,
    this.groupChildrenByTag = const <String, List<AppProxySummary>>{},
  });

  final List<AppProxySummary> proxies;
  final int? totalTopLevelProxies;
  final String selectedTag;
  final AppProxySummary? activeProxy;
  final bool activeProxyHideIp;
  final bool connected;
  final bool hapticEnabled;
  final double speedBytesPerSecond;
  final double trafficBytes;
  final ValueListenable<TrafficUiSnapshot>? trafficListenable;
  final ProxySort initialSort;
  final ValueChanged<ProxySort>? onSortChanged;
  final bool progressiveBlurEnabled;
  final ValueChanged<String> onSelected;
  final Future<void> Function() onUrlTest;
  final Outbound? Function(String tag)? outboundForTag;
  final Future<List<AppProfileSummary>> Function()? loadProxyChainTargetSources;
  final Future<List<AppProxySummary>> Function(String subscriptionId)?
  loadProxyChainTargetsForSource;
  final Future<void> Function(String detourTag, String targetTag)?
  onAddProxyChain;
  final Future<void> Function(String chainTag, String detourTag)?
  onChangeProxyChainDetour;
  final Future<void> Function(String chainTag, String name)? onRenameProxyChain;
  final Future<void> Function(String chainTag)? onRemoveProxyChain;
  final bool Function(String tag)? isProxyChainTag;
  final ValueChanged<bool>? onActiveProxyHideIpChanged;
  final VoidCallback? onActiveProxyIpRefresh;
  final bool embedded;
  final ValueListenable<ProxyPanelMetrics>? sheetMetricsListenable;
  final ScrollController? scrollController;
  final bool sheetAtMaxExtent;
  final bool sheetCanFillScreen;
  final double sheetExtent;
  final double collapsedSheetExtent;
  final double expandedHeaderExtent;
  final double sheetCornerRadius;
  final bool collapseOnAnyDownwardDrag;
  final VoidCallback? onInteractionStart;
  final ValueChanged<DragUpdateDetails>? onHeaderDragUpdate;
  final ValueChanged<DragEndDetails>? onHeaderDragEnd;
  final VoidCallback? onHeaderTap;
  final ProxyRuntimeVisualStore? runtimeStates;
  final Map<String, List<AppProxySummary>> groupChildrenByTag;

  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> {
  late ProxySort _sort;
  List<AppProxySummary> _visibleItems = const [];
  int _hiddenCount = 0;
  bool _showAllProxies = false;
  VelocityTracker? _proxySheetDragVelocityTracker;
  double? _pendingProxySheetCarryVelocity;
  bool _proxySheetDragMoved = false;
  bool _proxySheetPointerStartedInList = false;
  double _proxySheetPointerDeltaY = 0;
  double _proxySheetHeaderScrollCollapse = 0;
  bool _groupSheetOpen = false;
  bool _showExtraLowests = false;
  List<_ProxyListEntry>? _visibleEntriesCache;
  List<AppProxySummary>? _visibleEntriesItemsCache;
  ProxySort? _visibleEntriesSortCache;
  bool? _visibleEntriesExtraLowestsCache;
  bool? _visibleEntriesCanAddChainCache;
  bool Function(String tag)? _visibleEntriesChainPredicateCache;
  int? _visibleEntriesHiddenCountCache;

  bool _isProxyChain(AppProxySummary proxy) =>
      widget.isProxyChainTag?.call(proxy.tag) ?? false;

  ProxyPanelMetrics? get _sheetMetrics => widget.sheetMetricsListenable?.value;

  bool get _effectiveSheetAtMaxExtent =>
      _sheetMetrics?.atMaxExtent ?? widget.sheetAtMaxExtent;

  bool get _effectiveCollapseOnAnyDownwardDrag =>
      _sheetMetrics?.collapseOnAnyDownwardDrag ??
      widget.collapseOnAnyDownwardDrag;

  @override
  void initState() {
    super.initState();
    _sort = widget.initialSort;
    _rebuildVisibleItems();
  }

  @override
  void didUpdateWidget(covariant ProxiesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.proxies != widget.proxies ||
        oldWidget.totalTopLevelProxies != widget.totalTopLevelProxies ||
        oldWidget.isProxyChainTag != widget.isProxyChainTag) {
      _rebuildVisibleItems();
    }
    if (oldWidget.initialSort != widget.initialSort &&
        widget.initialSort != _sort) {
      _sort = widget.initialSort;
      _rebuildVisibleItems();
    }
    if (!_effectiveSheetAtMaxExtent && _proxySheetHeaderScrollCollapse != 0) {
      _proxySheetHeaderScrollCollapse = 0;
    }
  }

  void _setSort(ProxySort value) {
    if (_sort == value) {
      return;
    }
    setState(() {
      _sort = value;
      _rebuildVisibleItems();
    });
    widget.onSortChanged?.call(value);
  }

  void _rebuildVisibleItems() {
    var topLevelCount = 0;
    final pinnedItems = <AppProxySummary>[];
    final visibleItems = <AppProxySummary>[];
    for (final proxy in widget.proxies) {
      final parentTag = proxy.parentGroupTag;
      if (parentTag != null && parentTag.isNotEmpty) {
        continue;
      }
      topLevelCount++;
      if (_isPinnedHeaderProxy(proxy)) {
        pinnedItems.add(proxy);
      } else {
        visibleItems.add(proxy);
      }
    }

    _sortItems(visibleItems);
    final displayedItems = _showAllProxies
        ? visibleItems
        : visibleItems.take(_kProxyListPreviewLimit).toList(growable: false);

    _visibleItems = [...pinnedItems, ...displayedItems];
    final effectiveTopLevelCount = widget.totalTopLevelProxies == null
        ? topLevelCount
        : widget.totalTopLevelProxies!.clamp(topLevelCount, 1 << 30).toInt();
    _hiddenCount = effectiveTopLevelCount - _visibleItems.length;
    if (!_visibleItems.any(_isExtraLowest)) {
      _showExtraLowests = false;
    }
    _invalidateVisibleEntries();
  }

  bool _isPrimarySynthetic(AppProxySummary proxy) =>
      proxy.tag == lowestProxyTag || proxy.tag == mixedProxyTag;

  bool _isExtraLowest(AppProxySummary proxy) =>
      proxy.tag == lowestOpenProxyTag || proxy.tag == lowestFreeProxyTag;

  bool _isPinnedHeaderProxy(AppProxySummary proxy) =>
      _isPrimarySynthetic(proxy) ||
      _isExtraLowest(proxy) ||
      _isProxyChain(proxy);

  List<_ProxyListEntry> _visibleEntries() {
    if (kDebugMode) {
      return developer.Timeline.timeSync(
        'ProxiesPage._visibleEntries',
        _visibleEntriesImpl,
        arguments: <String, Object?>{
          'visibleItems': _visibleItems.length,
          'hiddenCount': _hiddenCount,
          'embedded': widget.embedded,
        },
      );
    }
    return _visibleEntriesImpl();
  }

  List<_ProxyListEntry> _visibleEntriesImpl() {
    final cached = _visibleEntriesCache;
    if (cached != null &&
        identical(_visibleEntriesItemsCache, _visibleItems) &&
        _visibleEntriesSortCache == _sort &&
        _visibleEntriesExtraLowestsCache == _showExtraLowests &&
        _visibleEntriesCanAddChainCache == (widget.onAddProxyChain != null) &&
        _visibleEntriesChainPredicateCache == widget.isProxyChainTag &&
        _visibleEntriesHiddenCountCache == _hiddenCount) {
      return cached;
    }
    final primary = <AppProxySummary>[];
    final extraLowests = <AppProxySummary>[];
    final chains = <AppProxySummary>[];
    final rest = <AppProxySummary>[];
    for (final proxy in _visibleItems) {
      if (_isPrimarySynthetic(proxy)) {
        primary.add(proxy);
      } else if (_isExtraLowest(proxy)) {
        extraLowests.add(proxy);
      } else if (_isProxyChain(proxy)) {
        chains.add(proxy);
      } else {
        rest.add(proxy);
      }
    }
    int byPinnedOrder(AppProxySummary a, AppProxySummary b) =>
        pinnedProxyTagOrder(a.tag).compareTo(pinnedProxyTagOrder(b.tag));
    primary.sort(byPinnedOrder);
    extraLowests.sort(byPinnedOrder);
    final hasPinnedOverflow =
        extraLowests.isNotEmpty || widget.onAddProxyChain != null;
    final visibleChains = _showExtraLowests
        ? chains
        : const <AppProxySummary>[];
    final hasPinnedHeader =
        primary.isNotEmpty || visibleChains.isNotEmpty || hasPinnedOverflow;
    final entries = <_ProxyListEntry>[
      for (final proxy in primary) _ProxyListEntry.tile(proxy),
      if (hasPinnedOverflow && !_showExtraLowests)
        const _ProxyListEntry.moreLowests(),
      if (_showExtraLowests)
        for (final proxy in extraLowests) _ProxyListEntry.tile(proxy),
      for (final proxy in visibleChains) _ProxyListEntry.tile(proxy),
      if (_showExtraLowests && widget.onAddProxyChain != null)
        const _ProxyListEntry.addChain(),
      if (hasPinnedOverflow && _showExtraLowests)
        const _ProxyListEntry.moreLowests(),
      if (rest.isNotEmpty && hasPinnedHeader) const _ProxyListEntry.divider(),
      for (final proxy in rest) _ProxyListEntry.tile(proxy),
      if (_hiddenCount > 0) const _ProxyListEntry.moreProxies(),
    ];
    _visibleEntriesCache = entries;
    _visibleEntriesItemsCache = _visibleItems;
    _visibleEntriesSortCache = _sort;
    _visibleEntriesExtraLowestsCache = _showExtraLowests;
    _visibleEntriesCanAddChainCache = widget.onAddProxyChain != null;
    _visibleEntriesChainPredicateCache = widget.isProxyChainTag;
    _visibleEntriesHiddenCountCache = _hiddenCount;
    return entries;
  }

  void _invalidateVisibleEntries() {
    _visibleEntriesCache = null;
    _visibleEntriesItemsCache = null;
    _visibleEntriesSortCache = null;
    _visibleEntriesExtraLowestsCache = null;
    _visibleEntriesCanAddChainCache = null;
    _visibleEntriesChainPredicateCache = null;
    _visibleEntriesHiddenCountCache = null;
  }

  void _toggleExtraLowests() {
    if (widget.hapticEnabled) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _showExtraLowests = !_showExtraLowests;
      _invalidateVisibleEntries();
    });
  }

  void _showEveryProxy() {
    if (_showAllProxies) return;
    if (widget.hapticEnabled) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _showAllProxies = true;
      _rebuildVisibleItems();
    });
  }

  List<AppProxySummary> _groupChildren(AppProxySummary group) {
    if (group.childTags.isEmpty) {
      return const [];
    }
    final cachedChildren = widget.groupChildrenByTag[group.tag];
    if (cachedChildren != null) {
      final children = cachedChildren.toList(growable: false);
      _sortItems(children, keepLowestFirst: false);
      return children;
    }
    final childByTag = <String, AppProxySummary>{
      for (final proxy in widget.proxies)
        if (proxy.parentGroupTag == group.tag) proxy.tag: proxy,
    };
    final children = group.childTags
        .map((tag) => childByTag[tag])
        .whereType<AppProxySummary>()
        .toList(growable: false);
    _sortItems(children, keepLowestFirst: false);
    return children;
  }

  Future<void> _openGroupOutbounds(AppProxySummary group, Rect _) async {
    final children = _groupChildren(group);
    if (children.isEmpty) {
      return;
    }
    if (widget.hapticEnabled) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _groupSheetOpen = true;
    });
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          barrierDismissible: true,
          barrierColor: Colors.transparent,
          barrierLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
          transitionDuration: const Duration(milliseconds: 440),
          reverseTransitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (context, animation, secondaryAnimation) =>
              _GroupOutboundsSheet(
                group: group,
                children: children,
                selectedTag: widget.selectedTag,
                progressiveBlurEnabled: widget.progressiveBlurEnabled,
                runtimeStates: widget.runtimeStates,
                routeAnimation: animation,
                onSelected: widget.onSelected,
                outboundForTag: widget.outboundForTag,
                initialSort: _sort,
                onSortChanged: (value) {
                  if (_sort != value && mounted) {
                    setState(() {
                      _sort = value;
                      _rebuildVisibleItems();
                    });
                  }
                  widget.onSortChanged?.call(value);
                },
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return child;
          },
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _groupSheetOpen = false;
        });
      }
    }
  }

  Future<void> _openProxyShareSheet(AppProxySummary proxy) async {
    if (proxy.isGroup) {
      return;
    }
    final outbound = widget.outboundForTag?.call(proxy.tag);
    if (outbound == null) {
      return;
    }
    if (widget.hapticEnabled) {
      HapticFeedback.selectionClick();
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProxyShareSheet(proxy: proxy, outbound: outbound),
    );
  }

  void _sortItems(List<AppProxySummary> items, {bool keepLowestFirst = true}) {
    sortProxySummaries(items, _sort, keepPinnedFirst: keepLowestFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final theme = Theme.of(context);
    if (widget.embedded) {
      final sheetMetricsListenable = widget.sheetMetricsListenable;
      if (sheetMetricsListenable != null) {
        return ValueListenableBuilder<ProxyPanelMetrics>(
          valueListenable: sheetMetricsListenable,
          builder: (context, metrics, _) {
            return _buildEmbeddedSheet(
              context: context,
              l10n: l10n,
              theme: theme,
              sheetAtMaxExtent: metrics.atMaxExtent,
              sheetCanFillScreen: metrics.canFillScreen,
              sheetExtent: metrics.progress,
              progressiveBlurEnabled:
                  widget.progressiveBlurEnabled && !metrics.dragging,
            );
          },
        );
      }
      return _buildEmbeddedSheet(context: context, l10n: l10n, theme: theme);
    }

    final topPadding = appSystemStatusBarInset(context);
    final headerHeight = topPadding + kToolbarHeight;
    final footerHeight = appBottomNavigationTotalHeight(context);
    final listTopPadding = widget.progressiveBlurEnabled
        ? headerHeight + 8
        : 6.0;
    final listBottomPadding = footerHeight + 24;
    final headerBlurHeight = appHeaderBlurTotalHeight(context);

    return Scaffold(
      extendBodyBehindAppBar: widget.progressiveBlurEnabled,
      appBar: AppBar(
        title: Text(l10n.proxiesTitle),
        backgroundColor: widget.progressiveBlurEnabled
            ? Colors.transparent
            : theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: l10n.sort,
            onPressed: () => _showProxySortPicker(
              context,
              l10n: l10n,
              current: _sort,
              onSelected: _setSort,
            ),
            icon: const Icon(FluentIcons.arrow_sort_24_regular),
          ),
        ],
      ),
      body: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Stack(
          children: [
            AppProgressiveEdgeBlur(
              enabled: widget.progressiveBlurEnabled,
              headerHeight: headerBlurHeight,
              footerHeight: 0,
              sigma: 16,
              tintColor: theme.scaffoldBackgroundColor.withValues(
                alpha: theme.brightness == Brightness.dark ? .08 : .06,
              ),
              child: _buildProxyList(
                context: context,
                l10n: l10n,
                listTopPadding: listTopPadding,
                listBottomPadding: listBottomPadding,
              ),
            ),
            if (widget.connected)
              Positioned(
                right: 24,
                bottom: footerHeight + 24,
                child: FloatingActionButton.small(
                  onPressed: () => widget.onUrlTest(),
                  tooltip: l10n.urlTestTitle,
                  child: const Icon(FluentIcons.flash_24_filled),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbeddedSheet({
    required BuildContext context,
    required AppLocalizations l10n,
    required ThemeData theme,
    bool? sheetAtMaxExtent,
    bool? sheetCanFillScreen,
    double? sheetExtent,
    bool? progressiveBlurEnabled,
  }) {
    final effectiveSheetAtMaxExtent =
        sheetAtMaxExtent ?? widget.sheetAtMaxExtent;
    final effectiveSheetCanFillScreen =
        sheetCanFillScreen ?? widget.sheetCanFillScreen;
    final effectiveSheetExtent = sheetExtent ?? widget.sheetExtent;
    final effectiveProgressiveBlurEnabled =
        progressiveBlurEnabled ?? widget.progressiveBlurEnabled;
    final bottomInset = appSystemNavigationBarInset(context);
    final progressRange =
        widget.expandedHeaderExtent - widget.collapsedSheetExtent;
    final headerProgress = progressRange <= 0
        ? 1.0
        : ((effectiveSheetExtent - widget.collapsedSheetExtent) / progressRange)
              .clamp(0.0, 1.0)
              .toDouble();
    final listProgress = ((headerProgress - .16) / .44)
        .clamp(0.0, 1.0)
        .toDouble();
    final headerScrollCollapse = effectiveSheetAtMaxExtent
        ? _proxySheetHeaderScrollCollapse
        : 0.0;
    final headerHeight = _proxySheetHeaderHeightForCollapse(
      headerScrollCollapse,
    );
    final compactListTopPadding = max(headerHeight + 6, 84).toDouble();
    final listTopPadding = lerpDouble(
      _kProxySheetListTopReserve,
      compactListTopPadding,
      ((headerProgress - .52) / .36).clamp(0.0, 1.0).toDouble(),
    )!;
    final listMounted =
        effectiveSheetAtMaxExtent || headerProgress > .22 || listProgress > 0;
    final listScrollEnabled = effectiveSheetAtMaxExtent || headerProgress > .94;
    final list = listMounted
        ? Builder(
            builder: (context) {
              final entries = _visibleEntries();
              return ListView.builder(
                controller: widget.scrollController,
                physics: listScrollEnabled
                    ? const _ProxySheetScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      )
                    : const NeverScrollableScrollPhysics(),
                itemExtent: _kProxySheetRowExtent,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                addSemanticIndexes: false,
                padding: EdgeInsets.only(
                  top: listTopPadding,
                  bottom: bottomInset + 20,
                ),
                itemCount: widget.proxies.isEmpty ? 1 : entries.length,
                itemBuilder: (context, index) {
                  if (widget.proxies.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.noProxies,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    );
                  }

                  final entry = entries[index];
                  return IgnorePointer(
                    ignoring: listProgress < .12,
                    child: _buildEmbeddedEntry(
                      context: context,
                      l10n: l10n,
                      entry: entry,
                    ),
                  );
                },
              );
            },
          )
        : null;
    final header = _ProxySheetHeader(
      height: headerHeight,
      progress: headerProgress,
      scrollCollapse: headerScrollCollapse,
      canFillScreen: effectiveSheetCanFillScreen,
      activeProxy: widget.activeProxy,
      activeProxyHideIp: widget.activeProxyHideIp,
      l10n: l10n,
      sort: _sort,
      connected: widget.connected,
      hapticEnabled: widget.hapticEnabled,
      speedBytesPerSecond: widget.speedBytesPerSecond,
      trafficBytes: widget.trafficBytes,
      trafficListenable: widget.trafficListenable,
      onSortSelected: _setSort,
      onUrlTest: widget.onUrlTest,
      onRefreshIp: widget.onActiveProxyIpRefresh,
      onTap: widget.onHeaderTap,
      onInteractionStart: widget.onInteractionStart,
      onVerticalDragUpdate: widget.onHeaderDragUpdate,
      onVerticalDragEnd: widget.onHeaderDragEnd,
    );
    final pinnedHeader = _ProxySheetHeaderBackdrop(
      enabled:
          effectiveProgressiveBlurEnabled &&
          !_groupSheetOpen &&
          headerProgress >= _kProxySheetHeaderBlurStart,
      cornerRadius: widget.sheetCornerRadius,
      height: headerHeight,
      child: header,
    );
    final sheetBody = RepaintBoundary(
      child: Stack(
        children: [
          if (list != null)
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handleEmbeddedPointerDown,
              onPointerMove: _handleEmbeddedPointerMove,
              onPointerUp: _handleEmbeddedPointerEnd,
              onPointerCancel: _handleEmbeddedPointerCancel,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleEmbeddedScrollNotification,
                child: RepaintBoundary(child: list),
              ),
            ),
          Positioned(left: 0, right: 0, top: 0, child: pinnedHeader),
        ],
      ),
    );
    return Material(
      color: theme.scaffoldBackgroundColor,
      elevation: 0,
      shadowColor: Colors.transparent,
      clipBehavior: Clip.none,
      child: sheetBody,
    );
  }

  bool _handleEmbeddedScrollNotification(ScrollNotification notification) {
    _updateProxySheetHeaderScrollCollapse(notification.metrics);
    if (_pendingProxySheetCarryVelocity == null) {
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _startProxySheetCarryIfListSettledAtTop();
      if (notification is ScrollEndNotification) {
        _pendingProxySheetCarryVelocity = null;
      }
    }
    return false;
  }

  void _updateProxySheetHeaderScrollCollapse(ScrollMetrics metrics) {
    final nextCollapse = _effectiveSheetAtMaxExtent
        ? ((metrics.pixels - metrics.minScrollExtent) /
                  _kProxySheetHeaderCollapseDistance)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;
    if ((nextCollapse - _proxySheetHeaderScrollCollapse).abs() < 0.01) {
      return;
    }
    setState(() {
      _proxySheetHeaderScrollCollapse = nextCollapse;
    });
  }

  void _handleEmbeddedPointerDown(PointerDownEvent event) {
    widget.onInteractionStart?.call();
    _pendingProxySheetCarryVelocity = null;
    _resetProxySheetDragTracking();
    final headerHitHeight = _proxySheetHeaderHeightForCollapse(
      _effectiveSheetAtMaxExtent ? _proxySheetHeaderScrollCollapse : 0,
    );
    if (event.localPosition.dy <= headerHitHeight) {
      return;
    }
    _proxySheetPointerStartedInList = true;
    _proxySheetDragVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handleEmbeddedPointerMove(PointerMoveEvent event) {
    if (!_proxySheetPointerStartedInList) {
      return;
    }
    final deltaY = event.delta.dy;
    _proxySheetPointerDeltaY += deltaY;
    _proxySheetDragVelocityTracker?.addPosition(
      event.timeStamp,
      event.position,
    );
    final shouldCollapseFromAnyScroll =
        _effectiveCollapseOnAnyDownwardDrag && deltaY > 0;
    if (deltaY == 0 ||
        (!_embeddedListAtTop() && !shouldCollapseFromAnyScroll)) {
      return;
    }
    if (_effectiveSheetAtMaxExtent && deltaY < 0) {
      return;
    }
    _proxySheetDragMoved = true;
    widget.onHeaderDragUpdate?.call(
      DragUpdateDetails(
        sourceTimeStamp: event.timeStamp,
        delta: event.delta,
        primaryDelta: deltaY,
        globalPosition: event.position,
        localPosition: event.localPosition,
      ),
    );
  }

  void _handleEmbeddedPointerEnd(PointerUpEvent event) {
    final velocity =
        _proxySheetDragVelocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0;
    if (!_proxySheetDragMoved) {
      if (_proxySheetPointerStartedInList &&
          _effectiveSheetAtMaxExtent &&
          !_embeddedListAtTop() &&
          velocity > _kProxySheetCarryMinVelocity &&
          _proxySheetPointerDeltaY > _kProxySheetCarryMinDistance) {
        final residualVelocity = _proxySheetResidualVelocityAtTop(velocity);
        if (residualVelocity > _kProxySheetCarryMinResidualVelocity) {
          _pendingProxySheetCarryVelocity = residualVelocity;
        }
      }
      _resetProxySheetDragTracking();
      return;
    }
    _resetProxySheetDragTracking();
    widget.onHeaderDragEnd?.call(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
        primaryVelocity: velocity,
      ),
    );
  }

  void _handleEmbeddedPointerCancel(PointerCancelEvent event) {
    if (_proxySheetDragMoved) {
      widget.onHeaderDragEnd?.call(DragEndDetails());
    }
    _resetProxySheetDragTracking();
  }

  void _resetProxySheetDragTracking() {
    _proxySheetDragVelocityTracker = null;
    _proxySheetDragMoved = false;
    _proxySheetPointerStartedInList = false;
    _proxySheetPointerDeltaY = 0;
  }

  void _startProxySheetCarryIfListSettledAtTop() {
    final velocity = _pendingProxySheetCarryVelocity;
    if (velocity == null || !_embeddedListAtTop()) {
      return;
    }
    _pendingProxySheetCarryVelocity = null;
    widget.onHeaderDragEnd?.call(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
        primaryVelocity: velocity,
      ),
    );
  }

  double _proxySheetResidualVelocityAtTop(double pointerVelocity) {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) {
      return 0;
    }
    var residualVelocity = 0.0;
    for (final position in controller.positions) {
      final scrollVelocity = -pointerVelocity;
      if (scrollVelocity >= 0) {
        continue;
      }
      final simulation = FrictionSimulation(
        _kProxySheetFrictionDrag,
        position.pixels,
        scrollVelocity,
      );
      if (simulation.finalX > position.minScrollExtent) {
        continue;
      }
      final timeAtTop = simulation.timeAtX(position.minScrollExtent);
      if (!timeAtTop.isFinite) {
        continue;
      }
      final velocityAtTop = -simulation.dx(timeAtTop);
      if (velocityAtTop > residualVelocity) {
        residualVelocity = velocityAtTop;
      }
    }
    return residualVelocity
        .clamp(0.0, _kProxySheetMaxSpringTransferVelocity)
        .toDouble();
  }

  bool _embeddedListAtTop() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) {
      return true;
    }
    return controller.positions.every(
      (position) => position.pixels <= position.minScrollExtent + 0.5,
    );
  }

  double _proxySheetHeaderHeightForCollapse(double collapse) {
    final t = Curves.easeOutCubic.transform(
      collapse.clamp(0.0, 1.0).toDouble(),
    );
    return lerpDouble(
      _kProxySheetHeaderHeight,
      _kProxySheetCompactHeaderHeight,
      t,
    )!;
  }

  Widget _buildProxyList({
    required BuildContext context,
    required AppLocalizations l10n,
    required double listTopPadding,
    required double listBottomPadding,
  }) {
    final theme = Theme.of(context);
    if (widget.proxies.isEmpty) {
      return Center(
        child: Text(l10n.noProxies, style: theme.textTheme.titleMedium),
      );
    }
    final entries = _visibleEntries();
    return ListView.builder(
      padding: EdgeInsets.only(top: listTopPadding, bottom: listBottomPadding),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return _buildEntry(context: context, l10n: l10n, entry: entries[index]);
      },
    );
  }

  Widget _buildEntry({
    required BuildContext context,
    required AppLocalizations l10n,
    required _ProxyListEntry entry,
  }) {
    switch (entry.type) {
      case _ProxyListEntryType.tile:
        final proxy = entry.proxy!;
        Widget buildTile(ProxyRuntimeVisualState? state) => ProxyTile(
          proxy: proxy,
          runtimeState: state,
          selected: proxy.tag == widget.selectedTag,
          highlighted: proxy.highlighted,
          animate: !widget.embedded,
          onTap: () => widget.onSelected(proxy.tag),
          onLongPress: proxy.isGroup
              ? null
              : _isProxyChain(proxy)
              ? () => _openProxyChainActionSheet(proxy)
              : () => _openProxyShareSheet(proxy),
          onOpenGroup: proxy.isGroup
              ? (rect) => _openGroupOutbounds(proxy, rect)
              : null,
        );
        final runtimeStates = widget.runtimeStates;
        if (!widget.embedded || runtimeStates == null) {
          return buildTile(null);
        }
        return ValueListenableBuilder<ProxyRuntimeVisualState?>(
          valueListenable: runtimeStates.listenableFor(proxy.tag),
          builder: (context, state, _) => buildTile(state),
        );
      case _ProxyListEntryType.moreLowests:
        return _MoreLowestsTile(onTap: _toggleExtraLowests);
      case _ProxyListEntryType.addChain:
        return _AddProxyChainTile(onTap: _openAddProxyChainSheet);
      case _ProxyListEntryType.divider:
        return const _ProxyListDivider();
      case _ProxyListEntryType.moreProxies:
        return _MoreProxiesTile(
          label: l10n.moreProxies(_hiddenCount),
          onTap: _showEveryProxy,
        );
    }
  }

  Widget _buildEmbeddedEntry({
    required BuildContext context,
    required AppLocalizations l10n,
    required _ProxyListEntry entry,
  }) {
    return _buildEntry(context: context, l10n: l10n, entry: entry);
  }

  Future<void> _openAddProxyChainSheet() async {
    final callback = widget.onAddProxyChain;
    if (callback == null) {
      return;
    }
    final localTargets = widget.proxies
        .where(
          (proxy) =>
              !proxy.isGroup &&
              !_isProxyChain(proxy) &&
              !isLowestProxyTag(proxy.tag) &&
              !isMixedProxyTag(proxy.tag),
        )
        .toList(growable: false);
    final sources = await widget.loadProxyChainTargetSources?.call();
    if (!mounted) {
      return;
    }
    final detours = widget.proxies
        .where((proxy) => !_isProxyChain(proxy))
        .toList(growable: false);
    if (sources == null ||
        sources.isEmpty ||
        widget.loadProxyChainTargetsForSource == null) {
      if (localTargets.isEmpty) {
        return;
      }
      final selection = await showModalBottomSheet<_ProxyChainSelection>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _AddProxyChainSheet.staticTargets(
          detours: detours,
          targets: localTargets,
        ),
      );
      if (selection != null) {
        await callback(selection.detourTag, selection.targetTag);
      }
      return;
    }
    final selection = await showModalBottomSheet<_ProxyChainSelection>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AddProxyChainSheet(
        detours: detours,
        sources: sources,
        loadTargetsForSource: widget.loadProxyChainTargetsForSource!,
      ),
    );
    if (selection == null) {
      return;
    }
    await callback(selection.detourTag, selection.targetTag);
  }

  Future<void> _openProxyChainActionSheet(AppProxySummary proxy) async {
    if (widget.onRemoveProxyChain == null &&
        widget.onChangeProxyChainDetour == null &&
        widget.onRenameProxyChain == null) {
      return;
    }
    final action = await showModalBottomSheet<_ProxyChainAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(proxy.displayName),
              subtitle: Text(proxy.detailText),
            ),
            if (widget.onChangeProxyChainDetour != null)
              ListTile(
                leading: const Icon(FluentIcons.arrow_routing_24_regular),
                title: const Text('Change first hop'),
                onTap: () => Navigator.of(context).pop(_ProxyChainAction.edit),
              ),
            if (widget.onRenameProxyChain != null)
              ListTile(
                leading: const Icon(FluentIcons.edit_24_regular),
                title: const Text('Rename'),
                onTap: () =>
                    Navigator.of(context).pop(_ProxyChainAction.rename),
              ),
            ListTile(
              leading: const Icon(FluentIcons.delete_24_regular),
              title: const Text('Remove proxy chain'),
              onTap: () => Navigator.of(context).pop(_ProxyChainAction.remove),
            ),
          ],
        ),
      ),
    );
    if (action == _ProxyChainAction.remove) {
      await widget.onRemoveProxyChain?.call(proxy.tag);
    } else if (action == _ProxyChainAction.edit) {
      await _openChangeProxyChainDetourSheet(proxy);
    } else if (action == _ProxyChainAction.rename) {
      await _openRenameProxyChainSheet(proxy);
    }
  }

  Future<void> _openRenameProxyChainSheet(AppProxySummary proxy) async {
    final callback = widget.onRenameProxyChain;
    if (callback == null) {
      return;
    }
    final controller = TextEditingController(text: proxy.displayName);
    final name = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rename proxy chain',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await callback(proxy.tag, name);
  }

  Future<void> _openChangeProxyChainDetourSheet(AppProxySummary proxy) async {
    final callback = widget.onChangeProxyChainDetour;
    if (callback == null) {
      return;
    }
    final detours = widget.proxies
        .where((candidate) => !_isProxyChain(candidate))
        .toList(growable: false);
    if (detours.isEmpty) {
      return;
    }
    final detourTag = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _ChangeProxyChainDetourSheet(detours: detours),
    );
    if (detourTag == null || detourTag.trim().isEmpty) {
      return;
    }
    await callback(proxy.tag, detourTag);
  }
}

enum _ProxyListEntryType { tile, moreLowests, addChain, divider, moreProxies }

class _ProxyChainSelection {
  const _ProxyChainSelection({
    required this.detourTag,
    required this.targetTag,
  });

  final String detourTag;
  final String targetTag;
}

class _ChangeProxyChainDetourSheet extends StatelessWidget {
  const _ChangeProxyChainDetourSheet({required this.detours});

  final List<AppProxySummary> detours;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'Change first hop',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final proxy in detours)
            ListTile(
              leading: CountryFlagBadge(countryCode: proxy.countryCode),
              title: Text(proxy.displayName, overflow: TextOverflow.ellipsis),
              subtitle: Text(proxy.detailText, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).pop(proxy.tag),
            ),
        ],
      ),
    );
  }
}

class _AddProxyChainSheet extends StatefulWidget {
  const _AddProxyChainSheet({
    required this.detours,
    required this.sources,
    required this.loadTargetsForSource,
  }) : staticTargets = const [];

  const _AddProxyChainSheet.staticTargets({
    required this.detours,
    required List<AppProxySummary> targets,
  }) : sources = const [],
       staticTargets = targets,
       loadTargetsForSource = null;

  final List<AppProxySummary> detours;
  final List<AppProfileSummary> sources;
  final List<AppProxySummary> staticTargets;
  final Future<List<AppProxySummary>> Function(String subscriptionId)?
  loadTargetsForSource;

  @override
  State<_AddProxyChainSheet> createState() => _AddProxyChainSheetState();
}

class _AddProxyChainSheetState extends State<_AddProxyChainSheet> {
  static const int _visibleTargetLimit = 160;

  late String _detourTag = widget.detours.first.tag;
  late String _sourceId = widget.sources.isEmpty ? '' : widget.sources.first.id;
  final TextEditingController _searchController = TextEditingController();
  List<AppProxySummary> _targets = const [];
  String? _targetTag;
  bool _loading = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.staticTargets.isNotEmpty) {
      _targets = widget.staticTargets;
      _targetTag = _targets.first.tag;
    } else {
      _loadTargets();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    final loader = widget.loadTargetsForSource;
    final sourceId = _sourceId;
    if (loader == null || sourceId.isEmpty) {
      return;
    }
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _targets = const [];
      _targetTag = null;
    });
    final targets = await loader(sourceId);
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    setState(() {
      _targets = targets;
      _targetTag = targets.isEmpty ? null : targets.first.tag;
      _loading = false;
    });
  }

  List<AppProxySummary> _visibleTargets() {
    final query = _searchController.text.trim().toLowerCase();
    final result = <AppProxySummary>[];
    for (final proxy in _targets) {
      if (query.isNotEmpty &&
          !proxy.displayName.toLowerCase().contains(query) &&
          !proxy.detailText.toLowerCase().contains(query) &&
          !proxy.countryCode.toLowerCase().contains(query) &&
          !proxy.server.toLowerCase().contains(query)) {
        continue;
      }
      result.add(proxy);
      if (result.length >= _visibleTargetLimit) {
        break;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleTargets = _visibleTargets();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add proxy chain', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _detourTag,
                decoration: const InputDecoration(labelText: 'First hop'),
                items: widget.detours
                    .map(
                      (proxy) => DropdownMenuItem(
                        value: proxy.tag,
                        child: Text(
                          proxy.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _detourTag = value);
                  }
                },
              ),
              if (widget.sources.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _sourceId,
                  decoration: const InputDecoration(labelText: 'Subscription'),
                  items: widget.sources
                      .map(
                        (source) => DropdownMenuItem(
                          value: source.id,
                          child: Text(
                            source.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null || value == _sourceId) {
                      return;
                    }
                    setState(() {
                      _sourceId = value;
                      _searchController.clear();
                    });
                    _loadTargets();
                  },
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Exit proxy',
                  prefixIcon: Icon(FluentIcons.search_24_regular),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : visibleTargets.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing found',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: visibleTargets.length,
                        itemBuilder: (context, index) {
                          final proxy = visibleTargets[index];
                          final selected = proxy.tag == _targetTag;
                          return ListTile(
                            onTap: () => setState(() => _targetTag = proxy.tag),
                            leading: CountryFlagBadge(
                              countryCode: proxy.countryCode,
                            ),
                            title: Text(
                              proxy.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              proxy.detailText,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? Icon(
                                    FluentIcons.checkmark_circle_24_filled,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _targetTag == null
                    ? null
                    : () => Navigator.of(context).pop(
                        _ProxyChainSelection(
                          detourTag: _detourTag,
                          targetTag: _targetTag!,
                        ),
                      ),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProxyListEntry {
  const _ProxyListEntry._(this.type, [this.proxy]);

  const _ProxyListEntry.tile(AppProxySummary proxy)
    : this._(_ProxyListEntryType.tile, proxy);
  const _ProxyListEntry.moreLowests() : this._(_ProxyListEntryType.moreLowests);
  const _ProxyListEntry.addChain() : this._(_ProxyListEntryType.addChain);
  const _ProxyListEntry.divider() : this._(_ProxyListEntryType.divider);
  const _ProxyListEntry.moreProxies() : this._(_ProxyListEntryType.moreProxies);

  final _ProxyListEntryType type;
  final AppProxySummary? proxy;
}

class _ProxySheetScrollPhysics extends BouncingScrollPhysics {
  const _ProxySheetScrollPhysics({super.parent});

  @override
  _ProxySheetScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ProxySheetScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      return value - position.pixels;
    }
    if (value < position.minScrollExtent &&
        position.minScrollExtent < position.pixels) {
      return value - position.minScrollExtent;
    }
    return super.applyBoundaryConditions(position, value);
  }
}

class _ProxySheetHeaderBackdrop extends StatelessWidget {
  const _ProxySheetHeaderBackdrop({
    required this.enabled,
    required this.cornerRadius,
    required this.height,
    required this.child,
  });

  final bool enabled;
  final double cornerRadius;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.scaffoldBackgroundColor;
    if (!enabled) {
      return ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cornerRadius)),
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: .36),
                  color.withValues(alpha: .22),
                  Colors.transparent,
                ],
                stops: const [0, 1, 1],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: child,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(cornerRadius)),
      child: SizedBox(
        height: height,
        child: RepaintBoundary(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (enabled)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: height,
                  child: const IgnorePointer(
                    child: _ProxySheetProgressiveBlur(),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: enabled ? .54 : .36),
                          color.withValues(alpha: enabled ? .32 : .22),
                          Colors.transparent,
                        ],
                        stops: const [0, 1, 1],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(left: 0, right: 0, top: 0, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight header merge effect for Android cool/balanced paths.
class _ProxySheetProgressiveBlur extends StatelessWidget {
  const _ProxySheetProgressiveBlur();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.94),
            color.withValues(alpha: 0.70),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

class _ProxySheetHeader extends StatelessWidget {
  const _ProxySheetHeader({
    required this.height,
    required this.progress,
    required this.scrollCollapse,
    required this.canFillScreen,
    required this.activeProxy,
    required this.activeProxyHideIp,
    required this.l10n,
    required this.sort,
    required this.connected,
    required this.hapticEnabled,
    required this.speedBytesPerSecond,
    required this.trafficBytes,
    required this.trafficListenable,
    required this.onSortSelected,
    required this.onUrlTest,
    required this.onRefreshIp,
    required this.onTap,
    required this.onInteractionStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final double height;
  final double progress;
  final double scrollCollapse;
  final bool canFillScreen;
  final AppProxySummary? activeProxy;
  final bool activeProxyHideIp;
  final AppLocalizations l10n;
  final ProxySort sort;
  final bool connected;
  final bool hapticEnabled;
  final double speedBytesPerSecond;
  final double trafficBytes;
  final ValueListenable<TrafficUiSnapshot>? trafficListenable;
  final ValueChanged<ProxySort> onSortSelected;
  final Future<void> Function() onUrlTest;
  final VoidCallback? onRefreshIp;
  final VoidCallback? onTap;
  final VoidCallback? onInteractionStart;
  final ValueChanged<DragUpdateDetails>? onVerticalDragUpdate;
  final ValueChanged<DragEndDetails>? onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toolbarOpacity = ((progress - .48) / .28).clamp(0.0, 1.0).toDouble();
    final headerOpacity = Curves.easeOutCubic.transform(toolbarOpacity);
    final collapse = Curves.easeOutCubic.transform(
      scrollCollapse.clamp(0.0, 1.0).toDouble(),
    );
    final handleOpacity = canFillScreen
        ? (1 - Curves.easeInCubic.transform(scrollCollapse))
              .clamp(0.0, 1.0)
              .toDouble()
        : (1 - collapse * .72).clamp(0.0, 1.0).toDouble();
    final activeProxyFade = (1 - (progress / .34)).clamp(0.0, 1.0).toDouble();
    final activeProxyOpacity = Curves.easeOutCubic.transform(activeProxyFade);
    final showHandle = handleOpacity >= .08;
    final showActiveProxy = activeProxy != null && activeProxyOpacity >= .02;
    final showToolbar = headerOpacity >= .02;
    final toolbarTop = lerpDouble(18, 8, collapse)!;
    final toolbarBottom = lerpDouble(0, 4, collapse)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onInteractionStart?.call(),
      onTap: onTap,
      onVerticalDragStart: (_) => onInteractionStart?.call(),
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (showHandle)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: .34,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            if (showActiveProxy)
              Positioned(
                left: 16,
                right: 16,
                top: 24,
                bottom: 4,
                child: IgnorePointer(
                  ignoring: activeProxyOpacity < .85,
                  child: Opacity(
                    opacity: activeProxyOpacity,
                    child: trafficListenable == null
                        ? _ActiveProxyLabel(
                            connected: connected,
                            proxy: activeProxy!,
                            hideIp: activeProxyHideIp,
                            hapticEnabled: hapticEnabled,
                            speedBytesPerSecond: speedBytesPerSecond,
                            trafficBytes: trafficBytes,
                            unknownText: '—',
                            onRefreshIp: onRefreshIp,
                          )
                        : ValueListenableBuilder<TrafficUiSnapshot>(
                            valueListenable: trafficListenable!,
                            builder: (context, traffic, _) {
                              return _ActiveProxyLabel(
                                connected: connected,
                                proxy: activeProxy!,
                                hideIp: activeProxyHideIp,
                                hapticEnabled: hapticEnabled,
                                speedBytesPerSecond:
                                    traffic.speedBytesPerSecond,
                                trafficBytes: traffic.trafficBytes,
                                unknownText: '—',
                                onRefreshIp: onRefreshIp,
                              );
                            },
                          ),
                  ),
                ),
              ),
            if (showToolbar) ...[
              Positioned(
                left: 16,
                right: 16,
                top: toolbarTop,
                bottom: toolbarBottom,
                child: Opacity(
                  opacity: headerOpacity,
                  child: Center(
                    child: Text(
                      l10n.proxiesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: toolbarTop,
                bottom: toolbarBottom,
                child: Opacity(
                  opacity: headerOpacity,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: onTap,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      icon: const Icon(FluentIcons.chevron_left_24_regular),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: toolbarTop,
                bottom: toolbarBottom,
                child: Opacity(
                  opacity: headerOpacity,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (connected)
                          IconButton(
                            onPressed: () => onUrlTest(),
                            tooltip: l10n.urlTestTitle,
                            icon: const Icon(FluentIcons.flash_24_filled),
                          ),
                        IconButton(
                          tooltip: l10n.sort,
                          onPressed: () => _showProxySortPicker(
                            context,
                            l10n: l10n,
                            current: sort,
                            onSelected: onSortSelected,
                          ),
                          icon: const Icon(FluentIcons.arrow_sort_24_regular),
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
    );
  }
}

class _ActiveProxyLabel extends StatelessWidget {
  const _ActiveProxyLabel({
    required this.connected,
    required this.proxy,
    required this.hideIp,
    required this.hapticEnabled,
    required this.speedBytesPerSecond,
    required this.trafficBytes,
    required this.unknownText,
    required this.onRefreshIp,
  });

  final bool connected;
  final AppProxySummary proxy;
  final bool hideIp;
  final bool hapticEnabled;
  final double speedBytesPerSecond;
  final double trafficBytes;
  final String unknownText;
  final VoidCallback? onRefreshIp;

  String _maskIp(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.*.*';
    }
    if (ip.length > 8) {
      return '${ip.substring(0, ip.length ~/ 2)}****';
    }
    return ip;
  }

  String get _displayIp {
    if (!connected) return '—';
    final ip = proxy.ip;
    if (ip.isEmpty) return unknownText;
    if (hideIp) return _maskIp(ip);
    return ip;
  }

  void _refreshIp() {
    if (!connected || onRefreshIp == null) return;
    if (hapticEnabled) {
      HapticFeedback.lightImpact();
    }
    onRefreshIp?.call();
  }

  Widget _ipDisplay(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    if (connected && proxy.ipChecking) {
      return IpRefreshDots(
        key: const ValueKey('ip-refresh-checking'),
        color: color,
      );
    }
    return Text(
      _displayIp,
      key: ValueKey(_displayIp),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speedText = formatSpeed(connected ? speedBytesPerSecond : 0);
    final trafficText = formatBytes(connected ? trafficBytes : 0);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 74),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CountryFlagBadge(countryCode: proxy.countryCode, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerLeft,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previousChildren, ?currentChild],
                          );
                        },
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.12),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          proxy.displayName,
                          key: ValueKey(proxy.displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: connected ? _refreshIp : null,
                    child: SizedBox(
                      height: 24,
                      width: double.infinity,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.centerLeft,
                              children: [...previousChildren, ?currentChild],
                            );
                          },
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.12),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _ipDisplay(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActiveProxyStatLine(
                  icon: FluentIcons.arrow_download_20_regular,
                  text: speedText,
                ),
                const SizedBox(height: 8),
                _ActiveProxyStatLine(
                  icon: FluentIcons.arrow_bidirectional_up_down_20_regular,
                  text: trafficText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveProxyStatLine extends StatelessWidget {
  const _ActiveProxyStatLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
      ],
    );
  }
}

class _MoreProxiesTile extends StatelessWidget {
  const _MoreProxiesTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreLowestsTile extends StatelessWidget {
  const _MoreLowestsTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Icon(
              FluentIcons.more_horizontal_24_regular,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddProxyChainTile extends StatelessWidget {
  const _AddProxyChainTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                FluentIcons.link_add_24_regular,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '+ add proxy chain',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProxyListDivider extends StatelessWidget {
  const _ProxyListDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _GroupOutboundsSheet extends StatelessWidget {
  const _GroupOutboundsSheet({
    required this.group,
    required this.children,
    required this.selectedTag,
    required this.progressiveBlurEnabled,
    this.runtimeStates,
    required this.routeAnimation,
    required this.onSelected,
    this.outboundForTag,
    required this.initialSort,
    this.onSortChanged,
  });

  final AppProxySummary group;
  final List<AppProxySummary> children;
  final String selectedTag;
  final bool progressiveBlurEnabled;
  final ProxyRuntimeVisualStore? runtimeStates;
  final Animation<double> routeAnimation;
  final ValueChanged<String> onSelected;
  final Outbound? Function(String tag)? outboundForTag;
  final ProxySort initialSort;
  final ValueChanged<ProxySort>? onSortChanged;

  @override
  Widget build(BuildContext context) {
    return _GroupOutboundsSheetBody(
      group: group,
      children: children,
      selectedTag: selectedTag,
      progressiveBlurEnabled: progressiveBlurEnabled,
      runtimeStates: runtimeStates,
      routeAnimation: routeAnimation,
      onSelected: onSelected,
      outboundForTag: outboundForTag,
      initialSort: initialSort,
      onSortChanged: onSortChanged,
    );
  }
}

class _GroupOutboundsSheetBody extends StatefulWidget {
  const _GroupOutboundsSheetBody({
    required this.group,
    required this.children,
    required this.selectedTag,
    required this.progressiveBlurEnabled,
    this.runtimeStates,
    required this.routeAnimation,
    required this.onSelected,
    this.outboundForTag,
    required this.initialSort,
    this.onSortChanged,
  });

  final AppProxySummary group;
  final List<AppProxySummary> children;
  final String selectedTag;
  final bool progressiveBlurEnabled;
  final ProxyRuntimeVisualStore? runtimeStates;
  final Animation<double> routeAnimation;
  final ValueChanged<String> onSelected;
  final Outbound? Function(String tag)? outboundForTag;
  final ProxySort initialSort;
  final ValueChanged<ProxySort>? onSortChanged;

  @override
  State<_GroupOutboundsSheetBody> createState() =>
      _GroupOutboundsSheetBodyState();
}

class _GroupOutboundsSheetBodyState extends State<_GroupOutboundsSheetBody>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _maxSheetSize = 1.0;
  static const _sheetMinHeight = _kProxySheetHeaderHeight;
  static const _sheetStatusBarGap = 8.0;
  static const _sheetSettleCloseRatio = .857;
  static const _sheetCompactSettleCloseRatio = .64;
  static const _sheetInertiaMinVelocity = 90.0;
  static const _sheetMaxSpringVelocity = 5000.0;
  static const _predictiveBackLiveMaxProgress = .88;
  static const _predictiveBackSettleMinDuration = Duration(milliseconds: 110);
  static const _predictiveBackSettleMaxDuration = Duration(milliseconds: 260);
  static final SpringDescription _sheetSpring =
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: 1.1);

  final ScrollController _scrollController = ScrollController();
  late ProxySort _sort;
  late String _selectedTag;
  List<AppProxySummary>? _sortedChildrenCache;
  ProxySort? _sortedChildrenSort;
  AnimationController? _sheetInertiaController;
  AnimationController? _predictiveBackSettleController;
  VelocityTracker? _sheetDragVelocityTracker;
  double? _pendingSheetCarryVelocity;
  double _sheetSize = _maxSheetSize;
  int _sheetDragDirection = 0;
  bool _sheetDragMoved = false;
  bool _sheetPointerStartedInList = false;
  double _sheetPointerDeltaY = 0;
  bool _predictiveBackInProgress = false;
  double _predictiveBackProgress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sort = widget.initialSort;
    _selectedTag = widget.selectedTag;
  }

  @override
  void didUpdateWidget(covariant _GroupOutboundsSheetBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children != widget.children) {
      _sortedChildrenCache = null;
      _sortedChildrenSort = null;
    }
    if (oldWidget.selectedTag != widget.selectedTag) {
      _selectedTag = widget.selectedTag;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _predictiveBackSettleController?.dispose();
    _sheetInertiaController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !mounted) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) {
      return false;
    }
    _cancelSheetInertia();
    _cancelPredictiveBackSettle();
    setState(() {
      _predictiveBackInProgress = true;
      _predictiveBackProgress = _livePredictiveBackProgress(backEvent);
    });
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_predictiveBackInProgress || !mounted) {
      return;
    }
    _cancelPredictiveBackSettle();
    setState(() {
      _predictiveBackProgress = _livePredictiveBackProgress(backEvent);
    });
  }

  @override
  void handleCancelBackGesture() {
    if (!_predictiveBackInProgress || !mounted) {
      return;
    }
    _animatePredictiveBackSettle(
      target: 0,
      curve: Curves.easeOutCubic,
      onComplete: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _predictiveBackInProgress = false;
          _predictiveBackProgress = 0;
        });
      },
    );
  }

  @override
  void handleCommitBackGesture() {
    if (!_predictiveBackInProgress || !mounted) {
      return;
    }
    _animatePredictiveBackSettle(
      target: 1,
      curve: Curves.easeOutCubic,
      onComplete: () {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop();
      },
    );
  }

  double _livePredictiveBackProgress(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent) {
      return 0;
    }
    return backEvent.progress
        .clamp(0.0, _predictiveBackLiveMaxProgress)
        .toDouble();
  }

  void _animatePredictiveBackSettle({
    required double target,
    required Curve curve,
    required VoidCallback onComplete,
  }) {
    _cancelPredictiveBackSettle();
    final start = _predictiveBackProgress.clamp(0.0, 1.0).toDouble();
    final end = target.clamp(0.0, 1.0).toDouble();
    final distance = (end - start).abs();
    if (distance <= 0.001) {
      setState(() {
        _predictiveBackProgress = end;
      });
      onComplete();
      return;
    }
    final duration = lerpDouble(
      _predictiveBackSettleMinDuration.inMilliseconds.toDouble(),
      _predictiveBackSettleMaxDuration.inMilliseconds.toDouble(),
      distance,
    )!.round();
    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    );
    _predictiveBackSettleController = controller;
    final animation = controller.drive(CurveTween(curve: curve));
    controller.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _predictiveBackProgress = lerpDouble(
          start,
          end,
          animation.value,
        )!.clamp(0.0, 1.0).toDouble();
      });
    });
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) {
        return;
      }
      controller.dispose();
      if (identical(_predictiveBackSettleController, controller)) {
        _predictiveBackSettleController = null;
      }
      onComplete();
    });
    controller.forward();
  }

  void _cancelPredictiveBackSettle() {
    final controller = _predictiveBackSettleController;
    if (controller == null) {
      return;
    }
    _predictiveBackSettleController = null;
    controller.stop();
    controller.dispose();
  }

  void _setSort(ProxySort value) {
    if (_sort == value) {
      return;
    }
    setState(() {
      _sort = value;
      _sortedChildrenCache = null;
      _sortedChildrenSort = null;
    });
    widget.onSortChanged?.call(value);
  }

  List<AppProxySummary> _sortedChildren() {
    final cached = _sortedChildrenCache;
    if (cached != null && _sortedChildrenSort == _sort) {
      return cached;
    }
    final children = widget.children.toList(growable: false);
    _sortItems(children, keepLowestFirst: false);
    _sortedChildrenCache = children;
    _sortedChildrenSort = _sort;
    return children;
  }

  void _sortItems(List<AppProxySummary> items, {bool keepLowestFirst = true}) {
    sortProxySummaries(items, _sort, keepPinnedFirst: keepLowestFirst);
  }

  void _select(String tag) {
    setState(() {
      _selectedTag = tag;
    });
    widget.onSelected(tag);
  }

  Future<void> _openProxyShareSheet(AppProxySummary proxy) async {
    if (proxy.isGroup) {
      return;
    }
    final outbound = widget.outboundForTag?.call(proxy.tag);
    if (outbound == null) {
      return;
    }
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProxyShareSheet(proxy: proxy, outbound: outbound),
    );
  }

  void _handleHeaderDragStart(DragStartDetails details) {
    _cancelSheetInertia();
  }

  void _handleHeaderDragUpdate(DragUpdateDetails details) {
    final height = MediaQuery.sizeOf(context).height;
    _dragSheet(details.delta.dy, height);
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    final height = MediaQuery.sizeOf(context).height;
    _settleSheet(details, height);
  }

  bool _handleSheetScrollNotification(ScrollNotification notification) {
    if (_pendingSheetCarryVelocity == null) {
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _startSheetCarryIfListSettledAtTop();
      if (notification is ScrollEndNotification) {
        _pendingSheetCarryVelocity = null;
      }
    }
    return false;
  }

  void _handleSheetPointerDown(PointerDownEvent event) {
    _pendingSheetCarryVelocity = null;
    _resetSheetDragTracking();
    const headerHitHeight = _kProxySheetHeaderHeight;
    if (event.localPosition.dy <= headerHitHeight) {
      return;
    }
    _sheetPointerStartedInList = true;
    _sheetDragVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handleSheetPointerMove(PointerMoveEvent event) {
    if (!_sheetPointerStartedInList) {
      return;
    }
    final deltaY = event.delta.dy;
    _sheetPointerDeltaY += deltaY;
    _sheetDragVelocityTracker?.addPosition(event.timeStamp, event.position);
    if (deltaY == 0 || (!_sheetListAtTop() && deltaY > 0)) {
      return;
    }
    final maxSize = _sheetMaxSize(MediaQuery.sizeOf(context).height);
    if (_sheetSize >= maxSize - 0.001 && deltaY < 0) {
      return;
    }
    _sheetDragMoved = true;
    _dragSheet(deltaY, MediaQuery.sizeOf(context).height);
  }

  void _handleSheetPointerEnd(PointerUpEvent event) {
    final velocity =
        _sheetDragVelocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0;
    if (!_sheetDragMoved) {
      if (_sheetPointerStartedInList &&
          _sheetSize >=
              _sheetMaxSize(MediaQuery.sizeOf(context).height) - 0.001 &&
          !_sheetListAtTop() &&
          velocity > _kProxySheetCarryMinVelocity &&
          _sheetPointerDeltaY > _kProxySheetCarryMinDistance) {
        final residualVelocity = _sheetResidualVelocityAtTop(velocity);
        if (residualVelocity > _kProxySheetCarryMinResidualVelocity) {
          _pendingSheetCarryVelocity = residualVelocity;
        }
      }
      _resetSheetDragTracking();
      return;
    }
    _resetSheetDragTracking();
    _settleSheet(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
        primaryVelocity: velocity,
      ),
      MediaQuery.sizeOf(context).height,
    );
  }

  void _handleSheetPointerCancel(PointerCancelEvent event) {
    if (_sheetDragMoved) {
      _settleSheet(DragEndDetails(), MediaQuery.sizeOf(context).height);
    }
    _resetSheetDragTracking();
  }

  void _resetSheetDragTracking() {
    _sheetDragVelocityTracker = null;
    _sheetDragMoved = false;
    _sheetPointerStartedInList = false;
    _sheetPointerDeltaY = 0;
  }

  void _dragSheet(double deltaY, double viewportHeight) {
    _cancelSheetInertia();
    if (viewportHeight <= 0) {
      return;
    }
    final minSize = _sheetMinSize(viewportHeight);
    final maxSize = _sheetMaxSize(viewportHeight);
    final nextDirection = deltaY < 0
        ? 1
        : deltaY > 0
        ? -1
        : _sheetDragDirection;
    final nextSize = (_sheetSize - deltaY / viewportHeight)
        .clamp(minSize, maxSize)
        .toDouble();
    if ((nextSize - _sheetSize).abs() < 0.001 &&
        nextDirection == _sheetDragDirection) {
      return;
    }
    setState(() {
      _sheetDragDirection = nextDirection;
      _sheetSize = nextSize;
    });
    if (nextSize < maxSize - 0.001) {
      _resetSheetListScroll();
    }
  }

  void _settleSheet(DragEndDetails details, double viewportHeight) {
    _cancelSheetInertia();
    if (viewportHeight <= 0) {
      return;
    }
    final maxSize = _sheetMaxSize(viewportHeight);
    final velocity = details.primaryVelocity ?? 0;
    final opening =
        velocity < -_sheetInertiaMinVelocity ||
        (velocity.abs() <= _sheetInertiaMinVelocity && _sheetDragDirection > 0);
    if (opening) {
      _animateSheetTo(
        target: maxSize,
        sizeVelocity: velocity < 0 ? -velocity / viewportHeight : 0,
        viewportHeight: viewportHeight,
      );
      return;
    }
    if (velocity > _sheetInertiaMinVelocity) {
      _animateSheetBallistic(
        velocity: velocity,
        viewportHeight: viewportHeight,
      );
      return;
    }
    if (_sheetSize <= _sheetCloseThreshold(viewportHeight)) {
      Navigator.of(context).pop();
      return;
    }
    final target = maxSize;
    _animateSheetTo(
      target: target,
      sizeVelocity: 0,
      viewportHeight: viewportHeight,
    );
  }

  void _animateSheetBallistic({
    required double velocity,
    required double viewportHeight,
  }) {
    final minSize = _sheetMinSize(viewportHeight);
    final maxSize = _sheetMaxSize(viewportHeight);
    final startSize = _sheetSize.clamp(minSize, maxSize).toDouble();
    final sizeVelocity = (-velocity / viewportHeight)
        .clamp(-_sheetMaxSpringVelocity, _sheetMaxSpringVelocity)
        .toDouble();
    final projectedLowPoint = _sheetProjectedSpringLowPoint(
      startSize: startSize,
      targetSize: maxSize,
      sizeVelocity: sizeVelocity,
      minSize: minSize,
      maxSize: maxSize,
    );
    final target = projectedLowPoint <= _sheetCloseThreshold(viewportHeight)
        ? minSize
        : maxSize;
    if (target <= minSize + 0.001) {
      Navigator.of(context).pop();
      return;
    }
    _animateSheetTo(
      target: target,
      sizeVelocity: sizeVelocity,
      viewportHeight: viewportHeight,
    );
  }

  double _sheetProjectedSpringLowPoint({
    required double startSize,
    required double targetSize,
    required double sizeVelocity,
    required double minSize,
    required double maxSize,
  }) {
    if (sizeVelocity >= 0) {
      return startSize;
    }
    final simulation = SpringSimulation(
      _sheetSpring,
      startSize,
      targetSize,
      sizeVelocity,
    );
    var lowPoint = startSize;
    var previousVelocity = sizeVelocity;
    for (var step = 1; step <= 120; step += 1) {
      final time = step / 120;
      final size = simulation.x(time).clamp(minSize, maxSize).toDouble();
      if (size < lowPoint) {
        lowPoint = size;
      }
      final velocity = simulation.dx(time);
      if (previousVelocity < 0 && velocity >= 0) {
        break;
      }
      if (simulation.isDone(time)) {
        break;
      }
      previousVelocity = velocity;
    }
    return lowPoint;
  }

  void _animateSheetTo({
    required double target,
    required double sizeVelocity,
    required double viewportHeight,
  }) {
    _cancelSheetInertia();
    final minSize = _sheetMinSize(viewportHeight);
    final maxSize = _sheetMaxSize(viewportHeight);
    final startSize = _sheetSize.clamp(minSize, maxSize).toDouble();
    if ((target - startSize).abs() <= 0.001 &&
        sizeVelocity.abs() <= _sheetInertiaMinVelocity / viewportHeight) {
      setState(() {
        _sheetDragDirection = 0;
        _sheetSize = target;
      });
      if (target <= minSize + 0.001) {
        Navigator.of(context).pop();
      }
      return;
    }
    final controller = AnimationController.unbounded(
      vsync: this,
      value: startSize,
    );
    _sheetInertiaController = controller;
    controller.addListener(() {
      final nextSize = controller.value.clamp(minSize, maxSize).toDouble();
      setState(() {
        _sheetDragDirection = target > startSize ? 1 : -1;
        _sheetSize = nextSize;
      });
      if (nextSize < maxSize - 0.001) {
        _resetSheetListScroll();
      }
    });
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) {
        return;
      }
      controller.dispose();
      if (identical(_sheetInertiaController, controller)) {
        _sheetInertiaController = null;
      }
      setState(() {
        _sheetDragDirection = 0;
        _sheetSize = target;
      });
      if (target <= minSize + 0.001) {
        Navigator.of(context).pop();
      }
    });
    controller.animateWith(
      SpringSimulation(_sheetSpring, startSize, target, sizeVelocity),
    );
  }

  void _cancelSheetInertia() {
    final controller = _sheetInertiaController;
    if (controller == null) {
      return;
    }
    final currentSize = controller.value
        .clamp(0.0, _sheetMaxSize(MediaQuery.sizeOf(context).height))
        .toDouble();
    final currentDirection = controller.velocity > 0
        ? 1
        : controller.velocity < 0
        ? -1
        : _sheetDragDirection;
    _sheetInertiaController = null;
    controller.stop();
    controller.dispose();
    if (!mounted) {
      return;
    }
    setState(() {
      _sheetDragDirection = currentDirection;
      _sheetSize = currentSize;
    });
  }

  void _startSheetCarryIfListSettledAtTop() {
    final velocity = _pendingSheetCarryVelocity;
    if (velocity == null || !_sheetListAtTop()) {
      return;
    }
    _pendingSheetCarryVelocity = null;
    _settleSheet(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
        primaryVelocity: velocity,
      ),
      MediaQuery.sizeOf(context).height,
    );
  }

  double _sheetResidualVelocityAtTop(double pointerVelocity) {
    if (!_scrollController.hasClients) {
      return 0;
    }
    var residualVelocity = 0.0;
    for (final position in _scrollController.positions) {
      final scrollVelocity = -pointerVelocity;
      if (scrollVelocity >= 0) {
        continue;
      }
      final simulation = FrictionSimulation(
        _kProxySheetFrictionDrag,
        position.pixels,
        scrollVelocity,
      );
      if (simulation.finalX > position.minScrollExtent) {
        continue;
      }
      final timeAtTop = simulation.timeAtX(position.minScrollExtent);
      if (!timeAtTop.isFinite) {
        continue;
      }
      final velocityAtTop = -simulation.dx(timeAtTop);
      if (velocityAtTop > residualVelocity) {
        residualVelocity = velocityAtTop;
      }
    }
    return residualVelocity
        .clamp(0.0, _kProxySheetMaxSpringTransferVelocity)
        .toDouble();
  }

  bool _sheetListAtTop() {
    if (!_scrollController.hasClients) {
      return true;
    }
    return _scrollController.positions.every(
      (position) => position.pixels <= position.minScrollExtent + 0.5,
    );
  }

  void _resetSheetListScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    for (final position in _scrollController.positions) {
      if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
        position.jumpTo(position.minScrollExtent);
      }
    }
  }

  Widget _runtimeTile({
    required AppProxySummary proxy,
    required bool selected,
    required bool highlighted,
    String? titleOverride,
    String? subtitleOverride,
    bool showGroupHandle = false,
    VoidCallback? onLongPress,
    required VoidCallback onTap,
  }) {
    Widget buildTile(ProxyRuntimeVisualState? state) {
      return ProxyTile(
        proxy: proxy,
        runtimeState: state,
        selected: selected,
        highlighted: highlighted,
        titleOverride: titleOverride,
        subtitleOverride: subtitleOverride,
        forceBaseInset: true,
        showGroupHandle: showGroupHandle,
        animate: false,
        onTap: onTap,
        onLongPress: onLongPress,
      );
    }

    final runtimeStates = widget.runtimeStates;
    if (runtimeStates == null) {
      return buildTile(null);
    }
    return ValueListenableBuilder<ProxyRuntimeVisualState?>(
      valueListenable: runtimeStates.listenableFor(proxy.tag),
      builder: (context, state, _) => buildTile(state),
    );
  }

  double _sheetMinSize(double viewportHeight) {
    if (viewportHeight <= _sheetMinHeight) {
      return _maxSheetSize;
    }
    return (_sheetMinHeight / viewportHeight)
        .clamp(0.0, _maxSheetSize)
        .toDouble();
  }

  double _sheetCloseThreshold(double viewportHeight) {
    final minSize = _sheetMinSize(viewportHeight);
    final maxSize = _sheetMaxSize(viewportHeight);
    final viewportThreshold = _sheetSettleCloseRatio;
    if (maxSize > viewportThreshold) {
      return viewportThreshold;
    }
    return minSize + (maxSize - minSize) * _sheetCompactSettleCloseRatio;
  }

  double _sheetMaxSize(double viewportHeight) {
    if (viewportHeight <= _sheetMinHeight) {
      return _maxSheetSize;
    }
    final topReserve = (appSystemStatusBarInset(context) + _sheetStatusBarGap)
        .clamp(0.0, viewportHeight - _sheetMinHeight)
        .toDouble();
    return ((viewportHeight - topReserve) / viewportHeight)
        .clamp(0.0, _maxSheetSize)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottomInset = appSystemNavigationBarInset(context);
    final activeChildTag = widget.group.selectedChildTag;
    final children = _sortedChildren();
    AppProxySummary? activeChild;
    for (final proxy in children) {
      if (proxy.tag == activeChildTag) {
        activeChild = proxy;
        break;
      }
    }
    const headerHeight = _kProxySheetHeaderHeight;
    final sheetTitle = l10n.proxySelectorTitle;
    final groupTitle = activeChild == null
        ? 'lowest'
        : 'lowest · ${activeChild.displayName}';
    final groupSubtitle = activeChild == null
        ? 'URLTest'
        : 'URLTest · ${activeChild.protocolLabel}';
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final maxSheetSize = _sheetMaxSize(viewportHeight);
    final effectiveSheetSize = _sheetSize
        .clamp(_sheetMinSize(viewportHeight), maxSheetSize)
        .toDouble();

    final viewportSize = MediaQuery.sizeOf(context);
    final destHeight = viewportHeight * effectiveSheetSize;
    final destRect = Rect.fromLTWH(
      0,
      viewportHeight - destHeight,
      viewportSize.width,
      destHeight,
    );
    // Pre-compute static parts of the sheet body once per build —
    // they don't depend on the route animation.
    final sheetBody = RepaintBoundary(
      child: SizedBox(
        width: destRect.width,
        height: destRect.height,
        child: Stack(
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handleSheetPointerDown,
              onPointerMove: _handleSheetPointerMove,
              onPointerUp: _handleSheetPointerEnd,
              onPointerCancel: _handleSheetPointerCancel,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleSheetScrollNotification,
                child: ListView.builder(
                  controller: _scrollController,
                  physics: effectiveSheetSize >= maxSheetSize - 0.001
                      ? const _ProxySheetScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        )
                      : const NeverScrollableScrollPhysics(),
                  itemExtent: _kProxySheetRowExtent,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  addSemanticIndexes: false,
                  padding: EdgeInsets.only(
                    top: _kProxyGroupSheetListTopReserve,
                    bottom: bottomInset + 18,
                  ),
                  itemCount: children.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _runtimeTile(
                        proxy: widget.group,
                        selected: widget.group.tag == _selectedTag,
                        highlighted: false,
                        titleOverride: groupTitle,
                        subtitleOverride: groupSubtitle,
                        showGroupHandle: true,
                        onTap: () => _select(widget.group.tag),
                      );
                    }
                    final proxy = children[index - 1];
                    return _runtimeTile(
                      proxy: proxy,
                      selected: proxy.tag == _selectedTag,
                      highlighted:
                          proxy.tag == activeChildTag || proxy.highlighted,
                      onTap: () => _select(proxy.tag),
                      onLongPress: () => _openProxyShareSheet(proxy),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              // BackdropFilter blur is the most expensive widget
              // in the tree — keep it disabled while the route
              // animation is in flight, then re-enable it once
              // the sheet has settled.
              child: AnimatedBuilder(
                animation: widget.routeAnimation,
                builder: (context, child) => _ProxySheetHeaderBackdrop(
                  enabled:
                      widget.progressiveBlurEnabled &&
                      widget.routeAnimation.value >= 0.985,
                  cornerRadius: 28,
                  height: headerHeight,
                  child: child!,
                ),
                child: _GroupOutboundsSheetHeader(
                  title: sheetTitle,
                  l10n: l10n,
                  sort: _sort,
                  onSortSelected: _setSort,
                  onClose: () => Navigator.of(context).pop(),
                  onVerticalDragStart: _handleHeaderDragStart,
                  onVerticalDragUpdate: _handleHeaderDragUpdate,
                  onVerticalDragEnd: _handleHeaderDragEnd,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: widget.routeAnimation,
        builder: (context, _) {
          final raw = _predictiveBackInProgress
              ? (1.0 - _predictiveBackProgress)
              : widget.routeAnimation.value.clamp(0.0, 1.0).toDouble();
          final scrimProgress = Curves.easeInOutCubic.transform(raw);
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(context).pop(),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.32 * scrimProgress),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fromRect(
                rect: destRect,
                child: IgnorePointer(
                  ignoring: raw < 0.6,
                  child: ClipRRect(
                    clipBehavior: Clip.hardEdge,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    child: sheetBody,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupOutboundsSheetHeader extends StatelessWidget {
  const _GroupOutboundsSheetHeader({
    required this.title,
    required this.l10n,
    required this.sort,
    required this.onSortSelected,
    required this.onClose,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final String title;
  final AppLocalizations l10n;
  final ProxySort sort;
  final ValueChanged<ProxySort> onSortSelected;
  final VoidCallback onClose;
  final ValueChanged<DragStartDetails> onVerticalDragStart;
  final ValueChanged<DragUpdateDetails> onVerticalDragUpdate;
  final ValueChanged<DragEndDetails> onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: SizedBox(
        height: _kProxySheetHeaderHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: .34,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 18,
              bottom: 0,
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 18,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: onClose,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(FluentIcons.chevron_left_24_regular),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 18,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: l10n.sort,
                  onPressed: () => _showProxySortPicker(
                    context,
                    l10n: l10n,
                    current: sort,
                    onSelected: onSortSelected,
                  ),
                  icon: const Icon(FluentIcons.arrow_sort_24_regular),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _prettyJson(Map<String, dynamic> value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}

Map<String, dynamic> _singboxOutboundJson(Outbound outbound) {
  final config = Map<String, dynamic>.from(outbound.config);
  config.remove('_name');
  config['tag'] = outbound.name.isNotEmpty ? outbound.name : outbound.tag;
  return config;
}

String? _outboundShareLink(Outbound outbound) {
  final config = outbound.config;
  final type = (config['type'] as String? ?? '').toLowerCase();
  return switch (type) {
    'vless' => _vlessShareLink(outbound),
    'vmess' => _vmessShareLink(outbound),
    'trojan' => _trojanShareLink(outbound),
    'shadowsocks' => _shadowsocksShareLink(outbound),
    'shadowsocksr' => _shadowsocksrShareLink(outbound),
    'socks' => _socksShareLink(outbound),
    'http' => _httpShareLink(outbound),
    'hysteria2' => _hysteria2ShareLink(outbound),
    'hysteria' => _hysteriaShareLink(outbound),
    'tuic' => _tuicShareLink(outbound),
    'anytls' => _anytlsShareLink(outbound),
    'naive' => _naiveShareLink(outbound),
    _ => null,
  };
}

String? _vlessShareLink(Outbound outbound) {
  final c = outbound.config;
  final uuid = _stringValue(c['uuid']);
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (uuid.isEmpty || server.isEmpty || port == null) return null;
  final query = <String, String>{};
  _putQuery(query, 'encryption', _stringValue(c['encryption']));
  _putQuery(query, 'flow', _stringValue(c['flow']));
  _putQuery(query, 'packetEncoding', _stringValue(c['packet_encoding']));
  _appendTlsQuery(query, c['tls']);
  _appendTransportQuery(query, c['transport']);
  return _uriWithQuery(
    scheme: 'vless',
    userInfo: uuid,
    server: server,
    port: port,
    query: query,
    name: outbound.name,
  );
}

String? _trojanShareLink(Outbound outbound) {
  final c = outbound.config;
  final password = _stringValue(c['password']);
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (password.isEmpty || server.isEmpty || port == null) return null;
  final query = <String, String>{};
  _appendTlsQuery(query, c['tls'], defaultSecurity: 'tls');
  _appendTransportQuery(query, c['transport']);
  return _uriWithQuery(
    scheme: 'trojan',
    userInfo: password,
    server: server,
    port: port,
    query: query,
    name: outbound.name,
  );
}

String? _shadowsocksShareLink(Outbound outbound) {
  final c = outbound.config;
  final method = _stringValue(c['method']);
  final password = _stringValue(c['password']);
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (method.isEmpty || password.isEmpty || server.isEmpty || port == null) {
    return null;
  }
  final userInfo = base64Url
      .encode(utf8.encode('$method:$password'))
      .replaceAll('=', '');
  return _uriWithQuery(
    scheme: 'ss',
    userInfo: userInfo,
    server: server,
    port: port,
    query: const {},
    name: outbound.name,
  );
}

String? _vmessShareLink(Outbound outbound) {
  final c = outbound.config;
  final uuid = _stringValue(c['uuid']);
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (uuid.isEmpty || server.isEmpty || port == null) return null;
  final tls = c['tls'] is Map
      ? Map<String, dynamic>.from(c['tls'] as Map)
      : null;
  final transport = c['transport'] is Map
      ? Map<String, dynamic>.from(c['transport'] as Map)
      : null;
  final payload = <String, dynamic>{
    'v': '2',
    'ps': outbound.name,
    'add': server,
    'port': '$port',
    'id': uuid,
    'aid': '${_intValue(c['alter_id']) ?? 0}',
    'scy': _stringValue(c['security'], fallback: 'auto'),
    'net': _stringValue(transport?['type'], fallback: 'tcp'),
    'type': _stringValue(
      transport?['headers'] is Map
          ? (transport!['headers'] as Map)['type']
          : null,
      fallback: 'none',
    ),
    'host': _transportHost(transport),
    'path': _stringValue(transport?['path']),
    'tls': tls?['enabled'] == true ? 'tls' : '',
    'sni': _stringValue(tls?['server_name']),
    'fp': _stringValue(
      tls?['utls'] is Map ? (tls!['utls'] as Map)['fingerprint'] : null,
    ),
  };
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'vmess://$encoded';
}

String? _shadowsocksrShareLink(Outbound outbound) {
  final c = outbound.config;
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  final protocol = _stringValue(c['protocol'], fallback: 'origin');
  final method = _stringValue(c['method']);
  final obfs = _stringValue(c['obfs'], fallback: 'plain');
  final password = _stringValue(c['password']);
  if (server.isEmpty || port == null || method.isEmpty || password.isEmpty) {
    return null;
  }
  final query = <String, String>{};
  _putQuery(query, 'obfsparam', _base64UrlNoPad(_stringValue(c['obfs_param'])));
  _putQuery(
    query,
    'protoparam',
    _base64UrlNoPad(_stringValue(c['protocol_param'])),
  );
  _putQuery(query, 'remarks', _base64UrlNoPad(outbound.name));
  final main =
      '$server:$port:$protocol:$method:$obfs:${_base64UrlNoPad(password)}/?'
      '${query.entries.map((e) => '${e.key}=${e.value}').join('&')}';
  return 'ssr://${_base64UrlNoPad(main)}';
}

String? _socksShareLink(Outbound outbound) {
  final c = outbound.config;
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (server.isEmpty || port == null) return null;
  final version = _stringValue(c['version'], fallback: '5');
  final scheme = version == '4' ? 'socks4' : 'socks5';
  return _uriWithQuery(
    scheme: scheme,
    userInfo: _credentialsUserInfo(c),
    server: server,
    port: port,
    query: const {},
    name: outbound.name,
  );
}

String? _httpShareLink(Outbound outbound) {
  final c = outbound.config;
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (server.isEmpty || port == null) return null;
  final tls = c['tls'] is Map
      ? Map<String, dynamic>.from(c['tls'] as Map)
      : null;
  return _uriWithQuery(
    scheme: tls?['enabled'] == true ? 'https' : 'http',
    userInfo: _credentialsUserInfo(c),
    server: server,
    port: port,
    query: const {},
    name: outbound.name,
  );
}

String? _naiveShareLink(Outbound outbound) {
  final c = outbound.config;
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (server.isEmpty || port == null) return null;
  final query = <String, String>{};
  final tls = c['tls'] is Map
      ? Map<String, dynamic>.from(c['tls'] as Map)
      : null;
  _putQuery(query, 'sni', _stringValue(tls?['server_name']));
  _putQuery(
    query,
    'quic_congestion_control',
    _stringValue(c['quic_congestion_control']),
  );
  final extraHeaders = _encodedHeaders(c['extra_headers']);
  _putQuery(query, 'extra-headers', extraHeaders);
  return _naiveUriWithQuery(
    scheme: c['quic'] == true ? 'naive+quic' : 'naive+https',
    userInfo: _credentialsUserInfo(c),
    server: server,
    port: port,
    query: query,
    name: outbound.name,
  );
}

String? _hysteria2ShareLink(Outbound outbound) {
  final c = outbound.config;
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (server.isEmpty || port == null) return null;
  final query = <String, String>{};
  _appendHyTlsQuery(query, c['tls']);
  final obfs = c['obfs'] is Map
      ? Map<String, dynamic>.from(c['obfs'] as Map)
      : null;
  _putQuery(query, 'obfs', _stringValue(obfs?['type']));
  _putQuery(query, 'obfs-password', _stringValue(obfs?['password']));
  return _uriWithQuery(
    scheme: 'hysteria2',
    userInfo: _stringValue(c['password']),
    server: server,
    port: port,
    query: query,
    name: outbound.name,
  );
}

String? _hysteriaShareLink(Outbound outbound) {
  final c = outbound.config;
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (server.isEmpty || port == null) return null;
  final query = <String, String>{};
  _putQuery(query, 'auth', _stringValue(c['auth_string']));
  _putQuery(query, 'upmbps', _stringValue(c['up_mbps']));
  _putQuery(query, 'downmbps', _stringValue(c['down_mbps']));
  _putQuery(query, 'obfsParam', _stringValue(c['obfs']));
  _appendHyTlsQuery(query, c['tls']);
  return _uriWithQuery(
    scheme: 'hysteria',
    userInfo: '',
    server: server,
    port: port,
    query: query,
    name: outbound.name,
  );
}

String? _tuicShareLink(Outbound outbound) {
  final c = outbound.config;
  final uuid = _stringValue(c['uuid']);
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (uuid.isEmpty || server.isEmpty || port == null) return null;
  final password = _stringValue(c['password']);
  final query = <String, String>{};
  _putQuery(query, 'congestion_control', _stringValue(c['congestion_control']));
  _putQuery(query, 'udp_relay_mode', _stringValue(c['udp_relay_mode']));
  _appendHyTlsQuery(query, c['tls'], insecureKey: 'allow_insecure');
  return _uriWithQuery(
    scheme: 'tuic',
    userInfo: password.isEmpty ? uuid : '$uuid:$password',
    server: server,
    port: port,
    query: query,
    name: outbound.name,
  );
}

String? _anytlsShareLink(Outbound outbound) {
  final c = outbound.config;
  final password = _stringValue(c['password']);
  final server = _stringValue(c['server']);
  final port = _intValue(c['server_port']);
  if (password.isEmpty || server.isEmpty || port == null) return null;
  final query = <String, String>{};
  _appendHyTlsQuery(query, c['tls']);
  return _uriWithQuery(
    scheme: 'anytls',
    userInfo: password,
    server: server,
    port: port,
    query: query,
    name: outbound.name,
  );
}

String _credentialsUserInfo(Map<String, dynamic> config) {
  final username = _stringValue(config['username']);
  final password = _stringValue(config['password']);
  if (username.isEmpty) return '';
  if (password.isEmpty) return username;
  return '$username:$password';
}

String _encodedHeaders(Object? rawHeaders) {
  if (rawHeaders is! Map) return '';
  final lines = <String>[];
  for (final entry in rawHeaders.entries) {
    final key = entry.key.toString().trim();
    final value = entry.value?.toString().trim() ?? '';
    if (key.isNotEmpty && value.isNotEmpty) {
      lines.add('$key: $value');
    }
  }
  return lines.join('\r\n');
}

void _appendTlsQuery(
  Map<String, String> query,
  Object? rawTls, {
  String defaultSecurity = '',
}) {
  if (rawTls is! Map || rawTls['enabled'] != true) {
    if (defaultSecurity.isNotEmpty) {
      _putQuery(query, 'security', defaultSecurity);
    }
    return;
  }
  final tls = Map<String, dynamic>.from(rawTls);
  final reality = tls['reality'] is Map
      ? Map<String, dynamic>.from(tls['reality'] as Map)
      : null;
  _putQuery(query, 'security', reality?['enabled'] == true ? 'reality' : 'tls');
  _putQuery(query, 'sni', _stringValue(tls['server_name']));
  _putQuery(
    query,
    'fp',
    _stringValue(
      tls['utls'] is Map ? (tls['utls'] as Map)['fingerprint'] : null,
    ),
  );
  if (reality?['enabled'] == true) {
    _putQuery(query, 'pbk', _stringValue(reality?['public_key']));
    _putQuery(query, 'sid', _stringValue(reality?['short_id']));
    _putQuery(query, 'spx', _stringValue(reality?['spider_x']));
  }
}

void _appendHyTlsQuery(
  Map<String, String> query,
  Object? rawTls, {
  String insecureKey = 'insecure',
}) {
  if (rawTls is! Map) return;
  final tls = Map<String, dynamic>.from(rawTls);
  _putQuery(query, 'sni', _stringValue(tls['server_name']));
  if (tls['insecure'] == true) {
    _putQuery(query, insecureKey, '1');
  }
  if (tls['alpn'] is List) {
    _putQuery(query, 'alpn', (tls['alpn'] as List).join(','));
  }
  _putQuery(
    query,
    'fp',
    _stringValue(
      tls['utls'] is Map ? (tls['utls'] as Map)['fingerprint'] : null,
    ),
  );
}

void _appendTransportQuery(Map<String, String> query, Object? rawTransport) {
  if (rawTransport is! Map) return;
  final transport = Map<String, dynamic>.from(rawTransport);
  _putQuery(query, 'type', _stringValue(transport['type']));
  _putQuery(query, 'path', _stringValue(transport['path']));
  _putQuery(query, 'host', _transportHost(transport));
  _putQuery(query, 'mode', _stringValue(transport['mode']));
  _putQuery(query, 'serviceName', _stringValue(transport['service_name']));
  if (transport['extra'] != null) {
    _putQuery(query, 'extra', jsonEncode(transport['extra']));
  }
}

String _transportHost(Map<String, dynamic>? transport) {
  if (transport == null) return '';
  final headers = transport['headers'];
  if (headers is Map) {
    return _stringValue(headers['Host'] ?? headers['host']);
  }
  return _stringValue(transport['host']);
}

String _uriWithQuery({
  required String scheme,
  required String userInfo,
  required String server,
  required int port,
  required Map<String, String> query,
  required String name,
}) {
  final encodedQuery = query.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
  final fragment = name.trim().isEmpty ? '' : '#${Uri.encodeComponent(name)}';
  final encodedUserInfo = _encodeUserInfo(userInfo);
  final auth = encodedUserInfo.isEmpty
      ? '$server:$port'
      : '$encodedUserInfo@$server:$port';
  return '$scheme://$auth${encodedQuery.isEmpty ? '' : '?$encodedQuery'}$fragment';
}

String _naiveUriWithQuery({
  required String scheme,
  required String userInfo,
  required String server,
  required int port,
  required Map<String, String> query,
  required String name,
}) {
  final encodedQuery = query.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
  final fragment = name.trim().isEmpty ? '' : '#${Uri.encodeComponent(name)}';
  final encodedUserInfo = _encodeUserInfo(userInfo);
  final authority = port == 443 ? server : '$server:$port';
  final auth = encodedUserInfo.isEmpty
      ? authority
      : '$encodedUserInfo@$authority';
  return '$scheme://$auth${encodedQuery.isEmpty ? '' : '?$encodedQuery'}$fragment';
}

String _encodeUserInfo(String userInfo) {
  if (userInfo.isEmpty) return '';
  final separator = userInfo.indexOf(':');
  if (separator < 0) {
    return Uri.encodeComponent(userInfo);
  }
  return '${Uri.encodeComponent(userInfo.substring(0, separator))}:'
      '${Uri.encodeComponent(userInfo.substring(separator + 1))}';
}

void _putQuery(Map<String, String> query, String key, String value) {
  if (value.trim().isNotEmpty) {
    query[key] = value.trim();
  }
}

String _base64UrlNoPad(String value) {
  if (value.isEmpty) return '';
  return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}

String _stringValue(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

class _ProxyShareSheet extends StatelessWidget {
  const _ProxyShareSheet({required this.proxy, required this.outbound});

  final AppProxySummary proxy;
  final Outbound outbound;

  Future<void> _copy(
    BuildContext context, {
    required String value,
    required String label,
  }) async {
    final navigator = Navigator.of(context);
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) {
      return;
    }
    final message = _copiedText(context, label);
    AppNotice.show(context, message, tone: AppNoticeTone.success);
    navigator.pop();
  }

  String _copiedText(BuildContext context, String label) {
    return AppLocalizations.of(context).copiedToClipboard(label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = appSystemNavigationBarInset(context);
    final shareLink = _outboundShareLink(outbound);
    final singboxJson = _prettyJson(_singboxOutboundJson(outbound));
    final l10n = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .42,
      minChildSize: .22,
      maxChildSize: .74,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(16, 10, 16, bottomInset + 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: .34,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.shareProxyTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _ProxyShareSummary(proxy: proxy),
                    const SizedBox(height: 12),
                    Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ProxyShareActionTile(
                            label: l10n.shareProxyLinkLabel,
                            icon: FluentIcons.clipboard_link_24_regular,
                            enabled: shareLink != null,
                            onTap: shareLink == null
                                ? null
                                : () => _copy(
                                    context,
                                    value: shareLink,
                                    label: l10n.shareProxyLinkLabel,
                                  ),
                          ),
                          Divider(
                            height: 1,
                            indent: 56,
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: .28,
                            ),
                          ),
                          _ProxyShareActionTile(
                            label: l10n.shareSingboxOutboundLabel,
                            icon: FluentIcons.clipboard_code_24_regular,
                            onTap: () => _copy(
                              context,
                              value: singboxJson,
                              label: l10n.shareSingboxOutboundLabel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProxyShareSummary extends StatelessWidget {
  const _ProxyShareSummary({required this.proxy});

  final AppProxySummary proxy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latencyText = proxy.latencyChecking
        ? '... ms'
        : proxy.latencyUnavailable
        ? '—'
        : proxy.latency == null
        ? '—'
        : '${proxy.latency} ms';

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            CountryFlagBadge(countryCode: proxy.countryCode, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proxy.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    proxy.protocolLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              latencyText,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxyShareActionTile extends StatelessWidget {
  const _ProxyShareActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      leading: Icon(icon),
      title: Text(label),
      subtitle: enabled
          ? null
          : Text(AppLocalizations.of(context).unavailableForThisType),
      trailing: const Icon(FluentIcons.copy_24_regular),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textColor: theme.colorScheme.onSurface,
      iconColor: theme.colorScheme.onSurfaceVariant,
    );
  }
}

class ProxyTile extends StatelessWidget {
  const ProxyTile({
    super.key,
    required this.proxy,
    required this.selected,
    required this.onTap,
    this.highlighted = false,
    this.titleOverride,
    this.subtitleOverride,
    this.forceBaseInset = false,
    this.showGroupHandle = false,
    this.animate = true,
    this.runtimeState,
    this.onOpenGroup,
    this.onLongPress,
  });

  final AppProxySummary proxy;
  final bool selected;
  final bool highlighted;
  final String? titleOverride;
  final String? subtitleOverride;
  final bool forceBaseInset;
  final bool showGroupHandle;
  final bool animate;
  final ProxyRuntimeVisualState? runtimeState;
  final VoidCallback onTap;
  final ValueChanged<Rect>? onOpenGroup;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final state = runtimeState;
    final latency = state?.latency ?? proxy.latency;
    final latencyFresh = state?.latencyFresh ?? proxy.latencyFresh;
    final latencyChecking = state?.latencyChecking ?? proxy.latencyChecking;
    final latencyUnavailable =
        state?.latencyUnavailable ?? proxy.latencyUnavailable;
    final latencyError = state?.latencyError ?? proxy.latencyError;
    final hasLatencyError = latencyError?.trim().isNotEmpty == true;
    final highlighted = state?.highlighted ?? this.highlighted;
    final selecting = state?.selecting ?? false;
    final latencyText = selecting
        ? l10n.proxySwitching
        : latencyChecking && latency == null
        ? '... ms'
        : latencyUnavailable
        ? _latencyErrorLabel(latencyError)
        : latency == null && hasLatencyError
        ? _latencyErrorLabel(latencyError)
        : latency == null
        ? '—'
        : '$latency ms';
    final delayColor = selecting
        ? theme.colorScheme.primary
        : latencyUnavailable
        ? theme.colorScheme.error
        : latency == null && hasLatencyError
        ? theme.colorScheme.tertiary
        : !latencyFresh || latency == null
        ? theme.colorScheme.onSurfaceVariant
        : latency < 800
        ? (theme.brightness == Brightness.dark
              ? Colors.lightGreen
              : Colors.green)
        : latency < 1500
        ? (theme.brightness == Brightness.dark
              ? Colors.orange
              : Colors.deepOrangeAccent)
        : Colors.red;
    final latencyLabel = _ProxyLatencyLabel(
      text: latencyText,
      color: delayColor,
      checking: latencyChecking && latency == null && !selecting,
      emphasized:
          selecting || latencyFresh || latencyUnavailable || hasLatencyError,
      tooltip: hasLatencyError ? _latencyErrorTooltip(latencyError) : null,
    );

    final horizontalInset = !forceBaseInset && proxy.isGroupChild ? 24.0 : 6.0;
    final emphasized = selected || highlighted;
    final groupHandleVisible = showGroupHandle || onOpenGroup != null;
    final animationDuration = animate
        ? const Duration(milliseconds: 220)
        : Duration.zero;
    final decoration = BoxDecoration(
      color: selected
          ? theme.colorScheme.secondaryContainer.withValues(alpha: .32)
          : highlighted
          ? theme.colorScheme.secondaryContainer.withValues(alpha: .15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
    );
    final indicatorDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: emphasized
          ? theme.colorScheme.primary.withValues(alpha: selected ? 1 : .46)
          : Colors.transparent,
    );
    final groupHandleDecoration = BoxDecoration(
      color: theme.colorScheme.primary.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(99),
    );
    final rowChild = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          animate
              ? AnimatedContainer(
                  duration: animationDuration,
                  width: 4,
                  height: 46,
                  decoration: indicatorDecoration,
                )
              : Container(
                  width: 4,
                  height: 46,
                  decoration: indicatorDecoration,
                ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            height: 36,
            child: CountryFlagBadge(countryCode: proxy.countryCode, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleOverride ?? proxy.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleOverride ?? proxy.protocolLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: selecting ? 104 : 72,
            child: !groupHandleVisible
                ? latencyLabel
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenGroup == null
                        ? null
                        : () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final rect = box != null && box.attached
                                ? box.localToGlobal(Offset.zero) & box.size
                                : Rect.zero;
                            onOpenGroup!(rect);
                          },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        latencyLabel,
                        SizedBox(
                          height: 10,
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: animate
                                ? Tooltip(
                                    message: proxy.displayName,
                                    child: AnimatedContainer(
                                      duration: animationDuration,
                                      width: 28,
                                      height: 3,
                                      decoration: groupHandleDecoration,
                                    ),
                                  )
                                : Container(
                                    width: 28,
                                    height: 3,
                                    decoration: groupHandleDecoration,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
    final child = animate
        ? InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            onLongPress: onLongPress,
            child: rowChild,
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onLongPress: onLongPress,
            child: rowChild,
          );
    if (animate) {
      return AnimatedContainer(
        duration: animationDuration,
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.fromLTRB(horizontalInset, 1, 6, 1),
        decoration: decoration,
        child: child,
      );
    }
    return Container(
      margin: EdgeInsets.fromLTRB(horizontalInset, 1, 6, 1),
      decoration: decoration,
      child: child,
    );
  }
}
