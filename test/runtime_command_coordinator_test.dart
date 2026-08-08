import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/runtime_command_coordinator.dart';

void main() {
  test('selector is issued once when its RPC times out', () async {
    var calls = 0;
    final coordinator = RuntimeCommandCoordinator(
      selectionTimeout: const Duration(milliseconds: 10),
      selectOutbound: (_, _) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
    );

    final result = await coordinator.selectOutbound('vless-1');

    expect(result.status, RuntimeSelectionStatus.failed);
    expect(result.error, isA<TimeoutException>());
    expect(calls, 1);
  });

  test('late result cannot confirm an older selection', () async {
    final first = Completer<void>();
    final coordinator = RuntimeCommandCoordinator(
      selectOutbound: (_, tag) =>
          tag == 'first' ? first.future : Future<void>.value(),
    );

    final firstResultFuture = coordinator.selectOutbound('first');
    final secondResult = await coordinator.selectOutbound('second');
    first.complete();
    final firstResult = await firstResultFuture;

    expect(secondResult.status, RuntimeSelectionStatus.applied);
    expect(firstResult.status, RuntimeSelectionStatus.stale);
  });
}
