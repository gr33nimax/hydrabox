import 'dart:async';
import 'dart:math';

sealed class BoundedTaskResult<T> {
  const BoundedTaskResult();
}

final class BoundedTaskSuccess<T> extends BoundedTaskResult<T> {
  const BoundedTaskSuccess(this.value);

  final T value;
}

final class BoundedTaskFailure<T> extends BoundedTaskResult<T> {
  const BoundedTaskFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

/// Runs asynchronous tasks with a fixed upper bound on concurrent work.
///
/// Results keep the same order as [tasks]. A failed task is captured in its
/// result and does not prevent the remaining tasks from running.
Future<List<BoundedTaskResult<T>>> runBoundedTasks<T>(
  List<Future<T> Function()> tasks, {
  required int concurrency,
  void Function(int completed, int total)? onSettled,
}) async {
  if (tasks.isEmpty) {
    return <BoundedTaskResult<T>>[];
  }
  if (concurrency < 1) {
    throw ArgumentError.value(concurrency, 'concurrency', 'must be positive');
  }

  final results = List<BoundedTaskResult<T>?>.filled(tasks.length, null);
  final workerCount = min(concurrency, tasks.length);
  var nextIndex = 0;
  var completed = 0;

  Future<void> worker() async {
    while (true) {
      final index = nextIndex++;
      if (index >= tasks.length) {
        return;
      }
      try {
        results[index] = BoundedTaskSuccess<T>(await tasks[index]());
      } catch (error, stackTrace) {
        results[index] = BoundedTaskFailure<T>(error, stackTrace);
      } finally {
        completed++;
        onSettled?.call(completed, tasks.length);
      }
    }
  }

  await Future.wait(List<Future<void>>.generate(workerCount, (_) => worker()));
  return results.cast<BoundedTaskResult<T>>();
}
