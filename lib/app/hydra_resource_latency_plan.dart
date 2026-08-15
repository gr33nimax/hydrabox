import 'package:hydrabox/core/lowest_proxy_groups.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:hydrabox/singbox/hydra_proxy_chain_resolver.dart';

class HydraResourceLatencyTarget {
  const HydraResourceLatencyTarget({
    required this.profileId,
    required this.resourceId,
    required this.runtimeTag,
    required this.nativeEntrypointTag,
    this.validationError = '',
  });

  final String profileId;
  final String resourceId;
  final String runtimeTag;
  final String nativeEntrypointTag;
  final String validationError;
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
      final nativeEntrypointTag = profile.entrypointTag.trim();
      if (!profile.enabled ||
          tag.isEmpty ||
          resourceId.isEmpty ||
          nativeEntrypointTag.isEmpty ||
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
          nativeEntrypointTag: nativeEntrypointTag,
        ),
      );
    }
    for (final chain in subscription.proxyChains) {
      final tag = chain.tag.trim();
      if (tag.isEmpty || excludedRuntimeTags.contains(tag)) {
        continue;
      }
      if (!seenRuntimeTags.add(tag)) {
        final existingIndex = targets.indexWhere(
          (target) => target.runtimeTag == tag,
        );
        if (existingIndex >= 0) {
          final existing = targets[existingIndex];
          targets[existingIndex] = HydraResourceLatencyTarget(
            profileId: existing.profileId,
            resourceId: existing.resourceId,
            runtimeTag: tag,
            nativeEntrypointTag: existing.nativeEntrypointTag,
            validationError:
                'Hydra proxy chain runtime tag "$tag" is ambiguous',
          );
        }
        continue;
      }
      HydraProxyChainResolution? resolution;
      var validationError = '';
      try {
        resolution = HydraProxyChainResolver.resolveForLatency(
          subscription: subscription,
          chain: chain,
        );
      } on StateError catch (error) {
        validationError = error.message.toString();
      }
      final owner = resolution?.ownerProfile;
      // The generated chain is app-owned and is emitted into the selected
      // native document under the same tag. Invalid advertised chains remain
      // planned with a validation error so the caller can publish a terminal
      // unavailable result instead of leaving latency state pending forever.
      targets.add(
        HydraResourceLatencyTarget(
          profileId: owner?.id ?? '',
          resourceId: owner?.resourceId ?? '',
          runtimeTag: tag,
          nativeEntrypointTag: tag,
          validationError: validationError,
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
    final next = HydraProxyChainResolver.ownerProfileForSelection(
      subscription,
      nextRuntimeTag,
    );
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
    // App selection identities are not native selector tags. Rebuilding is the
    // transactional boundary that selects the profile's exact native
    // entrypoint, even when two profiles happen to share one resource.
    return current.id != next.id;
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
      if (candidate.validationError.isNotEmpty) {
        continue;
      }
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
      if (candidate.validationError.isEmpty &&
          candidate.profileId == subscription.selectedProfileId) {
        return candidate.runtimeTag;
      }
    }
    for (final candidate in candidates) {
      if (candidate.validationError.isEmpty) {
        return candidate.runtimeTag;
      }
    }
    return requested;
  }

  /// Keeps the user-visible virtual Lowest choice while moving the isolated
  /// native resource pointer to the concrete profile that will be compiled.
  static Subscription retainVirtualSelection({
    required Subscription subscription,
    required String requestedRuntimeTag,
    required String concreteRuntimeTag,
  }) {
    final requested = requestedRuntimeTag.trim();
    if (subscription.resourceConfigs.isEmpty || !isLowestProxyTag(requested)) {
      return subscription;
    }
    final concreteProfile = subscription.profileForRuntimeTag(
      concreteRuntimeTag,
    );
    if (concreteProfile == null) {
      throw StateError(
        'Lowest selection has no concrete Hydra profile for '
        '"${concreteRuntimeTag.trim()}"',
      );
    }
    return subscription.copyWith(
      selectedProxyTag: requested,
      selectedProfileId: concreteProfile.id,
    );
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
