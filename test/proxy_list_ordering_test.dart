import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/features/proxies/proxy_list_ordering.dart';
import 'package:meow_client/models/app_view_models.dart';
import 'package:meow_client/models/proxy_runtime_visual_state.dart';

void main() {
  test('source ordering preserves provider order', () {
    final items = [_proxy('b', 'Beta'), _proxy('a', 'Alpha')];

    sortProxySummaries(items, ProxySort.source);

    expect(items.map((item) => item.tag), ['b', 'a']);
  });

  test('primary lowest stays pinned for every interactive sort', () {
    for (final sort in const [
      ProxySort.latency,
      ProxySort.name,
      ProxySort.country,
    ]) {
      final items = [
        _proxy('fast', 'Alpha', latency: 1, country: 'AA'),
        _proxy(lowestProxyTag, 'lowest', latency: 999, country: 'ZZ'),
      ];

      sortProxySummaries(items, sort);

      expect(items.first.tag, lowestProxyTag, reason: sort.name);
    }
  });

  test('latency ordering ranks fresh, checking, stale and unavailable', () {
    final items = [
      _proxy('unavailable', 'Unavailable', unavailable: true),
      _proxy('stale', 'Stale', latency: 10),
      _proxy('checking', 'Checking', checking: true),
      _proxy('fresh-slow', 'Fresh slow', latency: 80, fresh: true),
      _proxy('fresh-fast', 'Fresh fast', latency: 20, fresh: true),
    ];

    sortProxySummaries(items, ProxySort.latency, keepPinnedFirst: false);

    expect(items.map((item) => item.tag), [
      'fresh-fast',
      'fresh-slow',
      'checking',
      'stale',
      'unavailable',
    ]);
  });

  test('unavailable state wins over a stale successful latency', () {
    final items = [
      _proxy(
        'failed-with-old-ping',
        'Failed',
        latency: 1,
        fresh: true,
        unavailable: true,
      ),
      _proxy('healthy', 'Healthy', latency: 50, fresh: true),
    ];

    sortProxySummaries(items, ProxySort.latency, keepPinnedFirst: false);

    expect(items.map((item) => item.tag), ['healthy', 'failed-with-old-ping']);
  });

  test('latency ordering uses the latest runtime visual state', () {
    final items = [
      _proxy('old-fast', 'Old fast', latency: 1, fresh: true),
      _proxy('healthy', 'Healthy', latency: 50, fresh: true),
    ];
    const runtimeStates = <String, ProxyRuntimeVisualState>{
      'old-fast': ProxyRuntimeVisualState(
        latencyUnavailable: true,
        latencyError: 'i/o timeout',
      ),
      'healthy': ProxyRuntimeVisualState(latency: 25, latencyFresh: true),
    };

    sortProxySummaries(
      items,
      ProxySort.latency,
      keepPinnedFirst: false,
      runtimeStateFor: (tag) => runtimeStates[tag],
    );

    expect(items.map((item) => item.tag), ['healthy', 'old-fast']);
  });

  test('runtime state can clear an old latency without marking it dead', () {
    final items = [
      _proxy('old-fast', 'Old fast', latency: 1, fresh: true),
      _proxy('stale', 'Stale', latency: 50),
    ];
    const runtimeStates = <String, ProxyRuntimeVisualState>{
      'old-fast': ProxyRuntimeVisualState(latencyError: 'unexpected EOF'),
    };

    sortProxySummaries(
      items,
      ProxySort.latency,
      keepPinnedFirst: false,
      runtimeStateFor: (tag) => runtimeStates[tag],
    );

    expect(items.map((item) => item.tag), ['stale', 'old-fast']);
  });
}

AppProxySummary _proxy(
  String tag,
  String name, {
  String country = '',
  int? latency,
  bool fresh = false,
  bool checking = false,
  bool unavailable = false,
}) {
  return AppProxySummary(
    tag: tag,
    displayName: name,
    countryCode: country,
    type: 'vless',
    server: 'example.com',
    port: 443,
    detailText: 'VLESS · TLS',
    ip: '',
    latency: latency,
    latencyFresh: fresh,
    latencyChecking: checking,
    latencyUnavailable: unavailable,
    latencyError: null,
    protocolLabel: 'VLESS · TLS',
    endpointLabel: 'example.com:443',
  );
}
