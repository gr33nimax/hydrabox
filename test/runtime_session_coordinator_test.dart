import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/runtime_lifecycle_controller.dart';
import 'package:hydrabox/app/runtime_session_coordinator.dart';

void main() {
  test('concurrent stop requests share one native operation', () async {
    final coordinator = RuntimeSessionCoordinator();
    final completer = Completer<bool>();
    var stopCalls = 0;
    var suppressionClears = 0;

    Future<bool> stop() {
      stopCalls++;
      return completer.future;
    }

    final first = coordinator.stop(
      activeOrRequested: true,
      allowQueuedRestart: true,
      stopTimeout: const Duration(seconds: 1),
      suppressQueuedRestart: () {},
      clearQueuedRestartSuppression: () => suppressionClears++,
      restoreAfterStopFailure: () {},
      performStop: stop,
    );
    final second = coordinator.stop(
      activeOrRequested: true,
      allowQueuedRestart: true,
      stopTimeout: const Duration(seconds: 1),
      suppressQueuedRestart: () {},
      clearQueuedRestartSuppression: () => suppressionClears++,
      restoreAfterStopFailure: () {},
      performStop: stop,
    );

    expect(identical(first, second), isTrue);
    expect(stopCalls, 1);
    completer.complete(true);
    expect(await first, isTrue);
    expect(suppressionClears, 1);
  });

  test(
    'inactive stop clears restart suppression without native work',
    () async {
      final coordinator = RuntimeSessionCoordinator();
      var suppressed = 0;
      var cleared = 0;
      var stopCalls = 0;

      final result = await coordinator.stop(
        activeOrRequested: false,
        allowQueuedRestart: false,
        stopTimeout: const Duration(seconds: 1),
        suppressQueuedRestart: () => suppressed++,
        clearQueuedRestartSuppression: () => cleared++,
        restoreAfterStopFailure: () {},
        performStop: () async {
          stopCalls++;
          return true;
        },
      );

      expect(result, isTrue);
      expect(suppressed, 1);
      expect(cleared, 1);
      expect(stopCalls, 0);
    },
  );

  test('state event keeps retrying runtime in recovery', () {
    final decision = RuntimeSessionCoordinator().decideStateEvent(
      running: false,
      hasError: true,
      transitionInProgress: false,
      retryScheduled: true,
      starting: false,
      previouslyActive: true,
    );

    expect(decision.clearDisconnectedState, isFalse);
    expect(decision.retryScheduled, isTrue);
  });

  test(
    'a second stop gets the first stop deadline instead of hanging',
    () async {
      final coordinator = RuntimeSessionCoordinator();
      final completer = Completer<bool>();
      var failures = 0;

      final first = coordinator.stop(
        activeOrRequested: true,
        allowQueuedRestart: true,
        stopTimeout: const Duration(milliseconds: 10),
        suppressQueuedRestart: () {},
        clearQueuedRestartSuppression: () {},
        restoreAfterStopFailure: () => failures++,
        performStop: () => completer.future,
      );
      final second = coordinator.stop(
        activeOrRequested: true,
        allowQueuedRestart: true,
        stopTimeout: const Duration(milliseconds: 10),
        suppressQueuedRestart: () {},
        clearQueuedRestartSuppression: () {},
        restoreAfterStopFailure: () => failures++,
        performStop: () => completer.future,
      );

      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(failures, 1);
    },
  );

  test('a stop after its deadline starts a new native operation', () async {
    final coordinator = RuntimeSessionCoordinator();
    final first = Completer<bool>();
    var calls = 0;

    final timedOut = coordinator.stop(
      activeOrRequested: true,
      allowQueuedRestart: true,
      stopTimeout: const Duration(milliseconds: 10),
      suppressQueuedRestart: () {},
      clearQueuedRestartSuppression: () {},
      restoreAfterStopFailure: () {},
      performStop: () {
        calls++;
        return first.future;
      },
    );
    expect(await timedOut, isFalse);

    final next = coordinator.stop(
      activeOrRequested: true,
      allowQueuedRestart: true,
      stopTimeout: const Duration(milliseconds: 10),
      suppressQueuedRestart: () {},
      clearQueuedRestartSuppression: () {},
      restoreAfterStopFailure: () {},
      performStop: () {
        calls++;
        return Future<bool>.value(true);
      },
    );

    expect(await next, isTrue);
    expect(calls, 2);
  });

  test('stable disconnect clears runtime presentation state', () {
    final decision = RuntimeSessionCoordinator().decideStateEvent(
      running: false,
      hasError: false,
      transitionInProgress: false,
      retryScheduled: false,
      starting: false,
      previouslyActive: true,
    );

    expect(decision.clearDisconnectedState, isTrue);
  });

  test('repeated stopped snapshot preserves disconnected probe state', () {
    final decision = RuntimeSessionCoordinator().decideStateEvent(
      running: false,
      hasError: false,
      transitionInProgress: false,
      retryScheduled: false,
      starting: false,
      previouslyActive: false,
    );

    expect(decision.clearDisconnectedState, isFalse);
  });

  test('late successful cancelled start requires native cleanup', () {
    final disposition = RuntimeSessionCoordinator().classifyStartResult(
      result: const RuntimeLifecycleResult.success(
        policy: RuntimeApplyPolicy.fullServiceRestart,
      ),
      manualStartCancelled: true,
      automaticRecoveryCancelled: false,
      runtimeDesiredByUser: false,
    );

    expect(disposition, RuntimeStartDisposition.cancelledNeedsCleanup);
  });
}
