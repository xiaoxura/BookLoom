import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../errors/app_failure.dart';

/// Result of reclaiming stale import/export scratch directories.
final class JobCacheRecovery {
  const JobCacheRecovery({
    required this.removed,
    required this.active,
    required this.preserved,
    required this.failures,
  });

  final List<String> removed;
  final List<String> active;
  final List<String> preserved;
  final Map<String, String> failures;
}

/// A live scratch directory with a file lock held until [dispose].
final class CachedJob {
  CachedJob._(this._owner, this.directory, this._lockFile, this._handle);

  final JobCache _owner;
  final Directory directory;
  final File _lockFile;
  final RandomAccessFile _handle;
  Future<void>? _disposing;
  bool _handleClosed = false;

  Future<void> dispose() => _disposing ??= _owner._dispose(this);

  Future<void> _release() async {
    if (_handleClosed) return;
    _handleClosed = true;
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
    }
  }
}

/// Manages only `import-*` and `export-*` jobs under an app-owned cache root.
///
/// A coordination lock in the root's parent serializes the short create,
/// recover and dispose transitions across processes. It lives outside [root]
/// so a normally completed `workbench/` directory is empty. Each live job
/// additionally holds its own non-blocking exclusive `.lock` file in [root].
final class JobCache {
  JobCache(Directory root) : root = root.absolute;

  final Directory root;

  static final Logger _logger = Logger('job_cache');
  static final RegExp _jobName = RegExp(r'^(?:import|export)-[A-Za-z0-9_-]+$');
  static final Map<String, Future<void>> _queues = {};
  static final Set<String> _activePaths = {};

  String get _rootKey => p.normalize(root.path);
  File get _guardFile => File(
    p.join(root.parent.path, '.${p.basename(root.path)}.job-cache.guard'),
  );

  /// Creates a private task directory after taking its lease.
  Future<CachedJob> create(String kind) {
    if (kind != 'import' && kind != 'export') {
      throw ArgumentError.value(kind, 'kind', 'Expected import or export');
    }
    return _withGuard(() async {
      final String name = '$kind-${const Uuid().v4()}';
      final Directory directory = Directory(p.join(root.path, name));
      final File lockFile = File(p.join(root.path, '$name.lock'));
      RandomAccessFile? handle;
      bool ownsLockFile = false;
      try {
        await lockFile.create(exclusive: true);
        ownsLockFile = true;
        handle = await lockFile.open(mode: FileMode.append);
        await handle.lock(FileLock.exclusive);
        _activePaths.add(p.normalize(directory.path));
        if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const FileSystemException('Cache task name already exists');
        }
        await directory.create();
        return CachedJob._(this, directory, lockFile, handle);
      } on Object catch (error, stack) {
        _activePaths.remove(p.normalize(directory.path));
        if (handle != null) {
          try {
            await handle.close();
          } on Object {
            // Preserve the original creation error.
          }
        }
        if (ownsLockFile) {
          try {
            if (await lockFile.exists()) await lockFile.delete();
          } on Object {
            // recover() will reclaim a leftover lock without a directory.
          }
        }
        throw StorageFailure(
          '无法建立导入或导出的临时目录。',
          cause: error,
          stackTrace: stack,
        );
      }
    });
  }

  /// Reclaims only jobs whose lease is demonstrably no longer held.
  Future<JobCacheRecovery> recover() => _withGuard(() async {
    final Set<String> candidates = {};
    final List<String> preserved = [];
    await for (final FileSystemEntity entity in root.list(followLinks: false)) {
      final String name = p.basename(entity.path);
      final bool isLock = name.endsWith('.lock');
      final String jobName = isLock
          ? name.substring(0, name.length - '.lock'.length)
          : name;
      if (!_jobName.hasMatch(jobName)) {
        preserved.add(name);
        continue;
      }
      candidates.add(jobName);
    }

    final List<String> removed = [];
    final List<String> active = [];
    final Map<String, String> failures = {};
    for (final String name in candidates) {
      final Directory directory = Directory(p.join(root.path, name));
      final File lockFile = File(p.join(root.path, '$name.lock'));
      if (_activePaths.contains(p.normalize(directory.path))) {
        active.add(name);
        continue;
      }

      RandomAccessFile? handle;
      bool locked = false;
      try {
        final FileSystemEntityType directoryType = await FileSystemEntity.type(
          directory.path,
          followLinks: false,
        );
        final FileSystemEntityType lockType = await FileSystemEntity.type(
          lockFile.path,
          followLinks: false,
        );
        if ((directoryType != FileSystemEntityType.directory &&
                directoryType != FileSystemEntityType.notFound) ||
            (lockType != FileSystemEntityType.file &&
                lockType != FileSystemEntityType.notFound)) {
          preserved.add(name);
          continue;
        }
        if (lockType == FileSystemEntityType.file) {
          handle = await lockFile.open(mode: FileMode.append);
          try {
            await handle.lock(FileLock.exclusive);
            locked = true;
          } on FileSystemException catch (error) {
            if (_isBusy(error)) {
              active.add(name);
              continue;
            }
            rethrow;
          }
        }

        // New jobs create and lock the lease before creating their directory.
        // With the coordination lock held, a directory lacking a lease is an
        // abandoned job; a lease lacking a directory is the other crash window.
        if (directoryType == FileSystemEntityType.directory) {
          await directory.delete(recursive: true);
        }
        if (handle != null) {
          await handle.unlock();
          locked = false;
          await handle.close();
          handle = null;
          await lockFile.delete();
        }
        removed.add(name);
      } on Object catch (error) {
        failures[name] = error.toString();
        preserved.add(name);
        _logger.warning('Cache recovery kept $name (${error.runtimeType})');
      } finally {
        if (handle != null) {
          if (locked) {
            try {
              await handle.unlock();
            } on Object {
              // Closing the handle still releases its OS lock.
            }
          }
          try {
            await handle.close();
          } on Object catch (error) {
            failures[name] = error.toString();
            preserved.add(name);
            _logger.warning('Cache recovery could not close $name: $error');
          }
        }
      }
    }
    return JobCacheRecovery(
      removed: List.unmodifiable(removed),
      active: List.unmodifiable(active),
      preserved: List.unmodifiable(preserved),
      failures: Map.unmodifiable(failures),
    );
  });

  Future<void> _dispose(CachedJob job) async {
    try {
      await _withGuard(() async {
        final FileSystemEntityType directoryType = await FileSystemEntity.type(
          job.directory.path,
          followLinks: false,
        );
        final FileSystemEntityType lockType = await FileSystemEntity.type(
          job._lockFile.path,
          followLinks: false,
        );
        if (directoryType != FileSystemEntityType.directory &&
            directoryType != FileSystemEntityType.notFound) {
          throw const StorageFailure('临时目录已被替换，无法安全清理。');
        }
        if (lockType != FileSystemEntityType.file) {
          throw const StorageFailure('临时任务锁已丢失，无法安全清理。');
        }
        if (directoryType == FileSystemEntityType.directory) {
          await job.directory.delete(recursive: true);
        }
        await job._release();
        await job._lockFile.delete();
      });
    } on AppFailure {
      rethrow;
    } on Object catch (error, stack) {
      throw StorageFailure('无法清理导入或导出的临时文件。', cause: error, stackTrace: stack);
    } finally {
      try {
        await job._release();
      } finally {
        _activePaths.remove(p.normalize(job.directory.path));
      }
    }
  }

  Future<T> _withGuard<T>(Future<T> Function() operation) async {
    final String key = _rootKey;
    final Future<void>? previous = _queues[key];
    final Completer<void> done = Completer<void>();
    _queues[key] = done.future;
    if (previous != null) await previous;

    RandomAccessFile? guard;
    bool locked = false;
    try {
      await _ensureRoot();
      guard = await _openGuard();
      for (int attempt = 0; attempt < 50; attempt++) {
        try {
          await guard.lock(FileLock.exclusive);
          locked = true;
          break;
        } on FileSystemException catch (error) {
          if (!_isBusy(error) || attempt == 49) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      return await operation();
    } finally {
      try {
        if (guard != null) {
          try {
            if (locked) await guard.unlock();
          } finally {
            await guard.close();
          }
        }
      } finally {
        done.complete();
        if (identical(_queues[key], done.future)) await _queues.remove(key);
      }
    }
  }

  Future<void> _ensureRoot() async {
    final FileSystemEntityType type = await FileSystemEntity.type(
      root.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link ||
        (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory)) {
      throw const StorageFailure('临时目录位置不安全，无法继续。');
    }
    if (type == FileSystemEntityType.notFound) {
      await root.create(recursive: true);
    }
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const StorageFailure('临时目录位置不安全，无法继续。');
    }
  }

  Future<RandomAccessFile> _openGuard() async {
    final File guard = _guardFile;
    final FileSystemEntityType type = await FileSystemEntity.type(
      guard.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      try {
        await guard.create(exclusive: true);
      } on FileSystemException {
        // Another process may have created the guard first.
      }
    }
    if (await FileSystemEntity.type(guard.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const StorageFailure('临时任务协调锁不安全，无法继续。');
    }
    return guard.open(mode: FileMode.append);
  }

  static bool _isBusy(FileSystemException error) {
    // EAGAIN/EACCES on Unix, sharing/lock violation on Windows.
    return const [11, 13, 32, 33].contains(error.osError?.errorCode);
  }
}
