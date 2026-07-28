import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/runtime_connection_controller.dart';

void main() {
  test('every phase derives a consistent connection snapshot', () {
    final expected = <AppConnectionPhase, (bool, bool, bool)>{
      AppConnectionPhase.idle: (false, false, false),
      AppConnectionPhase.preparing: (false, true, true),
      AppConnectionPhase.configuring: (false, true, true),
      AppConnectionPhase.reconfiguring: (true, true, true),
      AppConnectionPhase.starting: (false, true, true),
      AppConnectionPhase.connected: (true, false, false),
      AppConnectionPhase.stopping: (false, false, true),
      AppConnectionPhase.recovering: (false, true, true),
      AppConnectionPhase.failed: (false, false, false),
    };

    for (final entry in expected.entries) {
      final snapshot = RuntimeConnectionSnapshot.fromPhase(entry.key);
      expect(snapshot.connected, entry.value.$1, reason: entry.key.name);
      expect(snapshot.starting, entry.value.$2, reason: entry.key.name);
      expect(
        snapshot.transitionInProgress,
        entry.value.$3,
        reason: entry.key.name,
      );
    }
  });

  test('reports transition boundaries only when they actually change', () {
    final controller = RuntimeConnectionController();

    final preparing = controller.transitionTo(AppConnectionPhase.preparing);
    expect(preparing.transitionStarted, isTrue);
    expect(preparing.becameConnected, isFalse);

    final starting = controller.transitionTo(AppConnectionPhase.starting);
    expect(starting.transitionStarted, isFalse);
    expect(starting.transitionFinished, isFalse);

    final connected = controller.transitionTo(AppConnectionPhase.connected);
    expect(connected.transitionFinished, isTrue);
    expect(connected.becameConnected, isTrue);

    final reconfiguring = controller.transitionTo(
      AppConnectionPhase.reconfiguring,
    );
    expect(reconfiguring.transitionStarted, isTrue);
    expect(reconfiguring.becameDisconnected, isFalse);

    final reconfigured = controller.transitionTo(AppConnectionPhase.connected);
    expect(reconfigured.transitionFinished, isTrue);
    expect(reconfigured.becameConnected, isFalse);

    final stopping = controller.transitionTo(AppConnectionPhase.stopping);
    expect(stopping.transitionStarted, isTrue);
    expect(stopping.becameDisconnected, isTrue);

    final idle = controller.transitionTo(AppConnectionPhase.idle);
    expect(idle.transitionFinished, isTrue);
    expect(idle.becameDisconnected, isFalse);
  });
}
