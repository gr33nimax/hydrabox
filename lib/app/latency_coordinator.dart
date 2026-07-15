import 'dart:async';

import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/singbox/libbox_capabilities.dart';

enum LatencySessionKind { full, startup }

enum LatencySessionPhase { idle, startingRpc, collectingEvents, settled }

class LatencyUiPolicy {
  const LatencyUiPolicy({
    this.nativeCommandTimeout = const Duration(seconds: 5),
    this.firstEventGrace = const Duration(seconds: 4),
    this.eventSettleDelay = const Duration(milliseconds: 1800),
    this.hardWatchdog = const Duration(seconds: 30),
  });

  final Duration nativeCommandTimeout;
  final Duration firstEventGrace;
  final Duration eventSettleDelay;
  final Duration hardWatchdog;
}

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
}

typedef LatencyTestRunner = Future<void> Function(LatencyTestRequest request);
typedef LatencyBoolReader = bool Function();
typedef LatencyStringReader = String Function();
typedef LatencyIntReader = int Function();
typedef LatencyEventTimesReader = Map<String, int> Function();
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
    LatencyEventTimesReader? eventBaselineTimes,
    this.capabilities = LibboxCapabilities.bundledLegacy,
    this.uiPolicy = const LatencyUiPolicy(),
  }) : _runTest = runTest,
       _isConnected = isConnected,
       _isForeground = isForeground,
       _activeOutboundTag = activeOutboundTag,
       _testUrl = testUrl,
       _outboundCount = outboundCount,
       _onSessionChanged = onSessionChanged,
       _canRunDiagnostics = canRunDiagnostics ?? _alwaysReady,
       _operationGeneration = operationGeneration ?? _zeroGeneration,
       _eventBaselineTimes = eventBaselineTimes ?? _emptyEventTimes;

  static const perOutboundTimeoutMillis = 15000;
  static const fullDeadlineMillis = 60000;
  static const automaticFullTestMaxOutbounds = 250;

  final LatencyTestRunner _runTest;
  final LatencyBoolReader _isConnected;
  final LatencyBoolReader _isForeground;
  final LatencyStringReader _activeOutboundTag;
  final LatencyStringReader _testUrl;
  final LatencyIntReader _outboundCount;
  final LatencySessionChanged _onSessionChanged;
  final LatencyBoolReader _canRunDiagnostics;
  final LatencyIntReader _operationGeneration;
  final LatencyEventTimesReader _eventBaselineTimes;
  final LibboxCapabilities capabilities;
  final LatencyUiPolicy uiPolicy;

  static bool _alwaysReady() => true;
  static int _zeroGeneration() => 0;
  static Map<String, int> _emptyEventTimes() => const <String, int>{};

  Timer? _firstEventTimer;
  Timer? _settleTimer;
  Timer? _watchdogTimer;
  bool _disposed = false;
  int _generation = 0;
  int _sessionOperationGeneration = 0;
  int _sessionStartedAtSeconds = 0;
  LatencySessionPhase _phase = LatencySessionPhase.idle;
  LatencySessionKind? _kind;
  String _targetTag = '';
  Map<String, int> _baselineEventTimes = const <String, int>{};
  final Map<String, int> _acceptedEventTimes = <String, int>{};
  Completer<bool>? _sessionResult;
  Completer<void>? _nativeSessionFinished;
  bool _rpcAccepted = false;
  bool _receivedFreshEvent = false;

  bool get isRunning =>
      _phase == LatencySessionPhase.startingRpc ||
      _phase == LatencySessionPhase.collectingEvents;
  LatencySessionKind? get kind => isRunning ? _kind : null;
  LatencySessionPhase get phase => _phase;
  int get sessionStartedAtSeconds => _sessionStartedAtSeconds;

  bool isChecking(String tag) {
    if (!isRunning) return false;
    return _targetTag.isEmpty || _targetTag == tag;
  }

  Future<bool> runStartup({required String reason}) {
    if (_outboundCount() > automaticFullTestMaxOutbounds) {
      AppLogStore.info(
        'latency',
        'startup group test skipped: outbounds=${_outboundCount()} '
            'limit=$automaticFullTestMaxOutbounds',
      );
      return Future<bool>.value(false);
    }
    return _runGroupSession(kind: LatencySessionKind.startup, reason: reason);
  }

  Future<bool> runFull({required String reason}) {
    return _runGroupSession(kind: LatencySessionKind.full, reason: reason);
  }

  /// Records one timestamped result from the command client's group stream.
  /// Cached snapshots from before this session and duplicate events are
  /// ignored, so they cannot keep the progress UI alive indefinitely.
  bool handleGroupEvent({required String tag, required int timeSeconds}) {
    final normalizedTag = tag.trim();
    if (!isRunning || normalizedTag.isEmpty || timeSeconds <= 0) {
      return false;
    }
    if (_operationGeneration() != _sessionOperationGeneration ||
        !_isConnected() ||
        !_canRunDiagnostics()) {
      _settleCurrent(success: false, reason: 'stale_runtime');
      return false;
    }
    final baseline = _baselineEventTimes[normalizedTag] ?? 0;
    if (timeSeconds < _sessionStartedAtSeconds ||
        (baseline > 0 && timeSeconds <= baseline) ||
        timeSeconds <= (_acceptedEventTimes[normalizedTag] ?? 0)) {
      return false;
    }
    _acceptedEventTimes[normalizedTag] = timeSeconds;
    _receivedFreshEvent = true;
    _phase = LatencySessionPhase.collectingEvents;
    _firstEventTimer?.cancel();
    _firstEventTimer = null;
    _settleTimer?.cancel();
    final generation = _generation;
    _settleTimer = Timer(uiPolicy.eventSettleDelay, () {
      if (generation != _generation) return;
      _settleCurrent(success: true, reason: 'event_stream_settled');
    });
    return true;
  }

  void cancel() {
    _generation++;
    final wasRunning = isRunning;
    final previousKind = _kind;
    final previousTarget = _targetTag;
    _cancelSessionTimers();
    _phase = LatencySessionPhase.idle;
    _kind = null;
    _targetTag = '';
    _baselineEventTimes = const <String, int>{};
    _acceptedEventTimes.clear();
    final result = _sessionResult;
    _sessionResult = null;
    if (result != null && !result.isCompleted) {
      result.complete(false);
    }
    if (wasRunning) {
      _onSessionChanged(false, previousKind, previousTarget);
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
      // The UI generation is already stale; a late completion cannot revive it.
    }
  }

  void dispose() {
    _disposed = true;
    cancel();
  }

  LatencyTestRequest _groupRequest() => LatencyTestRequest(
    priorityOutboundTag: _activeOutboundTag().trim(),
    url: _testUrl(),
    timeoutMillis: perOutboundTimeoutMillis,
    concurrency: 0,
    deadlineMillis: fullDeadlineMillis,
  );

  Future<bool> _runGroupSession({
    required LatencySessionKind kind,
    required String reason,
  }) {
    if (_disposed ||
        !_isConnected() ||
        !_isForeground() ||
        !_canRunDiagnostics()) {
      return Future<bool>.value(false);
    }
    if (isRunning || _nativeSessionFinished != null) {
      AppLogStore.info(
        'latency',
        'group session skipped reason=$reason phase=${_phase.name} '
            'nativeCommandPending=${_nativeSessionFinished != null}',
      );
      return Future<bool>.value(false);
    }

    final generation = ++_generation;
    _sessionOperationGeneration = _operationGeneration();
    _sessionStartedAtSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _baselineEventTimes = Map<String, int>.from(_eventBaselineTimes());
    _acceptedEventTimes.clear();
    _rpcAccepted = false;
    _receivedFreshEvent = false;
    _phase = LatencySessionPhase.startingRpc;
    _kind = kind;
    _targetTag = '';
    final result = Completer<bool>();
    _sessionResult = result;
    _onSessionChanged(true, kind, '');
    AppLogStore.info(
      'latency',
      'group session start kind=${kind.name} reason=$reason '
          'outbounds=${_outboundCount()} completion='
          '${capabilities.urlTestCompletionModel.name}',
    );

    _watchdogTimer = Timer(uiPolicy.hardWatchdog, () {
      if (generation != _generation) return;
      _settleCurrent(
        success: _rpcAccepted || _receivedFreshEvent,
        reason: 'hard_watchdog',
      );
    });
    unawaited(
      _invokeNativeGroupTest(
        generation: generation,
        kind: kind,
        reason: reason,
        request: _groupRequest(),
      ),
    );
    return result.future;
  }

  Future<void> _invokeNativeGroupTest({
    required int generation,
    required LatencySessionKind kind,
    required String reason,
    required LatencyTestRequest request,
  }) async {
    final nativeFinished = Completer<void>();
    _nativeSessionFinished = nativeFinished;
    late final Future<void> nativeCall;
    try {
      nativeCall = _runTest(request);
    } catch (error, stackTrace) {
      nativeCall = Future<void>.error(error, stackTrace);
    }
    unawaited(
      nativeCall.then<void>(
        (_) => _markNativeFinished(nativeFinished),
        onError: (Object _, StackTrace _) =>
            _markNativeFinished(nativeFinished),
      ),
    );

    try {
      await nativeCall.timeout(uiPolicy.nativeCommandTimeout);
      if (!_isActiveGeneration(generation)) return;
      if (_sessionOperationGeneration != _operationGeneration() ||
          !_isConnected() ||
          !_canRunDiagnostics()) {
        _settleCurrent(success: false, reason: 'stale_runtime');
        return;
      }
      _rpcAccepted = true;
      _phase = LatencySessionPhase.collectingEvents;
      if (_receivedFreshEvent) {
        return;
      }
      _firstEventTimer?.cancel();
      _firstEventTimer = Timer(uiPolicy.firstEventGrace, () {
        if (generation != _generation) return;
        _settleCurrent(success: true, reason: 'first_event_grace');
      });
    } on TimeoutException {
      if (!_isActiveGeneration(generation)) return;
      AppLogStore.warning(
        'latency',
        'native group command timed out kind=${kind.name} reason=$reason '
            'uiTimeoutMs=${uiPolicy.nativeCommandTimeout.inMilliseconds}',
      );
      _settleCurrent(success: false, reason: 'native_command_timeout');
    } catch (error, stackTrace) {
      if (!_isActiveGeneration(generation)) return;
      AppLogStore.warning(
        'latency',
        'native group command failed kind=${kind.name} reason=$reason '
            'error=$error\n$stackTrace',
      );
      _settleCurrent(success: false, reason: 'native_command_error');
    }
  }

  void _markNativeFinished(Completer<void> nativeFinished) {
    if (!nativeFinished.isCompleted) {
      nativeFinished.complete();
    }
    if (identical(_nativeSessionFinished, nativeFinished)) {
      _nativeSessionFinished = null;
    }
  }

  bool _isActiveGeneration(int generation) {
    return !_disposed && generation == _generation && isRunning;
  }

  void _settleCurrent({required bool success, required String reason}) {
    if (!isRunning) return;
    final previousKind = _kind;
    final previousTarget = _targetTag;
    final result = _sessionResult;
    _cancelSessionTimers();
    _phase = LatencySessionPhase.settled;
    _kind = null;
    _targetTag = '';
    _baselineEventTimes = const <String, int>{};
    _acceptedEventTimes.clear();
    _sessionResult = null;
    _onSessionChanged(false, previousKind, previousTarget);
    if (result != null && !result.isCompleted) {
      result.complete(success);
    }
    AppLogStore.info(
      'latency',
      'group session settled kind=${previousKind?.name ?? 'unknown'} '
          'reason=$reason success=$success',
    );
  }

  void _cancelSessionTimers() {
    _firstEventTimer?.cancel();
    _firstEventTimer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }
}
