import 'dart:async';
import 'dart:convert';

import 'package:bookloom/app/ai_providers.dart';
import 'package:bookloom/app/rule_providers.dart';
import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_proofreading_prompt.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_store.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:bookloom/features/editor/application/ai_proofreading_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:bookloom/features/editor/presentation/ai_proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/rule_workbench_panel.dart';
import 'package:bookloom/features/settings/data/ai_http_client.dart';
import 'package:bookloom/features/settings/data/secure_ai_credential_store.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'joint rules chapter samples authorize only their actual later chunk',
    (tester) async {
      final session = EditorSession.withStore(
        store: _BookStore(
          firstText: List.filled(20000, '甲').join(),
          firstFollowingBlocks: const [
            TextBlock(id: 'heading-sample', text: '第四章 标题'),
          ],
        ),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final client = _EmptyRecordingClient();
      final task = await _pumpCompletedAiPanel(
        tester,
        session,
        client,
        missingChapter: true,
        beforePrepare: (_) async {
          await _tapAi(tester, 'ai-request-rules');
          final field = find.byKey(const ValueKey('ai-rule-positive'));
          expect(tester.widget<TextField>(field).controller!.text, isEmpty);
          await tester.ensureVisible(field);
          await tester.enterText(field, '第四章 标题');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
        },
        afterPrepare: (task) async {
          final consent = task.consent!;
          expect(consent.ruleRequest!.kind, ProofreadingRuleKind.chapter);
          expect(consent.ruleChunkIndex, greaterThan(0));
          await _scrollAiResult(
            tester,
            find.textContaining('仅第 ${consent.ruleChunkIndex! + 1} 个分块'),
          );
          await _tapAi(tester, 'ai-chunk-${consent.ruleChunkIndex}');
          final payload = find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                widget.data != null &&
                widget.data!.contains('"rule_request"'),
          );
          await tester.pumpAndSettle();
          expect(payload, findsOneWidget);
          final json = jsonDecode(
            tester.widget<SelectableText>(payload).data!,
          ) as Map<String, dynamic>;
          expect(
            (json['context'] as Map)['chunk_index'],
            consent.ruleChunkIndex,
          );
          expect((json['rule_request'] as Map)['kind'], 'chapter');
        },
      );
      final index = task.consent!.ruleChunkIndex!;
      expect(client.contexts.length, task.consent!.plan.chunks.length);
      for (var chunk = 0; chunk < client.contexts.length; chunk++) {
        final payload =
            jsonDecode(client.contexts[chunk]) as Map<String, dynamic>;
        expect(payload.containsKey('rule_request'), chunk == index);
        expect(
          client.prompts[chunk].contains('No rule creation was requested'),
          chunk != index,
        );
      }
      expect(task.ruleProposals, isEmpty);
      await _scrollAiResult(
        tester,
        find.text(lookupAppLocalizations(const Locale('zh')).aiRuleNoProposals),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('joint rules default off never grants rule permission', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final client = _SyntheticClient();
    final task = await _pumpCompletedAiPanel(
      tester,
      session,
      client,
      beforePrepare: (task) async {
        expect(
          tester
              .widget<Checkbox>(find.byKey(const ValueKey('ai-request-rules')))
              .value,
          isFalse,
        );
        expect(client.requestCount, 0);
      },
    );
    expect(task.consent!.ruleRequest, isNull);
    expect(task.consent!.ruleChunkIndex, isNull);
    expect(
      jsonDecode(client.lastUserContext!),
      isNot(contains('rule_request')),
    );
    expect(task.ruleProposals, isEmpty);
    await _scrollAiResult(tester, find.textContaining('本次未请求规则候选'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'joint rules changing authorization or samples revokes consent without losing focus',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final session = EditorSession.withStore(store: _BookStore());
      await session.open('book');
      addTearDown(session.dispose);
      final selection = AiAdvertisementRequest.fromSelection(
        book: session.book!,
        sessionId: session.sessionId!,
        sessionRevision: session.saveSeq,
        chapterId: 'first',
        blockId: 'paragraph-first',
        startUtf16: 0,
        endUtf16: 2,
        original: '广告',
      );
      final client = _SyntheticClient(withRules: true);
      final task = await _pumpCompletedAiPanel(
        tester,
        session,
        client,
        selection: selection,
        themeMode: ThemeMode.dark,
        beforePrepare: (task) async {
          Future<void> prepare() async {
            await _tapAi(tester, 'ai-prepare');
            await _pumpUntil(
              tester,
              () => task.phase == AiProofreadingPhase.awaitingConsent,
            );
          }

          await prepare();
          final old = task.consent!;
          await _tapAi(tester, 'ai-request-rules');
          expect(task.phase, AiProofreadingPhase.cancelled);
          expect(find.byKey(const ValueKey('ai-run')), findsNothing);
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('ai-rule-positive')),
                )
                .controller!
                .text,
            '广告',
          );
          await prepare();
          expect(task.consent, isNot(same(old)));
          expect(task.consent!.advertisementSelection, same(selection));
          await tester.ensureVisible(
            find.byKey(const ValueKey('ai-rule-negative')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('ai-rule-negative')),
            '正文',
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 240);
          await tester.pump();
          expect(task.phase, AiProofreadingPhase.cancelled);
          expect(find.byKey(const ValueKey('ai-run')), findsNothing);
          expect(client.requestCount, 0);
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding();
          await tester.enterText(
            find.byKey(const ValueKey('ai-rule-negative')),
            '',
          );
          tester.testTextInput.hide();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
        },
      );
      expect(task.consent!.advertisementSelection, same(selection));
      expect(task.ruleProposals, hasLength(1));
      final payload =
          jsonDecode(client.lastUserContext!) as Map<String, dynamic>;
      expect(payload, contains('rule_request'));
      expect(payload, contains('advertisement_selection'));
      expect(
        find.byKey(
          ValueKey('ai-use-rule-${task.ruleProposals.single.proposalId}'),
        ),
        findsNothing,
      );
      await _tapAi(tester, 'ai-request-rules');
      expect(task.ruleProposals, isEmpty);
      expect(task.phase, AiProofreadingPhase.cancelled);
      expect(find.byKey(const ValueKey('ai-run')), findsNothing);
      expect(
        find.byKey(const ValueKey('ai-advertisement-selection-source')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final applyRule in [false, true]) {
    testWidgets(
      'joint rules real proofreading parent workbench ${applyRule ? 'edit expires' : 'save returns to'} body proposals',
      (tester) async {
        final session = EditorSession.withStore(store: _BookStore());
        await session.open('book');
        addTearDown(session.dispose);
        final database = AppDatabase.memory();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(database.close);
        });
        final store = SettingsProofreadingRuleStore(database);
        final revision = session.saveSeq;
        var handoffs = 0;
        final task = await _pumpCompletedAiPanel(
          tester,
          session,
          _SyntheticClient(withRules: true),
          proofreadingParent: true,
          ruleStore: store,
          onUseRule: (rule) {
            handoffs++;
            final context = tester.element(find.byType(AiProofreadingPanel));
            showDialog<void>(
              context: context,
              builder: (dialog) => Dialog(
                child: SizedBox(
                  width: 700,
                  height: 700,
                  child: Column(
                    children: [
                      CloseButton(onPressed: () => Navigator.of(dialog).pop()),
                      Expanded(
                        child: RuleWorkbenchPanel(
                          session: session,
                          initialRule: rule,
                          initialSessionId: session.sessionId,
                          initialSaveSeq: session.saveSeq,
                          onLocate: (chapterId, blockId) async {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          beforePrepare: (_) async {
            await _tapAi(tester, 'ai-request-rules');
            await tester.ensureVisible(
              find.byKey(const ValueKey('ai-rule-positive')),
            );
            await tester.enterText(
              find.byKey(const ValueKey('ai-rule-positive')),
              '广告',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pump();
          },
        );
        expect(task.changes, hasLength(1));
        expect(task.ruleProposals, hasLength(1));
        final proposal = task.ruleProposals.single;
        await _tapAi(tester, 'ai-rule-tile-${proposal.proposalId}');
        await _tapAi(tester, 'ai-use-rule-${proposal.proposalId}');
        await _pumpUntil(
          tester,
          () => find.byType(RuleWorkbenchPanel).evaluate().isNotEmpty,
        );
        final panel = tester.widget<RuleWorkbenchPanel>(
          find.byType(RuleWorkbenchPanel),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(RuleWorkbenchPanel)),
        );
        final workbench = container.read(ruleWorkbenchTaskProvider(session));
        await _pumpUntil(tester, () => workbench.rules.isNotEmpty);
        expect(panel.initialRule, same(proposal.rule));
        expect(handoffs, 1);
        expect(workbench.trial, isNull);
        expect(await tester.runAsync(() => store.loadForBook('book')), isEmpty);
        expect(session.saveSeq, revision);
        expect(task.canApply, isTrue);
        await _tapRule(tester, 'rule-scan');
        await _pumpUntil(tester, () => workbench.hasCurrentTrial);
        if (applyRule) {
          await _tapRule(tester, 'rule-check-${workbench.matches.single.id}');
          await _tapRule(tester, 'rule-apply-selected');
          await _pumpUntil(tester, () => session.saveSeq != revision);
        } else {
          await _tapRule(tester, 'rule-save');
          await _pumpUntil(tester, () => workbench.isSaved(proposal.rule.id));
          expect(session.saveSeq, revision);
          expect(
            await tester.runAsync(() => store.loadForBook('book')),
            hasLength(1),
          );
        }
        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        expect(find.byType(AiProofreadingPanel), findsOneWidget);
        expect(task.canUseRuleProposals, !applyRule);
        if (applyRule) {
          expect(task.canApply, isFalse);
          expect(task.ruleProposals, isEmpty);
          expect(
            find.byKey(ValueKey('ai-use-rule-${proposal.proposalId}')),
            findsNothing,
          );
        } else {
          expect(task.canApply, isTrue);
          await _tapAi(tester, 'ai-change-${task.changes.single.id}');
          await _tapAi(tester, 'ai-apply-selected');
          await _pumpUntil(
            tester,
            () => task.phase == AiProofreadingPhase.applied,
          );
          expect(
            session.activeChapter!.blocks.whereType<TextBlock>().first.text,
            '原文。',
          );
          expect(task.canUseRuleProposals, isFalse);
        }
        await tester.runAsync(session.flush);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('joint rules rule-only result is not no findings', (
    tester,
  ) async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final task = await _pumpCompletedAiPanel(
      tester,
      session,
      _SyntheticClient(withRules: true, rulesOnly: true),
      beforePrepare: (_) async {
        await _tapAi(tester, 'ai-request-rules');
        await tester.ensureVisible(
          find.byKey(const ValueKey('ai-rule-positive')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('ai-rule-positive')),
          '广告',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
      },
    );
    await _scrollAiResult(
      tester,
      find.byKey(const ValueKey('ai-rule-results')),
    );
    expect(task.ruleProposals, hasLength(1));
    expect(
      find.text(
        lookupAppLocalizations(const Locale('zh')).aiProofreadingNoFindings,
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('ai-apply-selected')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'advertisement selection previews exact sent scope and confirms',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final session = EditorSession.withStore(
        store: _BookStore(
          firstText: '前文广告原文。后文',
          firstFollowingBlocks: const [
            TextBlock(id: 'adjacent', text: '邻接只读正文。'),
          ],
        ),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final selection = AiAdvertisementRequest.fromSelection(
        book: session.book!,
        sessionId: session.sessionId!,
        sessionRevision: session.saveSeq,
        chapterId: 'first',
        blockId: 'paragraph-first',
        startUtf16: 2,
        endUtf16: 4,
        original: '广告',
        ruleName: '站点候选',
      );
      final client = _SyntheticClient();
      late AiProofreadingTask task;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiProofreadingTaskProvider(session).overrideWith(
              (ref) => task = AiProofreadingTask(
                session: session,
                loadConfiguration: () async => const AiConfiguration(
                  enabled: true,
                  address: 'http://localhost:9823/v1',
                  model: 'test-model',
                  credentialReference: 'test-key',
                ),
                credentials: _SyntheticCredentials(),
                createClient: () => client,
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AiProofreadingPanel(
                session: session,
                initialAdvertisementSelection: selection,
                onLocate: (chapterId, blockId) async {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('站点候选'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ai-advertisement-selection-text')),
        findsOneWidget,
      );
      expect(task.phase, AiProofreadingPhase.idle);
      expect(client.requestCount, 0);
      expect(find.byKey(const ValueKey('ai-run')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('ai-prepare')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-prepare')));
      await _pumpUntil(
        tester,
        () => task.phase == AiProofreadingPhase.awaitingConsent,
      );
      final consent = task.consent!;
      expect(consent.advertisementSelection, same(selection));
      expect(consent.plan.chunks, hasLength(1));
      expect(consent.plan.chunks.single.slices.last.text, '邻接只读正文。');
      expect(consent.plan.chunks.single.slices.first.text, '广告');
      expect(find.text('邻接只读正文。'), findsOneWidget);
      expect(client.requestCount, 0);
      final chunkTile = find.byKey(const ValueKey('ai-chunk-0'));
      final outerScroll = find
          .descendant(
            of: find.byType(AiProofreadingPanel),
            matching: find.byType(Scrollable),
          )
          .first;
      for (
        var attempt = 0;
        attempt < 12 && chunkTile.evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(outerScroll, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      expect(chunkTile, findsOneWidget);
      await tester.ensureVisible(chunkTile);
      await tester.tap(chunkTile);
      await tester.pump(const Duration(milliseconds: 200));
      final preview = tester
          .widget<SelectableText>(
            find.descendant(
              of: chunkTile,
              matching: find.byType(SelectableText),
            ),
          )
          .data!;
      final payload = jsonDecode(preview) as Map<String, dynamic>;
      expect(payload['advertisement_selection'], selection.toJson());
      final blocks =
          (payload['context'] as Map<String, dynamic>)['blocks']
              as List<dynamic>;
      expect((blocks.first as Map<String, dynamic>)['text'], '广告');
      expect((blocks.last as Map<String, dynamic>)['text'], '邻接只读正文。');
      final run = find.byKey(const ValueKey('ai-run'));
      await tester.ensureVisible(run);
      await tester.tap(run);
      await _pumpUntil(
        tester,
        () => task.phase == AiProofreadingPhase.completed,
      );
      expect(client.requestCount, 1);
      expect(client.lastUserContext, preview);
      expect(client.lastSystemPrompt, contains('advertisement_selection'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing scope and stale selection revoke old consent', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(firstText: '前文广告原文。后文'),
    );
    await session.open('book');
    addTearDown(session.dispose);
    AiAdvertisementRequest request() => AiAdvertisementRequest.fromSelection(
      book: session.book!,
      sessionId: session.sessionId!,
      sessionRevision: session.saveSeq,
      chapterId: 'first',
      blockId: 'paragraph-first',
      startUtf16: 2,
      endUtf16: 4,
      original: '广告',
    );
    final selection = request();
    final client = _SyntheticClient();
    late AiProofreadingTask task;
    Widget panel(AiAdvertisementRequest selected) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        aiProofreadingTaskProvider(session).overrideWith(
          (ref) => task = AiProofreadingTask(
            session: session,
            loadConfiguration: () async => const AiConfiguration(
              enabled: true,
              address: 'http://localhost:9823/v1',
              model: 'test-model',
              credentialReference: 'test-key',
            ),
            credentials: _SyntheticCredentials(),
            createClient: () => client,
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiProofreadingPanel(
            session: session,
            initialAdvertisementSelection: selected,
            onLocate: (chapterId, blockId) async {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(panel(selection));
    await _tapAi(tester, 'ai-prepare');
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    final oldRun = tester
        .widget<FilledButton>(find.byKey(const ValueKey('ai-run')))
        .onPressed!;
    await _tapAi(tester, 'ai-chapter-second');
    expect(find.byKey(const ValueKey('ai-run')), findsNothing);
    expect(task.phase, AiProofreadingPhase.cancelled);
    oldRun();
    await tester.pump();
    expect(client.requestCount, 0);

    await tester.pumpWidget(panel(request()));
    await _tapAi(tester, 'ai-prepare');
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    final staleRun = tester
        .widget<FilledButton>(find.byKey(const ValueKey('ai-run')))
        .onPressed!;
    session.editBlockText('paragraph-first', '已改动正文');
    await tester.pump();
    expect(find.textContaining('广告选区已失效'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-run')), findsNothing);
    staleRun();
    await tester.pump();
    expect(client.requestCount, 0);
    await session.flush();
    expect(tester.takeException(), isNull);
  });

  test(
    'opening an editor AI task does not initialize unused configuration',
    () {
      final session = EditorSession.withStore(store: _BookStore());
      var configurationBuilds = 0;
      final container = ProviderContainer(
        overrides: [
          aiConfigurationServiceProvider.overrideWith((ref) {
            configurationBuilds++;
            throw StateError('AI configuration must remain lazy.');
          }),
        ],
      );
      try {
        final subscription = container.listen(
          aiProofreadingTaskProvider(session),
          (previous, next) {},
        );
        expect(subscription.read().phase, AiProofreadingPhase.idle);
        expect(configurationBuilds, 0);
      } finally {
        container.dispose();
        session.dispose();
      }
    },
  );

  testWidgets('AI tool offers chapter choices at 320 width and 2x text', (
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
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    var clientCreated = 0;
    late AiProofreadingTask task;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiProofreadingTaskProvider(session).overrideWith(
            (ref) => task = AiProofreadingTask(
              session: session,
              loadConfiguration: () async => const AiConfiguration(
                enabled: true,
                address: 'http://localhost:9823/v1',
                model: 'test-model',
                credentialReference: 'test-key',
              ),
              credentials: SecureAiCredentialStore(),
              createClient: () {
                clientCreated++;
                return AiHttpClient();
              },
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ProofreadingPanel(
              session: session,
              onLocate: (chapterId, blockId) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final aiTool = find.text(l10n.aiProofreadingTitle);
    await tester.ensureVisible(aiTool);
    await tester.tap(aiTool);
    await tester.pump();
    expect(find.text(l10n.aiProofreadingPrepare), findsOneWidget);
    expect(find.text(l10n.aiProofreadingStart), findsNothing);
    final missing = find.text(l10n.aiProofreadingMissingChapter);
    await tester.ensureVisible(missing);
    await tester.tap(missing);
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.idle);
    expect(
      find.text('${l10n.aiProofreadingSelectedChapters}: 2'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('ai-chapter-first')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('ai-chapter-second')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('ai-prepare')));
    for (
      var attempt = 0;
      attempt < 100 && find.byKey(const ValueKey('ai-run')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(find.byKey(const ValueKey('ai-run')), findsOneWidget);
    expect(
      find.textContaining('http://localhost:9823/v1/chat/completions'),
      findsOneWidget,
    );
    expect(find.textContaining('test-model'), findsOneWidget);
    expect(clientCreated, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('split result previews and applies one change at 320 width', (
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
    const source = '😀前章引子\r\n第三章 风雨\r\n当前章后文';
    const followingText = '下一段后续正文';
    final session = EditorSession.withStore(
      store: _BookStore(
        firstText: source,
        firstFollowingBlocks: const [
          TextBlock(id: 'following-first', text: followingText),
        ],
      ),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    final client = _SplitSyntheticClient();
    late AiProofreadingTask task;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiProofreadingTaskProvider(session).overrideWith(
            (ref) => task = AiProofreadingTask(
              session: session,
              loadConfiguration: () async => const AiConfiguration(
                enabled: true,
                address: 'http://localhost:9823/v1',
                model: 'test-model',
                credentialReference: 'test-key',
              ),
              credentials: _SyntheticCredentials(),
              createClient: () => client,
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ProofreadingPanel(
              session: session,
              onLocate: (chapterId, blockId) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final aiTool = find.text(l10n.aiProofreadingTitle);
    await tester.ensureVisible(aiTool);
    await tester.tap(aiTool);
    await tester.pump();
    final missing = find.text(l10n.aiProofreadingMissingChapter);
    await tester.ensureVisible(missing);
    await tester.tap(missing);
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.idle);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('ai-chapter-first')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('ai-chapter-second')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('ai-prepare')));
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    expect(task.consent!.chapterTitles.keys, containsAll(['first', 'second']));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ai-run')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-run')));
    await _pumpUntil(tester, () => task.phase == AiProofreadingPhase.completed);
    expect(task.splitChanges, hasLength(1));
    await tester.pumpAndSettle();
    expect(task.changes, isEmpty);
    expect(client.requestCount, 1);
    final change = task.splitChanges.single;
    final checkbox = find.byKey(ValueKey('ai-change-${change.id}'));
    final tile = find.byKey(ValueKey('ai-change-tile-${change.id}'));
    final changesScroll = find
        .descendant(
          of: find.byType(AiProofreadingPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(tile, 120, scrollable: changesScroll);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    final splitHeading = find.text('${l10n.aiProofreadingSplit}: 第三章 风雨');
    await tester.ensureVisible(splitHeading);
    await tester.pumpAndSettle();
    await tester.tap(splitHeading);
    await tester.pumpAndSettle();

    final prefix = source.substring(0, source.indexOf('第三章 风雨'));
    final suffix = source.substring(
      source.indexOf('第三章 风雨') + '第三章 风雨\r\n'.length,
    );
    expect(find.text(source), findsOneWidget);
    expect(find.text('${l10n.aiProofreadingSplitSource}: 第一章'), findsOneWidget);
    expect(find.text(prefix), findsOneWidget);
    expect(find.text('${l10n.aiProofreadingSplitNew}: 第三章 风雨'), findsOneWidget);
    expect(find.text(l10n.aiProofreadingSplitRemoveTitle), findsOneWidget);
    expect(find.text(suffix), findsOneWidget);
    expect(find.text(l10n.aiProofreadingSplitTopLevel), findsOneWidget);
    final followingCount = find.text(l10n.aiProofreadingSplitAfterCount(1));
    await _tapSplitTarget(tester, followingCount);
    expect(find.text(followingText), findsOneWidget);
    expect(find.text(l10n.aiProofreadingSplitResources), findsOneWidget);
    for (final preview in [
      find.text(source),
      find.text(prefix),
      find.text(suffix),
      find.text(followingText),
    ]) {
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      final rect = tester.getRect(preview);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
    }
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    final apply = find.byKey(const ValueKey('ai-apply-selected'));
    await tester.scrollUntilVisible(apply, -160, scrollable: changesScroll);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await _pumpUntil(tester, () => task.phase == AiProofreadingPhase.applied);
    expect(session.book!.chapters, hasLength(4));
    expect(session.book!.chapters[1].title, '第三章 风雨');
    expect(
      (session.book!.chapters
                  .firstWhere((chapter) => chapter.id == 'first')
                  .blocks
                  .singleWhere((block) => block.id == 'paragraph-first')
              as TextBlock)
          .text,
      prefix,
    );
    expect(session.canUndo, isTrue);

    await session.undo();
    await tester.pump();
    expect(session.book!.chapters.map((chapter) => chapter.id), [
      'first',
      'second',
      'third',
    ]);
    expect(
      (session.activeChapter!.blocks.firstWhere(
        (block) => block.id == 'paragraph-first',
      ) as TextBlock).text,
      source,
    );
    expect(session.canUndo, isFalse);
    await session.flush();
    await tester.pump();
    expect(session.dirty, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('split preview preserves mixed block order and parent volume', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final session = EditorSession.withStore(
      store: _BookStore(
        firstText: '前章正文\n第三章 风雨\n新章正文',
        firstParentTitle: '第一卷',
        firstPrecedingBlocks: const [
          TextBlock(id: 'before-text', text: '保留的前置正文'),
          ImageBlock(
            id: 'before-image',
            assetId: 'asset-before',
            caption: '保留的图注',
            alt: '保留的替代文本',
          ),
          FootnoteBlock(id: 'before-note', marker: '甲', text: '保留的脚注'),
          DividerBlock(id: 'before-divider'),
        ],
        firstFollowingBlocks: const [
          DividerBlock(id: 'after-divider'),
          FootnoteBlock(id: 'after-note', marker: '乙', text: '转移的脚注'),
          ImageBlock(
            id: 'after-image',
            assetId: 'asset-after',
            caption: '转移的图注',
            alt: '转移的替代文本',
          ),
          TextBlock(id: 'after-text', text: '转移的后续正文'),
        ],
      ),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final client = _SplitSyntheticClient();
    final task = await _pumpCompletedAiPanel(
      tester,
      session,
      client,
      missingChapter: true,
      themeMode: ThemeMode.dark,
    );
    final change = task.splitChanges.single;
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(change.sourceBlockIndex, 4);
    expect(change.sourceChapter.blocks.map((block) => block.id), [
      'before-text',
      'before-image',
      'before-note',
      'before-divider',
      'paragraph-first',
      'after-divider',
      'after-note',
      'after-image',
      'after-text',
    ]);
    expect(session.book!.chapters, hasLength(4));
    expect(session.canUndo, isFalse);
    await _tapSplitTarget(
      tester,
      find.text('${l10n.aiProofreadingSplit}: 第三章 风雨'),
    );
    expect(find.text('${l10n.aiProofreadingSplitParent}: 第一卷'), findsOneWidget);
    final before = find.byKey(ValueKey('ai-split-before-${change.id}'));
    final after = find.byKey(ValueKey('ai-split-after-${change.id}'));
    expect(find.text(l10n.aiProofreadingSplitBeforeCount(4)), findsOneWidget);
    expect(find.text(l10n.aiProofreadingSplitAfterCount(4)), findsOneWidget);
    final beforeTitle = find.text(l10n.aiProofreadingSplitBeforeCount(4));
    await _tapSplitTarget(tester, beforeTitle);
    expect(_splitBlockLabels(tester, before), [
      '${l10n.ruleWorkbenchTextBlock} · before-text',
      '${l10n.ruleWorkbenchImageBlock} · before-image',
      '${l10n.ruleWorkbenchFootnoteBlock} · before-note',
      '${l10n.ruleWorkbenchDividerBlock} · before-divider',
    ]);
    for (final value in [
      '保留的前置正文',
      '${l10n.ruleWorkbenchAssetId}: asset-before',
      '${l10n.aiProofreadingSplitCaption}: 保留的图注',
      '${l10n.aiProofreadingSplitAlt}: 保留的替代文本',
      '${l10n.aiProofreadingSplitMarker}: 甲',
      '保留的脚注',
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    final afterTitle = find.text(l10n.aiProofreadingSplitAfterCount(4));
    await _tapSplitTarget(tester, afterTitle);
    expect(_splitBlockLabels(tester, after), [
      '${l10n.ruleWorkbenchDividerBlock} · after-divider',
      '${l10n.ruleWorkbenchFootnoteBlock} · after-note',
      '${l10n.ruleWorkbenchImageBlock} · after-image',
      '${l10n.ruleWorkbenchTextBlock} · after-text',
    ]);
    for (final value in [
      '${l10n.aiProofreadingSplitMarker}: 乙',
      '转移的脚注',
      '${l10n.ruleWorkbenchAssetId}: asset-after',
      '${l10n.aiProofreadingSplitCaption}: 转移的图注',
      '${l10n.aiProofreadingSplitAlt}: 转移的替代文本',
      '转移的后续正文',
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    final blockLefts = <double>[
      for (final label in [
        ..._splitBlockLabels(tester, before),
        ..._splitBlockLabels(tester, after),
      ])
        tester.getRect(find.text(label)).left,
    ];
    expect(blockLefts, hasLength(8));
    expect(blockLefts.toSet(), hasLength(1));
    expect(blockLefts.first, lessThan(320 / 3));
    tester.view.physicalSize = const Size(1280, 900);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();
    final wideLefts = <double>[
      for (final label in [
        ..._splitBlockLabels(tester, before),
        ..._splitBlockLabels(tester, after),
      ])
        tester.getRect(find.text(label)).left,
    ];
    expect(wideLefts.toSet(), hasLength(1));
    expect(
      wideLefts.first,
      closeTo(tester.getRect(find.text(change.sourceBlock.text)).left, 1),
    );
    expect(client.requestCount, 1);
    expect(session.canUndo, isFalse);
    expect(session.book!.chapters, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('split block lists page in hundreds and reset on new results', (
    tester,
  ) async {
    final session = EditorSession.withStore(
      store: _BookStore(
        firstText: '前文\n第三章 风雨\n后文',
        firstPrecedingBlocks: [
          for (var index = 1; index <= 105; index++)
            DividerBlock(id: 'lead-$index'),
        ],
        firstFollowingBlocks: [
          for (var index = 1; index <= 205; index++)
            DividerBlock(id: 'tail-$index'),
        ],
      ),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final client = _SplitSyntheticClient();
    final task = await _pumpCompletedAiPanel(
      tester,
      session,
      client,
      missingChapter: true,
    );
    final first = task.splitChanges.single;
    final l10n = lookupAppLocalizations(const Locale('zh'));
    await _tapSplitTarget(
      tester,
      find.text('${l10n.aiProofreadingSplit}: 第三章 风雨'),
    );
    final beforeTitle = find.text(l10n.aiProofreadingSplitBeforeCount(105));
    await _tapSplitTarget(tester, beforeTitle);
    final before = find.byKey(ValueKey('ai-split-before-${first.id}'));
    expect(tester.widget<ExpansionTile>(before).children, hasLength(101));
    expect(
      find.text('${l10n.ruleWorkbenchDividerBlock} · lead-101'),
      findsNothing,
    );
    final beforeMore = find.byKey(ValueKey('ai-split-more-before-${first.id}'));
    final staleBefore = tester.widget<TextButton>(beforeMore).onPressed!;
    await _tapSplitTarget(tester, beforeMore);
    expect(tester.widget<ExpansionTile>(before).children, hasLength(105));
    expect(beforeMore, findsNothing);
    expect(
      find.text('${l10n.ruleWorkbenchDividerBlock} · lead-105'),
      findsOneWidget,
    );
    final afterTitle = find.text(l10n.aiProofreadingSplitAfterCount(205));
    await _tapSplitTarget(tester, afterTitle);
    final after = find.byKey(ValueKey('ai-split-after-${first.id}'));
    expect(tester.widget<ExpansionTile>(after).children, hasLength(101));
    expect(
      find.text('${l10n.ruleWorkbenchDividerBlock} · tail-101'),
      findsNothing,
    );
    final more = find.byKey(ValueKey('ai-split-more-after-${first.id}'));
    final staleCallback = tester.widget<TextButton>(more).onPressed!;
    await _tapSplitTarget(tester, more);
    expect(tester.widget<ExpansionTile>(after).children, hasLength(201));
    expect(
      find.text('${l10n.ruleWorkbenchDividerBlock} · tail-101'),
      findsOneWidget,
    );
    await _tapSplitTarget(tester, more);
    expect(tester.widget<ExpansionTile>(after).children, hasLength(205));
    expect(more, findsNothing);
    expect(
      find.text('${l10n.ruleWorkbenchDividerBlock} · tail-205'),
      findsOneWidget,
    );

    task.cancel();
    await tester.pumpAndSettle();
    staleBefore();
    staleCallback();
    await tester.pumpAndSettle();
    expect(task.phase, AiProofreadingPhase.cancelled);
    await _tapAi(tester, 'ai-prepare');
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    await _tapAi(tester, 'ai-run');
    await _pumpUntil(tester, () => task.phase == AiProofreadingPhase.completed);
    final second = task.splitChanges.single;
    staleBefore();
    staleCallback();
    await tester.pumpAndSettle();
    await _tapSplitTarget(
      tester,
      find.text('${l10n.aiProofreadingSplit}: 第三章 风雨'),
    );
    await _tapSplitTarget(tester, beforeTitle);
    expect(
      tester
          .widget<ExpansionTile>(
            find.byKey(ValueKey('ai-split-before-${second.id}')),
          )
          .children,
      hasLength(101),
    );
    expect(
      find.text('${l10n.ruleWorkbenchDividerBlock} · lead-101'),
      findsNothing,
    );
    await _tapSplitTarget(tester, afterTitle);
    expect(
      tester
          .widget<ExpansionTile>(
            find.byKey(ValueKey('ai-split-after-${second.id}')),
          )
          .children,
      hasLength(101),
    );
    expect(
      find.text('${l10n.ruleWorkbenchDividerBlock} · tail-101'),
      findsNothing,
    );
    expect(client.requestCount, 2);
    expect(session.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing AI scope invalidates completed changes and consent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final panelVisible = ValueNotifier<bool>(true);
    addTearDown(panelVisible.dispose);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    final client = _SyntheticClient();
    late AiProofreadingTask task;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiProofreadingTaskProvider(session).overrideWith(
            (ref) => task = AiProofreadingTask(
              session: session,
              loadConfiguration: () async => const AiConfiguration(
                enabled: true,
                address: 'http://localhost:9823/v1',
                model: 'test-model',
                credentialReference: 'test-key',
              ),
              credentials: _SyntheticCredentials(),
              createClient: () => client,
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(
              aiProofreadingTaskProvider(session).select((task) => null),
            );
            return MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: panelVisible,
                  builder: (context, visible, child) => visible
                      ? ProofreadingPanel(
                          session: session,
                          onLocate: (chapterId, blockId) async {
                            panelVisible.value = false;
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final aiTool = find.text(l10n.aiProofreadingTitle);
    await tester.ensureVisible(aiTool);
    await tester.tap(aiTool);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ai-prepare')));
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('ai-run')));
    await tester.tap(find.byKey(const ValueKey('ai-run')));
    await _pumpUntil(tester, () => task.phase == AiProofreadingPhase.completed);
    expect(task.canApply, isTrue);
    expect(task.changes, hasLength(1));
    expect(client.requestCount, 1);
    final changeId = task.changes.single.id;
    final changesScroll = find
        .descendant(
          of: find.byType(AiProofreadingPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('ai-change-tile-$changeId')),
      160,
      scrollable: changesScroll,
    );
    await tester.tap(find.byKey(ValueKey('ai-change-tile-$changeId')));
    await tester.pumpAndSettle();
    final locate = find.byKey(ValueKey('ai-locate-$changeId'));
    await tester.ensureVisible(locate);
    await tester.pump();
    await tester.tap(locate);
    await tester.pump();
    expect(find.byType(ProofreadingPanel), findsNothing);
    expect(task.phase, AiProofreadingPhase.completed);
    panelVisible.value = true;
    await tester.pump();
    await tester.ensureVisible(aiTool);
    await tester.tap(aiTool);
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.completed);
    expect(task.changes.single.id, changeId);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('ai-change-tile-$changeId')),
      160,
      scrollable: find
          .descendant(
            of: find.byType(AiProofreadingPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(ValueKey('ai-change-$changeId')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('ai-apply-selected')))
          .onPressed,
      isNotNull,
    );

    final secondChapter = find.byKey(const ValueKey('ai-chapter-second'));
    await tester.ensureVisible(secondChapter);
    await tester.tap(secondChapter);
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.cancelled);
    expect(task.canApply, isFalse);
    expect(task.changes, isEmpty);
    expect(find.byKey(const ValueKey('ai-apply-selected')), findsNothing);
    expect(find.byKey(ValueKey('ai-change-$changeId')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai-prepare')));
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    expect(find.byKey(const ValueKey('ai-run')), findsOneWidget);
    await tester.ensureVisible(secondChapter);
    await tester.tap(secondChapter);
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.cancelled);
    panelVisible.value = false;
    await tester.pump();
    panelVisible.value = true;
    await tester.pump();
    await tester.ensureVisible(aiTool);
    await tester.tap(aiTool);
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-run')), findsNothing);
    expect(find.byKey(ValueKey('ai-change-$changeId')), findsNothing);
    await tester.ensureVisible(secondChapter);
    await tester.tap(secondChapter);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-prepare')));
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    expect(find.byKey(const ValueKey('ai-run')), findsOneWidget);
    final missing = find.text(l10n.aiProofreadingMissingChapter);
    await tester.ensureVisible(missing);
    await tester.tap(missing);
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.cancelled);
    expect(find.byKey(const ValueKey('ai-run')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai-prepare')));
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    expect(find.byKey(const ValueKey('ai-run')), findsOneWidget);
    panelVisible.value = false;
    await tester.pump();
    panelVisible.value = true;
    await tester.pump();
    await tester.ensureVisible(aiTool);
    await tester.tap(aiTool);
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, l10n.aiProofreadingMissingChapter),
          )
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('ai-run')), findsOneWidget);
    final currentChapter = find.text(l10n.aiProofreadingCurrentChapter);
    await tester.ensureVisible(currentChapter);
    await tester.tap(currentChapter);
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.cancelled);
    expect(find.byKey(const ValueKey('ai-run')), findsNothing);
    expect(client.requestCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing a busy AI panel cancels its task after disposal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final panelVisible = ValueNotifier<bool>(true);
    addTearDown(panelVisible.dispose);
    final configuration = Completer<AiConfiguration>();
    late AiProofreadingTask task;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiProofreadingTaskProvider(session).overrideWith(
            (ref) => task = AiProofreadingTask(
              session: session,
              loadConfiguration: () => configuration.future,
              credentials: SecureAiCredentialStore(),
              createClient: AiHttpClient.new,
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(
              aiProofreadingTaskProvider(session).select((task) => null),
            );
            return MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: panelVisible,
                  builder: (context, visible, child) => visible
                      ? ProofreadingPanel(
                          session: session,
                          onLocate: (chapterId, blockId) async {},
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final aiTool = find.text(
      lookupAppLocalizations(const Locale('zh')).aiProofreadingTitle,
    );
    await tester.ensureVisible(aiTool);
    await tester.tap(aiTool);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('ai-prepare')));
    await tester.tap(find.byKey(const ValueKey('ai-prepare')));
    expect(task.isBusy, isTrue);
    panelVisible.value = false;
    await tester.pump();
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.cancelled);
    configuration.complete(const AiConfiguration());
    await _pumpUntil(tester, () => !task.isBusy);
    expect(task.phase, AiProofreadingPhase.cancelled);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ignored text change disappears and restore does not reselect it',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final session = EditorSession.withStore(store: _BookStore());
      await session.open('book');
      addTearDown(session.dispose);
      final task = await _pumpCompletedAiPanel(
        tester,
        session,
        _SyntheticClient(),
      );
      final change = task.changes.single;
      final checkbox = find.byKey(ValueKey('ai-change-${change.id}'));
      final tile = find.byKey(ValueKey('ai-change-tile-${change.id}'));
      await _scrollAiResult(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);

      final ignore = find.byKey(ValueKey('ai-ignore-${change.finding.id}'));
      await tester.ensureVisible(ignore);
      await tester.pumpAndSettle();
      await tester.tap(ignore);
      await tester.pumpAndSettle();
      expect(task.visibleChanges, isEmpty);
      expect(task.ignoredFindingCount, 1);
      expect(tile, findsNothing);
      expect(find.byKey(const ValueKey('ai-apply-selected')), findsNothing);
      final restore = find.byKey(const ValueKey('ai-restore-ignored'));
      expect(restore, findsOneWidget);
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(task.ignoredFindingCount, 0);
      await _scrollAiResult(tester, tile);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('ai-apply-selected')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'remove block previews impact and only explicit application removes it',
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
      const source = '广告原文。';
      const following = '随后保留的正文';
      final session = EditorSession.withStore(
        store: _BookStore(
          firstFollowingBlocks: const [
            TextBlock(id: 'following-first', text: following),
          ],
        ),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final l10n = lookupAppLocalizations(const Locale('zh'));
      final task = await _pumpCompletedAiPanel(
        tester,
        session,
        _SyntheticClient(wholeBlockAction: 'remove_block'),
        themeMode: ThemeMode.dark,
      );
      expect(task.changes, hasLength(1));
      final change = task.changes.single;
      final tile = find.byKey(ValueKey('ai-change-tile-${change.id}'));
      final checkbox = find.byKey(ValueKey('ai-change-${change.id}'));
      final impact = find.byKey(
        ValueKey('ai-remove-block-impact-${change.id}'),
      );
      await _scrollAiResult(tester, tile);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('ai-apply-selected')),
            )
            .onPressed,
        isNull,
      );
      expect(session.activeChapter!.blocks.map((block) => block.id), [
        'paragraph-first',
        'following-first',
      ]);
      expect(
        find.textContaining(l10n.aiProofreadingRemoveBlock),
        findsOneWidget,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text(source), findsOneWidget);
      expect(find.text('合成广告样例。'), findsOneWidget);
      expect(find.text(l10n.aiProofreadingReplacement), findsNothing);
      expect(
        tester.widget<Text>(impact).data,
        l10n.aiProofreadingRemoveBlockImpact,
      );
      await tester.ensureVisible(impact);
      await tester.pumpAndSettle();
      final impactRect = tester.getRect(impact);
      expect(impactRect.left, greaterThanOrEqualTo(0));
      expect(impactRect.right, lessThanOrEqualTo(320));
      expect(impactRect.bottom, lessThanOrEqualTo(900 - 280));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pump();
      final ignore = find.byKey(ValueKey('ai-ignore-${change.finding.id}'));
      await tester.ensureVisible(ignore);
      await tester.pumpAndSettle();
      await tester.tap(ignore);
      await tester.pumpAndSettle();
      expect(task.visibleChanges, isEmpty);
      expect(tile, findsNothing);
      final restore = find.byKey(const ValueKey('ai-restore-ignored'));
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      await _scrollAiResult(tester, tile);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('ai-apply-selected')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final applyOne = find.text(l10n.aiProofreadingApplyOne);
      await tester.ensureVisible(applyOne);
      await tester.pumpAndSettle();
      await tester.tap(applyOne);
      await _pumpUntil(tester, () => task.phase == AiProofreadingPhase.applied);
      expect(session.activeChapter!.blocks.map((block) => block.id), [
        'following-first',
      ]);
      expect(session.book!.chapters, hasLength(3));
      expect(session.canUndo, isTrue);
      await session.undo();
      await tester.pump();
      expect(session.activeChapter!.blocks.map((block) => block.id), [
        'paragraph-first',
        'following-first',
      ]);
      expect((session.activeChapter!.blocks.first as TextBlock).text, source);
      await session.flush();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'rename chapter previews full evidence and preserves body in ${themeMode.name}',
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
        const source = '第三章 风雨\n正文保留。';
        final session = EditorSession.withStore(
          store: _BookStore(
            firstText: source,
            firstFollowingBlocks: const [
              TextBlock(id: 'following-first', text: '后续段落。'),
              ImageBlock(id: 'image-first', assetId: 'cover'),
              FootnoteBlock(id: 'footnote-first', text: '脚注。'),
              DividerBlock(id: 'divider-first'),
            ],
          ),
        );
        await session.open('book');
        addTearDown(session.dispose);
        final originalBlocks = List<Block>.of(session.activeChapter!.blocks);
        final originalChapterIds = session.book!.chapters
            .map((chapter) => chapter.id)
            .toList();
        final task = await _pumpCompletedAiPanel(
          tester,
          session,
          _RenameChapterSyntheticClient(),
          missingChapter: true,
          themeMode: themeMode,
        );
        final l10n = lookupAppLocalizations(const Locale('zh'));
        expect(task.changes, hasLength(1));
        expect(task.splitChanges, isEmpty);
        final change = task.changes.single;
        expect(change.proposal.originalTitle, '第一章');
        expect(change.proposal.target.originalText, '第三章 风雨');
        final tile = find.byKey(ValueKey('ai-change-tile-${change.id}'));
        final checkbox = find.byKey(ValueKey('ai-change-${change.id}'));
        final impact = find.byKey(
          ValueKey('ai-rename-chapter-impact-${change.id}'),
        );
        await _scrollAiResult(tester, tile);
        expect(tester.widget<Checkbox>(checkbox).value, isFalse);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('ai-apply-selected')),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.textContaining(l10n.aiProofreadingRenameChapter),
          findsOneWidget,
        );
        expect(session.activeChapter!.title, '第一章');
        expect(session.activeChapter!.blocks, originalBlocks);

        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.text(l10n.aiProofreadingOriginalEvidence), findsOneWidget);
        expect(
          find.descendant(of: tile, matching: find.text('第三章 风雨')),
          findsNWidgets(2),
        );
        expect(
          find.text(l10n.aiProofreadingOriginalChapterTitle),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tile, matching: find.text('第一章')),
          findsOneWidget,
        );
        expect(find.text(l10n.aiProofreadingNewChapterTitle), findsOneWidget);
        expect(find.text(l10n.aiProofreadingReplacement), findsNothing);
        expect(find.text('将目录标题与正文标题行对齐。'), findsOneWidget);
        expect(
          tester.widget<Text>(impact).data,
          l10n.aiProofreadingRenameChapterImpact,
        );
        await tester.ensureVisible(impact);
        await tester.pumpAndSettle();
        final impactRect = tester.getRect(impact);
        expect(impactRect.left, greaterThanOrEqualTo(0));
        expect(impactRect.right, lessThanOrEqualTo(320));
        expect(impactRect.bottom, lessThanOrEqualTo(620));
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await tester.pump();
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);
        final ignore = find.byKey(ValueKey('ai-ignore-${change.finding.id}'));
        await tester.ensureVisible(ignore);
        await tester.pumpAndSettle();
        await tester.tap(ignore);
        await tester.pumpAndSettle();
        expect(task.visibleChanges, isEmpty);
        expect(tile, findsNothing);
        final restore = find.byKey(const ValueKey('ai-restore-ignored'));
        await tester.ensureVisible(restore);
        await tester.pumpAndSettle();
        await tester.tap(restore);
        await tester.pumpAndSettle();
        await _scrollAiResult(tester, tile);
        expect(tester.widget<Checkbox>(checkbox).value, isFalse);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('ai-apply-selected')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(tile);
        await tester.pumpAndSettle();
        final applyOne = find.text(l10n.aiProofreadingApplyOne);
        await tester.ensureVisible(applyOne);
        await tester.pumpAndSettle();
        await tester.tap(applyOne);
        await _pumpUntil(
          tester,
          () => task.phase == AiProofreadingPhase.applied,
        );
        expect(session.activeChapter!.title, '第三章 风雨');
        expect(session.activeChapter!.blocks, originalBlocks);
        expect(
          session.book!.chapters.map((chapter) => chapter.id),
          originalChapterIds,
        );
        expect(session.canUndo, isTrue);
        await session.undo();
        await tester.pump();
        expect(session.activeChapter!.title, '第一章');
        expect(session.activeChapter!.blocks, originalBlocks);
        expect(session.canRedo, isTrue);
        await session.redo();
        await tester.pump();
        expect(session.activeChapter!.title, '第三章 风雨');
        expect(session.activeChapter!.blocks, originalBlocks);
        await session.flush();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('rename chapter action and impact render in English', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final session = EditorSession.withStore(
      store: _BookStore(firstText: '第三章 风雨\n正文保留。'),
    );
    await session.open('book');
    addTearDown(session.dispose);
    final task = await _pumpCompletedAiPanel(
      tester,
      session,
      _RenameChapterSyntheticClient(),
      missingChapter: true,
      locale: const Locale('en'),
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    final change = task.changes.single;
    final tile = find.byKey(ValueKey('ai-change-tile-${change.id}'));
    await _scrollAiResult(tester, tile);
    expect(
      find.textContaining(l10n.aiProofreadingRenameChapter),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiProofreadingOriginalChapterTitle), findsOneWidget);
    expect(find.text(l10n.aiProofreadingNewChapterTitle), findsOneWidget);
    expect(find.text(l10n.aiProofreadingOriginalEvidence), findsOneWidget);
    expect(find.text(l10n.aiProofreadingRenameChapterImpact), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('whole-text delete remains a text edit', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final task = await _pumpCompletedAiPanel(
      tester,
      session,
      _SyntheticClient(wholeBlockAction: 'delete_text'),
    );
    final change = task.changes.single;
    final tile = find.byKey(ValueKey('ai-change-tile-${change.id}'));
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(l10n.aiProofreadingDelete, contains('保留正文块'));
    await _scrollAiResult(tester, tile);
    expect(find.textContaining(l10n.aiProofreadingDelete), findsOneWidget);
    expect(find.textContaining(l10n.aiProofreadingRemoveBlock), findsNothing);
    expect(
      find.byKey(ValueKey('ai-remove-block-impact-${change.id}')),
      findsNothing,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiProofreadingDelete), findsOneWidget);
    expect(find.text(l10n.aiProofreadingReplacement), findsOneWidget);
    expect(find.text('广告原文。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remove block action and impact render in English', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final task = await _pumpCompletedAiPanel(
      tester,
      session,
      _SyntheticClient(wholeBlockAction: 'remove_block'),
      locale: const Locale('en'),
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    final change = task.changes.single;
    final tile = find.byKey(ValueKey('ai-change-tile-${change.id}'));
    await _scrollAiResult(tester, tile);
    expect(find.textContaining(l10n.aiProofreadingRemoveBlock), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiProofreadingRemoveBlockImpact), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ignored split change disappears and stays unselected on restore',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final session = EditorSession.withStore(
        store: _BookStore(firstText: '前章\n第三章 风雨\n后文'),
      );
      await session.open('book');
      addTearDown(session.dispose);
      final task = await _pumpCompletedAiPanel(
        tester,
        session,
        _SplitSyntheticClient(),
        missingChapter: true,
      );
      final change = task.splitChanges.single;
      final tile = find.byKey(ValueKey('ai-change-tile-${change.id}'));
      final checkbox = find.byKey(ValueKey('ai-change-${change.id}'));
      await _scrollAiResult(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pump();
      final ignore = find.byKey(ValueKey('ai-ignore-${change.finding.id}'));
      await tester.ensureVisible(ignore);
      await tester.pumpAndSettle();
      await tester.tap(ignore);
      await tester.pumpAndSettle();
      expect(task.visibleSplitChanges, isEmpty);
      expect(tile, findsNothing);
      expect(find.byKey(const ValueKey('ai-apply-selected')), findsNothing);
      final restore = find.byKey(const ValueKey('ai-restore-ignored'));
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      await _scrollAiResult(tester, tile);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending finding can be ignored even when it is the only result',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final session = EditorSession.withStore(store: _BookStore());
      await session.open('book');
      addTearDown(session.dispose);
      final task = await _pumpCompletedAiPanel(
        tester,
        session,
        _SyntheticClient(pendingOnly: true),
      );
      expect(task.visibleChanges, isEmpty);
      final finding = task.findings.single;
      final tile = find.byKey(ValueKey('ai-finding-${finding.id}'));
      await _scrollAiResult(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final ignore = find.byKey(ValueKey('ai-ignore-${finding.id}'));
      await tester.ensureVisible(ignore);
      await tester.pumpAndSettle();
      await tester.tap(ignore);
      await tester.pumpAndSettle();
      expect(task.visibleFindings, isEmpty);
      expect(tile, findsNothing);
      final restore = find.byKey(const ValueKey('ai-restore-ignored'));
      expect(restore, findsOneWidget);
      expect(
        find.text(
          lookupAppLocalizations(const Locale('zh'))
              .aiProofreadingIgnoredCount(1),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      await _scrollAiResult(tester, tile);
      expect(tile, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale and prior result callbacks cannot edit later results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    addTearDown(session.dispose);
    final task = await _pumpCompletedAiPanel(
      tester,
      session,
      _SyntheticClient(),
    );
    final firstChange = task.changes.single;
    final tile = find.byKey(ValueKey('ai-change-tile-${firstChange.id}'));
    await _scrollAiResult(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final ignore = find.byKey(ValueKey('ai-ignore-${firstChange.finding.id}'));
    final oldIgnore = tester.widget<TextButton>(ignore).onPressed!;
    await tester.ensureVisible(ignore);
    await tester.pumpAndSettle();
    await tester.tap(ignore);
    await tester.pumpAndSettle();
    final restore = find.byKey(const ValueKey('ai-restore-ignored'));
    final oldRestore = tester.widget<TextButton>(restore).onPressed!;

    session.editChapterTitle('first', '第一章（修订）');
    await tester.pump();
    expect(task.phase, AiProofreadingPhase.stale);
    oldIgnore();
    oldRestore();
    expect(task.ignoredFindingCount, 0);
    expect(find.byKey(const ValueKey('ai-restore-ignored')), findsNothing);

    unawaited(
      task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: ['first'],
      ),
    );
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
    unawaited(task.run(task.consent!));
    await _pumpUntil(tester, () => task.phase == AiProofreadingPhase.completed);
    final laterFinding = task.findings.single;
    task.ignoreFinding(laterFinding.id);
    await tester.pump();
    expect(task.ignoredFindingCount, 1);
    oldRestore();
    oldIgnore();
    await tester.pump();
    expect(task.ignoredFindingCount, 1);
    expect(task.visibleFindings, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

Future<AiProofreadingTask> _pumpCompletedAiPanel(
  WidgetTester tester,
  EditorSession session,
  AiTextClient client, {
  bool missingChapter = false,
  ThemeMode themeMode = ThemeMode.light,
  Locale locale = const Locale('zh'),
  Future<void> Function(AiProofreadingTask task)? beforePrepare,
  Future<void> Function(AiProofreadingTask task)? afterPrepare,
  bool proofreadingParent = false,
  void Function(ProofreadingRule)? onUseRule,
  ProofreadingRuleStore? ruleStore,
  AiAdvertisementRequest? selection,
}) async {
  late AiProofreadingTask task;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (ruleStore != null)
          proofreadingRuleStoreProvider.overrideWithValue(ruleStore),
        aiProofreadingTaskProvider(session).overrideWith(
          (ref) => task = AiProofreadingTask(
            session: session,
            loadConfiguration: () async => const AiConfiguration(
              enabled: true,
              address: 'http://localhost:9823/v1',
              model: 'test-model',
              credentialReference: 'test-key',
            ),
            credentials: _SyntheticCredentials(),
            createClient: () => client,
          ),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        theme: AppTheme.light(glass: GlassQuality.off),
        darkTheme: AppTheme.dark(glass: GlassQuality.off),
        themeMode: themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: proofreadingParent
              ? ProofreadingPanel(
                  session: session,
                  onLocate: (chapterId, blockId) async {},
                  onUseRule: onUseRule,
                )
              : AiProofreadingPanel(
                  session: session,
                  onLocate: (chapterId, blockId) async {},
                  onUseRule: onUseRule,
                  initialAdvertisementSelection: selection,
                ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (proofreadingParent) {
    final chip = find.widgetWithText(FilterChip, 'AI 校对');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
  }
  if (missingChapter) {
    await tester.tap(find.byKey(const ValueKey('ai-intent-missingChapter')));
    await tester.pump();
  }
  if (beforePrepare != null) await beforePrepare(task);
  await tester.ensureVisible(find.byKey(const ValueKey('ai-prepare')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('ai-prepare')));
  await _pumpUntil(
    tester,
    () => task.phase == AiProofreadingPhase.awaitingConsent,
  );
  if (afterPrepare != null) await afterPrepare(task);
  await tester.ensureVisible(find.byKey(const ValueKey('ai-run')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('ai-run')));
  await _pumpUntil(tester, () => task.phase == AiProofreadingPhase.completed);
  await tester.pumpAndSettle();
  return task;
}

Future<void> _scrollAiResult(WidgetTester tester, Finder result) async {
  if (result.evaluate().isNotEmpty) {
    await tester.ensureVisible(result);
  } else {
    await tester.scrollUntilVisible(
      result,
      160,
      scrollable: find
          .descendant(
            of: find.byType(AiProofreadingPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _tapAi(WidgetTester tester, String key) async {
  await tester.pumpAndSettle();
  final target = find.byKey(ValueKey(key));
  await _scrollAiResult(tester, target);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _tapSplitTarget(WidgetTester tester, Finder target) async {
  final listView = find
      .descendant(
        of: find.byType(AiProofreadingPanel),
        matching: find.byType(ListView),
      )
      .first;
  final scrollable = find
      .descendant(of: listView, matching: find.byType(Scrollable))
      .first;
  final viewport = tester.getRect(scrollable);
  final position = tester.state<ScrollableState>(scrollable).position;
  for (var attempt = 0; attempt < 100; attempt++) {
    final elements = target.evaluate();
    if (elements.isNotEmpty) {
      final rect = tester.getRect(target);
      if (rect.top >= viewport.top && rect.bottom <= viewport.bottom) {
        await tester.tap(target);
        await tester.pumpAndSettle();
        return;
      }
      position.jumpTo(
        (position.pixels + (rect.top < viewport.top ? -350 : 350)).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    } else {
      position.jumpTo(
        (position.pixels + 350).clamp(0.0, position.maxScrollExtent),
      );
    }
    await tester.pumpAndSettle();
  }
  fail('Split preview target did not enter the viewport: $target');
}

List<String> _splitBlockLabels(WidgetTester tester, Finder tile) => tester
    .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
    .map((widget) => widget.data)
    .whereType<String>()
    .where((text) => text.contains(' · '))
    .toList();

Future<void> _tapRule(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
  } else {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find
          .descendant(
            of: find.byType(RuleWorkbenchPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
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

class _SyntheticCredentials implements AiCredentialStore {
  @override
  Future<String?> read(String reference) async => 'synthetic-key';

  @override
  Future<void> write(String reference, String value) async {}

  @override
  Future<void> delete(String reference) async {}
}

class _EmptyRecordingClient implements AiTextClient {
  final contexts = <String>[];
  final prompts = <String>[];

  @override
  Future<String> generate({
    required AiEndpoint endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
    required AiCancellation cancellation,
  }) async {
    contexts.add(userContext);
    prompts.add(systemPrompt);
    return jsonEncode({
      'schema_version': 1,
      'findings': <Object>[],
      'proposals': <Object>[],
      'rule_proposals': <Object>[],
    });
  }

  @override
  void dispose() {}
}

class _SyntheticClient implements AiTextClient {
  _SyntheticClient({
    this.pendingOnly = false,
    this.wholeBlockAction,
    this.withRules = false,
    this.rulesOnly = false,
  });

  final bool pendingOnly;
  final String? wholeBlockAction;
  final bool withRules;
  final bool rulesOnly;
  int requestCount = 0;
  String? lastUserContext;
  String? lastSystemPrompt;

  @override
  Future<String> generate({
    required AiEndpoint endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
    required AiCancellation cancellation,
  }) async {
    requestCount++;
    lastUserContext = userContext;
    lastSystemPrompt = systemPrompt;
    final original = wholeBlockAction == null ? '广告' : '广告原文。';
    final after = wholeBlockAction == null ? '原文。' : '';
    return jsonEncode({
      'schema_version': 1,
      'findings': rulesOnly
          ? <Object>[]
          : [
              {
                'id': 'ad-finding',
                'category': 'advertisement',
                'assessment': pendingOnly ? 'undetermined' : 'advertisement',
                'chapter_id': 'first',
                'block_id': 'paragraph-first',
                'original': original,
                'before': '',
                'after': after,
                'reason': '合成广告样例。',
              },
            ],
      'proposals': pendingOnly || rulesOnly
          ? <Object>[]
          : [
              {
                'id': 'ad-change',
                'finding_id': 'ad-finding',
                'action': wholeBlockAction ?? 'delete_text',
                'chapter_id': 'first',
                'block_id': 'paragraph-first',
                'original': original,
                'before': '',
                'after': after,
                'replacement': '',
                'reason': '合成广告样例。',
              },
            ],
      'rule_proposals': withRules
          ? [
              {
                'schema_version': 1,
                'name': '合成广告规则',
                'kind': 'advertisement',
                'target': 'body_line',
                'match': {
                  'mode': 'literal',
                  'pattern': '广告',
                  'case_sensitive': true,
                },
                'action': 'exact_deletion',
                'positive_examples': ['广告'],
                'negative_examples': <String>[],
                'reason': '仅根据提供的样例生成。',
              },
            ]
          : <Object>[],
    });
  }

  @override
  void dispose() {}
}

class _SplitSyntheticClient implements AiTextClient {
  int requestCount = 0;

  @override
  Future<String> generate({
    required AiEndpoint endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
    required AiCancellation cancellation,
  }) async {
    requestCount++;
    final envelope = jsonDecode(userContext) as Map<String, dynamic>;
    final context = envelope['context'] as Map<String, dynamic>;
    final blocks = context['blocks'] as List<dynamic>;
    final sourceBlocks = blocks.cast<Map<String, dynamic>>().where(
      (block) => block['block_id'] == 'paragraph-first',
    );
    if (sourceBlocks.isEmpty) {
      return jsonEncode({
        'schema_version': 1,
        'findings': <Object>[],
        'proposals': <Object>[],
        'rule_proposals': <Object>[],
      });
    }
    final slice = sourceBlocks.first;
    final text = slice['text'] as String;
    const heading = '第三章 风雨';
    final start = text.indexOf(heading);
    final end = start + heading.length;
    final target = {
      'chapter_id': slice['chapter_id'],
      'block_id': slice['block_id'],
      'original': heading,
      'before': text.substring(0, start),
      'after': text.substring(end),
    };
    return jsonEncode({
      'schema_version': 1,
      'findings': [
        {
          'id': 'split-finding',
          'category': 'missing_chapter',
          'assessment': 'missed_heading',
          ...target,
          'reason': '原文存在独立章节标题。',
        },
      ],
      'proposals': [
        {
          'id': 'split-proposal',
          'finding_id': 'split-finding',
          'action': 'split_chapter',
          ...target,
          'title': heading,
          'remove_title_line': true,
          'reason': '将标题行拆分为独立章节。',
        },
      ],
      'rule_proposals': <Object>[],
    });
  }

  @override
  void dispose() {}
}

class _RenameChapterSyntheticClient implements AiTextClient {
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
        'id': 'title-finding',
        'category': 'missing_chapter',
        'assessment': 'missed_heading',
        'chapter_id': 'first',
        'block_id': 'paragraph-first',
        'original': '第三章 风雨',
        'before': '',
        'after': '\n正文保留。',
        'reason': '目录标题与正文标题行不一致。',
      },
    ],
    'proposals': [
      {
        'id': 'title-change',
        'finding_id': 'title-finding',
        'action': 'rename_chapter',
        'chapter_id': 'first',
        'block_id': 'paragraph-first',
        'original': '第三章 风雨',
        'before': '',
        'after': '\n正文保留。',
        'original_title': '第一章',
        'replacement': '第三章 风雨',
        'reason': '将目录标题与正文标题行对齐。',
      },
    ],
    'rule_proposals': <Object>[],
  });

  @override
  void dispose() {}
}

class _BookStore implements EditorBookStore {
  _BookStore({
    this.firstText = '广告原文。',
    this.firstPrecedingBlocks = const <Block>[],
    this.firstFollowingBlocks = const <Block>[],
    String? firstParentTitle,
  }) : book = Book(
         id: 'book',
         meta: BookMeta(title: '书', author: '作者'),
         chapters: [
           if (firstParentTitle != null)
             Chapter(
               id: 'volume',
               bookId: 'book',
               title: firstParentTitle,
               level: 1,
             ),
           Chapter(
             id: 'first',
             bookId: 'book',
             title: '第一章',
             parentId: firstParentTitle == null ? null : 'volume',
           ),
           const Chapter(id: 'second', bookId: 'book', title: '第二章'),
           const Chapter(id: 'third', bookId: 'book', title: '第三章'),
         ],
         createdAt: DateTime.utc(2026, 11, 6),
         updatedAt: DateTime.utc(2026, 11, 6),
       );

  final String firstText;
  final List<Block> firstPrecedingBlocks;
  final List<Block> firstFollowingBlocks;

  final Book book;

  @override
  Future<Book?> loadBook(String bookId) async => bookId == 'book' ? book : null;

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async =>
      Chapter(
        id: chapterId,
        bookId: bookId,
        title: book.chapters
            .firstWhere((chapter) => chapter.id == chapterId)
            .title,
        parentId: book.chapters
            .firstWhere((chapter) => chapter.id == chapterId)
            .parentId,
        blocks: [
          if (chapterId == 'first') ...firstPrecedingBlocks,
          TextBlock(
            id: 'paragraph-$chapterId',
            text: chapterId == 'first' ? firstText : '原文。',
          ),
          if (chapterId == 'first') ...firstFollowingBlocks,
        ],
      );

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async => book;
}
