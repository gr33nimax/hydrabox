import 'package:hydrabox/app/runtime_connection_controller.dart';

AppConnectionPhase runtimeSnapshotPhase(
  Map<String, dynamic> snapshot, {
  required AppConnectionPhase currentPhase,
}) {
  return switch (snapshot['state']) {
    'RUNTIME_STATE_UNKNOWN' => currentPhase,
    'RUNTIME_STATE_PREPARING' => AppConnectionPhase.preparing,
    'RUNTIME_STATE_STARTING' => AppConnectionPhase.starting,
    'RUNTIME_STATE_RUNNING' => AppConnectionPhase.connected,
    'RUNTIME_STATE_RECOVERING' => AppConnectionPhase.recovering,
    'RUNTIME_STATE_FAILED' => AppConnectionPhase.failed,
    _ => AppConnectionPhase.idle,
  };
}
