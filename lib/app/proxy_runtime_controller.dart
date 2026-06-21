import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/models/subscription.dart';

class ProxyRuntimeGroupUpdateInput {
  const ProxyRuntimeGroupUpdateInput({
    required this.rawGroups,
    required this.activeSubscription,
    required this.selectedProxyTag,
    required this.pendingRuntimeSelectTag,
    required this.runtimeSelectionUpdatesAllowed,
    required this.currentResolvedActiveOutboundTag,
    required this.activeOutboundTags,
    required this.activeOutboundLatestPings,
    required this.proxyCacheContainsTag,
    required this.visibleGroupProxyCacheMissingChild,
  });

  final List<dynamic> rawGroups;
  final Subscription activeSubscription;
  final String selectedProxyTag;
  final String? pendingRuntimeSelectTag;
  final bool runtimeSelectionUpdatesAllowed;
  final String? currentResolvedActiveOutboundTag;
  final Set<String> activeOutboundTags;
  final Map<String, int?> activeOutboundLatestPings;
  final bool Function(String? tag) proxyCacheContainsTag;
  final bool Function(String groupTag, String childTag)
  visibleGroupProxyCacheMissingChild;
}

class ProxyRuntimeGroupUpdateResult {
  const ProxyRuntimeGroupUpdateResult({
    required this.changed,
    required this.requiresRootRebuild,
    required this.shouldRebuildProxyCache,
    required this.shouldClearRuntimeProxySelectionGuard,
    required this.shouldCancelUrlTestFallbackTimer,
    required this.realOutboundRuntimeStateChanged,
    this.selectedProxyTagToApply,
  });

  static const noChanges = ProxyRuntimeGroupUpdateResult(
    changed: false,
    requiresRootRebuild: false,
    shouldRebuildProxyCache: false,
    shouldClearRuntimeProxySelectionGuard: false,
    shouldCancelUrlTestFallbackTimer: false,
    realOutboundRuntimeStateChanged: false,
  );

  final bool changed;
  final bool requiresRootRebuild;
  final bool shouldRebuildProxyCache;
  final bool shouldClearRuntimeProxySelectionGuard;
  final bool shouldCancelUrlTestFallbackTimer;
  final bool realOutboundRuntimeStateChanged;
  final String? selectedProxyTagToApply;
}

class ProxyRuntimeController {
  static const urlTestStatusUnavailable = 'unavailable';

  static bool effectiveLatencyUnavailable({
    required bool urlTestUnavailable,
    required bool endpointFallbackReachable,
  }) {
    return urlTestUnavailable && !endpointFallbackReachable;
  }

  static String? effectiveLatencyError({
    required String? urlTestError,
    required bool endpointFallbackReachable,
  }) {
    return endpointFallbackReachable ? null : urlTestError;
  }

  int? lowestLatency;
  String? runtimeLowestOutboundTag;
  bool urlTestInFlight = false;

  final Map<String, String> runtimeLowestSelections = <String, String>{};
  final Map<String, int> runtimeLatencies = <String, int>{};
  final Set<String> unavailableLatencyTags = <String>{};
  final Map<String, String> latencyErrors = <String, String>{};
  final Map<String, int> latencyFailureCounts = <String, int>{};
  final Map<String, String> runtimeGroupSelections = <String, String>{};

  final Map<String, Map<String, int>> _pendingLatestPingSaves =
      <String, Map<String, int>>{};
  Timer? _latestPingSaveTimer;
  bool _latestPingSaveInFlight = false;
  bool _latestPingSaveRequested = false;
  bool _updatesFrozen = false;

  bool get updatesFrozen => _updatesFrozen;

  void dispose() {
    _latestPingSaveTimer?.cancel();
  }

  void beginTransition() {
    if (_updatesFrozen) {
      return;
    }
    _updatesFrozen = true;
    urlTestInFlight = false;
    AppLogStore.info(
      'proxy',
      'urlTest updates frozen during runtime transition',
    );
  }

  void endTransition() {
    if (!_updatesFrozen) {
      return;
    }
    _updatesFrozen = false;
    AppLogStore.info(
      'proxy',
      'urlTest updates unfrozen after runtime transition',
    );
  }

  void reset({bool resetUrlTestInFlight = true}) {
    _updatesFrozen = false;
    runtimeLatencies.clear();
    unavailableLatencyTags.clear();
    latencyErrors.clear();
    latencyFailureCounts.clear();
    runtimeGroupSelections.clear();
    runtimeLowestSelections.clear();
    lowestLatency = null;
    runtimeLowestOutboundTag = null;
    if (resetUrlTestInFlight) {
      urlTestInFlight = false;
    }
  }

  String? runtimeLowestOutboundTagFor(String lowestTag) {
    final selected = runtimeLowestSelections[lowestTag];
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }
    if (lowestTag == lowestProxyTag) {
      return runtimeLowestOutboundTag;
    }
    return null;
  }

  ProxyRuntimeGroupUpdateResult applyGroupUpdates(
    ProxyRuntimeGroupUpdateInput input,
  ) {
    final rawGroups = input.rawGroups;
    if (rawGroups.isEmpty) {
      return ProxyRuntimeGroupUpdateResult.noChanges;
    }
    if (_updatesFrozen) {
      AppLogStore.debug(
        'proxy',
        'ignored URLTest group update while runtime transition is active '
            'groups=${rawGroups.length}',
      );
      return ProxyRuntimeGroupUpdateResult.noChanges;
    }

    final delays = <String, int?>{};
    final statuses = <String, String>{};
    final errors = <String, String>{};
    final times = <String, int>{};
    String? runtimeSelected;
    final subscriptionGroupTags = input.activeSubscription.groups
        .map((group) => group.tag)
        .toSet();
    final groupSelections = Map<String, String>.fromEntries(
      runtimeGroupSelections.entries.where(
        (entry) => subscriptionGroupTags.contains(entry.key),
      ),
    );
    final lowestSelections = Map<String, String>.fromEntries(
      runtimeLowestSelections.entries.where(
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

    _logUrlTestGroupUpdateSummary(
      groupCount: rawGroups.length,
      delays: delays,
      statuses: statuses,
      errors: errors,
      runtimeSelected: runtimeSelected,
      activeOutboundTag: input.currentResolvedActiveOutboundTag,
    );

    final persistableDelays = <String, int?>{
      for (final entry in delays.entries)
        if (input.activeOutboundTags.contains(entry.key))
          entry.key: entry.value,
    };
    _queueLatestPingSave(input.activeSubscription.id, persistableDelays);

    if (delays.isEmpty &&
        statuses.isEmpty &&
        runtimeSelected == null &&
        mapEquals(runtimeLowestSelections, lowestSelections) &&
        mapEquals(runtimeGroupSelections, groupSelections)) {
      return ProxyRuntimeGroupUpdateResult.noChanges;
    }

    final nextRuntimeLatencies = Map<String, int>.from(runtimeLatencies);
    final nextUnavailableLatencyTags = Set<String>.from(unavailableLatencyTags);
    final nextLatencyErrors = Map<String, String>.from(latencyErrors);
    final nextLatencyFailureCounts = Map<String, int>.from(
      latencyFailureCounts,
    );
    final touchedTags = <String>{
      ...delays.keys,
      ...statuses.keys,
      ...errors.keys,
    };
    for (final tag in touchedTags) {
      final status = statuses[tag];
      if (status == urlTestStatusUnavailable) {
        if (_isTransientLatencyError(errors[tag])) {
          nextUnavailableLatencyTags.remove(tag);
          nextLatencyErrors.remove(tag);
          nextLatencyFailureCounts.remove(tag);
          continue;
        }
        final knownLatency =
            nextRuntimeLatencies[tag] ?? input.activeOutboundLatestPings[tag];
        final failureCount = (nextLatencyFailureCounts[tag] ?? 0) + 1;
        nextLatencyFailureCounts[tag] = failureCount;
        if (knownLatency != null && failureCount < 2) {
          AppLogStore.debug(
            'proxy',
            'urlTest single failure ignored tag=$tag error=${errors[tag] ?? ''}',
          );
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
        nextLatencyFailureCounts.remove(tag);
      }
      if (delays.containsKey(tag)) {
        final delay = delays[tag];
        if (delay != null && delay > 0) {
          nextRuntimeLatencies[tag] = delay;
          nextUnavailableLatencyTags.remove(tag);
          nextLatencyErrors.remove(tag);
          nextLatencyFailureCounts.remove(tag);
        }
      }
    }

    int? nextLowestLatency;
    for (final entry in nextRuntimeLatencies.entries) {
      if (nextUnavailableLatencyTags.contains(entry.key)) {
        continue;
      }
      final delay = entry.value;
      if (nextLowestLatency == null || delay < nextLowestLatency) {
        nextLowestLatency = delay;
      }
    }

    final pendingRuntimeSelectTag = input.pendingRuntimeSelectTag;
    final runtimeSelectionConfirmsPending =
        pendingRuntimeSelectTag != null &&
        runtimeSelected == pendingRuntimeSelectTag;
    final runtimeSelectionIsStaleDuringPending =
        pendingRuntimeSelectTag != null &&
        runtimeSelected != null &&
        runtimeSelected.isNotEmpty &&
        runtimeSelected != pendingRuntimeSelectTag &&
        input.selectedProxyTag == pendingRuntimeSelectTag;
    if (runtimeSelectionIsStaleDuringPending) {
      AppLogStore.info(
        'proxy',
        'ignored stale runtime selected outbound tag=$runtimeSelected '
            'while pending tag=$pendingRuntimeSelectTag',
      );
    }

    final runtimeSelectionChanged =
        input.runtimeSelectionUpdatesAllowed &&
        !runtimeSelectionIsStaleDuringPending &&
        runtimeSelected != null &&
        runtimeSelected.isNotEmpty &&
        !isLowestProxyTag(runtimeSelected) &&
        !isLowestProxyTag(input.selectedProxyTag) &&
        input.selectedProxyTag != runtimeSelected;
    final latencyStateChanged =
        lowestLatency != nextLowestLatency ||
        urlTestInFlight ||
        !mapEquals(runtimeLatencies, nextRuntimeLatencies) ||
        !setEquals(unavailableLatencyTags, nextUnavailableLatencyTags) ||
        !mapEquals(latencyErrors, nextLatencyErrors) ||
        !mapEquals(latencyFailureCounts, nextLatencyFailureCounts) ||
        !mapEquals(runtimeLowestSelections, lowestSelections) ||
        !mapEquals(runtimeGroupSelections, groupSelections);
    final realOutboundRuntimeStateChanged =
        touchedTags.any(input.activeOutboundTags.contains) ||
        !mapEquals(runtimeLowestSelections, lowestSelections) ||
        !mapEquals(runtimeGroupSelections, groupSelections);

    if (!runtimeSelectionChanged && !latencyStateChanged) {
      return ProxyRuntimeGroupUpdateResult.noChanges;
    }

    final nextRuntimeLowestOutboundTag = lowestSelections[lowestProxyTag];
    final shouldRebuildProxyCache =
        (runtimeSelectionChanged &&
            !input.proxyCacheContainsTag(runtimeSelected)) ||
        lowestSelections.values.any(
          (tag) => !input.proxyCacheContainsTag(tag),
        ) ||
        groupSelections.entries.any(
          (entry) =>
              input.visibleGroupProxyCacheMissingChild(entry.key, entry.value),
        );
    final lowestSelectionsChanged = !mapEquals(
      runtimeLowestSelections,
      lowestSelections,
    );
    final groupSelectionsChanged = !mapEquals(
      runtimeGroupSelections,
      groupSelections,
    );
    final activeProxyTouched =
        input.currentResolvedActiveOutboundTag != null &&
        touchedTags.contains(input.currentResolvedActiveOutboundTag);
    final requiresRootRebuild =
        runtimeSelectionChanged ||
        lowestSelectionsChanged ||
        groupSelectionsChanged ||
        activeProxyTouched ||
        urlTestInFlight;

    runtimeLatencies
      ..clear()
      ..addAll(nextRuntimeLatencies);
    unavailableLatencyTags
      ..clear()
      ..addAll(nextUnavailableLatencyTags);
    latencyErrors
      ..clear()
      ..addAll(nextLatencyErrors);
    latencyFailureCounts
      ..clear()
      ..addAll(nextLatencyFailureCounts);
    runtimeGroupSelections
      ..clear()
      ..addAll(groupSelections);
    runtimeLowestSelections
      ..clear()
      ..addAll(lowestSelections);
    lowestLatency = nextLowestLatency;
    runtimeLowestOutboundTag = nextRuntimeLowestOutboundTag;
    final shouldCancelUrlTestFallbackTimer = urlTestInFlight;
    urlTestInFlight = false;

    return ProxyRuntimeGroupUpdateResult(
      changed: true,
      requiresRootRebuild: requiresRootRebuild,
      shouldRebuildProxyCache: shouldRebuildProxyCache,
      shouldClearRuntimeProxySelectionGuard: runtimeSelectionConfirmsPending,
      shouldCancelUrlTestFallbackTimer: shouldCancelUrlTestFallbackTimer,
      realOutboundRuntimeStateChanged: realOutboundRuntimeStateChanged,
      selectedProxyTagToApply: runtimeSelectionChanged ? runtimeSelected : null,
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

  void _logUrlTestGroupUpdateSummary({
    required int groupCount,
    required Map<String, int?> delays,
    required Map<String, String> statuses,
    required Map<String, String> errors,
    required String? runtimeSelected,
    required String? activeOutboundTag,
  }) {
    final positiveDelays = delays.entries
        .where((entry) => entry.value != null && entry.value! > 0)
        .toList();
    if (positiveDelays.isEmpty && !urlTestInFlight) {
      return;
    }
    MapEntry<String, int?>? minEntry;
    MapEntry<String, int?>? maxEntry;
    for (final entry in positiveDelays) {
      if (minEntry == null || entry.value! < minEntry.value!) {
        minEntry = entry;
      }
      if (maxEntry == null || entry.value! > maxEntry.value!) {
        maxEntry = entry;
      }
    }
    final maxDelay = maxEntry?.value ?? 0;
    if (!urlTestInFlight && maxDelay < 1000) {
      return;
    }
    final unavailableCount = statuses.values
        .where((status) => status == urlTestStatusUnavailable)
        .length;
    final errorSummary = errors.entries
        .take(4)
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
    final message =
        'urlTest group update groups=$groupCount '
        'delays=${positiveDelays.length}/${delays.length} '
        'min=${minEntry?.key ?? ''}:${minEntry?.value ?? ''} '
        'max=${maxEntry?.key ?? ''}:$maxDelay '
        'unavailable=$unavailableCount '
        'selected=${runtimeSelected ?? ''} '
        'active=${activeOutboundTag ?? ''}'
        '${errorSummary.isEmpty ? '' : ' errors=$errorSummary'}';
    if (maxDelay >= 1000) {
      AppLogStore.warning('proxy', message);
    } else {
      AppLogStore.info('proxy', message);
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
}
