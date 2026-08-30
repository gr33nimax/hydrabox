import 'package:hydrabox/app/runtime_connection_controller.dart';

enum RuntimeToggleAction { start, stop, queueStartAfterStop }

RuntimeToggleAction runtimeToggleAction(
  Map<String, dynamic>? snapshot, {
  required AppConnectionPhase localPhase,
}) {
  return switch (snapshot?['state']) {
    'RUNTIME_STATE_STOPPING' => RuntimeToggleAction.queueStartAfterStop,
    'RUNTIME_STATE_RUNNING' ||
    'RUNTIME_STATE_STARTING' ||
    'RUNTIME_STATE_RECOVERING' => RuntimeToggleAction.stop,
    _ => switch (localPhase) {
      AppConnectionPhase.preparing ||
      AppConnectionPhase.configuring => RuntimeToggleAction.stop,
      _ => RuntimeToggleAction.start,
    },
  };
}

AppConnectionPhase runtimeSnapshotPhase(
  Map<String, dynamic> snapshot, {
  required AppConnectionPhase currentPhase,
}) {
  return switch (snapshot['state']) {
    'RUNTIME_STATE_UNKNOWN' => currentPhase,
    'RUNTIME_STATE_PREPARING' => AppConnectionPhase.preparing,
    'RUNTIME_STATE_STARTING' => AppConnectionPhase.starting,
    'RUNTIME_STATE_RUNNING' => AppConnectionPhase.connected,
    'RUNTIME_STATE_STOPPING' => AppConnectionPhase.stopping,
    'RUNTIME_STATE_RECOVERING' => AppConnectionPhase.recovering,
    'RUNTIME_STATE_FAILED' => AppConnectionPhase.failed,
    _ => AppConnectionPhase.idle,
  };
}
