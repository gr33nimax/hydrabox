import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/models/app_view_models.dart';

void sortProxySummaries(
  List<AppProxySummary> items,
  ProxySort sort, {
  bool keepPinnedFirst = true,
}) {
  if (sort == ProxySort.source || items.length < 2) {
    return;
  }
  items.sort(
    (a, b) => compareProxySummaries(
      a,
      b,
      sort: sort,
      keepPinnedFirst: keepPinnedFirst,
    ),
  );
}

int compareProxySummaries(
  AppProxySummary a,
  AppProxySummary b, {
  required ProxySort sort,
  bool keepPinnedFirst = true,
}) {
  final pinnedOrder = _comparePinned(a, b, keepPinnedFirst);
  if (pinnedOrder != null) {
    return pinnedOrder;
  }
  return switch (sort) {
    ProxySort.source => 0,
    ProxySort.name => a.displayName.compareTo(b.displayName),
    ProxySort.country => a.countryCode.compareTo(b.countryCode),
    ProxySort.latency => _compareLatency(a, b),
  };
}

int _compareLatency(AppProxySummary a, AppProxySummary b) {
  final rankOrder = _latencyRank(a).compareTo(_latencyRank(b));
  if (rankOrder != 0) {
    return rankOrder;
  }
  final latencyOrder = (a.latency ?? 1 << 30).compareTo(b.latency ?? 1 << 30);
  if (latencyOrder != 0) {
    return latencyOrder;
  }
  return a.displayName.compareTo(b.displayName);
}

int? _comparePinned(
  AppProxySummary a,
  AppProxySummary b,
  bool keepPinnedFirst,
) {
  if (!keepPinnedFirst) {
    return null;
  }
  final aPinned = isPinnedProxyTag(a.tag);
  final bPinned = isPinnedProxyTag(b.tag);
  if (aPinned && bPinned) {
    return pinnedProxyTagOrder(a.tag).compareTo(pinnedProxyTagOrder(b.tag));
  }
  if (aPinned) {
    return -1;
  }
  if (bPinned) {
    return 1;
  }
  return null;
}

int _latencyRank(AppProxySummary proxy) {
  if (proxy.latencyFresh && proxy.latency != null) {
    return 0;
  }
  if (proxy.latencyChecking) {
    return 1;
  }
  if (!proxy.latencyUnavailable && proxy.latency != null) {
    return 2;
  }
  if (!proxy.latencyUnavailable) {
    return 3;
  }
  return 4;
}
