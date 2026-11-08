import 'dart:io';

import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/theme/app_tokens.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/design/tokens/app_typography.dart';
import 'package:bookloom/features/editor/presentation/editor_page.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_bookloom.dart' show testBookloomWidgets;
import '../support/workbench_ui_harness.dart';

final AppLocalizations zh = lookupAppLocalizations(const Locale('zh'));
bool _goldenFontsReady = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use existing local fonts only for readable Linux evidence. Font files
    // are not copied into the application or redistributed with these tests.
    final fonts = <String, String>{
      AppTypography.sans:
          '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      AppTypography.serif:
          '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
    };
    for (final path in fonts.values) {
      if (!await File(path).exists()) {
        debugPrint(
          'Golden fonts unavailable; behavior checks still run, screenshots unverified.',
        );
        return;
      }
    }
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          Future.value(
            ByteData.sublistView(await File(entry.value).readAsBytes()),
          ),
        );
      await loader.load();
    }
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await materialIcons.load();
    _goldenFontsReady = true;
  });
  testBookloomWidgets('TXT picker review opens the parsed book in the editor', (
    WidgetTester tester,
  ) async {
    final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(tester);

    await tester.tap(find.text(zh.libraryEmptyAction));
    await tester.pumpAndSettle();
    expect(find.text(zh.importSelectTitle), findsOneWidget);

    // A picker cancellation leaves the import page empty and creates no book.
    harness.files.cancelNextPick = true;
    await tester.tap(find.text(zh.importSelectTitle));
    await tester.pumpAndSettle();
    expect(await harness.listSummaries(), isEmpty);
    expect(find.text(zh.importAnalyze), findsNothing);

    await tester.tap(find.text(zh.importSelectTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.files.lastMultiple, isFalse);
    expect(harness.files.lastExtensions, <String>['txt', 'epub', 'docx']);
    expect(find.text('《海风》作者：林澈.txt'), findsOneWidget);

    // The parse starts automatically; the preview replaces the options-only
    // state without an extra click.
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.text(zh.importReviewTitle).evaluate().isNotEmpty,
    );
    expect(find.textContaining('2 章'), findsOneWidget);
    expect(find.text('门边放着一封信。'), findsOneWidget);
    expect(await harness.listSummaries(), isEmpty);

    await tester.ensureVisible(find.text(zh.importAddToLibrary));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.importAddToLibrary));
    await _pumpUntil(
      tester,
      () =>
          find.byType(EditorPage).evaluate().isNotEmpty &&
          find.text(zh.editorSaved).evaluate().isNotEmpty,
    );
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.text('第一章 清晨'), findsWidgets);
    expect(_paragraphFieldWithText('门边放着一封信。'), findsOneWidget);
    expect(await harness.listSummaries(), hasLength(1));

    expect(find.text(zh.editorPreview), findsNothing);
    expect(find.text(zh.editorEdit), findsNothing);
    expect(_paragraphFieldWithText('门边放着一封信。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets(
    'IME composition blocks chapter navigation and persists commit',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(tester);
      final book = await harness.seedBook();
      await _pumpUntil(
        tester,
        () => find.text(book.meta.title).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(book.meta.title));
      await _pumpUntil(
        tester,
        () => find.text(zh.editorSaved).evaluate().isNotEmpty,
      );

      final Chapter first = book.chapters.firstWhere(
        (chapter) => !chapter.isVolume,
      );
      final Chapter second = book.chapters
          .where((chapter) => !chapter.isVolume)
          .elementAt(1);
      final String original = first.blocks.whereType<TextBlock>().first.text;
      final String composingText = '$original 正在输入';
      final Finder paragraph = _paragraphFieldWithText(original);
      await tester.tap(paragraph);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: composingText,
          selection: TextSelection.collapsed(offset: composingText.length),
          composing: TextRange(
            start: original.length,
            end: composingText.length,
          ),
        ),
      );
      await tester.pump();
      expect(_paragraphFieldWithText(composingText), findsOneWidget);

      // This tap is ignored while the IME owns an uncommitted composition.
      await tester.tap(find.text(second.title).first);
      await tester.pump();
      expect(find.text(first.title), findsNWidgets(2));
      expect(find.text(second.title), findsOneWidget);

      // Many IMEs commit by changing only the composing range while keeping the
      // text identical. That committed value must reach the editing session.
      final int expectedSaveAttempts = harness.repository.saveAttempts + 1;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: composingText,
          selection: TextSelection.collapsed(offset: composingText.length),
        ),
      );
      await tester.pump();
      await _waitForStoredParagraph(
        tester,
        harness,
        book.id,
        first.id,
        composingText,
        expectedSaveAttempts: expectedSaveAttempts,
      );

      await tester.tap(find.text(second.title).first);
      await _pumpUntil(
        tester,
        () => find.text(second.title).evaluate().length >= 2,
      );
      expect(find.text(second.title), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'a failed autosave keeps the editor dirty until retry succeeds',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(tester);
      final book = await harness.seedBook();
      await _pumpUntil(
        tester,
        () => find.text(book.meta.title).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(book.meta.title));
      await _pumpUntil(
        tester,
        () => find.text(zh.editorSaved).evaluate().isNotEmpty,
      );

      final Chapter first = book.chapters.firstWhere(
        (chapter) => !chapter.isVolume,
      );
      final String original = first.blocks.whereType<TextBlock>().first.text;
      const String corrected = '门边放着一封已经校订的新信。';
      harness.repository.failNextSave = true;
      await tester.enterText(_paragraphFieldWithText(original), corrected);
      await tester.pump(const Duration(milliseconds: 1100));
      await _pumpUntil(
        tester,
        () => find.text(zh.editorSaveFailed).evaluate().isNotEmpty,
      );

      expect(_paragraphFieldWithText(corrected), findsOneWidget);
      expect(
        (await harness.loadChapter(
          book.id,
          first.id,
        ))!.blocks.whereType<TextBlock>().first.text,
        original,
      );

      // Leaving also retries the flush. A second failure keeps this route open,
      // and the visible retry action can commit the still-present edit.
      harness.repository.failNextSave = true;
      await tester.tap(find.byTooltip(zh.editorBack));
      await _pumpUntil(
        tester,
        () => find.text(zh.editorSaveFailedStay).evaluate().isNotEmpty,
      );
      expect(find.byType(EditorPage), findsOneWidget);
      expect(_paragraphFieldWithText(corrected), findsOneWidget);

      final int expectedSaveAttempts = harness.repository.saveAttempts + 1;
      await tester.tap(find.text(zh.commonRetry).first);
      await _waitForStoredParagraph(
        tester,
        harness,
        book.id,
        first.id,
        corrected,
        expectedSaveAttempts: expectedSaveAttempts,
      );
      expect(find.text(zh.editorSaved), findsOneWidget);
      expect(find.byType(EditorPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'cancelling the export destination does not report success',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(tester);
      final book = await harness.seedBook();
      await _pumpUntil(
        tester,
        () => find.text(book.meta.title).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(book.meta.title));
      await _pumpUntil(
        tester,
        () => find.text(zh.editorSaved).evaluate().isNotEmpty,
      );

      harness.files.cancelNextSave = true;
      expect(find.byTooltip(zh.editorExport).hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip(zh.editorExport));
      await tester.pump(Duration.zero);
      await _pumpUntil(tester, () => find.text('选择保存位置').evaluate().isNotEmpty);
      await tester.tap(find.text('选择保存位置'));
      await tester.pumpAndSettle();
      await _pumpUntil(tester, () => harness.files.saveCount == 1);

      expect(harness.files.savedExports, isEmpty);
      expect(find.text(zh.editorExportSaved), findsNothing);
      expect(find.text(zh.editorExportFailed), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'active chapter has a visible selected surface after navigation',
    (WidgetTester tester) async {
      final harness = await WorkbenchUiHarness.pump(tester);
      final book = await harness.seedBook();
      await _pumpUntil(
        tester,
        () => find.text(book.meta.title).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(book.meta.title));
      await _pumpUntil(
        tester,
        () => find.text(zh.editorSaved).evaluate().isNotEmpty,
      );
      final tiles = find.byWidgetPredicate(
        (widget) => widget is ListTile && widget.selected,
      );
      expect(tiles, findsOneWidget);
      final firstTile = tester.widget<ListTile>(tiles);
      final colors = tester.element(tiles).colors;
      expect(firstTile.selectedTileColor, colors.accentSoft);
      expect(firstTile.selectedTileColor, isNot(colors.surface));
      expect(
        find.descendant(of: tiles, matching: find.text('第一章 清晨')),
        findsOneWidget,
      );
      final nextChapter = find.ancestor(
        of: find.text('第二章 返航'),
        matching: find.byType(ListTile),
      );
      await tester.tap(nextChapter);
      await _pumpUntil(
        tester,
        () => _paragraphFieldWithText('灯又亮了。').evaluate().isNotEmpty,
      );
      expect(tiles, findsOneWidget);
      expect(
        find.descendant(of: tiles, matching: find.text('第二章 返航')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'workbench remains reachable and renders at desktop and narrow sizes',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(tester);
      final book = await harness.seedBook();
      await _pumpUntil(
        tester,
        () => find.text(book.meta.title).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(book.meta.title));
      await _pumpUntil(
        tester,
        () => find.text(zh.editorSaved).evaluate().isNotEmpty,
      );

      await _setSize(tester, const Size(1280, 900));
      expect(find.text(zh.editorBookInfo), findsOneWidget);
      expect(find.text(zh.editorSaved).hitTestable(), findsOneWidget);
      expect(find.byTooltip(zh.editorExport).hitTestable(), findsOneWidget);
      await _golden(
        find.byKey(workbenchAppGoldenBoundaryKey),
        'goldens/workbench-dark-1280x900.png',
      );
      expect(tester.takeException(), isNull);

      await _setSize(tester, const Size(2560, 1440));
      // The reading column caps at ~40 CJK ems no matter how wide the window
      // gets; the column itself is centered in the pane.
      expect(
        tester.getSize(_paragraphFieldWithText('门边放着一封信。')).width,
        closeTo(AppLayout.readingMaxChars * AppTypography.readingFont, 1),
      );
      await _golden(
        find.byKey(workbenchAppGoldenBoundaryKey),
        'goldens/workbench-dark-2560x1440.png',
      );
      expect(tester.takeException(), isNull);

      await _setSize(tester, const Size(960, 900));
      expect(find.byTooltip(zh.editorBookInfo).hitTestable(), findsOneWidget);
      expect(find.byTooltip(zh.editorExport).hitTestable(), findsOneWidget);
      expect(find.text(zh.editorSaved).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _setSize(tester, const Size(959, 900));
      await _openChapterDrawer(
        tester,
        book.chapters.firstWhere((c) => !c.isVolume),
      );
      expect(tester.takeException(), isNull);
      await _closeChapterDrawer(tester, const Size(959, 900));

      await _setSize(tester, const Size(520, 900));
      expect(find.byTooltip(zh.editorExport).hitTestable(), findsOneWidget);
      expect(find.text(zh.editorSaved).hitTestable(), findsOneWidget);
      await _golden(
        find.byKey(workbenchAppGoldenBoundaryKey),
        'goldens/workbench-dark-520x900.png',
      );
      await _openChapterDrawer(
        tester,
        book.chapters.firstWhere((c) => !c.isVolume),
      );
      await _closeChapterDrawer(tester, const Size(520, 900));
      expect(tester.takeException(), isNull);

      await _setSize(tester, const Size(320, 900));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      // Below 420px the export action lives in the overflow menu.
      expect(
        find.byTooltip(zh.editorWorkbenchMoreActions).hitTestable(),
        findsOneWidget,
      );
      expect(find.text(zh.editorSaved).hitTestable(), findsOneWidget);
      await _golden(
        find.byKey(workbenchAppGoldenBoundaryKey),
        'goldens/workbench-dark-320x900-text-2x.png',
      );
      await _openChapterDrawer(
        tester,
        book.chapters.firstWhere((c) => !c.isVolume),
      );
      await _closeChapterDrawer(tester, const Size(320, 900));
      expect(tester.takeException(), isNull);

      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(zh.editorWorkbenchMoreActions).hitTestable(),
        findsOneWidget,
      );
      expect(find.text(zh.editorSaved).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await _setSize(tester, const Size(1280, 900));
      final Chapter first = book.chapters.firstWhere((c) => !c.isVolume);
      await tester.pumpAndSettle();
      expect(find.text(first.title).hitTestable(), findsWidgets);
      expect(find.text(zh.editorSaved).hitTestable(), findsOneWidget);
      expect(find.byTooltip(zh.editorExport).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'light workbench renders at desktop',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(
        tester,
        appearance: const Appearance(themeMode: AppThemeMode.light),
      );
      final book = await harness.seedBook();
      await _pumpUntil(
        tester,
        () => find.text(book.meta.title).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(book.meta.title));
      await _pumpUntil(
        tester,
        () => find.text(zh.editorSaved).evaluate().isNotEmpty,
      );

      expect(find.byTooltip(zh.editorExport).hitTestable(), findsOneWidget);
      expect(find.text(zh.editorSaved).hitTestable(), findsOneWidget);
      await _golden(
        find.byKey(workbenchAppGoldenBoundaryKey),
        'goldens/workbench-light-1280x900.png',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _golden(Finder finder, String path) async {
  if (!_goldenFontsReady) {
    debugPrint('UNVERIFIED golden: $path (Noto CJK fonts missing)');
    return;
  }
  await expectLater(finder, matchesGoldenFile(path));
}

Finder _paragraphFieldWithText(String text) => find.byWidgetPredicate(
  (Widget widget) => widget is TextField && widget.controller?.text == text,
  description: 'editable paragraph containing "$text"',
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  // Repository/import work runs on the real async event loop. Advancing only
  // FakeAsync's clock can leave a loading route spinning forever, so poll with
  // a bounded real delay and pump frames until the observable UI is present.
  //
  // The budget is wall-clock rather than a fixed number of attempts: importing
  // a book and opening the editor takes noticeably longer on Windows (debug VM,
  // temp-dir I/O, background database isolate) and a fixed attempt count made
  // the test flaky across hosts instead of reporting a real regression.
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(Duration.zero);
  }
  expect(condition(), isTrue, reason: 'UI did not reach the expected state');
  await tester.pumpAndSettle();
}

Future<void> _waitForStoredParagraph(
  WidgetTester tester,
  WorkbenchUiHarness harness,
  String bookId,
  String chapterId,
  String text, {
  required int expectedSaveAttempts,
}) async {
  // Give the editor's debounce a fake-clock interval, then let SQLite IO
  // progress on the real event loop while the widget tree continues to pump.
  await tester.pump(const Duration(milliseconds: 1100));
  await _pumpUntil(
    tester,
    () =>
        harness.repository.saveAttempts >= expectedSaveAttempts &&
        find.text(zh.editorSaved).evaluate().isNotEmpty,
  );
  final chapter = await harness.loadChapter(bookId, chapterId);
  expect(chapter?.blocks.whereType<TextBlock>().firstOrNull?.text, text);
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _openChapterDrawer(
  WidgetTester tester,
  Chapter firstChapter,
) async {
  await tester.tap(find.byTooltip(zh.editorChapters));
  await tester.pumpAndSettle();
  expect(find.text(firstChapter.title).hitTestable(), findsWidgets);
}

Future<void> _closeChapterDrawer(WidgetTester tester, Size size) async {
  await tester.tapAt(Offset(size.width - 1, size.height / 2));
  await tester.pumpAndSettle();
}
