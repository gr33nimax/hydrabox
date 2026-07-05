import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/active_proxy_ip_controller.dart';

void main() {
  test('schedule publishes checking then known snapshot', () async {
    final controller = ActiveProxyIpController();
    addTearDown(controller.dispose);

    final snapshots = <ActiveProxyIpSnapshot>[];
    final persisted = <String>[];
    var resolveCalls = 0;

    controller.schedule(
      delay: Duration.zero,
      isConnected: () => true,
      isForegroundActive: () => true,
      currentTarget: () => _target(),
      networkUsable: (_) async => true,
      resolveExternalIp: (tag) async {
        resolveCalls++;
        return const ActiveProxyIpResolveResult(ip: '203.0.113.10');
      },
      persistResult: (target, result) async {
        persisted.add('${target.outboundTag}:${result.ip}');
      },
      onSnapshot: snapshots.add,
    );

    await _waitUntil(() => snapshots.length >= 2);

    expect(resolveCalls, 1);
    expect(snapshots.map((snapshot) => snapshot.state), [
      ActiveProxyIpState.checking,
      ActiveProxyIpState.known,
    ]);
    expect(snapshots.last.ip, '203.0.113.10');
    expect(persisted, ['vless-1:203.0.113.10']);
  });

  test('recent cached location avoids duplicate core lookup', () async {
    final controller = ActiveProxyIpController();
    addTearDown(controller.dispose);

    final snapshots = <ActiveProxyIpSnapshot>[];
    var target = _target();
    var resolveCalls = 0;

    Future<ActiveProxyIpResolveResult?> resolve(String tag) async {
      resolveCalls++;
      return const ActiveProxyIpResolveResult(ip: '203.0.113.10');
    }

    controller.schedule(
      delay: Duration.zero,
      isConnected: () => true,
      isForegroundActive: () => true,
      currentTarget: () => target,
      networkUsable: (_) async => true,
      resolveExternalIp: resolve,
      persistResult: (_, _) async {},
      onSnapshot: snapshots.add,
    );
    await _waitUntil(
      () =>
          snapshots.isNotEmpty &&
          snapshots.last.state == ActiveProxyIpState.known,
    );

    target = _target(cachedIp: '203.0.113.10', cachedCountryCode: 'FR');
    controller.schedule(
      delay: Duration.zero,
      isConnected: () => true,
      isForegroundActive: () => true,
      currentTarget: () => target,
      networkUsable: (_) async => true,
      resolveExternalIp: resolve,
      persistResult: (_, _) async {},
      onSnapshot: snapshots.add,
    );
    await _waitUntil(
      () =>
          snapshots.isNotEmpty &&
          snapshots.last.state == ActiveProxyIpState.known &&
          snapshots.last.countryCode == 'FR',
    );

    expect(resolveCalls, 1);
    expect(snapshots.last.ip, '203.0.113.10');
    expect(snapshots.last.countryCode, 'FR');
  });

  test('cached IP is shown immediately and kept when refresh fails', () async {
    final controller = ActiveProxyIpController();
    addTearDown(controller.dispose);

    final snapshots = <ActiveProxyIpSnapshot>[];
    var resolveCalls = 0;

    controller.schedule(
      delay: Duration.zero,
      isConnected: () => true,
      isForegroundActive: () => true,
      currentTarget: () => _target(cachedIp: '203.0.113.10'),
      networkUsable: (_) async => true,
      resolveExternalIp: (_) async {
        resolveCalls++;
        return null;
      },
      persistResult: (_, _) async => fail('failed refresh must not persist'),
      onSnapshot: snapshots.add,
    );

    expect(snapshots.single.state, ActiveProxyIpState.known);
    expect(snapshots.single.ip, '203.0.113.10');

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(resolveCalls, 1);
    expect(controller.snapshot.state, ActiveProxyIpState.known);
    expect(controller.snapshot.ip, '203.0.113.10');
  });

  test('force refresh bypasses recent cached location', () async {
    final controller = ActiveProxyIpController();
    addTearDown(controller.dispose);

    final snapshots = <ActiveProxyIpSnapshot>[];
    var target = _target();
    var resolveCalls = 0;

    Future<ActiveProxyIpResolveResult?> resolve(String tag) async {
      resolveCalls++;
      return ActiveProxyIpResolveResult(ip: '203.0.113.${10 + resolveCalls}');
    }

    controller.schedule(
      delay: Duration.zero,
      isConnected: () => true,
      isForegroundActive: () => true,
      currentTarget: () => target,
      networkUsable: (_) async => true,
      resolveExternalIp: resolve,
      persistResult: (_, _) async {},
      onSnapshot: snapshots.add,
    );
    await _waitUntil(
      () =>
          snapshots.isNotEmpty &&
          snapshots.last.state == ActiveProxyIpState.known,
    );

    target = _target(cachedIp: '203.0.113.11', cachedCountryCode: 'FR');
    controller.schedule(
      delay: Duration.zero,
      forceRefresh: true,
      isConnected: () => true,
      isForegroundActive: () => true,
      currentTarget: () => target,
      networkUsable: (_) async => true,
      resolveExternalIp: resolve,
      persistResult: (_, _) async {},
      onSnapshot: snapshots.add,
    );
    await _waitUntil(
      () =>
          snapshots.isNotEmpty &&
          snapshots.last.state == ActiveProxyIpState.known &&
          snapshots.last.ip == '203.0.113.12',
    );

    expect(resolveCalls, 2);
    expect(snapshots.last.countryCode, isNull);
  });

  test('disconnected schedule does not publish or resolve', () async {
    final controller = ActiveProxyIpController();
    addTearDown(controller.dispose);

    final snapshots = <ActiveProxyIpSnapshot>[];
    var resolveCalls = 0;

    controller.schedule(
      delay: Duration.zero,
      isConnected: () => false,
      isForegroundActive: () => true,
      currentTarget: () => _target(),
      networkUsable: (_) async => true,
      resolveExternalIp: (_) async {
        resolveCalls++;
        return const ActiveProxyIpResolveResult(ip: '203.0.113.10');
      },
      persistResult: (_, _) async {},
      onSnapshot: snapshots.add,
    );

    await Future<void>.delayed(Duration.zero);

    expect(resolveCalls, 0);
    expect(snapshots, isEmpty);
  });

  test('reset cancels pending lookup and publishes idle', () async {
    final controller = ActiveProxyIpController();
    addTearDown(controller.dispose);

    final snapshots = <ActiveProxyIpSnapshot>[];
    var resolveCalls = 0;

    controller.schedule(
      delay: const Duration(milliseconds: 30),
      isConnected: () => true,
      isForegroundActive: () => true,
      currentTarget: () => _target(),
      networkUsable: (_) async => true,
      resolveExternalIp: (_) async {
        resolveCalls++;
        return const ActiveProxyIpResolveResult(ip: '203.0.113.10');
      },
      persistResult: (_, _) async {},
      onSnapshot: snapshots.add,
    );
    controller.reset(onSnapshot: snapshots.add);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(resolveCalls, 0);
    expect(snapshots.map((snapshot) => snapshot.state), [
      ActiveProxyIpState.checking,
      ActiveProxyIpState.idle,
    ]);
  });

  test('stale result is ignored after active target changes', () async {
    final controller = ActiveProxyIpController();
    addTearDown(controller.dispose);

    final snapshots = <ActiveProxyIpSnapshot>[];
    var currentTarget = _target();

    controller.schedule(
      delay: Duration.zero,
      isConnected: () => true,
      isForegroundActive: () => true,
      currentTarget: () => currentTarget,
      networkUsable: (_) async => true,
      resolveExternalIp: (_) async {
        currentTarget = _target(outboundTag: 'vless-2');
        return const ActiveProxyIpResolveResult(ip: '203.0.113.10');
      },
      persistResult: (_, _) async => fail('stale result must not persist'),
      onSnapshot: snapshots.add,
    );

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(snapshots.map((snapshot) => snapshot.state), [
      ActiveProxyIpState.checking,
    ]);
    expect(controller.snapshot.state, ActiveProxyIpState.checking);
  });
}

ActiveProxyIpTarget _target({
  String outboundTag = 'vless-1',
  String cachedIp = '',
  String cachedCountryCode = '',
}) {
  return ActiveProxyIpTarget(
    subscriptionId: 'sub-1',
    outboundTag: outboundTag,
    cachedIp: cachedIp,
    cachedCountryCode: cachedCountryCode,
    hasCachedLocation: cachedIp.isNotEmpty && cachedCountryCode.isNotEmpty,
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not met before timeout');
}
