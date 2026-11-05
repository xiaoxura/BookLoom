import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/app/app.dart';
import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart' show TextBlock;
import 'package:bookloom/core/model/book.dart' as model;
import 'package:bookloom/core/model/chapter.dart' as model;
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/app_paths.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/core/storage/settings_store.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Short original text owned by this widget test. It is long enough to exercise
/// chapter navigation and paragraph editing without depending on outside
/// fixture licensing or fonts.
const String workbenchUiSampleText = '''
第一章 清晨
门边放着一封信。

小船已经离港。

第二章 返航
灯又亮了。
''';

const Key workbenchAppGoldenBoundaryKey = ValueKey<String>(
  'workbench-app-golden-boundary',
);

class WorkbenchUiHarness {
  WorkbenchUiHarness._({
    required this.tester,
    required this.root,
    required this.database,
    required this.repository,
    required this.settingsStore,
    required this.files,
    required this.source,
    required this.paths,
  });

  final WidgetTester tester;
  final Directory root;
  final AppDatabase database;
  final WorkbenchUiRepository repository;
  final SettingsStore settingsStore;
  final WorkbenchUiFileService files;
  final File source;
  final AppPaths paths;

  static Future<WorkbenchUiHarness> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 900),
    Appearance appearance = const Appearance(
      themeMode: AppThemeMode.dark,
      glass: GlassQuality.off,
    ),
    SettingsStore Function(AppDatabase database)? settingsStoreFactory,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final fixture = await tester.runAsync(() async {
      final Directory root = await Directory.systemTemp.createTemp(
        'bookloom-workbench-ui-',
      );
      final Directory cache = Directory(p.join(root.path, 'cache'));
      final Directory books = Directory(p.join(root.path, 'books'));
      final Directory logs = Directory(p.join(root.path, 'logs'));
      await Future.wait(<Future<void>>[
        cache.create(recursive: true),
        books.create(recursive: true),
        logs.create(recursive: true),
      ]);
      final File source = File(p.join(root.path, '《海风》作者：林澈.txt'));
      await source.writeAsString(workbenchUiSampleText.trim());
      final Uint8List sourceBytes = await source.readAsBytes();
      final Directory exports = Directory(p.join(root.path, 'exports'));
      await exports.create();

      final AppDatabase database = AppDatabase.openAt(
        File(p.join(root.path, 'bookloom.sqlite')),
      );
      final AppPaths paths = AppPaths(
        support: root,
        books: books,
        logs: logs,
        cache: cache,
      );
      final WorkbenchUiRepository repository = WorkbenchUiRepository(
        database,
        root,
      );
      final WorkbenchUiFileService files = WorkbenchUiFileService(
        sourceName: p.basename(source.path),
        sourceBytes: sourceBytes,
        exports: exports,
      );
      return (
        root: root,
        database: database,
        repository: repository,
        files: files,
        source: source,
        paths: paths,
      );
    });
    if (fixture == null) throw StateError('Could not create test fixture');
    final SettingsStore settingsStore =
        settingsStoreFactory?.call(fixture.database) ??
        SettingsStore(fixture.database);
    final WorkbenchUiHarness harness = WorkbenchUiHarness._(
      tester: tester,
      root: fixture.root,
      database: fixture.database,
      repository: fixture.repository,
      settingsStore: settingsStore,
      files: fixture.files,
      source: fixture.source,
      paths: fixture.paths,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await tester.runAsync(() async {
        await harness.database.close();
        if (await harness.root.exists()) {
          await harness.root.delete(recursive: true);
        }
      });
      await tester.pump(Duration.zero);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(fixture.database),
          appPathsProvider.overrideWithValue(fixture.paths),
          bookRepositoryProvider.overrideWithValue(fixture.repository),
          fileServiceProvider.overrideWithValue(fixture.files),
          settingsStoreProvider.overrideWithValue(settingsStore),
          initialAppearanceProvider.overrideWithValue(appearance),
        ],
        child: const RepaintBoundary(
          key: workbenchAppGoldenBoundaryKey,
          child: BookloomApp(),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find
          .text(lookupAppLocalizations(const Locale('zh')).libraryEmptyTitle)
          .evaluate()
          .isNotEmpty,
    );
    return harness;
  }

  /// Creates an existing book with the sample TXT's content through the real
  /// repository. The import UI test separately exercises the importer; this
  /// keeps IME/layout tests focused on the editor and avoids a worker isolate.
  Future<model.Book> seedBook() async {
    final DateTime now = DateTime.utc(2026, 1, 1);
    const String bookId = 'workbench-ui-seed';
    final model.Book book = model.Book(
      id: bookId,
      meta: BookMeta(title: '海风', author: '林澈'),
      chapters: const <model.Chapter>[
        model.Chapter(
          id: 'workbench-ui-chapter-1',
          bookId: bookId,
          title: '第一章 清晨',
          order: 0,
          blocks: <TextBlock>[
            TextBlock(id: 'workbench-ui-block-1', text: '门边放着一封信。'),
            TextBlock(id: 'workbench-ui-block-2', text: '小船已经离港。'),
          ],
        ),
        model.Chapter(
          id: 'workbench-ui-chapter-2',
          bookId: bookId,
          title: '第二章 返航',
          order: 1,
          blocks: <TextBlock>[
            TextBlock(id: 'workbench-ui-block-3', text: '灯又亮了。'),
          ],
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final model.Book? committed = await tester.runAsync(
      () => repository.createBook(book),
    );
    if (committed == null) throw StateError('Could not seed test book');
    // createBook persists every block, but intentionally returns a structural
    // book without bodies. Return the fixture model for assertions; the editor
    // still reloads stored bodies through the repository.
    return book;
  }

  Future<List<BookSummary>> listSummaries() async {
    final List<BookSummary>? summaries = await tester.runAsync(
      repository.listSummaries,
    );
    if (summaries == null) throw StateError('Could not read book summaries');
    return summaries;
  }

  Future<model.Chapter?> loadChapter(String bookId, String chapterId) async {
    final model.Chapter? chapter = await tester.runAsync<model.Chapter?>(
      () => repository.loadChapter(bookId, chapterId),
    );
    return chapter;
  }
}

class WorkbenchUiFileService implements FileService {
  WorkbenchUiFileService({
    required this.sourceName,
    required this.sourceBytes,
    required this.exports,
  });

  final String sourceName;
  final Uint8List sourceBytes;
  final Directory exports;
  bool cancelNextPick = false;
  bool cancelNextSave = false;
  List<PickedInput>? nextPickedInputs;
  int pickCount = 0;
  int saveCount = 0;
  List<String>? lastExtensions;
  bool? lastMultiple;
  final List<({String name, String mimeType, File file})> savedExports = [];

  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const <String>['txt', 'epub', 'docx'],
  }) async {
    pickCount++;
    lastExtensions = List<String>.of(extensions);
    lastMultiple = multiple;
    final List<PickedInput>? queuedInputs = nextPickedInputs;
    if (queuedInputs != null) {
      nextPickedInputs = null;
      return queuedInputs;
    }
    if (cancelNextPick) {
      cancelNextPick = false;
      return <PickedInput>[];
    }
    return <PickedInput>[
      PickedInput(
        name: sourceName,
        size: sourceBytes.length,
        openRead: () => Stream<List<int>>.value(sourceBytes),
      ),
    ];
  }

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) async {
    saveCount++;
    if (cancelNextSave) {
      cancelNextSave = false;
      return const SaveCancelled();
    }
    final File captured = File(
      p.join(exports.path, 'export-${savedExports.length + 1}.epub'),
    );
    // File I/O itself completes on the real event loop. Avoid starting a
    // nested tester.runAsync from a UI callback: the harness's polling loop
    // may also need runAsync to let worker messages and the UI finish.
    await prepared.copy(captured.path);
    savedExports.add((name: suggestedName, mimeType: mimeType, file: captured));
    return SaveSaved(captured.uri);
  }

  @override
  Future<void> clearTemporaryFiles() async {}
}

/// Uses the real repository except for a one-shot save failure that makes the
/// editor's dirty/retry state observable without changing production APIs.
class WorkbenchUiRepository extends BookRepository {
  WorkbenchUiRepository(super.db, super.appSupportDirectory);

  bool failNextSave = false;
  int saveAttempts = 0;

  @override
  Future<model.Book> saveBook(
    model.Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    saveAttempts++;
    if (failNextSave) {
      failNextSave = false;
      throw const StorageFailure('测试磁盘故障：暂不保存。');
    }
    return super.saveBook(
      book,
      expectedRevision: expectedRevision,
      dirtyChapterIds: dirtyChapterIds,
      deletedChapterIds: deletedChapterIds,
    );
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) {
      await tester.pump(Duration.zero);
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(Duration.zero);
  }
  expect(condition(), isTrue, reason: 'UI did not reach its initial state');
}
