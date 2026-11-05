import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/export/application/export_service.dart';
import 'package:bookloom/features/export/application/library_export_service.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Files implements FileService {
  _Files(this.destination);

  final File destination;
  bool cancelSave = false;
  Completer<void>? saveEntered;
  Completer<void>? saveRelease;

  @override
  Future<void> clearTemporaryFiles() async {}

  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const ['txt', 'epub', 'docx'],
  }) async => [];

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) async {
    saveEntered?.complete();
    if (saveRelease != null) await saveRelease!.future;
    if (cancelSave) return const SaveCancelled();
    await prepared.copy(destination.path);
    return SaveSaved(destination.uri);
  }
}

class _CountingExportService extends ExportService {
  _CountingExportService({
    required super.repository,
    required super.files,
    required super.jobs,
    required super.temporaryDirectory,
  });

  final Map<String, int> calls = {};
  final Set<String> failOnce = {};

  @override
  Future<T> withPreparedExport<T>(
    String bookId, {
    ExportFormat format = ExportFormat.epub3,
    void Function(JobProgress)? onProgress,
    required Future<T> Function(
      File file, {
      required String suggestedName,
      required String mimeType,
    })
    submit,
  }) {
    calls[bookId] = (calls[bookId] ?? 0) + 1;
    if (failOnce.remove(bookId)) {
      return Future<T>.error(const ExportFailure('模拟单本导出失败。'));
    }
    return super.withPreparedExport<T>(
      bookId,
      format: format,
      onProgress: onProgress,
      submit: submit,
    );
  }
}

void main() {
  late Directory root;
  late AppDatabase database;
  late BookRepository repository;
  late BackgroundJobs jobs;
  late _Files files;
  late _CountingExportService exporter;
  late LibraryExportService batch;

  Future<String> createBook(String name, String body) async {
    final importer = ImportService(
      repository: repository,
      jobs: jobs,
      temporaryDirectory: Directory('${root.path}/workbench'),
    );
    final bytes = utf8.encode(body);
    final prepared = await importer.prepare(
      PickedInput(
        name: name,
        size: bytes.length,
        openRead: () => Stream.value(bytes),
      ),
    );
    return (await importer.commit(prepared)).id;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookloom-library-export-');
    database = AppDatabase.openAt(File('${root.path}/test.sqlite'));
    repository = BookRepository(database, root);
    jobs = BackgroundJobs();
    files = _Files(File('${root.path}/saved.zip'));
    exporter = _CountingExportService(
      repository: repository,
      files: files,
      jobs: jobs,
      temporaryDirectory: Directory('${root.path}/workbench'),
    );
    batch = LibraryExportService(
      exportService: exporter,
      files: files,
      jobs: jobs,
      temporaryDirectory: Directory('${root.path}/workbench'),
    );
  });

  tearDown(() async {
    await batch.shutdown();
    jobs.dispose();
    await database.close();
    await root.delete(recursive: true);
  });

  test('40-book queue limit rejects before replacing selection', () async {
    await expectLater(
      batch.enqueue([
        for (var i = 0; i <= ImportLimits.maxBatchInputs; i++) '$i',
      ]),
      throwsA(isA<ValidationFailure>()),
    );
    expect(batch.items, isEmpty);
  });

  test(
    'partial results use current books and ZIP contains successes only',
    () async {
      final first = await createBook('同名.txt', '第一章 一\n第一本当前正文。');
      final second = await createBook('同名.txt', '第一章 二\n第二本当前正文。');
      const missing = '00000000-0000-4000-8000-000000000000';
      await batch.enqueue([first, missing, second], format: ExportFormat.txt);
      await batch.start();
      expect(batch.items.map((item) => item.status), [
        LibraryExportStatus.success,
        LibraryExportStatus.failed,
        LibraryExportStatus.success,
      ]);
      expect((await repository.listSummaries()).length, 2);
      final firstName = batch.items[0].outputName;
      final secondName = batch.items[2].outputName;
      expect(firstName, isNot(secondName));
      files.cancelSave = true;
      expect(await batch.saveZip(), isA<SaveCancelled>());
      expect(files.destination.existsSync(), isFalse);
      files.cancelSave = false;
      expect(await batch.saveZip(), isA<SaveSaved>());
      final archive = ZipDecoder().decodeBytes(
        await files.destination.readAsBytes(),
      );
      final entries = {for (final entry in archive) entry.name: entry};
      expect(
        entries.keys,
        containsAll([firstName, secondName, 'result-manifest.json']),
      );
      expect(entries.length, 3);
      expect(utf8.decode(entries[firstName]!.content), contains('第一本当前正文'));
      expect(utf8.decode(entries[secondName]!.content), contains('第二本当前正文'));
      final manifest = jsonDecode(
        utf8.decode(entries['result-manifest.json']!.content),
      ) as Map<String, dynamic>;
      final results = manifest['results'] as List<dynamic>;
      expect((results[1] as Map<String, dynamic>)['status'], 'failed');
      expect((results[1] as Map<String, dynamic>)['output'], isNull);
      expect((await repository.listSummaries()).length, 2);
    },
  );

  test('retryFailed does not regenerate already successful books', () async {
    final first = await createBook('先失败.txt', '第一章 一\n一段正文。');
    final second = await createBook('始终成功.txt', '第一章 二\n另一段正文。');
    exporter.failOnce.add(first);
    await batch.enqueue([first, second], format: ExportFormat.txt);
    await batch.start();
    expect(batch.items.map((item) => item.status), [
      LibraryExportStatus.failed,
      LibraryExportStatus.success,
    ]);
    await batch.retryFailed();
    expect(batch.items.map((item) => item.status), [
      LibraryExportStatus.success,
      LibraryExportStatus.success,
    ]);
    expect(exporter.calls[first], 2);
    expect(exporter.calls[second], 1);
    expect((await repository.listSummaries()).length, 2);
  });

  test('shutdown waits for native save and retains accurate outcome', () async {
    final id = await createBook('待保存.txt', '第一章 一\n待保存内容。');
    await batch.enqueue([id], format: ExportFormat.txt);
    await batch.start();
    files.saveEntered = Completer<void>();
    files.saveRelease = Completer<void>();
    final saving = batch.saveZip();
    await files.saveEntered!.future;
    expect(batch.isCommitting, isTrue);
    final closing = batch.shutdown();
    files.saveRelease!.complete();
    expect(await saving, isA<SaveSaved>());
    await closing;
    expect(batch.items.single.status, LibraryExportStatus.success);
    expect(await Directory('${root.path}/workbench').list().toList(), isEmpty);
  });
}
