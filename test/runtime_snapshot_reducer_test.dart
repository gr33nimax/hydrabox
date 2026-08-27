import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/runtime_connection_controller.dart';
import 'package:hydrabox/app/runtime_snapshot_reducer.dart';

void main() {
  test('maps every runtime snapshot state to the UI phase', () {
    final cases = <String, AppConnectionPhase>{
      'RUNTIME_STATE_STOPPED': AppConnectionPhase.idle,
      'RUNTIME_STATE_PREPARING': AppConnectionPhase.preparing,
      'RUNTIME_STATE_STARTING': AppConnectionPhase.starting,
      'RUNTIME_STATE_RUNNING': AppConnectionPhase.connected,
      'RUNTIME_STATE_RECOVERING': AppConnectionPhase.recovering,
      'RUNTIME_STATE_FAILED': AppConnectionPhase.failed,
    };

    for (final entry in cases.entries) {
      expect(
        runtimeSnapshotPhase(<String, dynamic>{'state': entry.key}),
        entry.value,
      );
    }
  });

  test('stopped state wins over a contradictory legacy running value', () {
    expect(
      runtimeSnapshotPhase(<String, dynamic>{
        'running': true,
        'state': 'RUNTIME_STATE_STOPPED',
      }),
      AppConnectionPhase.idle,
    );
  });
}
