import 'package:hydrabox/models/subscription.dart';

/// Maps telemetry from one isolated native Hydra resource back into the
/// app-owned profile identity used by selection and latency state.
class HydraRuntimeTagProjection {
  const HydraRuntimeTagProjection._();

  static List<dynamic> canonicalizeGroupUpdates({
    required Subscription subscription,
    required String selectedRuntimeTag,
    required List<dynamic> rawGroups,
  }) {
    if (subscription.resourceConfigs.isEmpty || rawGroups.isEmpty) {
      return rawGroups;
    }
    final profile =
        subscription.profileForRuntimeTag(selectedRuntimeTag) ??
        _selectedProfile(subscription);
    if (profile == null ||
        profile.runtimeTag.trim().isEmpty ||
        profile.entrypointTag.trim().isEmpty) {
      return rawGroups;
    }
    final nativeTag = profile.entrypointTag.trim();
    final appTag = profile.runtimeTag.trim();
    return rawGroups.map<dynamic>((rawGroup) {
      if (rawGroup is! Map) return rawGroup;
      final group = Map<String, dynamic>.from(rawGroup);
      if (group['tag']?.toString() == nativeTag) {
        group['tag'] = appTag;
      }
      if (group['selected']?.toString() == nativeTag) {
        group['selected'] = appTag;
      }
      final rawItems = group['items'];
      if (rawItems is List) {
        group['items'] = rawItems.map<dynamic>((rawItem) {
          if (rawItem is! Map || rawItem['tag']?.toString() != nativeTag) {
            return rawItem;
          }
          return <String, dynamic>{
            ...Map<String, dynamic>.from(rawItem),
            'tag': appTag,
          };
        }).toList(growable: false);
      }
      return group;
    }).toList(growable: false);
  }

  static SubscriptionProfile? _selectedProfile(Subscription subscription) {
    for (final profile in subscription.profiles) {
      if (profile.enabled && profile.id == subscription.selectedProfileId) {
        return profile;
      }
    }
    return null;
  }
}
