import 'dart:async';

import 'package:meow_client/logging/app_log_store.dart';

enum ActiveProxyIpState { idle, checking, known, failed }

class ActiveProxyIpSnapshot {
  const ActiveProxyIpSnapshot({
    required this.state,
    required this.outboundTag,
    this.ip,
    this.countryCode,
    this.errorCode,
    required this.updatedAt,
  });

  const ActiveProxyIpSnapshot.idle()
    : state = ActiveProxyIpState.idle,
      outboundTag = '',
      ip = null,
      countryCode = null,
      errorCode = null,
      updatedAt = null;

  final ActiveProxyIpState state;
  final String outboundTag;
  final String? ip;
  final String? countryCode;
  final String? errorCode;
  final DateTime? updatedAt;

  bool get hasKnownIp =>
      state == ActiveProxyIpState.known && (ip?.trim().isNotEmpty ?? false);
}

class ActiveProxyIpTarget {
  const ActiveProxyIpTarget({
    required this.subscriptionId,
    required this.outboundTag,
    this.cachedIp,
    this.cachedCountryCode,
    this.hasCachedLocation = false,
  });

  final String subscriptionId;
  final String outboundTag;
  final String? cachedIp;
  final String? cachedCountryCode;
  final bool hasCachedLocation;

  String get key => '$subscriptionId\n$outboundTag';
  bool get hasCachedIp => cachedIp?.trim().isNotEmpty ?? false;
}

class ActiveProxyIpResolveResult {
  const ActiveProxyIpResolveResult({required this.ip, this.countryCode});

  final String ip;
  final String? countryCode;
}

class ActiveProxyIpController {
  ActiveProxyIpController({
    this.lookupMinInterval = const Duration(minutes: 5),
    this.failureBackoff = const Duration(minutes: 2),
    this.retryDelay = const Duration(seconds: 10),
    this.maxFailuresBeforeBackoff = 2,
  });

  final Duration lookupMinInterval;
  final Duration failureBackoff;
  final Duration retryDelay;
  final int maxFailuresBeforeBackoff;

  final Map<String, DateTime> _attempts = <String, DateTime>{};
  final Map<String, int> _failureCounts = <String, int>{};
  final Map<String, DateTime> _suppressedUntil = <String, DateTime>{};

  Timer? _timer;
  Timer? _retryTimer;
  int _token = 0;
  bool _disposed = false;
  ActiveProxyIpSnapshot snapshot = const ActiveProxyIpSnapshot.idle();

  void dispose() {
    _disposed = true;
    cancelPending();
  }

  void cancelPending() {
    _timer?.cancel();
    _timer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _token++;
  }

  void cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void reset({
    required void Function(ActiveProxyIpSnapshot snapshot) onSnapshot,
  }) {
    if (_disposed) {
      return;
    }
    cancelPending();
    _attempts.clear();
    _failureCounts.clear();
    _suppressedUntil.clear();
    _setSnapshot(const ActiveProxyIpSnapshot.idle(), onSnapshot);
  }

  void schedule({
    Duration delay = const Duration(milliseconds: 120),
    bool forceRefresh = false,
    required bool Function() isConnected,
    required bool Function() isForegroundActive,
    required ActiveProxyIpTarget? Function() currentTarget,
    required Future<bool> Function(String reason) networkUsable,
    required Future<ActiveProxyIpResolveResult?> Function(String outboundTag)
    resolveExternalIp,
    required Future<void> Function(
      ActiveProxyIpTarget target,
      ActiveProxyIpResolveResult result,
    )
    persistResult,
    required void Function(ActiveProxyIpSnapshot snapshot) onSnapshot,
  }) {
    if (_disposed) {
      return;
    }
    _timer?.cancel();
    final token = ++_token;
    if (!isConnected() || !isForegroundActive()) {
      return;
    }

    final target = currentTarget();
    if (target == null) {
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = null;

    final now = DateTime.now();
    if (forceRefresh) {
      _failureCounts.remove(target.key);
      _suppressedUntil.remove(target.key);
    }
    final suppressedUntil = _suppressedUntil[target.key];
    final showCachedImmediately = !forceRefresh && target.hasCachedIp;
    if (!forceRefresh &&
        suppressedUntil != null &&
        now.isBefore(suppressedUntil)) {
      if (showCachedImmediately) {
        _setSnapshot(_cachedSnapshot(target, now), onSnapshot);
      } else {
        _setSnapshot(
          ActiveProxyIpSnapshot(
            state: ActiveProxyIpState.failed,
            outboundTag: target.outboundTag,
            errorCode: 'lookup_backoff',
            updatedAt: now,
          ),
          onSnapshot,
        );
      }
      AppLogStore.warning(
        'proxy',
        'active_ip_lookup_result tag=${target.outboundTag} '
            'error=lookup_backoff',
      );
      return;
    }

    if (showCachedImmediately) {
      _setSnapshot(_cachedSnapshot(target, now), onSnapshot);
    } else {
      _setSnapshot(
        ActiveProxyIpSnapshot(
          state: ActiveProxyIpState.checking,
          outboundTag: target.outboundTag,
          updatedAt: now,
        ),
        onSnapshot,
      );
    }
    _timer = Timer(delay, () {
      unawaited(
        _runLookup(
          token: token,
          target: target,
          allowRetry: true,
          forceRefresh: forceRefresh,
          keepStaleOnFailure: showCachedImmediately,
          isConnected: isConnected,
          isForegroundActive: isForegroundActive,
          currentTarget: currentTarget,
          networkUsable: networkUsable,
          resolveExternalIp: resolveExternalIp,
          persistResult: persistResult,
          onSnapshot: onSnapshot,
        ),
      );
    });
  }

  Future<void> _runLookup({
    required int token,
    required ActiveProxyIpTarget target,
    required bool allowRetry,
    required bool forceRefresh,
    required bool keepStaleOnFailure,
    required bool Function() isConnected,
    required bool Function() isForegroundActive,
    required ActiveProxyIpTarget? Function() currentTarget,
    required Future<bool> Function(String reason) networkUsable,
    required Future<ActiveProxyIpResolveResult?> Function(String outboundTag)
    resolveExternalIp,
    required Future<void> Function(
      ActiveProxyIpTarget target,
      ActiveProxyIpResolveResult result,
    )
    persistResult,
    required void Function(ActiveProxyIpSnapshot snapshot) onSnapshot,
  }) async {
    if (!_isCurrent(
      token,
      target,
      isConnected,
      isForegroundActive,
      currentTarget,
    )) {
      return;
    }
    if (!await networkUsable('active_ip_lookup')) {
      if (_isCurrent(
            token,
            target,
            isConnected,
            isForegroundActive,
            currentTarget,
          ) &&
          !keepStaleOnFailure) {
        _setSnapshot(
          ActiveProxyIpSnapshot(
            state: ActiveProxyIpState.failed,
            outboundTag: target.outboundTag,
            errorCode: 'no_interface',
            updatedAt: DateTime.now(),
          ),
          onSnapshot,
        );
      }
      AppLogStore.warning(
        'proxy',
        'active_ip_lookup_result tag=${target.outboundTag} error=no_interface',
      );
      return;
    }

    final now = DateTime.now();
    final lastAttempt = _attempts[target.key];
    if (!forceRefresh &&
        lastAttempt != null &&
        now.difference(lastAttempt) < lookupMinInterval &&
        target.hasCachedLocation) {
      if (_isCurrent(
        token,
        target,
        isConnected,
        isForegroundActive,
        currentTarget,
      )) {
        _setSnapshot(
          ActiveProxyIpSnapshot(
            state: ActiveProxyIpState.known,
            outboundTag: target.outboundTag,
            ip: target.cachedIp?.trim(),
            countryCode: target.cachedCountryCode,
            updatedAt: DateTime.now(),
          ),
          onSnapshot,
        );
      }
      return;
    }
    _attempts[target.key] = now;

    final resolved = await resolveExternalIp(target.outboundTag);
    if (resolved == null) {
      _markLookupFailed(
        token: token,
        target: target,
        allowRetry: allowRetry,
        keepStaleOnFailure: keepStaleOnFailure,
        isConnected: isConnected,
        isForegroundActive: isForegroundActive,
        currentTarget: currentTarget,
        networkUsable: networkUsable,
        resolveExternalIp: resolveExternalIp,
        persistResult: persistResult,
        onSnapshot: onSnapshot,
      );
      return;
    }
    if (!_isCurrent(
      token,
      target,
      isConnected,
      isForegroundActive,
      currentTarget,
    )) {
      return;
    }

    _failureCounts.remove(target.key);
    _suppressedUntil.remove(target.key);
    _setSnapshot(
      ActiveProxyIpSnapshot(
        state: ActiveProxyIpState.known,
        outboundTag: target.outboundTag,
        ip: resolved.ip,
        countryCode: resolved.countryCode,
        updatedAt: DateTime.now(),
      ),
      onSnapshot,
    );
    AppLogStore.info(
      'proxy',
      'active_ip_lookup_result tag=${target.outboundTag} status=known',
    );
    await persistResult(target, resolved);
  }

  void _markLookupFailed({
    required int token,
    required ActiveProxyIpTarget target,
    required bool allowRetry,
    required bool keepStaleOnFailure,
    required bool Function() isConnected,
    required bool Function() isForegroundActive,
    required ActiveProxyIpTarget? Function() currentTarget,
    required Future<bool> Function(String reason) networkUsable,
    required Future<ActiveProxyIpResolveResult?> Function(String outboundTag)
    resolveExternalIp,
    required Future<void> Function(
      ActiveProxyIpTarget target,
      ActiveProxyIpResolveResult result,
    )
    persistResult,
    required void Function(ActiveProxyIpSnapshot snapshot) onSnapshot,
  }) {
    final failures = (_failureCounts[target.key] ?? 0) + 1;
    _failureCounts[target.key] = failures;
    final suppressLookups = failures >= maxFailuresBeforeBackoff;
    if (suppressLookups) {
      _suppressedUntil[target.key] = DateTime.now().add(failureBackoff);
    }
    if (!keepStaleOnFailure &&
        _isCurrent(
          token,
          target,
          isConnected,
          isForegroundActive,
          currentTarget,
        )) {
      _setSnapshot(
        ActiveProxyIpSnapshot(
          state: ActiveProxyIpState.failed,
          outboundTag: target.outboundTag,
          errorCode: 'lookup_failed',
          updatedAt: DateTime.now(),
        ),
        onSnapshot,
      );
    }
    AppLogStore.warning(
      'proxy',
      'active_ip_lookup_result tag=${target.outboundTag} error=lookup_failed '
          'failures=$failures suppressed=$suppressLookups',
    );
    if (!allowRetry ||
        suppressLookups ||
        !_isCurrent(
          token,
          target,
          isConnected,
          isForegroundActive,
          currentTarget,
        )) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, () {
      unawaited(
        _runLookup(
          token: token,
          target: target,
          allowRetry: false,
          forceRefresh: false,
          keepStaleOnFailure: keepStaleOnFailure,
          isConnected: isConnected,
          isForegroundActive: isForegroundActive,
          currentTarget: currentTarget,
          networkUsable: networkUsable,
          resolveExternalIp: resolveExternalIp,
          persistResult: persistResult,
          onSnapshot: onSnapshot,
        ),
      );
    });
  }

  bool _isCurrent(
    int token,
    ActiveProxyIpTarget target,
    bool Function() isConnected,
    bool Function() isForegroundActive,
    ActiveProxyIpTarget? Function() currentTarget,
  ) {
    if (_disposed ||
        !isConnected() ||
        !isForegroundActive() ||
        token != _token) {
      return false;
    }
    final current = currentTarget();
    return current != null &&
        current.subscriptionId == target.subscriptionId &&
        current.outboundTag == target.outboundTag;
  }

  void _setSnapshot(
    ActiveProxyIpSnapshot next,
    void Function(ActiveProxyIpSnapshot snapshot) onSnapshot,
  ) {
    if (_disposed) {
      return;
    }
    snapshot = next;
    onSnapshot(next);
  }

  ActiveProxyIpSnapshot _cachedSnapshot(
    ActiveProxyIpTarget target,
    DateTime updatedAt,
  ) {
    return ActiveProxyIpSnapshot(
      state: ActiveProxyIpState.known,
      outboundTag: target.outboundTag,
      ip: target.cachedIp?.trim(),
      countryCode: target.cachedCountryCode,
      updatedAt: updatedAt,
    );
  }
}
