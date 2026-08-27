import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/runtime_intent_controller.dart';

void main() {
  test('same-epoch binder reconnect leaves runtime intent unchanged', () {
    final controller = RuntimeIntentController()
      ..applySnapshot({
        'processEpoch': 'epoch-1',
        'desiredRuntime': {'wantRunning': true},
      });

    controller.applySnapshot({
      'processEpoch': 'epoch-1',
      'desiredRuntime': {'wantRunning': true},
    });

    expect(controller.desiredByUser, isTrue);
  });
}
