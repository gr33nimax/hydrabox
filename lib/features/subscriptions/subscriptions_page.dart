import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/core/demo_utils.dart';
import 'package:meow_client/data/subscription/happ_crypto_link.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:meow_client/widgets/country_flag_badge.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

const _kSubscriptionProxyPreviewLimit = 50;
const _kSubscriptionOperationSoftWarningDelay = Duration(seconds: 15);
const _kSubscriptionOperationTimeout = Duration(seconds: 30);
final _kSingleLineFormatter = FilteringTextInputFormatter.deny(
  RegExp(r'[\r\n]'),
);

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
  List<Subscription> _subscriptions = [];
  final Set<String> _selectedIds = <String>{};
  bool _loading = false;
  String? _error;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _haptic() {
    if (widget.hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.openAddOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _addSubscription();
        }
      });
    }
  }

  void _reload() {
    setState(() {
      _subscriptions = SubscriptionStore.getAllMetadata();
      _selectedIds.removeWhere(
        (id) => !_subscriptions.any((subscription) => subscription.id == id),
      );
    });
  }

  Future<T> _runSubscriptionOperationWithWarning<T>(Future<T> operation) async {
    var completed = false;
    final timer = Timer(_kSubscriptionOperationSoftWarningDelay, () {
      if (!completed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).subscriptionOperationSlowWarning,
            ),
          ),
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
    if (error is TimeoutException) {
      return AppLocalizations.of(context).subscriptionOperationTimeout;
    }
    return error.toString();
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

  Future<void> _addSubscription() async {
    final l10n = AppLocalizations.of(context);
    final result = await Navigator.of(context).push<_AddResult>(
      MaterialPageRoute(builder: (_) => const _AddSubscriptionPage()),
    );
    if (result == null || !mounted) return;

    try {
      final prepared = await _prepareSubscriptionImport(result);
      if (prepared == null || !mounted) {
        return;
      }

      setState(() {
        _loading = true;
        _error = null;
      });

      final createdResult = await _runSubscriptionOperationWithWarning(
        prepared.fileContent != null
            ? SubscriptionStore.addFromContent(
                prepared.fileContent!,
                customName: result.name.isNotEmpty ? result.name : null,
                sourceName: prepared.sourceName,
                operationTimeout: _kSubscriptionOperationTimeout,
              )
            : SubscriptionStore.addFromUrl(
                prepared.url!,
                customName: result.name.isNotEmpty ? result.name : null,
                requestInfo: prepared.requestInfo,
                operationTimeout: _kSubscriptionOperationTimeout,
              ),
      );
      final created = createdResult.subscription;
      if (mounted) {
        if (createdResult.hasWarning) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.subscriptionSavedWithFetchWarning)),
          );
        }
        if (prepared.fileContent == null) {
          await _offerLikelyHwidFix(created);
        }
      }
      await _maybeHandleMovedSubscription(created);
      _reload();
    } catch (e) {
      setState(() => _error = _userFacingSubscriptionError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
      return _PreparedSubscriptionImport(url: rawUrl);
    }

    final confirmed = await _showHappImportDialog();
    if (confirmed != true) {
      return null;
    }

    final prepared = await HappCryptoLinkDecoder.prepare(rawUrl);
    return _PreparedSubscriptionImport(
      url: prepared.resolvedUrl,
      requestInfo: prepared.requestInfo,
    );
  }

  Future<bool?> _showHappImportDialog() {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.happImportTitle),
        content: Text(l10n.happImportMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              AppLocalizations.of(dialogContext).deepLinkImportHappCancelAction,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
    final subscription = SubscriptionStore.get(id);
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
      _loading = true;
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
        setState(() => _loading = false);
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
    final current = SubscriptionStore.get(id);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).subscriptionHwidEnabledAndUpdated,
          ),
        ),
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
    _haptic();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait(
        _subscriptions
            .where((sub) => !SubscriptionStore.isLocalFileImportUrl(sub.url))
            .map((sub) async {
              try {
                await _runSubscriptionOperationWithWarning(
                  SubscriptionStore.refresh(
                    sub.id,
                    operationTimeout: _kSubscriptionOperationTimeout,
                  ),
                );
              } catch (_) {}
            }),
      );
      _reload();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ProgressiveBlurScaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '${_selectedIds.length}' : l10n.subscriptionsTitle,
        ),
        flexibleSpace: _loading
            ? Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            IconButton(
              onPressed: _loading ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: l10n.delete,
            ),
            IconButton(
              onPressed: _clearSelection,
              icon: const Icon(Icons.close_rounded),
              tooltip: l10n.close,
            ),
          ] else ...[
            if (_subscriptions.isNotEmpty)
              IconButton(
                onPressed: _loading ? null : _refreshAll,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: l10n.refreshAll,
              ),
            IconButton(
              onPressed: _loading ? null : _addSubscription,
              icon: const Icon(Icons.add_rounded),
              tooltip: l10n.addSubscription,
            ),
          ],
          const Gap(8),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.errorContainer,
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          Expanded(
            child: _subscriptions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_download_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        const Gap(16),
                        Text(
                          l10n.noSubscriptions,
                          style: theme.textTheme.titleMedium,
                        ),
                        const Gap(4),
                        Text(
                          l10n.noSubscriptionsHint,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Gap(24),
                        FilledButton.icon(
                          onPressed: _addSubscription,
                          icon: const Icon(Icons.add_rounded),
                          label: Text(l10n.addSubscription),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(
                      top: progressiveHeaderTopPadding(context, 6),
                      bottom: appBottomSafePadding(context, 24),
                    ),
                    itemCount: _subscriptions.length,
                    itemBuilder: (context, index) {
                      final sub = _subscriptions[index];
                      return _SubscriptionCard(
                        subscription: sub,
                        active: sub.id == widget.activeSubscriptionId,
                        multiSelected: _selectedIds.contains(sub.id),
                        selectionMode: _selectionMode,
                        loading: _loading,
                        onSelect: () {
                          if (_selectionMode) {
                            _toggleSelection(sub.id);
                          } else {
                            Navigator.of(context).pop(sub.id);
                          }
                        },
                        onLongPress: () => _toggleSelection(sub.id),
                        onRefresh: () => _refreshSubscription(sub.id),
                        onDelete: () => _deleteSubscription(sub.id),
                        onOpenDetails: () async {
                          if (_selectionMode) {
                            _toggleSelection(sub.id);
                            return;
                          }
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _SubscriptionDetailsPage(
                                subscriptionId: sub.id,
                                onRefresh: () => _refreshSubscription(sub.id),
                                onDelete: () => _deleteSubscription(sub.id),
                                onMoveUp: index > 0
                                    ? () => _moveSubscriptionUp(sub.id)
                                    : null,
                                hapticEnabled: widget.hapticEnabled,
                              ),
                            ),
                          );
                          if (mounted) {
                            _reload();
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.subscription,
    required this.active,
    required this.multiSelected,
    required this.selectionMode,
    required this.loading,
    required this.onSelect,
    required this.onLongPress,
    required this.onRefresh,
    required this.onDelete,
    required this.onOpenDetails,
  });

  final Subscription subscription;
  final bool active;
  final bool multiSelected;
  final bool selectionMode;
  final bool loading;
  final VoidCallback onSelect;
  final VoidCallback onLongPress;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
    final hasFooter = usageText != null || remainingText != null;
    final refreshable = !SubscriptionStore.isLocalFileImportUrl(
      subscription.url,
    );
    final sourceLabel = refreshable
        ? Uri.tryParse(subscription.url)?.host ?? subscription.url
        : l10n.refreshActiveSubscriptionUnavailable;
    final lastUpdatedText = subscription.lastUpdated > 0
        ? l10n.lastUpdated(
            formatTime(
              DateTime.fromMillisecondsSinceEpoch(subscription.lastUpdated),
            ),
          )
        : l10n.notAvailableShort;
    final proxyCount = subscription.outbounds
        .where((outbound) => !outbound.info.deleted)
        .length;
    final highlighted = active || multiSelected;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.secondaryContainer.withValues(alpha: .32)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlighted
              ? theme.colorScheme.primary.withValues(alpha: .55)
              : theme.colorScheme.outlineVariant.withValues(alpha: .42),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Stack(
          children: [
            Positioned(
              left: 48,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: 1,
                child: ColoredBox(
                  color: highlighted
                      ? theme.colorScheme.primary.withValues(alpha: .34)
                      : theme.colorScheme.outline.withValues(alpha: .24),
                ),
              ),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 48,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onOpenDetails,
                        onLongPress: onLongPress,
                        child: Center(
                          child: Icon(
                            selectionMode
                                ? (multiSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded)
                                : Icons.more_vert_rounded,
                            size: 20,
                            color: multiSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onSelect,
                        onLongPress: onLongPress,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                constraints: const BoxConstraints(
                                  minHeight: 32,
                                ),
                                decoration: BoxDecoration(
                                  color: active || multiSelected
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: hasFooter
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      subscription.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _SubscriptionBadge(
                                          icon: active
                                              ? Icons.check_circle_rounded
                                              : Icons.circle_outlined,
                                          label: active
                                              ? l10n.currentProfileLabel
                                              : sourceLabel,
                                        ),
                                        _SubscriptionBadge(
                                          icon: Icons.hub_outlined,
                                          label: l10n.subscriptionServersCount(
                                            proxyCount,
                                          ),
                                        ),
                                        _SubscriptionBadge(
                                          icon: Icons.route_rounded,
                                          label:
                                              l10n.subscriptionProxyTypeLabel,
                                        ),
                                        _SubscriptionBadge(
                                          icon: Icons.update_rounded,
                                          label: lastUpdatedText,
                                        ),
                                        if (!refreshable)
                                          _SubscriptionBadge(
                                            icon: Icons.lock_outline_rounded,
                                            label: l10n
                                                .subscriptionLocalImportBadge,
                                          ),
                                        if (remainingDays != null &&
                                            remainingDays <= 3)
                                          _SubscriptionBadge(
                                            icon: Icons.warning_amber_rounded,
                                            label: remainingText ?? '',
                                            warning: true,
                                          ),
                                      ],
                                    ),
                                    if (hasTraffic) ...[
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: LinearProgressIndicator(
                                          value: info?.ratio ?? 0,
                                          minHeight: 5,
                                          backgroundColor: theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                        ),
                                      ),
                                    ],
                                    if (hasFooter) ...[
                                      SizedBox(height: hasTraffic ? 6 : 1),
                                      Row(
                                        children: [
                                          if (usageText != null)
                                            Expanded(
                                              child: Text(
                                                usageText,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.labelSmall,
                                              ),
                                            ),
                                          if (remainingText != null) ...[
                                            if (usageText != null)
                                              const SizedBox(width: 12),
                                            Text(
                                              remainingText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color:
                                                        remainingDays != null &&
                                                            remainingDays <= 3
                                                        ? theme
                                                              .colorScheme
                                                              .error
                                                        : theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!selectionMode) ...[
                                const SizedBox(width: 4),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: refreshable
                                          ? l10n.refresh
                                          : l10n.refreshActiveSubscriptionUnavailable,
                                      onPressed: loading || !refreshable
                                          ? null
                                          : onRefresh,
                                      icon: const Icon(Icons.refresh_rounded),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: l10n.subscriptionDetailsTitle,
                                      onPressed: onOpenDetails,
                                      icon: const Icon(
                                        Icons.info_outline_rounded,
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: l10n.delete,
                                      onPressed: loading ? null : onDelete,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionBadge extends StatelessWidget {
  const _SubscriptionBadge({
    required this.icon,
    required this.label,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warning ? theme.colorScheme.error : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).subscriptionQrUnsupported),
        ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
                                await Clipboard.setData(
                                  ClipboardData(text: subscription.url),
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
                          Text(
                            isLocalFileImport
                                ? l10n.importedFromFileLabel(
                                    localFileImportName ?? subscription.name,
                                  )
                                : subscription.url,
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
                                    await Clipboard.setData(
                                      ClipboardData(text: happCryptoLink),
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
                                hintText: 'Etonify/0.1.1',
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .42),
        ),
      ),
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
  const _AddResult.url(this.url, this.name)
    : fileContent = null,
      sourceName = null;

  const _AddResult.file({
    required this.name,
    required this.fileContent,
    required this.sourceName,
  }) : url = '';

  final String url;
  final String name;
  final String? fileContent;
  final String? sourceName;
}

// ---------------------------------------------------------------------------
// Add-subscription page
// ---------------------------------------------------------------------------

class _AddSubscriptionPage extends StatefulWidget {
  const _AddSubscriptionPage();

  @override
  State<_AddSubscriptionPage> createState() => _AddSubscriptionPageState();
}

class _AddSubscriptionPageState extends State<_AddSubscriptionPage> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _urlError;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ---- form actions ----

  void _submit() {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      setState(() => _urlError = AppLocalizations.of(context).invalidUrl);
      return;
    }
    final name = _nameController.text.trim();
    if (HappCryptoLinkDecoder.isSupportedSubscriptionUrl(input)) {
      Navigator.pop(context, _AddResult.url(input, name));
      return;
    }
    Navigator.pop(
      context,
      _AddResult.file(
        name: name,
        fileContent: input,
        sourceName: 'manual import',
      ),
    );
  }

  Future<void> _pasteUrl() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (!mounted || text.isEmpty) return;
    _urlController.text = text;
    _urlController.selection = TextSelection.collapsed(offset: text.length);
    if (_urlError != null) setState(() => _urlError = null);
  }

  Future<void> _scanQr() async {
    FocusScope.of(context).unfocus();
    final scannedUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _SubscriptionQrScannerPage()),
    );
    if (!mounted || scannedUrl == null || scannedUrl.isEmpty) return;
    if (!HappCryptoLinkDecoder.isSupportedSubscriptionUrl(scannedUrl)) {
      setState(
        () => _urlError = AppLocalizations.of(context).invalidQrSubscription,
      );
      return;
    }
    Navigator.pop(
      context,
      _AddResult.url(scannedUrl, _nameController.text.trim()),
    );
  }

  Future<void> _pickFile() async {
    FocusScope.of(context).unfocus();
    final result = await FilePicker.pickFiles(withData: true);
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes =
        file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(
        () => _urlError = AppLocalizations.of(context).invalidSubscriptionFile,
      );
      return;
    }
    final content = utf8.decode(bytes, allowMalformed: true).trim();
    if (content.isEmpty) {
      setState(
        () => _urlError = AppLocalizations.of(context).invalidSubscriptionFile,
      );
      return;
    }
    Navigator.pop(
      context,
      _AddResult.file(
        name: _nameController.text.trim(),
        fileContent: content,
        sourceName: file.name,
      ),
    );
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ProgressiveBlurScaffold(
      appBar: AppBar(
        title: Text(l10n.addSubscription),
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Theme(
        data: settingsTileTheme(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                settingsScreenPadding.left,
                progressiveHeaderTopPadding(context, settingsScreenPadding.top),
                settingsScreenPadding.right,
                appBottomSafePadding(context, settingsScreenPadding.bottom),
              ),
              children: [
                _AddSubscriptionImportMethods(
                  scanLabel: l10n.scanQrCode,
                  fileLabel: l10n.importFromFile,
                  onScanQr: _scanQr,
                  onPickFile: _pickFile,
                ),
                if (_urlError case final error?) ...[
                  const Gap(settingsIslandGap),
                  _AddSubscriptionErrorTile(message: error),
                ],
                const Gap(settingsSectionGap),
                _AddSubscriptionSectionLabel(label: l10n.orManually),
                const Gap(settingsSectionLabelGap),
                _AddSubscriptionManualCard(
                  urlController: _urlController,
                  nameController: _nameController,
                  contentLabel: _manualImportLabel(l10n),
                  contentHint: _manualImportHint(l10n),
                  nameLabel: l10n.subscriptionName,
                  pasteTooltip: l10n.pasteAction,
                  addLabel: l10n.add,
                  onPasteUrl: _pasteUrl,
                  onSubmit: _submit,
                  onUrlChanged: () {
                    if (_urlError != null) {
                      setState(() => _urlError = null);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _manualImportLabel(AppLocalizations l10n) =>
      l10n.subscriptionUrlOrContent;

  String _manualImportHint(AppLocalizations l10n) =>
      l10n.subscriptionUrlOrContentHint;
}

class _AddSubscriptionImportMethods extends StatelessWidget {
  const _AddSubscriptionImportMethods({
    required this.scanLabel,
    required this.fileLabel,
    required this.onScanQr,
    required this.onPickFile,
  });

  final String scanLabel;
  final String fileLabel;
  final VoidCallback onScanQr;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _AddSubscriptionMethodTile(
            icon: Icons.qr_code_scanner_rounded,
            color: cs.primary,
            title: scanLabel,
            onTap: onScanQr,
          ),
          Divider(
            height: 1,
            indent: 72,
            color: cs.outlineVariant.withValues(alpha: .36),
          ),
          _AddSubscriptionMethodTile(
            icon: Icons.file_open_rounded,
            color: cs.tertiary,
            title: fileLabel,
            onTap: onPickFile,
          ),
        ],
      ),
    );
  }
}

class _AddSubscriptionMethodTile extends StatelessWidget {
  const _AddSubscriptionMethodTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SettingsLeadingIcon(icon: icon, color: color),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _AddSubscriptionSectionLabel extends StatelessWidget {
  const _AddSubscriptionSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _AddSubscriptionManualCard extends StatelessWidget {
  const _AddSubscriptionManualCard({
    required this.urlController,
    required this.nameController,
    required this.contentLabel,
    required this.contentHint,
    required this.nameLabel,
    required this.pasteTooltip,
    required this.addLabel,
    required this.onPasteUrl,
    required this.onSubmit,
    required this.onUrlChanged,
  });

  final TextEditingController urlController;
  final TextEditingController nameController;
  final String contentLabel;
  final String contentHint;
  final String nameLabel;
  final String pasteTooltip;
  final String addLabel;
  final VoidCallback onPasteUrl;
  final VoidCallback onSubmit;
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

class _AddSubscriptionErrorTile extends StatelessWidget {
  const _AddSubscriptionErrorTile({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: cs.errorContainer,
      child: ListTile(
        leading: Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
        title: Text(
          message,
          style: TextStyle(
            color: cs.onErrorContainer,
            fontWeight: FontWeight.w700,
          ),
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
