import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/group_url_test_scheduler.dart';

void main() {
  group('runtime startup URLTest gate', () {
    test('runs once for each normal native generation', () {
      final gate = RuntimeStartupUrlTestGate();

      expect(gate.decide(1), RuntimeStartupUrlTestDecision.run);
      expect(gate.decide(1), RuntimeStartupUrlTestDecision.ignore);
      expect(gate.decide(2), RuntimeStartupUrlTestDecision.run);
    });

    test('skips only the generation created by network recovery', () {
      final gate = RuntimeStartupUrlTestGate();

      expect(gate.decide(7), RuntimeStartupUrlTestDecision.run);
      gate.markRecoveryRestart(currentGeneration: 7);
      expect(gate.decide(7), RuntimeStartupUrlTestDecision.ignore);
      expect(gate.decide(8), RuntimeStartupUrlTestDecision.skipAfterRecovery);
      expect(gate.decide(9), RuntimeStartupUrlTestDecision.run);
    });

    test('explicit disconnect clears a pending recovery suppression', () {
      final gate = RuntimeStartupUrlTestGate();

      expect(gate.decide(3), RuntimeStartupUrlTestDecision.run);
      gate.markRecoveryRestart(currentGeneration: 3);
      gate.reset();
      expect(gate.decide(4), RuntimeStartupUrlTestDecision.run);
    });
  });

  test('latest automatic URLTest replaces the previous timer', () async {
    final scheduler = GroupUrlTestScheduler();
    addTearDown(scheduler.dispose);
    final calls = <String>[];

    scheduler.schedule(
      delay: const Duration(milliseconds: 30),
      canRun: () => true,
      run: () async {
        calls.add('first');
        return true;
      },
    );
    scheduler.schedule(
      delay: const Duration(milliseconds: 10),
      canRun: () => true,
      run: () async {
        calls.add('second');
        return true;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, const <String>['second']);
    expect(scheduler.isScheduled, isFalse);
  });

  test('cancelled or no-longer-ready check is never queued', () async {
    final scheduler = GroupUrlTestScheduler();
    addTearDown(scheduler.dispose);
    var ready = false;
    var calls = 0;

    scheduler.schedule(
      delay: Duration.zero,
      canRun: () => ready,
      run: () async {
        calls++;
        return true;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);

    ready = true;
    scheduler.schedule(
      delay: const Duration(milliseconds: 20),
      canRun: () => ready,
      run: () async {
        calls++;
        return true;
      },
    );
    scheduler.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(calls, 0);
  });
}
