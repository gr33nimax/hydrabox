import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/app/bounded_task_runner.dart';
import 'package:meow_client/core/demo_utils.dart';
import 'package:meow_client/core/security/sensitive_clipboard.dart';
import 'package:meow_client/core/widgets/app_notice.dart';
import 'package:meow_client/data/backup/etonify_backup_service.dart';
import 'package:meow_client/data/subscription/happ_crypto_link.dart';
import 'package:meow_client/data/subscription/subscription_failure.dart';
import 'package:meow_client/data/subscription/subscription_fetcher.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/features/subscriptions/subscription_error_message.dart';
import 'package:meow_client/features/subscriptions/subscription_file_reader.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:meow_client/widgets/country_flag_badge.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

const _kSubscriptionProxyPreviewLimit = 50;
const _kSubscriptionOperationSoftWarningDelay = Duration(seconds: 15);
const _kSubscriptionOperationTimeout = Duration(seconds: 30);
const _kSubscriptionSheetMinExtent = .28;
const _kSubscriptionSheetListExtent = .38;
const _kSubscriptionSheetAddQuickExtent = .44;
const _kSubscriptionSheetAddManualExtent = .92;
const _kSubscriptionSheetMaxExtent = .92;
const _kSubscriptionSheetHeaderHeight = 104.0;
const _kAddSubscriptionSheetHeaderHeight = 132.0;
const _kSubscriptionSheetAnimationDuration = Duration(milliseconds: 260);
const _kSubscriptionSummaryHydrationDelay = Duration(milliseconds: 420);
const _kAutoRefreshOptions = <int>[0, 60, 180, 360, 720, 1440];
final _kSingleLineFormatter = FilteringTextInputFormatter.deny(
  RegExp(r'[\r\n]'),
);

int _visibleProxyCount(Iterable<Outbound> outbounds) {
  return outbounds
      .where((outbound) => !outbound.info.deleted)
      .where((outbound) => outbound.config['_group_only'] != true)
      .length;
}

enum _HappImportDecision { sendHwid, withoutHwid }

enum _SubscriptionSortMode { manual, name, updated, servers }

enum _SubscriptionsSheetMode { list, add }

class _LocalizedSubscriptionPageError implements Exception {
  const _LocalizedSubscriptionPageError(this.message);

  final String message;

  @override
  String toString() => message;
}

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({
    super.key,
    this.activeSubscriptionId,
    this.openAddOnStart = false,
    this.hapticEnabled = true,
  });

  final String? activeSubscriptionId;
  final bool openAddOnStart;
  final bool hapticEnabled;

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  ScrollController? _sheetScrollController;
  List<Subscription> _subscriptions = [];
  final Set<String> _selectedIds = <String>{};
  final Set<String> _refreshingIds = <String>{};
  final Map<String, int> _subscriptionServerCounts = <String, int>{};
  final Set<String> _subscriptionsWithRawPayload = <String>{};
  int _countHydrationGeneration = 0;
  Timer? _countHydrationTimer;
  late _SubscriptionsSheetMode _sheetMode;
  _AddSubscriptionSheetMode _addSheetMode = _AddSubscriptionSheetMode.quick;
  int _addModeTransitionGeneration = 0;
  bool _closingFromMinExtent = false;
  bool _loading = false;
  int _refreshAllCompleted = 0;
  int _refreshAllTotal = 0;
  String? _error;

  bool get _addOnly => widget.openAddOnStart;
  bool get _selectionMode => _selectedIds.isNotEmpty;
  double get _sheetMaxExtent =>
      _sheetMode == _SubscriptionsSheetMode.add &&
          _addSheetMode == _AddSubscriptionSheetMode.quick
      ? _kSubscriptionSheetAddQuickExtent
      : _kSubscriptionSheetMaxExtent;

  void _haptic() {
    if (widget.hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void initState() {
    super.initState();
    _sheetMode = _addOnly
        ? _SubscriptionsSheetMode.add
        : _SubscriptionsSheetMode.list;
    if (!_addOnly) {
      _reload();
    }
  }

  @override
  void dispose() {
    _countHydrationTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  void _reload() {
    final generation = ++_countHydrationGeneration;
    unawaited(_reloadMetadataInBackground(generation));
  }

  Future<void> _reloadMetadataInBackground(int generation) async {
    final subscriptions = await SubscriptionStore.getAllMetadataInBackground();
    if (!mounted || generation != _countHydrationGeneration) {
      return;
    }
    setState(() {
      _subscriptions = subscriptions;
      for (final subscription in _subscriptions) {
        if (subscription.cachedVisibleProxyCount >= 0) {
          _subscriptionServerCounts[subscription.id] =
              subscription.cachedVisibleProxyCount;
          if (subscription.hasRawPayload) {
            _subscriptionsWithRawPayload.add(subscription.id);
          } else {
            _subscriptionsWithRawPayload.remove(subscription.id);
          }
        } else {
          _subscriptionServerCounts.remove(subscription.id);
          _subscriptionsWithRawPayload.remove(subscription.id);
        }
      }
      final ids = _subscriptions.map((subscription) => subscription.id).toSet();
      _subscriptionServerCounts.removeWhere((id, _) => !ids.contains(id));
      _subscriptionsWithRawPayload.removeWhere((id) => !ids.contains(id));
      _selectedIds.removeWhere(
        (id) => !_subscriptions.any((subscription) => subscription.id == id),
      );
      _refreshingIds.removeWhere(
        (id) => !_subscriptions.any((subscription) => subscription.id == id),
      );
    });
    _countHydrationTimer?.cancel();
    if (_subscriptions.any((sub) => sub.cachedVisibleProxyCount < 0)) {
      _countHydrationTimer = Timer(
        _kSubscriptionSummaryHydrationDelay,
        () => unawaited(_hydrateSubscriptionCounts(generation)),
      );
    }
  }

  Future<void> _hydrateSubscriptionCounts(int generation) async {
    final snapshot = _subscriptions
        .where((subscription) => subscription.cachedVisibleProxyCount < 0)
        .toList(growable: false);
    final counts = <String, int>{};
    final rawPayloadIds = <String>{};
    final summaries = <String, ({int visibleProxyCount, bool hasRawPayload})>{};
    for (final subscription in snapshot) {
      if (generation != _countHydrationGeneration) {
        return;
      }
      var hydrated = subscription;
      if (subscription.outbounds.isEmpty) {
        hydrated = await SubscriptionStore.withPayloadInBackground(
          subscription,
        );
      }
      final visibleProxyCount = _visibleProxyCount(hydrated.outbounds);
      final hasRawPayload = hydrated.rawContent.trim().length > 16;
      counts[subscription.id] = visibleProxyCount;
      summaries[subscription.id] = (
        visibleProxyCount: visibleProxyCount,
        hasRawPayload: hasRawPayload,
      );
      if (hasRawPayload) {
        rawPayloadIds.add(subscription.id);
      }
    }
    if (!mounted || generation != _countHydrationGeneration) {
      return;
    }
    setState(() {
      _subscriptionServerCounts.addAll(counts);
      _subscriptionsWithRawPayload.addAll(rawPayloadIds);
    });
    unawaited(SubscriptionStore.cachePayloadSummaries(summaries));
  }

  Future<T> _runSubscriptionOperationWithWarning<T>(Future<T> operation) async {
    var completed = false;
    final timer = Timer(_kSubscriptionOperationSoftWarningDelay, () {
      if (!completed && mounted) {
        AppNotice.show(
          context,
          AppLocalizations.of(context).subscriptionOperationSlowWarning,
          tone: AppNoticeTone.warning,
        );
      }
    });
    try {
      return await operation;
    } on TimeoutException {
      throw _LocalizedSubscriptionPageError(
        AppLocalizations.of(context).subscriptionOperationTimeout,
      );
    } finally {
      completed = true;
      timer.cancel();
    }
  }

  String _userFacingSubscriptionError(Object error) {
    if (error is _LocalizedSubscriptionPageError) {
      return error.message;
    }
    return subscriptionErrorMessage(error, AppLocalizations.of(context));
  }

  Future<Subscription> _maybeHandleMovedSubscription(Subscription sub) async {
    final info = sub.info;
    final movedUrl = info?.newUrl;
    final l10n = AppLocalizations.of(context);
    if (!mounted ||
        info == null ||
        info.ignoreSubscriptionMoved ||
        movedUrl == null ||
        movedUrl.isEmpty ||
        movedUrl == sub.url) {
      return sub;
    }

    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.subscriptionMovedTitle),
        content: Text('${l10n.movedSubscriptionMessage}\n\n$movedUrl'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.ignoreAction),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.updateUrlAction),
          ),
        ],
      ),
    );

    if (decision == true) {
      final updated = sub.copyWith(
        url: movedUrl,
        info: info.copyWith(newUrl: null, ignoreSubscriptionMoved: false),
      );
      await SubscriptionStore.save(updated);
      return updated;
    }

    final ignored = sub.copyWith(
      info: info.copyWith(ignoreSubscriptionMoved: true),
    );
    await SubscriptionStore.save(ignored);
    return ignored;
  }

  void _addSubscription() {
    if (_sheetMode == _SubscriptionsSheetMode.add) {
      return;
    }
    _haptic();
    _countHydrationTimer?.cancel();
    _countHydrationGeneration++;
    _addModeTransitionGeneration++;
    setState(() {
      _sheetMode = _SubscriptionsSheetMode.add;
      _addSheetMode = _AddSubscriptionSheetMode.quick;
    });
    unawaited(
      _animateSheetTo(_kSubscriptionSheetAddQuickExtent, resetScroll: true),
    );
  }

  void _closeAddSubscription({required bool changed}) {
    if (_addOnly) {
      Navigator.of(context).pop(changed);
      return;
    }
    _addModeTransitionGeneration++;
    setState(() => _sheetMode = _SubscriptionsSheetMode.list);
    unawaited(
      _animateSheetTo(
        _kSubscriptionSheetListExtent,
        resetScroll: true,
      ).whenComplete(() {
        if (changed && mounted && _sheetMode == _SubscriptionsSheetMode.list) {
          _reload();
        }
      }),
    );
  }

  void _handleAddModeChanged(_AddSubscriptionSheetMode mode) {
    final generation = ++_addModeTransitionGeneration;
    if (mode == _AddSubscriptionSheetMode.manual) {
      setState(() => _addSheetMode = mode);
    }
    unawaited(
      _animateSheetTo(
        mode == _AddSubscriptionSheetMode.manual
            ? _kSubscriptionSheetAddManualExtent
            : _kSubscriptionSheetAddQuickExtent,
        resetScroll: true,
      ).whenComplete(() {
        if (!mounted ||
            generation != _addModeTransitionGeneration ||
            _sheetMode != _SubscriptionsSheetMode.add ||
            mode != _AddSubscriptionSheetMode.quick) {
          return;
        }
        setState(() => _addSheetMode = mode);
      }),
    );
  }

  Future<void> _animateSheetTo(
    double extent, {
    bool resetScroll = false,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_sheetController.isAttached) {
      return;
    }
    if (resetScroll) {
      final scrollController = _sheetScrollController;
      if (scrollController != null && scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.minScrollExtent);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_sheetController.isAttached) {
          return;
        }
      }
    }
    await _sheetController.animateTo(
      extent.clamp(_kSubscriptionSheetMinExtent, _sheetMaxExtent),
      duration: _kSubscriptionSheetAnimationDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _handleSheetHeaderDragUpdate(DragUpdateDetails details) {
    if (!_sheetController.isAttached) {
      return;
    }
    final availableHeight = MediaQuery.sizeOf(context).height;
    if (availableHeight <= 0) {
      return;
    }
    final nextExtent =
        (_sheetController.size - details.delta.dy / availableHeight).clamp(
          _kSubscriptionSheetMinExtent,
          _sheetMaxExtent,
        );
    _sheetController.jumpTo(nextExtent);
  }

  void _handleSheetHeaderDragEnd(DragEndDetails details) {
    if (!_sheetController.isAttached) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final current = _sheetController.size;
    final addMode = _sheetMode == _SubscriptionsSheetMode.add;
    final compactExtent = addMode
        ? _kSubscriptionSheetAddQuickExtent
        : _kSubscriptionSheetListExtent;
    if (current <= _kSubscriptionSheetMinExtent + .015 ||
        (velocity > 900 && current <= compactExtent + .08)) {
      if (addMode && !_addOnly) {
        _closeAddSubscription(changed: false);
      } else {
        Navigator.of(context).maybePop();
      }
      return;
    }
    final target = velocity < -650 || current > (compactExtent + .18)
        ? _sheetMaxExtent
        : compactExtent;
    unawaited(_animateSheetTo(target));
  }

  bool _handleSheetNotification(DraggableScrollableNotification notification) {
    if (notification.extent > _kSubscriptionSheetMinExtent + .002 ||
        _closingFromMinExtent) {
      return false;
    }
    _closingFromMinExtent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _closingFromMinExtent = false;
      if (_sheetMode == _SubscriptionsSheetMode.add && !_addOnly) {
        _closeAddSubscription(changed: false);
      } else {
        Navigator.of(context).maybePop();
      }
    });
    return false;
  }

  Future<bool> _importAddResult(_AddResult result) async {
    try {
      final prepared = await _prepareSubscriptionImport(result);
      if (prepared == null) {
        return false;
      }

      final createdResult = await _runSubscriptionOperationWithWarning(
        prepared.fileContent != null
            ? SubscriptionStore.addFromContent(
                prepared.fileContent!,
                customName: result.name.isNotEmpty ? result.name : null,
                sourceName: prepared.sourceName,
                operationTimeout: _kSubscriptionOperationTimeout,
                isCancelled: result.isCancelled,
              )
            : SubscriptionStore.addFromUrl(
                prepared.url!,
                customName: result.name.isNotEmpty ? result.name : null,
                autoRefreshMinutes: result.autoRefreshMinutes,
                requestInfo: prepared.requestInfo,
                operationTimeout: _kSubscriptionOperationTimeout,
                isCancelled: result.isCancelled,
              ),
      );
      final created = createdResult.subscription;
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        if (createdResult.hasWarning) {
          AppNotice.show(
            context,
            subscriptionSavedWarningMessage(createdResult.warning, l10n),
            tone: AppNoticeTone.warning,
          );
        }
        if (prepared.fileContent == null) {
          await _offerLikelyHwidFix(created);
        }
      }
      await _maybeHandleMovedSubscription(created);
      if (mounted) {
        setState(() {
          _subscriptionServerCounts[created.id] = _visibleProxyCount(
            created.outbounds,
          );
          if (created.rawContent.trim().length > 16) {
            _subscriptionsWithRawPayload.add(created.id);
          }
        });
      }
      return true;
    } on SubscriptionImportCancelledException {
      rethrow;
    } catch (e) {
      AppLogStore.warning(
        'subscription',
        'Subscription import failed: ${e.runtimeType}: $e',
      );
      throw _LocalizedSubscriptionPageError(_userFacingSubscriptionError(e));
    }
  }

  Future<_PreparedSubscriptionImport?> _prepareSubscriptionImport(
    _AddResult result,
  ) async {
    if (result.fileContent != null) {
      return _PreparedSubscriptionImport(
        fileContent: result.fileContent,
        sourceName: result.sourceName,
      );
    }

    final rawUrl = result.url.trim();
    if (!HappCryptoLinkDecoder.isSupportedLink(rawUrl)) {
      return _PreparedSubscriptionImport(
        url: rawUrl,
        requestInfo: result.requestInfo,
      );
    }

    final decision = await _showHappImportDialog();
    if (decision == null) {
      return null;
    }

    final prepared = await HappCryptoLinkDecoder.prepare(rawUrl);
    final requestInfo = switch (decision) {
      _HappImportDecision.sendHwid => prepared.requestInfo,
      _HappImportDecision.withoutHwid => prepared.requestInfo?.copyWith(
        requireHwid: false,
      ),
    };
    return _PreparedSubscriptionImport(
      url: prepared.resolvedUrl,
      requestInfo: _mergeSubscriptionRequestInfo(
        requestInfo,
        result.requestInfo,
      ),
    );
  }

  SubscriptionInfo? _mergeSubscriptionRequestInfo(
    SubscriptionInfo? base,
    SubscriptionInfo? override,
  ) {
    if (base == null) {
      return override;
    }
    if (override == null) {
      return base;
    }
    return SubscriptionInfo(
      title: base.title,
      upload: base.upload,
      download: base.download,
      total: base.total,
      expire: base.expire,
      happCryptoLink: base.happCryptoLink,
      supportUrl: base.supportUrl,
      webPageUrl: base.webPageUrl,
      newUrl: base.newUrl,
      ignoreSubscriptionMoved: base.ignoreSubscriptionMoved,
      updateIntervalHours: base.updateIntervalHours,
      perAppProxyMode: base.perAppProxyMode,
      perAppProxyList: base.perAppProxyList,
      customUserAgent: override.customUserAgent ?? base.customUserAgent,
      customRequestHeader:
          override.customRequestHeader ?? base.customRequestHeader,
      requireHwid: base.requireHwid || override.requireHwid,
      customHwid: override.customHwid ?? base.customHwid,
    );
  }

  Future<_HappImportDecision?> _showHappImportDialog() {
    final l10n = AppLocalizations.of(context);
    return showDialog<_HappImportDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.happImportTitle),
        content: Text(l10n.happImportMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(dialogContext).cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_HappImportDecision.withoutHwid),
            child: Text(l10n.deepLinkImportHappWithoutHwidAction),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_HappImportDecision.sendHwid),
            child: Text(
              AppLocalizations.of(
                dialogContext,
              ).deepLinkImportHappSendHwidAction,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshSubscription(String id) async {
    if (_refreshingIds.contains(id)) {
      return;
    }
    final subscription = await SubscriptionStore.getInBackground(id);
    if (subscription != null &&
        SubscriptionStore.isLocalFileImportUrl(subscription.url)) {
      setState(() {
        _error = AppLocalizations.of(
          context,
        ).refreshActiveSubscriptionUnavailable;
      });
      return;
    }
    _haptic();
    setState(() {
      _refreshingIds.add(id);
      _error = null;
    });
    try {
      final updated = await _runSubscriptionOperationWithWarning(
        SubscriptionStore.refresh(
          id,
          operationTimeout: _kSubscriptionOperationTimeout,
        ),
      );
      if (mounted) {
        if (!SubscriptionStore.isLocalFileImportUrl(updated.url)) {
          await _offerLikelyHwidFix(updated);
        }
      }
      await _maybeHandleMovedSubscription(updated);
      _reload();
    } catch (e) {
      setState(() => _error = _userFacingSubscriptionError(e));
    } finally {
      if (mounted) {
        setState(() {
          _refreshingIds.remove(id);
        });
      }
    }
  }

  Future<void> _offerLikelyHwidFix(Subscription subscription) async {
    if (!SubscriptionStore.likelyRequiresHwidEnable(subscription) || !mounted) {
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

  Future<void> _enableHwidAndRefreshSubscription(String id) async {
    final current = await SubscriptionStore.getInBackground(id);
    if (current == null) {
      return;
    }
    final info = current.info ?? const SubscriptionInfo();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SubscriptionStore.save(
        current.copyWith(info: info.copyWith(requireHwid: true)),
      );
      final updated = await _runSubscriptionOperationWithWarning(
        SubscriptionStore.refresh(
          id,
          operationTimeout: _kSubscriptionOperationTimeout,
        ),
      );
      if (!mounted) {
        return;
      }
      AppNotice.show(
        context,
        AppLocalizations.of(context).subscriptionHwidEnabledAndUpdated,
        tone: AppNoticeTone.success,
      );
      await _maybeHandleMovedSubscription(updated);
      _reload();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _userFacingSubscriptionError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshAll() async {
    if (_loading) {
      return;
    }
    _haptic();
    final refreshable = _subscriptions
        .where((sub) => !SubscriptionStore.isLocalFileImportUrl(sub.url))
        .toList(growable: false);
    setState(() {
      _loading = true;
      _refreshAllCompleted = 0;
      _refreshAllTotal = refreshable.length;
      _error = null;
    });
    try {
      final results = await _runSubscriptionOperationWithWarning(
        runBoundedTasks<Subscription>(
          refreshable
              .map<Future<Subscription> Function()>(
                (sub) =>
                    () => SubscriptionStore.refresh(
                      sub.id,
                      operationTimeout: _kSubscriptionOperationTimeout,
                    ),
              )
              .toList(growable: false),
          concurrency: 2,
          onSettled: (completed, total) {
            if (mounted) {
              setState(() {
                _refreshAllCompleted = completed;
                _refreshAllTotal = total;
              });
            }
          },
        ),
      );
      final updated = results
          .whereType<BoundedTaskSuccess<Subscription>>()
          .length;
      final failed = results.length - updated;
      _reload();
      if (!mounted) {
        return;
      }
      AppNotice.show(
        context,
        AppLocalizations.of(
          context,
        ).subscriptionsRefreshAllComplete(updated, failed),
        tone: failed > 0 ? AppNoticeTone.warning : AppNoticeTone.success,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshAllCompleted = 0;
          _refreshAllTotal = 0;
        });
      }
    }
  }

  Future<void> _deleteSubscription(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteSubscription),
        content: Text(l10n.deleteSubscriptionConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _haptic();
      await SubscriptionStore.delete(id);
      _reload();
    }
  }

  void _toggleSelection(String id) {
    _haptic();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteSubscription),
        content: Text(l10n.deleteSubscriptionConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    _haptic();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SubscriptionStore.deleteMany(_selectedIds);
      _clearSelection();
      _reload();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _moveSubscriptionUp(String id) async {
    _haptic();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SubscriptionStore.moveUp(id);
      _reload();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sortSubscriptions(_SubscriptionSortMode mode) async {
    if (_subscriptions.length < 2) {
      return;
    }
    _haptic();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = _subscriptions.toList(growable: false);
      switch (mode) {
        case _SubscriptionSortMode.manual:
          break;
        case _SubscriptionSortMode.name:
          next.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        case _SubscriptionSortMode.updated:
          next.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
        case _SubscriptionSortMode.servers:
          next.sort((a, b) {
            final left = _subscriptionServerCounts[a.id] ?? 0;
            final right = _subscriptionServerCounts[b.id] ?? 0;
            return right.compareTo(left);
          });
      }
      if (mounted) {
        setState(() => _subscriptions = next);
      }
      await SubscriptionStore.reorder(next);
      _reload();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _qrShareValue(Subscription subscription) {
    final happCryptoLink = subscription.info?.happCryptoLink?.trim() ?? '';
    if (happCryptoLink.isEmpty) {
      return subscription.url;
    }
    if (happCryptoLink.toLowerCase().startsWith('happ://crypt5/')) {
      return subscription.url;
    }
    return happCryptoLink;
  }

  Future<void> _showSubscriptionQr(
    Subscription subscription, {
    required String title,
  }) async {
    final value = _qrShareValue(subscription).trim();
    if (value.isEmpty ||
        !HappCryptoLinkDecoder.isSupportedSubscriptionUrl(value)) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppLocalizations.of(context).subscriptionQrUnsupported,
        tone: AppNoticeTone.warning,
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _SubscriptionQrPage(title: title, value: value),
      ),
    );
  }

  Future<void> _copySubscriptionUrl(Subscription subscription) async {
    await SensitiveClipboard.copy(subscription.url);
    if (!mounted) {
      return;
    }
    AppNotice.show(
      context,
      AppLocalizations.of(context).subscriptionUrlCopied,
      tone: AppNoticeTone.success,
    );
  }

  Future<void> _copySubscriptionJson(Subscription subscription) async {
    final hydrated =
        await SubscriptionStore.getInBackground(subscription.id) ??
        subscription;
    const encoder = JsonEncoder.withIndent('  ');
    await SensitiveClipboard.copy(encoder.convert(hydrated.toMap()));
    if (!mounted) {
      return;
    }
    AppNotice.show(
      context,
      AppLocalizations.of(context).subscriptionJsonCopied,
      tone: AppNoticeTone.success,
    );
  }

  Future<void> _openSubscriptionDetails(
    Subscription subscription, {
    required int index,
  }) async {
    _haptic();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SubscriptionDetailsPage(
          subscriptionId: subscription.id,
          onRefresh: () => _refreshSubscription(subscription.id),
          onDelete: () => _deleteSubscription(subscription.id),
          onMoveUp: index > 0
              ? () => _moveSubscriptionUp(subscription.id)
              : null,
          hapticEnabled: widget.hapticEnabled,
        ),
      ),
    );
    if (mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final initialExtent = _addOnly
        ? _kSubscriptionSheetAddQuickExtent
        : _subscriptions.isEmpty
        ? .40
        : _kSubscriptionSheetListExtent;

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _handleSheetNotification,
      child: DraggableScrollableSheet(
        controller: _sheetController,
        expand: false,
        initialChildSize: initialExtent,
        minChildSize: _kSubscriptionSheetMinExtent,
        maxChildSize: _sheetMaxExtent,
        builder: (context, scrollController) {
          _sheetScrollController = scrollController;
          return Theme(
            data: settingsTileTheme(context),
            child: RepaintBoundary(
              child: Material(
                key: const ValueKey('subscriptions_sheet_clip'),
                color: cs.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                clipBehavior: Clip.hardEdge,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: _sheetMode == _SubscriptionsSheetMode.add
                      ? _AddSubscriptionSheet(
                          onAdd: _importAddResult,
                          scrollController: scrollController,
                          onClose: (changed) =>
                              _closeAddSubscription(changed: changed),
                          onModeChanged: _handleAddModeChanged,
                          onHeaderDragUpdate: _handleSheetHeaderDragUpdate,
                          onHeaderDragEnd: _handleSheetHeaderDragEnd,
                        )
                      : Stack(
                          children: [
                            CustomScrollView(
                              controller: scrollController,
                              slivers: [
                                const SliverToBoxAdapter(
                                  child: SizedBox(
                                    height: _kSubscriptionSheetHeaderHeight,
                                  ),
                                ),
                                if (_error != null)
                                  SliverToBoxAdapter(
                                    child: Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.fromLTRB(
                                        18,
                                        8,
                                        18,
                                        2,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.errorContainer,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: cs.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_subscriptions.isEmpty)
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _EmptySubscriptionsPanel(
                                      onAdd: _addSubscription,
                                    ),
                                  )
                                else
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      8,
                                      14,
                                      0,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, itemIndex) {
                                          if (itemIndex.isOdd) {
                                            return const Gap(10);
                                          }
                                          final index = itemIndex ~/ 2;
                                          final sub = _subscriptions[index];
                                          final hydratedServerCount =
                                              _subscriptionServerCounts[sub.id];
                                          final serverCount =
                                              hydratedServerCount ??
                                              _visibleProxyCount(sub.outbounds);
                                          final rawLooksNonEmpty =
                                              _subscriptionsWithRawPayload
                                                  .contains(sub.id) ||
                                              (sub.rawContent
                                                      .trim()
                                                      .isNotEmpty &&
                                                  sub.rawContent.trim().length >
                                                      16);
                                          return _SubscriptionCard(
                                            subscription: sub,
                                            serverCount: serverCount,
                                            rawLooksNonEmpty: rawLooksNonEmpty,
                                            active:
                                                sub.id ==
                                                widget.activeSubscriptionId,
                                            multiSelected: _selectedIds
                                                .contains(sub.id),
                                            selectionMode: _selectionMode,
                                            loading:
                                                _loading ||
                                                _refreshingIds.contains(sub.id),
                                            onSelect: () {
                                              if (_selectionMode) {
                                                _toggleSelection(sub.id);
                                              } else {
                                                Navigator.of(
                                                  context,
                                                ).pop(sub.id);
                                              }
                                            },
                                            onLongPress: () =>
                                                _toggleSelection(sub.id),
                                            onRefresh: () =>
                                                _refreshSubscription(sub.id),
                                            onCopyUrl: () =>
                                                _copySubscriptionUrl(sub),
                                            onShowQr: () => _showSubscriptionQr(
                                              sub,
                                              title: sub.name,
                                            ),
                                            onCopyJson: () =>
                                                _copySubscriptionJson(sub),
                                            onEdit: () =>
                                                _openSubscriptionDetails(
                                                  sub,
                                                  index: index,
                                                ),
                                            onDelete: () =>
                                                _deleteSubscription(sub.id),
                                          );
                                        },
                                        childCount:
                                            _subscriptions.length * 2 - 1,
                                      ),
                                    ),
                                  ),
                                SliverToBoxAdapter(
                                  child: SizedBox(height: bottomPadding + 14),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.topCenter,
                              child: _SubscriptionsSheetHeader(
                                title: _selectionMode
                                    ? '${_selectedIds.length}'
                                    : _loading && _refreshAllTotal > 0
                                    ? l10n.subscriptionsRefreshAllProgress(
                                        _refreshAllCompleted,
                                        _refreshAllTotal,
                                      )
                                    : l10n.subscriptionsTitle,
                                selectionMode: _selectionMode,
                                loading: _loading,
                                canSort: _subscriptions.length > 1,
                                canRefreshAll: _subscriptions.isNotEmpty,
                                onSortSelected: (mode) {
                                  _haptic();
                                  unawaited(_sortSubscriptions(mode));
                                },
                                onRefreshAll: _refreshAll,
                                onAdd: _addSubscription,
                                onDeleteSelected: _deleteSelected,
                                onClearSelection: _clearSelection,
                                onClose: () => Navigator.of(context).pop(),
                                onVerticalDragUpdate:
                                    _handleSheetHeaderDragUpdate,
                                onVerticalDragEnd: _handleSheetHeaderDragEnd,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SubscriptionsSheetHeader extends StatelessWidget {
  const _SubscriptionsSheetHeader({
    required this.title,
    required this.selectionMode,
    required this.loading,
    required this.canSort,
    required this.canRefreshAll,
    required this.onSortSelected,
    required this.onRefreshAll,
    required this.onAdd,
    required this.onDeleteSelected,
    required this.onClearSelection,
    required this.onClose,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final String title;
  final bool selectionMode;
  final bool loading;
  final bool canSort;
  final bool canRefreshAll;
  final ValueChanged<_SubscriptionSortMode> onSortSelected;
  final VoidCallback onRefreshAll;
  final VoidCallback onAdd;
  final VoidCallback onDeleteSelected;
  final VoidCallback onClearSelection;
  final VoidCallback onClose;
  final ValueChanged<DragUpdateDetails> onVerticalDragUpdate;
  final ValueChanged<DragEndDetails> onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: SizedBox(
        height: _kSubscriptionSheetHeaderHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.surface,
                cs.surface.withValues(alpha: .96),
                cs.surface.withValues(alpha: .0),
              ],
              stops: const [0, .74, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 12),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: .34),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (selectionMode) ...[
                      IconButton(
                        onPressed: loading ? null : onDeleteSelected,
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: AppLocalizations.of(context).delete,
                      ),
                      IconButton(
                        onPressed: onClearSelection,
                        icon: const Icon(Icons.close_rounded),
                        tooltip: AppLocalizations.of(context).close,
                      ),
                    ] else ...[
                      _SubscriptionSortMenuButton(
                        enabled: !loading && canSort,
                        onSelected: onSortSelected,
                      ),
                      IconButton(
                        onPressed: loading || !canRefreshAll
                            ? null
                            : onRefreshAll,
                        icon: const Icon(Icons.update_rounded),
                        tooltip: AppLocalizations.of(
                          context,
                        ).refreshSubscriptions,
                      ),
                      IconButton(
                        onPressed: loading ? null : onAdd,
                        icon: const Icon(Icons.add_rounded),
                        tooltip: AppLocalizations.of(context).addSubscription,
                      ),
                      IconButton(
                        onPressed: loading ? null : onClose,
                        icon: const Icon(Icons.close_rounded),
                        tooltip: AppLocalizations.of(context).close,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionSortMenuButton extends StatelessWidget {
  const _SubscriptionSortMenuButton({
    required this.enabled,
    required this.onSelected,
  });

  final bool enabled;
  final ValueChanged<_SubscriptionSortMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(-184, 4),
      menuChildren: [
        _sortItem(
          mode: _SubscriptionSortMode.manual,
          icon: Icons.drag_indicator_rounded,
          label: l10n.subscriptionSortManual,
        ),
        _sortItem(
          mode: _SubscriptionSortMode.name,
          icon: Icons.sort_by_alpha_rounded,
          label: l10n.subscriptionSortByName,
        ),
        _sortItem(
          mode: _SubscriptionSortMode.updated,
          icon: Icons.update_rounded,
          label: l10n.subscriptionSortByUpdated,
        ),
        _sortItem(
          mode: _SubscriptionSortMode.servers,
          icon: Icons.hub_outlined,
          label: l10n.subscriptionSortByServers,
        ),
      ],
      builder: (context, controller, child) => IconButton(
        onPressed: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        icon: const Icon(Icons.sort_rounded),
        tooltip: l10n.sort,
      ),
    );
  }

  MenuItemButton _sortItem({
    required _SubscriptionSortMode mode,
    required IconData icon,
    required String label,
  }) {
    return MenuItemButton(
      leadingIcon: Icon(icon),
      onPressed: () => onSelected(mode),
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(label),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.subscription,
    required this.serverCount,
    required this.rawLooksNonEmpty,
    required this.active,
    required this.multiSelected,
    required this.selectionMode,
    required this.loading,
    required this.onSelect,
    required this.onLongPress,
    required this.onRefresh,
    required this.onCopyUrl,
    required this.onShowQr,
    required this.onCopyJson,
    required this.onEdit,
    required this.onDelete,
  });

  final Subscription subscription;
  final int serverCount;
  final bool rawLooksNonEmpty;
  final bool active;
  final bool multiSelected;
  final bool selectionMode;
  final bool loading;
  final VoidCallback onSelect;
  final VoidCallback onLongPress;
  final VoidCallback onRefresh;
  final VoidCallback onCopyUrl;
  final VoidCallback onShowQr;
  final VoidCallback onCopyJson;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    final info = subscription.info;
    final totalBytes = info?.total;
    final consumedBytes = info?.consumed;
    final remainingDays = info?.remainingDays;
    final hasTraffic = totalBytes != null && totalBytes > 0;
    final hasUnlimitedTraffic = info != null && !hasTraffic;
    final remainingText = remainingDays != null
        ? remainingDays > 0
              ? l10n.daysLeft(remainingDays)
              : l10n.expired
        : info == null
        ? null
        : l10n.daysLeftUnlimited;
    String? usageText;
    if (hasTraffic && consumedBytes != null) {
      usageText = l10n.trafficUsage(
        formatBytes(consumedBytes.toDouble()),
        formatBytes(totalBytes.toDouble()),
      );
    } else if (hasUnlimitedTraffic) {
      usageText = l10n.trafficUsage(
        formatBytes((consumedBytes ?? 0).toDouble()),
        l10n.unlimitedSymbol,
      );
    }
    final refreshable = !SubscriptionStore.isLocalFileImportUrl(
      subscription.url,
    );
    final lastUpdatedText = subscription.lastUpdated > 0
        ? l10n.lastUpdated(
            formatTime(
              DateTime.fromMillisecondsSinceEpoch(subscription.lastUpdated),
            ),
          )
        : null;
    final metaParts = <String>[
      l10n.subscriptionServersCount(serverCount),
      ...?(lastUpdatedText == null ? null : <String>[lastUpdatedText]),
      if (serverCount == 0 && rawLooksNonEmpty)
        l10n.subscriptionReparseRecommended,
    ];
    final highlighted = active || multiSelected;
    return Material(
      color: highlighted
          ? cs.secondaryContainer.withValues(alpha: .28)
          : cs.surfaceContainerLowest.withValues(alpha: .18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: highlighted
              ? cs.primary.withValues(alpha: .55)
              : cs.outlineVariant.withValues(alpha: .44),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (loading)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 54,
                height: 92,
                child: selectionMode
                    ? InkWell(
                        onTap: onSelect,
                        onLongPress: onLongPress,
                        child: Icon(
                          multiSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: multiSelected
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                      )
                    : _SubscriptionActionsMenu(
                        refreshable: refreshable,
                        loading: loading,
                        onRefresh: onRefresh,
                        onCopyUrl: onCopyUrl,
                        onShowQr: onShowQr,
                        onCopyJson: onCopyJson,
                        onEdit: onEdit,
                        onDelete: onDelete,
                      ),
              ),
              SizedBox(
                width: 1,
                height: 70,
                child: ColoredBox(
                  color: highlighted
                      ? cs.primary.withValues(alpha: .34)
                      : cs.outline.withValues(alpha: .24),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onSelect,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 44,
                          decoration: BoxDecoration(
                            color: highlighted
                                ? cs.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const Gap(8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      subscription.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0,
                                          ),
                                    ),
                                  ),
                                  if (remainingText != null) ...[
                                    const Gap(12),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 116,
                                      ),
                                      child: Text(
                                        remainingText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.right,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color:
                                                  remainingDays != null &&
                                                      remainingDays <= 3
                                                  ? cs.error
                                                  : cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const Gap(5),
                              if (info != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: hasTraffic
                                        ? (info.ratio.clamp(0, 1)).toDouble()
                                        : 0,
                                    minHeight: 5,
                                    backgroundColor: cs.surfaceContainerHighest,
                                  ),
                                ),
                              const Gap(5),
                              Text(
                                metaParts.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              if (usageText != null) ...[
                                const Gap(4),
                                Text(
                                  usageText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubscriptionActionsMenu extends StatelessWidget {
  const _SubscriptionActionsMenu({
    required this.refreshable,
    required this.loading,
    required this.onRefresh,
    required this.onCopyUrl,
    required this.onShowQr,
    required this.onCopyJson,
    required this.onEdit,
    required this.onDelete,
  });

  final bool refreshable;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onCopyUrl;
  final VoidCallback onShowQr;
  final VoidCallback onCopyJson;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.refresh_rounded),
          onPressed: refreshable && !loading ? onRefresh : null,
          child: Text(l10n.refresh),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.ios_share_rounded),
          menuChildren: [
            MenuItemButton(
              onPressed: refreshable ? onCopyUrl : null,
              child: Text(l10n.subscriptionCopyUrl),
            ),
            MenuItemButton(
              onPressed: refreshable ? onShowQr : null,
              child: Text(l10n.subscriptionShowUrlQr),
            ),
            MenuItemButton(
              onPressed: onCopyJson,
              child: Text(l10n.subscriptionCopyJson),
            ),
          ],
          child: Text(l10n.shareProxyTitle),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_rounded),
          onPressed: onEdit,
          child: Text(l10n.subscriptionDetailsTitle),
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.delete_outline_rounded, color: cs.error),
          onPressed: loading ? null : onDelete,
          child: Text(
            l10n.delete,
            style: TextStyle(color: loading ? null : cs.error),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return Tooltip(
          message: MaterialLocalizations.of(context).showMenuTooltip,
          child: InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Center(
              child: Icon(
                Icons.more_vert_rounded,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptySubscriptionsPanel extends StatelessWidget {
  const _EmptySubscriptionsPanel({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withValues(alpha: .54),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .42)),
          ),
          child: Column(
            children: [
              SettingsLeadingIcon(
                icon: Icons.add_link_rounded,
                color: cs.primary,
              ),
              const Gap(14),
              Text(
                l10n.noSubscriptions,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const Gap(8),
              Text(
                l10n.addSubscriptionQuickSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Gap(18),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.addSubscription),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionDetailsPage extends StatefulWidget {
  const _SubscriptionDetailsPage({
    required this.subscriptionId,
    required this.onRefresh,
    required this.onDelete,
    required this.onMoveUp,
    required this.hapticEnabled,
  });

  final String subscriptionId;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onDelete;
  final Future<void> Function()? onMoveUp;
  final bool hapticEnabled;

  @override
  State<_SubscriptionDetailsPage> createState() =>
      _SubscriptionDetailsPageState();
}

class _SubscriptionDetailsPageState extends State<_SubscriptionDetailsPage> {
  bool _busy = false;
  Subscription? _currentSubscription;
  late final TextEditingController _nameController;
  late final TextEditingController _customUserAgentController;
  late final TextEditingController _customHwidController;
  late final TextEditingController _customHeadersController;
  late bool _sendHwid;
  late bool _useCustomHwid;

  void _haptic() {
    if (widget.hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void initState() {
    super.initState();
    _currentSubscription = SubscriptionStore.get(widget.subscriptionId);
    final initialSubscription = _subscription;
    final initialInfo = initialSubscription?.info;
    _nameController = TextEditingController(
      text: initialSubscription?.name ?? '',
    );
    _customUserAgentController = TextEditingController(
      text: initialInfo?.customUserAgent ?? '',
    );
    _customHwidController = TextEditingController(
      text: initialInfo?.customHwid ?? '',
    );
    _customHeadersController = TextEditingController(
      text: initialInfo?.customRequestHeader ?? '',
    );
    _sendHwid = initialInfo?.requireHwid ?? false;
    _useCustomHwid = (initialInfo?.customHwid?.trim().isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customUserAgentController.dispose();
    _customHwidController.dispose();
    _customHeadersController.dispose();
    super.dispose();
  }

  Subscription? get _subscription {
    return _currentSubscription;
  }

  void _reloadCurrentSubscription() {
    _currentSubscription = SubscriptionStore.get(widget.subscriptionId);
  }

  bool _hasPendingName(Subscription subscription) {
    final trimmed = _nameController.text.trim();
    return trimmed.isNotEmpty && trimmed != subscription.name;
  }

  Future<void> _saveNameSilently(Subscription subscription) async {
    final trimmed = _nameController.text.trim();
    final nextName = trimmed.isEmpty ? subscription.name : trimmed;
    if (nextName == subscription.name) {
      return;
    }
    await SubscriptionStore.save(subscription.copyWith(name: nextName));
    _reloadCurrentSubscription();
  }

  Future<void> _saveName(Subscription subscription) async {
    final trimmed = _nameController.text.trim();
    final nextName = trimmed.isEmpty ? subscription.name : trimmed;
    if (nextName == subscription.name) {
      return;
    }
    setState(() => _busy = true);
    try {
      await SubscriptionStore.save(subscription.copyWith(name: nextName));
      _reloadCurrentSubscription();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveAutoUpdate(
    Subscription subscription, {
    required bool disabled,
  }) async {
    if (subscription.disableAutoUpdate == disabled) {
      return;
    }
    setState(() => _busy = true);
    try {
      await SubscriptionStore.save(
        subscription.copyWith(disableAutoUpdate: disabled),
      );
      _reloadCurrentSubscription();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveAutoRefreshInterval(
    Subscription subscription,
    int minutes,
  ) async {
    final disabled = minutes <= 0;
    if (subscription.disableAutoUpdate == disabled &&
        (disabled || subscription.autoRefreshMinutes == minutes)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await SubscriptionStore.save(
        subscription.copyWith(
          disableAutoUpdate: disabled,
          autoRefreshMinutes: disabled
              ? subscription.autoRefreshMinutes
              : minutes,
        ),
      );
      _reloadCurrentSubscription();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveMarkAllServersRussia(
    Subscription subscription, {
    required bool enabled,
  }) async {
    if (subscription.markAllServersRussia == enabled) {
      return;
    }
    setState(() => _busy = true);
    try {
      await SubscriptionStore.save(
        subscription.copyWith(markAllServersRussia: enabled),
      );
      _reloadCurrentSubscription();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveRequestSettings(Subscription subscription) async {
    final baseInfo = subscription.info ?? const SubscriptionInfo();
    final customHwid = _useCustomHwid ? _customHwidController.text.trim() : '';
    final customUserAgent = _customUserAgentController.text.trim();
    final customHeaders = _customHeadersController.text.trim();
    setState(() => _busy = true);
    try {
      await SubscriptionStore.save(
        subscription.copyWith(
          info: SubscriptionInfo(
            title: baseInfo.title,
            upload: baseInfo.upload,
            download: baseInfo.download,
            total: baseInfo.total,
            expire: baseInfo.expire,
            happCryptoLink: baseInfo.happCryptoLink,
            supportUrl: baseInfo.supportUrl,
            webPageUrl: baseInfo.webPageUrl,
            newUrl: baseInfo.newUrl,
            ignoreSubscriptionMoved: baseInfo.ignoreSubscriptionMoved,
            updateIntervalHours: baseInfo.updateIntervalHours,
            perAppProxyMode: baseInfo.perAppProxyMode,
            perAppProxyList: baseInfo.perAppProxyList,
            customUserAgent: customUserAgent.isEmpty ? null : customUserAgent,
            customRequestHeader: customHeaders.isEmpty ? null : customHeaders,
            requireHwid: _sendHwid,
            customHwid: customHwid.isEmpty ? null : customHwid,
          ),
        ),
      );
      _reloadCurrentSubscription();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _applyMigratedUrl(Subscription subscription) async {
    final newUrl = subscription.info?.newUrl;
    if (newUrl == null || newUrl.isEmpty || newUrl == subscription.url) {
      return;
    }
    setState(() => _busy = true);
    try {
      await SubscriptionStore.save(
        subscription.copyWith(
          url: newUrl,
          info: subscription.info?.copyWith(
            newUrl: null,
            ignoreSubscriptionMoved: false,
          ),
        ),
      );
      _reloadCurrentSubscription();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  ({String? url, String? error}) _validateEditedSubscriptionUrl(
    String input,
    AppLocalizations l10n,
  ) {
    final urls = input
        .split(RegExp(r'[\r\n]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty) {
      return (url: null, error: l10n.invalidUrl);
    }
    if (urls.length > 1) {
      return (url: null, error: l10n.subscriptionUrlSingleSourceRequired);
    }

    try {
      final uri = SubscriptionFetcher.parseRequestUri(urls.single);
      final scheme = uri.scheme.toLowerCase();
      if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
        return (url: null, error: l10n.invalidUrl);
      }
      return (url: uri.toString(), error: null);
    } on FormatException {
      return (url: null, error: l10n.invalidUrl);
    }
  }

  Future<void> _editSubscriptionUrl(Subscription subscription) async {
    final l10n = AppLocalizations.of(context);
    final editedUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _SubscriptionUrlEditDialog(
        initialValue: subscription.url,
        validate: (input) => _validateEditedSubscriptionUrl(input, l10n),
      ),
    );

    if (!mounted || editedUrl == null || editedUrl == subscription.url) {
      return;
    }
    setState(() => _busy = true);
    try {
      await SubscriptionStore.saveMetadata(
        subscription.copyWith(
          url: editedUrl,
          lastUpdated: 0,
          info: subscription.info?.copyWith(ignoreSubscriptionMoved: false),
        ),
      );
      _reloadCurrentSubscription();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showSubscriptionQr(
    String value, {
    required String title,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        !HappCryptoLinkDecoder.isSupportedSubscriptionUrl(trimmed)) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppLocalizations.of(context).subscriptionQrUnsupported,
        tone: AppNoticeTone.warning,
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _SubscriptionQrPage(title: title, value: trimmed),
      ),
    );
  }

  String _qrShareValue(Subscription subscription) {
    final happCryptoLink = subscription.info?.happCryptoLink?.trim() ?? '';
    if (happCryptoLink.isEmpty) {
      return subscription.url;
    }
    if (happCryptoLink.toLowerCase().startsWith('happ://crypt5/')) {
      return subscription.url;
    }
    return happCryptoLink;
  }

  Future<void> _reparseSubscription(Subscription subscription) async {
    setState(() => _busy = true);
    try {
      await SubscriptionStore.reparseFromRaw(subscription.id);
      _reloadCurrentSubscription();
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppNotice.show(context, error.toString(), tone: AppNoticeTone.error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _formatRefreshInterval(BuildContext context, int minutes) {
    final l10n = AppLocalizations.of(context);
    if (minutes <= 0) {
      return l10n.disabledLabel;
    }
    if (minutes % (60 * 24) == 0) {
      return l10n.refreshIntervalDaysShort(minutes ~/ (60 * 24));
    }
    if (minutes % 60 == 0) {
      return l10n.refreshIntervalHoursShort(minutes ~/ 60);
    }
    return l10n.refreshIntervalMinutesShort(minutes);
  }

  String _summarizeHappCryptoLink(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 32) {
      return trimmed;
    }
    return '${trimmed.substring(0, 32)}...';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final subscription = _subscription;
    if (subscription == null) {
      return const SizedBox.shrink();
    }
    final isLocalFileImport = SubscriptionStore.isLocalFileImportUrl(
      subscription.url,
    );
    final localFileImportName = SubscriptionStore.localFileImportDisplayName(
      subscription.url,
    );

    Future<void> refresh() async {
      setState(() => _busy = true);
      try {
        await widget.onRefresh();
        _reloadCurrentSubscription();
      } finally {
        if (mounted) {
          setState(() => _busy = false);
        }
      }
    }

    Future<void> delete() async {
      final navigator = Navigator.of(context);
      var popped = false;
      setState(() => _busy = true);
      try {
        await widget.onDelete();
        if (mounted) {
          navigator.pop();
          popped = true;
        }
      } finally {
        if (mounted && !popped) {
          setState(() => _busy = false);
        }
      }
    }

    final info = subscription.info;
    final expireSeconds = info?.expire;
    final hasUnlimitedExpire =
        info != null && (expireSeconds == null || expireSeconds <= 0);
    final supportUrl = info?.supportUrl;
    final webPageUrl = info?.webPageUrl;
    final happCryptoLink = info?.happCryptoLink;
    final migratedUrl = info?.newUrl;
    final movedIgnored = info?.ignoreSubscriptionMoved == true;
    final userVisibleOutbounds = subscription.outbounds
        .where((outbound) => outbound.config['_group_only'] != true)
        .toList(growable: false);
    final visibleOutbounds = userVisibleOutbounds
        .take(_kSubscriptionProxyPreviewLimit)
        .toList(growable: false);
    final hiddenOutboundsCount =
        userVisibleOutbounds.length - visibleOutbounds.length;
    final usageText = switch ((info?.consumed, info?.total)) {
      (final consumed?, final total?) when total > 0 => l10n.trafficUsage(
        formatBytes(consumed.toDouble()),
        formatBytes(total.toDouble()),
      ),
      (final consumed?, _) => l10n.trafficUsage(
        formatBytes(consumed.toDouble()),
        l10n.unlimitedSymbol,
      ),
      (_, _) when info != null => l10n.trafficUsage(
        '0 B',
        l10n.unlimitedSymbol,
      ),
      _ => null,
    };
    final untilText = switch (expireSeconds) {
      final seconds? when seconds > 0 => MaterialLocalizations.of(
        context,
      ).formatCompactDate(DateTime.fromMillisecondsSinceEpoch(seconds * 1000)),
      _ => null,
    };
    final untilLabel = untilText != null
        ? l10n.untilDate(untilText)
        : hasUnlimitedExpire
        ? l10n.daysLeftUnlimited
        : null;

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop || _busy || !_hasPendingName(subscription)) {
          return;
        }
        unawaited(_saveNameSilently(subscription));
      },
      child: ProgressiveBlurScaffold(
        appBar: AppBar(
          title: Text(l10n.subscriptionDetailsTitle),
          flexibleSpace: _busy
              ? Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : null,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  12,
                  progressiveHeaderTopPadding(context, 8),
                  12,
                  appBottomSafePadding(context, 24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (widget.onMoveUp != null)
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      _haptic();
                                      await widget.onMoveUp!();
                                    },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                size: 18,
                              ),
                            ),
                          if (!isLocalFileImport)
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      _haptic();
                                      refresh();
                                    },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(l10n.refresh),
                            ),
                          if (!isLocalFileImport)
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      _haptic();
                                      await _reparseSubscription(subscription);
                                    },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(l10n.reparseProxies),
                            ),
                          FilledButton.tonal(
                            onPressed: _busy
                                ? null
                                : () {
                                    _haptic();
                                    delete();
                                  },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(l10n.delete),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Stack(
                            alignment: Alignment.centerRight,
                            children: [
                              TextField(
                                controller: _nameController,
                                onTapOutside: (_) async {
                                  FocusScope.of(context).unfocus();
                                  if (_hasPendingName(subscription)) {
                                    await _saveName(subscription);
                                  }
                                },
                                onSubmitted: (_) => _saveName(subscription),
                                onEditingComplete: () async {
                                  FocusScope.of(context).unfocus();
                                  await _saveName(subscription);
                                },
                                textInputAction: TextInputAction.done,
                                inputFormatters: [_kSingleLineFormatter],
                                minLines: 1,
                                maxLines: 3,
                                keyboardType: TextInputType.text,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: InputDecoration(
                                  hintText: l10n.subscriptionName,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  isDense: true,
                                  filled: true,
                                  fillColor: theme.scaffoldBackgroundColor,
                                  contentPadding: const EdgeInsets.only(
                                    right: 16,
                                  ),
                                ),
                              ),
                              IgnorePointer(
                                child: Opacity(
                                  opacity: 0.38,
                                  child: Text(
                                    '|',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _DetailsBlock(
                      title: isLocalFileImport ? l10n.sourceLabel : 'URL',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isLocalFileImport) ...[
                            IconButton(
                              key: const ValueKey(
                                'edit_subscription_url_button',
                              ),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      _haptic();
                                      await _editSubscriptionUrl(subscription);
                                    },
                              tooltip: l10n.editSubscriptionUrlAction,
                              icon: const Icon(Icons.edit_rounded),
                            ),
                            FilledButton.tonal(
                              onPressed: () async {
                                _haptic();
                                await _showSubscriptionQr(
                                  _qrShareValue(subscription),
                                  title: subscription.name,
                                );
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                l10n.showQrCode,
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
                            const Gap(4),
                            FilledButton.tonal(
                              onPressed: () async {
                                _haptic();
                                await SensitiveClipboard.copy(subscription.url);
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                MaterialLocalizations.of(
                                  context,
                                ).copyButtonLabel,
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
                          ],
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isLocalFileImport)
                            Text(
                              l10n.importedFromFileLabel(
                                localFileImportName ?? subscription.name,
                              ),
                              style: theme.textTheme.bodyMedium,
                            )
                          else
                            SelectableText(
                              subscription.url,
                              style: theme.textTheme.bodyMedium,
                            ),
                          if (happCryptoLink != null &&
                              happCryptoLink.isNotEmpty) ...[
                            Divider(
                              height: 24,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: .45),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.happCryptoLinkImportedLabel,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      const Gap(4),
                                      Text(
                                        _summarizeHappCryptoLink(
                                          happCryptoLink,
                                        ),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Gap(12),
                                FilledButton.tonal(
                                  onPressed: () async {
                                    _haptic();
                                    await SensitiveClipboard.copy(
                                      happCryptoLink,
                                    );
                                  },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    MaterialLocalizations.of(
                                      context,
                                    ).copyButtonLabel,
                                    style: theme.textTheme.labelMedium,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (movedIgnored &&
                        migratedUrl != null &&
                        migratedUrl.isNotEmpty &&
                        migratedUrl != subscription.url)
                      _DetailsBlock(
                        title: l10n.newUrlTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.movedSubscriptionPrompt,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const Gap(6),
                            Text(
                              migratedUrl,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Gap(10),
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      _haptic();
                                      await _applyMigratedUrl(subscription);
                                    },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(l10n.updateUrlAction),
                            ),
                          ],
                        ),
                      ),
                    if (!isLocalFileImport)
                      _DetailsBlock(
                        title: l10n.autoUpdateTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.disableAutoUpdateTitle,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                Switch.adaptive(
                                  value: subscription.disableAutoUpdate,
                                  onChanged: _busy
                                      ? null
                                      : (value) async {
                                          _haptic();
                                          await _saveAutoUpdate(
                                            subscription,
                                            disabled: value,
                                          );
                                        },
                                ),
                              ],
                            ),
                            if (subscription.lastUpdated > 0) ...[
                              const Gap(6),
                              Text(
                                l10n.lastUpdated(
                                  formatTime(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      subscription.lastUpdated,
                                    ),
                                  ),
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const Gap(6),
                            Text(
                              subscription.disableAutoUpdate
                                  ? l10n.refreshesEvery(l10n.disabledLabel)
                                  : l10n.refreshesEvery(
                                      _formatRefreshInterval(
                                        context,
                                        subscription.autoRefreshMinutes,
                                      ),
                                    ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Gap(10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final minutes in _kAutoRefreshOptions)
                                  ChoiceChip(
                                    label: Text(
                                      minutes <= 0
                                          ? l10n.disabledLabel
                                          : _formatRefreshInterval(
                                              context,
                                              minutes,
                                            ),
                                    ),
                                    selected: minutes <= 0
                                        ? subscription.disableAutoUpdate
                                        : !subscription.disableAutoUpdate &&
                                              subscription.autoRefreshMinutes ==
                                                  minutes,
                                    onSelected: _busy
                                        ? null
                                        : (_) async {
                                            _haptic();
                                            await _saveAutoRefreshInterval(
                                              subscription,
                                              minutes,
                                            );
                                          },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    _DetailsBlock(
                      title: 'Локация',
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Пометить все сервера как Россию'),
                        subtitle: const Text(
                          'Только для этой подписки: список прокси, lowest/open/free и mixed будут считать все outbound российскими.',
                        ),
                        secondary: const Icon(Icons.flag_rounded),
                        value: subscription.markAllServersRussia,
                        onChanged: _busy
                            ? null
                            : (value) async {
                                _haptic();
                                await _saveMarkAllServersRussia(
                                  subscription,
                                  enabled: value,
                                );
                              },
                      ),
                    ),
                    if (!isLocalFileImport)
                      _DetailsBlock(
                        title: l10n.serverRequestTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.sendHwidTitle),
                              subtitle: Text(l10n.sendHwidSubtitle),
                              value: _sendHwid,
                              onChanged: _busy
                                  ? null
                                  : (value) async {
                                      _haptic();
                                      setState(() {
                                        _sendHwid = value;
                                        if (!value) {
                                          _useCustomHwid = false;
                                        }
                                      });
                                      await _saveRequestSettings(subscription);
                                    },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.useCustomHwidTitle),
                              subtitle: Text(l10n.useCustomHwidSubtitle),
                              value: _sendHwid && _useCustomHwid,
                              onChanged: !_sendHwid || _busy
                                  ? null
                                  : (value) async {
                                      _haptic();
                                      setState(() => _useCustomHwid = value);
                                      await _saveRequestSettings(subscription);
                                    },
                            ),
                            const Gap(6),
                            if (_sendHwid && _useCustomHwid) ...[
                              TextField(
                                controller: _customHwidController,
                                onTapOutside: (_) async {
                                  FocusScope.of(context).unfocus();
                                  await _saveRequestSettings(subscription);
                                },
                                onSubmitted: (_) =>
                                    _saveRequestSettings(subscription),
                                onEditingComplete: () async {
                                  FocusScope.of(context).unfocus();
                                  await _saveRequestSettings(subscription);
                                },
                                inputFormatters: [_kSingleLineFormatter],
                                decoration: InputDecoration(
                                  labelText: l10n.customHwidTitle,
                                  helperText: l10n.customHwidSubtitle,
                                ),
                              ),
                              const Gap(6),
                            ],
                            TextField(
                              controller: _customUserAgentController,
                              onTapOutside: (_) async {
                                FocusScope.of(context).unfocus();
                                await _saveRequestSettings(subscription);
                              },
                              onSubmitted: (_) =>
                                  _saveRequestSettings(subscription),
                              onEditingComplete: () async {
                                FocusScope.of(context).unfocus();
                                await _saveRequestSettings(subscription);
                              },
                              inputFormatters: [_kSingleLineFormatter],
                              decoration: InputDecoration(
                                labelText: l10n.customUserAgentTitle,
                                helperText: l10n.customUserAgentSubtitle,
                                hintText: SubscriptionFetcher.defaultUserAgent,
                              ),
                            ),
                            const Gap(12),
                            TextField(
                              controller: _customHeadersController,
                              minLines: 3,
                              maxLines: 8,
                              onTapOutside: (_) async {
                                FocusScope.of(context).unfocus();
                                await _saveRequestSettings(subscription);
                              },
                              onSubmitted: (_) =>
                                  _saveRequestSettings(subscription),
                              onEditingComplete: () async {
                                FocusScope.of(context).unfocus();
                                await _saveRequestSettings(subscription);
                              },
                              decoration: InputDecoration(
                                labelText: l10n.customRequestHeadersTitle,
                                helperText: l10n.customRequestHeadersSubtitle,
                                hintText:
                                    'Authorization: Bearer ...\nX-Token: ...',
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (usageText != null || untilLabel != null)
                      _DetailsBlock(
                        title: l10n.usageTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (usageText != null)
                              Text(
                                l10n.spentTraffic(usageText),
                                style: theme.textTheme.bodyMedium,
                              ),
                            if (untilLabel != null) ...[
                              if (usageText != null) const Gap(6),
                              Text(
                                untilLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (supportUrl != null || webPageUrl != null)
                      _DetailsBlock(
                        title: l10n.infoTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (supportUrl != null) ...[
                              Text(
                                l10n.supportUrlLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Gap(4),
                              _LinkText(
                                label: supportUrl,
                                onTap: () => _openUrl(supportUrl),
                              ),
                            ],
                            if (webPageUrl != null) ...[
                              if (supportUrl != null) const Gap(12),
                              Text(
                                l10n.websiteLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Gap(4),
                              _LinkText(
                                label: webPageUrl,
                                onTap: () => _openUrl(webPageUrl),
                              ),
                            ],
                          ],
                        ),
                      ),
                    _DetailsBlock(
                      title: l10n.proxiesTitle,
                      trailing: _CountBadge(
                        label: l10n.outboundsCount(userVisibleOutbounds.length),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < visibleOutbounds.length; i++) ...[
                            _OutboundRow(outbound: visibleOutbounds[i]),
                            if (i != visibleOutbounds.length - 1 ||
                                hiddenOutboundsCount > 0)
                              Divider(
                                height: 20,
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: .45),
                              ),
                          ],
                          if (hiddenOutboundsCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                l10n.moreProxies(hiddenOutboundsCount),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailsBlock extends StatelessWidget {
  const _DetailsBlock({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailingWidget = trailing;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .42),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ...switch (trailingWidget) {
                    final widget? => [widget],
                    null => const <Widget>[],
                  },
                ],
              ),
              const Gap(10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionUrlEditDialog extends StatefulWidget {
  const _SubscriptionUrlEditDialog({
    required this.initialValue,
    required this.validate,
  });

  final String initialValue;
  final ({String? url, String? error}) Function(String input) validate;

  @override
  State<_SubscriptionUrlEditDialog> createState() =>
      _SubscriptionUrlEditDialogState();
}

class _SubscriptionUrlEditDialogState
    extends State<_SubscriptionUrlEditDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final result = widget.validate(_controller.text);
    if (result.error case final error?) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.of(context).pop(result.url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.editSubscriptionUrlAction),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: const ValueKey('subscription_url_editor'),
          controller: _controller,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: l10n.subscriptionUrl,
            helperText: l10n.subscriptionUrlEditHint,
            helperMaxLines: 4,
            errorText: _errorText,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.saveAction)),
      ],
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary.withValues(alpha: .75),
          ),
        ),
      ),
    );
  }
}

class _OutboundRow extends StatelessWidget {
  const _OutboundRow({required this.outbound});

  final Outbound outbound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latency = outbound.info.latestPing;
    final primaryMeta = [
      outbound.type.toLowerCase(),
      ...[
        _securityLabel(outbound),
        _transportLabel(outbound),
      ].whereType<String>(),
    ];
    final secondaryMeta = [
      _endpointWithPath(outbound),
      if (_transportLabel(outbound) case final transport?) 'stream/$transport',
    ];
    final sniLabel = _sniLabel(outbound);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: outbound.info.checked
            ? theme.colorScheme.secondaryContainer.withValues(alpha: .22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CountryFlagBadge(countryCode: outbound.info.country ?? '', size: 34),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  outbound.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Gap(4),
                Text(
                  primaryMeta.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Gap(2),
                Text(
                  secondaryMeta.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (sniLabel != null) ...[
                  const Gap(2),
                  Text(
                    'sni = $sniLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(10),
          Text(
            latency == null ? '...' : '$latency ms',
            style: theme.textTheme.labelMedium?.copyWith(
              color: latency == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(10),
          Container(
            width: 4,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: outbound.info.checked
                  ? theme.colorScheme.primary
                  : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

String? _securityLabel(Outbound outbound) {
  final tls = outbound.config['tls'];
  if (tls is! Map) {
    return null;
  }
  final reality = tls['reality'];
  if (reality is Map && reality['enabled'] == true) {
    return 'reality';
  }
  if (tls['enabled'] == true) {
    return 'tls';
  }
  return null;
}

String? _transportLabel(Outbound outbound) {
  final transport = outbound.config['transport'];
  final rawType = transport is Map
      ? (transport['type'] as String?)?.trim().toLowerCase()
      : null;
  if (rawType == null || rawType.isEmpty) {
    return null;
  }
  if (rawType == 'http') {
    return _securityLabel(outbound) == 'tls' ||
            _securityLabel(outbound) == 'reality'
        ? 'https'
        : 'http';
  }
  return rawType;
}

String _endpointWithPath(Outbound outbound) {
  final buffer = StringBuffer();
  if (outbound.server.isNotEmpty) {
    buffer.write(outbound.server);
    if (outbound.port > 0) {
      buffer.write(':${outbound.port}');
    }
  } else {
    buffer.write(outbound.tag);
  }
  final transport = outbound.config['transport'];
  final path = transport is Map ? (transport['path'] as String?)?.trim() : null;
  if (path != null && path.isNotEmpty) {
    buffer.write(path.startsWith('/') ? path : '/$path');
  }
  return buffer.toString();
}

String? _sniLabel(Outbound outbound) {
  final tls = outbound.config['tls'];
  if (tls is! Map) {
    return null;
  }
  final value = (tls['server_name'] as String?)?.trim();
  if (value != null && value.isNotEmpty) {
    return value;
  }
  final fallback = (tls['sni'] as String?)?.trim();
  if (fallback != null && fallback.isNotEmpty) {
    return fallback;
  }
  return null;
}

class _AddResult {
  const _AddResult.url(
    this.url,
    this.name, {
    this.requestInfo,
    this.autoRefreshMinutes = 360,
    this.isCancelled,
  }) : fileContent = null,
       sourceName = null;

  const _AddResult.file({
    required this.name,
    required this.fileContent,
    required this.sourceName,
    this.isCancelled,
  }) : url = '',
       requestInfo = null,
       autoRefreshMinutes = 0;

  final String url;
  final String name;
  final SubscriptionInfo? requestInfo;
  final int autoRefreshMinutes;
  final String? fileContent;
  final String? sourceName;
  final bool Function()? isCancelled;

  _AddResult withCancellation(bool Function() isCancelled) {
    if (fileContent != null) {
      return _AddResult.file(
        name: name,
        fileContent: fileContent!,
        sourceName: sourceName,
        isCancelled: isCancelled,
      );
    }
    return _AddResult.url(
      url,
      name,
      requestInfo: requestInfo,
      autoRefreshMinutes: autoRefreshMinutes,
      isCancelled: isCancelled,
    );
  }
}

// ---------------------------------------------------------------------------
// Add-subscription sheet
// ---------------------------------------------------------------------------

class _AddSubscriptionSheet extends StatefulWidget {
  const _AddSubscriptionSheet({
    required this.onAdd,
    required this.scrollController,
    required this.onClose,
    required this.onModeChanged,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
  });

  final Future<bool> Function(_AddResult result) onAdd;
  final ScrollController scrollController;
  final ValueChanged<bool> onClose;
  final ValueChanged<_AddSubscriptionSheetMode> onModeChanged;
  final ValueChanged<DragUpdateDetails> onHeaderDragUpdate;
  final ValueChanged<DragEndDetails> onHeaderDragEnd;

  @override
  State<_AddSubscriptionSheet> createState() => _AddSubscriptionSheetState();
}

enum _AddSubscriptionSheetMode { quick, manual }

class _AddSubscriptionSheetState extends State<_AddSubscriptionSheet> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _customUserAgentController = TextEditingController();
  final _customHwidController = TextEditingController();
  _AddSubscriptionSheetMode _mode = _AddSubscriptionSheetMode.quick;
  bool _busy = false;
  bool _useCustomUserAgent = false;
  bool _sendHwid = false;
  bool _useCustomHwid = false;
  int _autoRefreshMinutes = 360;
  String? _stage;
  bool _cancelRequested = false;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _customUserAgentController.dispose();
    _customHwidController.dispose();
    super.dispose();
  }

  SubscriptionInfo? _manualRequestInfo() {
    final customUserAgent = _useCustomUserAgent
        ? _customUserAgentController.text.trim()
        : '';
    final customHwid = _sendHwid && _useCustomHwid
        ? _customHwidController.text.trim()
        : '';
    if (customUserAgent.isEmpty && !_sendHwid && customHwid.isEmpty) {
      return null;
    }
    return SubscriptionInfo(
      customUserAgent: customUserAgent.isEmpty ? null : customUserAgent,
      requireHwid: _sendHwid,
      customHwid: customHwid.isEmpty ? null : customHwid,
    );
  }

  void _setError(String message) {
    setState(() {
      _busy = false;
      _stage = null;
    });
    AppNotice.show(context, message, tone: AppNoticeTone.error);
  }

  Future<void> _submitResult(
    _AddResult result, {
    bool keepCurrentStage = false,
  }) async {
    if (_busy && !keepCurrentStage) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (!keepCurrentStage) {
      setState(() {
        _busy = true;
        _stage = l10n.addSubscriptionImporting;
      });
    } else {
      setState(() {
        _stage = l10n.addSubscriptionImporting;
      });
    }
    try {
      final added = await widget.onAdd(
        result.withCancellation(() => _cancelRequested),
      );
      if (!mounted) {
        return;
      }
      if (!added) {
        setState(() {
          _busy = false;
          _stage = null;
        });
        return;
      }
      setState(() => _stage = l10n.addSubscriptionDone);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (mounted) {
        widget.onClose(true);
      }
    } on SubscriptionImportCancelledException {
      if (mounted && !_cancelRequested) {
        setState(() {
          _busy = false;
          _stage = null;
        });
      }
    } on _LocalizedSubscriptionPageError catch (e) {
      if (mounted) {
        _setError(e.message);
      }
    } catch (e) {
      if (mounted) {
        _setError(subscriptionErrorMessage(e, l10n));
      }
    }
  }

  void _submit() {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      _setError(AppLocalizations.of(context).invalidUrl);
      return;
    }
    final name = _nameController.text.trim();
    if (HappCryptoLinkDecoder.isSupportedSubscriptionUrl(input)) {
      unawaited(
        _submitResult(
          _AddResult.url(
            input,
            name,
            requestInfo: _manualRequestInfo(),
            autoRefreshMinutes: _autoRefreshMinutes,
          ),
        ),
      );
      return;
    }
    unawaited(
      _submitResult(
        _AddResult.file(
          name: name,
          fileContent: input,
          sourceName: 'manual import',
        ),
      ),
    );
  }

  Future<void> _pasteUrl() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (!mounted || text.isEmpty) return;
    _urlController.text = text;
    _urlController.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _importFromClipboard() async {
    if (_busy) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _stage = l10n.addSubscriptionReadingClipboard;
    });
    final data = await Clipboard.getData('text/plain');
    if (!mounted) {
      return;
    }
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _setError(l10n.clipboardEmpty);
      return;
    }
    final name = _nameController.text.trim();
    if (HappCryptoLinkDecoder.isSupportedSubscriptionUrl(text)) {
      await _submitResult(
        _AddResult.url(text, name, autoRefreshMinutes: _autoRefreshMinutes),
        keepCurrentStage: true,
      );
      return;
    }
    await _submitResult(
      _AddResult.file(name: name, fileContent: text, sourceName: 'clipboard'),
      keepCurrentStage: true,
    );
  }

  Future<void> _scanQr() async {
    if (_busy) {
      return;
    }
    FocusScope.of(context).unfocus();
    final scannedUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _SubscriptionQrScannerPage()),
    );
    if (!mounted || scannedUrl == null || scannedUrl.isEmpty) return;
    if (!HappCryptoLinkDecoder.isSupportedSubscriptionUrl(scannedUrl)) {
      _setError(AppLocalizations.of(context).invalidQrSubscription);
      return;
    }
    await _submitResult(
      _AddResult.url(
        scannedUrl,
        _nameController.text.trim(),
        autoRefreshMinutes: _autoRefreshMinutes,
      ),
    );
  }

  Future<void> _pickFile() async {
    if (_busy) {
      return;
    }
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.pickFiles(
        withData: false,
        withReadStream: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      _cancelRequested = false;
      setState(() {
        _busy = true;
        _stage = l10n.addSubscriptionReadingFile;
      });
      final file = result.files.single;
      final content = await readSubscriptionFile(file);
      if (!mounted || _cancelRequested) return;
      if (content.contains(EtonifyBackupService.profileMagic) ||
          content.contains(EtonifyBackupService.settingsMagic)) {
        _setError(l10n.backupUseSettingsImport);
        return;
      }
      await _submitResult(
        _AddResult.file(
          name: _nameController.text.trim(),
          fileContent: content,
          sourceName: file.name,
        ),
        keepCurrentStage: true,
      );
    } catch (error) {
      AppLogStore.warning(
        'subscription',
        'Selected subscription file could not be read: '
            '${error.runtimeType}: $error',
      );
      if (mounted && !_cancelRequested) {
        _setError(l10n.invalidSubscriptionFile);
      }
    }
  }

  void _cancelAndClose() {
    _cancelRequested = true;
    widget.onClose(false);
  }

  void _showManual() {
    if (_busy) {
      return;
    }
    setState(() {
      _mode = _AddSubscriptionSheetMode.manual;
    });
    widget.onModeChanged(_mode);
  }

  void _showQuick() {
    if (_busy || _mode == _AddSubscriptionSheetMode.quick) {
      return;
    }
    setState(() {
      _mode = _AddSubscriptionSheetMode.quick;
    });
    widget.onModeChanged(_mode);
  }

  Future<void> _showHelp() {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.subscriptionImportHelpTitle),
        content: Text(l10n.subscriptionImportHelpBody),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatRefreshInterval(AppLocalizations l10n, int minutes) {
    if (minutes <= 0) {
      return l10n.disabledLabel;
    }
    if (minutes % (60 * 24) == 0) {
      return l10n.refreshIntervalDaysShort(minutes ~/ (60 * 24));
    }
    if (minutes % 60 == 0) {
      return l10n.refreshIntervalHoursShort(minutes ~/ 60);
    }
    return l10n.refreshIntervalMinutesShort(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding =
        mediaQuery.padding.bottom + mediaQuery.viewInsets.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final quickButtonHeight = ((constraints.maxWidth - 18 * 2 - 10 * 2) / 3)
            .clamp(124.0, 132.0);
        return PopScope(
          canPop: _mode == _AddSubscriptionSheetMode.quick || _busy,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              _cancelRequested = true;
              return;
            }
            if (!didPop && !_busy) {
              _showQuick();
            }
          },
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: widget.scrollController,
                padding: EdgeInsets.fromLTRB(
                  18,
                  _kAddSubscriptionSheetHeaderHeight + 8,
                  18,
                  18 + bottomPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: _kSubscriptionSheetAnimationDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      layoutBuilder: (currentChild, previousChildren) =>
                          currentChild ?? const SizedBox.shrink(),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: RepaintBoundary(child: child),
                      ),
                      child: _busy
                          ? _AddSubscriptionLoadingCard(
                              key: const ValueKey('loading'),
                              stage: _stage ?? l10n.addSubscriptionImporting,
                            )
                          : _mode == _AddSubscriptionSheetMode.quick
                          ? _AddSubscriptionQuickOptions(
                              key: const ValueKey('quick'),
                              buttonHeight: quickButtonHeight,
                              onScanQr: _scanQr,
                              onClipboard: _importFromClipboard,
                              onPickFile: _pickFile,
                              onManual: _showManual,
                              onHelp: _showHelp,
                            )
                          : _AddSubscriptionManualCard(
                              key: const ValueKey('manual'),
                              urlController: _urlController,
                              nameController: _nameController,
                              customUserAgentController:
                                  _customUserAgentController,
                              customHwidController: _customHwidController,
                              contentLabel: _manualImportLabel(l10n),
                              contentHint: _manualImportHint(l10n),
                              nameLabel: l10n.subscriptionName,
                              customUserAgentLabel: l10n.customUserAgentTitle,
                              customUserAgentSubtitle:
                                  l10n.customUserAgentSubtitle,
                              userAgentHint:
                                  SubscriptionFetcher.defaultUserAgent,
                              sendHwidLabel: l10n.sendHwidTitle,
                              sendHwidSubtitle: l10n.sendHwidSubtitle,
                              customHwidLabel: l10n.customHwidTitle,
                              customHwidSubtitle: l10n.customHwidSubtitle,
                              customHwidSwitchLabel: l10n.useCustomHwidTitle,
                              customHwidSwitchSubtitle:
                                  l10n.useCustomHwidSubtitle,
                              pasteTooltip: l10n.pasteAction,
                              addLabel: l10n.add,
                              autoUpdateLabel: l10n.autoUpdateTitle,
                              autoUpdateValue: l10n.refreshesEvery(
                                _formatRefreshInterval(
                                  l10n,
                                  _autoRefreshMinutes,
                                ),
                              ),
                              autoRefreshMinutes: _autoRefreshMinutes,
                              formatAutoRefreshOption: (minutes) =>
                                  _formatRefreshInterval(l10n, minutes),
                              useCustomUserAgent: _useCustomUserAgent,
                              sendHwid: _sendHwid,
                              useCustomHwid: _useCustomHwid,
                              onPasteUrl: _pasteUrl,
                              onSubmit: _submit,
                              onUseCustomUserAgentChanged: (value) {
                                setState(() => _useCustomUserAgent = value);
                              },
                              onSendHwidChanged: (value) {
                                setState(() {
                                  _sendHwid = value;
                                  if (!value) {
                                    _useCustomHwid = false;
                                  }
                                });
                              },
                              onUseCustomHwidChanged: (value) {
                                setState(() => _useCustomHwid = value);
                              },
                              onAutoRefreshMinutesChanged: (value) {
                                setState(() => _autoRefreshMinutes = value);
                              },
                              onUrlChanged: () {},
                            ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: widget.onHeaderDragUpdate,
                  onVerticalDragEnd: widget.onHeaderDragEnd,
                  child: SizedBox(
                    height: _kAddSubscriptionSheetHeaderHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            cs.surface,
                            cs.surface.withValues(alpha: .97),
                            cs.surface.withValues(alpha: .0),
                          ],
                          stops: const [0, .78, 1],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: .38,
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const Gap(14),
                            Row(
                              children: [
                                if (_mode == _AddSubscriptionSheetMode.manual)
                                  IconButton(
                                    tooltip: MaterialLocalizations.of(
                                      context,
                                    ).backButtonTooltip,
                                    onPressed: _busy ? null : _showQuick,
                                    icon: const Icon(Icons.arrow_back_rounded),
                                  )
                                else
                                  const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _mode == _AddSubscriptionSheetMode.quick
                                            ? l10n.addSubscriptionQuickTitle
                                            : l10n.addSubscriptionManual,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0,
                                            ),
                                      ),
                                      const Gap(4),
                                      Text(
                                        _mode == _AddSubscriptionSheetMode.quick
                                            ? l10n.addSubscriptionQuickSubtitle
                                            : l10n.subscriptionUrlOrContentHint,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: l10n.close,
                                  onPressed: _cancelAndClose,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _manualImportLabel(AppLocalizations l10n) =>
      l10n.subscriptionUrlOrContent;

  String _manualImportHint(AppLocalizations l10n) =>
      l10n.subscriptionUrlOrContentHint;
}

class _AddSubscriptionQuickOptions extends StatelessWidget {
  const _AddSubscriptionQuickOptions({
    super.key,
    required this.buttonHeight,
    required this.onScanQr,
    required this.onClipboard,
    required this.onPickFile,
    required this.onManual,
    required this.onHelp,
  });

  final double buttonHeight;
  final VoidCallback onScanQr;
  final VoidCallback onClipboard;
  final VoidCallback onPickFile;
  final VoidCallback onManual;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _AddSubscriptionQuickCard(
                height: buttonHeight,
                icon: Icons.qr_code_scanner_rounded,
                color: cs.primary,
                title: l10n.scanQrCode,
                onTap: onScanQr,
              ),
            ),
            const Gap(10),
            Expanded(
              child: _AddSubscriptionQuickCard(
                height: buttonHeight,
                icon: Icons.content_paste_rounded,
                color: cs.secondary,
                title: l10n.addSubscriptionFromClipboard,
                onTap: onClipboard,
              ),
            ),
            const Gap(10),
            Expanded(
              child: _AddSubscriptionQuickCard(
                height: buttonHeight,
                icon: Icons.add_rounded,
                color: cs.primary,
                title: l10n.addSubscriptionManual,
                onTap: onManual,
              ),
            ),
          ],
        ),
        const Gap(16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickFile,
                icon: const Icon(Icons.file_open_rounded),
                label: Text(
                  l10n.importFromFile,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const Gap(8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onHelp,
                icon: const Icon(Icons.help_outline_rounded),
                label: Text(
                  l10n.subscriptionImportHelpTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddSubscriptionQuickCard extends StatelessWidget {
  const _AddSubscriptionQuickCard({
    required this.height,
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  final double height;
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsLeadingIcon(
                  icon: icon,
                  color: color,
                  size: 48,
                  iconSize: 24,
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddSubscriptionLoadingCard extends StatelessWidget {
  const _AddSubscriptionLoadingCard({super.key, required this.stage});

  final String stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: cs.primary,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Text(
                    stage,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Gap(16),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _AddSubscriptionManualCard extends StatelessWidget {
  const _AddSubscriptionManualCard({
    super.key,
    required this.urlController,
    required this.nameController,
    required this.customUserAgentController,
    required this.customHwidController,
    required this.contentLabel,
    required this.contentHint,
    required this.nameLabel,
    required this.customUserAgentLabel,
    required this.customUserAgentSubtitle,
    required this.userAgentHint,
    required this.sendHwidLabel,
    required this.sendHwidSubtitle,
    required this.customHwidLabel,
    required this.customHwidSubtitle,
    required this.customHwidSwitchLabel,
    required this.customHwidSwitchSubtitle,
    required this.pasteTooltip,
    required this.addLabel,
    required this.autoUpdateLabel,
    required this.autoUpdateValue,
    required this.autoRefreshMinutes,
    required this.formatAutoRefreshOption,
    required this.useCustomUserAgent,
    required this.sendHwid,
    required this.useCustomHwid,
    required this.onPasteUrl,
    required this.onSubmit,
    required this.onUseCustomUserAgentChanged,
    required this.onSendHwidChanged,
    required this.onUseCustomHwidChanged,
    required this.onAutoRefreshMinutesChanged,
    required this.onUrlChanged,
  });

  final TextEditingController urlController;
  final TextEditingController nameController;
  final TextEditingController customUserAgentController;
  final TextEditingController customHwidController;
  final String contentLabel;
  final String contentHint;
  final String nameLabel;
  final String customUserAgentLabel;
  final String customUserAgentSubtitle;
  final String userAgentHint;
  final String sendHwidLabel;
  final String sendHwidSubtitle;
  final String customHwidLabel;
  final String customHwidSubtitle;
  final String customHwidSwitchLabel;
  final String customHwidSwitchSubtitle;
  final String pasteTooltip;
  final String addLabel;
  final String autoUpdateLabel;
  final String autoUpdateValue;
  final int autoRefreshMinutes;
  final String Function(int minutes) formatAutoRefreshOption;
  final bool useCustomUserAgent;
  final bool sendHwid;
  final bool useCustomHwid;
  final VoidCallback onPasteUrl;
  final VoidCallback onSubmit;
  final ValueChanged<bool> onUseCustomUserAgentChanged;
  final ValueChanged<bool> onSendHwidChanged;
  final ValueChanged<bool> onUseCustomHwidChanged;
  final ValueChanged<int> onAutoRefreshMinutesChanged;
  final VoidCallback onUrlChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: .36)),
    );
    final focusedFieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.primary, width: 1.4),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: urlController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                isDense: true,
                alignLabelWithHint: true,
                labelText: contentLabel,
                hintText: contentHint,
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  tooltip: pasteTooltip,
                  onPressed: onPasteUrl,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
                filled: true,
                fillColor: cs.surfaceContainerLowest,
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: focusedFieldBorder,
              ),
              onChanged: (_) => onUrlChanged(),
              onSubmitted: (_) => onSubmit(),
            ),
            const Gap(10),
            TextField(
              controller: nameController,
              textInputAction: TextInputAction.done,
              inputFormatters: [_kSingleLineFormatter],
              decoration: InputDecoration(
                isDense: true,
                labelText: nameLabel,
                prefixIcon: const Icon(Icons.label_outline_rounded),
                filled: true,
                fillColor: cs.surfaceContainerLowest,
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: focusedFieldBorder,
              ),
              onSubmitted: (_) => onSubmit(),
            ),
            const Gap(12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .36),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          autoUpdateLabel,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        autoUpdateValue,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in _kAutoRefreshOptions)
                        ChoiceChip(
                          label: Text(formatAutoRefreshOption(minutes)),
                          selected: autoRefreshMinutes == minutes,
                          onSelected: (_) =>
                              onAutoRefreshMinutesChanged(minutes),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded),
              title: Text(
                customUserAgentLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('$customUserAgentSubtitle · HWID'),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(customUserAgentLabel),
                  subtitle: Text(customUserAgentSubtitle),
                  value: useCustomUserAgent,
                  onChanged: onUseCustomUserAgentChanged,
                ),
                if (useCustomUserAgent) ...[
                  TextField(
                    controller: customUserAgentController,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [_kSingleLineFormatter],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: customUserAgentLabel,
                      hintText: userAgentHint,
                      prefixIcon: const Icon(Icons.badge_outlined),
                      filled: true,
                      fillColor: cs.surfaceContainerLowest,
                      border: fieldBorder,
                      enabledBorder: fieldBorder,
                      focusedBorder: focusedFieldBorder,
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                  const Gap(8),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(sendHwidLabel),
                  subtitle: Text(sendHwidSubtitle),
                  value: sendHwid,
                  onChanged: onSendHwidChanged,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(customHwidSwitchLabel),
                  subtitle: Text(customHwidSwitchSubtitle),
                  value: sendHwid && useCustomHwid,
                  onChanged: sendHwid ? onUseCustomHwidChanged : null,
                ),
                if (sendHwid && useCustomHwid) ...[
                  TextField(
                    controller: customHwidController,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [_kSingleLineFormatter],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: customHwidLabel,
                      helperText: customHwidSubtitle,
                      prefixIcon: const Icon(Icons.fingerprint_rounded),
                      filled: true,
                      fillColor: cs.surfaceContainerLowest,
                      border: fieldBorder,
                      enabledBorder: fieldBorder,
                      focusedBorder: focusedFieldBorder,
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                  const Gap(8),
                ],
              ],
            ),
            const Gap(14),
            FilledButton.icon(
              onPressed: onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(addLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionQrPage extends StatelessWidget {
  const _SubscriptionQrPage({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.subscriptionQrTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            appBottomSafePadding(context, 24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: QrImageView(
                  data: value,
                  version: QrVersions.auto,
                  size: 280,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const Gap(20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(8),
              Text(
                l10n.subscriptionQrHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Gap(16),
              SelectableText(
                value,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionQrScannerPage extends StatefulWidget {
  const _SubscriptionQrScannerPage();

  @override
  State<_SubscriptionQrScannerPage> createState() =>
      _SubscriptionQrScannerPageState();
}

class _SubscriptionQrScannerPageState
    extends State<_SubscriptionQrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim() ?? '';
      if (rawValue.isEmpty) {
        continue;
      }
      if (!HappCryptoLinkDecoder.isSupportedSubscriptionUrl(rawValue)) {
        continue;
      }
      _handled = true;
      Navigator.of(context).pop(rawValue);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanQrCode)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _handleBarcode),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                appBottomSafePadding(context, 36),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh.withValues(
                    alpha: .92,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Text(
                    l10n.subscriptionQrHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparedSubscriptionImport {
  const _PreparedSubscriptionImport({
    this.url,
    this.requestInfo,
    this.fileContent,
    this.sourceName,
  });

  final String? url;
  final SubscriptionInfo? requestInfo;
  final String? fileContent;
  final String? sourceName;
}
