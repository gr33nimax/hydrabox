import 'package:hydrabox/app/hydra_resource_latency_plan.dart';
import 'package:hydrabox/models/subscription.dart';

/// One protocol-agnostic URLTest target exposed by the client.
///
/// The probe implementation is identical for every outbound. Hydra v2 targets
/// only differ in where their native configuration comes from: independent
/// resource documents must be built in isolation and cannot be merged.
class UniversalUrlTestTarget {
  const UniversalUrlTestTarget({
    required this.runtimeTag,
    required this.nativeOutboundTag,
    this.profileId = '',
    this.validationError = '',
    this.requiresIsolatedConfig = false,
  });

  final String runtimeTag;
  final String nativeOutboundTag;
  final String profileId;
  final String validationError;
  final bool requiresIsolatedConfig;
}

class UniversalUrlTestPlan {
  const UniversalUrlTestPlan._();

  /// Returns every concrete user-selectable outbound, without protocol
  /// allowlists. This keeps future sing-box outbound types on the same path.
  static List<UniversalUrlTestTarget> targets(
    Subscription subscription, {
    Set<String> excludedRuntimeTags = const <String>{},
  }) {
    if (subscription.resourceConfigs.isNotEmpty) {
      return HydraResourceLatencyPlan.targets(
            subscription,
            excludedRuntimeTags: excludedRuntimeTags,
          )
          .map(
            (target) => UniversalUrlTestTarget(
              runtimeTag: target.runtimeTag,
              nativeOutboundTag: target.nativeEntrypointTag,
              profileId: target.profileId,
              validationError: target.validationError,
              requiresIsolatedConfig: true,
            ),
          )
          .toList(growable: false);
    }

    final seen = <String>{};
    final targets = <UniversalUrlTestTarget>[];
    void addTarget(String rawTag) {
      final tag = rawTag.trim();
      if (tag.isEmpty || excludedRuntimeTags.contains(tag) || !seen.add(tag)) {
        return;
      }
      targets.add(
        UniversalUrlTestTarget(runtimeTag: tag, nativeOutboundTag: tag),
      );
    }

    for (final outbound in subscription.selectableOutbounds) {
      if (outbound.info.deleted || outbound.config['_group_only'] == true) {
        continue;
      }
      addTarget(outbound.tag);
    }
    for (final chain in subscription.proxyChains) {
      addTarget(chain.tag);
    }
    return List<UniversalUrlTestTarget>.unmodifiable(targets);
  }
}
