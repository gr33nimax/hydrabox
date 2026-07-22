import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:meow_client/core/demo_utils.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/core/widgets/app_notice.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/app_view_models.dart';
import 'package:meow_client/models/proxy_runtime_visual_state.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/widgets/country_flag_badge.dart';
import 'package:meow_client/widgets/ip_refresh_dots.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

import 'proxy_list_ordering.dart';
import 'proxy_panel_shell.dart';

const _kProxySheetHeaderHeight = 108.0;
const _kProxySheetCompactHeaderHeight = 72.0;
const _kProxyGroupSheetListTopReserve = 144.0;
const _kProxySheetRowExtent = 72.0;
const _kProxySheetHeaderCollapseDistance = 48.0;
const _kProxySheetHeaderBlurStart = 0.0;

enum _ProxyChainAction { edit, rename, remove }

String _proxySortLabel(AppLocalizations l10n, ProxySort sort) => switch (sort) {
  ProxySort.source => l10n.sortByDefault,
  ProxySort.latency => l10n.sortByLatency,
  ProxySort.name => l10n.sortByName,
  ProxySort.country => l10n.sortByCountry,
};

String _localizedLowestBaseLabel(AppLocalizations l10n, String tag) =>
    l10n.proxyLowestName;

String? _lowestSelectedDisplayName(AppProxySummary proxy) {
  final selected = proxy.selectedChildName?.trim() ?? '';
  if (selected.isNotEmpty) {
    return selected;
  }
  final technicalBase = lowestProxyBaseLabel(proxy.tag);
  final prefix = '$technicalBase · ';
  return proxy.displayName.startsWith(prefix)
      ? proxy.displayName.substring(prefix.length).trim()
      : null;
}

String _localizedProxyTitle(AppLocalizations l10n, AppProxySummary proxy) {
  if (!isLowestProxyTag(proxy.tag)) {
    return proxy.displayName;
  }
  final base = _localizedLowestBaseLabel(l10n, proxy.tag);
  final selected = _lowestSelectedDisplayName(proxy);
  return selected == null || selected.isEmpty ? base : '$base · $selected';
}

String _localizedProxySubtitle(AppLocalizations l10n, AppProxySummary proxy) {
  return _localizedProxyTechnicalText(l10n, proxy, proxy.protocolLabel.trim());
}

String _localizedProxyDetail(AppLocalizations l10n, AppProxySummary proxy) {
  return _localizedProxyTechnicalText(l10n, proxy, proxy.detailText.trim());
}

String _localizedProxyTechnicalText(
  AppLocalizations l10n,
  AppProxySummary proxy,
  String value,
) {
  const urlTestPrefix = 'URLTest · ';
  if (value == 'URLTest' || value == 'URLTest · auto') {
    return l10n.proxyAutomaticSelectionLabel;
  }
  if (value.startsWith(urlTestPrefix)) {
    final detail = value.substring(urlTestPrefix.length).trim();
    return detail.isEmpty
        ? l10n.proxyAutomaticSelectionLabel
        : '${l10n.proxyAutomaticSelectionLabel} · $detail';
  }
  const chainPrefix = 'Chain · ';
  if (value == 'Chain') {
    return l10n.proxyChainLabel;
  }
  if (value.startsWith(chainPrefix)) {
    return '${l10n.proxyChainLabel} · ${value.substring(chainPrefix.length)}';
  }
  if (proxy.isGroup && proxy.childCount > 0 && value.isEmpty) {
    return '${l10n.proxyAutomaticSelectionLabel} · '
        '${l10n.subscriptionServersCount(proxy.childCount)}';
  }
  return value;
}

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
    this.onHeaderTap,
    this.runtimeStates,
    this.groupChildrenByTag = const <String, List<AppProxySummary>>{},
  });

  final List<AppProxySummary> proxies;
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
  final VoidCallback? onHeaderTap;
  final ProxyRuntimeVisualStore? runtimeStates;
  final Map<String, List<AppProxySummary>> groupChildrenByTag;

  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> {
  late ProxySort _sort;
  List<AppProxySummary> _visibleItems = const [];
  double _proxySheetHeaderScrollCollapse = 0;
  bool _groupSheetOpen = false;
  List<_ProxyListEntry>? _visibleEntriesCache;
  List<AppProxySummary>? _visibleEntriesItemsCache;
  ProxySort? _visibleEntriesSortCache;
  bool _embeddedListActivated = false;
  bool? _visibleEntriesCanAddChainCache;
  bool Function(String tag)? _visibleEntriesChainPredicateCache;

  bool _isProxyChain(AppProxySummary proxy) =>
      widget.isProxyChainTag?.call(proxy.tag) ?? false;

  ProxyPanelMetrics? get _sheetMetrics => widget.sheetMetricsListenable?.value;

  bool get _effectiveSheetAtMaxExtent =>
      _sheetMetrics?.atMaxExtent ?? widget.sheetAtMaxExtent;

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
    final pinnedItems = <AppProxySummary>[];
    final visibleItems = <AppProxySummary>[];
    for (final proxy in widget.proxies) {
      final parentTag = proxy.parentGroupTag;
      if (parentTag != null && parentTag.isNotEmpty) {
        continue;
      }
      if (_isPinnedHeaderProxy(proxy)) {
        pinnedItems.add(proxy);
      } else {
        visibleItems.add(proxy);
      }
    }

    _sortItems(visibleItems);
    _visibleItems = [...pinnedItems, ...visibleItems];
    _invalidateVisibleEntries();
    _visibleEntriesImpl();
  }

  bool _isPinnedHeaderProxy(AppProxySummary proxy) =>
      isLowestProxyTag(proxy.tag) || _isProxyChain(proxy);

  List<_ProxyListEntry> _visibleEntries() {
    if (kDebugMode) {
      return developer.Timeline.timeSync(
        'ProxiesPage._visibleEntries',
        _visibleEntriesImpl,
        arguments: <String, Object?>{
          'visibleItems': _visibleItems.length,
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
        _visibleEntriesCanAddChainCache == (widget.onAddProxyChain != null) &&
        _visibleEntriesChainPredicateCache == widget.isProxyChainTag) {
      return cached;
    }
    final primary = <AppProxySummary>[];
    final chains = <AppProxySummary>[];
    final rest = <AppProxySummary>[];
    for (final proxy in _visibleItems) {
      if (isLowestProxyTag(proxy.tag)) {
        primary.add(proxy);
      } else if (_isProxyChain(proxy)) {
        chains.add(proxy);
      } else {
        rest.add(proxy);
      }
    }
    int byPinnedOrder(AppProxySummary a, AppProxySummary b) =>
        pinnedProxyTagOrder(a.tag).compareTo(pinnedProxyTagOrder(b.tag));
    primary.sort(byPinnedOrder);
    final hasPinnedHeader =
        primary.isNotEmpty ||
        chains.isNotEmpty ||
        widget.onAddProxyChain != null;
    final entries = <_ProxyListEntry>[
      for (final proxy in primary) _ProxyListEntry.tile(proxy),
      for (final proxy in chains) _ProxyListEntry.tile(proxy),
      if (widget.onAddProxyChain != null) const _ProxyListEntry.addChain(),
      if (rest.isNotEmpty && hasPinnedHeader) const _ProxyListEntry.divider(),
      for (final proxy in rest) _ProxyListEntry.tile(proxy),
    ];
    _visibleEntriesCache = entries;
    _visibleEntriesItemsCache = _visibleItems;
    _visibleEntriesSortCache = _sort;
    _visibleEntriesCanAddChainCache = widget.onAddProxyChain != null;
    _visibleEntriesChainPredicateCache = widget.isProxyChainTag;
    return entries;
  }

  void _invalidateVisibleEntries() {
    _visibleEntriesCache = null;
    _visibleEntriesItemsCache = null;
    _visibleEntriesSortCache = null;
    _visibleEntriesCanAddChainCache = null;
    _visibleEntriesChainPredicateCache = null;
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
    final headerScrollCollapse = effectiveSheetAtMaxExtent
        ? _proxySheetHeaderScrollCollapse
        : 0.0;
    final headerHeight = _proxySheetHeaderHeightForCollapse(
      headerScrollCollapse,
    );
    final compactListTopPadding = max(headerHeight + 6, 84).toDouble();
    final listTopPadding = compactListTopPadding;
    if (effectiveSheetAtMaxExtent) {
      _embeddedListActivated = true;
    }
    final listMounted = _embeddedListActivated;
    final list = Builder(
      builder: (context) {
        final entries = listMounted
            ? _visibleEntries()
            : const <_ProxyListEntry>[];
        return ListView.builder(
          controller: widget.scrollController,
          physics: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemExtent: _kProxySheetRowExtent,
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          addSemanticIndexes: false,
          padding: listMounted
              ? EdgeInsets.only(top: listTopPadding, bottom: bottomInset + 20)
              : EdgeInsets.zero,
          itemCount: !listMounted
              ? 0
              : widget.proxies.isEmpty
              ? 1
              : entries.length,
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
              ignoring: !effectiveSheetAtMaxExtent,
              child: _buildEmbeddedEntry(
                context: context,
                l10n: l10n,
                entry: entry,
              ),
            );
          },
        );
      },
    );
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
          NotificationListener<ScrollNotification>(
            onNotification: _handleEmbeddedScrollNotification,
            child: RepaintBoundary(child: list),
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
      case _ProxyListEntryType.addChain:
        return _AddProxyChainTile(onTap: _openAddProxyChainSheet);
      case _ProxyListEntryType.divider:
        return const _ProxyListDivider();
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
              !isSyntheticProxyTag(proxy.tag),
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
    final l10n = AppLocalizations.of(context);
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
              title: Text(_localizedProxyTitle(l10n, proxy)),
              subtitle: Text(_localizedProxyDetail(l10n, proxy)),
            ),
            if (widget.onChangeProxyChainDetour != null)
              ListTile(
                leading: const Icon(FluentIcons.arrow_routing_24_regular),
                title: Text(l10n.proxyChainChangeFirstHop),
                onTap: () => Navigator.of(context).pop(_ProxyChainAction.edit),
              ),
            if (widget.onRenameProxyChain != null)
              ListTile(
                leading: const Icon(FluentIcons.edit_24_regular),
                title: Text(l10n.proxyChainRenameAction),
                onTap: () =>
                    Navigator.of(context).pop(_ProxyChainAction.rename),
              ),
            ListTile(
              leading: const Icon(FluentIcons.delete_24_regular),
              title: Text(l10n.proxyChainRemoveAction),
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
    final l10n = AppLocalizations.of(context);
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
              l10n.proxyChainRenameTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: l10n.proxyChainNameLabel),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(l10n.proxyChainSaveAction),
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

enum _ProxyListEntryType { tile, addChain, divider }

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
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              l10n.proxyChainChangeFirstHop,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final proxy in detours)
            ListTile(
              leading: CountryFlagBadge(countryCode: proxy.countryCode),
              title: Text(
                _localizedProxyTitle(l10n, proxy),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _localizedProxyDetail(l10n, proxy),
                overflow: TextOverflow.ellipsis,
              ),
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
    final l10n = AppLocalizations.of(context);
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
              Text(l10n.proxyChainAddTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _detourTag,
                decoration: InputDecoration(
                  labelText: l10n.proxyChainFirstHopLabel,
                ),
                items: widget.detours
                    .map(
                      (proxy) => DropdownMenuItem(
                        value: proxy.tag,
                        child: Text(
                          _localizedProxyTitle(l10n, proxy),
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
                  decoration: InputDecoration(
                    labelText: l10n.subscriptionsTitle,
                  ),
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
                decoration: InputDecoration(
                  labelText: l10n.proxyChainExitLabel,
                  prefixIcon: const Icon(FluentIcons.search_24_regular),
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
                          l10n.proxyChainNothingFound,
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
                              _localizedProxyTitle(l10n, proxy),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _localizedProxyDetail(l10n, proxy),
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
                child: Text(l10n.add),
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
  const _ProxyListEntry.addChain() : this._(_ProxyListEntryType.addChain);
  const _ProxyListEntry.divider() : this._(_ProxyListEntryType.divider);

  final _ProxyListEntryType type;
  final AppProxySummary? proxy;
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
    final toolbarTop = lerpDouble(18, 8, collapse)!;
    final toolbarBottom = lerpDouble(0, 4, collapse)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
            if (activeProxy != null)
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
              child: IgnorePointer(
                ignoring: headerOpacity < .85,
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
            ),
            Positioned(
              left: 16,
              right: 16,
              top: toolbarTop,
              bottom: toolbarBottom,
              child: IgnorePointer(
                ignoring: headerOpacity < .85,
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
            ),
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
    if (connected && proxy.ipChecking && proxy.ip.trim().isEmpty) {
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
    final l10n = AppLocalizations.of(context);
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
                          _localizedProxyTitle(l10n, proxy),
                          key: ValueKey(_localizedProxyTitle(l10n, proxy)),
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

class _AddProxyChainTile extends StatelessWidget {
  const _AddProxyChainTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
                  '+ ${l10n.proxyChainAddTile}',
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

class _GroupOutboundsSheetBodyState extends State<_GroupOutboundsSheetBody> {
  late ProxySort _sort;
  late String _selectedTag;
  List<AppProxySummary>? _sortedChildrenCache;
  ProxySort? _sortedChildrenSort;

  @override
  void initState() {
    super.initState();
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
    sortProxySummaries(children, _sort, keepPinnedFirst: false);
    _sortedChildrenCache = children;
    _sortedChildrenSort = _sort;
    return children;
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

    final groupBaseTitle = isLowestProxyTag(widget.group.tag)
        ? _localizedLowestBaseLabel(l10n, widget.group.tag)
        : widget.group.displayName;
    final groupTitle = activeChild == null
        ? groupBaseTitle
        : '$groupBaseTitle · ${_localizedProxyTitle(l10n, activeChild)}';
    final groupSubtitle = activeChild == null
        ? l10n.proxyAutomaticSelectionLabel
        : '${l10n.proxyAutomaticSelectionLabel} · '
              '${_localizedProxySubtitle(l10n, activeChild)}';

    final viewportSize = MediaQuery.sizeOf(context);
    final topReserve = (appSystemStatusBarInset(context) + 8)
        .clamp(0.0, max(0.0, viewportSize.height - _kProxySheetHeaderHeight))
        .toDouble();
    final panelRect = Rect.fromLTWH(
      0,
      topReserve,
      viewportSize.width,
      viewportSize.height - topReserve,
    );
    final sheetBody = RepaintBoundary(
      child: SizedBox(
        width: panelRect.width,
        height: panelRect.height,
        child: Stack(
          children: [
            ListView.builder(
              physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
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
                  highlighted: proxy.tag == activeChildTag || proxy.highlighted,
                  onTap: () => _select(proxy.tag),
                  onLongPress: () => _openProxyShareSheet(proxy),
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AnimatedBuilder(
                animation: widget.routeAnimation,
                builder: (context, child) => _ProxySheetHeaderBackdrop(
                  enabled:
                      widget.progressiveBlurEnabled &&
                      widget.routeAnimation.value >= 0.985,
                  cornerRadius: 28,
                  height: _kProxySheetHeaderHeight,
                  child: child!,
                ),
                child: _GroupOutboundsSheetHeader(
                  title: l10n.proxySelectorTitle,
                  l10n: l10n,
                  sort: _sort,
                  onSortSelected: _setSort,
                  onClose: () => Navigator.of(context).pop(),
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
          final raw = widget.routeAnimation.value.clamp(0.0, 1.0).toDouble();
          final progress = Curves.easeOutCubic.transform(raw);
          final scrimProgress = Curves.easeInOutCubic.transform(raw);
          final animatedRect = panelRect.shift(
            Offset(0, panelRect.height * (1 - progress)),
          );
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
                rect: animatedRect,
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
  });

  final String title;
  final AppLocalizations l10n;
  final ProxySort sort;
  final ValueChanged<ProxySort> onSortSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
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
    final l10n = AppLocalizations.of(context);
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
                    _localizedProxyTitle(l10n, proxy),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _localizedProxySubtitle(l10n, proxy),
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
        : latencyChecking
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
        : latencyChecking
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
      checking: latencyChecking && !selecting,
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
                  titleOverride ?? _localizedProxyTitle(l10n, proxy),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleOverride ?? _localizedProxySubtitle(l10n, proxy),
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
                                    message: _localizedProxyTitle(l10n, proxy),
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
