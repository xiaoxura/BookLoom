import 'dart:convert';

import 'package:bookloom/app/ai_providers.dart';
import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/application/ai_proofreading_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/presentation/ai_proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/proofreading_panel.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('check handoff uses the numbered gap, not the active chapter', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.runAudit(tester);
    await fixture.showGap(tester, 'c3');
    final locate = tester.widget<ListTile>(
      find.ancestor(
        of: find.byKey(const ValueKey('audit-ai-gap-c3')),
        matching: find.byType(ListTile),
      ),
    );
    locate.onTap!();
    await tester.pump();
    expect(fixture.locates, <String>['c3']);
    fixture.locates.clear();
    await tester.tap(find.byKey(const ValueKey('audit-ai-gap-c3')));
    await tester.pump();
    expect(fixture.locates, isEmpty);
    expect(fixture.session.activeChapterId, 'c8');
    expect(locate.onTap, isNotNull);
    expect(find.byKey(const ValueKey('ai-audit-gap-source')), findsOneWidget);
    expect(find.textContaining('<script>界限</script>'), findsWidgets);
    expect(fixture.configurationLoads, 0);
    expect(fixture.credentials.readCount, 0);
    expect(fixture.client.requestCount, 0);
    expect(fixture.task.phase, AiProofreadingPhase.idle);
    expect(
      tester
          .widget<AiProofreadingPanel>(find.byType(AiProofreadingPanel))
          .initialAuditGap
          ?.chapterIds,
      <String>['c1', 'c3'],
    );

    await fixture.prepare(tester);
    final consent = fixture.task.consent!;
    expect(consent.auditGap?.chapterIds, <String>['c1', 'c3']);
    expect(consent.auditGap?.gap.firstMissing, 2);
    expect(consent.auditGap?.gap.lastMissing, 2);
    expect(consent.chapterTitles.keys, <String>['c1', 'c3']);
    expect(fixture.credentials.readCount, 0);
    expect(fixture.client.requestCount, 0);
    expect(consent.plan.chunks, hasLength(1));
    final systemTile = find.ancestor(
      of: find.text('完整系统提示词'),
      matching: find.byType(ExpansionTile),
    );
    await tester.ensureVisible(systemTile);
    await tester.pumpAndSettle();
    await tester.tap(systemTile);
    await tester.pumpAndSettle();
    final previewSystem = tester
        .widget<SelectableText>(
          find.descendant(
            of: systemTile,
            matching: find.byType(SelectableText),
          ),
        )
        .data!;
    final chunkTile = find.byKey(const ValueKey('ai-chunk-0'));
    if (chunkTile.evaluate().isEmpty) {
      await tester.scrollUntilVisible(chunkTile, 120, scrollable: _aiScroll);
    }
    await tester.ensureVisible(chunkTile);
    await tester.pumpAndSettle();
    await tester.tap(chunkTile);
    await tester.pumpAndSettle();
    final previewContext = tester
        .widget<SelectableText>(
          find.descendant(of: chunkTile, matching: find.byType(SelectableText)),
        )
        .data!;
    expect(previewSystem, contains('audit_gap'));
    expect(previewContext, contains('"audit_gap"'));
    expect(fixture.client.requestCount, 0);
    final run = find.byKey(const ValueKey('ai-run'));
    await tester.ensureVisible(run);
    await tester.pumpAndSettle();
    await tester.tap(run);
    await _pumpUntil(
      tester,
      () => fixture.task.phase == AiProofreadingPhase.completed,
    );
    expect(fixture.credentials.readCount, greaterThan(0));
    expect(fixture.client.requestCount, 1);
    expect(fixture.client.contexts.single, previewContext);
    expect(fixture.client.systemPrompts.single, previewSystem);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial gap accepts one chapter and rejects an old consent', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.runAudit(tester);
    await fixture.showGap(tester, 'c4');
    await tester.tap(find.byKey(const ValueKey('audit-ai-gap-c4')));
    await tester.pump();
    expect(
      tester
          .widget<AiProofreadingPanel>(find.byType(AiProofreadingPanel))
          .initialAuditGap
          ?.chapterIds,
      <String>['c4'],
    );
    expect(find.textContaining('本卷没有前一章'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('ai-prepare')))
          .onPressed,
      isNotNull,
    );
    await fixture.prepare(tester);
    expect(fixture.task.consent!.auditGap?.gap.beforeChapterId, isNull);
    expect(fixture.task.consent!.chapterTitles.keys, <String>['c4']);
    final oldRun = tester
        .widget<FilledButton>(find.byKey(const ValueKey('ai-run')))
        .onPressed!;

    final scope = find.byKey(const ValueKey('ai-chapter-c5'));
    await tester.scrollUntilVisible(
      scope,
      80,
      scrollable: find
          .descendant(
            of: find.byType(AiProofreadingPanel),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.ensureVisible(scope);
    await tester.pumpAndSettle();
    await tester.tap(scope);
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-audit-gap-source')), findsNothing);
    expect(find.byKey(const ValueKey('ai-run')), findsNothing);
    expect(fixture.task.phase, AiProofreadingPhase.cancelled);
    oldRun();
    await tester.pump();
    expect(fixture.credentials.readCount, 0);
    expect(fixture.client.requestCount, 0);

    tester.state<ScrollableState>(_aiScroll).position.jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-intent-advertisement')));
    await tester.pump();
    await fixture.prepare(tester);
    expect(fixture.task.consent!.auditGap, isNull);
    expect(fixture.task.consent!.chapterTitles.keys, <String>['c8']);
    expect(fixture.client.requestCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing invalidates the check and old gap callback', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.runAudit(tester);
    await fixture.showGap(tester, 'c3');
    final oldButton = tester
        .widget<TextButton>(find.byKey(const ValueKey('audit-ai-gap-c3')))
        .onPressed!;
    fixture.session.editChapterTitle('c8', '第8章 修订');
    await tester.pump();
    expect(find.byKey(const ValueKey('audit-ai-gap-c3')), findsNothing);
    oldButton();
    await tester.pump();
    expect(find.byType(AiProofreadingPanel), findsNothing);
    expect(fixture.configurationLoads, 0);

    await fixture.runAudit(tester);
    await fixture.showGap(tester, 'c3');
    await tester.tap(find.byKey(const ValueKey('audit-ai-gap-c3')));
    await tester.pump();
    fixture.session.editChapterTitle('c8', '第8章 再修订');
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-audit-gap-source')), findsNothing);
    expect(find.textContaining('请重新体检'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('ai-prepare')))
          .onPressed,
      isNull,
    );
    expect(fixture.client.requestCount, 0);
    await fixture.session.flush();
  });

  testWidgets('replacing the session clears the old report in the same state', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.runAudit(tester);
    await fixture.showGap(tester, 'c3');
    final oldButton = tester
        .widget<TextButton>(find.byKey(const ValueKey('audit-ai-gap-c3')))
        .onPressed!;
    final oldState = tester.state(find.byType(ProofreadingPanel));
    final nextSession = EditorSession.withStore(store: _Store());
    await nextSession.open('book', chapterId: 'c8');
    addTearDown(nextSession.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiProofreadingTaskProvider(fixture.session)
              .overrideWith((ref) => fixture.task),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ProofreadingPanel(
              session: nextSession,
              onLocate: (chapterId, blockId) async {},
            ),
          ),
        ),
      ),
    );
    expect(tester.state(find.byType(ProofreadingPanel)), same(oldState));
    expect(find.byKey(const ValueKey('audit-ai-gap-c3')), findsNothing);
    oldButton();
    await tester.pump();
    expect(find.byType(AiProofreadingPanel), findsNothing);
    expect(
      find.byKey(const ValueKey('proofreading-audit-run')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    testWidgets('handoff fits 320px at 2x with keyboard in $themeMode', (
      tester,
    ) async {
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
      final fixture = await _Fixture.open(tester, themeMode: themeMode);
      await fixture.runAudit(tester);
      await fixture.showGap(tester, 'c4');
      final gap = find.byKey(const ValueKey('audit-ai-gap-c4'));
      await tester.tap(gap);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-audit-gap-source')), findsOneWidget);
      expect(fixture.client.requestCount, 0);
      expect(fixture.credentials.readCount, 0);
      final prepare = find.byKey(const ValueKey('ai-prepare'));
      await tester.ensureVisible(prepare);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(prepare).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
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

Finder get _aiScroll => find
    .descendant(
      of: find.byType(AiProofreadingPanel),
      matching: find.byType(Scrollable),
    )
    .first;

class _Fixture {
  _Fixture(this.session, this.credentials, this.client);

  final EditorSession session;
  final _Credentials credentials;
  final _Client client;
  final List<String> locates = [];
  late AiProofreadingTask task;
  int configurationLoads = 0;

  static Future<_Fixture> open(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    final session = EditorSession.withStore(store: _Store());
    await session.open('book', chapterId: 'c8');
    addTearDown(session.dispose);
    final fixture = _Fixture(session, _Credentials(), _Client());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiProofreadingTaskProvider(session).overrideWith(
            (ref) => fixture.task = AiProofreadingTask(
              session: session,
              loadConfiguration: () async {
                fixture.configurationLoads++;
                return const AiConfiguration(
                  enabled: true,
                  address: 'http://localhost:9823/v1',
                  model: 'test-model',
                  credentialReference: 'test-key',
                );
              },
              credentials: fixture.credentials,
              createClient: () => fixture.client,
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          theme: AppTheme.light(glass: GlassQuality.off),
          darkTheme: AppTheme.dark(glass: GlassQuality.off),
          themeMode: themeMode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ProofreadingPanel(
              session: session,
              onLocate: (chapterId, blockId) async {
                fixture.locates.add(chapterId);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return fixture;
  }

  Future<void> runAudit(WidgetTester tester) async {
    tester.state<ScrollableState>(_auditScroll).position.jumpTo(0);
    await tester.pump();
    final run = find.byKey(const ValueKey('proofreading-audit-run'));
    if (run.evaluate().isEmpty) {
      await tester.scrollUntilVisible(run, 120, scrollable: _auditScroll);
    }
    await tester.ensureVisible(run);
    await tester.pumpAndSettle();
    await tester.tap(run);
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('proofreading-audit-total'))
          .evaluate()
          .isNotEmpty,
    );
  }

  Future<void> showGap(WidgetTester tester, String chapterId) async {
    final gap = find.byKey(ValueKey('audit-ai-gap-$chapterId'));
    if (gap.evaluate().isEmpty) {
      await tester.scrollUntilVisible(gap, 120, scrollable: _auditScroll);
    }
    await tester.ensureVisible(gap);
    await tester.pumpAndSettle();
  }

  Finder get _auditScroll => find
      .descendant(
        of: find.byType(ProofreadingPanel),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> prepare(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('ai-prepare'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await _pumpUntil(
      tester,
      () => task.phase == AiProofreadingPhase.awaitingConsent,
    );
  }
}

class _Credentials implements AiCredentialStore {
  int readCount = 0;

  @override
  Future<String?> read(String reference) async {
    readCount++;
    return 'synthetic-key';
  }

  @override
  Future<void> write(String reference, String value) async {}

  @override
  Future<void> delete(String reference) async {}
}

class _Client implements AiTextClient {
  int requestCount = 0;
  final List<String> contexts = [];
  final List<String> systemPrompts = [];

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
    contexts.add(userContext);
    systemPrompts.add(systemPrompt);
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

class _Store implements EditorBookStore {
  final Book book = Book(
    id: 'book',
    meta: BookMeta(title: '书', author: '作者'),
    chapters: const [
      Chapter(id: 'v1', bookId: 'book', title: '上卷', level: 1),
      Chapter(
        id: 'c1',
        bookId: 'book',
        title: '第1章 <script>界限</script>',
        parentId: 'v1',
      ),
      Chapter(id: 'c3', bookId: 'book', title: '第3章 后段', parentId: 'v1'),
      Chapter(id: 'c8', bookId: 'book', title: '第8章 远处', parentId: 'v1'),
      Chapter(id: 'v2', bookId: 'book', title: '下卷', level: 1),
      Chapter(id: 'c4', bookId: 'book', title: '第4章 开端', parentId: 'v2'),
      Chapter(id: 'c5', bookId: 'book', title: '第5章 继续', parentId: 'v2'),
    ],
    createdAt: DateTime.utc(2026, 11, 7),
    updatedAt: DateTime.utc(2026, 11, 7),
  );

  @override
  Future<Book?> loadBook(String bookId) async => bookId == 'book' ? book : null;

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async {
    final chapter = book.chapters.firstWhere((item) => item.id == chapterId);
    return chapter.copyWith(
      blocks: chapter.isVolume
          ? const <Block>[]
          : <Block>[TextBlock(id: 'text-$chapterId', text: '正文 $chapterId。')],
    );
  }

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async => book;
}
