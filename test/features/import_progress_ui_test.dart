import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/app_paths.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/design/tokens/app_colors.dart';
import 'package:bookloom/design/tokens/app_typography.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:bookloom/features/import/presentation/import_page.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../support/pump_bookloom.dart' show testBookloomWidgets;

final AppLocalizations _zh = lookupAppLocalizations(const Locale('zh'));
const _importScreenshotKey = ValueKey('import-progress-capture');

void main() {
  setUpAll(() async {
    if (Platform.environment['BOOKLOOM_IMPORT_SCREENSHOT_DIR'] == null) return;
    for (final entry in {
      AppTypography.sans: 'BOOKLOOM_IMPORT_SANS_FONT',
      AppTypography.serif: 'BOOKLOOM_IMPORT_SERIF_FONT',
    }.entries) {
      final path = Platform.environment[entry.value];
      if (path == null) throw StateError('Set ${entry.value} for screenshots');
      final loader = FontLoader(entry.key)
        ..addFont(
          Future.value(ByteData.sublistView(await File(path).readAsBytes())),
        );
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testBookloomWidgets('prepare dialog reports progress and cancels on return', (
    tester,
  ) async {
    final fixture = await _ImportFixture.pump(tester);
    fixture.service.prepareGate = Completer<void>();
    await fixture.pick(tester);
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(_zh.importPreparing), findsOneWidget);
    expect(find.text(_zh.importProgressPercent(0)), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );

    fixture.service.emitPrepare(0.37, 'parse');
    await tester.pump();
    expect(find.text(_zh.importStageParse), findsOneWidget);
    expect(find.text(_zh.importProgressPercent(37)), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );

    await tester.tapAt(const Offset(1, 1));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fixture.service.cancelCalls, 0);

    tester.view.physicalSize = const Size(320, 900);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(_zh.commonCancel).hitTestable(), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(_zh.commonCancel),
      ),
    );
    await _pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
    expect(fixture.service.cancelCalls, 1);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(800, 900);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();
    expect(find.text(_zh.importAnalyze), findsOneWidget);

    fixture.service.prepareGate = Completer<void>();
    await tester.ensureVisible(find.text(_zh.importAnalyze));
    await tester.tap(find.text(_zh.importAnalyze));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await _pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
    expect(fixture.service.cancelCalls, 2);
    expect(find.byType(ImportPage), findsOneWidget);
    expect(find.text(_zh.importAnalyze), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('commit progress closes and a failed save can retry', (
    tester,
  ) async {
    final successLogs = <LogRecord>[];
    final logSubscription = Logger('import').onRecord.listen((record) {
      if (record.loggerName == 'import' &&
          record.message.startsWith('import commit success ')) {
        successLogs.add(record);
      }
    });
    addTearDown(logSubscription.cancel);
    final fixture = await _ImportFixture.pump(tester);
    await fixture.pick(tester);
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.text(_zh.importReviewTitle).evaluate().isNotEmpty,
    );
    expect(find.byType(AlertDialog), findsNothing);

    fixture.service.commitGate = Completer<void>();
    fixture.service.failNextCommit = true;
    await tester.ensureVisible(find.text(_zh.importAddToLibrary));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_zh.importAddToLibrary));
    await tester.pump();
    expect(find.text(_zh.importProgressPercent(0)), findsOneWidget);
    expect(find.text(_zh.importProgressPercent(100)), findsNothing);
    expect(find.text(_zh.importSavingNotice), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(_zh.commonCancel),
      ),
      findsNothing,
    );

    fixture.service.emitCommit(0.52, 'save_blocks');
    await tester.pump();
    expect(find.text(_zh.importStageSaveBlocks), findsOneWidget);
    expect(find.text(_zh.importProgressPercent(52)), findsOneWidget);
    await _captureSaveDialogScreenshots(tester);
    fixture.service.emitCommit(0.99999, 'save_finalize');
    await tester.pump();
    expect(find.text(_zh.importProgressPercent(99)), findsOneWidget);
    expect(find.text(_zh.importProgressPercent(100)), findsNothing);
    await tester.tapAt(const Offset(1, 1));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fixture.service.cancelCalls, 0);

    fixture.service.commitGate!.complete();
    await _pumpUntil(
      tester,
      () => find.textContaining(_zh.importSaveFailed).evaluate().isNotEmpty,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ImportPage), findsOneWidget);
    expect(find.text(_zh.importReviewTitle), findsOneWidget);

    fixture.service.commitGate = Completer<void>();
    await tester.tap(find.text(_zh.importAddToLibrary));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(_zh.importProgressPercent(0)), findsOneWidget);
    fixture.service.emitCommit(0.75, 'save_finalize');
    await tester.pump();
    expect(find.text(_zh.importProgressPercent(75)), findsOneWidget);
    fixture.service.commitGate!.complete();
    await _pumpUntil(
      tester,
      () => find.text('book-open').evaluate().isNotEmpty,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.service.commitCalls, 2);
    expect(
      fixture.service.realSaveProgress.map((progress) => progress.stage),
      containsAll(['save_chapters', 'save_blocks', 'save_finalize']),
    );
    expect(fixture.service.realSaveProgress.last.fraction, 1);
    expect(successLogs, hasLength(1));
    expect(successLogs.single.level, Level.INFO);
    expect(
      successLogs.single.message,
      matches(
        r'^import commit success chapters=1 blocks=1 words=8 storage_ms=\d+ cleanup_ms=\d+ total_ms=\d+$',
      ),
    );
    expect(tester.takeException(), isNull);
  });
  testBookloomWidgets(
    'ready waits for default layout without showing 100 percent',
    (tester) async {
      final layout = Completer<LayoutOptions>();
      var loadingLayout = false;
      final fixture = await _ImportFixture.pump(
        tester,
        loadDefaultLayout: () {
          loadingLayout = true;
          return layout.future;
        },
      );
      await fixture.pick(tester);
      await tester.pump();
      await _pumpUntil(tester, () => loadingLayout);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_zh.importStageReady), findsOneWidget);
      expect(find.text(_zh.importProgressPercent(100)), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(find.text(_zh.importReviewTitle), findsNothing);
      layout.complete(LayoutOptions());
      await _pumpUntil(
        tester,
        () => find.text(_zh.importReviewTitle).evaluate().isNotEmpty,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets('disposing during save removes only its task dialog', (
    tester,
  ) async {
    final fixture = await _ImportFixture.pump(tester);
    await fixture.pick(tester);
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.text(_zh.importReviewTitle).evaluate().isNotEmpty,
    );
    fixture.service.commitGate = Completer<void>();
    await tester.ensureVisible(find.text(_zh.importAddToLibrary));
    await tester.tap(find.text(_zh.importAddToLibrary));
    await tester.pump();
    final taskRoute = ModalRoute.of(tester.element(find.byType(AlertDialog)))!;
    final navigator = taskRoute.navigator!;
    final otherRoute = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('other-route')),
    );
    unawaited(navigator.push(otherRoute));
    await tester.pumpAndSettle();
    fixture.showImport.value = false;
    await tester.pump();
    await tester.pump();
    expect(taskRoute.isActive, isFalse);
    expect(otherRoute.isCurrent, isTrue);
    expect(find.text('other-route'), findsOneWidget);
    expect(fixture.service.cancelCalls, 0);
    fixture.service.emitCommit(0.99999, 'save_finalize');
    fixture.service.commitGate!.complete();
    await _pumpUntil(tester, () => fixture.service.completedCommits == 1);
    await tester.pumpAndSettle();
    expect(otherRoute.isCurrent, isTrue);
    expect(find.text('book-open'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _ImportFixture {
  const _ImportFixture(this.service, this.showImport);

  final _ControlledImportService service;
  final ValueNotifier<bool> showImport;

  static Future<_ImportFixture> pump(
    WidgetTester tester, {
    Future<LayoutOptions> Function()? loadDefaultLayout,
  }) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final fixture = await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('bookloom-import-ui-');
      final database = AppDatabase.openAt(
        File(p.join(root.path, 'test.sqlite')),
      );
      final repository = BookRepository(database, root);
      final jobs = BackgroundJobs();
      final paths = AppPaths(
        support: root,
        books: Directory(p.join(root.path, 'books')),
        logs: Directory(p.join(root.path, 'logs')),
        cache: Directory(p.join(root.path, 'cache')),
      );
      final service = _ControlledImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: Directory(p.join(root.path, 'workbench')),
        loadDefaultLayout: loadDefaultLayout,
      );
      return (
        root: root,
        database: database,
        repository: repository,
        jobs: jobs,
        paths: paths,
        service: service,
      );
    });
    if (fixture == null) throw StateError('Could not create import fixture');
    final showImport = ValueNotifier<bool>(true);
    final router = GoRouter(
      initialLocation: '/import',
      routes: [
        GoRoute(
          path: '/import',
          builder: (_, _) => ValueListenableBuilder<bool>(
            valueListenable: showImport,
            builder: (_, visible, _) => Scaffold(
              body: visible ? const ImportPage() : const Text('import-removed'),
            ),
          ),
        ),
        GoRoute(
          path: '/books/:id',
          builder: (_, _) => const Scaffold(body: Text('book-open')),
        ),
      ],
    );
    addTearDown(() async {
      fixture.jobs.dispose();
      router.dispose();
      showImport.dispose();
      await fixture.database.close();
      await fixture.root.delete(recursive: true);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPathsProvider.overrideWithValue(fixture.paths),
          databaseProvider.overrideWithValue(fixture.database),
          bookRepositoryProvider.overrideWithValue(fixture.repository),
          fileServiceProvider.overrideWithValue(_ImportFiles()),
          importServiceProvider.overrideWithValue(fixture.service),
        ],
        child: RepaintBoundary(
          key: _importScreenshotKey,
          child: ColoredBox(
            color: AppColors.light.canvas,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _ImportFixture(fixture.service, showImport);
  }

  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text(_zh.importSelectTitle));
    // Parsing starts automatically; avoid pumpAndSettle here because the
    // progress dialog carries an indeterminate indicator until the gate
    // (or the fake service) resolves.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('sample.txt'), findsOneWidget);
  }
}

class _ImportFiles implements FileService {
  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const ['txt', 'epub', 'docx'],
  }) async {
    final bytes = utf8.encode('第一章 清晨\n门边放着一封信。');
    return [
      PickedInput(
        name: 'sample.txt',
        size: bytes.length,
        openRead: () => Stream.value(bytes),
      ),
    ];
  }

  @override
  Future<void> clearTemporaryFiles() async {}

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) async => const SaveCancelled();
}

class _ControlledImportService extends ImportService {
  _ControlledImportService({
    required super.repository,
    required super.jobs,
    required super.temporaryDirectory,
    super.loadDefaultLayout,
  });

  Completer<void>? prepareGate;
  Completer<void>? commitGate;
  void Function(JobProgress)? _prepareProgress;
  void Function(JobProgress)? _commitProgress;
  bool _cancelled = false;
  bool failNextCommit = false;
  int cancelCalls = 0;
  int commitCalls = 0;
  int completedCommits = 0;
  final List<JobProgress> realSaveProgress = [];

  void emitPrepare(double fraction, String stage) =>
      _prepareProgress?.call(JobProgress(1, 0, fraction, stage));

  void emitCommit(double fraction, String stage) =>
      _commitProgress?.call(JobProgress(2, 0, fraction, stage));

  @override
  Future<PreparedImport> prepare(
    PickedInput input, {
    ParseOptions options = const ParseOptions(),
    void Function(JobProgress)? onProgress,
  }) async {
    _cancelled = false;
    _prepareProgress = onProgress;
    final gate = prepareGate;
    if (gate != null) await gate.future;
    if (_cancelled) throw const TaskCancelled();
    return super.prepare(input, options: options, onProgress: onProgress);
  }

  @override
  Future<Book> commit(
    PreparedImport prepared, {
    void Function(JobProgress)? onProgress,
  }) async {
    commitCalls++;
    _commitProgress = onProgress;
    final gate = commitGate;
    if (gate != null) await gate.future;
    if (failNextCommit) {
      failNextCommit = false;
      throw const StorageFailure('测试保存失败');
    }
    final book = await super.commit(
      prepared,
      onProgress: (progress) {
        realSaveProgress.add(progress);
        onProgress?.call(progress);
      },
    );
    completedCommits++;
    return book;
  }

  @override
  void cancel() {
    cancelCalls++;
    _cancelled = true;
    final gate = prepareGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    super.cancel();
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    condition(),
    isTrue,
    reason: 'Import UI did not reach the expected state',
  );
}

Future<void> _captureSaveDialogScreenshots(WidgetTester tester) async {
  final directory = Platform.environment['BOOKLOOM_IMPORT_SCREENSHOT_DIR'];
  if (directory == null) return;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  for (final width in [1280.0, 320.0]) {
    tester.view.physicalSize = Size(width, 900);
    tester.platformDispatcher.textScaleFactorTestValue = width == 320 ? 2 : 1;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(_zh.importSavingNotice).hitTestable(), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_importScreenshotKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('Could not encode import screenshot');
        }
        await Directory(directory).create(recursive: true);
        await File(p.join(directory, 'import-save-${width.toInt()}.png'))
            .writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
      } finally {
        image.dispose();
      }
    });
  }
  tester.view.physicalSize = const Size(800, 900);
  tester.platformDispatcher.clearTextScaleFactorTestValue();
  await tester.pump(const Duration(milliseconds: 300));
}
