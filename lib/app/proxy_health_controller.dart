import 'dart:async';
import 'dart:collection';

import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';

enum ProxyHealthState { checking, reachable, unreachable, stale }

class ProxyHealthSnapshot {
  const ProxyHealthSnapshot({
    required this.state,
    this.latency,
    this.errorCode,
    required this.checkedAt,
  });

  final ProxyHealthState state;
  final int? latency;
  final String? errorCode;
  final DateTime checkedAt;

  bool get isChecking => state == ProxyHealthState.checking;

  bool get isReachable =>
      state == ProxyHealthState.reachable && latency != null;
}

typedef ProxyHealthBoolGetter = bool Function();
typedef ProxyHealthIntGetter = int Function();
typedef ProxyHealthOutboundResolver = Outbound? Function(String tag);
typedef ProxyHealthNetworkCheck = Future<bool> Function(String reason);
typedef ProxyHealthProbeEndpoint =
    Future<EndpointProbeResult> Function(EndpointProbeRequest request);
typedef ProxyHealthVisualUpdate = void Function(Set<String> touchedTags);

class ProxyHealthController {
  ProxyHealthController({
    required ProxyHealthBoolGetter isMounted,
    required ProxyHealthBoolGetter isForegroundLifecycleActive,
    required ProxyHealthBoolGetter isConnected,
    required ProxyHealthBoolGetter isRuntimeTransitionInProgress,
    required ProxyHealthIntGetter concurrency,
    required ProxyHealthOutboundResolver resolveOutboundByTag,
    required ProxyHealthNetworkCheck networkInterfaceUsable,
    required ProxyHealthProbeEndpoint probeEndpoint,
    required ProxyHealthVisualUpdate onVisualUpdate,
    DateTime Function()? now,
    Duration successTtl = const Duration(seconds: 120),
    Duration failureTtl = const Duration(seconds: 45),
    Duration forceRefreshCooldown = const Duration(seconds: 8),
    Duration protectRetryDelay = const Duration(milliseconds: 900),
    int timeoutMs = 3000,
    int maxProtectRetries = 2,
  }) : _isMounted = isMounted,
       _isForegroundLifecycleActive = isForegroundLifecycleActive,
       _isConnected = isConnected,
       _isRuntimeTransitionInProgress = isRuntimeTransitionInProgress,
       _concurrency = concurrency,
       _resolveOutboundByTag = resolveOutboundByTag,
       _networkInterfaceUsable = networkInterfaceUsable,
       _probeEndpoint = probeEndpoint,
       _onVisualUpdate = onVisualUpdate,
       _now = now ?? DateTime.now,
       _successTtl = successTtl,
       _failureTtl = failureTtl,
       _forceRefreshCooldown = forceRefreshCooldown,
       _protectRetryDelay = protectRetryDelay,
       _timeoutMs = timeoutMs,
       _maxProtectRetries = maxProtectRetries;

  final ProxyHealthBoolGetter _isMounted;
  final ProxyHealthBoolGetter _isForegroundLifecycleActive;
  final ProxyHealthBoolGetter _isConnected;
  final ProxyHealthBoolGetter _isRuntimeTransitionInProgress;
  final ProxyHealthIntGetter _concurrency;
  final ProxyHealthOutboundResolver _resolveOutboundByTag;
  final ProxyHealthNetworkCheck _networkInterfaceUsable;
  final ProxyHealthProbeEndpoint _probeEndpoint;
  final ProxyHealthVisualUpdate _onVisualUpdate;
  final DateTime Function() _now;
  final Duration _successTtl;
  final Duration _failureTtl;
  final Duration _forceRefreshCooldown;
  final Duration _protectRetryDelay;
  final int _timeoutMs;
  final int _maxProtectRetries;

  final Map<String, ProxyHealthSnapshot> _health =
      <String, ProxyHealthSnapshot>{};
  final Set<String> _inFlight = <String>{};
  final Queue<String> _queue = Queue<String>();
  final Map<String, DateTime> _lastQueuedAt = <String, DateTime>{};
  final Map<String, int> _protectRetryCounts = <String, int>{};
  final Map<String, Timer> _protectRetryTimers = <String, Timer>{};
  int _generation = 0;
  bool _disposed = false;

  ProxyHealthSnapshot? effective(String tag) {
    final state = _health[tag];
    if (state == null) {
      return null;
    }
    if (state.state == ProxyHealthState.checking) {
      return state;
    }
    final age = _now().difference(state.checkedAt);
    final ttl = state.state == ProxyHealthState.reachable
        ? _successTtl
        : _failureTtl;
    if (age <= ttl) {
      return state;
    }
    return ProxyHealthSnapshot(
      state: ProxyHealthState.stale,
      latency: state.latency,
      errorCode: state.errorCode,
      checkedAt: state.checkedAt,
    );
  }

  ProxyHealthSnapshot? rawSnapshotForTesting(String tag) => _health[tag];

  void queueRefresh(
    Iterable<Outbound> outbounds, {
    required String reason,
    bool ignoreTtl = false,
  }) {
    if (_disposed || !_isForegroundLifecycleActive()) {
      return;
    }
    final now = _now();
    final manualRefresh = reason.startsWith('manual_ping_all');
    final queuedTags = <String>[];
    final byTag = <String, Outbound>{};
    for (final outbound in outbounds) {
      final tag = outbound.tag.trim();
      final host = outbound.server.trim();
      if (tag.isEmpty || host.isEmpty || outbound.port <= 0) {
        continue;
      }
      if (_inFlight.contains(tag) || _queue.contains(tag)) {
        continue;
      }
      final lastQueuedAt = _lastQueuedAt[tag];
      if (ignoreTtl &&
          !manualRefresh &&
          lastQueuedAt != null &&
          now.difference(lastQueuedAt) < _forceRefreshCooldown) {
        continue;
      }
      final current = effective(tag);
      if (!ignoreTtl &&
          current != null &&
          current.state != ProxyHealthState.stale) {
        continue;
      }
      byTag[tag] = outbound;
      _queue.add(tag);
      _lastQueuedAt[tag] = now;
      queuedTags.add(tag);
    }
    if (queuedTags.isEmpty) {
      return;
    }
    _markChecking(queuedTags);
    AppLogStore.info(
      'proxy',
      'recovery_probe_start reason=$reason count=${queuedTags.length}',
    );
    _drain(byTag, ++_generation);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    for (final timer in _protectRetryTimers.values) {
      timer.cancel();
    }
    _protectRetryTimers.clear();
    _queue.clear();
    _inFlight.clear();
    _protectRetryCounts.clear();
  }

  void _markChecking(Iterable<String> tags) {
    final now = _now();
    var changed = false;
    final touchedTags = <String>{};
    for (final rawTag in tags) {
      final tag = rawTag.trim();
      if (tag.isEmpty) {
        continue;
      }
      final current = _health[tag];
      _health[tag] = ProxyHealthSnapshot(
        state: ProxyHealthState.checking,
        latency: current?.latency,
        errorCode: null,
        checkedAt: now,
      );
      touchedTags.add(tag);
      changed = true;
    }
    if (changed) {
      _onVisualUpdate(touchedTags);
    }
  }

  void _drain(Map<String, Outbound> queuedOutbounds, int generation) {
    if (_disposed || !_isMounted() || generation != _generation) {
      return;
    }
    while (_inFlight.length < _concurrency() && _queue.isNotEmpty) {
      final tag = _queue.removeFirst();
      final outbound = queuedOutbounds[tag] ?? _resolveOutboundByTag(tag);
      if (outbound == null) {
        continue;
      }
      _inFlight.add(tag);
      unawaited(
        _runProbe(outbound, generation).whenComplete(() {
          _inFlight.remove(tag);
          _drain(queuedOutbounds, generation);
        }),
      );
    }
  }

  Future<void> _runProbe(Outbound outbound, int generation) async {
    final tag = outbound.tag.trim();
    if (tag.isEmpty || generation != _generation || _disposed) {
      return;
    }
    if (_isConnected() && !await _networkInterfaceUsable('proxy_probe')) {
      _health[tag] = ProxyHealthSnapshot(
        state: ProxyHealthState.stale,
        latency: _health[tag]?.latency,
        errorCode: 'no_interface',
        checkedAt: _now(),
      );
      _onVisualUpdate({tag});
      AppLogStore.warning(
        'proxy',
        'recovery_probe_result tag=$tag reachable=false error=no_interface',
      );
      return;
    }
    late final EndpointProbeResult result;
    try {
      result = await _probeEndpoint(
        EndpointProbeRequest(
          tag: tag,
          host: outbound.server,
          port: outbound.port,
          timeoutMs: _timeoutMs,
        ),
      );
    } catch (error) {
      if (_disposed || !_isMounted() || generation != _generation) {
        return;
      }
      _clearProtectRetry(tag);
      _health[tag] = ProxyHealthSnapshot(
        state: ProxyHealthState.unreachable,
        errorCode: 'probe_failed',
        checkedAt: _now(),
      );
      AppLogStore.warning(
        'proxy',
        'recovery_probe_result tag=$tag reachable=false '
            'error=probe_failed detail=$error',
      );
      _onVisualUpdate({tag});
      return;
    }
    if (_disposed || !_isMounted() || generation != _generation) {
      return;
    }
    if (_isConnected() && !result.protectedSocket) {
      final protectFailed = result.errorCode == 'protect_failed';
      _health[tag] = ProxyHealthSnapshot(
        state: ProxyHealthState.stale,
        latency: _health[tag]?.latency,
        errorCode: protectFailed ? 'protect_pending' : 'unprotected_probe',
        checkedAt: DateTime.fromMillisecondsSinceEpoch(result.checkedAtMillis),
      );
      if (protectFailed) {
        _scheduleProtectRetry(outbound, generation);
        AppLogStore.debug(
          'proxy',
          'probe deferred until VPN protect is ready tag=$tag',
        );
      } else {
        _clearProtectRetry(tag);
        AppLogStore.warning(
          'proxy',
          'probe_unprotected_ignored tag=$tag reachable=${result.reachable} '
              'latency=${result.latencyMs ?? ''} error=${result.errorCode}',
        );
      }
      _onVisualUpdate({tag});
      return;
    }
    _clearProtectRetry(tag);
    final state = result.reachable
        ? ProxyHealthState.reachable
        : ProxyHealthState.unreachable;
    _health[tag] = ProxyHealthSnapshot(
      state: state,
      latency: result.latencyMs,
      errorCode: result.errorCode.isEmpty ? null : result.errorCode,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(result.checkedAtMillis),
    );
    AppLogStore.info(
      'proxy',
      'recovery_probe_result tag=$tag reachable=${result.reachable} '
          'latency=${result.latencyMs ?? ''} error=${result.errorCode} '
          'protected=${result.protectedSocket}',
    );
    _onVisualUpdate({tag});
  }

  void _scheduleProtectRetry(Outbound outbound, int generation) {
    final tag = outbound.tag.trim();
    if (tag.isEmpty || generation != _generation || _disposed) {
      return;
    }
    final retryCount = _protectRetryCounts[tag] ?? 0;
    if (retryCount >= _maxProtectRetries) {
      return;
    }
    _protectRetryCounts[tag] = retryCount + 1;
    _protectRetryTimers[tag]?.cancel();
    _protectRetryTimers[tag] = Timer(_protectRetryDelay, () {
      _protectRetryTimers.remove(tag);
      if (_disposed ||
          !_isMounted() ||
          generation != _generation ||
          !_isConnected() ||
          !_isForegroundLifecycleActive() ||
          _isRuntimeTransitionInProgress() ||
          _inFlight.contains(tag) ||
          _queue.contains(tag)) {
        return;
      }
      _queue.add(tag);
      _markChecking([tag]);
      _drain({tag: outbound}, generation);
    });
  }

  void _clearProtectRetry(String tag) {
    _protectRetryCounts.remove(tag);
    _protectRetryTimers.remove(tag)?.cancel();
  }
}
