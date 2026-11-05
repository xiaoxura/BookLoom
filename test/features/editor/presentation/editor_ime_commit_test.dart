import 'dart:io';

import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/presentation/editor_page.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../support/pump_bookloom.dart';

void main() {
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

  static Future<_EditorHarness> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
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
          chapters: const <Chapter>[
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
        overrides: [bookRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(
          locale: const Locale('zh'),
          theme: AppTheme.light(),
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

class _GuardCapture {
  Future<void> Function()? beforeClose;
}
