import 'package:hydrabox/core/lowest_proxy_groups.dart';
import 'package:hydrabox/models/subscription.dart';

class HydraResourceLatencyTarget {
  const HydraResourceLatencyTarget({
    required this.profileId,
    required this.resourceId,
    required this.runtimeTag,
  });

  final String profileId;
  final String resourceId;
  final String runtimeTag;
}

/// Plans operations that must keep Hydra Subscription v2 resources isolated.
///
/// Every resource is a complete native document. It must be rebuilt and
/// probed independently instead of being merged into the running selector.
class HydraResourceLatencyPlan {
  const HydraResourceLatencyPlan._();

  static List<HydraResourceLatencyTarget> targets(
    Subscription subscription, {
    Set<String> excludedRuntimeTags = const <String>{},
  }) {
    if (subscription.resourceConfigs.isEmpty) {
      return const <HydraResourceLatencyTarget>[];
    }
    final seenRuntimeTags = <String>{};
    final targets = <HydraResourceLatencyTarget>[];
    for (final profile in subscription.profiles) {
      final tag = profile.runtimeTag.trim();
      final resourceId = profile.resourceId.trim();
      if (!profile.enabled ||
          tag.isEmpty ||
          resourceId.isEmpty ||
          excludedRuntimeTags.contains(tag) ||
          !subscription.resourceConfigs.containsKey(resourceId) ||
          !seenRuntimeTags.add(tag)) {
        continue;
      }
      targets.add(
        HydraResourceLatencyTarget(
          profileId: profile.id,
          resourceId: resourceId,
          runtimeTag: tag,
        ),
      );
    }
    return targets;
  }

  static bool requiresRuntimeReload({
    required Subscription subscription,
    required String previousRuntimeTag,
    required String nextRuntimeTag,
  }) {
    if (subscription.resourceConfigs.isEmpty) {
      return false;
    }
    final next = _enabledProfileForRuntimeTag(subscription, nextRuntimeTag);
    if (next == null) {
      return false;
    }
    final current =
        _enabledProfileForId(subscription, subscription.selectedProfileId) ??
        _enabledProfileForRuntimeTag(subscription, previousRuntimeTag) ??
        _firstEnabledProfileWithResource(subscription);
    if (current == null) {
      return true;
    }
    return current.resourceId.trim() != next.resourceId.trim();
  }

  /// A selector group cannot span independent native documents. Resolve the
  /// virtual lowest-latency choice to one concrete profile before rebuilding
  /// the runtime, preferring fresh standalone measurements.
  static String concreteSelectionTag({
    required Subscription subscription,
    required String requestedRuntimeTag,
    required Map<String, int> runtimeLatencies,
  }) {
    final requested = requestedRuntimeTag.trim();
    if (subscription.resourceConfigs.isEmpty || !isLowestProxyTag(requested)) {
      return requested;
    }
    final candidates = targets(subscription);
    HydraResourceLatencyTarget? fastest;
    int? fastestDelay;
    for (final candidate in candidates) {
      final delay = runtimeLatencies[candidate.runtimeTag];
      if (delay != null &&
          delay > 0 &&
          (fastestDelay == null || delay < fastestDelay)) {
        fastest = candidate;
        fastestDelay = delay;
      }
    }
    if (fastest != null) {
      return fastest.runtimeTag;
    }
    for (final candidate in candidates) {
      if (candidate.profileId == subscription.selectedProfileId) {
        return candidate.runtimeTag;
      }
    }
    return candidates.isEmpty ? requested : candidates.first.runtimeTag;
  }

  static SubscriptionProfile? _enabledProfileForId(
    Subscription subscription,
    String profileId,
  ) {
    final normalized = profileId.trim();
    if (normalized.isEmpty) return null;
    for (final profile in subscription.profiles) {
      if (profile.enabled && profile.id == normalized) {
        return profile;
      }
    }
    return null;
  }

  static SubscriptionProfile? _enabledProfileForRuntimeTag(
    Subscription subscription,
    String runtimeTag,
  ) {
    final normalized = runtimeTag.trim();
    if (normalized.isEmpty) return null;
    for (final profile in subscription.profiles) {
      if (profile.enabled && profile.runtimeTag.trim() == normalized) {
        return profile;
      }
    }
    return null;
  }

  static SubscriptionProfile? _firstEnabledProfileWithResource(
    Subscription subscription,
  ) {
    for (final profile in subscription.profiles) {
      if (profile.enabled &&
          subscription.resourceConfigs.containsKey(profile.resourceId)) {
        return profile;
      }
    }
    return null;
  }
}
