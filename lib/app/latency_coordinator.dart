import 'dart:async';

import 'package:meow_client/logging/app_log_store.dart';

enum LatencySessionKind { active, full, startup }

class LatencyTestRequest {
  const LatencyTestRequest({
    this.groupTag = 'select',
    this.targetOutboundTag = '',
    this.priorityOutboundTag = '',
    this.excludeOutboundTag = '',
    required this.url,
    this.timeoutMillis = 3000,
    this.concurrency = 0,
    this.deadlineMillis = 10000,
    this.force = true,
  });

  final String groupTag;
  final String targetOutboundTag;
  final String priorityOutboundTag;
  final String excludeOutboundTag;
  final String url;
  final int timeoutMillis;
  final int concurrency;
  final int deadlineMillis;
  final bool force;

  LatencyTestRequest copyWith({int? timeoutMillis, int? deadlineMillis}) {
    return LatencyTestRequest(
      groupTag: groupTag,
      targetOutboundTag: targetOutboundTag,
      priorityOutboundTag: priorityOutboundTag,
      excludeOutboundTag: excludeOutboundTag,
      url: url,
      timeoutMillis: timeoutMillis ?? this.timeoutMillis,
      concurrency: concurrency,
      deadlineMillis: deadlineMillis ?? this.deadlineMillis,
      force: force,
    );
  }
}

typedef LatencyTestRunner = Future<void> Function(LatencyTestRequest request);
typedef LatencyBoolReader = bool Function();
typedef LatencyStringReader = String Function();
typedef LatencyIntReader = int Function();
typedef LatencySessionChanged =
    void Function(bool running, LatencySessionKind? kind, String targetTag);

class LatencyCoordinator {
  LatencyCoordinator({
    required LatencyTestRunner runTest,
    required LatencyBoolReader isConnected,
    required LatencyBoolReader isForeground,
    required LatencyStringReader activeOutboundTag,
    required LatencyStringReader testUrl,
    required LatencyIntReader outboundCount,
    required LatencySessionChanged onSessionChanged,
    LatencyBoolReader? canRunDiagnostics,
    LatencyIntReader? operationGeneration,
  }) : _runTest = runTest,
       _isConnected = isConnected,
       _isForeground = isForeground,
       _activeOutboundTag = activeOutboundTag,
       _testUrl = testUrl,
       _outboundCount = outboundCount,
       _onSessionChanged = onSessionChanged,
       _canRunDiagnostics = canRunDiagnostics ?? _alwaysReady,
       _operationGeneration = operationGeneration ?? _zeroGeneration;

  // A VLESS/Reality/WebSocket probe can legitimately need several seconds on
  // a freshly changed mobile network. Three seconds produced false timeouts
  // for an actively carrying outbound on real devices. Keep the probe under
  // the ten-second UI budget, but leave enough room for DNS, TCP and TLS.
  static const perOutboundTimeoutMillis = 15000;
  static const activeDeadlineMillis = 7000;
  static const fullDeadlineMillis = 15000;
  static const automaticFullTestMaxOutbounds = 250;
  static const rpcDeadlineGrace = Duration(milliseconds: 500);
  static const activeDedupWindow = Duration(seconds: 5);

  final LatencyTestRunner _runTest;
  final LatencyBoolReader _isConnected;
  final LatencyBoolReader _isForeground;
  final LatencyStringReader _activeOutboundTag;
  final LatencyStringReader _testUrl;
  final LatencyIntReader _outboundCount;
  final LatencySessionChanged _onSessionChanged;
  final LatencyBoolReader _canRunDiagnostics;
  final LatencyIntReader _operationGeneration;

  static bool _alwaysReady() => true;
  static int _zeroGeneration() => 0;

  Timer? _autoTimer;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  LatencySessionKind? _kind;
  String _targetTag = '';
  String _lastActiveTag = '';
  DateTime? _lastActiveFinishedAt;
  Completer<void>? _nativeSessionFinished;

  bool get isRunning => _running;
  LatencySessionKind? get kind => _kind;

  bool isChecking(String tag) {
    if (!_running) return false;
    return _targetTag.isEmpty || _targetTag == tag;
  }

  void configureAuto(Duration? interval) {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (_disposed || interval == null || interval <= Duration.zero) {
      return;
    }
    _autoTimer = Timer.periodic(interval, (_) {
      if (!_isConnected() || !_isForeground()) return;
      unawaited(runFull(reason: 'auto_interval'));
    });
  }

  Future<bool> runStartup({required String reason}) async {
    if (_outboundCount() > automaticFullTestMaxOutbounds) {
      AppLogStore.info(
        'latency',
        'startup full test skipped: outbounds=${_outboundCount()} '
            'limit=$automaticFullTestMaxOutbounds',
      );
      return false;
    }
    final activeTag = _activeOutboundTag().trim();
    return _runSession(
      kind: LatencySessionKind.startup,
      reason: reason,
      targetTag: '',
      requests: [_fullRequest(priorityTag: activeTag)],
    );
  }

  Future<bool> runActive({required String reason}) {
    final activeTag = _activeOutboundTag().trim();
    if (activeTag.isEmpty) {
      AppLogStore.debug('latency', 'active test skipped: no active outbound');
      return Future<bool>.value(false);
    }
    final lastFinishedAt = _lastActiveFinishedAt;
    if (_lastActiveTag == activeTag &&
        lastFinishedAt != null &&
        DateTime.now().difference(lastFinishedAt) < activeDedupWindow) {
      AppLogStore.debug(
        'latency',
        'active test skipped: deduplicated tag=$activeTag reason=$reason',
      );
      return Future<bool>.value(false);
    }
    return _runSession(
      kind: LatencySessionKind.active,
      reason: reason,
      targetTag: activeTag,
      // Keep the HTTP URLTest semantics, but constrain the native session to
      // the selected leaf. Merely prioritizing the leaf still tests every
      // member of the selector and can overload large subscriptions.
      requests: [_activeRequest(activeTag)],
    );
  }

  Future<bool> runFull({required String reason}) {
    if (reason == 'auto_interval' &&
        _outboundCount() > automaticFullTestMaxOutbounds) {
      AppLogStore.info(
        'latency',
        'automatic full test skipped: outbounds=${_outboundCount()} '
            'limit=$automaticFullTestMaxOutbounds',
      );
      return Future<bool>.value(false);
    }
    final activeTag = _activeOutboundTag().trim();
    return _runSession(
      kind: LatencySessionKind.full,
      reason: reason,
      targetTag: '',
      requests: [_fullRequest(priorityTag: activeTag)],
    );
  }

  void cancel() {
    _generation++;
    if (_running) {
      _running = false;
      _kind = null;
      _targetTag = '';
      _onSessionChanged(false, null, '');
    }
  }

  /// Invalidates UI state immediately, then waits for the issued native RPC
  /// to leave libbox's serialized command lane.
  Future<void> cancelAndWait({
    Duration maxWait = const Duration(seconds: 8),
  }) async {
    final pending = _nativeSessionFinished?.future;
    cancel();
    if (pending == null) return;
    try {
      await pending.timeout(maxWait);
    } on TimeoutException {
      // Its generation is stale already; a late result cannot update state.
    }
  }

  void dispose() {
    _disposed = true;
    _autoTimer?.cancel();
    _autoTimer = null;
    cancel();
  }

  LatencyTestRequest _fullRequest({
    required String priorityTag,
    String excludeTag = '',
  }) => LatencyTestRequest(
    priorityOutboundTag: priorityTag,
    excludeOutboundTag: excludeTag,
    url: _testUrl(),
    timeoutMillis: perOutboundTimeoutMillis,
    concurrency: 0,
    deadlineMillis: fullDeadlineMillis,
  );

  LatencyTestRequest _activeRequest(String targetTag) => LatencyTestRequest(
    targetOutboundTag: targetTag,
    priorityOutboundTag: targetTag,
    url: _testUrl(),
    timeoutMillis: perOutboundTimeoutMillis,
    concurrency: 1,
    deadlineMillis: activeDeadlineMillis,
  );

  Future<bool> _runSession({
    required LatencySessionKind kind,
    required String reason,
    required String targetTag,
    required List<LatencyTestRequest> requests,
  }) async {
    if (_disposed ||
        !_isConnected() ||
        !_isForeground() ||
        !_canRunDiagnostics()) {
      return false;
    }
    if (_running) {
      AppLogStore.info(
        'latency',
        'session skipped reason=$reason running=${_kind?.name ?? 'unknown'}',
      );
      return false;
    }
    final generation = ++_generation;
    final operationGeneration = _operationGeneration();
    final nativeSessionFinished = Completer<void>();
    _nativeSessionFinished = nativeSessionFinished;
    final startedAt = DateTime.now();
    _running = true;
    _kind = kind;
    _targetTag = targetTag;
    _onSessionChanged(true, kind, targetTag);
    AppLogStore.info(
      'latency',
      'session start kind=${kind.name} reason=$reason '
          'outbounds=${_outboundCount()} target=$targetTag requests=${requests.length}',
    );
    var completed = false;
    var completedRequests = 0;
    try {
      for (final request in requests) {
        if (_disposed ||
            generation != _generation ||
            operationGeneration != _operationGeneration() ||
            !_isConnected() ||
            !_canRunDiagnostics()) {
          break;
        }
        final sessionDeadlineMillis = switch (kind) {
          LatencySessionKind.active => activeDeadlineMillis,
          LatencySessionKind.full ||
          LatencySessionKind.startup => fullDeadlineMillis,
        };
        final elapsedMillis = DateTime.now()
            .difference(startedAt)
            .inMilliseconds;
        final remainingMillis = sessionDeadlineMillis - elapsedMillis;
        if (remainingMillis <= 0) {
          throw TimeoutException(
            'latency ${kind.name} session exceeded ${sessionDeadlineMillis}ms',
          );
        }
        final requestDeadline = request.deadlineMillis
            .clamp(1, remainingMillis)
            .toInt();
        final requestTimeout = request.timeoutMillis
            .clamp(1, requestDeadline)
            .toInt();
        final boundedRequest = request.copyWith(
          timeoutMillis: requestTimeout,
          deadlineMillis: requestDeadline,
        );
        await _runTest(
          boundedRequest,
        ).timeout(Duration(milliseconds: requestDeadline) + rpcDeadlineGrace);
        if (operationGeneration != _operationGeneration()) {
          break;
        }
        completedRequests++;
      }
      completed =
          !_disposed &&
          generation == _generation &&
          operationGeneration == _operationGeneration() &&
          completedRequests == requests.length;
      return completed;
    } catch (error, stackTrace) {
      final stale =
          generation != _generation ||
          operationGeneration != _operationGeneration();
      if (stale) {
        AppLogStore.debug(
          'latency',
          'discarded stale session result kind=${kind.name} reason=$reason '
              'error=$error',
        );
      } else {
        AppLogStore.warning(
          'latency',
          'session failed kind=${kind.name} reason=$reason error=$error\n$stackTrace',
        );
      }
      return false;
    } finally {
      if (!nativeSessionFinished.isCompleted) {
        nativeSessionFinished.complete();
      }
      if (identical(_nativeSessionFinished, nativeSessionFinished)) {
        _nativeSessionFinished = null;
      }
      if (generation == _generation) {
        if (operationGeneration == _operationGeneration() &&
            kind == LatencySessionKind.active &&
            targetTag.isNotEmpty) {
          _lastActiveTag = targetTag;
          _lastActiveFinishedAt = DateTime.now();
        }
        _running = false;
        _kind = null;
        _targetTag = '';
        _onSessionChanged(false, kind, targetTag);
      }
      AppLogStore.info(
        'latency',
        'session finish kind=${kind.name} reason=$reason completed=$completed '
            'elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
    }
  }
}
