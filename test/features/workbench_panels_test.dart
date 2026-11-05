import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookloom/core/app_info.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/settings/workbench_preferences.dart';
import 'package:bookloom/core/storage/book_backup.dart';
import 'package:bookloom/core/storage/settings_store.dart';
import 'package:bookloom/design/tokens/app_typography.dart';
import 'package:bookloom/features/editor/presentation/editor_page.dart';
import 'package:bookloom/features/editor/presentation/proofreading_panel.dart';
import 'package:bookloom/features/preview/reading_preview.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/pump_bookloom.dart' show testBookloomWidgets;
import '../support/workbench_ui_harness.dart';

final AppLocalizations _zh = lookupAppLocalizations(const Locale('zh'));
bool _panelScreenshotFontsReady = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final Map<String, String> fontPaths = <String, String>{
      AppTypography.sans:
          '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      AppTypography.serif:
          '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
    };
    for (final String path in fontPaths.values) {
      if (!await File(path).exists()) {
        debugPrint(
          'Panel screenshots unverified: local Noto CJK fonts are unavailable.',
        );
        return;
      }
    }
    for (final MapEntry<String, String> entry in fontPaths.entries) {
      final FontLoader loader = FontLoader(entry.key)
        ..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(await File(entry.value).readAsBytes()),
          ),
        );
      await loader.load();
    }
    final FontLoader materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await materialIcons.load();
    _panelScreenshotFontsReady = true;
  });

  testBookloomWidgets(
    'backup restore exposes its budget and a same-ID conflict choice',
    (WidgetTester tester) async {
      debugPrint('[backup-panel] setup:start');
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(
        tester,
        size: const Size(520, 900),
      );
      final book = await harness.seedBook();
      // Build the real archive before BookDataPage starts its storage refresh;
      // both use this repository, and the UI fixture should not overlap their
      // initial SQLite reads under the widget test's FakeAsync zone.
      debugPrint('[backup-panel] backup:start');
      final Uint8List backupBytes = await _backupBytes(
        tester,
        harness,
        book.id,
      );
      debugPrint('[backup-panel] backup:ready');
      await _openSettings(tester);
      final Finder manageData = find.text(_zh.workbenchOpenData);
      await tester.ensureVisible(manageData);
      await tester.tap(manageData);
      await _pumpUntil(
        tester,
        () => find.text(_zh.dataWorkbenchBackupTitle).evaluate().isNotEmpty,
      );
      debugPrint('[backup-panel] data-open:ready');

      final Finder budget = _textFieldWithLabel(_zh.dataWorkbenchBackupMaxData);
      await tester.ensureVisible(budget);
      expect(budget.hitTestable(), findsOneWidget);
      expect(find.text(_zh.dataWorkbenchBackupMaxDataHelp), findsOneWidget);

      final Finder selectBackup = find.text(
        _zh.dataWorkbenchBackupChooseInspect,
      );
      await tester.ensureVisible(selectBackup);

      await tester.enterText(budget, '0');
      final int pickCountBeforeInvalidBudget = harness.files.pickCount;
      await tester.ensureVisible(selectBackup);
      await tester.tap(selectBackup);
      await _pumpUntil(
        tester,
        () => find
            .text(_zh.dataWorkbenchBackupInvalidBudget)
            .evaluate()
            .isNotEmpty,
      );
      expect(harness.files.pickCount, pickCountBeforeInvalidBudget);

      await tester.enterText(budget, '16');
      harness.files.nextPickedInputs = <PickedInput>[
        PickedInput(
          name: 'same-book.bookloom',
          size: backupBytes.length,
          openRead: () => Stream<List<int>>.value(backupBytes),
        ),
      ];
      await tester.ensureVisible(selectBackup);
      debugPrint('[backup-panel] prepare:start');
      await tester.tap(selectBackup);
      await _pumpUntil(
        tester,
        () => find
            .text(_zh.dataWorkbenchBackupConflictPolicy)
            .evaluate()
            .isNotEmpty,
      );
      debugPrint('[backup-panel] preview:ready');
      await tester.ensureVisible(
        find.text(_zh.dataWorkbenchBackupConflictPolicy),
      );
      await _capturePanelScreenshot(tester, 'panels-backup-preview.png');

      expect(harness.files.lastMultiple, isFalse);
      expect(harness.files.lastExtensions, <String>['bookloom']);
      expect(
        find.textContaining(_zh.dataWorkbenchBackupValidated(1, '')),
        findsOneWidget,
      );
      debugPrint('[backup-panel] policy:ensure-visible:start');
      await tester.ensureVisible(find.text(_zh.dataWorkbenchBackupKeepBoth));
      debugPrint('[backup-panel] policy:ensure-visible:done');
      expect(
        find.text(_zh.dataWorkbenchBackupKeepBoth).hitTestable(),
        findsOneWidget,
      );
      debugPrint('[backup-panel] policy:choose:start');
      await _chooseDropdown(
        tester,
        _zh.dataWorkbenchBackupKeepBoth,
        _zh.dataWorkbenchBackupSkipConflicts,
      );
      debugPrint('[backup-panel] policy:choose:done');

      final Finder restore = find.text(_zh.dataWorkbenchBackupConfirmRestore);
      debugPrint('[backup-panel] restore:ensure-visible:start');
      await tester.ensureVisible(restore);
      debugPrint('[backup-panel] restore:ensure-visible:done');
      expect(restore.hitTestable(), findsOneWidget);
      debugPrint('[backup-panel] restore:start');
      await tester.tap(restore);
      await _pumpUntil(
        tester,
        () => find
            .textContaining(_zh.dataWorkbenchBackupSkipped(1))
            .evaluate()
            .isNotEmpty,
      );
      debugPrint('[backup-panel] restore:ready');
      expect(
        find.textContaining(_zh.dataWorkbenchBackupRestored(0)),
        findsOneWidget,
      );
      expect(
        find.textContaining(_zh.dataWorkbenchBackupSkipped(1)),
        findsOneWidget,
      );
      expect(await harness.listSummaries(), hasLength(1));
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testBookloomWidgets(
    'Markdown default reaches batch and library export entry points',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(tester);
      await harness.seedBook();
      await _openSettings(tester);

      final Finder defaultFormat = find.text(
        _zh.bookWorkbenchDefaultExportFormat,
      );
      await tester.ensureVisible(defaultFormat);
      await _chooseDefaultExportFormat(tester, 'Markdown');
      await _pumpUntil(
        tester,
        () => find.text('Markdown').evaluate().isNotEmpty,
      );
      final WorkbenchPreferences? savedDefaults = await tester.runAsync(
        () => WorkbenchPreferences.read(harness.settingsStore),
      );
      expect(savedDefaults?.exportFormat, ExportFormat.markdown);

      await _selectShellTab(tester, _zh.navImport);
      await _openBatch(tester);
      await _chooseDropdown(
        tester,
        _zh.dataWorkbenchBatchAddToLibrary,
        _zh.dataWorkbenchBatchConvertFiles,
      );
      await _pumpUntil(
        tester,
        () => find.text('Markdown').evaluate().isNotEmpty,
      );
      expect(find.text('Markdown').hitTestable(), findsOneWidget);

      // /batch is a root-navigator route above the shell, so tab controls are
      // not interactive until a system-back event pops that route.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await _pumpUntil(
        tester,
        () => find.text(_zh.navImport).hitTestable().evaluate().isNotEmpty,
      );
      await _selectShellTab(tester, _zh.navSettings);
      final Finder manageData = find.text(_zh.workbenchOpenData);
      await tester.ensureVisible(manageData);
      await tester.tap(manageData);
      await _pumpUntil(
        tester,
        () => find.text(_zh.dataWorkbenchLibraryTitle).evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.text(_zh.dataWorkbenchLibraryTitle));
      await _pumpUntil(
        tester,
        () => find.text('Markdown').hitTestable().evaluate().isNotEmpty,
      );
      expect(find.text('Markdown').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testBookloomWidgets(
    'a late batch default does not replace the format the user chose',
    (WidgetTester tester) async {
      late final _GatedSettingsStore gatedStore;
      await WorkbenchUiHarness.pump(
        tester,
        settingsStoreFactory: (database) =>
            gatedStore = _GatedSettingsStore(database),
      );
      await tester.runAsync(
        () =>
            WorkbenchPreferences(exportFormat: ExportFormat.markdown)
                .write(gatedStore),
      );

      await _selectShellTab(tester, _zh.navImport);
      await _openBatch(tester);
      await _pumpUntil(
        tester,
        () => find.text(_zh.dataWorkbenchBatchTitle).evaluate().isNotEmpty,
      );
      await tester.runAsync(
        () => gatedStore.readStarted.future.timeout(const Duration(seconds: 5)),
      );

      await _chooseDropdown(
        tester,
        _zh.dataWorkbenchBatchAddToLibrary,
        _zh.dataWorkbenchBatchConvertFiles,
      );
      await _chooseDropdown(tester, 'EPUB 3', 'EPUB 2');
      gatedStore.releaseDefaults();
      await _pumpUntil(
        tester,
        () => find.text('EPUB 2').hitTestable().evaluate().isNotEmpty,
      );

      expect(find.text('EPUB 2').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testBookloomWidgets(
    'rapid default-format choices persist the latest complete preference',
    (WidgetTester tester) async {
      late final _GatedSettingsStore gatedStore;
      await WorkbenchUiHarness.pump(
        tester,
        size: const Size(320, 900),
        settingsStoreFactory: (database) =>
            gatedStore = _GatedSettingsStore(database),
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpUiFrames(tester);
      await _openSettings(tester);
      await tester.runAsync(
        () => gatedStore.readStarted.future.timeout(const Duration(seconds: 5)),
      );
      gatedStore.releaseDefaults();
      await _pumpUntil(
        tester,
        () => find
            .byWidgetPredicate((widget) => widget is DropdownMenu<ExportFormat>)
            .evaluate()
            .isNotEmpty,
      );

      gatedStore.gateDefaultWrites();
      await _chooseDefaultExportFormat(tester, 'Markdown');
      await tester.runAsync(
        () =>
            gatedStore.writeStarted.future.timeout(const Duration(seconds: 5)),
      );
      await _chooseDefaultExportFormat(tester, 'EPUB 2');
      expect(find.text('EPUB 2').hitTestable(), findsOneWidget);

      gatedStore.releaseWrites();
      await _pumpUntilStored(tester, () async {
        final WorkbenchPreferences preferences =
            await WorkbenchPreferences.read(gatedStore);
        return preferences.exportFormat == ExportFormat.epub2;
      });
      expect(gatedStore.defaultWriteCount, 2);
      await _capturePanelScreenshot(tester, 'panels-defaults-320-2x.png');
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testBookloomWidgets(
    'cancelled batch ZIP save keeps converted results available',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(tester);
      await _selectShellTab(tester, _zh.navImport);
      await _openBatch(tester);

      expect(find.text(_zh.dataWorkbenchBatchSubtitle), findsOneWidget);
      await _chooseDropdown(
        tester,
        _zh.dataWorkbenchBatchAddToLibrary,
        _zh.dataWorkbenchBatchConvertFiles,
      );
      await tester.tap(find.text(_zh.dataWorkbenchBatchChooseFiles));
      await _pumpUntil(
        tester,
        () => find
            .text(_zh.dataWorkbenchBatchSelectedFiles(1))
            .evaluate()
            .isNotEmpty,
      );
      expect(harness.files.lastMultiple, isTrue);

      final Finder start = find.text(_zh.dataWorkbenchBatchStart);
      await tester.ensureVisible(start);
      await tester.tap(start);
      await _pumpUntil(
        tester,
        () =>
            find
                .text(_zh.dataWorkbenchBatchSummary(1, 0, 1))
                .evaluate()
                .isNotEmpty &&
            find.text(_zh.dataWorkbenchStatusSuccess).evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.text(_zh.dataWorkbenchBatchQueue));
      await _capturePanelScreenshot(tester, 'panels-batch-queue.png');
      expect(await harness.listSummaries(), isEmpty);

      harness.files.cancelNextSave = true;
      final Finder saveZip = find.widgetWithText(
        FilledButton,
        _zh.dataWorkbenchBatchSaveZip,
      );
      await tester.ensureVisible(saveZip);
      await _pumpUntil(tester, () => _filledButtonEnabled(saveZip));
      expect(saveZip.hitTestable(), findsOneWidget);
      await tester.tap(saveZip);
      await _pumpUntil(tester, () => harness.files.saveCount == 1);
      await _pumpUntil(
        tester,
        () => find
            .text(_zh.dataWorkbenchBatchSaveCancelled)
            .evaluate()
            .isNotEmpty,
      );
      expect(harness.files.savedExports, isEmpty);

      await tester.ensureVisible(saveZip);
      await _pumpUntil(tester, () => _filledButtonEnabled(saveZip));
      expect(saveZip.hitTestable(), findsOneWidget);
      await tester.tap(saveZip);
      await _pumpUntil(tester, () => harness.files.saveCount == 2);
      await _pumpUntil(tester, () => harness.files.savedExports.length == 1);
      await _pumpUntil(
        tester,
        () => find.text(_zh.dataWorkbenchZipSaved).evaluate().isNotEmpty,
      );
      expect(harness.files.savedExports, hasLength(1));
      expect(await harness.listSummaries(), isEmpty);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testBookloomWidgets(
    'metadata, layout, cover and reading preview stay editable on a narrow screen',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(
        tester,
        size: const Size(520, 900),
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpUiFrames(tester);
      final book = await harness.seedBook();
      await _openBook(tester, book.meta.title);

      await tester.tap(find.byTooltip(_zh.editorBookInfo));
      await _pumpUntil(
        tester,
        () => find.text(_zh.bookWorkbenchSettings).evaluate().isNotEmpty,
      );

      final Finder title = _textFieldWithLabel(_zh.editorBookTitle);
      await tester.ensureVisible(title);
      await _pumpUiFrames(tester);
      expect(title.hitTestable(), findsOneWidget);
      await tester.enterText(title, '海风·校订版');
      await _chooseSettingSection(
        tester,
        _zh.bookWorkbenchMetadata,
        _zh.bookWorkbenchLayoutFonts,
      );
      final Finder indent = find.text(_zh.bookWorkbenchTwoCharacterIndent);
      await tester.ensureVisible(indent);
      await _pumpUiFrames(tester);
      expect(indent.hitTestable(), findsOneWidget);
      await tester.tap(indent);

      await _chooseSettingSection(
        tester,
        _zh.bookWorkbenchLayoutFonts,
        _zh.bookWorkbenchCover,
      );
      await _chooseDropdown(
        tester,
        _zh.bookWorkbenchAuto,
        _zh.bookWorkbenchSea,
      );
      await _chooseSettingSection(
        tester,
        _zh.bookWorkbenchCover,
        _zh.bookWorkbenchReadingPreview,
      );
      final previewParagraph = find.descendant(
        of: find.byType(ReadingPreview),
        matching: find.text('门边放着一封信。'),
      );
      await tester.ensureVisible(previewParagraph);
      await _pumpUiFrames(tester);
      expect(find.byType(ReadingPreview), findsOneWidget);
      expect(previewParagraph.hitTestable(), findsOneWidget);
      await _capturePanelScreenshot(tester, 'panels-metadata-520-2x.png');

      await _pumpUntilStored(tester, () async {
        final stored = await harness.repository.loadBook(book.id);
        return stored?.meta.title == '海风·校订版' &&
            stored?.layout.indent == false &&
            stored?.coverOptions.palette == 'sea';
      });
      final stored = await tester.runAsync(
        () => harness.repository.loadBook(book.id),
      );
      expect(stored?.meta.title, '海风·校订版');
      expect(stored?.layout.indent, isFalse);
      expect(stored?.coverOptions.palette, 'sea');
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testBookloomWidgets(
    'proofreading preview applies and undoes one replacement on a 320px 2x screen',
    (WidgetTester tester) async {
      final WorkbenchUiHarness harness = await WorkbenchUiHarness.pump(
        tester,
        size: const Size(320, 900),
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpUiFrames(tester);
      final book = await harness.seedBook();
      await _openBook(tester, book.meta.title);

      final Finder moreActions = find.byTooltip(_zh.editorWorkbenchMoreActions);
      await tester.ensureVisible(moreActions);
      await _pumpUiFrames(tester);
      expect(moreActions.hitTestable(), findsOneWidget);
      await tester.tap(moreActions);
      await _pumpUiFrames(tester);
      await _pumpUntil(
        tester,
        () => find
            .text(_zh.editorWorkbenchTools)
            .hitTestable()
            .evaluate()
            .isNotEmpty,
      );
      final Finder toolsLabel = find.text(_zh.editorWorkbenchTools);
      final Finder toolsOption = _menuEntryForText(toolsLabel);
      await _pumpUntil(
        tester,
        () => toolsOption.hitTestable().evaluate().isNotEmpty,
      );
      expect(toolsOption.hitTestable(), findsWidgets);
      await tester.tap(toolsOption);
      await _pumpUntil(tester, () => toolsOption.evaluate().isEmpty);
      await _pumpUntil(
        tester,
        () => find.byType(ProofreadingPanel).evaluate().isNotEmpty,
      );
      final Finder replaceSection = find.text(_zh.editorWorkbenchFindReplace);
      final toolsScrollable = find
          .descendant(
            of: find.byType(ProofreadingPanel),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        replaceSection,
        250,
        scrollable: toolsScrollable,
      );
      await _pumpUiFrames(tester);
      expect(replaceSection.hitTestable(), findsOneWidget);
      await tester.tap(replaceSection);
      await _pumpUiFrames(tester);

      final Finder findField = _textFieldWithLabel(_zh.editorWorkbenchFindText);
      final Finder replaceField = _textFieldWithLabel(
        _zh.editorWorkbenchReplaceWith,
      );
      await tester.ensureVisible(findField);
      await _pumpUiFrames(tester);
      expect(findField.hitTestable(), findsOneWidget);
      await tester.enterText(findField, '一封');
      await tester.ensureVisible(replaceField);
      await _pumpUiFrames(tester);
      await tester.enterText(replaceField, '两封');
      final Finder preview = find.text(_zh.editorWorkbenchPreviewReplace);
      await tester.ensureVisible(preview);
      await _pumpUiFrames(tester);
      expect(preview.hitTestable(), findsOneWidget);
      await tester.tap(preview);
      await _pumpUntil(
        tester,
        () => find
            .text(_zh.editorWorkbenchPreviewStats(1, 1))
            .evaluate()
            .isNotEmpty,
      );
      final chapter = book.chapters.first;
      expect(
        (await harness.loadChapter(
          book.id,
          chapter.id,
        ))!.blocks.whereType<TextBlock>().first.text,
        '门边放着一封信。',
      );

      final Finder apply = find.text(_zh.editorWorkbenchApplyOneUndo);
      await tester.ensureVisible(apply);
      await _pumpUiFrames(tester);
      expect(apply.hitTestable(), findsOneWidget);
      await _capturePanelScreenshot(tester, 'panels-tools-320-2x.png');
      await tester.tap(apply);
      await _pumpUntilStored(tester, () async {
        final stored = await harness.repository.loadChapter(
          book.id,
          chapter.id,
        );
        return stored?.blocks.whereType<TextBlock>().firstOrNull?.text ==
            '门边放着两封信。';
      });
      expect(
        (await harness.loadChapter(
          book.id,
          chapter.id,
        ))!.blocks.whereType<TextBlock>().first.text,
        '门边放着两封信。',
      );

      expect(await tester.binding.handlePopRoute(), isTrue);
      await _pumpUntil(
        tester,
        () => find.byType(ProofreadingPanel).evaluate().isEmpty,
      );
      final Finder undo = find.byTooltip(_zh.editorUndo);
      await tester.ensureVisible(undo);
      await _pumpUiFrames(tester);
      expect(undo.hitTestable(), findsOneWidget);
      await tester.tap(undo);
      await _pumpUntilStored(tester, () async {
        final stored = await harness.repository.loadChapter(
          book.id,
          chapter.id,
        );
        return stored?.blocks.whereType<TextBlock>().firstOrNull?.text ==
            '门边放着一封信。';
      });
      expect(
        (await harness.loadChapter(
          book.id,
          chapter.id,
        ))!.blocks.whereType<TextBlock>().first.text,
        '门边放着一封信。',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

class _GatedSettingsStore extends SettingsStore {
  _GatedSettingsStore(super.database);

  final Completer<void> readStarted = Completer<void>();
  final Completer<void> _releaseRead = Completer<void>();
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> _releaseWrite = Completer<void>();
  bool _gateWrites = false;
  int defaultWriteCount = 0;

  @override
  Future<String?> read(String key) async {
    if (key == 'workbench.defaults' && !_releaseRead.isCompleted) {
      if (!readStarted.isCompleted) readStarted.complete();
      await _releaseRead.future;
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (key == 'workbench.defaults') {
      defaultWriteCount++;
      if (_gateWrites && !_releaseWrite.isCompleted) {
        if (!writeStarted.isCompleted) writeStarted.complete();
        await _releaseWrite.future;
      }
    }
    await super.write(key, value);
  }

  void releaseDefaults() {
    if (!_releaseRead.isCompleted) _releaseRead.complete();
  }

  void gateDefaultWrites() {
    _gateWrites = true;
  }

  void releaseWrites() {
    if (!_releaseWrite.isCompleted) _releaseWrite.complete();
  }
}

Future<void> _openSettings(WidgetTester tester) async {
  await _selectShellTab(tester, _zh.navSettings);
  await _pumpUntil(
    tester,
    () => find.text(_zh.workbenchOpenData).evaluate().isNotEmpty,
  );
}

Future<void> _openBatch(WidgetTester tester) async {
  final Finder open = find.text(_zh.workbenchOpenBatch);
  await tester.ensureVisible(open);
  await tester.tap(open);
  await _pumpUntil(
    tester,
    () => find.text(_zh.dataWorkbenchBatchTitle).evaluate().isNotEmpty,
  );
}

Future<void> _openBook(WidgetTester tester, String title) async {
  await _pumpUntil(tester, () => find.text(title).evaluate().isNotEmpty);
  final Finder bookRow = find.text(title).first;
  await tester.ensureVisible(bookRow);
  await tester.tap(bookRow);
  await _pumpUntil(
    tester,
    () =>
        find.byType(EditorPage).evaluate().isNotEmpty &&
        find.text(_zh.editorSaved).evaluate().isNotEmpty,
  );
}

Future<void> _selectShellTab(WidgetTester tester, String label) async {
  final Finder tab = find.text(label).last;
  if (!tab.hitTestable().evaluate().isNotEmpty) await tester.ensureVisible(tab);
  await tester.tap(tab);
  await _pumpUiFrames(tester);
}

Future<void> _chooseSettingSection(
  WidgetTester tester,
  String current,
  String next,
) => _chooseDropdown(tester, current, next);

Future<void> _chooseDropdown(
  WidgetTester tester,
  String current,
  String next,
) async {
  final Finder selected = find.text(current).last;
  await tester.ensureVisible(selected);
  await _pumpUiFrames(tester);
  expect(selected.hitTestable(), findsOneWidget);
  await tester.tap(selected);
  await _pumpUntil(
    tester,
    () => find.text(next).hitTestable().evaluate().isNotEmpty,
  );
  final Finder option = find.text(next).hitTestable().last;
  await tester.ensureVisible(option);
  await _pumpUiFrames(tester);
  await tester.tap(option);
  await _pumpUiFrames(tester);
}

Future<void> _chooseDefaultExportFormat(
  WidgetTester tester,
  String next,
) async {
  final Finder dropdown = find.byWidgetPredicate(
    (Widget widget) => widget is DropdownMenu<ExportFormat>,
    description: 'default export format selector',
  );
  expect(dropdown, findsOneWidget);
  final Finder input = find.descendant(
    of: dropdown,
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(input);
  await _pumpUiFrames(tester);
  expect(input.hitTestable(), findsOneWidget);
  await tester.tap(input);

  final Finder options = find.text(next).hitTestable();
  await _pumpUntil(tester, () => options.evaluate().isNotEmpty);
  final Finder option = options.last;
  await tester.ensureVisible(option);
  await _pumpUiFrames(tester);
  expect(option.hitTestable(), findsWidgets);
  await tester.tap(option);
  await _pumpUiFrames(tester);
}

Finder _menuEntryForText(Finder text) => find.ancestor(
  of: text,
  matching: find.byWidgetPredicate(
    (Widget widget) =>
        widget is MenuItemButton ||
        widget is DropdownMenuItem ||
        widget is PopupMenuItem,
  ),
);

Finder _textFieldWithLabel(String label) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is TextField && widget.decoration?.labelText == label,
  description: 'text field labelled "$label"',
);

bool _filledButtonEnabled(Finder finder) => finder.evaluate().any((element) {
  final Widget widget = element.widget;
  return widget is FilledButton && widget.onPressed != null;
});

Future<Uint8List> _backupBytes(
  WidgetTester tester,
  WorkbenchUiHarness harness,
  String bookId,
) async {
  final Completer<void> done = Completer<void>();
  Uint8List? bytes;
  Object? failure;
  StackTrace? failureStack;

  // Start the real database + worker operation in the real async zone, then
  // return to the widget test so FakeAsync timers and Drift query callbacks
  // can make progress while the archive is being prepared.
  await tester.runAsync(() async {
    unawaited(
      _exportBackupBytes(harness, bookId).then<void>(
        (result) {
          bytes = result;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          failure = error;
          failureStack = stack;
          done.complete();
        },
      ),
    );
  });

  for (var attempt = 0; attempt < 300 && !done.isCompleted; attempt++) {
    await tester.pump(Duration.zero);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(Duration.zero);
  }
  if (!done.isCompleted) {
    throw TimeoutException(
      'Timed out while preparing the backup fixture',
      const Duration(seconds: 6),
    );
  }
  if (failure case final error?) {
    Error.throwWithStackTrace(error, failureStack!);
  }
  return bytes ?? (throw StateError('Backup worker completed without bytes'));
}

Future<Uint8List> _exportBackupBytes(
  WorkbenchUiHarness harness,
  String bookId,
) async {
  final Directory scratch = Directory(
    p.join(harness.paths.cache.path, 'ui-backup-fixture'),
  );
  await scratch.create(recursive: true);
  final File output = File(p.join(harness.root.path, 'same-book.bookloom'));
  final BackgroundJobs jobs = BackgroundJobs();
  try {
    final BookBackup backup = BookBackup(
      harness.repository,
      scratchDirectory: scratch,
      appVersion: AppInfo.version,
      jobs: jobs,
    );
    final File archive = await backup.exportBooks(
      <String>[bookId],
      output.path,
      includeSources: false,
    );
    return await archive.readAsBytes();
  } finally {
    jobs.dispose();
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    if (condition()) {
      await _pumpUiFrames(tester);
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: 'UI did not reach the expected state');
  await _pumpUiFrames(tester);
}

Future<void> _pumpUntilStored(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  bool pending = false;
  bool? result;
  Object? failure;
  StackTrace? failureStack;
  for (var attempt = 0; attempt < 250; attempt++) {
    if (!pending && result == null) {
      pending = true;
      // A query can wait for a transaction begun by the UI's fake-clock zone.
      // Start the real I/O without blocking the fake frames it needs to finish.
      await tester.runAsync(() async {
        unawaited(
          condition().then<void>(
            (value) {
              result = value;
              pending = false;
            },
            onError: (Object error, StackTrace stack) {
              failure = error;
              failureStack = stack;
              pending = false;
            },
          ),
        );
      });
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
    if (result == true) {
      await _pumpUiFrames(tester);
      return;
    }
    if (result == false) result = null;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Stored data did not reach the expected state');
}

/// Advances finite page, menu, and tab transitions without waiting forever
/// for unrelated animated progress indicators. Real async work is given a
/// short turn between fake-clock frames so Drift/isolate events can dispatch.
Future<void> _pumpUiFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  await tester.pump(Duration.zero);
}

Future<void> _capturePanelScreenshot(
  WidgetTester tester,
  String basename,
) async {
  final String? screenshotDirectory = Platform
      .environment['BOOKLOOM_PANEL_SCREENSHOT_DIR']
      ?.trim();
  if (screenshotDirectory == null || screenshotDirectory.isEmpty) {
    debugPrint(
      'Panel screenshot skipped: set BOOKLOOM_PANEL_SCREENSHOT_DIR to enable.',
    );
    return;
  }
  final String path = p.join(screenshotDirectory, basename);
  if (!_panelScreenshotFontsReady) {
    debugPrint('UNVERIFIED panel screenshot: $path (fonts unavailable)');
    return;
  }
  await _pumpUiFrames(tester);
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(workbenchAppGoldenBoundaryKey),
  );
  // The renderer/image futures complete outside Flutter's fake clock. Keep
  // their entire async chain in runAsync so subsequent guarded tester calls do
  // not wait for a fake-microtask continuation that cannot run on its own.
  final bool? written = await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) throw StateError('Could not encode panel screenshot');
      final Uint8List bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final File file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } finally {
      image.dispose();
    }
  });
  if (written != true) throw StateError('Could not write $path');
  debugPrint('Panel screenshot saved: $path');
}
