import 'dart:async';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:flutter_test/flutter_test.dart';

int _count(int value, void Function(double, String) progress) {
  progress(0.5, 'count');
  return value + 1;
}

int _loop(int value, void Function(double, String) progress) {
  progress(0, 'loop');
  while (true) {
    value++;
  }
}

void main() {
  test('result and progress preserve input revision', () async {
    final jobs = BackgroundJobs();
    final progress = <JobProgress>[];
    expect(await jobs.run(4, _count, revision: 7, onProgress: progress.add), 5);
    expect(progress.single.revision, 7);
    expect(jobs.isBusy, isFalse);
  });

  test(
    'timeout kills a computation that never returns and permits new work',
    () async {
      final jobs = BackgroundJobs();
      await expectLater(
        jobs.run(
          0,
          _loop,
          revision: 0,
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TaskTimedOut>()),
      );
      expect(await jobs.run(1, _count, revision: 1), 2);
    },
  );

  test(
    'cancel interrupts active computation without accepting a late result',
    () async {
      final jobs = BackgroundJobs();
      final started = Completer<void>();
      final future = jobs.run(
        0,
        _loop,
        revision: 0,
        onProgress: (_) {
          if (!started.isCompleted) started.complete();
        },
      );
      final expectation = expectLater(future, throwsA(isA<TaskCancelled>()));
      await started.future;
      await expectLater(
        jobs.run(1, _count, revision: 0),
        throwsA(isA<ValidationFailure>()),
      );
      jobs.cancelActive();
      await expectation;
      expect(await jobs.run(2, _count, revision: 2), 3);
    },
  );
}
