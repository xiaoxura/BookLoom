import 'dart:async';
import 'dart:io';

import 'package:bookloom/app/providers.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/settings/workbench_preferences.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/export/application/export_service.dart';
import 'package:bookloom/features/export/application/library_export_service.dart';
import 'package:bookloom/features/import/application/batch_service.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../features/preview/book_cover.dart';
import 'offline_dictionaries.dart';

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => BookRepository(
    ref.watch(databaseProvider),
    ref.watch(appPathsProvider).support,
  ),
);

final backgroundJobsProvider = Provider<BackgroundJobs>((ref) {
  final jobs = BackgroundJobs();
  ref.onDispose(jobs.dispose);
  return jobs;
});

final fileServiceProvider = Provider<FileService>((ref) => NativeFileService());

final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(
    loadDictionaries: loadOfflineDictionaries,
    loadDefaultLayout: () async =>
        (await WorkbenchPreferences.read(ref.read(settingsStoreProvider)))
            .layout,
    repository: ref.watch(bookRepositoryProvider),
    jobs: ref.watch(backgroundJobsProvider),
    temporaryDirectory: Directory(
      p.join(ref.watch(appPathsProvider).cache.path, 'workbench'),
    ),
  ),
);

final libraryBooksProvider = StreamProvider<List<BookSummary>>(
  (ref) => ref.watch(bookRepositoryProvider).watchSummaries(),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(
    renderTemplateCover: BookCoverRenderer.renderJpeg,
    repository: ref.watch(bookRepositoryProvider),
    files: ref.watch(fileServiceProvider),
    jobs: ref.watch(backgroundJobsProvider),
    temporaryDirectory: Directory(
      p.join(ref.watch(appPathsProvider).cache.path, 'workbench'),
    ),
  ),
);

final batchServiceProvider = Provider<BatchService>((ref) {
  final service = BatchService(
    repository: ref.watch(bookRepositoryProvider),
    files: ref.watch(fileServiceProvider),
    jobs: ref.watch(backgroundJobsProvider),
    importService: ref.watch(importServiceProvider),
    temporaryDirectory: Directory(
      p.join(ref.watch(appPathsProvider).cache.path, 'workbench'),
    ),
    renderTemplateCover: BookCoverRenderer.renderJpeg,
  );
  ref.onDispose(() => unawaited(service.shutdown()));
  return service;
});

final libraryExportServiceProvider = Provider<LibraryExportService>((ref) {
  final service = LibraryExportService(
    exportService: ref.watch(exportServiceProvider),
    files: ref.watch(fileServiceProvider),
    jobs: ref.watch(backgroundJobsProvider),
    temporaryDirectory: Directory(
      p.join(ref.watch(appPathsProvider).cache.path, 'workbench'),
    ),
  );
  ref.onDispose(() => unawaited(service.shutdown()));
  return service;
});
