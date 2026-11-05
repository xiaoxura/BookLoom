import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/epub/epub_validator.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/io/safe_zip_archive.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/export/application/export_service.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

class _Files implements FileService {
  _Files(this.target, {this.cancel = false});
  final File target;
  final bool cancel;

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) async {
    if (cancel) return const SaveCancelled();
    await prepared.copy(target.path);
    return SaveSaved(target.uri);
  }

  @override
  Future<void> clearTemporaryFiles() async {}

  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const ['txt', 'epub', 'docx'],
  }) async => [];
}

void main() {
  late Directory directory;
  late AppDatabase database;
  late BookRepository repository;
  late BackgroundJobs jobs;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bookloom-roundtrip-');
    database = AppDatabase.openAt(File('${directory.path}/test.sqlite'));
    repository = BookRepository(database, directory);
    jobs = BackgroundJobs();
  });
  tearDown(() async {
    jobs.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'TXT to native edit, disk restart, and validated EPUB uses saved edits',
    () async {
      const text = '第一卷 海风\n第一章 清晨\n门边放着一封信。\n\n小船已经离港。\n第二章 返航\n灯又亮了。';
      final source = File('${directory.path}/source.txt');
      await source.writeAsString(text);
      final service = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: Directory('${directory.path}/cache'),
      );
      final prepared = await service.prepare(
        PickedInput(
          name: '《海风》作者：林澈.txt',
          size: await source.length(),
          openRead: source.openRead,
        ),
      );
      expect(await repository.listSummaries(), isEmpty);
      final stored = await service.commit(prepared);
      expect(await source.readAsString(), text);
      var session = EditorSession(repository: repository);
      await session.open(stored.id);
      final chapter = session.book!.chapters.firstWhere(
        (item) => !item.isVolume,
      );
      await session.selectChapter(chapter.id);
      session.editChapterTitle(chapter.id, '第一章 新的清晨');
      final block = session.activeChapter!.blocks.whereType<TextBlock>().first;
      session.editBlockText(block.id, '这段正文已经重新校对。');
      session.editBookMeta(session.book!.meta.copyWith(title: '海风修订稿'));
      final splitBlock = session.activeChapter!.blocks
          .whereType<TextBlock>()
          .last;
      await session.splitAtParagraph(chapter.id, splitBlock.id);
      final countAfterSplit = session.book!.chapters.length;
      await session.undo();
      expect(session.book!.chapters.length, countAfterSplit - 1);
      await session.redo();
      await session.close();

      await database.close();
      database = AppDatabase.openAt(File('${directory.path}/test.sqlite'));
      repository = BookRepository(database, directory);
      session = EditorSession(repository: repository);
      await session.open(stored.id, chapterId: chapter.id);
      expect(session.book!.meta.title, '海风修订稿');
      expect(session.activeChapter!.title, '第一章 新的清晨');
      expect(session.activeChapter!.blocks.first.plainText, '这段正文已经重新校对。');
      expect(session.book!.chapters.length, countAfterSplit);
      final output = File('${directory.path}/海风.epub');
      final export = ExportService(
        repository: repository,
        files: _Files(output),
        jobs: jobs,
        temporaryDirectory: Directory('${directory.path}/cache'),
      );
      expect(await export.exportBook(stored.id), isA<SaveSaved>());
      validateEpub(output.path);
      final zip = SafeZipArchive.open(
        output.path,
        limits: const ImportLimits(),
      );
      try {
        final body = zip.entries
            .where((entry) => entry.name.endsWith('.xhtml'))
            .map((entry) => zip.readXml(entry.name).innerText)
            .join();
        expect(body, contains('这段正文已经重新校对。'));
        expect(body, contains('第一章 新的清晨'));
      } finally {
        zip.close();
      }
      expect(await source.readAsString(), text);
      expect(
        await Directory('${directory.path}/cache').list().toList(),
        isEmpty,
      );
      await session.close();
    },
  );

  test(
    'failed source read and discarded preparation create no shelf entries',
    () async {
      final service = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: Directory('${directory.path}/cache'),
      );
      await expectLater(
        service.prepare(
          PickedInput(
            name: '坏文件.txt',
            size: null,
            openRead: () =>
                Stream<List<int>>.error(const FileSystemException('denied')),
          ),
        ),
        throwsA(isA<ImportFailure>()),
      );
      await expectLater(
        service.prepare(
          PickedInput(
            name: '错误编码.txt',
            size: 4,
            openRead: () => Stream.value([0xef, 0xbb, 0xbf, 0xff]),
          ),
        ),
        throwsA(
          isA<ImportFailure>().having(
            (error) => error.message,
            'encoding guidance',
            contains('编码'),
          ),
        ),
      );
      final prepared = await service.prepare(
        PickedInput(
          name: '可取消.txt',
          size: null,
          openRead: () => Stream.value(utf8.encode('第一章 风\n风吹来了。')),
        ),
      );
      await service.discard(prepared);
      expect(await repository.listSummaries(), isEmpty);
      expect(
        await Directory('${directory.path}/cache').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'save dialog cancellation preserves book and removes private export',
    () async {
      final service = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: Directory('${directory.path}/cache'),
      );
      final prepared = await service.prepare(
        PickedInput(
          name: '雨.txt',
          size: null,
          openRead: () => Stream.value(utf8.encode('第一章 雨\n雨停了。')),
        ),
      );
      final book = await service.commit(prepared);
      final output = File('${directory.path}/cancelled.epub');
      final export = ExportService(
        repository: repository,
        files: _Files(output, cancel: true),
        jobs: jobs,
        temporaryDirectory: Directory('${directory.path}/cache'),
      );
      expect(await export.exportBook(book.id), isA<SaveCancelled>());
      expect(await output.exists(), isFalse);
      expect(await repository.loadBook(book.id), isNotNull);
      expect(
        await Directory('${directory.path}/cache').list().toList(),
        isEmpty,
      );
    },
  );

  test('export bounds actual asset bytes and rejects changed hashes', () async {
    final service = ImportService(
      repository: repository,
      jobs: jobs,
      temporaryDirectory: Directory('${directory.path}/cache'),
    );
    final prepared = await service.prepare(
      PickedInput(
        name: '资源.txt',
        size: null,
        openRead: () => Stream.value(utf8.encode('第一章 灯\n灯亮了。')),
      ),
    );
    final book = await service.commit(prepared);
    final asset = await repository.addAsset(
      book.id,
      AssetImport(
        kind: 'font',
        mime: 'font/ttf',
        extension: 'ttf',
        openRead: () => Stream.value([0, 1, 0, 0]),
      ),
    );
    await repository.saveBook(
      book.copyWith(
        layout: book.layout.copyWith(embeddedFontAssetId: asset.id),
      ),
      expectedRevision: book.revision,
      dirtyChapterIds: {},
    );
    final resource = File('${directory.path}/${asset.storedPath}');
    final export = ExportService(
      repository: repository,
      files: _Files(File('${directory.path}/changed.epub')),
      jobs: jobs,
      temporaryDirectory: Directory('${directory.path}/cache'),
    );
    final handle = await resource.open(mode: FileMode.writeOnly);
    await handle.truncate(ImportLimits.maxFontBytes + 1);
    await handle.close();
    await expectLater(
      export.exportBook(book.id),
      throwsA(
        isA<ExportFailure>().having(
          (error) => error.message,
          'size reason',
          contains('资源大小'),
        ),
      ),
    );
    await resource.writeAsBytes([0, 1, 0, 1]);
    await expectLater(
      export.exportBook(book.id),
      throwsA(
        isA<ExportFailure>().having(
          (error) => error.message,
          'hash reason',
          contains('资源内容'),
        ),
      ),
    );
    expect(await Directory('${directory.path}/cache').list().toList(), isEmpty);
  });

  test(
    'committed import remains successful when cache cleanup is deferred',
    () async {
      final cache = Directory('${directory.path}/cache');
      final service = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: cache,
      );
      PickedInput input() => PickedInput(
        name: '缓存.txt',
        size: null,
        openRead: () => Stream.value(utf8.encode('第一章 灯\n灯亮了。')),
      );
      final prepared = await service.prepare(input());
      final lease = (await cache.list().toList()).whereType<File>().singleWhere(
        (file) => file.path.endsWith('.lock'),
      );
      await lease.delete();
      final book = await service.commit(prepared);
      expect(await repository.loadBook(book.id), isNotNull);
      final next = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: cache,
      );
      final retry = await next.prepare(input());
      await next.discard(retry);
      expect(await cache.list().toList(), isEmpty);
    },
    skip: Platform.isWindows ? 'Windows forbids unlinking a held lease' : false,
  );

  test(
    'missing source accepts matching bytes without applying prepared chapters',
    () async {
      const String originalName = '原稿作者甲.txt';
      const String originalText = '第一章 原稿\n原始正文保留。\n第二章 终章\n原始结尾。';
      final List<int> sourceBytes = utf8.encode(originalText);
      final Directory cache = Directory('${directory.path}/reparse-cache');
      final ImportService service = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: cache,
      );
      final PreparedImport initial = await service.prepare(
        _pickedText(originalName, sourceBytes),
      );
      final book = await service.commit(initial);
      await _editStoredBook(
        repository,
        book.id,
        title: '用户维护的书名',
        author: '用户作者',
        body: '用户手工校订的正文。',
      );

      final savedBook = (await repository.loadBook(book.id))!;
      final savedChapter = (await repository.loadChapter(
        book.id,
        savedBook.chapters.firstWhere((chapter) => !chapter.isVolume).id,
      ))!;
      final sourceBefore = (await repository.loadSource(book.id))!;
      expect(sourceBefore.originalName, originalName);
      final originalFile = await repository.resolveSource(sourceBefore);
      await originalFile.delete();

      final PreparedImport replacement = await service.prepareReparse(
        book.id,
        options: const ParseOptions(),
        replacementInput: _pickedText('临时选择名.txt', sourceBytes),
      );
      try {
        expect(replacement.isReparse, isTrue);
        expect(replacement.bookId, book.id);
        expect(replacement.originalName, '临时选择名.txt');

        final sourceAfter = (await repository.loadSource(book.id))!;
        expect(sourceAfter.id, sourceBefore.id);
        expect(sourceAfter.storedPath, sourceBefore.storedPath);
        expect(sourceAfter.sha256, sourceBefore.sha256);
        expect(sourceAfter.byteSize, sourceBefore.byteSize);
        expect(sourceAfter.originalName, originalName);
        expect(await originalFile.readAsBytes(), sourceBytes);

        final currentBook = (await repository.loadBook(book.id))!;
        expect(currentBook.meta.title, savedBook.meta.title);
        expect(currentBook.meta.author, savedBook.meta.author);
        expect(currentBook.revision, savedBook.revision);
        final currentChapter = (await repository.loadChapter(
          book.id,
          savedChapter.id,
        ))!;
        expect(currentChapter.title, savedChapter.title);
        expect(
          currentChapter.blocks.whereType<TextBlock>().first.text,
          '用户手工校订的正文。',
        );
        expect(await repository.listSummaries(), hasLength(1));
      } finally {
        await service.discard(replacement);
      }

      // The reattachment survives a database reopen with the same durable
      // source identity and the user-edited book remains the current version.
      await database.close();
      database = AppDatabase.openAt(File('${directory.path}/test.sqlite'));
      repository = BookRepository(database, directory);
      final durableSource = (await repository.loadSource(book.id))!;
      expect(durableSource.id, sourceBefore.id);
      expect(durableSource.storedPath, sourceBefore.storedPath);
      expect(durableSource.sha256, sourceBefore.sha256);
      expect(durableSource.originalName, originalName);
      final durableFile = await repository.resolveSource(durableSource);
      expect(await durableFile.readAsBytes(), sourceBytes);

      await durableFile.delete();
      final mismatchedBytes = utf8.encode('第一章 改写\n这不是原始来源。');
      final mismatchService = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: cache,
      );
      await expectLater(
        mismatchService.prepareReparse(
          book.id,
          options: const ParseOptions(),
          replacementInput: _pickedText('错误替换.txt', mismatchedBytes),
        ),
        throwsA(
          isA<ImportFailure>().having(
            (failure) => failure.message,
            'mismatch guidance',
            contains('不一致'),
          ),
        ),
      );
      expect(await durableFile.exists(), isFalse);
      expect(await repository.loadSource(book.id), durableSource);
      final unchangedBook = (await repository.loadBook(book.id))!;
      expect(unchangedBook.meta.title, savedBook.meta.title);
      expect(unchangedBook.meta.author, savedBook.meta.author);
      expect(unchangedBook.revision, savedBook.revision);
      final unchangedChapter = (await repository.loadChapter(
        book.id,
        savedChapter.id,
      ))!;
      expect(unchangedChapter.title, savedChapter.title);
      expect(
        unchangedChapter.blocks.whereType<TextBlock>().first.text,
        '用户手工校订的正文。',
      );
      expect(await repository.listSummaries(), hasLength(1));
      expect(await cache.list().toList(), isEmpty);
    },
  );

  test('cancel while source lookup is pending stops reparse before worker or writes', () async {
    const String originalName = '取消测试原稿.txt';
    final List<int> sourceBytes = utf8.encode('第一章 原稿\n原始正文。\n第二章 终章\n原始结尾。');
    final Directory seedCache = Directory('${directory.path}/seed-cache');
    final ImportService seedService = ImportService(
      repository: repository,
      jobs: jobs,
      temporaryDirectory: seedCache,
    );
    final PreparedImport initial = await seedService.prepare(
      _pickedText(originalName, sourceBytes),
    );
    final book = await seedService.commit(initial);
    await _editStoredBook(
      repository,
      book.id,
      title: '取消前用户书名',
      author: '用户作者',
      body: '取消前用户正文。',
    );
    final savedBook = (await repository.loadBook(book.id))!;
    final savedChapter = (await repository.loadChapter(
      book.id,
      savedBook.chapters.firstWhere((chapter) => !chapter.isVolume).id,
    ))!;
    final sourceBefore = (await repository.loadSource(book.id))!;
    final sourceFile = await repository.resolveSource(sourceBefore);
    final List<int> sourceBytesOnDisk = await sourceFile.readAsBytes();

    final Completer<void> loadStarted = Completer<void>();
    final Completer<void> releaseLoad = Completer<void>();
    final _GatedSourceRepository gatedRepository = _GatedSourceRepository(
      database,
      directory,
      loadStarted,
      releaseLoad,
    );
    final _CountingBackgroundJobs countingJobs = _CountingBackgroundJobs();
    addTearDown(countingJobs.dispose);
    final Directory cancelCache = Directory(
      '${directory.path}/cancel-before-prepare-cache',
    );
    final ImportService reparseService = ImportService(
      repository: gatedRepository,
      jobs: countingJobs,
      temporaryDirectory: cancelCache,
    );
    final Future<PreparedImport> pending = reparseService.prepareReparse(
      book.id,
      options: const ParseOptions(),
      replacementInput: _pickedText(originalName, sourceBytes),
    );
    final Future<void> cancelled = expectLater(
      pending,
      throwsA(isA<TaskCancelled>()),
    );
    try {
      await loadStarted.future.timeout(const Duration(seconds: 5));
      reparseService.cancel();
    } finally {
      if (!releaseLoad.isCompleted) releaseLoad.complete();
    }
    await cancelled;

    expect(countingJobs.runCount, 0);
    expect(countingJobs.isBusy, isFalse);
    expect(await cancelCache.exists(), isFalse);
    expect(await repository.loadSource(book.id), sourceBefore);
    expect(await sourceFile.readAsBytes(), sourceBytesOnDisk);
    final currentBook = (await repository.loadBook(book.id))!;
    expect(currentBook.meta.title, savedBook.meta.title);
    expect(currentBook.meta.author, savedBook.meta.author);
    expect(currentBook.revision, savedBook.revision);
    final currentChapter = (await repository.loadChapter(
      book.id,
      savedChapter.id,
    ))!;
    expect(currentChapter.title, savedChapter.title);
    expect(currentChapter.blocks.whereType<TextBlock>().first.text, '取消前用户正文。');
    expect(await repository.listSummaries(), hasLength(1));
  });
}

PickedInput _pickedText(String name, List<int> bytes) => PickedInput(
  name: name,
  size: bytes.length,
  openRead: () => Stream<List<int>>.value(bytes),
);

Future<void> _editStoredBook(
  BookRepository repository,
  String bookId, {
  required String title,
  required String author,
  required String body,
}) async {
  final EditorSession session = EditorSession(repository: repository);
  await session.open(bookId);
  final String blockId = session.activeChapter!.blocks
      .whereType<TextBlock>()
      .first
      .id;
  session.editBookMeta(
    session.book!.meta.copyWith(title: title, author: author),
  );
  session.editBlockText(blockId, body);
  await session.close();
}

class _GatedSourceRepository extends BookRepository {
  _GatedSourceRepository(
    super.db,
    super.appSupportDirectory,
    this.loadStarted,
    this.releaseLoad,
  );

  final Completer<void> loadStarted;
  final Completer<void> releaseLoad;

  @override
  Future<Source?> loadSource(String bookId) async {
    if (!loadStarted.isCompleted) loadStarted.complete();
    await releaseLoad.future;
    return super.loadSource(bookId);
  }
}

class _CountingBackgroundJobs extends BackgroundJobs {
  int runCount = 0;

  @override
  Future<R> run<T, R>(
    T input,
    FutureOr<R> Function(T input, void Function(double, String) progress)
    compute, {
    required int revision,
    Duration timeout = const Duration(minutes: 2),
    void Function(JobProgress)? onProgress,
  }) {
    runCount++;
    return super.run<T, R>(
      input,
      compute,
      revision: revision,
      timeout: timeout,
      onProgress: onProgress,
    );
  }
}
