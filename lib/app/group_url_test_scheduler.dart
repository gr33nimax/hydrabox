import 'dart:async';

typedef GroupUrlTestReadiness = bool Function();
typedef GroupUrlTestAction = Future<bool> Function();

enum RuntimeStartupUrlTestDecision { ignore, run, skipAfterRecovery }

/// Decides whether a newly ready native runtime should receive an automatic
/// startup URLTest.
///
/// A recovery restart already competes with real application traffic while the
/// network stack is stabilizing. Its first ready generation is therefore
/// consumed without starting a selector-wide probe. A later normal generation
/// is allowed again.
class RuntimeStartupUrlTestGate {
  int _lastHandledGeneration = 0;
  int? _recoveryBaselineGeneration;

  void markRecoveryRestart({required int currentGeneration}) {
    _recoveryBaselineGeneration = currentGeneration;
  }

  RuntimeStartupUrlTestDecision decide(int nativeRuntimeGeneration) {
    if (nativeRuntimeGeneration <= 0 ||
        nativeRuntimeGeneration == _lastHandledGeneration) {
      return RuntimeStartupUrlTestDecision.ignore;
    }
    _lastHandledGeneration = nativeRuntimeGeneration;
    final recoveryBaseline = _recoveryBaselineGeneration;
    if (recoveryBaseline != null &&
        nativeRuntimeGeneration != recoveryBaseline) {
      _recoveryBaselineGeneration = null;
      return RuntimeStartupUrlTestDecision.skipAfterRecovery;
    }
    return RuntimeStartupUrlTestDecision.run;
  }

  void reset() {
    _lastHandledGeneration = 0;
    _recoveryBaselineGeneration = null;
  }
}

/// Owns the single debounced automatic URLTest slot.
///
/// Manual checks bypass this scheduler. A later automatic reason replaces an
/// earlier one, and a check that is no longer safe at fire time is discarded
/// instead of being queued behind the current native command.
class GroupUrlTestScheduler {
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  bool get isScheduled => _timer?.isActive ?? false;

  void schedule({
    required Duration delay,
    required GroupUrlTestReadiness canRun,
    required GroupUrlTestAction run,
  }) {
    if (_disposed) return;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      if (_disposed || generation != _generation || !canRun()) {
        return;
      }
      unawaited(run());
    });
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
