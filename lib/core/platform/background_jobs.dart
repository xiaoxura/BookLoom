import 'dart:async';
import 'dart:isolate';

import 'package:bookloom/core/errors/app_failure.dart';

/// One interruptible computation at a time. Workers never receive UI or DB
/// objects; [input] and [compute] must contain only isolate-sendable data.
class BackgroundJobs {
  _ActiveJob? _active;
  int _nextId = 0;

  bool get isBusy => _active != null;

  Future<R> run<T, R>(
    T input,
    FutureOr<R> Function(T input, void Function(double, String) progress)
    compute, {
    required int revision,
    Duration timeout = const Duration(minutes: 2),
    void Function(JobProgress)? onProgress,
  }) async {
    if (_active != null) {
      throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
    }
    final job = _ActiveJob(++_nextId, revision);
    _active = job;
    final receive = ReceivePort();
    final errors = ReceivePort();
    final result = Completer<R>();
    final stopped = Completer<void>();
    // Spawn itself is asynchronous; cancellation can complete this future
    // before the await below has attached its error handler.
    result.future.ignore();
    final subscriptions = <StreamSubscription<Object?>>[];

    void fail(Object error, [StackTrace? stack]) {
      if (!result.isCompleted) result.completeError(error, stack);
    }

    job.cancel = () => fail(const TaskCancelled());
    subscriptions.add(
      receive.listen((Object? value) {
        if (value == null) {
          if (!stopped.isCompleted) stopped.complete();
          if (!result.isCompleted) fail(const UnexpectedFailure());
          return;
        }
        if (_active != job || result.isCompleted || value is! _WorkerReply) {
          return;
        }
        if (value.jobId != job.id || value.revision != revision) return;
        if (value is _WorkerProgress) {
          onProgress?.call(
            JobProgress(job.id, revision, value.fraction, value.stage),
          );
        } else if (value is _WorkerDone) {
          result.complete(value.value as R);
        } else if (value is _WorkerFailed) {
          fail(value.failure, StackTrace.fromString(value.stack));
        }
      }),
    );
    subscriptions.add(
      errors.listen((Object? error) {
        fail(const UnexpectedFailure());
      }),
    );
    final timer = Timer(timeout, () {
      fail(const TaskTimedOut());
      job.isolate?.kill(priority: Isolate.immediate);
    });
    try {
      job.isolate = await Isolate.spawn(
        _worker<T, R>,
        _WorkerInput<T, R>(receive.sendPort, job.id, revision, input, compute),
        onError: errors.sendPort,
        // Result and exit use the same port so a normal exit cannot overtake
        // the result sent immediately before it.
        onExit: receive.sendPort,
        errorsAreFatal: true,
      );
      // Cancellation may have happened while spawn was pending.
      if (result.isCompleted) job.isolate?.kill(priority: Isolate.immediate);
      return await result.future;
    } finally {
      timer.cancel();
      job.isolate?.kill(priority: Isolate.immediate);
      if (job.isolate != null) {
        // A kill request is asynchronous. Keep ownership until the worker has
        // exited so callers can safely reclaim its open temporary files.
        await stopped.future;
      }
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      receive.close();
      errors.close();
      if (_active == job) _active = null;
    }
  }

  void cancelActive() {
    final job = _active;
    if (job == null) return;
    job.cancel?.call();
    job.isolate?.kill(priority: Isolate.immediate);
  }

  void dispose() => cancelActive();
}

class JobProgress {
  const JobProgress(this.jobId, this.revision, this.fraction, this.stage);
  final int jobId;
  final int revision;
  final double fraction;
  final String stage;
}

class _ActiveJob {
  _ActiveJob(this.id, this.revision);
  final int id;
  final int revision;
  Isolate? isolate;
  void Function()? cancel;
}

class _WorkerInput<T, R> {
  const _WorkerInput(
    this.port,
    this.id,
    this.revision,
    this.input,
    this.compute,
  );
  final SendPort port;
  final int id;
  final int revision;
  final T input;
  final FutureOr<R> Function(T, void Function(double, String)) compute;
}

Future<void> _worker<T, R>(_WorkerInput<T, R> request) async {
  try {
    final result = await request.compute(request.input, (
      double fraction,
      String stage,
    ) {
      request.port.send(
        _WorkerProgress(
          request.id,
          request.revision,
          fraction.clamp(0, 1),
          stage,
        ),
      );
    });
    request.port.send(_WorkerDone(request.id, request.revision, result));
  } on Object catch (error, stack) {
    request.port.send(
      _WorkerFailed(
        request.id,
        request.revision,
        error is AppFailure ? error : const UnexpectedFailure(),
        '$stack',
      ),
    );
  }
}

sealed class _WorkerReply {
  const _WorkerReply(this.jobId, this.revision);
  final int jobId;
  final int revision;
}

class _WorkerProgress extends _WorkerReply {
  const _WorkerProgress(super.jobId, super.revision, this.fraction, this.stage);
  final double fraction;
  final String stage;
}

class _WorkerDone extends _WorkerReply {
  const _WorkerDone(super.jobId, super.revision, this.value);
  final Object? value;
}

class _WorkerFailed extends _WorkerReply {
  const _WorkerFailed(super.jobId, super.revision, this.failure, this.stack);
  final AppFailure failure;
  final String stack;
}
