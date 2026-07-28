/// Owns user intent around starting and stopping the VPN runtime.
///
/// Native lifecycle work remains in `RuntimeLifecycleController`. Keeping the
/// intent flags here prevents a late start, a queued restart, or a deferred
/// recovery from surviving an explicit user stop by accident.
class RuntimeIntentController {
  bool _desiredByUser = false;
  bool _startAfterStopRequested = false;
  bool _queuedRestartSuppressed = false;
  bool _retryOnResume = false;
  bool _explicitStopInProgress = false;
  int _manualStartGeneration = 0;

  bool get desiredByUser => _desiredByUser;
  bool get startAfterStopRequested => _startAfterStopRequested;
  bool get retryOnResume => _retryOnResume;
  bool get explicitStopInProgress => _explicitStopInProgress;

  int beginManualStart() {
    return ++_manualStartGeneration;
  }

  void markRuntimeDesired() {
    _desiredByUser = true;
  }

  void clearRuntimeDesired() {
    _desiredByUser = false;
  }

  void restoreDesiredFromObservedRuntime() {
    if (!_explicitStopInProgress) {
      _desiredByUser = true;
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
    _explicitStopInProgress = false;
  }

  void beginExplicitStop() {
    _desiredByUser = false;
    _explicitStopInProgress = true;
  }

  bool completeSuccessfulStop() {
    final shouldRestart = !_queuedRestartSuppressed && _startAfterStopRequested;
    _desiredByUser = false;
    _startAfterStopRequested = false;
    _explicitStopInProgress = false;
    return shouldRestart;
  }

  void deferRetryUntilResume() {
    _retryOnResume = true;
  }

  bool consumeRetryOnResume({required bool connected}) {
    final shouldRetry = _retryOnResume && !connected && _desiredByUser;
    _retryOnResume = false;
    return shouldRetry;
  }

  void clearRetryOnResume() {
    _retryOnResume = false;
  }
}
