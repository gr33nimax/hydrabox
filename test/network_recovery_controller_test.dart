import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/network_recovery_controller.dart';
import 'package:meow_client/app/runtime_recovery_policy.dart';

void main() {
  NetworkRecoveryController createController() {
    return NetworkRecoveryController(
      interfacePolicy: const RuntimeInterfaceRecoveryPolicy(
        issueWindow: Duration(seconds: 8),
        issueThreshold: 2,
        retriggerCooldown: Duration(seconds: 12),
        decisionDelay: Duration(hours: 1),
      ),
      restartCooldown: const Duration(seconds: 60),
      restartWindow: const Duration(minutes: 10),
      maxRestartsPerWindow: 2,
    );
  }

  test('repeated interface issues are debounced and then rate limited', () {
    final controller = createController();
    final start = DateTime(2026, 7, 29, 12);

    expect(
      controller.registerInterfaceIssue(start).shouldScheduleRecovery,
      isFalse,
    );
    final scheduled = controller.registerInterfaceIssue(
      start.add(const Duration(seconds: 1)),
    );
    expect(scheduled.issueCount, 2);
    expect(scheduled.shouldScheduleRecovery, isTrue);
    expect(
      controller
          .registerInterfaceIssue(start.add(const Duration(seconds: 2)))
          .shouldScheduleRecovery,
      isFalse,
    );
    controller.dispose();
  });

  test('restart budget enforces cooldown and rolling window limit', () {
    final controller = createController();
    final start = DateTime(2026, 7, 29, 12);

    expect(controller.canRestart(start), isTrue);
    controller.recordRestart(start);
    expect(
      controller.canRestart(start.add(const Duration(seconds: 59))),
      isFalse,
    );
    expect(
      controller.canRestart(start.add(const Duration(seconds: 60))),
      isTrue,
    );
    controller.recordRestart(start.add(const Duration(seconds: 60)));
    expect(
      controller.canRestart(start.add(const Duration(seconds: 120))),
      isFalse,
    );
    expect(
      controller.canRestart(start.add(const Duration(minutes: 10, seconds: 1))),
      isTrue,
    );
    controller.dispose();
  });

  test('a newer recovery decision invalidates an older pending decision', () {
    final controller = createController();
    final first = controller.scheduleDecision(
      forceRestartOnDecision: false,
      onReady: (_) {},
    );
    final second = controller.scheduleDecision(
      forceRestartOnDecision: true,
      onReady: (_) {},
    );

    expect(controller.isCurrentDecision(first), isFalse);
    expect(controller.isCurrentDecision(second), isTrue);
    controller.cancelDecision();
    expect(controller.isCurrentDecision(second), isFalse);
    controller.dispose();
  });
}
