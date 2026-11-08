import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/import/application/batch_service.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedFiles implements FileService {
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
  }) async => const SaveCancelled();
}

class _RejectingImportService extends ImportService {
  _RejectingImportService({
    required super.repository,
    required super.jobs,
    required super.temporaryDirectory,
  });

  final List<int> consumedBytes = [];

  @override
  Future<PreparedImport> prepare(
    PickedInput input, {
    ParseOptions options = const ParseOptions(),
    void Function(JobProgress)? onProgress,
  }) async {
    var consumed = 0;
    try {
      await for (final chunk in input.openRead()) {
        consumed += chunk.length;
      }
    } finally {
      consumedBytes.add(consumed);
    }
    throw const ImportFailure('synthetic parse rejection');
  }
}

PickedInput _chunkedInput(
  String name,
  int? size,
  Uint8List chunk,
  int chunkCount,
) => PickedInput(
  name: name,
  size: size,
  openRead: () => _repeatChunk(chunk, chunkCount),
);

Stream<List<int>> _repeatChunk(Uint8List chunk, int count) async* {
  for (var index = 0; index < count; index++) {
    yield chunk;
  }
}

void main() {
  late Directory root;
  late AppDatabase database;
  late BookRepository repository;
  late BackgroundJobs jobs;
  late ImportService importer;
  BatchService? batch;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookloom-import-budget-');
    database = AppDatabase.openAt(File('${root.path}/books.sqlite'));
    repository = BookRepository(database, root);
    jobs = BackgroundJobs();
    importer = ImportService(
      repository: repository,
      jobs: jobs,
      temporaryDirectory: Directory('${root.path}/cache'),
    );
    batch = null;
  });

  tearDown(() async {
    final currentBatch = batch;
    if (currentBatch != null) await currentBatch.close();
    jobs.dispose();
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'actual single input limit rejects imports and replacement reparses',
    () async {
      final cache = Directory('${root.path}/cache');
      final oversized = Uint8List(ImportLimits.maxSingleInputBytes + 1);

      for (final declaredSize in <int?>[null, 1]) {
        await expectLater(
          importer.prepare(
            PickedInput(
              name: '越界$declaredSize.txt',
              size: declaredSize,
              openRead: () => Stream<List<int>>.value(oversized),
            ),
          ),
          throwsA(
            isA<ImportFailure>().having(
              (failure) => failure.message,
              'message',
              contains('实际文件大小超过 80 MiB'),
            ),
          ),
        );
        expect(await repository.listSummaries(), isEmpty);
        expect(await cache.list().toList(), isEmpty);
      }

      final sourceBytes = Uint8List.fromList(utf8.encode('第一章 原稿\n原始正文保留。'));
      final prepared = await importer.prepare(
        PickedInput(
          name: '原稿作者甲.txt',
          size: sourceBytes.length,
          openRead: () => Stream<List<int>>.value(sourceBytes),
        ),
      );
      final stored = await importer.commit(prepared);
      final savedBook = (await repository.loadBook(stored.id))!;
      final savedChapter = await repository.loadChapter(
        stored.id,
        savedBook.chapters.firstWhere((chapter) => !chapter.isVolume).id,
      );
      final sourceBefore = (await repository.loadSource(stored.id))!;
      final sourceFile = await repository.resolveSource(sourceBefore);

      await expectLater(
        importer.prepareReparse(
          stored.id,
          options: const ParseOptions(),
          replacementInput: PickedInput(
            name: '超限替换.txt',
            size: 1,
            openRead: () => Stream<List<int>>.value(oversized),
          ),
        ),
        throwsA(
          isA<ImportFailure>().having(
            (failure) => failure.message,
            'message',
            contains('实际文件大小超过 80 MiB'),
          ),
        ),
      );

      final currentBook = (await repository.loadBook(stored.id))!;
      final currentChapter = await repository.loadChapter(
        stored.id,
        savedChapter!.id,
      );
      final sourceAfter = (await repository.loadSource(stored.id))!;
      expect(currentBook.meta.title, savedBook.meta.title);
      expect(currentBook.meta.author, savedBook.meta.author);
      expect(currentBook.revision, savedBook.revision);
      expect(currentChapter!.title, savedChapter.title);
      expect(
        currentChapter.blocks.whereType<TextBlock>().map((block) => block.text),
        savedChapter.blocks.whereType<TextBlock>().map((block) => block.text),
      );
      expect(sourceAfter.id, sourceBefore.id);
      expect(sourceAfter.sha256, sourceBefore.sha256);
      expect(sourceAfter.byteSize, sourceBefore.byteSize);
      expect(sourceAfter.originalName, sourceBefore.originalName);
      expect(await sourceFile.readAsBytes(), sourceBytes);
      expect(await repository.listSummaries(), hasLength(1));
      expect(await cache.list().toList(), isEmpty);
    },
  );

  test(
    'batch total limit counts actual streams and preserves per-item failures',
    () async {
      final chunk = Uint8List(ImportLimits.mebibyte);
      final rejectingImporter = _RejectingImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: Directory('${root.path}/batch-cache'),
      );
      batch = BatchService(
        repository: repository,
        files: _UnusedFiles(),
        jobs: jobs,
        importService: rejectingImporter,
        temporaryDirectory: Directory('${root.path}/batch-cache'),
      );

      await batch!.enqueue([
        _chunkedInput('第一本.txt', 1, chunk, 80),
        _chunkedInput('第二本.txt', null, chunk, 80),
        _chunkedInput('第三本.txt', 0, chunk, 41),
      ], mode: BatchMode.addToLibrary);
      await batch!.start();

      expect(batch!.items.map((item) => item.status), [
        BatchItemStatus.failed,
        BatchItemStatus.failed,
        BatchItemStatus.failed,
      ]);
      expect(batch!.items[0].error, 'synthetic parse rejection');
      expect(batch!.items[1].error, 'synthetic parse rejection');
      expect(batch!.items[2].error, contains('实际输入总量超过 200 MiB'));
      expect(batch!.items.map((item) => item.bookId), everyElement(isNull));
      expect(rejectingImporter.consumedBytes, [
        80 * ImportLimits.mebibyte,
        80 * ImportLimits.mebibyte,
        40 * ImportLimits.mebibyte,
      ]);
      expect(batch!.isRunning, isFalse);
      expect(await repository.listSummaries(), isEmpty);
      expect(await Directory('${root.path}/batch-cache').exists(), isFalse);
    },
  );
}
