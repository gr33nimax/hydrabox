import 'dart:async';

import 'package:hydrabox/core/lowest_proxy_groups.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:hydrabox/singbox/hydra_proxy_chain_resolver.dart';

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
  static const defaultConfirmationTimeout = Duration(seconds: 12);

  int _generation = 0;
  Future<void> _persistenceQueue = Future<void>.value();
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
    _setPendingRuntimeSelection(
      generation: generation,
      tag: tag,
      previousTag: previousTag,
      onTimeout: onTimeout,
      confirmationTimeout: confirmationTimeout,
    );
    return generation;
  }

  int guardCurrentSelectionForRuntime({
    required String tag,
    required String previousTag,
    required void Function(ProxySelectionTimeout timeout) onTimeout,
    Duration confirmationTimeout = defaultConfirmationTimeout,
  }) {
    final generation = _generation;
    _setPendingRuntimeSelection(
      generation: generation,
      tag: tag,
      previousTag: previousTag,
      onTimeout: onTimeout,
      confirmationTimeout: confirmationTimeout,
    );
    return generation;
  }

  Future<void> enqueuePersistence({
    required int generation,
    required Future<void> Function() action,
  }) {
    final operation = _persistenceQueue.then((_) async {
      if (!isCurrentGeneration(generation)) {
        return;
      }
      await action();
    });
    _persistenceQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> waitForPersistence() async {
    while (true) {
      final pending = _persistenceQueue;
      await pending;
      if (identical(pending, _persistenceQueue)) {
        return;
      }
    }
  }

  void _setPendingRuntimeSelection({
    required int generation,
    required String tag,
    required String previousTag,
    required void Function(ProxySelectionTimeout timeout) onTimeout,
    required Duration confirmationTimeout,
  }) {
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
    return withSelectedProxyOutbound(subscription, tag);
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
    final normalized = normalizeProxySelectionTag(preferredTag);
    final liveOutbounds = subscription.selectableOutbounds
        .where(
          (outbound) =>
              !outbound.info.deleted && outbound.config['_group_only'] != true,
        )
        .toList(growable: false);
    if (liveOutbounds.isEmpty) {
      return '';
    }
    if (normalized.isEmpty) {
      return liveOutbounds.length == 1
          ? liveOutbounds.first.tag
          : lowestProxyTag;
    }
    if (subscription.profileForRuntimeTag(normalized) != null) {
      return normalized;
    }
    if (isLowestProxyTag(normalized)) {
      return liveOutbounds.length == 1 ? liveOutbounds.first.tag : normalized;
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
    if (subscription.resourceConfigs.isNotEmpty) {
      final selectedProfile = subscription.profileForId(
        subscription.selectedProfileId,
      );
      if (selectedProfile != null) {
        return selectedProfile.runtimeTag;
      }
    }
    return liveOutbounds.length == 1 ? liveOutbounds.first.tag : lowestProxyTag;
  }

  static String effectiveSelectedProxyTag({
    required String metadataSelectedProxyTag,
    required String preferredSelectedProxyTag,
    required bool preferPreferred,
  }) {
    final preferred = normalizeProxySelectionTag(preferredSelectedProxyTag);
    final metadata = normalizeProxySelectionTag(metadataSelectedProxyTag);
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

Subscription withSelectedProxyOutbound(Subscription subscription, String tag) {
  final normalized = normalizeProxySelectionTag(tag);
  final owner = HydraProxyChainResolver.ownerProfileForSelection(
    subscription,
    normalized,
  );
  return subscription.copyWith(
    selectedProxyTag: normalized,
    selectedProfileId: owner?.id,
  );
}
