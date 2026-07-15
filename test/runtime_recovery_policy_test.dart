import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/runtime_recovery_policy.dart';

void main() {
  group('runtime interface recovery', () {
    test('waits for a burst of confirmed interface errors', () {
      expect(
        runtimeInterfaceRecoveryPolicy.shouldSchedule(
          issueCount: runtimeInterfaceRecoveryPolicy.issueThreshold - 1,
          elapsedSinceLastRecovery: null,
        ),
        isFalse,
      );
      expect(
        runtimeInterfaceRecoveryPolicy.shouldSchedule(
          issueCount: runtimeInterfaceRecoveryPolicy.issueThreshold,
          elapsedSinceLastRecovery: null,
        ),
        isTrue,
      );
    });

    test('debounces decisions without an artificial long outage', () {
      expect(
        runtimeInterfaceRecoveryPolicy.shouldSchedule(
          issueCount: runtimeInterfaceRecoveryPolicy.issueThreshold,
          elapsedSinceLastRecovery:
              runtimeInterfaceRecoveryPolicy.retriggerCooldown -
              const Duration(milliseconds: 1),
        ),
        isFalse,
      );
      expect(
        runtimeInterfaceRecoveryPolicy.shouldSchedule(
          issueCount: runtimeInterfaceRecoveryPolicy.issueThreshold,
          elapsedSinceLastRecovery:
              runtimeInterfaceRecoveryPolicy.retriggerCooldown,
        ),
        isTrue,
      );
      expect(
        runtimeInterfaceRecoveryPolicy.decisionDelay,
        lessThan(runtimeInterfaceRecoveryPolicy.issueWindow),
      );
    });
  });

  test('fresh intent from a dead process does not show recovery', () {
    expect(
      nativeRuntimeRecoveryPending(
        running: false,
        recordedServiceAlive: false,
        activeRuntimeOwner: false,
        runtimeIntentFresh: true,
      ),
      isFalse,
    );
  });

  test('a live recorded service is recovery evidence', () {
    expect(
      nativeRuntimeRecoveryPending(
        running: false,
        recordedServiceAlive: true,
        activeRuntimeOwner: false,
        runtimeIntentFresh: true,
      ),
      isTrue,
    );
  });

  test('running runtime is connected instead of recovering', () {
    expect(
      nativeRuntimeRecoveryPending(
        running: true,
        recordedServiceAlive: true,
        activeRuntimeOwner: true,
        runtimeIntentFresh: true,
      ),
      isFalse,
    );
  });
}
