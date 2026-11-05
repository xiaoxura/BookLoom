import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:bookloom/app/app.dart';
import 'package:bookloom/app/bootstrap.dart';
import 'package:bookloom/app/offline_dictionaries.dart';
import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/router.dart';
import 'package:bookloom/app/window/window_controls.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/epub/epub_validator.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/presentation/editor_page.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Requires a task-owned XDG root and a controller for the two GTK dialogs.
/// See docs/development/00-native-workbench.md for the recorded invocation.
/// This exercises a visible native app; text entry is Flutter test input and
/// does not establish compatibility with a real desktop IME.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated Linux import, edit, save, restart and performance', (
    tester,
  ) async {
    final rootPath = Platform.environment['BOOKLOOM_NATIVE_TEST_ROOT'];
    if (!Platform.isLinux || rootPath == null) {
      fail(
        'Use the isolated Linux validation launcher, never the daily library.',
      );
    }
    final root = Directory(rootPath);
    expect(await File(p.join(root.path, '.bookloom-owned')).exists(), isTrue);
    expect(Platform.environment['XDG_DATA_HOME'], p.join(root.path, 'data'));
    expect(Platform.environment['XDG_CACHE_HOME'], p.join(root.path, 'cache'));
    final restart = Platform.environment['BOOKLOOM_NATIVE_PHASE'] == 'restart';
    final pickerBypass =
        Platform.environment['BOOKLOOM_NATIVE_PICKER_BYPASS'] == '1';
    final metrics = <String, Object?>{
      'phase': restart ? 'restart' : 'import',
      'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
      'realDesktopImeMeasured': false,
      'processStartToMainMeasured': false,
      'nativePickerMeasured': !pickerBypass,
      'dartHttpDisabled': true,
    };
    HttpOverrides.global = _OfflineHttp();
    final coldStart = Stopwatch()..start();
    WindowControls.configure();
    final boot = await bootstrap();
    expect(p.isWithin(root.path, boot.paths.support.path), isTrue);
    final container = ProviderContainer(
      overrides: [
        appPathsProvider.overrideWithValue(boot.paths),
        databaseProvider.overrideWithValue(boot.database),
        initialAppearanceProvider.overrideWithValue(boot.appearance),
        fileServiceProvider.overrideWithValue(_TracingNativeFiles(root)),
      ],
    );
    const boundaryKey = ValueKey('native-validation-boundary');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RepaintBoundary(key: boundaryKey, child: BookloomApp()),
      ),
    );
    final zh = lookupAppLocalizations(const Locale('zh'));
    final en = lookupAppLocalizations(const Locale('en'));
    final repository = container.read(bookRepositoryProvider);
    final router = container.read(routerProvider);
    final source = File(p.join(root.path, '百万字.txt'));
    final sourceHash = (await sha256.bind(source.openRead()).first).toString();
    try {
      if (restart) {
        final id = await File(p.join(root.path, 'book-id')).readAsString();
        await _wait(tester, () => find.text('百万字').evaluate().isNotEmpty);
        metrics['existingShelfBootstrapToFrameMilliseconds'] =
            coldStart.elapsedMilliseconds;
        router.go('/books/$id');
        await _wait(tester, () => _paragraph('已校对：').evaluate().isNotEmpty);
        final book = await repository.loadBook(id);
        expect(book!.chapters, hasLength(1000));
        final chapter = await repository.loadChapter(
          id,
          book.chapters.first.id,
        );
        expect(chapter!.blocks.first.plainText, startsWith('已校对：'));
        validateEpub(p.join(root.path, 'native-export.epub'));
      } else {
        await _wait(
          tester,
          () =>
              find.text(zh.libraryEmptyAction).evaluate().isNotEmpty ||
              find.text(en.libraryEmptyAction).evaluate().isNotEmpty,
        );
        metrics['emptyShelfBootstrapToFrameMilliseconds'] =
            coldStart.elapsedMilliseconds;
        final localized = find.text(zh.libraryEmptyAction).evaluate().isNotEmpty
            ? zh
            : en;
        final editable = Stopwatch()..start();
        if (pickerBypass) {
          // A separately labelled performance path when the desktop Portal
          // cannot be controlled. It still uses production parsing, staging,
          // repository and the real native renderer; no picker claim is made.
          final importer = container.read(importServiceProvider);
          final prepared = await importer.prepare(
            PickedInput(
              name: p.basename(source.path),
              size: await source.length(),
              openRead: source.openRead,
            ),
          );
          final stored = await importer.commit(prepared);
          router.go('/books/${stored.id}');
        } else {
          await tester.tap(find.text(localized.libraryEmptyAction));
          await tester.pumpAndSettle();
          await File(p.join(root.path, 'pick-ready'))
              .writeAsString(source.path);
          await tester.tap(find.text(localized.importChooseFile));
          await _wait(tester, () => find.text('百万字.txt').evaluate().isNotEmpty);
          await tester.ensureVisible(find.text(localized.importAnalyze));
          editable.reset();
          await tester.tap(find.text(localized.importAnalyze));
          await _wait(
            tester,
            () => find.text(localized.importReviewTitle).evaluate().isNotEmpty,
          );
          await tester.ensureVisible(find.text(localized.importAddToLibrary));
          await tester.tap(find.text(localized.importAddToLibrary));
        }
        await _wait(tester, () => _paragraph('甲').evaluate().isNotEmpty);
        expect(find.byType(EditorPage), findsOneWidget);
        metrics['millionImportToEditableMilliseconds'] =
            editable.elapsedMilliseconds;
        metrics['peakRssBytes'] = ProcessInfo.maxRss;
        await File(p.join(root.path, 'metrics-editable.json'))
            .writeAsString(const JsonEncoder.withIndent('  ').convert(metrics));
        final summaries = await repository.listSummaries();
        expect(summaries, hasLength(1));
        final id = summaries.single.id;
        final book = await repository.loadBook(id);
        expect(book!.chapters, hasLength(1000));
        expect(summaries.single.wordCount, 1000000);
        await File(p.join(root.path, 'book-id')).writeAsString(id);
        final paragraph = tester.widget<TextField>(_paragraph('甲'));
        // The real integration binding leaves TestTextInput unregistered.
        // Profile mode rejects its default client -1, so explicitly capture a
        // real client ID for this simulated editing assertion.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        tester.testTextInput.register();
        await tester.enterText(
          _paragraph('甲'),
          '已校对：${paragraph.controller!.text.substring(4)}',
        );
        await _wait(tester, () => _paragraph('已校对：').evaluate().isNotEmpty);
        // Switching through the real directory flushes the visible editor.
        final switches = <int>[];
        for (final index in [2, 3, 4, 5, 1]) {
          final title = '第$index章 测试章节';
          final tile = find.ancestor(
            of: find.text(title),
            matching: find.byType(ListTile),
          );
          if (tile.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              find.text(title),
              index == 1 ? -300 : 300,
              scrollable: find.descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              ),
            );
          }
          await tester.ensureVisible(tile);
          final watch = Stopwatch()..start();
          await tester.tap(tile);
          await _wait(tester, () => find.text(title).evaluate().length >= 2);
          switches.add(watch.elapsedMilliseconds);
        }
        metrics['chapterSwitchMilliseconds'] = switches;
        final tree = find.byType(ListView).first;
        await tester.fling(tree, const Offset(0, -12000), 8000);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('第1000章 测试章节'),
          12000,
          scrollable: find.descendant(
            of: tree,
            matching: find.byType(Scrollable),
          ),
          maxScrolls: 12,
        );
        metrics['thousandChapterScrollFlutterError'] = tester
            .takeException()
            ?.toString();
        expect(metrics['thousandChapterScrollFlutterError'], isNull);
        await _screenshot(tester, boundaryKey, root, 'native-million.png');
        final export = container.read(exportServiceProvider);
        await File(p.join(root.path, 'save-ready'))
            .writeAsString(p.join(root.path, 'native-export.epub'));
        final exportWatch = Stopwatch()..start();
        expect(
          await export.withPreparedExport<SaveOutcome>(
            id,
            submit: (file, {required suggestedName, required mimeType}) {
              metrics['epubPreparationMilliseconds'] =
                  exportWatch.elapsedMilliseconds;
              return container
                  .read(fileServiceProvider)
                  .savePreparedFile(
                    file,
                    suggestedName: suggestedName,
                    mimeType: mimeType,
                  );
            },
          ),
          isA<SaveSaved>(),
        );
        metrics['epubIncludingNativeSaveMilliseconds'] =
            exportWatch.elapsedMilliseconds;
        validateEpub(p.join(root.path, 'native-export.epub'));

        // Load the production bundled dictionaries on their first use. No
        // source-tree dictionary reads or network clients are involved.
        final offline = await container
            .read(importServiceProvider)
            .prepare(
              PickedInput(
                name: '离线转换.txt',
                size: null,
                openRead: () => Stream.value(utf8.encode('第一章 後來\n軟體與滑鼠。')),
              ),
              options: const ParseOptions(convertMode: ConvertMode.simplified),
            );
        final converted = await container
            .read(importServiceProvider)
            .commit(offline);
        final session = EditorSession(
          repository: repository,
          jobs: container.read(backgroundJobsProvider),
        );
        await session.open(converted.id);
        expect(session.activeChapter!.title, contains('后来'));
        expect(
          session.activeChapter!.blocks.whereType<TextBlock>().first.text,
          '软体与滑鼠。',
        );
        final preview = await session.previewConvert(
          ConvertMode.taiwan,
          await loadOfflineDictionaries(),
        );
        await session.applyToolPreview(preview);
        expect(session.activeChapter!.title, contains('後來'));
        await session.undo();
        expect(session.activeChapter!.title, contains('后来'));
        await session.close();
        metrics['bundledOfflineImportConvertUndo'] = true;
      }
      expect(
        (await sha256.bind(source.openRead()).first).toString(),
        sourceHash,
      );
      metrics['peakRssBytes'] = ProcessInfo.maxRss;
      await File(
        p.join(root.path, 'metrics-${restart ? 'restart' : 'import'}.json'),
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(metrics));
    } on Object {
      await _screenshot(tester, boundaryKey, root, 'native-failure.png');
      rethrow;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      await boot.database.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class _OfflineHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('HTTP disabled in native validation');
}

class _TracingNativeFiles implements FileService {
  _TracingNativeFiles(this.root);
  final Directory root;
  final _native = NativeFileService();

  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const ['txt', 'epub', 'docx'],
  }) async {
    try {
      return await _native.pickImports(
        multiple: multiple,
        extensions: extensions,
      );
    } on Object catch (error) {
      await File(p.join(root.path, 'picker-error.txt'))
          .writeAsString('$error\n${error is AppFailure ? error.cause : ''}');
      rethrow;
    }
  }

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) => _native.savePreparedFile(
    prepared,
    suggestedName: suggestedName,
    mimeType: mimeType,
  );

  @override
  Future<void> clearTemporaryFiles() => _native.clearTemporaryFiles();
}

Finder _paragraph(String start) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.maxLines == null &&
      (widget.controller?.text.startsWith(start) ?? false),
);

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 30)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Native UI did not reach the requested state',
  );
  await tester.pump();
}

Future<void> _screenshot(
  WidgetTester tester,
  Key key,
  Directory directory,
  String name,
) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final screenshot = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await screenshot.toByteData(format: ImageByteFormat.png);
    await File(p.join(directory.path, name))
        .writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    screenshot.dispose();
  }
}
