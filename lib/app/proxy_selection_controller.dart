import 'dart:async';

import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/models/subscription.dart';

class ProxySelectionTimeout {
  const ProxySelectionTimeout({
    required this.generation,
    required this.tag,
    required this.previousTag,
  });

  final int generation;
  final String tag;
  final String? previousTag;
}

class ProxySelectionController {
  static const defaultConfirmationTimeout = Duration(seconds: 8);

  int _generation = 0;
  String? _pendingRuntimeSelectTag;
  String? _pendingRuntimeSelectPreviousTag;
  Timer? _pendingRuntimeSelectTimer;

  int get generation => _generation;
  String? get pendingRuntimeSelectTag => _pendingRuntimeSelectTag;
  String? get pendingRuntimeSelectPreviousTag =>
      _pendingRuntimeSelectPreviousTag;
  bool get hasPendingRuntimeSelection => _pendingRuntimeSelectTag != null;

  void dispose() {
    _pendingRuntimeSelectTimer?.cancel();
  }

  int beginLocalSelection() {
    _generation++;
    _clearPendingRuntimeSelection();
    return _generation;
  }

  int beginRuntimeSelection({
    required String tag,
    required String previousTag,
    required void Function(ProxySelectionTimeout timeout) onTimeout,
    Duration confirmationTimeout = defaultConfirmationTimeout,
  }) {
    final generation = ++_generation;
    _pendingRuntimeSelectTag = tag;
    _pendingRuntimeSelectPreviousTag = previousTag;
    _pendingRuntimeSelectTimer?.cancel();
    _pendingRuntimeSelectTimer = Timer(confirmationTimeout, () {
      if (_generation != generation || _pendingRuntimeSelectTag != tag) {
        return;
      }
      onTimeout(
        ProxySelectionTimeout(
          generation: generation,
          tag: tag,
          previousTag: _pendingRuntimeSelectPreviousTag,
        ),
      );
    });
    return generation;
  }

  bool clearRuntimeSelection({int? generation}) {
    if (generation != null && generation != _generation) {
      return false;
    }
    final hadPending = hasPendingRuntimeSelection;
    _clearPendingRuntimeSelection();
    return hadPending;
  }

  bool isCurrentGeneration(int generation) => generation == _generation;

  Subscription withSelectedOutbound(Subscription subscription, String tag) {
    return subscription.copyWith(selectedProxyTag: tag);
  }

  List<Subscription> replaceSubscription(
    List<Subscription> subscriptions,
    Subscription updated,
  ) {
    return subscriptions
        .map(
          (subscription) =>
              subscription.id == updated.id ? updated : subscription,
        )
        .toList(growable: false);
  }

  String validSelectedProxyTagForSubscription(
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
    final proxyChainTags = subscription.proxyChains
        .map((chain) => chain.tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    if (proxyChainTags.contains(normalized)) {
      return normalized;
    }
    final liveOutboundTags = liveOutbounds
        .where((outbound) => outbound.config['_group_only'] != true)
        .map((outbound) => outbound.tag)
        .toSet();
    for (final group in subscription.groups) {
      if (group.tag == normalized &&
          group.outboundTags.any(liveOutboundTags.contains)) {
        return normalized;
      }
    }
    for (final outbound in liveOutbounds) {
      if (outbound.tag == normalized) {
        return normalized;
      }
    }
    return liveOutbounds.length == 1 ? liveOutbounds.first.tag : lowestProxyTag;
  }

  static String effectiveSelectedProxyTag({
    required String metadataSelectedProxyTag,
    required String preferredSelectedProxyTag,
    required bool preferPreferred,
  }) {
    final preferred = preferredSelectedProxyTag.trim();
    final metadata = metadataSelectedProxyTag.trim();
    if (preferPreferred && preferred.isNotEmpty) {
      return preferred;
    }
    if (metadata.isNotEmpty) {
      return metadata;
    }
    return preferred;
  }

  bool runtimeSelectionUpdatesAllowed({
    required bool connected,
    required bool connectionStable,
    required bool transitionInProgress,
  }) {
    return connected && connectionStable && !transitionInProgress;
  }

  void _clearPendingRuntimeSelection() {
    _pendingRuntimeSelectTimer?.cancel();
    _pendingRuntimeSelectTimer = null;
    _pendingRuntimeSelectTag = null;
    _pendingRuntimeSelectPreviousTag = null;
  }
}
