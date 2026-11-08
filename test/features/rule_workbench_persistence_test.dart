import 'dart:io';

import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Book, Chapter, Block;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/application/rule_workbench_task.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved title capture mapping survives a new workbench load', () async {
    final database = AppDatabase.memory();
    final store = SettingsProofreadingRuleStore(database);
    final session = EditorSession.withStore(store: _MappedBookStore());
    final task = RuleWorkbenchTask(session: session, store: store);
    try {
      await session.open('book');
      await task.load();
      final rule = ProofreadingRule.create(
        id: 'mapped',
        name: '章节标题映射',
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
        negativeExamples: const ['普通正文'],
      );
      task.putRule(rule);
      await task.scan();
      expect(task.matches.single.splitTitle, '风雨');
      await task.saveRule(rule.id);
      expect(session.dirty, isFalse);

      await task.load();
      expect(task.rules.single.titleCaptureGroup, 1);
      expect(task.selectedRuleIds, isEmpty);
      expect(task.trial, isNull);
      task.setRuleSelected(rule.id, true);
      await task.scan();
      expect(task.matches.single.splitTitle, '风雨');
      expect(session.dirty, isFalse);
    } finally {
      task.dispose();
      session.dispose();
      await database.close();
    }
  });

  test(
    'guarded rule application autosaves outside the finished rule transaction',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookloom-rule-save-',
      );
      final database = AppDatabase.memory();
      final repository = BookRepository(database, directory);
      final session = EditorSession(
        repository: repository,
        debounce: const Duration(milliseconds: 800),
      );
      final store = SettingsProofreadingRuleStore(database);
      final task = RuleWorkbenchTask(session: session, store: store);
      try {
        final now = DateTime.utc(2026, 11, 7);
        await repository.createBook(
          Book(
            id: 'book',
            meta: BookMeta(title: '隔离自动保存样书'),
            createdAt: now,
            updatedAt: now,
            chapters: const [
              Chapter(
                id: 'chapter',
                bookId: 'book',
                title: '第一章',
                blocks: [TextBlock(id: 'text', text: '😀前文。\r\n广告正文。')],
              ),
              Chapter(
                id: 'next',
                bookId: 'book',
                title: '第二章',
                order: 1,
                blocks: [TextBlock(id: 'next-text', text: '后续原文。')],
              ),
            ],
          ),
        );
        final rule = ProofreadingRule.create(
          id: 'rule',
          name: '合成精确删除',
          kind: ProofreadingRuleKind.advertisement,
          source: ProofreadingRuleSource.user,
          bookId: 'book',
          target: ProofreadingRuleTarget.bodyLine,
          mode: ProofreadingMatchMode.literal,
          pattern: '广告',
          caseSensitive: true,
          action: ProofreadingRuleAction.exactDeletion,
          positiveExamples: const ['广告正文。'],
          negativeExamples: const ['正文。'],
        );
        await store.save(rule);
        await session.open('book');
        await task.load();
        task.setRuleSelected('rule', true);
        await task.scan();
        expect(task.hasCurrentTrial, isTrue);
        await task.applySelected({task.matches.single.id});
        expect(task.phase, RuleWorkbenchPhase.applied);
        expect(session.dirty, isTrue);

        for (
          var attempt = 0;
          attempt < 150 && session.dirty && session.saveError == null;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(session.saveError, isNull);
        expect(session.dirty, isFalse);
        expect(task.phase, RuleWorkbenchPhase.applied);
        final saved = await repository.loadChapter('book', 'chapter');
        expect((saved!.blocks.single as TextBlock).text, '😀前文。\r\n正文。');
        final untouched = await repository.loadChapter('book', 'next');
        expect((untouched!.blocks.single as TextBlock).text, '后续原文。');

        await session.undo();
        await session.flush();
        expect(
          (session.activeChapter!.blocks.single as TextBlock).text,
          '😀前文。\r\n广告正文。',
        );
        expect((await store.loadForBook('book')).single.pattern, '广告');
      } finally {
        task.dispose();
        await session.close();
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

class _MappedBookStore implements EditorBookStore {
  final book = Book(
    id: 'book',
    meta: BookMeta(title: '映射测试书'),
    chapters: const [Chapter(id: 'first', bookId: 'book', title: '第一章')],
    createdAt: DateTime.utc(2026, 11, 7),
    updatedAt: DateTime.utc(2026, 11, 7),
  );

  @override
  Future<Book?> loadBook(String bookId) async => bookId == 'book' ? book : null;

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async =>
      const Chapter(
        id: 'first',
        bookId: 'book',
        title: '第一章',
        blocks: [TextBlock(id: 'text', text: '前文\n【第二章 风雨】\n后文')],
      );

  @override
  Future<Book> saveBook(
    Book source, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async => source;
}
