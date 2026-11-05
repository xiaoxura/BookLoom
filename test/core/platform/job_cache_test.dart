import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/platform/job_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory root;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('bookloom-cache-test-');
    root = Directory(p.join(sandbox.path, 'workbench'));
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('completed task removes its directory and lease', () async {
    final JobCache cache = JobCache(root);
    final CachedJob job = await cache.create('import');
    await File(p.join(job.directory.path, 'source.txt')).writeAsString('稿件');
    expect(await File('${job.directory.path}.lock').exists(), isTrue);

    await job.dispose();
    await job.dispose();
    expect(await root.list().toList(), isEmpty);
  });

  test(
    'recovery removes both crash windows but preserves active jobs',
    () async {
      await root.create();
      final Directory orphanDirectory = Directory(
        p.join(root.path, 'import-old'),
      );
      await orphanDirectory.create();
      await File(p.join(orphanDirectory.path, 'source.txt'))
          .writeAsString('old');
      final File orphanLock = File(p.join(root.path, 'export-old.lock'));
      await orphanLock.create();

      final CachedJob liveImport = await JobCache(root).create('import');
      final CachedJob liveExport = await JobCache(root).create('export');
      try {
        final JobCacheRecovery report = await JobCache(root).recover();
        expect(report.removed, containsAll(['import-old', 'export-old']));
        expect(
          report.active,
          containsAll([
            p.basename(liveImport.directory.path),
            p.basename(liveExport.directory.path),
          ]),
        );
        expect(report.failures, isEmpty);
        expect(await orphanDirectory.exists(), isFalse);
        expect(await orphanLock.exists(), isFalse);
        expect(await liveImport.directory.exists(), isTrue);
        expect(await liveExport.directory.exists(), isTrue);
      } finally {
        await liveImport.dispose();
        await liveExport.dispose();
      }
      expect(await root.list().toList(), isEmpty);
    },
  );

  test('unknown entries and matching symlinks are never reclaimed', () async {
    await root.create();
    final Directory external = Directory(p.join(sandbox.path, 'external'));
    await external.create();
    final File sentinel = File(p.join(external.path, 'keep.txt'));
    await sentinel.writeAsString('keep');
    final Link namedDirectory = Link(p.join(root.path, 'import-link'));
    final Link namedLock = Link(p.join(root.path, 'export-link.lock'));
    await namedDirectory.create(external.path);
    await namedLock.create(sentinel.path);
    final Directory unknown = Directory(p.join(root.path, 'other-data'));
    await unknown.create();
    final File unknownFile = File(p.join(root.path, 'notes.txt'));
    await unknownFile.writeAsString('leave');
    final Directory orphan = Directory(p.join(root.path, 'import-orphan'));
    await orphan.create();

    final JobCacheRecovery report = await JobCache(root).recover();
    expect(report.removed, contains('import-orphan'));
    expect(
      report.preserved,
      containsAll(['import-link', 'export-link', 'other-data', 'notes.txt']),
    );
    expect(await namedDirectory.exists(), isTrue);
    expect(await namedLock.exists(), isTrue);
    expect(await sentinel.readAsString(), 'keep');
    expect(await unknown.exists(), isTrue);
    expect(await unknownFile.exists(), isTrue);
    expect(await orphan.exists(), isFalse);
  }, skip: !Platform.isLinux);

  test('a symlink cache root is refused', () async {
    final Directory outside = Directory(p.join(sandbox.path, 'outside'));
    await outside.create();
    await Link(root.path).create(outside.path);
    expect(JobCache(root).create('import'), throwsA(isA<StorageFailure>()));
    expect(await outside.exists(), isTrue);
  }, skip: !Platform.isLinux);

  test('a different process holding the lease keeps its task', () async {
    await root.create();
    final Directory externalJob = Directory(
      p.join(root.path, 'export-external'),
    );
    await externalJob.create();
    final File lease = File('${externalJob.path}.lock');
    await lease.create();
    final Process holder = await Process.start('python3', [
      '-u',
      '-c',
      'import fcntl,sys\n'
          'f=open(sys.argv[1],"a+")\n'
          'fcntl.lockf(f,fcntl.LOCK_EX)\n'
          'print("ready",flush=True)\n'
          'sys.stdin.readline()\n',
      lease.path,
    ]);
    try {
      final String ready = await holder.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 3));
      expect(ready, 'ready');
      final JobCacheRecovery report = await JobCache(root).recover();
      expect(report.active, contains('export-external'));
      expect(await externalJob.exists(), isTrue);
      expect(await lease.exists(), isTrue);
    } finally {
      holder.stdin.writeln('stop');
      await holder.stdin.close();
      await holder.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          holder.kill();
          return holder.exitCode;
        },
      );
    }
    final JobCacheRecovery afterExit = await JobCache(root).recover();
    expect(afterExit.removed, contains('export-external'));
  }, skip: !Platform.isLinux);
}
