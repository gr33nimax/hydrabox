import 'dart:math';

import 'package:hydrabox/data/subscription/subscription_fetcher.dart';
import 'package:hydrabox/data/subscription/subscription_storage_id.dart';
import 'package:hydrabox/models/subscription.dart';

typedef SubscriptionProfileLoader = Future<List<Subscription>> Function();
typedef SubscriptionProfileSaver =
    Future<void> Function(Subscription subscription);
typedef SubscriptionProfileBatchSaver =
    Future<void> Function(List<Subscription> subscriptions);
typedef SubscriptionProfileImportApplied = Future<void> Function();
typedef SubscriptionProfileIdGenerator = String Function();

class SubscriptionProfileImportResult {
  const SubscriptionProfileImportResult({
    required this.subscriptions,
    required this.addedCount,
    required this.updatedCount,
  });

  const SubscriptionProfileImportResult.empty()
    : subscriptions = const <Subscription>[],
      addedCount = 0,
      updatedCount = 0;

  final List<Subscription> subscriptions;
  final int addedCount;
  final int updatedCount;
}

/// Merges a decoded profile backup into the subscription store.
///
/// The backup codec only reconstructs profile data. This controller owns the
/// application policy: matching existing profiles, preserving their identity
/// and position, appending new profiles, persisting them, and refreshing the
/// client after all writes complete.
class SubscriptionProfileImportController {
  const SubscriptionProfileImportController({
    required this.loadExisting,
    required this.save,
    required this.onApplied,
    this.saveBatch,
    this.generateId = SubscriptionFetcher.generateId,
  });

  final SubscriptionProfileLoader loadExisting;
  final SubscriptionProfileSaver save;
  final SubscriptionProfileBatchSaver? saveBatch;
  final SubscriptionProfileImportApplied onApplied;
  final SubscriptionProfileIdGenerator generateId;

  Future<SubscriptionProfileImportResult> apply(
    List<Subscription> importedSubscriptions,
  ) async {
    if (importedSubscriptions.isEmpty) {
      return const SubscriptionProfileImportResult.empty();
    }
    final existing = await loadExisting();
    final result = merge(
      existing: existing,
      imported: importedSubscriptions,
      generateId: generateId,
    );
    final batchSaver = saveBatch;
    if (batchSaver != null) {
      await batchSaver(result.subscriptions);
    } else {
      for (final subscription in result.subscriptions) {
        await save(subscription);
      }
    }
    await onApplied();
    return result;
  }

  static SubscriptionProfileImportResult merge({
    required List<Subscription> existing,
    required List<Subscription> imported,
    SubscriptionProfileIdGenerator generateId = SubscriptionFetcher.generateId,
  }) {
    if (imported.isEmpty) {
      return const SubscriptionProfileImportResult.empty();
    }

    final byIdentity = <String, Subscription>{};
    final usedIds = <String>{};
    for (final subscription in existing) {
      _indexSubscription(byIdentity, subscription);
      final id = subscription.id.trim();
      if (id.isNotEmpty) {
        usedIds.add(id);
      }
    }

    var nextSortOrder = existing.isEmpty
        ? 0
        : existing
                  .map((subscription) => subscription.sortOrder ?? 0)
                  .fold<int>(0, max) +
              1;
    final plannedById = <String, Subscription>{};
    final plannedIds = <String>[];
    final addedIds = <String>{};
    final updatedIds = <String>{};

    for (final importedSubscription in imported) {
      final importedId = importedSubscription.id.trim();
      final importedUrl = importedSubscription.url.trim();
      final matched =
          (importedId.isEmpty ? null : byIdentity['id:$importedId']) ??
          (importedUrl.isEmpty ? null : byIdentity['url:$importedUrl']);

      late final Subscription normalized;
      if (matched == null) {
        final id = _availableId(importedId, usedIds, generateId);
        normalized = importedSubscription.copyWith(
          id: id,
          sortOrder: nextSortOrder++,
        );
        addedIds.add(id);
      } else {
        normalized = importedSubscription.copyWith(
          id: matched.id,
          sortOrder: matched.sortOrder,
          selectedProxyTag: importedSubscription.selectedProxyTag.isNotEmpty
              ? importedSubscription.selectedProxyTag
              : matched.selectedProxyTag,
        );
        if (!addedIds.contains(matched.id)) {
          updatedIds.add(matched.id);
        }
      }

      final id = normalized.id;
      if (!plannedById.containsKey(id)) {
        plannedIds.add(id);
      }
      plannedById[id] = normalized;
      usedIds.add(id);
      _indexSubscription(byIdentity, normalized);
    }

    return SubscriptionProfileImportResult(
      subscriptions: [for (final id in plannedIds) plannedById[id]!],
      addedCount: addedIds.length,
      updatedCount: updatedIds.length,
    );
  }

  static void _indexSubscription(
    Map<String, Subscription> byIdentity,
    Subscription subscription,
  ) {
    final id = subscription.id.trim();
    final url = subscription.url.trim();
    if (id.isNotEmpty) {
      byIdentity['id:$id'] = subscription;
    }
    if (url.isNotEmpty) {
      byIdentity['url:$url'] = subscription;
    }
  }

  static String _availableId(
    String preferredId,
    Set<String> usedIds,
    SubscriptionProfileIdGenerator generateId,
  ) {
    if (isSafeSubscriptionStorageId(preferredId) &&
        !usedIds.contains(preferredId)) {
      return preferredId;
    }
    for (var attempt = 0; attempt < 32; attempt++) {
      final generated = generateId().trim();
      if (isSafeSubscriptionStorageId(generated) &&
          !usedIds.contains(generated)) {
        return generated;
      }
    }
    throw StateError('Could not allocate a unique subscription profile ID.');
  }
}
