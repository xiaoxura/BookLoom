import 'dart:async';
import 'dart:convert';

import 'package:bookloom/app/ai_rule_providers.dart';
import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/application/ai_rule_creation_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/presentation/ai_rule_creation_panel.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = '前文\n  【卷二】夜雨  \n后文';
const _sample = '  【卷二】夜雨  ';
const _configuration = AiConfiguration(
  enabled: true,
  address: 'https://api.example.com/v1',
  model: 'test-model',
  credentialReference: 'test-key',
);

void main() {
  testWidgets(
    'review is local, editing invalidates consent, and result only transfers',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final store = _BookStore();
      final session = EditorSession.withStore(store: store);
      await session.open('book');
      addTearDown(session.dispose);
      final client = _Client();
      final credentials = _Credentials();
      final used = <ProofreadingRule>[];
      final mode = ValueNotifier(ThemeMode.light);
      addTearDown(mode.dispose);
      late AiRuleCreationTask task;
      final selection = AiRuleSelection(
        chapterId: 'first',
        blockId: 'paragraph',
        startUtf16: _source.indexOf(_sample),
        endUtf16: _source.indexOf(_sample) + _sample.length,
        original: _sample,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiRuleCreationTaskProvider(session).overrideWith(
              (ref) => task = AiRuleCreationTask(
                session: session,
                loadConfiguration: () async => _configuration,
                credentials: credentials,
                createClient: () => client,
                jobs: _InlineJobs(),
              ),
            ),
          ],
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: mode,
            builder: (context, value, child) => MaterialApp(
              locale: const Locale('zh'),
              theme: AppTheme.light(glass: GlassQuality.off),
              darkTheme: AppTheme.dark(glass: GlassQuality.off),
              themeMode: value,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(viewInsets: const EdgeInsets.only(bottom: 280)),
                    child: AiRuleCreationPanel(
                      session: session,
                      selection: selection,
                      initialKind: ProofreadingRuleKind.chapter,
                      onUseRule: used.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      expect(find.text(_sample), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-rule-send')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('ai-rule-intent')),
        '只识别独立章节标题',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-rule-negative')),
        '\n  普通正文  \r\n',
      );
      _press<FilledButton>(tester, const ValueKey('ai-rule-prepare'));
      await _pumpUntil(
        tester,
        () => task.phase == AiRuleCreationPhase.awaitingConsent,
      );
      expect(credentials.reads, 0);
      expect(client.calls, 0);
      expect(task.consent!.request.negativeExamples, ['  普通正文  ']);
      expect(
        find.textContaining('https://api.example.com/v1/chat/completions'),
        findsOneWidget,
      );
      expect(find.textContaining('OpenAI Chat Completions'), findsOneWidget);
      expect(find.textContaining('test-model'), findsOneWidget);
      expect(find.text(l10n.aiRuleBefore), findsOneWidget);
      expect(find.text(l10n.aiRuleAfter), findsOneWidget);
      expect(find.text('${l10n.aiRuleRelated}: 0'), findsOneWidget);
      mode.value = ThemeMode.dark;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byKey(const ValueKey('ai-rule-intent')),
        '只识别独立卷标题',
      );
      await tester.pump();
      expect(task.consent, isNull);
      expect(find.byKey(const ValueKey('ai-rule-send')), findsNothing);
      _press<FilledButton>(tester, const ValueKey('ai-rule-prepare'));
      await _pumpUntil(
        tester,
        () => task.phase == AiRuleCreationPhase.awaitingConsent,
      );
      _press<FilledButton>(tester, const ValueKey('ai-rule-send'));
      await _pumpUntil(
        tester,
        () => task.phase == AiRuleCreationPhase.completed,
      );
      expect(client.calls, 1);
      expect(credentials.reads, greaterThan(0));
      expect(store.saves, 0);
      expect((session.activeChapter!.blocks.single as TextBlock).text, _source);
      final proposal = task.proposals.single;
      final tile = find.byKey(
        ValueKey('ai-rule-proposal-${proposal.proposalId}'),
      );
      await tester.scrollUntilVisible(
        tile,
        300,
        scrollable: find
            .descendant(
              of: find.byType(AiRuleCreationPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final useButton = tester.widget<FilledButton>(
        find.byKey(ValueKey('ai-rule-use-${proposal.proposalId}')),
      );
      final oldCallback = useButton.onPressed!;
      oldCallback();
      expect(used, [proposal.rule]);
      expect(store.saves, 0);
      expect((session.activeChapter!.blocks.single as TextBlock).text, _source);
      session.editBlockText('paragraph', '已变化');
      await tester.pump();
      oldCallback();
      expect(task.canUseProposals, isFalse);
      expect(used, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'running task can be cancelled without transferring late result',
    (tester) async {
      final session = EditorSession.withStore(store: _BookStore());
      await session.open('book');
      addTearDown(session.dispose);
      final client = _Client()..response = Completer<String>();
      final used = <ProofreadingRule>[];
      late AiRuleCreationTask task;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiRuleCreationTaskProvider(session).overrideWith(
              (ref) => task = AiRuleCreationTask(
                session: session,
                loadConfiguration: () async => _configuration,
                credentials: _Credentials(),
                createClient: () => client,
                jobs: _InlineJobs(),
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AiRuleCreationPanel(
                session: session,
                selection: AiRuleSelection(
                  chapterId: 'first',
                  blockId: 'paragraph',
                  startUtf16: _source.indexOf(_sample),
                  endUtf16: _source.indexOf(_sample) + _sample.length,
                  original: _sample,
                ),
                initialKind: ProofreadingRuleKind.chapter,
                onUseRule: used.add,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-rule-intent')),
        '识别标题',
      );
      await tester.pump();
      _press<FilledButton>(tester, const ValueKey('ai-rule-prepare'));
      await _pumpUntil(
        tester,
        () => task.phase == AiRuleCreationPhase.awaitingConsent,
      );
      _press<FilledButton>(tester, const ValueKey('ai-rule-send'));
      await _pumpUntil(tester, () => task.phase == AiRuleCreationPhase.running);
      _press<TextButton>(tester, const ValueKey('ai-rule-cancel'));
      client.response!.complete(_ruleResponse());
      await tester.pumpAndSettle();
      expect(task.phase, AiRuleCreationPhase.cancelled);
      expect(task.proposals, isEmpty);
      expect(used, isEmpty);
    },
  );
}

void _press<T extends ButtonStyleButton>(WidgetTester tester, Key key) {
  tester.widget<T>(find.byKey(key)).onPressed!.call();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(ready(), isTrue);
  await tester.pump();
}

String _ruleResponse() => jsonEncode({
  'schema_version': 1,
  'findings': <Object>[],
  'proposals': <Object>[],
  'rule_proposals': [
    {
      'schema_version': 1,
      'name': '卷标题候选',
      'kind': 'chapter',
      'target': 'heading_line',
      'match': {'mode': 'literal', 'pattern': '【卷二】夜雨', 'case_sensitive': true},
      'action': 'chapter_candidate',
      'positive_examples': [_sample],
      'negative_examples': ['  普通正文  '],
      'reason': '只匹配示例标题',
    },
  ],
});

class _Credentials implements AiCredentialStore {
  int reads = 0;
  @override
  Future<String?> read(String reference) async {
    reads++;
    return 'test-key';
  }

  @override
  Future<void> write(String reference, String value) async {}
  @override
  Future<void> delete(String reference) async {}
}

class _Client implements AiTextClient {
  int calls = 0;
  Completer<String>? response;
  @override
  Future<String> generate({
    required AiEndpoint endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
    required AiCancellation cancellation,
  }) {
    calls++;
    return response?.future ?? Future.value(_ruleResponse());
  }

  @override
  void dispose() {}
}

class _InlineJobs extends BackgroundJobs {
  @override
  Future<R> run<T, R>(
    T input,
    FutureOr<R> Function(T, void Function(double, String)) compute, {
    required int revision,
    Duration timeout = const Duration(minutes: 2),
    void Function(JobProgress)? onProgress,
  }) async => compute(input, (fraction, stage) {});
  @override
  void cancelActive() {}
}

class _BookStore implements EditorBookStore {
  final book = Book(
    id: 'book',
    meta: BookMeta(title: '书'),
    chapters: const [Chapter(id: 'first', bookId: 'book', title: '第一章')],
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  int saves = 0;
  @override
  Future<Book?> loadBook(String bookId) async => book;
  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async =>
      const Chapter(
        id: 'first',
        bookId: 'book',
        title: '第一章',
        blocks: [TextBlock(id: 'paragraph', text: _source)],
      );
  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    saves++;
    return book;
  }
}
