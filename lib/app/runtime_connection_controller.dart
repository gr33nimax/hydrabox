enum AppConnectionPhase {
  idle,
  preparing,
  configuring,
  reconfiguring,
  starting,
  connected,
  stopping,
  recovering,
  failed,
}

class RuntimeConnectionSnapshot {
  const RuntimeConnectionSnapshot._({
    required this.phase,
    required this.connected,
    required this.starting,
    required this.transitionInProgress,
  });

  const RuntimeConnectionSnapshot.idle()
    : this._(
        phase: AppConnectionPhase.idle,
        connected: false,
        starting: false,
        transitionInProgress: false,
      );

  factory RuntimeConnectionSnapshot.fromPhase(AppConnectionPhase phase) {
    return RuntimeConnectionSnapshot._(
      phase: phase,
      connected:
          phase == AppConnectionPhase.connected ||
          phase == AppConnectionPhase.reconfiguring,
      starting: switch (phase) {
        AppConnectionPhase.preparing ||
        AppConnectionPhase.configuring ||
        AppConnectionPhase.reconfiguring ||
        AppConnectionPhase.starting ||
        AppConnectionPhase.recovering => true,
        _ => false,
      },
      transitionInProgress: switch (phase) {
        AppConnectionPhase.preparing ||
        AppConnectionPhase.configuring ||
        AppConnectionPhase.reconfiguring ||
        AppConnectionPhase.starting ||
        AppConnectionPhase.stopping ||
        AppConnectionPhase.recovering => true,
        _ => false,
      },
    );
  }

  final AppConnectionPhase phase;
  final bool connected;
  final bool starting;
  final bool transitionInProgress;
}

class RuntimeConnectionTransition {
  const RuntimeConnectionTransition({
    required this.previous,
    required this.current,
  });

  final RuntimeConnectionSnapshot previous;
  final RuntimeConnectionSnapshot current;

  bool get becameConnected => current.connected && !previous.connected;
  bool get becameDisconnected => !current.connected && previous.connected;
  bool get transitionStarted =>
      current.transitionInProgress && !previous.transitionInProgress;
  bool get transitionFinished =>
      !current.transitionInProgress && previous.transitionInProgress;
}

/// Owns the UI-facing VPN connection phase and all values derived from it.
///
/// Native start/stop work remains in [RuntimeLifecycleController]. This class
/// prevents the root widget from independently mutating several booleans that
/// must always describe the same lifecycle phase.
class RuntimeConnectionController {
  RuntimeConnectionSnapshot _snapshot = const RuntimeConnectionSnapshot.idle();

  RuntimeConnectionSnapshot get snapshot => _snapshot;
  AppConnectionPhase get phase => _snapshot.phase;
  bool get connected => _snapshot.connected;
  bool get starting => _snapshot.starting;
  bool get transitionInProgress => _snapshot.transitionInProgress;

  RuntimeConnectionTransition transitionTo(AppConnectionPhase phase) {
    final previous = _snapshot;
    final current = RuntimeConnectionSnapshot.fromPhase(phase);
    _snapshot = current;
    return RuntimeConnectionTransition(previous: previous, current: current);
  }
}
