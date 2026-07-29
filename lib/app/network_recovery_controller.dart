import 'dart:async';
import 'dart:collection';

import 'package:meow_client/app/runtime_recovery_policy.dart';

class NetworkInterfaceIssueDecision {
  const NetworkInterfaceIssueDecision({
    required this.issueCount,
    required this.shouldScheduleRecovery,
  });

  final int issueCount;
  final bool shouldScheduleRecovery;
}

/// Owns the timing and rate limits for recovery after an Android network
/// interface changes or repeated native interface errors are observed.
///
/// Starting/stopping the VPN remains an app-level side effect. Keeping the
/// policy here makes those decisions testable without a Flutter runtime.
class NetworkRecoveryController {
  NetworkRecoveryController({
    this.interfacePolicy = runtimeInterfaceRecoveryPolicy,
    this.restartCooldown = const Duration(seconds: 60),
    this.restartWindow = const Duration(minutes: 10),
    this.maxRestartsPerWindow = 2,
  });

  final RuntimeInterfaceRecoveryPolicy interfacePolicy;
  final Duration restartCooldown;
  final Duration restartWindow;
  final int maxRestartsPerWindow;

  Timer? _decisionTimer;
  int _decisionGeneration = 0;
  DateTime? _lastRestartAt;
  final Queue<DateTime> _restartHistory = Queue<DateTime>();
  DateTime? _lastInterfaceIssueRecoveryAt;
  final Queue<DateTime> _interfaceIssueTimes = Queue<DateTime>();

  int scheduleDecision({
    required bool forceRestartOnDecision,
    required void Function(int generation) onReady,
  }) {
    final generation = ++_decisionGeneration;
    _decisionTimer?.cancel();
    _decisionTimer = null;
    if (forceRestartOnDecision) {
      _decisionTimer = Timer(interfacePolicy.decisionDelay, () {
        _decisionTimer = null;
        if (isCurrentDecision(generation)) {
          onReady(generation);
        }
      });
    }
    return generation;
  }

  bool isCurrentDecision(int generation) => generation == _decisionGeneration;

  void cancelDecision() {
    _decisionGeneration++;
    _decisionTimer?.cancel();
    _decisionTimer = null;
  }

  NetworkInterfaceIssueDecision registerInterfaceIssue(DateTime now) {
    _interfaceIssueTimes.addLast(now);
    _prune(_interfaceIssueTimes, now: now, window: interfacePolicy.issueWindow);
    final issueCount = _interfaceIssueTimes.length;
    final lastRecoveryAt = _lastInterfaceIssueRecoveryAt;
    final shouldScheduleRecovery = interfacePolicy.shouldSchedule(
      issueCount: issueCount,
      elapsedSinceLastRecovery: lastRecoveryAt == null
          ? null
          : now.difference(lastRecoveryAt),
    );
    if (shouldScheduleRecovery) {
      _lastInterfaceIssueRecoveryAt = now;
      _interfaceIssueTimes.clear();
    }
    return NetworkInterfaceIssueDecision(
      issueCount: issueCount,
      shouldScheduleRecovery: shouldScheduleRecovery,
    );
  }

  void clearInterfaceIssueWindow() {
    _interfaceIssueTimes.clear();
    _lastInterfaceIssueRecoveryAt = null;
  }

  bool canRestart(DateTime now) {
    final lastRestartAt = _lastRestartAt;
    if (lastRestartAt != null &&
        now.difference(lastRestartAt) < restartCooldown) {
      return false;
    }
    _prune(_restartHistory, now: now, window: restartWindow);
    return _restartHistory.length < maxRestartsPerWindow;
  }

  void recordRestart(DateTime now) {
    _lastRestartAt = now;
    _restartHistory.addLast(now);
  }

  void dispose() {
    cancelDecision();
    _restartHistory.clear();
    clearInterfaceIssueWindow();
  }

  void _prune(
    Queue<DateTime> values, {
    required DateTime now,
    required Duration window,
  }) {
    while (values.isNotEmpty && now.difference(values.first) > window) {
      values.removeFirst();
    }
  }
}
