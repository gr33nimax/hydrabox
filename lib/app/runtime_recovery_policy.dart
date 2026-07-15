class RuntimeInterfaceRecoveryPolicy {
  const RuntimeInterfaceRecoveryPolicy({
    this.issueWindow = const Duration(seconds: 8),
    this.issueThreshold = 4,
    this.retriggerCooldown = const Duration(seconds: 12),
    this.decisionDelay = const Duration(seconds: 2),
  });

  final Duration issueWindow;
  final int issueThreshold;
  final Duration retriggerCooldown;
  final Duration decisionDelay;

  bool shouldSchedule({
    required int issueCount,
    required Duration? elapsedSinceLastRecovery,
  }) {
    if (issueCount < issueThreshold) {
      return false;
    }
    return elapsedSinceLastRecovery == null ||
        elapsedSinceLastRecovery >= retriggerCooldown;
  }
}

const runtimeInterfaceRecoveryPolicy = RuntimeInterfaceRecoveryPolicy();

bool nativeRuntimeRecoveryPending({
  required bool running,
  required bool recordedServiceAlive,
  required bool activeRuntimeOwner,
  required bool runtimeIntentFresh,
}) {
  if (running) {
    return false;
  }

  // A runtime-intent is only a short-lived hint for Android's START_STICKY
  // restoration. By itself it does not prove that a service exists or starts.
  return recordedServiceAlive || activeRuntimeOwner;
}
