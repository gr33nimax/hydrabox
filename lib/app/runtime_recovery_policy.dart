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
