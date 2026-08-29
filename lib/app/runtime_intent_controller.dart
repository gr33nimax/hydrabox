/// Owns user intent around starting and stopping the VPN runtime.
///
/// Native lifecycle work remains in `RuntimeLifecycleController`. Keeping the
/// intent flags here prevents a late start, a queued restart, or a deferred
/// recovery from surviving an explicit user stop by accident.
class RuntimeIntentController {
  bool _desiredByUser = false;
  bool _startAfterStopRequested = false;
  bool _queuedRestartSuppressed = false;
  int _manualStartGeneration = 0;

  bool get desiredByUser => _desiredByUser;
  bool get startAfterStopRequested => _startAfterStopRequested;

  int beginManualStart() {
    return ++_manualStartGeneration;
  }

  void markRuntimeDesired() {
    _desiredByUser = true;
  }

  void clearRuntimeDesired() {
    _desiredByUser = false;
  }

  void applySnapshot(Map<String, dynamic> snapshot) {
    final desired = snapshot['desiredRuntime'];
    if (desired is Map) {
      _desiredByUser = desired['wantRunning'] == true;
    }
  }

  bool isManualStartCurrent(int generation) {
    return _desiredByUser && generation == _manualStartGeneration;
  }

  void invalidateManualStart() {
    _manualStartGeneration++;
  }

  void queueStartAfterStop() {
    _startAfterStopRequested = true;
  }

  void suppressQueuedRestart() {
    _startAfterStopRequested = false;
    _queuedRestartSuppressed = true;
  }

  void clearQueuedRestartSuppression() {
    _queuedRestartSuppressed = false;
  }

  void restoreAfterStopFailure() {
    _desiredByUser = true;
    _startAfterStopRequested = false;
  }

  void beginExplicitStop({bool discardQueuedStart = false}) {
    _desiredByUser = false;
    if (discardQueuedStart) {
      _startAfterStopRequested = false;
    }
  }

  bool completeSuccessfulStop() {
    final shouldRestart = !_queuedRestartSuppressed && _startAfterStopRequested;
    _desiredByUser = false;
    _startAfterStopRequested = false;
    return shouldRestart;
  }
}
