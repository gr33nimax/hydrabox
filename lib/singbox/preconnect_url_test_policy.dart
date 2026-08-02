import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/models/subscription.dart';

/// Resolves the one concrete outbound that can be tested without starting the
/// VPN. Synthetic and automatic groups are deliberately rejected.
String? resolvePreconnectUrlTestTarget({
  required String selectedTag,
  required Map<String, SubscriptionGroup> groupsByTag,
  required Map<String, String> runtimeGroupSelections,
  required Map<String, Outbound> outboundsByTag,
  Set<String> proxyChainTags = const <String>{},
}) {
  final selected = selectedTag.trim();
  if (selected.isEmpty || isLowestProxyTag(selected)) {
    return null;
  }

  final group = groupsByTag[selected];
  if (group != null) {
    if (group.type.trim().toLowerCase() != 'selector') {
      return null;
    }
    final child = runtimeGroupSelections[group.tag]?.trim() ?? '';
    if (child.isEmpty ||
        !group.outboundTags.contains(child) ||
        groupsByTag.containsKey(child)) {
      return null;
    }
    return _isConcrete(outboundsByTag[child]) ? child : null;
  }

  if (proxyChainTags.contains(selected)) {
    return selected;
  }
  return _isConcrete(outboundsByTag[selected]) ? selected : null;
}

bool _isConcrete(Outbound? outbound) {
  if (outbound == null || outbound.config['_group_only'] == true) {
    return false;
  }
  final type = outbound.type.trim().toLowerCase();
  return type != 'selector' && type != 'urltest';
}
