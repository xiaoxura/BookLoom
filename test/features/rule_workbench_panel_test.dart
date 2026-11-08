import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/app/ai_providers.dart';
import 'package:bookloom/app/rule_providers.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_store.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/application/rule_workbench_task.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:bookloom/features/editor/presentation/ai_proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/rule_workbench_panel.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('remote advertisement candidate hands off exact source', (
    tester,
  ) async {
    const remoteText = '前段\n广告文字\n后段';
    final firstName = List.filled(128, '甲').join();
    final secondName = '${List.filled(124, '乙').join()}😀丙丁';
    final session = EditorSession.withStore(
      store: _BookStore(
        text: '当前章没有候选。',
        followingChapters: const [
          Chapter(
            id: 'remote',
            bookId: 'book',
            title: '远章',
            blocks: [TextBlock(id: 'remote-block', text: remoteText)],
          ),
        ],
      ),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'candidate-a', name: firstName),
      _rule(id: 'candidate-b', name: secondName),
    ]);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.rules.isNotEmpty);
    await _tap(tester, const ValueKey('rule-select-candidate-a'));
    await _tap(tester, const ValueKey('rule-select-candidate-b'));
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
    final hit = task.matches.single;
    expect(hit.match.chapterId, 'remote');
    expect(session.activeChapterId, 'first');
    expect(session.book!.chapters.last.blocks, isEmpty);
    final revision = session.saveSeq;
    await _tap(tester, ValueKey('rule-hit-${hit.id}'));
    await _tap(tester, ValueKey('rule-ai-analyze-${hit.id}'));
    await _pumpUntil(
      tester,
      () => find.byType(AiProofreadingPanel).evaluate().isNotEmpty,
    );
    final selection = tester
        .widget<AiProofreadingPanel>(find.byType(AiProofreadingPanel))
        .initialAdvertisementSelection!;
    expect(session.activeChapterId, 'first');
    expect(session.saveSeq, revision);
    expect(selection.chapterId, 'remote');
    expect(selection.blockId, 'remote-block');
    expect(selection.original, '广告');
    expect(selection.startUtf16, remoteText.indexOf('广告'));
    expect(selection.ruleName, startsWith(firstName));
    expect(selection.ruleName, endsWith('…'));
    expect(selection.ruleName!.length, lessThanOrEqualTo(256));
    selection.validate(
      book: session.book!,
      sessionId: session.sessionId!,
      sessionRevision: revision,
    );
    expect(find.byKey(const ValueKey('ai-run')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import rules render read-only and never join the trial', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(
        parseOptions: const ParseOptions(rulePreset: 'numbered'),
      ),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded && !task.isBusy);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(find.text(l10n.ruleWorkbenchImportRules), findsOneWidget);
    expect(
      find.text(
        '${l10n.ruleWorkbenchImportPreset('数字标题')} · ${l10n.ruleWorkbenchEnabled}',
      ),
      findsOneWidget,
    );
    await _tap(tester, const ValueKey('rule-import-rules'));
    expect(find.text(l10n.ruleWorkbenchImportEntryChapter), findsOneWidget);
    expect(
      find.text(r'\s{0,8}\d{1,4}\s{0,8}[、.．:：]\s{0,8}.{0,40}'),
      findsOneWidget,
    );
    expect(find.text(l10n.ruleWorkbenchImportReadOnly), findsOneWidget);
    expect(task.rules, isEmpty);
    expect(task.selectedRuleIds, isEmpty);
    expect(store.rules, isEmpty);
    expect(find.byKey(const ValueKey('rule-select-numbered')), findsNothing);

    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom and invalid import rules stay read-only', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('zh'));
    final session = EditorSession.withStore(
      store: _BookStore(
        parseOptions: const ParseOptions(
          rulePreset: 'custom',
          ruleSpec: <String, Object?>{'name': '我的章节规则', 'chapter': r'^第\d+章'},
        ),
      ),
    );
    await session.open('book');
    addTearDown(session.dispose);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, _RuleStore(), onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded && !task.isBusy);
    expect(
      find.text(
        '${l10n.ruleWorkbenchImportPreset('我的章节规则')} · '
        '${l10n.ruleWorkbenchImportCustom} · ${l10n.ruleWorkbenchEnabled}',
      ),
      findsOneWidget,
    );
    await _tap(tester, const ValueKey('rule-import-rules'));
    expect(find.text(r'^第\d+章'), findsOneWidget);
    expect(find.text(l10n.ruleWorkbenchImportCustomNote), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unresolvable import rules warn without breaking the panel', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(
        parseOptions: const ParseOptions(rulePreset: 'missing-preset'),
      ),
    );
    await session.open('book');
    addTearDown(session.dispose);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, _RuleStore(), onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded && !task.isBusy);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(find.text(l10n.ruleWorkbenchImportInvalid), findsWidgets);
    await _tap(tester, const ValueKey('rule-import-rules'));
    expect(
      tester
          .widget<ExpansionTile>(
            find.byKey(const ValueKey('rule-import-rules')),
          )
          .children,
      hasLength(1),
    );
    expect(find.text(l10n.ruleWorkbenchImportReadOnly), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-trial conflicts are counted and block applying', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(text: '前文\n第三章广告 风雨\n尾声'),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final chapter = ProofreadingRule.create(
      id: 'chapter-x',
      name: '章节边界',
      kind: ProofreadingRuleKind.chapter,
      source: ProofreadingRuleSource.user,
      bookId: 'book',
      target: ProofreadingRuleTarget.headingLine,
      mode: ProofreadingMatchMode.literal,
      pattern: '第三章',
      caseSensitive: false,
      action: ProofreadingRuleAction.chapterCandidate,
      positiveExamples: const ['第三章 风雨'],
      negativeExamples: const [],
    );
    final deletion = ProofreadingRule.create(
      id: 'delete-x',
      name: '广告删除',
      kind: ProofreadingRuleKind.advertisement,
      source: ProofreadingRuleSource.user,
      bookId: 'book',
      target: ProofreadingRuleTarget.bodyLine,
      mode: ProofreadingMatchMode.literal,
      pattern: '广告',
      caseSensitive: false,
      action: ProofreadingRuleAction.exactDeletion,
      positiveExamples: const ['广告'],
      negativeExamples: const [],
    );
    final store = _RuleStore([chapter, deletion]);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded && task.rules.length == 2);
    await _tap(tester, const ValueKey('rule-select-chapter-x'));
    await _tap(tester, const ValueKey('rule-select-delete-x'));
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
    expect(task.trial!.totalConflicts, 1);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(find.textContaining(l10n.ruleWorkbenchConflicts), findsOneWidget);
    for (final id in ['rule-hit-0', 'rule-hit-1']) {
      await _tap(tester, ValueKey('rule-check-$id'));
      await tester.pump();
    }
    expect(find.text(l10n.aiProofreadingConflict), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('rule-apply-selected')),
          )
          .onPressed,
      isNull,
    );
    final details = find.text(l10n.ruleWorkbenchConflictDetails);
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text(l10n.ruleWorkbenchDeleteChapterConflict), findsOneWidget);
    expect(session.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI candidate loads once into memory without trial or save', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final candidate = _rule(id: 'ai-new', source: ProofreadingRuleSource.ai);
    final store = _RuleStore()..loadGate = Completer<void>();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ruleWorkbenchTaskProvider(session).overrideWith(
            (ref) => task = RuleWorkbenchTask(session: session, store: store),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RuleWorkbenchPanel(
              session: session,
              onLocate: (chapterId, blockId) async {},
              initialRule: candidate,
              initialSessionId: session.sessionId,
              initialSaveSeq: session.saveSeq,
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(tester, () => task.isBusy);
    expect(task.rules, isEmpty);
    store.loadGate!.complete();
    await _pumpUntil(
      tester,
      () => task.rules.any((rule) => rule.id == 'ai-new'),
    );
    expect(task.rules.single, same(candidate));
    expect(task.selectedRuleIds, {'ai-new'});
    expect(task.trial, isNull);
    expect(task.isSaved('ai-new'), isFalse);
    expect(store.rules, isEmpty);
    expect(session.dirty, isFalse);
    await tester.pump();
    expect(task.rules, hasLength(1));
    await tester.ensureVisible(find.byKey(const ValueKey('rule-definition')));
    await tester.tap(find.byKey(const ValueKey('rule-definition')));
    await tester.pumpAndSettle();
    expect(find.textContaining('广告'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale or colliding AI candidate never replaces saved rule', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final existing = _rule(id: 'same');
    final store = _RuleStore([existing]);
    late RuleWorkbenchTask task;
    Future<void> show(ProofreadingRule candidate, int revision) =>
        tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              ruleWorkbenchTaskProvider(session).overrideWith(
                (ref) =>
                    task = RuleWorkbenchTask(session: session, store: store),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: RuleWorkbenchPanel(
                  session: session,
                  onLocate: (chapterId, blockId) async {},
                  initialRule: candidate,
                  initialSessionId: session.sessionId,
                  initialSaveSeq: revision,
                ),
              ),
            ),
          ),
        );
    await show(
      _rule(id: 'same', source: ProofreadingRuleSource.ai),
      session.saveSeq,
    );
    await _pumpUntil(tester, () => task.isLoaded);
    await tester.pump();
    expect(task.rules.single, same(existing));
    expect(
      find.text(
        lookupAppLocalizations(const Locale('zh')).ruleWorkbenchInitialRejected,
      ),
      findsOneWidget,
    );
    await show(
      _rule(id: 'fresh', source: ProofreadingRuleSource.ai),
      session.saveSeq - 1,
    );
    await _pumpUntil(tester, () => task.isLoaded);
    await tester.pump();
    expect(task.rules.single, same(existing));
    expect(store.rules, [existing]);
    expect(
      find.text(
        lookupAppLocalizations(const Locale('zh')).ruleWorkbenchInitialRejected,
      ),
      findsOneWidget,
    );
  });

  testWidgets('rules entry stays offline and starts with no selected rules', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final bookStore = _BookStore();
    final session = EditorSession.withStore(store: bookStore);
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'global', scope: ProofreadingRuleScope.global),
    ]);
    final themeMode = ValueNotifier(ThemeMode.light);
    addTearDown(themeMode.dispose);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(
        session,
        store,
        onTask: (value) => task = value,
        themeMode: themeMode,
      ),
    );
    final title = lookupAppLocalizations(const Locale('zh')).ruleWorkbenchTitle;
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pump();
    await _pumpUntil(tester, () => task.rules.isNotEmpty);
    expect(find.byType(RuleWorkbenchPanel), findsOneWidget);
    expect(task.selectedRuleIds, isEmpty);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('rule-select-global')))
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('rule-scan')))
          .onPressed,
      isNull,
    );
    final offline = find.text(
      lookupAppLocalizations(const Locale('zh')).ruleWorkbenchOffline,
    );
    final ruleName = find.text('广告候选');
    final lightOffline = _resolvedColor(tester, offline);
    final lightRuleName = _resolvedColor(tester, ruleName);
    themeMode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    final darkOffline = _resolvedColor(tester, offline);
    final darkRuleName = _resolvedColor(tester, ruleName);
    expect(darkOffline, isNot(lightOffline));
    expect(darkRuleName, isNot(lightRuleName));
    final surface = AppTheme.dark().colorScheme.surface;
    expect(_contrast(darkOffline, surface), greaterThanOrEqualTo(4.5));
    expect(_contrast(darkRuleName, surface), greaterThanOrEqualTo(4.5));
    await _tap(tester, const ValueKey('rule-new'));
    await tester.ensureVisible(find.byKey(const ValueKey('rule-commit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rule-commit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create, trial, save only, then apply one deletion and undo', (
    tester,
  ) async {
    final bookStore = _BookStore();
    final session = EditorSession.withStore(store: bookStore);
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.idle);
    await _tap(tester, const ValueKey('rule-new'));
    await tester.enterText(find.byKey(const ValueKey('rule-name')), '删除广告词');
    await tester.enterText(find.byKey(const ValueKey('rule-pattern')), '广告');
    await tester.enterText(find.byKey(const ValueKey('rule-positive')), '广告甲');
    await _tap(tester, const ValueKey('rule-action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精确删除命中文本').last);
    await tester.pumpAndSettle();
    await _tap(tester, const ValueKey('rule-commit'));
    expect(task.rules, hasLength(1));
    expect(task.selectedRuleIds, {task.rules.single.id});
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
    expect(task.trial!.totalMatches, 2);
    expect(task.matches, hasLength(2));
    expect(session.dirty, isFalse);
    await _tap(tester, const ValueKey('rule-save'));
    await _pumpUntil(tester, () => task.isSaved(task.rules.single.id));
    expect(store.rules, hasLength(1));
    expect(session.dirty, isFalse);
    expect(
      session.activeChapter!.blocks.whereType<TextBlock>().first.text,
      '广告甲广告乙正文。',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('rule-check-rule-hit-0')),
    );
    await tester.tap(find.byKey(const ValueKey('rule-check-rule-hit-0')));
    await tester.pump();
    await _tap(tester, const ValueKey('rule-apply-selected'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.applied);
    expect(
      session.activeChapter!.blocks.whereType<TextBlock>().first.text,
      '甲广告乙正文。',
    );
    expect(session.canUndo, isTrue);
    await session.undo();
    expect(
      session.activeChapter!.blocks.whereType<TextBlock>().first.text,
      '广告甲广告乙正文。',
    );
    expect(store.rules, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('exclude text filters matches, saves and reloads in the form', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(text: '广告一\n引用广告二'),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _tap(tester, const ValueKey('rule-new'));
    await tester.enterText(find.byKey(const ValueKey('rule-name')), '带排除');
    await tester.enterText(find.byKey(const ValueKey('rule-pattern')), '广告');
    await tester.enterText(find.byKey(const ValueKey('rule-positive')), '广告一');
    await tester.enterText(find.byKey(const ValueKey('rule-exclude')), '引用');
    await _tap(tester, const ValueKey('rule-commit'));

    final rule = task.rules.single;
    expect(rule.excludePattern, '引用');
    expect(store.rules, isEmpty);
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
    expect(task.trial!.totalMatches, 1);
    expect(task.matches.single.match.lineNumber, 1);
    await _tap(tester, const ValueKey('rule-save'));
    await _pumpUntil(tester, () => task.isSaved(rule.id));
    expect(store.rules.single.excludePattern, '引用');

    await _tap(tester, const ValueKey('rule-definition'));
    expect(
      find.text('${l10n.ruleWorkbenchExcludePattern}: 引用'),
      findsOneWidget,
    );
    await _editRule(tester, rule.id);
    final excludeField = find.byKey(const ValueKey('rule-exclude'));
    await tester.ensureVisible(excludeField);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(excludeField).controller!.text, '引用');

    await tester.enterText(
      excludeField,
      List.filled(ProofreadingRule.maxExcludeUtf16 + 1, 'x').join(),
    );
    await _tap(tester, const ValueKey('rule-commit'));
    expect(find.text(l10n.ruleWorkbenchExcludePatternInvalid), findsOneWidget);
    expect(task.rules.single.excludePattern, '引用');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule file import rejects files without usable rules', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore();
    final empty = encodeProofreadingRules(const []);
    final files = _FakeFileService()
      ..picks = [
        PickedInput(
          name: 'empty.json',
          size: utf8.encode(empty).length,
          openRead: () => Stream<List<int>>.value(utf8.encode(empty)),
        ),
      ];
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value, files: files),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _tap(tester, const ValueKey('rule-import'));
    await _pumpUntil(
      tester,
      () => find
          .text(l10n.ruleWorkbenchRulesNoSharedInFile)
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const ValueKey('rule-import-dialog')), findsNothing);
    expect(store.rules, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared rule import reports oversized files', (tester) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore();
    final oversized = 'x' * (2 * 1024 * 1024 + 1);
    final files = _FakeFileService()
      ..picks = [
        PickedInput(
          name: 'huge.json',
          size: utf8.encode(oversized).length,
          openRead: () => Stream<List<int>>.value(utf8.encode(oversized)),
        ),
      ];
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value, files: files),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);

    await _tap(tester, const ValueKey('rule-import'));
    await _pumpUntil(
      tester,
      () => find.textContaining('2 MiB').evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('rule-import-dialog')), findsNothing);
    expect(store.rules, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule file import can keep conflicting rules as new ids', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'existing', scope: ProofreadingRuleScope.global, name: '旧名称'),
    ]);
    final file = encodeProofreadingRules([
      _rule(id: 'existing', scope: ProofreadingRuleScope.global, name: '新名称'),
      _rule(id: 'incoming', scope: ProofreadingRuleScope.global),
    ]);
    final files = _FakeFileService()
      ..picks = [
        PickedInput(
          name: 'rules.json',
          size: utf8.encode(file).length,
          openRead: () => Stream<List<int>>.value(utf8.encode(file)),
        ),
      ];
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value, files: files),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _tap(tester, const ValueKey('rule-import'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('rule-import-dialog'))
          .evaluate()
          .isNotEmpty,
    );
    await _tap(tester, const ValueKey('rule-import-copy-conflicts'));
    await _tap(tester, const ValueKey('rule-import-confirm'));
    await _pumpUntil(
      tester,
      () => find
          .text(l10n.ruleWorkbenchRulesImported(2, 0))
          .evaluate()
          .isNotEmpty,
    );
    expect(
      store.rules.singleWhere((rule) => rule.id == 'existing').name,
      '旧名称',
    );
    expect(
      store.rules.where((rule) => rule.id.startsWith('existing-')),
      hasLength(1),
    );
    expect(
      store.rules.singleWhere((rule) => rule.id.startsWith('existing-')).name,
      '新名称',
    );
    expect(store.rules.map((rule) => rule.id), contains('incoming'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule file export can omit selected rules', (tester) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'book-rule'),
      _rule(id: 'global-rule', scope: ProofreadingRuleScope.global),
    ]);
    final files = _FakeFileService();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value, files: files),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _tap(tester, const ValueKey('rule-export'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('rule-export-dialog'))
          .evaluate()
          .isNotEmpty,
    );
    await _tap(tester, const ValueKey('rule-export-book-rule'));
    await _tap(tester, const ValueKey('rule-export-confirm'));
    await _pumpUntil(tester, () => files.savedBytes != null);
    final exported = decodeProofreadingRules(utf8.decode(files.savedBytes!));
    expect(exported.map((rule) => rule.id), <String>['global-rule']);
    await _pumpUntil(
      tester,
      () => find.text(l10n.ruleWorkbenchRulesExported(1)).evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule export requires a selection and can be cancelled', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([_rule(id: 'only-rule')]);
    final files = _FakeFileService();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value, files: files),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);

    await _tap(tester, const ValueKey('rule-export'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('rule-export-dialog'))
          .evaluate()
          .isNotEmpty,
    );
    await _tap(tester, const ValueKey('rule-export-all'));
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('rule-export-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(files.savedBytes, isNull);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('rule-export-dialog')),
        matching: find.text(
          lookupAppLocalizations(const Locale('zh')).commonCancel,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rule-export-dialog')), findsNothing);
    expect(files.savedBytes, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule file export writes all loaded rules', (tester) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'book-rule'),
      _rule(id: 'global-rule', scope: ProofreadingRuleScope.global),
    ]);
    final files = _FakeFileService();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value, files: files),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _tap(tester, const ValueKey('rule-export'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('rule-export-dialog'))
          .evaluate()
          .isNotEmpty,
    );
    await _tap(tester, const ValueKey('rule-export-confirm'));
    await _pumpUntil(tester, () => files.savedBytes != null);
    final exported = decodeProofreadingRules(utf8.decode(files.savedBytes!));
    expect(exported.map((rule) => rule.id).toSet(), <String>{
      'book-rule',
      'global-rule',
    });
    expect(files.savedName, endsWith('.json'));
    await _pumpUntil(
      tester,
      () => find.text(l10n.ruleWorkbenchRulesExported(2)).evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared rule import copies book rules onto the open book', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'existing', scope: ProofreadingRuleScope.global, name: '旧名称'),
    ]);
    final incoming = encodeProofreadingRules([
      _rule(id: 'existing', scope: ProofreadingRuleScope.global, name: '新名称'),
      _rule(id: 'incoming', scope: ProofreadingRuleScope.global),
      _rule(id: 'book-only'),
    ]);
    final files = _FakeFileService()
      ..picks = [
        PickedInput(
          name: 'rules.json',
          size: utf8.encode(incoming).length,
          openRead: () => Stream<List<int>>.value(utf8.encode(incoming)),
        ),
      ];
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value, files: files),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _tap(tester, const ValueKey('rule-import'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('rule-import-dialog'))
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.text(l10n.ruleWorkbenchRulesImportBody(2, 1, 1)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rule-import-preview-existing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rule-import-preview-incoming')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rule-import-preview-book-only')),
      findsOneWidget,
    );
    expect(
      find.textContaining(l10n.ruleWorkbenchImportWillSkip),
      findsOneWidget,
    );
    final incomingPreview = tester.widget<Text>(
      find.byKey(const ValueKey('rule-import-preview-incoming')),
    );
    expect(
      incomingPreview.data,
      isNot(contains(l10n.ruleWorkbenchImportWillSkip)),
    );
    await _tap(tester, const ValueKey('rule-import-confirm'));
    await _pumpUntil(
      tester,
      () => find
          .text(l10n.ruleWorkbenchRulesImported(2, 1))
          .evaluate()
          .isNotEmpty,
    );
    expect(store.rules.map((rule) => rule.id), contains('incoming'));
    expect(store.rules.map((rule) => rule.id), contains('book-only'));
    expect(
      store.rules.singleWhere((rule) => rule.id == 'book-only').bookId,
      'book',
    );
    expect(
      store.rules.singleWhere((rule) => rule.id == 'existing').name,
      '旧名称',
    );
    expect(task.trial, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('built-in rules can be duplicated into editable user rules', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'builtin', source: ProofreadingRuleSource.builtIn),
    ]);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _openRuleMenu(tester, 'builtin');
    await tester.tap(find.text(l10n.ruleWorkbenchDuplicate).last);
    await tester.pumpAndSettle();
    const name = '广告候选（副本）';
    await _pumpUntil(
      tester,
      () => find.text(l10n.ruleWorkbenchDuplicated(name)).evaluate().isNotEmpty,
    );
    final copy = store.rules.singleWhere((rule) => rule.id != 'builtin');
    expect(copy.source, ProofreadingRuleSource.user);
    expect(copy.name, name);
    expect(copy.pattern, '广告');
    expect(store.rules.where((rule) => rule.id == 'builtin'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule search filters by name or pattern and can be cleared', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'ad', name: '广告规则'),
      _rule(id: 'chapter', name: '章节规则', pattern: '广告甲'),
    ]);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    final search = find.byKey(const ValueKey('rule-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, '章节');
    await tester.pump();
    expect(find.byKey(const ValueKey('rule-row-chapter')), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-row-ad')), findsNothing);

    await tester.enterText(search, '广告甲');
    await tester.pump();
    expect(find.byKey(const ValueKey('rule-row-chapter')), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-row-ad')), findsNothing);

    await tester.enterText(search, '不存在');
    await tester.pump();
    expect(find.text(l10n.ruleWorkbenchNoMatches), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-row-ad')), findsNothing);
    expect(find.byKey(const ValueKey('rule-row-chapter')), findsNothing);

    await _tap(tester, const ValueKey('rule-search-clear'));
    expect(find.byKey(const ValueKey('rule-row-ad')), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-row-chapter')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('whole-line switch filters matches and resets for paragraphs', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(text: '广告\n广告正文'),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _tap(tester, const ValueKey('rule-new'));
    await tester.enterText(find.byKey(const ValueKey('rule-name')), '整行推广');
    await tester.enterText(find.byKey(const ValueKey('rule-pattern')), '广告');
    await tester.enterText(find.byKey(const ValueKey('rule-positive')), '广告');
    await _tap(tester, const ValueKey('rule-whole-line'));
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('rule-whole-line')))
          .value,
      isTrue,
    );
    await _tap(tester, const ValueKey('rule-commit'));

    final rule = task.rules.single;
    expect(rule.wholeLineOnly, isTrue);
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
    expect(task.trial!.totalMatches, 1);
    expect(task.matches.single.match.lineNumber, 1);

    await _tap(tester, const ValueKey('rule-definition'));
    expect(
      find.text('${l10n.ruleWorkbenchWholeLine}: ${l10n.ruleWorkbenchEnabled}'),
      findsOneWidget,
    );

    await _editRule(tester, rule.id);
    final switchFinder = find.byKey(const ValueKey('rule-whole-line'));
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    await _tap(tester, const ValueKey('rule-target'));
    await tester.tap(find.text(l10n.ruleWorkbenchParagraph).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rule-whole-line')), findsNothing);
    await _tap(tester, const ValueKey('rule-commit'));
    expect(task.rules.single.wholeLineOnly, isFalse);
    expect(task.rules.single.target, ProofreadingRuleTarget.paragraph);
    expect(tester.takeException(), isNull);
  });

  testWidgets('definition examples align left with their headings', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([_rule(id: 'definition', name: '定义规则')]);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await _tap(tester, const ValueKey('rule-row-definition'));
    await _tap(tester, const ValueKey('rule-definition'));
    final headingLeft = tester
        .getRect(find.text(l10n.ruleWorkbenchPositive))
        .left;
    final exampleLeft = tester.getRect(find.text('广告甲')).left;
    expect(exampleLeft, closeTo(headingLeft, 1));
    expect(exampleLeft, lessThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('form validates examples with their original boundary spaces', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore();
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);

    await _tap(tester, const ValueKey('rule-new'));
    await tester.enterText(find.byKey(const ValueKey('rule-name')), '空格字面量');
    await tester.enterText(find.byKey(const ValueKey('rule-pattern')), ' 广告 ');
    await tester.enterText(
      find.byKey(const ValueKey('rule-positive')),
      '\n 广告 \r\n  ',
    );
    await _tap(tester, const ValueKey('rule-commit'));
    expect(task.rules, hasLength(1));
    final literal = task.rules.single;
    expect(literal.pattern, ' 广告 ');
    expect(literal.positiveExamples, [' 广告 ']);

    await _tap(tester, const ValueKey('rule-new'));
    await tester.enterText(find.byKey(const ValueKey('rule-name')), '边界反例');
    await tester.enterText(find.byKey(const ValueKey('rule-pattern')), '^广告\$');
    await tester.enterText(find.byKey(const ValueKey('rule-positive')), '广告');
    await tester.enterText(find.byKey(const ValueKey('rule-negative')), ' 广告 ');
    await _tap(tester, const ValueKey('rule-mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('受限正则（高级）').last);
    await tester.pumpAndSettle();
    await _tap(tester, const ValueKey('rule-commit'));
    expect(task.rules, hasLength(2));
    final anchored = task.rules.singleWhere((rule) => rule.name == '边界反例');
    expect(anchored.negativeExamples, [' 广告 ']);
    expect(anchored.matchSample(' 广告 '), isEmpty);
    expect(anchored.matchSample('广告'), isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter preview exposes following text and resource blocks', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(
        text: '前文\n第二章 风雨\n后文',
        followingBlocks: const [
          TextBlock(id: 'next-text', text: '后续全文。'),
          ImageBlock(id: 'image', assetId: 'asset-1', caption: '插图'),
          FootnoteBlock(id: 'note', text: '完整脚注', marker: '1'),
          DividerBlock(id: 'divider'),
        ],
      ),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([_chapterRule()]);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.rules.isNotEmpty);
    await _tap(tester, const ValueKey('rule-select-chapter'));
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
    expect(task.matches.single.followingBlockCount, 4);
    final ruleScroll = find
        .descendant(
          of: find.byType(RuleWorkbenchPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rule-hit-rule-hit-0')),
      200,
      scrollable: ruleScroll,
    );
    await _tap(tester, const ValueKey('rule-hit-rule-hit-0'));
    final following = find.text('展开新章后续全部内容');
    for (
      var attempt = 0;
      attempt < 6 && tester.getCenter(following).dy > 560;
      attempt++
    ) {
      await tester.drag(ruleScroll, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(tester.getCenter(following).dy, lessThan(560));
    await tester.tap(following);
    await tester.pumpAndSettle();
    expect(find.text('后续全文。'), findsOneWidget);
    expect(find.textContaining('asset-1'), findsWidgets);
    expect(find.text('完整脚注'), findsOneWidget);
    expect(find.textContaining('divider'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save does not apply and current trial can be retried', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([
      _rule(id: 'deletion', action: ProofreadingRuleAction.exactDeletion),
    ])..failSave = true;
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.rules.isNotEmpty);
    await _tap(tester, const ValueKey('rule-select-deletion'));
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rule-check-rule-hit-0')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(RuleWorkbenchPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _tap(tester, const ValueKey('rule-check-rule-hit-0'));
    await _tap(tester, const ValueKey('rule-save-apply'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.failed);
    expect(task.hasCurrentTrial, isTrue);
    expect(
      session.activeChapter!.blocks.whereType<TextBlock>().first.text,
      '广告甲广告乙正文。',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('rule-apply-selected')),
          )
          .onPressed,
      isNotNull,
    );
    await _tap(tester, const ValueKey('rule-apply-selected'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.applied);
    expect(
      session.activeChapter!.blocks.whereType<TextBlock>().first.text,
      '甲广告乙正文。',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing invalidates trial and ad candidate cannot be deleted', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([_rule(id: 'candidate')]);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.rules.isNotEmpty);
    await _tap(tester, const ValueKey('rule-select-candidate'));
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
    expect(task.trial!.distinctMatches, 2);
    expect(find.byKey(const ValueKey('rule-check-rule-hit-0')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('rule-apply-selected')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('规则操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();
    expect(task.phase, RuleWorkbenchPhase.cancelled);
    expect(task.hasCurrentTrial, isFalse);
    await tester.enterText(find.byKey(const ValueKey('rule-pattern')), '广告甲');
    expect(find.byKey(const ValueKey('rule-save')), findsNothing);
    expect(session.dirty, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'capture mapping creates a visible chapter preview and only applies on selection',
    (tester) async {
      const source = '前文\n【第二章 风雨】\n后文';
      final session = EditorSession.withStore(store: _BookStore(text: source));
      await session.open('book');
      addTearDown(session.dispose);
      final store = _RuleStore();
      late RuleWorkbenchTask task;
      await tester.pumpWidget(
        _app(session, store, onTask: (value) => task = value),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      await _tap(tester, const ValueKey('rule-new'));
      await tester.enterText(find.byKey(const ValueKey('rule-name')), '章节映射');
      await _chooseRuleOption(tester, const ValueKey('rule-kind'), '章节识别');
      await _chooseRuleOption(tester, const ValueKey('rule-mode'), '受限正则（高级）');
      await tester.enterText(
        find.byKey(const ValueKey('rule-pattern')),
        r'【第二章 ([^】]+)】',
      );
      await tester.enterText(
        find.byKey(const ValueKey('rule-positive')),
        '【第二章 风雨】',
      );
      await _tap(tester, const ValueKey('rule-advanced'));
      await tester.enterText(
        find.byKey(const ValueKey('rule-title-capture')),
        '2',
      );
      await tester.pump();
      expect(find.text('请输入可用编号内的非负整数。'), findsOneWidget);
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('rule-title-capture')),
        '1',
      );
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.titleCaptureGroup, 1);
      expect(store.rules, isEmpty);
      await _tap(tester, const ValueKey('rule-scan'));
      await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
      expect(task.matches.single.splitTitle, '风雨');
      await _tap(tester, const ValueKey('rule-hit-rule-hit-0'));
      expect(find.text('将移除的完整标题行'), findsOneWidget);
      expect(find.text('【第二章 风雨】'), findsWidgets);
      expect(find.text('新目录标题: 风雨'), findsOneWidget);
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        source,
      );
      await _tap(tester, const ValueKey('rule-save'), scrollDelta: -200);
      await _pumpUntil(tester, () => task.isSaved(task.rules.single.id));
      expect(store.rules.single.titleCaptureGroup, 1);
      expect(session.dirty, isFalse);
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        source,
      );
      await _tap(tester, const ValueKey('rule-check-rule-hit-0'));
      await _tap(
        tester,
        const ValueKey('rule-apply-selected'),
        scrollDelta: -200,
      );
      await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.applied);
      expect(session.book!.chapters[1].title, '风雨');
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        '前文\n',
      );
      await session.undo();
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        source,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing and switching match types do not retain a stale mapping',
    (tester) async {
      final session = EditorSession.withStore(
        store: _BookStore(text: '前文\n【第二章 风雨】\n后文'),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final store = _RuleStore([_mappedChapterRule()]);
      late RuleWorkbenchTask task;
      await tester.pumpWidget(
        _app(session, store, onTask: (value) => task = value),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      await _tap(tester, const ValueKey('rule-select-mapped'));
      await _tap(tester, const ValueKey('rule-definition'));
      expect(find.text('目录标题来自捕获组: 1'), findsOneWidget);
      await _tap(tester, const ValueKey('rule-scan'));
      await _pumpUntil(tester, () => task.hasCurrentTrial);
      await _openRuleMenu(tester, 'mapped');
      await tester.tap(find.text('编辑').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('rule-title-capture')))
            .controller!
            .text,
        '1',
      );
      final scanning = task.scan();
      await _pumpUntil(tester, () => task.hasCurrentTrial);
      await scanning;
      expect(task.hasCurrentTrial, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('rule-title-capture')),
        '0',
      );
      expect(task.hasCurrentTrial, isFalse);
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.titleCaptureGroup, 0);
      await _tap(tester, const ValueKey('rule-scan'));
      await _pumpUntil(tester, () => task.hasCurrentTrial);
      expect(task.matches.single.splitTitle, '【第二章 风雨】');
      await _tap(tester, const ValueKey('rule-save'));
      await _pumpUntil(tester, () => task.isSaved('mapped'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(session, store, onTask: (value) => task = value),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      expect(task.rules.single.titleCaptureGroup, 0);
      await _openRuleMenu(tester, 'mapped');
      await tester.tap(find.text('编辑').last);
      await tester.pumpAndSettle();
      await _chooseRuleOption(tester, const ValueKey('rule-mode'), '普通文本');
      expect(find.byKey(const ValueKey('rule-title-capture')), findsNothing);
      await _chooseRuleOption(tester, const ValueKey('rule-mode'), '受限正则（高级）');
      await _tap(tester, const ValueKey('rule-advanced'));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('rule-title-capture')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const ValueKey('rule-title-capture')),
        '1',
      );
      await _chooseRuleOption(tester, const ValueKey('rule-kind'), '广告识别');
      expect(find.byKey(const ValueKey('rule-title-capture')), findsNothing);
      await _chooseRuleOption(tester, const ValueKey('rule-kind'), '章节识别');
      await _tap(tester, const ValueKey('rule-advanced'));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('rule-title-capture')))
            .controller!
            .text,
        isEmpty,
      );
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.titleCaptureGroup, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'capture mapping stays usable at 320px with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final session = EditorSession.withStore(
        store: _BookStore(text: '前文\n【第二章 风雨】\n后文'),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final themeMode = ValueNotifier(ThemeMode.dark);
      addTearDown(themeMode.dispose);
      final store = _RuleStore([_mappedChapterRule()]);
      late RuleWorkbenchTask task;
      await tester.pumpWidget(
        _app(
          session,
          store,
          onTask: (value) => task = value,
          themeMode: themeMode,
        ),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      final ruleActions = find.byTooltip('规则操作');
      await tester.ensureVisible(ruleActions);
      await tester.pumpAndSettle();
      await tester.tap(ruleActions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑').last);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('rule-title-capture'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(tester.getSize(field).width, lessThanOrEqualTo(320));
      expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(620));
      expect(find.textContaining('0–1'), findsOneWidget);
      themeMode.value = ThemeMode.light;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(field, '2');
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(find.text('请输入可用编号内的非负整数。'), findsOneWidget);
      expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(620));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'number mapping saves and applies only explicitly selected composed titles',
    (tester) async {
      const source = '前文\n【第二章 风雨】\n后文';
      final session = EditorSession.withStore(store: _BookStore(text: source));
      await session.open('book');
      addTearDown(session.dispose);
      final store = _RuleStore();
      late RuleWorkbenchTask task;
      await tester.pumpWidget(
        _app(session, store, onTask: (value) => task = value),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      await _tap(tester, const ValueKey('rule-new'));
      await tester.enterText(find.byKey(const ValueKey('rule-name')), '章节映射');
      await _chooseRuleOption(tester, const ValueKey('rule-kind'), '章节识别');
      await _chooseRuleOption(tester, const ValueKey('rule-mode'), '受限正则（高级）');
      await tester.enterText(
        find.byKey(const ValueKey('rule-pattern')),
        r'【第(二)章 ([^】]+)】',
      );
      await tester.enterText(
        find.byKey(const ValueKey('rule-positive')),
        '【第二章 风雨】',
      );
      await _tap(tester, const ValueKey('rule-advanced'));
      await tester.enterText(
        find.byKey(const ValueKey('rule-title-capture')),
        '3',
      );
      await tester.pump();
      expect(find.text('请输入可用编号内的非负整数。'), findsOneWidget);
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('rule-title-capture')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('rule-number-capture')),
        '1',
      );
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.titleCaptureGroup, 2);
      expect(store.rules, isEmpty);
      await _tap(tester, const ValueKey('rule-scan'));
      await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.ready);
      expect(task.matches.single.splitTitle, '第2章 风雨');
      await _tap(tester, const ValueKey('rule-hit-rule-hit-0'));
      expect(find.text('将移除的完整标题行'), findsOneWidget);
      expect(find.text('【第二章 风雨】'), findsWidgets);
      expect(find.text('新目录标题: 第2章 风雨'), findsOneWidget);
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        source,
      );
      await _tap(tester, const ValueKey('rule-save'), scrollDelta: -200);
      await _pumpUntil(tester, () => task.isSaved(task.rules.single.id));
      expect(store.rules.single.titleCaptureGroup, 2);
      expect(store.rules.single.numberCaptureGroup, 1);
      expect(find.text('原文章号数字: 二'), findsOneWidget);
      expect(find.text('解析后的章号: 2'), findsOneWidget);
      expect(session.dirty, isFalse);
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        source,
      );
      await _tap(tester, const ValueKey('rule-check-rule-hit-0'));
      await _tap(
        tester,
        const ValueKey('rule-apply-selected'),
        scrollDelta: -200,
      );
      await _pumpUntil(tester, () => task.phase == RuleWorkbenchPhase.applied);
      expect(session.book!.chapters[1].title, '第2章 风雨');
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        '前文\n',
      );
      await session.undo();
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        source,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'number mapping stays usable at 320px with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final session = EditorSession.withStore(
        store: _BookStore(text: '前文\n【第二章 风雨】\n后文'),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final themeMode = ValueNotifier(ThemeMode.dark);
      addTearDown(themeMode.dispose);
      final store = _RuleStore([_numberedChapterRule()]);
      late RuleWorkbenchTask task;
      await tester.pumpWidget(
        _app(
          session,
          store,
          onTask: (value) => task = value,
          themeMode: themeMode,
        ),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      final ruleActions = find.byTooltip('规则操作');
      await tester.ensureVisible(ruleActions);
      await tester.pumpAndSettle();
      await tester.tap(ruleActions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑').last);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('rule-number-capture'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(tester.getSize(field).width, lessThanOrEqualTo(320));
      expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(620));
      expect(find.textContaining('0–2'), findsOneWidget);
      themeMode.value = ThemeMode.light;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(field, '3');
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(find.text('请先设置标题捕获组，并输入可用编号内的非负整数。'), findsOneWidget);
      expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(620));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('number mapping edits expire trials and reset dependent fields', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(text: '前文\n【第二章 风雨】\n后文'),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final store = _RuleStore([_numberedChapterRule()]);
    late RuleWorkbenchTask task;
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    await _tap(tester, const ValueKey('rule-select-mapped'));
    await _tap(tester, const ValueKey('rule-scan'));
    await _pumpUntil(tester, () => task.hasCurrentTrial);
    await _tap(tester, const ValueKey('rule-save'));
    await _pumpUntil(tester, () => task.isSaved('mapped'));
    await _openRuleMenu(tester, 'mapped');
    await tester.tap(find.text('停用规则').last.hitTestable());
    await _pumpUntil(tester, () => !task.isBusy && !task.rules.single.enabled);
    expect(task.rules.single.numberCaptureGroup, 1);
    await _openRuleMenu(tester, 'mapped');
    await tester.tap(find.text('启用规则').last.hitTestable());
    await _pumpUntil(
      tester,
      () => !task.isBusy && task.rules.single.enabled && task.isSaved('mapped'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _app(session, store, onTask: (value) => task = value),
    );
    await _openRules(tester);
    await _pumpUntil(tester, () => task.isLoaded);
    expect(task.rules.single.numberCaptureGroup, 1);
    await _editRule(tester, 'mapped');
    final title = find.byKey(const ValueKey('rule-title-capture'));
    final number = find.byKey(const ValueKey('rule-number-capture'));
    expect(tester.widget<TextField>(number).controller!.text, '1');
    task.setRuleSelected('mapped', true);
    final scanning = task.scan();
    await _pumpUntil(tester, () => task.hasCurrentTrial);
    await scanning;
    await tester.enterText(number, '0');
    expect(task.hasCurrentTrial, isFalse);
    await tester.enterText(title, '');
    expect(tester.widget<TextField>(number).controller!.text, isEmpty);
    await tester.enterText(number, '1');
    await tester.pump();
    expect(find.text('请先设置标题捕获组，并输入可用编号内的非负整数。'), findsOneWidget);
    await _tap(tester, const ValueKey('rule-commit'));
    expect(task.rules.single.numberCaptureGroup, 1);
    await tester.enterText(title, '2');
    await _chooseRuleOption(tester, const ValueKey('rule-mode'), '普通文本');
    await _chooseRuleOption(tester, const ValueKey('rule-mode'), '受限正则（高级）');
    await _tap(tester, const ValueKey('rule-advanced'));
    expect(tester.widget<TextField>(number).controller!.text, isEmpty);
    await tester.enterText(title, '2');
    await tester.enterText(number, '1');
    await _chooseRuleOption(tester, const ValueKey('rule-kind'), '广告识别');
    await _chooseRuleOption(tester, const ValueKey('rule-kind'), '章节识别');
    await _tap(tester, const ValueKey('rule-advanced'));
    expect(tester.widget<TextField>(number).controller!.text, isEmpty);
    await _tap(tester, const ValueKey('rule-commit'));
    expect(task.rules.single.numberCaptureGroup, isNull);
    expect(session.dirty, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'heading level survives create edit toggle reload and type changes',
    (tester) async {
      final session = EditorSession.withStore(
        store: _BookStore(text: '前文\n第二卷 风雨\n后文'),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final store = _RuleStore();
      late RuleWorkbenchTask task;
      await tester.pumpWidget(
        _app(session, store, onTask: (value) => task = value),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      await _tap(tester, const ValueKey('rule-new'));
      await tester.enterText(find.byKey(const ValueKey('rule-name')), '卷层级');
      await _chooseRuleOption(tester, const ValueKey('rule-kind'), '章节识别');
      final level = find.byKey(const ValueKey('rule-heading-level'));
      expect(
        tester.widget<DropdownButtonFormField<int>>(level).initialValue,
        2,
      );
      await _chooseRuleOption(
        tester,
        const ValueKey('rule-heading-level'),
        '卷',
      );
      await tester.enterText(find.byKey(const ValueKey('rule-pattern')), '第二卷');
      await tester.enterText(
        find.byKey(const ValueKey('rule-positive')),
        '第二卷 风雨',
      );
      await _tap(tester, const ValueKey('rule-commit'));
      final ruleId = task.rules.single.id;
      expect(task.rules.single.headingLevel, 1);
      expect(task.rules.single.mode, ProofreadingMatchMode.literal);
      await _editRule(tester, ruleId);
      expect(
        tester.widget<DropdownButtonFormField<int>>(level).initialValue,
        1,
      );
      await tester.enterText(
        find.byKey(const ValueKey('rule-name')),
        '编辑后的卷层级',
      );
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.headingLevel, 1);
      await _tap(tester, const ValueKey('rule-scan'));
      await _pumpUntil(tester, () => task.hasCurrentTrial);
      await _tap(tester, const ValueKey('rule-save'));
      await _pumpUntil(tester, () => task.isSaved(ruleId));
      for (final enabled in [false, true]) {
        await _openRuleMenu(tester, ruleId);
        await tester.tap(find.text(enabled ? '启用规则' : '停用规则').last);
        await tester.pump();
        await _pumpUntil(
          tester,
          () =>
              !task.isBusy &&
              task.rules.single.enabled == enabled &&
              task.isSaved(ruleId),
        );
        expect(task.rules.single.headingLevel, 1);
        expect(store.rules.single.headingLevel, 1);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(session, store, onTask: (value) => task = value),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      expect(task.rules.single.headingLevel, 1);
      expect(task.selectedRuleIds, isEmpty);
      await _tap(tester, ValueKey('rule-select-$ruleId'));
      await _editRule(tester, ruleId);
      final scanning = task.scan();
      await _pumpUntil(tester, () => task.hasCurrentTrial);
      await scanning;
      await _chooseRuleOption(
        tester,
        const ValueKey('rule-heading-level'),
        '章节',
      );
      expect(task.hasCurrentTrial, isFalse);
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.headingLevel, 2);
      await _editRule(tester, ruleId);
      await _chooseRuleOption(tester, const ValueKey('rule-mode'), '受限正则（高级）');
      await _chooseRuleOption(
        tester,
        const ValueKey('rule-heading-level'),
        '卷',
      );
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.headingLevel, 1);
      expect(task.rules.single.mode, ProofreadingMatchMode.safeRegex);
      await _editRule(tester, ruleId);
      await _chooseRuleOption(tester, const ValueKey('rule-kind'), '广告识别');
      expect(level, findsNothing);
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.headingLevel, 2);
      await _editRule(tester, ruleId);
      await _chooseRuleOption(tester, const ValueKey('rule-kind'), '章节识别');
      expect(
        tester.widget<DropdownButtonFormField<int>>(level).initialValue,
        2,
      );
      await _tap(tester, const ValueKey('rule-commit'));
      expect(task.rules.single.headingLevel, 2);
      expect(session.dirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'volume preview shows untitled front matter resources and paged chapter names',
    (tester) async {
      const source = '前文\n第二卷 风雨\n卷前正文';
      final session = EditorSession.withStore(
        store: _BookStore(
          text: source,
          followingBlocks: const [
            TextBlock(id: 'next-text', text: '完整卷前正文'),
            ImageBlock(id: 'image', assetId: 'volume-art', caption: '卷前插图'),
            FootnoteBlock(id: 'note', text: '完整卷前脚注', marker: '1'),
            DividerBlock(id: 'divider'),
          ],
          followingChapters: [
            for (var index = 0; index < 101; index++)
              Chapter(
                id: 'next-$index',
                bookId: 'book',
                title: '后续章$index',
                order: index + 1,
              ),
            const Chapter(
              id: 'stop-volume',
              bookId: 'book',
              title: '下一卷',
              level: 1,
              order: 102,
            ),
            const Chapter(
              id: 'outside',
              bookId: 'book',
              title: '不移入的章节',
              order: 103,
            ),
          ],
        ),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final store = _RuleStore([_volumeChapterRule()]);
      late RuleWorkbenchTask task;
      final l10n = lookupAppLocalizations(const Locale('zh'));
      await tester.pumpWidget(
        _app(session, store, onTask: (value) => task = value),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      await _tap(tester, const ValueKey('rule-select-volume'));
      await _tap(tester, const ValueKey('rule-definition'));
      expect(find.text('识别层级: 卷'), findsOneWidget);
      await _tap(tester, const ValueKey('rule-scan'));
      await _pumpUntil(tester, () => task.hasCurrentTrial);
      expect(task.matches.single.followingChapters, hasLength(101));
      await _tap(tester, const ValueKey('rule-hit-rule-hit-0'));
      expect(find.textContaining('卷识别'), findsWidgets);
      expect(find.text('新卷标题: 第二卷 风雨'), findsOneWidget);
      expect(find.text(l10n.ruleWorkbenchVolumeFrontMatter), findsOneWidget);
      expect(find.text(l10n.ruleWorkbenchVolumePreview), findsOneWidget);
      expect(find.text(l10n.aiProofreadingSplitResources), findsNothing);
      expect(find.text(l10n.ruleWorkbenchSplitSuffix), findsNothing);
      expect(find.text('将移除的完整标题行'), findsOneWidget);
      expect(find.text('单项应用将移入新卷的后续章节数: 101'), findsOneWidget);
      await _tap(tester, const ValueKey('rule-following-blocks-rule-hit-0'));
      expect(find.text('完整卷前正文'), findsOneWidget);
      expect(find.textContaining('volume-art'), findsWidgets);
      expect(find.text('完整卷前脚注'), findsOneWidget);
      final textLeft = tester.getRect(find.text('完整卷前正文')).left;
      final noteLeft = tester.getRect(find.text('完整卷前脚注')).left;
      expect(noteLeft, closeTo(textLeft, 1));
      expect(textLeft, lessThan(200));
      await _tap(tester, const ValueKey('rule-following-chapters-rule-hit-0'));
      expect(find.text('后续章0'), findsOneWidget);
      expect(find.text('后续章99'), findsOneWidget);
      expect(find.text('后续章100'), findsNothing);
      await _tap(tester, const ValueKey('rule-more-chapters-rule-hit-0'));
      expect(find.text('后续章100'), findsOneWidget);
      expect(find.text('不移入的章节'), findsNothing);
      expect(
        session.activeChapter!.blocks.whereType<TextBlock>().first.text,
        source,
      );
      expect(session.dirty, isFalse);
      expect(store.rules.single.headingLevel, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'volume heading preview and level field fit 320px large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final session = EditorSession.withStore(
        store: _BookStore(text: '前文\n第二卷 风雨\n后文'),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final themeMode = ValueNotifier(ThemeMode.dark);
      addTearDown(themeMode.dispose);
      final store = _RuleStore([_volumeChapterRule()]);
      late RuleWorkbenchTask task;
      await tester.pumpWidget(
        _app(
          session,
          store,
          onTask: (value) => task = value,
          themeMode: themeMode,
        ),
      );
      await _openRules(tester);
      await _pumpUntil(tester, () => task.isLoaded);
      await _tap(tester, const ValueKey('rule-select-volume'));
      await _tap(tester, const ValueKey('rule-scan'));
      await _pumpUntil(tester, () => task.hasCurrentTrial);
      await _tap(tester, const ValueKey('rule-hit-rule-hit-0'));
      expect(find.text('新卷标题: 第二卷 风雨'), findsOneWidget);
      expect(tester.takeException(), isNull);
      themeMode.value = ThemeMode.light;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _editRule(tester, 'volume');
      final level = find.byKey(const ValueKey('rule-heading-level'));
      await tester.ensureVisible(level);
      await tester.pumpAndSettle();
      expect(tester.getSize(level).width, lessThanOrEqualTo(320));
      expect(tester.getBottomRight(level).dy, lessThanOrEqualTo(620));
      await _chooseRuleOption(
        tester,
        const ValueKey('rule-heading-level'),
        '章节',
      );
      expect(
        tester.widget<DropdownButtonFormField<int>>(level).initialValue,
        2,
      );
      expect(session.dirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(
  EditorSession session,
  _RuleStore store, {
  required void Function(RuleWorkbenchTask) onTask,
  ValueNotifier<ThemeMode>? themeMode,
  FileService? files,
}) => ProviderScope(
  overrides: [
    if (files != null) fileServiceProvider.overrideWithValue(files),
    proofreadingRuleStoreProvider.overrideWithValue(store),
    aiConfigurationServiceProvider.overrideWith(
      (ref) => throw StateError(
        'The offline rule panel must not access AI configuration.',
      ),
    ),
    ruleWorkbenchTaskProvider(session).overrideWith((ref) {
      final task = RuleWorkbenchTask(session: session, store: store);
      onTask(task);
      return task;
    }),
  ],
  child: themeMode == null
      ? _themedApp(session, ThemeMode.light)
      : ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (context, mode, child) => _themedApp(session, mode),
        ),
);

Widget _themedApp(EditorSession session, ThemeMode mode) => MaterialApp(
  locale: const Locale('zh'),
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: ProofreadingPanel(
          session: session,
          onLocate: (chapterId, blockId) async {},
        ),
      ),
    ),
  ),
);

Color _resolvedColor(WidgetTester tester, Finder finder) =>
    DefaultTextStyle.of(tester.element(finder)).style.color!;

double _contrast(Color first, Color second) {
  final firstLight = first.computeLuminance();
  final secondLight = second.computeLuminance();
  final lighter = firstLight > secondLight ? firstLight : secondLight;
  final darker = firstLight > secondLight ? secondLight : firstLight;
  return (lighter + 0.05) / (darker + 0.05);
}

Future<void> _tap(
  WidgetTester tester,
  Key key, {
  double scrollDelta = 200,
}) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      scrollDelta,
      scrollable: find
          .descendant(
            of: find.byType(RuleWorkbenchPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var attempt = 0; attempt < 100; attempt++) {
    final center = tester.getCenter(finder);
    final framed =
        center.dy > height * .2 &&
        center.dy < height * .8 &&
        finder.hitTestable().evaluate().isNotEmpty;
    if (framed) break;
    final scrollable = find
        .descendant(
          of: find.byType(RuleWorkbenchPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(
      scrollable,
      Offset(0, center.dy >= height / 2 ? -250 : 250),
    );
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

Future<void> _openRuleMenu(WidgetTester tester, String ruleId) async {
  final row = find.byKey(ValueKey('rule-row-$ruleId'));
  if (row.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      row,
      -200,
      scrollable: find
          .descendant(
            of: find.byType(RuleWorkbenchPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  final menu = find.descendant(of: row, matching: find.byTooltip('规则操作'));
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  expect(menu.hitTestable(), findsOneWidget);
  await tester.tap(menu.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _editRule(WidgetTester tester, String ruleId) async {
  await _openRuleMenu(tester, ruleId);
  final edit = find.text('编辑').last;
  expect(edit.hitTestable(), findsOneWidget);
  await tester.tap(edit.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _openRules(WidgetTester tester) async {
  final title = lookupAppLocalizations(const Locale('zh')).ruleWorkbenchTitle;
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pump();
}

Future<void> _chooseRuleOption(
  WidgetTester tester,
  Key key,
  String label,
) async {
  await _tap(tester, key);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(condition(), isTrue);
  await tester.pump();
}

ProofreadingRule _rule({
  required String id,
  String name = '广告候选',
  ProofreadingRuleScope scope = ProofreadingRuleScope.book,
  String pattern = '广告',
  ProofreadingRuleAction action = ProofreadingRuleAction.advertisementCandidate,
  ProofreadingRuleSource source = ProofreadingRuleSource.user,
}) => ProofreadingRule.create(
  id: id,
  name: name,
  kind: ProofreadingRuleKind.advertisement,
  source: source,
  bookId: 'book',
  target: ProofreadingRuleTarget.bodyLine,
  mode: ProofreadingMatchMode.literal,
  pattern: pattern,
  caseSensitive: false,
  action: action,
  positiveExamples: ['广告甲'],
  negativeExamples: const [],
  scope: scope,
  globalScopeConfirmed: scope == ProofreadingRuleScope.global,
);

ProofreadingRule _chapterRule() => ProofreadingRule.create(
  id: 'chapter',
  name: '章节候选',
  kind: ProofreadingRuleKind.chapter,
  source: ProofreadingRuleSource.user,
  bookId: 'book',
  target: ProofreadingRuleTarget.headingLine,
  mode: ProofreadingMatchMode.literal,
  pattern: '第二章',
  caseSensitive: false,
  action: ProofreadingRuleAction.chapterCandidate,
  positiveExamples: ['第二章 风雨'],
  negativeExamples: const [],
);

ProofreadingRule _numberedChapterRule() => ProofreadingRule.create(
  id: 'mapped',
  name: '章号映射',
  kind: ProofreadingRuleKind.chapter,
  source: ProofreadingRuleSource.user,
  bookId: 'book',
  target: ProofreadingRuleTarget.headingLine,
  mode: ProofreadingMatchMode.safeRegex,
  pattern: r'【第(二)章 ([^】]+)】',
  titleCaptureGroup: 2,
  numberCaptureGroup: 1,
  caseSensitive: true,
  action: ProofreadingRuleAction.chapterCandidate,
  positiveExamples: const ['【第二章 风雨】'],
  negativeExamples: const [],
);

ProofreadingRule _mappedChapterRule() => ProofreadingRule.create(
  id: 'mapped',
  name: '章节映射',
  kind: ProofreadingRuleKind.chapter,
  source: ProofreadingRuleSource.user,
  bookId: 'book',
  target: ProofreadingRuleTarget.headingLine,
  mode: ProofreadingMatchMode.safeRegex,
  pattern: r'【第二章 ([^】]+)】',
  titleCaptureGroup: 1,
  caseSensitive: true,
  action: ProofreadingRuleAction.chapterCandidate,
  positiveExamples: const ['【第二章 风雨】'],
  negativeExamples: const [],
);

ProofreadingRule _volumeChapterRule() => ProofreadingRule.create(
  id: 'volume',
  name: '卷识别规则',
  kind: ProofreadingRuleKind.chapter,
  headingLevel: 1,
  source: ProofreadingRuleSource.user,
  bookId: 'book',
  target: ProofreadingRuleTarget.headingLine,
  mode: ProofreadingMatchMode.literal,
  pattern: '第二卷',
  caseSensitive: true,
  action: ProofreadingRuleAction.chapterCandidate,
  positiveExamples: const ['第二卷 风雨'],
  negativeExamples: const [],
);

class _RuleStore implements ProofreadingRuleStore {
  _RuleStore([List<ProofreadingRule> initial = const []])
    : rules = [...initial];
  final List<ProofreadingRule> rules;
  Completer<void>? loadGate;
  bool failSave = false;

  void _check(
    Map<String, ProofreadingRule?>? expectedRules,
    bool Function()? isCurrent,
  ) {
    if (isCurrent != null && !isCurrent()) throw StateError('stale rule');
    for (final entry
        in expectedRules?.entries ??
            const <MapEntry<String, ProofreadingRule?>>[]) {
      final actual = rules.where((rule) => rule.id == entry.key).firstOrNull;
      final expected = entry.value;
      if (actual == null && expected == null) continue;
      if (actual == null ||
          expected == null ||
          proofreadingRuleFingerprint(actual) !=
              proofreadingRuleFingerprint(expected)) {
        throw StateError('rule changed');
      }
    }
  }

  @override
  Future<List<ProofreadingRule>> loadForBook(String bookId) async {
    await loadGate?.future;
    return rules.where((rule) => rule.appliesToBook(bookId)).toList();
  }

  @override
  Future<RuleMergeResult> mergeMissing(
    List<ProofreadingRule> rules, {
    bool Function()? isCurrent,
  }) async {
    final added = <String>[];
    final skipped = <String>[];
    for (final rule in rules) {
      if (this.rules.any((existing) => existing.id == rule.id)) {
        skipped.add(rule.id);
      } else {
        this.rules.add(rule);
        added.add(rule.id);
      }
    }
    return RuleMergeResult(addedIds: added, skippedIds: skipped);
  }

  @override
  Future<void> save(
    ProofreadingRule rule, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  }) async {
    _check(expectedRules, isCurrent);
    if (failSave) throw StateError('synthetic save failure');
    rules.removeWhere((current) => current.id == rule.id);
    rules.add(rule);
  }

  @override
  Future<void> delete(
    String ruleId, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  }) async {
    _check(expectedRules, isCurrent);
    rules.removeWhere((rule) => rule.id == ruleId);
  }

  @override
  Future<void> runIfCurrent(
    Map<String, ProofreadingRule?> expectedRules,
    void Function() action, {
    bool Function()? isCurrent,
  }) async {
    _check(expectedRules, isCurrent);
    action();
  }
}

class _BookStore implements EditorBookStore {
  _BookStore({
    this.text = '广告甲广告乙正文。',
    this.followingBlocks = const [],
    this.followingChapters = const [],
    this.parseOptions = const ParseOptions(),
  });

  final String text;
  final List<Block> followingBlocks;
  final List<Chapter> followingChapters;
  final ParseOptions parseOptions;
  late final book = Book(
    id: 'book',
    meta: BookMeta(title: '书', author: '作者'),
    chapters: [
      const Chapter(id: 'first', bookId: 'book', title: '第一章'),
      for (final chapter in followingChapters)
        chapter.copyWith(blocks: const []),
    ],
    createdAt: DateTime.utc(2026, 11, 6),
    updatedAt: DateTime.utc(2026, 11, 6),
    parseOptions: parseOptions,
  );

  @override
  Future<Book?> loadBook(String bookId) async => bookId == 'book' ? book : null;

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async =>
      chapterId == 'first'
      ? Chapter(
          id: 'first',
          bookId: 'book',
          title: '第一章',
          blocks: [
            TextBlock(id: 'paragraph', text: text),
            ...followingBlocks,
          ],
        )
      : followingChapters
            .where((chapter) => chapter.id == chapterId)
            .firstOrNull;

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async => book;
}

class _FakeFileService implements FileService {
  List<PickedInput> picks = const [];
  List<int>? savedBytes;
  String? savedName;

  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const <String>['txt', 'epub', 'docx'],
  }) async => picks;

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) async {
    savedBytes = await prepared.readAsBytes();
    savedName = suggestedName;
    return SaveSaved(Uri());
  }

  @override
  Future<void> clearTemporaryFiles() async {}
}
