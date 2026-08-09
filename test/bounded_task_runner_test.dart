import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/bounded_task_runner.dart';

void main() {
  test('limits concurrency and preserves result order', () async {
    var active = 0;
    var maxActive = 0;
    final progress = <int>[];
    final tasks = List.generate(7, (index) {
      return () async {
        active++;
        maxActive = max(maxActive, active);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        if (index == 3) throw StateError('failed');
        return index;
      };
    });

    final results = await runBoundedTasks<int>(
      tasks,
      concurrency: 2,
      onSettled: (completed, _) => progress.add(completed),
    );

    expect(maxActive, 2);
    expect(results, hasLength(7));
    expect((results[0] as BoundedTaskSuccess<int>).value, 0);
    expect(results[3], isA<BoundedTaskFailure<int>>());
    expect((results[6] as BoundedTaskSuccess<int>).value, 6);
    expect(progress, <int>[1, 2, 3, 4, 5, 6, 7]);
  });

  test('rejects a non-positive concurrency value', () async {
    await expectLater(
      runBoundedTasks<int>([() async => 1], concurrency: 0),
      throwsArgumentError,
    );
  });
}
