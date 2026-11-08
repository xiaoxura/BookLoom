import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/import/application/batch_service.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Files implements FileService {
  _Files(this.destination);

  final File destination;
  bool cancelSave = false;
  int saveCalls = 0;

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
    saveCalls++;
    if (cancelSave) return const SaveCancelled();
    await prepared.copy(destination.path);
    return SaveSaved(destination.uri);
  }
}

class _DelayedCommitImportService extends ImportService {
  _DelayedCommitImportService({
    required super.repository,
    required super.jobs,
    required super.temporaryDirectory,
    required this.entered,
    required this.release,
  });

  final Completer<void> entered;
  final Completer<void> release;

  @override
  Future<Book> commit(
    PreparedImport prepared, {
    void Function(JobProgress)? onProgress,
  }) async {
    entered.complete();
    await release.future;
    return super.commit(prepared, onProgress: onProgress);
  }
}

PickedInput _txt(String name, {String body = '第一章 开始\n一段正文。'}) {
  final bytes = utf8.encode(body);
  return PickedInput(
    name: name,
    size: bytes.length,
    openRead: () => Stream.value(bytes),
  );
}

void main() {
  late Directory root;
  late AppDatabase database;
  late BookRepository repository;
  late BackgroundJobs jobs;
  late ImportService importer;
  late _Files files;
  late BatchService batch;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookloom-batch-');
    database = AppDatabase.openAt(File('${root.path}/test.sqlite'));
    repository = BookRepository(database, root);
    jobs = BackgroundJobs();
    importer = ImportService(
      repository: repository,
      jobs: jobs,
      temporaryDirectory: Directory('${root.path}/workbench'),
    );
    files = _Files(File('${root.path}/saved.zip'));
    batch = BatchService(
      repository: repository,
      files: files,
      jobs: jobs,
      importService: importer,
      temporaryDirectory: Directory('${root.path}/workbench'),
    );
  });

  tearDown(() async {
    await batch.close();
    jobs.dispose();
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'rejects count, per-file and aggregate limits before changing queue',
    () async {
      final small = _txt('小书.txt');
      await expectLater(
        batch.enqueue(
          List.filled(ImportLimits.maxBatchInputs + 1, small),
          mode: BatchMode.addToLibrary,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        batch.enqueue([
          PickedInput(
            name: '过大.txt',
            size: ImportLimits.maxSingleInputBytes + 1,
            openRead: () => const Stream.empty(),
          ),
        ], mode: BatchMode.addToLibrary),
        throwsA(isA<ImportFailure>()),
      );
      await expectLater(
        batch.enqueue([
          for (var i = 0; i < 3; i++)
            PickedInput(
              name: '$i.txt',
              size: 70 * ImportLimits.mebibyte,
              openRead: () => const Stream.empty(),
            ),
        ], mode: BatchMode.addToLibrary),
        throwsA(isA<ValidationFailure>()),
      );
      expect(batch.items, isEmpty);
    },
  );

  test(
    'queue freezes nested rule lists and rejects custom without a rule',
    () async {
      final drops = <String>['广告条'];
      final spec = <String, Object?>{'name': '固定规则', 'drop': drops};
      await batch.enqueue(
        [_txt('规则.txt', body: '第一章 开始\n保留正文。\n广告条')],
        mode: BatchMode.addToLibrary,
        options: ParseOptions(ruleSpec: spec),
      );
      drops.add('保留正文');
      spec['drop'] = <String>['保留正文'];
      await batch.start();
      expect(batch.items.single.status, BatchItemStatus.success);
      final book = (await repository.loadBook(batch.items.single.bookId!))!;
      final chapters = await Future.wait([
        for (final chapter in book.chapters)
          repository.loadChapter(book.id, chapter.id),
      ]);
      expect(
        chapters
            .expand((chapter) => chapter!.blocks)
            .map((block) => block.plainText)
            .join('\n'),
        contains('保留正文'),
      );
      await expectLater(
        batch.enqueue(
          [_txt('无规则.txt')],
          mode: BatchMode.addToLibrary,
          options: const ParseOptions(rulePreset: 'custom'),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test(
    'replacing and shutting down a queue release only retired inputs',
    () async {
      var firstReleases = 0;
      var secondReleases = 0;
      final first = PickedInput(
        name: '第一本.txt',
        size: 0,
        openRead: () => const Stream.empty(),
        onRelease: () async => firstReleases++,
      );
      final second = PickedInput(
        name: '第二本.txt',
        size: 0,
        openRead: () => const Stream.empty(),
        onRelease: () async => secondReleases++,
      );
      await batch.enqueue([first], mode: BatchMode.addToLibrary);
      expect(firstReleases, 0);
      await batch.enqueue([first, second], mode: BatchMode.addToLibrary);
      expect(firstReleases, 0);
      expect(secondReleases, 0);
      await batch.enqueue([second], mode: BatchMode.addToLibrary);
      expect(firstReleases, 1);
      expect(secondReleases, 0);
      await batch.shutdown();
      expect(firstReleases, 1);
      expect(secondReleases, 1);
      await batch.shutdown();
      expect(secondReleases, 1);
    },
  );

  test(
    'one failure does not stop library queue and retry skips committed books',
    () async {
      var failedReads = 0;
      var successfulReads = 0;
      final flaky = PickedInput(
        name: '稍后重试.txt',
        size: null,
        openRead: () {
          failedReads++;
          return failedReads == 1
              ? Stream<List<int>>.error(const FileSystemException('temporary'))
              : Stream.value(utf8.encode('第一章 重试\n后来成功了。'));
        },
      );
      final good = PickedInput(
        name: '正常.txt',
        size: null,
        openRead: () {
          successfulReads++;
          return Stream.value(utf8.encode('第一章 正常\n已经保存。'));
        },
      );
      await batch.enqueue([flaky, good], mode: BatchMode.addToLibrary);
      await batch.start();
      expect(batch.items.map((item) => item.status), [
        BatchItemStatus.failed,
        BatchItemStatus.success,
      ]);
      expect((await repository.listSummaries()).length, 1);
      await batch.retryFailed();
      expect(batch.items.map((item) => item.status), [
        BatchItemStatus.success,
        BatchItemStatus.success,
      ]);
      expect(failedReads, 2);
      expect(successfulReads, 1);
      expect((await repository.listSummaries()).length, 2);
    },
  );

  test('conversion leaves shelf empty and ZIP contains unique successes and manifest', () async {
    await batch.enqueue(
      [
        _txt('同名.txt'),
        _txt('同名.txt'),
        PickedInput(
          name: '损坏.txt',
          size: null,
          openRead: () =>
              Stream<List<int>>.error(const FileSystemException('broken')),
        ),
      ],
      mode: BatchMode.convertFiles,
      format: ExportFormat.txt,
    );
    await batch.start();
    expect(batch.items.map((item) => item.status), [
      BatchItemStatus.success,
      BatchItemStatus.success,
      BatchItemStatus.failed,
    ]);
    expect(await repository.listSummaries(), isEmpty);
    final first = batch.items[0].outputName;
    final second = batch.items[1].outputName;
    expect(first, isNot(second));
    expect(first, endsWith('.txt'));
    expect(second, endsWith('.txt'));

    files.cancelSave = true;
    expect(await batch.saveZip(), isA<SaveCancelled>());
    expect(files.destination.existsSync(), isFalse);
    files.cancelSave = false;
    expect(await batch.saveZip(), isA<SaveSaved>());
    final archive = ZipDecoder().decodeBytes(
      await files.destination.readAsBytes(),
    );
    final names = archive.map((entry) => entry.name).toSet();
    expect(names, containsAll([first, second, 'result-manifest.json']));
    expect(names.length, 3);
    final manifest = jsonDecode(
      utf8.decode(
        archive
            .firstWhere((entry) => entry.name == 'result-manifest.json')
            .content,
      ),
    ) as Map<String, dynamic>;
    final results = manifest['results'] as List<dynamic>;
    expect((results[2] as Map<String, dynamic>)['status'], 'failed');
    expect((results[2] as Map<String, dynamic>)['output'], isNull);
    expect(await repository.listSummaries(), isEmpty);
  });

  test(
    'cancellation marks active and remaining items without later rebound',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final slow = PickedInput(
        name: '等待.txt',
        size: null,
        openRead: () async* {
          entered.complete();
          await release.future;
          yield utf8.encode('第一章 等待\n正文。');
        },
      );
      await batch.enqueue([
        slow,
        _txt('下一本.txt'),
      ], mode: BatchMode.addToLibrary);
      final running = batch.start();
      await entered.future;
      expect(batch.items.first.status, BatchItemStatus.processing);
      final closing = batch.shutdown();
      release.complete();
      await running;
      await closing;
      expect(batch.items.map((item) => item.status), [
        BatchItemStatus.cancelled,
        BatchItemStatus.cancelled,
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(
        batch.items.every((item) => item.status == BatchItemStatus.cancelled),
        isTrue,
      );
      expect(await repository.listSummaries(), isEmpty);
      expect(
        await Directory('${root.path}/workbench').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'cancelling during commit finishes current book and skips the rest',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      importer = _DelayedCommitImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: Directory('${root.path}/workbench'),
        entered: entered,
        release: release,
      );
      await batch.close();
      batch = BatchService(
        repository: repository,
        files: files,
        jobs: jobs,
        importService: importer,
        temporaryDirectory: Directory('${root.path}/workbench'),
      );
      await batch.enqueue([
        _txt('当前.txt'),
        _txt('剩余.txt'),
      ], mode: BatchMode.addToLibrary);
      final running = batch.start();
      await entered.future;
      expect(batch.isCommitting, isTrue);
      batch.cancel();
      release.complete();
      await running;
      expect(batch.items.map((item) => item.status), [
        BatchItemStatus.success,
        BatchItemStatus.cancelled,
      ]);
      expect((await repository.listSummaries()).length, 1);
    },
  );

  test(
    'failed conversion discards prepared input and keeps shelf empty',
    () async {
      await batch.close();
      batch = BatchService(
        repository: repository,
        files: files,
        jobs: jobs,
        importService: importer,
        temporaryDirectory: Directory('${root.path}/workbench'),
        renderTemplateCover: (_) async => throw StateError('render failed'),
      );
      await batch.enqueue([_txt('封面失败.txt')], mode: BatchMode.convertFiles);
      await batch.start();
      expect(batch.items.single.status, BatchItemStatus.failed);
      expect(await repository.listSummaries(), isEmpty);
      final leftovers = await Directory('${root.path}/workbench')
          .list()
          .toList();
      expect(
        leftovers.every(
          (entity) => !entity.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('import-'),
        ),
        isTrue,
      );
    },
  );
}
