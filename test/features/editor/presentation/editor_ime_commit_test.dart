import 'dart:convert';
import 'dart:io';

import 'package:bookloom/app/ai_providers.dart';
import 'package:bookloom/app/rule_providers.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/components/app_select_field.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/ai_proofreading_task.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:bookloom/features/editor/presentation/ai_proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/ai_rule_creation_panel.dart';
import 'package:bookloom/features/editor/presentation/editor_page.dart';
import 'package:bookloom/features/editor/presentation/proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/rule_workbench_panel.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../support/pump_bookloom.dart';

void main() {
  for (final selectionEntry in <bool>[false]) {
    testBookloomWidgets(
      'joint rules EditorPage ${selectionEntry ? 'selection menu' : 'proofreading'} save returns to mounted AI',
      (tester) async {
        final harness = await _EditorHarness.pump(tester, jointRules: true);
        final l10n = lookupAppLocalizations(const Locale('zh'));
        // The paragraph context menu no longer opens the AI advertisement
        // panel directly; the proofreading chip is the remaining entry.
        await tester.tap(find.byTooltip(l10n.editorWorkbenchTools));
        await _pumpUntil(
          tester,
          () => find.byType(ProofreadingPanel).evaluate().isNotEmpty,
          'proofreading modal',
        );
        final chip = find.widgetWithText(FilterChip, l10n.aiProofreadingTitle);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await _pumpUntil(
          tester,
          () => find.byType(AiProofreadingPanel).evaluate().isNotEmpty,
          'AI panel',
        );
        final aiElement = tester.element(find.byType(AiProofreadingPanel));
        final panel = tester.widget<AiProofreadingPanel>(
          find.byType(AiProofreadingPanel),
        );
        final session = panel.session;
        final revision = session.saveSeq;
        final container = ProviderScope.containerOf(aiElement);
        final task = container.read(aiProofreadingTaskProvider(session));
        expect(panel.onUseRule, isNotNull);
        await _tapJointPanel(tester, AiProofreadingPanel, 'ai-request-rules');
        final field = find.byKey(const ValueKey('ai-rule-positive'));
        await tester.ensureVisible(field);
        await tester.enterText(field, '原始');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await _tapJointPanel(tester, AiProofreadingPanel, 'ai-prepare');
        await _pumpUntil(
          tester,
          () => task.phase == AiProofreadingPhase.awaitingConsent,
          'joint consent',
        );
        await _tapJointPanel(tester, AiProofreadingPanel, 'ai-run');
        await _pumpUntil(
          tester,
          () => task.phase == AiProofreadingPhase.completed,
          'joint results',
        );
        expect(task.changes, hasLength(1));
        final proposal = task.ruleProposals.single;
        await _tapJointPanel(
          tester,
          AiProofreadingPanel,
          'ai-rule-tile-${proposal.proposalId}',
        );
        await _tapJointPanel(
          tester,
          AiProofreadingPanel,
          'ai-use-rule-${proposal.proposalId}',
        );
        await _pumpUntil(
          tester,
          () => find.byType(RuleWorkbenchPanel).evaluate().isNotEmpty,
          'nested rule workbench',
        );
        expect(aiElement.mounted, isTrue);
        final workbench = container.read(ruleWorkbenchTaskProvider(session));
        await _pumpUntil(
          tester,
          () => workbench.rules.isNotEmpty,
          'candidate loaded',
        );
        expect(workbench.trial, isNull);
        expect(session.saveSeq, revision);
        expect(session.dirty, isFalse);
        expect(harness.repository.saveAttempts, 0);
        await _tapJointPanel(tester, RuleWorkbenchPanel, 'rule-scan');
        await _pumpUntil(
          tester,
          () => workbench.hasCurrentTrial,
          'explicit trial',
        );
        await _tapJointPanel(tester, RuleWorkbenchPanel, 'rule-save');
        await _pumpUntil(
          tester,
          () => workbench.isSaved(proposal.rule.id),
          'explicit save-only',
        );
        await tester.tap(find.byType(CloseButton).last);
        await tester.pump(const Duration(milliseconds: 300));
        expect(aiElement.mounted, isTrue);
        expect(find.byType(AiProofreadingPanel), findsOneWidget);
        expect(task.canApply, isTrue);
        expect(session.saveSeq, revision);
        expect(harness.repository.saveAttempts, 0);
        await _tapJointPanel(
          tester,
          AiProofreadingPanel,
          'ai-change-${task.changes.single.id}',
        );
        await _tapJointPanel(tester, AiProofreadingPanel, 'ai-apply-selected');
        await _pumpUntil(
          tester,
          () => task.phase == AiProofreadingPhase.applied,
          'body applied after rule save',
        );
        expect(task.canUseRuleProposals, isFalse);
        // Wide windows host the proofreading panel in the docked right pane,
        // whose close affordance is an IconButton, not a CloseButton.
        final closeTooltip = MaterialLocalizations.of(
          tester.element(find.byType(EditorPage)),
        ).closeButtonTooltip;
        await tester.tap(find.byTooltip(closeTooltip).first);
        await _pumpUntil(
          tester,
          () => _paragraphWithText('段落').evaluate().isNotEmpty,
          'updated editor',
        );
        await tester.runAsync(harness.beforeClose!);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final composing in [false, true]) {
    testBookloomWidgets(
      'toolbar undo and redo update focused text composing=$composing',
      (tester) async {
        await _EditorHarness.pump(tester);
        final l10n = lookupAppLocalizations(const Locale('zh'));
        final undo = find.widgetWithIcon(IconButton, Icons.undo_rounded);
        final redo = find.widgetWithIcon(IconButton, Icons.redo_rounded);
        Color? iconColor(IconData icon) => tester
            .widget<RichText>(
              find.descendant(
                of: find.byIcon(icon),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style
            ?.color;
        expect(tester.widget<IconButton>(undo).onPressed, isNull);
        expect(tester.widget<IconButton>(redo).onPressed, isNull);
        final disabledUndoColor = iconColor(Icons.undo_rounded);
        if (composing) {
          await _startComposition(tester, '修订正文');
        } else {
          await tester.enterText(_paragraphWithText('原始段落'), '修订正文');
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.widget<IconButton>(undo).onPressed, isNotNull);
        final enabledUndoColor = iconColor(Icons.undo_rounded);
        expect(enabledUndoColor, isNot(disabledUndoColor));
        await tester.tap(undo);
        await _pumpUntil(
          tester,
          () => _paragraphWithText('原始段落').evaluate().isNotEmpty,
          'undo restores paragraph',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(l10n.editorUndoDone), findsOneWidget);
        expect(tester.widget<IconButton>(redo).onPressed, isNotNull);
        expect(iconColor(Icons.redo_rounded), enabledUndoColor);
        await tester.tap(redo);
        await _pumpUntil(
          tester,
          () => _paragraphWithText('修订正文').evaluate().isNotEmpty,
          'redo restores focused text',
        );
        await tester.pump();
        expect(find.text(l10n.editorRedoDone), findsOneWidget);
        final field = tester.widget<TextField>(_paragraphWithText('修订正文'));
        expect(field.decoration?.filled, isFalse);
        expect(field.decoration?.contentPadding, EdgeInsets.zero);
        expect(field.decoration?.enabledBorder, InputBorder.none);
        expect(field.decoration?.focusedBorder, InputBorder.none);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testBookloomWidgets(
    'phone drawer remains usable after paragraph focus and chapter changes',
    (tester) async {
      await _EditorHarness.pump(
        tester,
        size: const Size(363, 844),
        platform: TargetPlatform.android,
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      await tester.showKeyboard(_paragraphWithText('原始段落'));
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.byTooltip(l10n.editorChapters));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '第二章'));
      await _pumpUntil(
        tester,
        () => _paragraphWithText('另一段落').evaluate().isNotEmpty,
        'second chapter after focused paragraph',
      );
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(
        find.byWidgetPredicate(
          (widget) => widget is Scaffold && widget.drawer != null,
        ),
      );
      expect(scaffold.isDrawerOpen, isFalse);
      await tester.tap(find.byTooltip(l10n.editorChapters));
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, isTrue);
      expect(find.widgetWithText(ListTile, '第一章'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'phone toolbar shares one row and system back closes drawer first',
    (tester) async {
      await _EditorHarness.pump(
        tester,
        size: const Size(363, 844),
        platform: TargetPlatform.android,
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      expect(find.byTooltip(l10n.editorBack), findsNothing);
      final undo = find.byTooltip(l10n.editorUndo);
      final redo = find.byTooltip(l10n.editorRedo);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text(l10n.editorEdit), findsNothing);
      expect(find.text(l10n.editorPreview), findsNothing);
      expect(tester.getCenter(undo).dy, closeTo(tester.getCenter(redo).dy, 1));
      expect(_paragraphWithText('原始段落'), findsOneWidget);
      // The title sits on the toolbar row; undo/redo share that row, the
      // save status label lives under the title.
      expect(
        tester.getTopLeft(undo).dy,
        lessThan(tester.getTopLeft(find.text(l10n.editorSaved)).dy),
      );
      expect(
        tester.getCenter(find.byTooltip(l10n.editorChapters)).dx,
        greaterThan(tester.getCenter(find.text('测试书')).dx),
      );
      await tester.tap(find.byTooltip(l10n.editorChapters));
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(
        find.byWidgetPredicate(
          (widget) => widget is Scaffold && widget.drawer != null,
        ),
      );
      expect(scaffold.isDrawerOpen, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, isFalse);
      expect(find.byType(EditorPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _pumpUntil(
        tester,
        () => find.text('打开编辑器').evaluate().isNotEmpty,
        'system back leaves editor',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets('phone controls remain reachable at 320px with 2x text', (
    tester,
  ) async {
    await _EditorHarness.pump(
      tester,
      size: const Size(320, 900),
      textScale: 2,
      platform: TargetPlatform.android,
    );
    final l10n = lookupAppLocalizations(const Locale('zh'));
    for (final tooltip in [
      l10n.editorChapters,
      l10n.editorUndo,
      l10n.editorRedo,
    ]) {
      expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.byTooltip(tooltip),
                matching: find.byType(IconButton),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(_paragraphWithText('原始段落').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets(
    'volumes collapse without editing and search reveals matching children',
    (tester) async {
      await _EditorHarness.pump(tester, chapters: _volumeChapters);
      final l10n = lookupAppLocalizations(const Locale('zh'));
      Finder chapterTile(String title) =>
          find.ancestor(of: find.text(title), matching: find.byType(ListTile));
      await tester.tap(chapterTile('第一卷'));
      await tester.pump();
      expect(chapterTile('第一章'), findsNothing);
      expect(chapterTile('第二章'), findsOneWidget);
      expect(_paragraphWithText('原始段落'), findsOneWidget);
      await tester.tap(chapterTile('第一卷'));
      await tester.pump();
      expect(chapterTile('第一章'), findsOneWidget);
      await tester.tap(chapterTile('第二卷'));
      await tester.pump();
      expect(chapterTile('第二章'), findsNothing);
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == l10n.editorSearchChapters,
      );
      await tester.enterText(search, '第二章');
      await tester.pump();
      expect(chapterTile('第二卷'), findsOneWidget);
      expect(chapterTile('第二章'), findsOneWidget);
      expect(chapterTile('第一卷'), findsNothing);
      await tester.tap(chapterTile('第二卷'));
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
      expect(chapterTile('第二章'), findsNothing);
      expect(_paragraphWithText('原始段落'), findsOneWidget);
      await tester.enterText(search, '第一卷');
      await tester.pump();
      expect(chapterTile('第一卷'), findsOneWidget);
      expect(chapterTile('第一章'), findsOneWidget);
      await tester.enterText(search, '2');
      await tester.pump();
      expect(chapterTile('第二卷'), findsOneWidget);
      expect(chapterTile('第二章'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pump();
      await tester.tap(find.text('测试书').first);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
      Focus.of(tester.element(find.byType(Scaffold).last)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await _pumpUntil(
        tester,
        () => _paragraphWithText('另一段落').evaluate().isNotEmpty,
        'keyboard skips volume headings',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final viewport in <({String name, Size size, double textScale})>[
    (name: '363px phone', size: const Size(363, 844), textScale: 1),
    (name: '520px phone', size: const Size(520, 844), textScale: 1),
    (name: 'desktop', size: const Size(1280, 900), textScale: 1),
    (name: '320px at 2x text', size: const Size(320, 900), textScale: 2),
  ]) {
    testBookloomWidgets('editor typography at ${viewport.name}', (
      tester,
    ) async {
      await _EditorHarness.pump(
        tester,
        size: viewport.size,
        textScale: viewport.textScale,
      );
      final compact = viewport.size.width < AppLayout.editorCompactBreakpoint;
      final headingSize = compact ? 18.0 : 21.0;
      final bodySize = compact ? 15.5 : 16.5;
      final headingPadding = compact ? AppSpacing.md : AppSpacing.lg;
      final paragraphGap = compact ? AppSpacing.md : AppSpacing.lg;

      final heading = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == '第一章' &&
            widget.style?.fontSize == headingSize,
      );
      expect(heading, findsOneWidget);
      final headingContainer = find
          .ancestor(
            of: heading,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding == EdgeInsets.all(headingPadding),
            ),
          )
          .first;
      expect(tester.widget<Padding>(headingContainer).child, isA<Align>());

      final paragraph = _paragraphWithText('原始段落');
      final field = tester.widget<TextField>(paragraph);
      expect(field.style?.fontSize, bodySize);
      expect(field.style?.height, compact ? 1.75 : 1.9);
      expect(
        MediaQuery.textScalerOf(tester.element(paragraph)).scale(bodySize),
        bodySize * viewport.textScale,
      );
      final paragraphPadding = find
          .ancestor(
            of: paragraph,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding == EdgeInsets.only(bottom: paragraphGap),
            ),
          )
          .first;
      expect(tester.widget<Padding>(paragraphPadding).child, isNot(isA<Row>()));
      expect(
        tester.getSize(paragraph).width,
        closeTo(tester.getSize(paragraphPadding).width, 1),
      );
      expect(
        tester
            .getSize(find.widgetWithIcon(IconButton, Icons.arrow_back_rounded))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        find.descendant(
          of: paragraphPadding,
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );
      expect(find.byTooltip('段落操作'), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text('预览'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testBookloomWidgets(
    'selected text rule menu preserves exact UTF16 selection without sending',
    (tester) async {
      final harness = await _EditorHarness.pump(tester);
      final l10n = lookupAppLocalizations(const Locale('zh'));
      const source = '😀前文。 第二章 标题 ';
      const original = ' 第二章 标题 ';
      final paragraph = _paragraphWithText('原始段落');
      await tester.enterText(paragraph, source);
      await tester.pump();
      final fieldFinder = _paragraphWithText(source);
      final field = tester.widget<TextField>(fieldFinder);
      final start = source.indexOf(original);
      field.controller!.selection = TextSelection(
        baseOffset: start,
        extentOffset: source.length,
      );
      await tester.pump();
      final editable = tester.state<EditableTextState>(
        find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
      );
      final toolbar = field.contextMenuBuilder!(
        tester.element(fieldFinder),
        editable,
      ) as AdaptiveTextSelectionToolbar;
      final create = toolbar.buttonItems!.singleWhere(
        (item) => item.label == l10n.editorAiCreateChapterRule,
      );
      create.onPressed!();
      await tester.pumpAndSettle();
      final panel = tester.widget<AiRuleCreationPanel>(
        find.byType(AiRuleCreationPanel),
      );
      expect(panel.selection.original, original);
      expect(panel.selection.startUtf16, start);
      expect(panel.selection.endUtf16, source.length);
      expect(panel.selection.blockId, 'p1');
      expect(panel.selection.chapterId, 'a');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      await tester.runAsync(harness.beforeClose!);
      expect(await _storedParagraph(tester, harness.repository), source);
    },
  );

  testBookloomWidgets(
    'long press offers paragraph actions with native text actions',
    (tester) async {
      final harness = await _EditorHarness.pump(
        tester,
        platform: TargetPlatform.android,
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            if (call.method == 'Clipboard.getData') return {'text': '可粘贴内容'};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final paragraph = _paragraphWithText('原始段落');
      await tester.longPressAt(
        tester.getTopLeft(paragraph) + const Offset(24, 16),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(paragraph).controller!.selection.isCollapsed,
        isFalse,
      );
      expect(find.text(l10n.editorSplitHere), findsOneWidget);
      expect(find.text(l10n.editorSetAsTitle), findsOneWidget);
      expect(find.text(l10n.editorAiCreateChapterRule), findsOneWidget);
      expect(find.text(l10n.editorAiCreateAdvertisementRule), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('粘贴'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);

      await tester.tap(find.text(l10n.editorSetAsTitle));
      await _pumpUntil(
        tester,
        () =>
            _paragraphWithText('原始段落').evaluate().isEmpty &&
            find.text('原始段落').evaluate().isNotEmpty,
        'paragraph becomes chapter title',
      );
      await tester.runAsync(harness.beforeClose!);
      await tester.pump();
      final updated = await tester.runAsync(
        () => harness.repository.loadChapter('book', 'a'),
      );
      expect(updated!.title, '原始段落');
      expect(updated.blocks, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'chapter management persists new volume and edited chapter with SQLite',
    (tester) async {
      final harness = await _EditorHarness.pump(tester);
      final l10n = lookupAppLocalizations(const Locale('zh'));
      const volumeTitle = '新卷';
      const newChapterTitle = '新章节';
      const newChapterBody = '新章节正文';

      // The directory header has no add button anymore; every chapter action
      // lives on the row's trailing menu (identical to the right-click menu).
      Future<void> openMoreMenu(String rowTitle) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        final row = find.ancestor(
          of: find.text(rowTitle).first,
          matching: find.byType(ListTile),
        );
        await _pumpUntil(
          tester,
          () => row.evaluate().isNotEmpty,
          'chapter row $rowTitle is visible',
        );
        final trigger = find.descendant(
          of: row.first,
          matching: find.byTooltip(l10n.editorChapterActions),
        );
        expect(trigger, findsOneWidget);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
      }

      Future<void> chooseAction(String action) async {
        final menuItem = find.text(action).hitTestable();
        await _pumpUntil(
          tester,
          () => menuItem.evaluate().isNotEmpty,
          'row action menu item $action',
        );
        await tester.tap(menuItem.last);
        await tester.pumpAndSettle();
      }

      Future<void> openMoreMenuAndPick(String rowTitle, String action) async {
        await openMoreMenu(rowTitle);
        await chooseAction(action);
      }

      Future<void> chooseVolume(String label, String title) async {
        final field = find.byWidgetPredicate(
          (widget) => widget is AppSelectField<String> && widget.label == label,
        );
        await tester.tap(
          find.descendant(of: field, matching: find.byType(TextField)),
        );
        await tester.pumpAndSettle();
        final option = find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text(title),
        );
        expect(option, findsOneWidget);
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: field, matching: find.byType(TextField)),
              )
              .controller
              ?.text,
          title,
        );
      }

      Future<void> expectChapterVolume(String chapter, String volume) async {
        await openMoreMenuAndPick(chapter, l10n.editorMoveChapters);
        final row = find.widgetWithText(CheckboxListTile, chapter);
        expect(row, findsOneWidget);
        expect(
          (tester.widget<CheckboxListTile>(row).subtitle! as Text).data,
          volume,
        );
        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();
      }

      await openMoreMenuAndPick('第二章', l10n.editorNewVolumeAfter);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        volumeTitle,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, l10n.editorCreate),
        ),
      );
      await tester.pumpAndSettle();
      await _pumpUntil(
        tester,
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            find.text(volumeTitle).evaluate().isNotEmpty,
        'new volume dialog dismissal and chapter list update',
      );

      await openMoreMenuAndPick(volumeTitle, l10n.editorNewChapter);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == l10n.editorChapterTitle,
        ),
        newChapterTitle,
      );
      await chooseVolume(l10n.editorTargetVolume, volumeTitle);
      await tester.tap(find.widgetWithText(FilledButton, l10n.editorCreate));
      final emptyBody = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.border == InputBorder.none &&
            widget.controller?.text.isEmpty == true,
      );
      await _pumpUntil(
        tester,
        () => emptyBody.evaluate().isNotEmpty,
        'new empty chapter body',
      );
      await tester.enterText(emptyBody, newChapterBody);
      await tester.pump();

      await openMoreMenuAndPick('第一章', l10n.editorMoveChapters);
      await chooseVolume(l10n.editorTargetVolume, volumeTitle);
      for (final chapter in ['第一章', '第二章']) {
        final row = find.widgetWithText(CheckboxListTile, chapter);
        await tester.tap(row);
        await tester.pump();
        expect(tester.widget<CheckboxListTile>(row).value, isTrue);
      }
      final move = find.widgetWithText(FilledButton, l10n.editorMove);
      expect(tester.widget<FilledButton>(move).onPressed, isNotNull);
      await tester.tap(move);
      await tester.pumpAndSettle();
      await expectChapterVolume('第一章', volumeTitle);
      await expectChapterVolume('第二章', volumeTitle);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byTooltip(l10n.editorUndo));
      await tester.pumpAndSettle();
      await expectChapterVolume('第一章', l10n.editorUnassigned);
      await tester.tap(find.byTooltip(l10n.editorRedo));
      await tester.pumpAndSettle();
      await expectChapterVolume('第一章', volumeTitle);

      await _pumpUntil(
        tester,
        () => find.text(l10n.editorSaved).evaluate().isNotEmpty,
        'chapter management autosave completes',
      );
      await tester.runAsync(harness.beforeClose!);
      await tester.pump();
      final persisted = await tester.runAsync(() async {
        final book = await harness.repository.loadBook('book');
        final original = await harness.repository.loadChapter('book', 'a');
        final otherOriginal = await harness.repository.loadChapter('book', 'b');
        final created = book!.chapters.singleWhere(
          (chapter) => chapter.title == newChapterTitle,
        );
        return (
          book: book,
          volumeId: book.chapters
              .singleWhere((chapter) => chapter.title == volumeTitle)
              .id,
          createdId: created.id,
          original: original,
          otherOriginal: otherOriginal,
          createdBody: await harness.repository.loadChapter('book', created.id),
        );
      });

      expect(persisted, isNotNull);
      final saved = persisted!;
      expect(
        saved.book.chapters
            .where(
              (chapter) =>
                  chapter.title == '第一章' ||
                  chapter.title == '第二章' ||
                  chapter.id == saved.createdId,
            )
            .every((chapter) => chapter.parentId == saved.volumeId),
        isTrue,
      );
      expect((saved.original!.blocks.single as TextBlock).text, '原始段落');
      expect((saved.otherOriginal!.blocks.single as TextBlock).text, '另一段落');
      expect(
        (saved.createdBody!.blocks.single as TextBlock).text,
        newChapterBody,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'IME commit with unchanged text saves before chapter switch',
    (tester) async {
      final harness = await _EditorHarness.pump(tester);
      await _startComposition(tester, '输入法新词');

      final secondChapter = find.ancestor(
        of: find.text('第二章').first,
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(secondChapter).onTap, isNull);

      // Some IMEs finish by clearing composing with no text change. EditableText
      // does not call TextField.onChanged for that transition.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '输入法新词',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      expect(tester.widget<ListTile>(secondChapter).onTap, isNotNull);

      await tester.tap(secondChapter);
      await _pumpUntil(
        tester,
        () => _paragraphWithText('另一段落').evaluate().isNotEmpty,
        'second chapter body',
      );
      expect(await _storedParagraph(tester, harness.repository), '输入法新词');

      await tester.tap(find.byTooltip('返回书架'));
      await _pumpUntil(
        tester,
        () => find.text('打开编辑器').evaluate().isNotEmpty,
        'shelf after return',
      );
      expect(find.text('打开编辑器'), findsOneWidget);
      expect(await _storedParagraph(tester, harness.repository), '输入法新词');
    },
  );

  testBookloomWidgets(
    'return commits visible text during an active composition',
    (tester) async {
      final harness = await _EditorHarness.pump(tester);
      await _startComposition(tester, '正在组合');

      await tester.tap(find.byTooltip('返回书架'));
      await _pumpUntil(
        tester,
        () => find.text('打开编辑器').evaluate().isNotEmpty,
        'shelf after composing return',
      );
      expect(find.text('打开编辑器'), findsOneWidget);
      expect(await _storedParagraph(tester, harness.repository), '正在组合');
    },
  );

  testBookloomWidgets(
    'native close guard commits visible composing text before save',
    (tester) async {
      final harness = await _EditorHarness.pump(tester);
      await _startComposition(tester, '关闭时的文字');

      await tester.runAsync(harness.beforeClose!);
      await tester.pump();
      expect(await _storedParagraph(tester, harness.repository), '关闭时的文字');
    },
  );

  testBookloomWidgets(
    'external route reset saves the last visible composing draft',
    (tester) async {
      final harness = await _EditorHarness.pump(tester);
      await _startComposition(tester, '路由重置前');

      harness.router.go('/');
      await _pumpUntil(
        tester,
        () => find.text('打开编辑器').evaluate().isNotEmpty,
        'shelf after route reset',
      );
      expect(find.text('打开编辑器'), findsOneWidget);
      // A removed page flushes asynchronously. Wait for that transaction to
      // finish before issuing a read against the same in-memory Drift DB.
      await _pumpUntil(
        tester,
        () =>
            harness.repository.saveAttempts > 0 &&
            harness.repository.completedSaves > 0,
        'route-reset save transaction',
      );
      expect(
        await _eventuallyStoredParagraph(tester, harness.repository, '路由重置前'),
        '路由重置前',
      );
    },
  );

  testBookloomWidgets('lifecycle pause flushes active composing text', (
    tester,
  ) async {
    final harness = await _EditorHarness.pump(tester);
    await _startComposition(tester, '暂停前的文字');

    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          harness.repository.saveAttempts > 0 &&
          harness.repository.completedSaves > 0,
      'lifecycle save transaction',
    );
    expect(
      await _eventuallyStoredParagraph(tester, harness.repository, '暂停前的文字'),
      '暂停前的文字',
    );
  });
}

const _volumeChapters = <Chapter>[
  Chapter(id: 'v1', bookId: 'book', title: '第一卷', level: 1, order: 0),
  Chapter(
    id: 'a',
    bookId: 'book',
    title: '第一章',
    parentId: 'v1',
    order: 1,
    blocks: <Block>[TextBlock(id: 'p1', text: '原始段落')],
  ),
  Chapter(id: 'v2', bookId: 'book', title: '第二卷', level: 1, order: 2),
  Chapter(
    id: 'b',
    bookId: 'book',
    title: '第二章',
    parentId: 'v2',
    order: 3,
    blocks: <Block>[TextBlock(id: 'p2', text: '另一段落')],
  ),
];

Future<String> _storedParagraph(
  WidgetTester tester,
  BookRepository repository,
) async => (await tester.runAsync(() async {
  final chapter = await repository.loadChapter('book', 'a');
  return (chapter!.blocks.single as TextBlock).text;
}))!;

Future<String> _eventuallyStoredParagraph(
  WidgetTester tester,
  BookRepository repository,
  String expected,
) async => (await tester.runAsync(() async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final chapter = await repository.loadChapter('book', 'a');
    final text = (chapter!.blocks.single as TextBlock).text;
    if (text == expected) return text;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Route-reset flush did not persist the IME draft');
}))!;

Future<void> _startComposition(WidgetTester tester, String text) async {
  final paragraph = _paragraphWithText('原始段落');
  expect(paragraph, findsOneWidget);
  final controller = tester.widget<TextField>(paragraph).controller!;
  await tester.showKeyboard(paragraph);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange(start: 0, end: text.length),
    ),
  );
  await tester.pump();
  expect(controller.text, text);
}

Finder _paragraphWithText(String text) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.controller?.text == text,
);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    // Repository file and database futures use the real event loop. Fake
    // clock pumps alone can leave the editor's loading spinner scheduled.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  throw TestFailure('Timed out waiting for $description');
}

class _EditorHarness {
  _EditorHarness(this.repository, this._guard, this.router);

  final _TrackingBookRepository repository;
  final _GuardCapture _guard;
  final GoRouter router;
  Future<void> Function()? get beforeClose => _guard.beforeClose;

  static Future<_EditorHarness> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 900),
    double textScale = 1,
    TargetPlatform platform = TargetPlatform.linux,
    List<Chapter>? chapters,
    bool jointRules = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fixture = await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp(
        'bookloom-editor-ime-',
      );
      final database = AppDatabase.memory();
      final repository = _TrackingBookRepository(database, root);
      final now = DateTime.utc(2026, 1, 1);
      await repository.createBook(
        Book(
          id: 'book',
          meta: BookMeta(title: '测试书'),
          chapters:
              chapters ??
              const <Chapter>[
                Chapter(
                  id: 'a',
                  bookId: 'book',
                  title: '第一章',
                  order: 0,
                  blocks: <Block>[TextBlock(id: 'p1', text: '原始段落')],
                ),
                Chapter(
                  id: 'b',
                  bookId: 'book',
                  title: '第二章',
                  order: 1,
                  blocks: <Block>[TextBlock(id: 'p2', text: '另一段落')],
                ),
              ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      return (root: root, database: database, repository: repository);
    });
    final root = fixture!.root;
    final database = fixture.database;
    final repository = fixture.repository;

    final guard = _GuardCapture();
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/book'),
              child: const Text('打开编辑器'),
            ),
          ),
        ),
        GoRoute(
          path: '/book',
          builder: (context, state) => EditorPage(
            bookId: 'book',
            closeGuardRegistrar: (callback, {onError}) {
              guard.beforeClose = callback;
              return () {};
            },
          ),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await tester.pump(Duration.zero);
      await tester.runAsync(() async {
        await database.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      await tester.pump(Duration.zero);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(repository),
          if (jointRules)
            proofreadingRuleStoreProvider.overrideWithValue(
              SettingsProofreadingRuleStore(database),
            ),
          if (jointRules)
            aiProofreadingTaskProvider.overrideWith(
              (ref, session) => AiProofreadingTask(
                session: session,
                loadConfiguration: () async => const AiConfiguration(
                  enabled: true,
                  address: 'http://localhost:9823/v1',
                  model: 'test',
                  credentialReference: 'key',
                ),
                credentials: _JointCredentials(),
                createClient: _JointRuleClient.new,
              ),
            ),
        ],
        child: MaterialApp.router(
          locale: const Locale('zh'),
          theme: AppTheme.light().copyWith(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('打开编辑器'), findsOneWidget);
    await tester.tap(find.text('打开编辑器'));
    await _pumpUntil(
      tester,
      () =>
          _paragraphWithText('原始段落').evaluate().isNotEmpty &&
          guard.beforeClose != null,
      'editor body and close guard',
    );
    return _EditorHarness(repository, guard, router);
  }
}

class _TrackingBookRepository extends BookRepository {
  _TrackingBookRepository(super.database, super.directory);

  int saveAttempts = 0;
  int completedSaves = 0;

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    saveAttempts++;
    final saved = await super.saveBook(
      book,
      expectedRevision: expectedRevision,
      dirtyChapterIds: dirtyChapterIds,
      deletedChapterIds: deletedChapterIds,
    );
    completedSaves++;
    return saved;
  }
}

Future<void> _tapJointPanel(WidgetTester tester, Type panel, String key) async {
  await tester.pump(const Duration(milliseconds: 300));
  final target = find.byKey(ValueKey(key));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find
          .descendant(of: find.byType(panel), matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(target);
  await tester.pump();
}

class _JointCredentials implements AiCredentialStore {
  @override
  Future<String?> read(String reference) async => 'test';
  @override
  Future<void> write(String reference, String value) async {}
  @override
  Future<void> delete(String reference) async {}
}

class _JointRuleClient implements AiTextClient {
  @override
  Future<String> generate({
    required AiEndpoint endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
    required AiCancellation cancellation,
  }) async => jsonEncode({
    'schema_version': 1,
    'findings': [
      {
        'id': 'ad-finding',
        'category': 'advertisement',
        'assessment': 'advertisement',
        'chapter_id': 'a',
        'block_id': 'p1',
        'original': '原始',
        'before': '',
        'after': '段落',
        'reason': '合成样例。',
      },
    ],
    'proposals': [
      {
        'id': 'change',
        'finding_id': 'ad-finding',
        'action': 'delete_text',
        'chapter_id': 'a',
        'block_id': 'p1',
        'original': '原始',
        'before': '',
        'after': '段落',
        'replacement': '',
        'reason': '合成样例。',
      },
    ],
    'rule_proposals': [
      {
        'schema_version': 1,
        'name': '合成广告规则',
        'kind': 'advertisement',
        'target': 'body_line',
        'match': {'mode': 'literal', 'pattern': '原始', 'case_sensitive': true},
        'action': 'exact_deletion',
        'positive_examples': ['原始'],
        'negative_examples': <String>[],
        'reason': '仅基于提供样例。',
      },
    ],
  });
  @override
  void dispose() {}
}

class _GuardCapture {
  Future<void> Function()? beforeClose;
}
