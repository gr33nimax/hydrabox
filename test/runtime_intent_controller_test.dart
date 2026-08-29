import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/runtime_intent_controller.dart';

void main() {
  test('manual start generations reject stale asynchronous work', () {
    final controller = RuntimeIntentController();

    final first = controller.beginManualStart();
    controller.markRuntimeDesired();
    expect(controller.isManualStartCurrent(first), isTrue);

    controller.invalidateManualStart();
    expect(controller.isManualStartCurrent(first), isFalse);

    final second = controller.beginManualStart();
    expect(second, greaterThan(first));
    expect(controller.isManualStartCurrent(second), isTrue);

    controller.clearRuntimeDesired();
    expect(controller.isManualStartCurrent(second), isFalse);
  });

  test('queued restart is consumed once after a successful stop', () {
    final controller = RuntimeIntentController()
      ..markRuntimeDesired()
      ..queueStartAfterStop()
      ..beginExplicitStop();

    expect(controller.completeSuccessfulStop(), isTrue);
    expect(controller.completeSuccessfulStop(), isFalse);
  });

  test('explicit stop suppresses an already queued restart', () {
    final controller = RuntimeIntentController()
      ..markRuntimeDesired()
      ..queueStartAfterStop()
      ..suppressQueuedRestart();

    expect(controller.startAfterStopRequested, isFalse);
    expect(controller.completeSuccessfulStop(), isFalse);

    controller.clearQueuedRestartSuppression();
    controller.queueStartAfterStop();
    expect(controller.completeSuccessfulStop(), isTrue);
  });

  test('failed stop restores intent without preserving queued restart', () {
    final controller = RuntimeIntentController()
      ..markRuntimeDesired()
      ..queueStartAfterStop()
      ..beginExplicitStop()
      ..restoreAfterStopFailure();

    expect(controller.desiredByUser, isTrue);
    expect(controller.startAfterStopRequested, isFalse);
    expect(controller.completeSuccessfulStop(), isFalse);
  });

  test('snapshot without desired runtime preserves user intent', () {
    final controller = RuntimeIntentController()..markRuntimeDesired();

    controller.applySnapshot({});

    expect(controller.desiredByUser, isTrue);
  });

  test('desired intent follows the runtime snapshot', () {
    final controller = RuntimeIntentController()..markRuntimeDesired();

    controller.applySnapshot({
      'desiredRuntime': {'wantRunning': true},
    });
    expect(controller.desiredByUser, isTrue);

    controller.applySnapshot({
      'desiredRuntime': {'wantRunning': false},
    });
    expect(controller.desiredByUser, isFalse);
  });
}
