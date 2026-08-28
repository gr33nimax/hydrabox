import 'package:hydrabox/app/runtime_connection_controller.dart';
import 'package:hydrabox/app/runtime_lifecycle_controller.dart';

enum RuntimeStartDisposition {
  success,
  failed,
  cancelled,
  cancelledNeedsCleanup,
}

class RuntimeStateDecision {
  const RuntimeStateDecision({
    required this.phase,
    required this.keepConnecting,
    required this.clearDisconnectedState,
    required this.retryScheduled,
  });

  final AppConnectionPhase phase;
  final bool keepConnecting;
  final bool clearDisconnectedState;
  final bool retryScheduled;
}

/// Coordinates root-level runtime operations that must have a single owner.
///
/// Native lifecycle work remains in [RuntimeLifecycleController]. This class
/// deduplicates stop requests and turns native/event state into deterministic
/// UI decisions without depending on a widget.
class RuntimeSessionCoordinator {
  Future<bool>? _stopInFlight;

  Future<bool> stop({
    required bool activeOrRequested,
    required bool allowQueuedRestart,
    required void Function() suppressQueuedRestart,
    required void Function() clearQueuedRestartSuppression,
    required Future<bool> Function() performStop,
  }) {
    if (!allowQueuedRestart) {
      suppressQueuedRestart();
    }
    final inFlight = _stopInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    if (!activeOrRequested) {
      clearQueuedRestartSuppression();
      return Future<bool>.value(true);
    }

    late final Future<bool> operation;
    operation = Future<bool>.sync(performStop).whenComplete(() {
      if (identical(_stopInFlight, operation)) {
        _stopInFlight = null;
        clearQueuedRestartSuppression();
      }
    });
    _stopInFlight = operation;
    return operation;
  }

  RuntimeStartDisposition classifyStartResult({
    required RuntimeLifecycleResult result,
    required bool manualStartCancelled,
    required bool automaticRecoveryCancelled,
    required bool runtimeDesiredByUser,
  }) {
    if (manualStartCancelled || automaticRecoveryCancelled) {
      return result.success && !runtimeDesiredByUser
          ? RuntimeStartDisposition.cancelledNeedsCleanup
          : RuntimeStartDisposition.cancelled;
    }
    return result.success
        ? RuntimeStartDisposition.success
        : RuntimeStartDisposition.failed;
  }

  RuntimeStateDecision decideStateEvent({
    required bool running,
    required bool hasError,
    required bool transitionInProgress,
    required bool retryScheduled,
    required bool starting,
    required bool previouslyActive,
  }) {
    final keepStateDuringError =
        hasError && (transitionInProgress || retryScheduled || starting);
    final keepConnecting =
        !running &&
        (!hasError || keepStateDuringError) &&
        (transitionInProgress || retryScheduled || starting);
    final phase = switch ((running, hasError, keepStateDuringError)) {
      (true, _, _) => AppConnectionPhase.connected,
      (false, true, true) => AppConnectionPhase.recovering,
      (false, true, false) => AppConnectionPhase.failed,
      (false, false, _) when keepConnecting && retryScheduled =>
        AppConnectionPhase.recovering,
      (false, false, _) when keepConnecting => AppConnectionPhase.starting,
      _ => AppConnectionPhase.idle,
    };
    return RuntimeStateDecision(
      phase: phase,
      keepConnecting: keepConnecting,
      // Runtime snapshots are level-triggered. A stopped snapshot can be
      // emitted after an unrelated command (for example an ephemeral probe),
      // so only tear down runtime-owned presentation state on an actual
      // active/transitioning -> stopped edge.
      clearDisconnectedState: !running && !keepConnecting && previouslyActive,
      retryScheduled: phase == AppConnectionPhase.recovering && retryScheduled,
    );
  }

}
