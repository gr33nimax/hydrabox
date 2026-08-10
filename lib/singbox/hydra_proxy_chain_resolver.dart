import 'package:hydrabox/core/hydra_profile_identity.dart';
import 'package:hydrabox/core/lowest_proxy_groups.dart';
import 'package:hydrabox/models/subscription.dart';

class HydraProxyChainResolution {
  const HydraProxyChainResolution({
    required this.ownerProfile,
    required this.target,
    required this.nativeDetourTag,
  });

  final SubscriptionProfile ownerProfile;
  final Outbound target;
  final String nativeDetourTag;
}

class _HydraProxyChainOwnership {
  const _HydraProxyChainOwnership({
    required this.targetProfile,
    required this.detourProfile,
    required this.virtualDetourTag,
  });

  final SubscriptionProfile targetProfile;
  final SubscriptionProfile? detourProfile;
  final String virtualDetourTag;
}

/// Resolves app-owned Hydra profile identities at the isolated native-resource
/// boundary used by generated proxy chains.
class HydraProxyChainResolver {
  const HydraProxyChainResolver._();

  static SubscriptionProfile? activeProfile(Subscription subscription) {
    if (subscription.resourceConfigs.isEmpty) return null;
    for (final profile in subscription.profiles) {
      if (profile.enabled &&
          profile.id == subscription.selectedProfileId &&
          subscription.resourceConfigs.containsKey(profile.resourceId)) {
        return profile;
      }
    }
    for (final profile in subscription.profiles) {
      if (profile.enabled &&
          subscription.resourceConfigs.containsKey(profile.resourceId)) {
        return profile;
      }
    }
    return null;
  }

  /// Returns the resource owner of [chain] without consulting the currently
  /// selected resource. The target profile owns the generated chain; its
  /// detour must be a concrete profile in that same resource or an owner-local
  /// virtual selector that is verified during full resolution.
  static SubscriptionProfile ownerProfile({
    required Subscription subscription,
    required SubscriptionProxyChain chain,
  }) {
    return _ownership(subscription: subscription, chain: chain).targetProfile;
  }

  /// Resolves an app-level selection to the profile whose native resource must
  /// be active. Ordinary selector/group tags have no dedicated owner.
  static SubscriptionProfile? ownerProfileForSelection(
    Subscription subscription,
    String runtimeTag,
  ) {
    if (subscription.resourceConfigs.isEmpty) return null;
    final normalized = runtimeTag.trim();
    if (normalized.isEmpty) return null;
    final profileMatches = subscription.profiles
        .where(
          (profile) =>
              profile.enabled && profile.runtimeTag.trim() == normalized,
        )
        .toList(growable: false);
    final chainMatches = subscription.proxyChains
        .where((chain) => chain.tag.trim() == normalized)
        .toList(growable: false);
    if (profileMatches.length + chainMatches.length > 1) {
      throw StateError(
        'Hydra runtime selection "$normalized" is ambiguous across profiles '
        'or proxy chains',
      );
    }
    if (profileMatches.length == 1) {
      final profile = profileMatches.single;
      if (!subscription.resourceConfigs.containsKey(profile.resourceId)) {
        throw StateError(
          'Hydra runtime selection "$normalized" owns missing resource '
          '"${profile.resourceId}"',
        );
      }
      return profile;
    }
    if (chainMatches.length == 1) {
      return resolveForLatency(
        subscription: subscription,
        chain: chainMatches.single,
      ).ownerProfile;
    }
    return null;
  }

  static HydraProxyChainResolution resolve({
    required Subscription subscription,
    required SubscriptionProxyChain chain,
    required Iterable<Outbound> activeResourceOutbounds,
    required Set<String> selectableBaseTags,
  }) {
    final ownership = _ownership(subscription: subscription, chain: chain);
    final active = activeProfile(subscription);
    if (active == null) {
      throw StateError(
        'Hydra proxy chain "${chain.tag.trim()}" has no enabled active '
        'resource',
      );
    }
    final ownerResourceId = ownership.targetProfile.resourceId.trim();
    if (active.resourceId.trim() != ownerResourceId) {
      throw StateError(
        'Hydra proxy chain "${chain.tag.trim()}" belongs to resource '
        '"$ownerResourceId", but the active native document is '
        '"${active.resourceId.trim()}"',
      );
    }
    return _resolveInOwnerResource(
      chain: chain,
      ownership: ownership,
      ownerResourceOutbounds: activeResourceOutbounds,
      selectableBaseTags: selectableBaseTags,
    );
  }

  static HydraProxyChainResolution resolveForLatency({
    required Subscription subscription,
    required SubscriptionProxyChain chain,
  }) {
    final ownership = _ownership(subscription: subscription, chain: chain);
    final ownerResourceId = ownership.targetProfile.resourceId.trim();
    final ownerOutbounds = subscription.outbounds
        .where((outbound) => !outbound.info.deleted)
        .where(
          (outbound) =>
              (outbound.config['_source_scope']?.toString() ?? '') ==
              ownerResourceId,
        )
        .toList(growable: false);
    final selectableTags = <String>{
      for (final outbound in ownerOutbounds)
        if (outbound.config['_group_only'] != true) outbound.tag.trim(),
    }..remove('');
    for (final group in subscription.groups) {
      final visibleMembers = group.outboundTags.where(selectableTags.contains);
      if (visibleMembers.length >= 2 && group.tag.trim().isNotEmpty) {
        selectableTags.add(group.tag.trim());
      }
    }
    if (selectableTags.length > 1) {
      selectableTags.add(lowestProxyTag);
    }
    return _resolveInOwnerResource(
      chain: chain,
      ownership: ownership,
      ownerResourceOutbounds: ownerOutbounds,
      selectableBaseTags: selectableTags,
    );
  }

  static _HydraProxyChainOwnership _ownership({
    required Subscription subscription,
    required SubscriptionProxyChain chain,
  }) {
    final chainTag = chain.tag.trim();
    if (subscription.resourceConfigs.isEmpty) {
      throw StateError(
        'Hydra proxy chain "$chainTag" cannot be resolved without resource '
        'identity',
      );
    }
    final targetSubscriptionId = chain.targetSubscriptionId.trim();
    if (targetSubscriptionId.isNotEmpty &&
        targetSubscriptionId != subscription.id) {
      throw StateError(
        'Hydra proxy chain "$chainTag" targets subscription '
        '"$targetSubscriptionId" from active subscription '
        '"${subscription.id}"; opaque cross-subscription snapshots cannot be '
        'composed into a Hydra resource',
      );
    }
    final targetProfile = _profileForRuntimeTag(
      subscription,
      chain.targetTag,
      chainTag: chainTag,
      role: 'target',
    );
    final detourTag = chain.detourTag.trim();
    final detourProfile = _optionalProfileForRuntimeTag(
      subscription,
      detourTag,
      chainTag: chainTag,
      role: 'detour',
    );
    final ownerResourceId = targetProfile.resourceId.trim();
    _requireConcreteOutboundProfile(
      chainTag: chainTag,
      role: 'target',
      profile: targetProfile,
    );
    if (detourProfile != null) {
      _requireConcreteOutboundProfile(
        chainTag: chainTag,
        role: 'detour',
        profile: detourProfile,
      );
      _requireSameResource(
        chainTag: chainTag,
        role: 'detour',
        profile: detourProfile,
        ownerResourceId: ownerResourceId,
      );
    } else {
      _requireVirtualDetourTag(
        subscription: subscription,
        chainTag: chainTag,
        detourTag: detourTag,
      );
    }
    if (!subscription.resourceConfigs.containsKey(ownerResourceId)) {
      throw StateError(
        'Hydra proxy chain "$chainTag" owner profile '
        '"${targetProfile.id}" references missing resource '
        '"$ownerResourceId"',
      );
    }
    return _HydraProxyChainOwnership(
      targetProfile: targetProfile,
      detourProfile: detourProfile,
      virtualDetourTag: detourProfile == null ? detourTag : '',
    );
  }

  static HydraProxyChainResolution _resolveInOwnerResource({
    required SubscriptionProxyChain chain,
    required _HydraProxyChainOwnership ownership,
    required Iterable<Outbound> ownerResourceOutbounds,
    required Set<String> selectableBaseTags,
  }) {
    final chainTag = chain.tag.trim();
    final ownerResourceId = ownership.targetProfile.resourceId.trim();
    if (chainTag.isEmpty) {
      throw StateError('Hydra proxy chain has an empty runtime tag');
    }
    if (selectableBaseTags.contains(chainTag)) {
      throw StateError(
        'Hydra proxy chain runtime tag "$chainTag" collides with a native '
        'selectable entry in owner resource "$ownerResourceId"',
      );
    }
    final outbounds = ownerResourceOutbounds.toList(growable: false);
    final target = _exactEntrypoint(
      chainTag: chainTag,
      role: 'target',
      profile: ownership.targetProfile,
      ownerResourceOutbounds: outbounds,
    );
    if (_isOpaqueOutbound(target) ||
        target.type.trim().toLowerCase() == 'direct') {
      throw StateError(
        'Hydra proxy chain "$chainTag" target profile '
        '"${ownership.targetProfile.id}" is an opaque or non-leaf native '
        'entrypoint; it cannot be cloned safely',
      );
    }
    final detourProfile = ownership.detourProfile;
    late final String nativeDetourTag;
    if (detourProfile == null) {
      nativeDetourTag = ownership.virtualDetourTag;
    } else {
      final detour = _exactEntrypoint(
        chainTag: chainTag,
        role: 'detour',
        profile: detourProfile,
        ownerResourceOutbounds: outbounds,
      );
      if (_isOpaqueOutbound(detour)) {
        throw StateError(
          'Hydra proxy chain "$chainTag" detour profile '
          '"${detourProfile.id}" is an opaque or non-leaf native entrypoint; '
          'it cannot own a dial detour safely',
        );
      }
      nativeDetourTag = detour.tag.trim();
    }
    if (!selectableBaseTags.contains(nativeDetourTag)) {
      throw StateError(
        'Hydra proxy chain "$chainTag" resolved detour "$nativeDetourTag" '
        'is not selectable inside owner resource "$ownerResourceId"',
      );
    }
    return HydraProxyChainResolution(
      ownerProfile: ownership.targetProfile,
      target: target,
      nativeDetourTag: nativeDetourTag,
    );
  }

  static SubscriptionProfile _profileForRuntimeTag(
    Subscription subscription,
    String runtimeTag, {
    required String chainTag,
    required String role,
  }) {
    final profile = _optionalProfileForRuntimeTag(
      subscription,
      runtimeTag,
      chainTag: chainTag,
      role: role,
    );
    if (profile == null) {
      throw StateError(
        'Hydra proxy chain "$chainTag" $role "${runtimeTag.trim()}" is not an '
        'unambiguous app-owned profile identity; opaque native snapshots '
        'cannot be chained safely',
      );
    }
    return profile;
  }

  static SubscriptionProfile? _optionalProfileForRuntimeTag(
    Subscription subscription,
    String runtimeTag, {
    required String chainTag,
    required String role,
  }) {
    final normalized = runtimeTag.trim();
    if (normalized.isEmpty) return null;
    final matches = subscription.profiles
        .where((profile) => profile.runtimeTag.trim() == normalized)
        .toList(growable: false);
    if (matches.length > 1) {
      throw StateError(
        'Hydra proxy chain "$chainTag" $role "$normalized" is ambiguous '
        'across app-owned profiles',
      );
    }
    if (matches.isEmpty) return null;
    final profile = matches.single;
    if (!profile.enabled) {
      throw StateError(
        'Hydra proxy chain "$chainTag" $role profile "${profile.id}" is '
        'disabled',
      );
    }
    return profile;
  }

  static void _requireVirtualDetourTag({
    required Subscription subscription,
    required String chainTag,
    required String detourTag,
  }) {
    if (detourTag.isEmpty) {
      throw StateError('Hydra proxy chain "$chainTag" has an empty detour');
    }
    final nativeProfileCollisions = subscription.profiles
        .where((profile) => profile.entrypointTag.trim() == detourTag)
        .length;
    final chainCollisions = subscription.proxyChains
        .where((chain) => chain.tag.trim() == detourTag)
        .length;
    final groupMatches = subscription.groups
        .where((group) => group.tag.trim() == detourTag)
        .length;
    if (HydraProfileIdentity.isRuntimeTag(detourTag) ||
        nativeProfileCollisions > 0 ||
        chainCollisions > 0 ||
        groupMatches > 1) {
      throw StateError(
        'Hydra proxy chain "$chainTag" detour "$detourTag" is not an '
        'unambiguous app-owned profile identity or virtual owner-local tag',
      );
    }
    if (!isLowestProxyTag(detourTag) && groupMatches != 1) {
      throw StateError(
        'Hydra proxy chain "$chainTag" detour "$detourTag" is opaque; only '
        'an app-owned profile, lowest group, or declared proxy group may be '
        'used',
      );
    }
  }

  static void _requireConcreteOutboundProfile({
    required String chainTag,
    required String role,
    required SubscriptionProfile profile,
  }) {
    if (profile.entrypointSection.trim() != 'outbounds') {
      throw StateError(
        'Hydra proxy chain "$chainTag" $role profile "${profile.id}" points '
        'to opaque section "${profile.entrypointSection}"; only a concrete '
        'outbound can participate in a chain',
      );
    }
  }

  static void _requireSameResource({
    required String chainTag,
    required String role,
    required SubscriptionProfile profile,
    required String ownerResourceId,
  }) {
    final resourceId = profile.resourceId.trim();
    if (resourceId != ownerResourceId) {
      throw StateError(
        'Hydra proxy chain "$chainTag" $role profile "${profile.id}" belongs '
        'to resource "$resourceId", but target owner resource is '
        '"$ownerResourceId"; cross-resource composition is forbidden',
      );
    }
  }

  static Outbound _exactEntrypoint({
    required String chainTag,
    required String role,
    required SubscriptionProfile profile,
    required List<Outbound> ownerResourceOutbounds,
  }) {
    final matches = ownerResourceOutbounds.where((outbound) {
      final sourceSection =
          outbound.config['_hydra_source_index_section']?.toString() ??
          outbound.config['_hydra_source_section']?.toString() ??
          '';
      final sourceTag =
          outbound.config['_hydra_original_tag']?.toString() ?? outbound.tag;
      final sourceScope =
          outbound.config['_source_scope']?.toString() ?? '';
      return sourceScope == profile.resourceId &&
          sourceSection == profile.entrypointSection &&
          sourceTag == profile.entrypointTag;
    }).toList(growable: false);
    if (matches.length != 1) {
      throw StateError(
        'Hydra proxy chain "$chainTag" $role profile "${profile.id}" did not '
        'resolve to exactly one native entrypoint in resource '
        '"${profile.resourceId}"',
      );
    }
    return matches.single;
  }

  static bool _isOpaqueOutbound(Outbound outbound) {
    final config = outbound.config;
    final type = outbound.type.trim().toLowerCase();
    return config['_group_only'] == true ||
        type == 'selector' ||
        type == 'urltest' ||
        config['outbounds'] is List ||
        config['providers'] is List ||
        config['endpoint'] != null;
  }
}
