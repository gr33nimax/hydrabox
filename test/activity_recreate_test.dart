import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/runtime_connection_controller.dart';
import 'package:hydrabox/app/runtime_snapshot_reducer.dart';

void main() {
  test('activity recreation restores the runtime phase from its snapshot only', () {
    var commands = 0;
    final restored = runtimeSnapshotPhase(
      <String, dynamic>{'state': 'RUNTIME_STATE_RUNNING'},
      currentPhase: AppConnectionPhase.idle,
    );

    expect(restored, AppConnectionPhase.connected);
    expect(commands, 0);
  });
}
