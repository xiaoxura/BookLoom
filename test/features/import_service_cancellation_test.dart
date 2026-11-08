import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cancel while defaults load cannot publish a late import preview',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookloom-cancel-',
      );
      final database = AppDatabase.openAt(
        File('${directory.path}/test.sqlite'),
      );
      final repository = BookRepository(database, directory);
      final jobs = BackgroundJobs();
      final entered = Completer<void>();
      final layout = Completer<LayoutOptions>();
      final cache = Directory('${directory.path}/cache');
      final service = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: cache,
        loadDefaultLayout: () {
          entered.complete();
          return layout.future;
        },
      );
      try {
        final pending = service.prepare(
          PickedInput(
            name: '取消.txt',
            size: null,
            openRead: () => Stream.value(utf8.encode('第一章 风\n风吹来了。')),
          ),
        );
        final rejected = expectLater(pending, throwsA(isA<TaskCancelled>()));
        await entered.future;
        service.cancel();
        layout.complete(LayoutOptions());
        await rejected;
        expect(await repository.listSummaries(), isEmpty);
        expect(await cache.list().toList(), isEmpty);
        expect(jobs.isBusy, isFalse);
      } finally {
        jobs.dispose();
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'commit progress follows completed batches and finishes after cleanup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookloom-commit-',
      );
      final database = AppDatabase.openAt(
        File('${directory.path}/test.sqlite'),
      );
      final repository = BookRepository(database, directory);
      final jobs = BackgroundJobs();
      final cache = Directory('${directory.path}/cache');
      final service = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: cache,
      );
      try {
        final content = utf8.encode('第一章 风\n风吹来了。\n第二章 雨\n雨落下了。');
        final prepared = await service.prepare(
          PickedInput(
            name: 'progress.txt',
            size: content.length,
            openRead: () => Stream.value(content),
          ),
        );
        final progress = <JobProgress>[];
        final stored = await service.commit(prepared, onProgress: progress.add);
        expect(await repository.loadBook(stored.id), isNotNull);
        expect(await cache.list().toList(), isEmpty);
        expect(progress.first.stage, 'save_prepare');
        expect(progress.first.fraction, 0);
        expect(progress.last.stage, 'save_finalize');
        expect(progress.last.fraction, 1);
        expect(
          progress.where((item) => item.stage == 'save_chapters'),
          isNotEmpty,
        );
        expect(
          progress.where((item) => item.stage == 'save_blocks'),
          isNotEmpty,
        );
        for (var index = 0; index < progress.length - 1; index++) {
          expect(progress[index].fraction, inInclusiveRange(0, 1));
          expect(progress[index].fraction, lessThan(1));
          expect(
            progress[index + 1].fraction,
            greaterThanOrEqualTo(progress[index].fraction),
          );
        }
        expect(
          progress.every((item) => item.jobId == 0 && item.revision == 0),
          isTrue,
        );
      } finally {
        jobs.dispose();
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
