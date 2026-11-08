import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/ai/ai_limits.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Block, Book, Chapter;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorSession.applyAiChanges', () {
    late _MemoryStore store;
    late EditorSession session;

    setUp(() {
      store = _MemoryStore();
      session = EditorSession.withStore(
        store: store,
        debounce: const Duration(milliseconds: 800),
      );
    });

    tearDown(() {
      session.dispose();
    });

    test(
      'renames a chapter without changing its text, resources or lazy siblings',
      () async {
        const source = '\r\n　第二章 😀新题　\r\n正文🙂';
        const retained = <Block>[
          ImageBlock(id: 'art', assetId: 'art-asset', alt: '插图'),
          FootnoteBlock(id: 'note', text: '脚注', marker: '①'),
          DividerBlock(id: 'divider'),
        ];
        session.dispose();
        store = _MemoryStore(
          firstBodyText: source,
          firstAdditionalBlocks: retained,
        );
        session = EditorSession.withStore(store: store);
        await session.open('book');
        final proposal = _renameChapter(
          session,
          source: source,
          original: '第二章 😀新题',
        );
        final count = session.book!.wordCount;
        final revision = session.saveSeq;
        await session.applyAiChanges(
          textProposals: [proposal],
          splitProposals: const [],
          selectedIds: {proposal.id},
        );
        expect(session.activeChapter!.title, '第二章 😀新题');
        expect(session.activeChapter!.blocks, [
          const TextBlock(id: 'body-a', text: source),
          ...retained,
        ]);
        expect(session.book!.wordCount, count);
        expect(session.saveSeq, revision + 1);
        expect(store.loadedChapterIds, ['a']);
        await session.undo();
        expect(session.activeChapter!.title, '合并稿');
        expect(session.canUndo, isFalse);
        await session.redo();
        await session.flush();
        expect(store.bodies[('book', 'a')]!.title, '第二章 😀新题');
        expect(store.bodies[('book', 'b')]!.blocks.single.plainText, '未选择章节正文');
      },
    );

    test(
      'combines a title correction and a disjoint text edit in one undo',
      () async {
        const source = '第二章 新题\r\n正文🙂';
        session.dispose();
        store = _MemoryStore(firstBodyText: source);
        session = EditorSession.withStore(store: store);
        await session.open('book');
        final title = _renameChapter(
          session,
          source: source,
          original: '第二章 新题',
        );
        final text = _replace(
          session,
          id: 'body-edit',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '正文',
          before: '\r\n',
          after: '🙂',
          replacement: '内容',
        );
        await session.applyAiChanges(
          textProposals: [title, text],
          splitProposals: const [],
          selectedIds: {title.id, text.id},
        );
        expect(session.activeChapter!.title, '第二章 新题');
        expect(
          session.activeChapter!.blocks.single.plainText,
          '第二章 新题\r\n内容🙂',
        );
        await session.undo();
        expect(session.activeChapter!.title, '合并稿');
        expect(session.activeChapter!.blocks.single.plainText, source);
        expect(session.canUndo, isFalse);
      },
    );

    test(
      'pure text entry refuses title correction instead of rewriting evidence',
      () async {
        const source = '第二章 新题\n正文';
        session.dispose();
        store = _MemoryStore(firstBodyText: source);
        session = EditorSession.withStore(store: store);
        await session.open('book');
        final proposal = _renameChapter(
          session,
          source: source,
          original: '第二章 新题',
        );
        await expectLater(
          session.applyAiTextProposals([proposal], selectedIds: {proposal.id}),
          throwsA(isA<ValidationFailure>()),
        );
        expect(session.activeChapter!.title, '合并稿');
        expect(session.activeChapter!.blocks.single.plainText, source);
        expect(session.canUndo, isFalse);
      },
    );

    test(
      'manual title edits reject a late compiled title correction',
      () async {
        const source = '第二章 新题\n正文';
        final jobs = _PausedJobs();
        session.dispose();
        store = _MemoryStore(firstBodyText: source);
        session = EditorSession.withStore(store: store, jobs: jobs);
        await session.open('book');
        final proposal = _renameChapter(
          session,
          source: source,
          original: '第二章 新题',
        );
        final applying = session.applyAiChanges(
          textProposals: [proposal],
          splitProposals: const [],
          selectedIds: {proposal.id},
        );
        await jobs.started.future;
        session.editChapterTitle('a', '保留人工修改');
        jobs.resume.complete();
        await expectLater(applying, throwsA(isA<ValidationFailure>()));
        expect(session.activeChapter!.title, '保留人工修改');
        expect(session.activeChapter!.blocks.single.plainText, source);
      },
    );

    test(
      'title-only correction preserves noncanonical directory order metadata',
      () async {
        const source = '第二章 新题\n正文';
        session.dispose();
        store = _MemoryStore(firstBodyText: source);
        final book = store._books['book']!;
        store._books['book'] = book.copyWith(
          chapters: [
            book.chapters[0].copyWith(order: 4),
            book.chapters[1].copyWith(order: 9),
          ],
        );
        for (final entry in [('a', 4), ('b', 9)]) {
          store.bodies[('book', entry.$1)] = store.bodies[('book', entry.$1)]!
              .copyWith(order: entry.$2);
        }
        session = EditorSession.withStore(store: store);
        await session.open('book');
        final proposal = _renameChapter(
          session,
          source: source,
          original: '第二章 新题',
        );
        await session.applyAiChanges(
          textProposals: [proposal],
          splitProposals: const [],
          selectedIds: {proposal.id},
        );
        expect(session.book!.chapters.map((chapter) => chapter.order), [4, 9]);
        await session.undo();
        expect(session.book!.chapters.map((chapter) => chapter.order), [4, 9]);
        await session.redo();
        await session.flush();
        expect(store._books['book']!.chapters.map((chapter) => chapter.order), [
          4,
          9,
        ]);
      },
    );

    test(
      'removes a block without splits and preserves lazy sibling bodies',
      () async {
        const source = '😀本站推广\r\n请收藏合成书屋';
        const retained = <Block>[
          ImageBlock(id: 'art', assetId: 'art-asset', alt: '插图'),
          FootnoteBlock(id: 'note', text: '脚注', marker: '①'),
          DividerBlock(id: 'divider'),
          TextBlock(id: 'ending', text: '后续正文🙂'),
        ];
        session.dispose();
        store = _MemoryStore(
          firstBodyText: source,
          firstAdditionalBlocks: retained,
        );
        session = EditorSession.withStore(store: store);
        await session.open('book');
        final proposal = _removeBlock(session, source: source);
        final revision = session.saveSeq;
        final initialCount = session.book!.wordCount;

        await session.applyAiChanges(
          textProposals: [proposal],
          splitProposals: const [],
          selectedIds: {proposal.id},
        );

        expect(session.activeChapter!.blocks, retained);
        expect(session.book!.chapters.map((chapter) => chapter.id), ['a', 'b']);
        expect(store.loadedChapterIds, ['a']);
        expect(session.saveSeq, revision + 1);
        expect(
          session.book!.wordCount,
          initialCount - WordCount.ofText(source),
        );
        expect(session.canUndo, isTrue);
        await session.undo();
        expect(session.activeChapter!.blocks, [
          const TextBlock(id: 'body-a', text: source),
          ...retained,
        ]);
        expect(session.canUndo, isFalse);
        expect(session.book!.wordCount, initialCount);
        await session.redo();
        expect(session.activeChapter!.blocks, retained);
        await session.flush();
        expect(store.bodies[('book', 'a')]!.blocks, retained);
        expect(store.bodies[('book', 'b')]!.blocks, const [
          TextBlock(id: 'body-b', text: '未选择章节正文'),
        ]);
      },
    );

    test(
      'legacy text-only application refuses structural block removal',
      () async {
        await session.open('book');
        final source = store.firstBodyText;
        final proposal = _removeBlock(session, source: source);
        final revision = session.saveSeq;
        await expectLater(
          session.applyAiTextProposals([proposal], selectedIds: {proposal.id}),
          throwsA(isA<ValidationFailure>()),
        );
        expect(session.saveSeq, revision);
        expect(
          session.activeChapter!.blocks.single,
          TextBlock(id: 'body-a', text: source),
        );
        expect(session.canUndo, isFalse);
      },
    );

    test(
      'a cancelled block removal cannot commit a late worker result',
      () async {
        final jobs = _PausedJobs();
        session.dispose();
        session = EditorSession.withStore(store: store, jobs: jobs);
        await session.open('book');
        final proposal = _removeBlock(session, source: store.firstBodyText);
        final revision = session.saveSeq;
        final applying = session.applyAiChanges(
          textProposals: [proposal],
          splitProposals: const [],
          selectedIds: {proposal.id},
        );
        await jobs.started.future;
        session.cancelTool();
        jobs.resume.complete();
        await expectLater(applying, throwsA(isA<TaskCancelled>()));
        expect(session.saveSeq, revision);
        expect(session.activeChapter!.blocks.single.id, 'body-a');
        expect(session.canUndo, isFalse);
      },
    );

    test('a manual edit makes an in-flight block removal stale', () async {
      final jobs = _PausedJobs();
      session.dispose();
      session = EditorSession.withStore(store: store, jobs: jobs);
      await session.open('book');
      final proposal = _removeBlock(session, source: store.firstBodyText);
      final applying = session.applyAiChanges(
        textProposals: [proposal],
        splitProposals: const [],
        selectedIds: {proposal.id},
      );
      await jobs.started.future;
      session.editBlockText('body-a', '保留用户刚写下的正文');
      final revision = session.saveSeq;
      jobs.resume.complete();
      await expectLater(applying, throwsA(isA<ValidationFailure>()));
      expect(session.saveSeq, revision);
      expect(
        session.activeChapter!.blocks.single,
        const TextBlock(id: 'body-a', text: '保留用户刚写下的正文'),
      );
    });

    test(
      'removing the last text block keeps the chapter and exports no ad',
      () async {
        await session.open('book');
        final proposal = _removeBlock(session, source: store.firstBodyText);
        await session.applyAiChanges(
          textProposals: [proposal],
          splitProposals: const [],
          selectedIds: {proposal.id},
        );
        expect(session.activeChapter!.blocks, isEmpty);
        expect(session.book!.chapters.first.id, 'a');
        await session.readAiSelectionChapter('b');
        final support = await Directory.systemTemp.createTemp(
          'bookloom-ai-remove-export-',
        );
        try {
          final output = '${support.path}/book.txt';
          writeDocument(
            ExportSnapshot(book: session.book!),
            output,
            format: ExportFormat.txt,
          );
          final exported = await File(output).readAsString();
          expect(exported, isNot(contains(store.firstBodyText)));
          expect(exported, contains('合并稿'));
          expect(exported, contains('未选择章节正文'));
        } finally {
          await support.delete(recursive: true);
        }
      },
    );

    test(
      'commits selected text and split proposals as one undoable change',
      () async {
        const source = '😀前缀\r\n第二章\r\n后缀🙂';
        session.dispose();
        store = _MemoryStore(firstBodyText: source);
        session = EditorSession.withStore(
          store: store,
          debounce: const Duration(milliseconds: 800),
        );
        await session.open('book');
        final before = _replace(
          session,
          id: 'before',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '前缀',
          before: '😀',
          after: '\r\n',
          replacement: '前',
        );
        final after = _replace(
          session,
          id: 'after',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '后缀',
          before: '\r\n',
          after: '🙂',
          replacement: '补充🙂',
        );
        final split = _split(
          session,
          id: 'split',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '第二章',
          before: '😀前缀\r\n',
          after: '\r\n',
          removeTitleLine: true,
        );
        final unselected = _replace(
          session,
          id: 'unselected',
          chapterId: 'b',
          blockId: 'body-b',
          source: '未选择章节正文',
          original: '未选择',
          before: '',
          after: '章节正文',
          replacement: '不应替换',
        );
        final initialSeq = session.saveSeq;
        final initialWordCount = session.book!.wordCount;

        await session.applyAiChanges(
          textProposals: <AiTextProposal>[before, after, unselected],
          splitProposals: <AiChapterSplitProposal>[split],
          selectedIds: const <String>{'before', 'after', 'split'},
        );

        final appliedIds = session.book!.chapters
            .map((chapter) => chapter.id)
            .toList();
        expect(session.saveSeq, initialSeq + 1);
        expect(appliedIds, hasLength(3));
        expect(session.book!.chapters.map((chapter) => chapter.title), [
          '合并稿',
          '第二章',
          '未选章节',
        ]);
        expect(
          (session.book!.chapters[0].blocks.single as TextBlock).text,
          '😀前\r\n',
        );
        expect(
          (session.book!.chapters[1].blocks.single as TextBlock).text,
          '补充🙂🙂',
        );
        expect(store.loadedChapterIds, ['a']);
        expect(
          (store.bodies[('book', 'b')]!.blocks.single as TextBlock).text,
          '未选择章节正文',
        );
        expect(session.canUndo, isTrue);

        await session.undo();
        expect(session.book!.chapters.map((chapter) => chapter.id), ['a', 'b']);
        expect(session.saveSeq, initialSeq + 2);
        expect(
          (session.activeChapter!.blocks.single as TextBlock).text,
          source,
        );
        expect(session.book!.wordCount, initialWordCount);
        expect(session.canUndo, isFalse);
        expect(session.canRedo, isTrue);

        await session.redo();
        expect(session.book!.chapters.map((chapter) => chapter.id), appliedIds);
        expect(session.saveSeq, initialSeq + 3);
        expect(
          (session.book!.chapters[1].blocks.single as TextBlock).text,
          '补充🙂🙂',
        );
        expect(session.canUndo, isTrue);
        expect(session.canRedo, isFalse);
      },
    );

    test(
      'applies pure text changes beside an unrelated large image alt block',
      () async {
        const source = '开头广告结尾';
        final imageAlt = List<String>.filled(
          aiMaxContextCharacters + 1,
          'x',
        ).join();
        final image = ImageBlock(
          id: 'large-image',
          assetId: 'synthetic-image',
          alt: imageAlt,
        );
        session.dispose();
        store = _MemoryStore(
          firstBodyText: source,
          firstAdditionalBlocks: <Block>[image],
        );
        session = EditorSession.withStore(
          store: store,
          debounce: const Duration(milliseconds: 800),
          historyByteBudget: 32 * 1024 * 1024,
        );
        await session.open('book');

        expect(imageAlt.length, greaterThan(aiMaxContextCharacters));
        expect(imageAlt.length, lessThan(32 * 1024 * 1024));
        final initialWordCount = session.book!.wordCount;
        final originalBlocks = store.bodies[('book', 'a')]!.blocks;
        expect(
          initialWordCount,
          WordCount.ofBlocks(originalBlocks) +
              WordCount.ofBlocks(store.bodies[('book', 'b')]!.blocks),
        );
        final proposal = _replace(
          session,
          id: 'small-text-change',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '广告',
          before: '开头',
          after: '结尾',
          replacement: '正文',
        );
        final initialSeq = session.saveSeq;

        await session.applyAiChanges(
          textProposals: <AiTextProposal>[proposal],
          splitProposals: const <AiChapterSplitProposal>[],
          selectedIds: <String>{proposal.id},
        );

        final updatedBlocks = session.activeChapter!.blocks;
        expect(session.saveSeq, initialSeq + 1);
        expect(updatedBlocks, hasLength(2));
        expect((updatedBlocks.first as TextBlock).text, '开头正文结尾');
        expect(updatedBlocks.last, image);
        expect(
          session.book!.wordCount,
          WordCount.ofBlocks(updatedBlocks) +
              WordCount.ofBlocks(store.bodies[('book', 'b')]!.blocks),
        );
      },
    );

    test(
      'rejects a cross-type conflict without changing the session',
      () async {
        await session.open('book');
        const source = '😀开篇\r\n第二章\r\n结尾';
        final split = _split(
          session,
          id: 'split',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '第二章',
          before: '😀开篇\r\n',
          after: '\r\n',
        );
        final deletion = AiTextProposal(
          id: 'delete-title',
          action: AiTextProposalAction.deleteText,
          target: split.target,
          range: split.range,
          replacement: '',
          reason: '删除待拆分标题',
        );
        final initialSeq = session.saveSeq;

        await expectLater(
          session.applyAiChanges(
            textProposals: <AiTextProposal>[deletion],
            splitProposals: <AiChapterSplitProposal>[split],
            selectedIds: const <String>{'delete-title', 'split'},
          ),
          throwsA(isA<ValidationFailure>()),
        );

        expect(session.saveSeq, initialSeq);
        expect(session.book!.chapters.map((chapter) => chapter.id), ['a', 'b']);
        expect(
          (session.activeChapter!.blocks.single as TextBlock).text,
          source,
        );
        expect(session.canUndo, isFalse);
      },
    );

    test(
      'rejects late worker output after the source revision changes',
      () async {
        final jobs = _PausedJobs();
        session.dispose();
        session = EditorSession.withStore(
          store: store,
          jobs: jobs,
          debounce: const Duration(milliseconds: 800),
        );
        await session.open('book');
        final split = _split(
          session,
          id: 'stale',
          chapterId: 'a',
          blockId: 'body-a',
          source: '😀开篇\r\n第二章\r\n结尾',
          original: '第二章',
          before: '😀开篇\r\n',
          after: '\r\n',
        );
        final applying = session.applyAiChanges(
          textProposals: const <AiTextProposal>[],
          splitProposals: <AiChapterSplitProposal>[split],
          selectedIds: const <String>{'stale'},
        );
        await jobs.started.future;
        session.editBlockText('body-a', '人工修改');
        final editedSeq = session.saveSeq;
        jobs.resume.complete();

        await expectLater(applying, throwsA(isA<ValidationFailure>()));
        expect(session.saveSeq, editedSeq);
        expect(session.book!.chapters.map((chapter) => chapter.id), ['a', 'b']);
        expect(
          (session.activeChapter!.blocks.single as TextBlock).text,
          '人工修改',
        );
      },
    );

    test(
      'cancellation prevents a late compiled change from applying',
      () async {
        final jobs = _PausedJobs();
        session.dispose();
        session = EditorSession.withStore(
          store: store,
          jobs: jobs,
          debounce: const Duration(milliseconds: 800),
        );
        await session.open('book');
        final source =
            (store.bodies[('book', 'a')]!.blocks.single as TextBlock).text;
        final split = _split(
          session,
          id: 'cancelled',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '第二章',
          before: '😀开篇\r\n',
          after: '\r\n',
        );
        final initialSeq = session.saveSeq;
        final applying = session.applyAiChanges(
          textProposals: const <AiTextProposal>[],
          splitProposals: <AiChapterSplitProposal>[split],
          selectedIds: const <String>{'cancelled'},
        );
        await jobs.started.future;
        expect(session.isToolRunning, isTrue);
        session.cancelTool();
        jobs.resume.complete();

        await expectLater(applying, throwsA(isA<TaskCancelled>()));
        expect(session.saveSeq, initialSeq);
        expect(session.book!.chapters.map((chapter) => chapter.id), ['a', 'b']);
        expect(
          (session.activeChapter!.blocks.single as TextBlock).text,
          source,
        );
        expect(session.canUndo, isFalse);
        expect(session.isToolRunning, isFalse);
      },
    );

    test('rejects late worker output after switching books', () async {
      final jobs = _PausedJobs();
      session.dispose();
      session = EditorSession.withStore(
        store: store,
        jobs: jobs,
        debounce: const Duration(milliseconds: 800),
      );
      await session.open('book');
      final split = _split(
        session,
        id: 'old-book',
        chapterId: 'a',
        blockId: 'body-a',
        source: '😀开篇\r\n第二章\r\n结尾',
        original: '第二章',
        before: '😀开篇\r\n',
        after: '\r\n',
      );
      final applying = session.applyAiChanges(
        textProposals: const <AiTextProposal>[],
        splitProposals: <AiChapterSplitProposal>[split],
        selectedIds: const <String>{'old-book'},
      );
      await jobs.started.future;
      await session.open('other');
      final newSessionId = session.sessionId;
      jobs.resume.complete();

      await expectLater(applying, throwsA(isA<ValidationFailure>()));
      expect(session.book!.id, 'other');
      expect(session.sessionId, isNotNull);
      expect(session.sessionId, isNot(split.target.sessionId));
      expect(session.sessionId, newSessionId);
      expect(session.book!.chapters.map((chapter) => chapter.id), ['c']);
      expect((session.activeChapter!.blocks.single as TextBlock).text, '新书正文');
    });

    test('undo-budget rejection leaves the complete batch untouched', () async {
      final jobs = _PausedJobs();
      session.dispose();
      session = EditorSession.withStore(
        store: store,
        jobs: jobs,
        debounce: const Duration(milliseconds: 800),
        historyByteBudget: 1,
      );
      await session.open('book');
      final source =
          (store.bodies[('book', 'a')]!.blocks.single as TextBlock).text;
      final split = _split(
        session,
        id: 'over-budget',
        chapterId: 'a',
        blockId: 'body-a',
        source: source,
        original: '第二章',
        before: '😀开篇\r\n',
        after: '\r\n',
      );
      final initialSeq = session.saveSeq;
      final initialWordCount = session.book!.wordCount;
      final applying = session.applyAiChanges(
        textProposals: const <AiTextProposal>[],
        splitProposals: <AiChapterSplitProposal>[split],
        selectedIds: const <String>{'over-budget'},
      );
      await jobs.started.future;
      jobs.resume.complete();

      await expectLater(applying, throwsA(isA<ValidationFailure>()));
      expect(session.saveSeq, initialSeq);
      expect(session.book!.wordCount, initialWordCount);
      expect(session.book!.chapters.map((chapter) => chapter.id), ['a', 'b']);
      expect((session.activeChapter!.blocks.single as TextBlock).text, source);
      expect(session.canUndo, isFalse);
      expect(session.dirty, isFalse);
    });
  });

  test(
    'persists block removal and preserves original source and resources',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'bookloom-ai-remove-sqlite-',
      );
      final database = AppDatabase.memory();
      final repository = BookRepository(database, support);
      final session = EditorSession(repository: repository);
      const bookId = 'remove-book';
      const advertisement = '😀本站推广\r\n请收藏合成书屋';
      const originalSource = '不可变原文件\r\n$advertisement\r\n正文🙂';
      const resources = <Block>[
        ImageBlock(id: 'image', assetId: 'image-asset', caption: '插图'),
        FootnoteBlock(id: 'footnote', text: '脚注内容', marker: '①'),
        DividerBlock(id: 'divider'),
        TextBlock(id: 'ending', text: '正文🙂'),
      ];
      final book = Book(
        id: bookId,
        meta: BookMeta(title: '合成测试'),
        createdAt: DateTime.utc(2026, 11, 7),
        updatedAt: DateTime.utc(2026, 11, 7),
        chapters: const [
          Chapter(id: 'volume', bookId: bookId, title: '卷一', level: 1),
          Chapter(
            id: 'a',
            bookId: bookId,
            title: '第一章',
            parentId: 'volume',
            blocks: [
              TextBlock(id: 'body-a', text: advertisement),
              ...resources,
            ],
          ),
          Chapter(
            id: 'b',
            bookId: bookId,
            title: '第二章',
            parentId: 'volume',
            order: 1,
            blocks: [TextBlock(id: 'body-b', text: '未选章节正文')],
          ),
        ],
      );
      try {
        await repository.createBook(
          book,
          source: SourceImport(
            format: 'txt',
            originalName: 'synthetic.txt',
            openRead: () => Stream.value(utf8.encode(originalSource)),
          ),
          assets: [
            AssetImport(
              id: 'image-asset',
              kind: 'image',
              mime: 'image/png',
              extension: 'png',
              openRead: () => Stream.value([0x89, 0x50, 0x4e, 0x47]),
            ),
          ],
        );
        await session.open(bookId);
        final proposal = _removeBlock(session, source: advertisement);
        final originalCount = session.book!.wordCount;
        await session.applyAiChanges(
          textProposals: [proposal],
          splitProposals: const [],
          selectedIds: {proposal.id},
        );
        expect(
          session.book!.chapters
              .singleWhere((chapter) => chapter.id == 'a')
              .blocks,
          resources,
        );
        await session.undo();
        expect(session.activeChapter!.blocks.first.id, 'body-a');
        await session.redo();
        await session.flush();
        final loaded = (await repository.loadBook(bookId))!;
        expect(loaded.chapters.map((chapter) => chapter.id), [
          'volume',
          'a',
          'b',
        ]);
        expect(loaded.chapters[1].parentId, 'volume');
        expect(
          loaded.wordCount,
          originalCount - WordCount.ofText(advertisement),
        );
        expect((await repository.loadChapter(bookId, 'a'))!.blocks, resources);
        expect((await repository.loadChapter(bookId, 'b'))!.blocks, const [
          TextBlock(id: 'body-b', text: '未选章节正文'),
        ]);
        final source = (await repository.loadSource(bookId))!;
        expect(
          await (await repository.resolveSource(source)).readAsString(),
          originalSource,
        );
        final asset = (await repository.loadAssets(bookId)).single;
        expect(asset.id, 'image-asset');
        expect(await (await repository.resolveAsset(asset)).readAsBytes(), [
          0x89,
          0x50,
          0x4e,
          0x47,
        ]);
      } finally {
        session.dispose();
        await database.close();
        await support.delete(recursive: true);
      }
    },
  );

  test('persists a corrected title and exports it without removing source evidence', () async {
    final support = await Directory.systemTemp.createTemp(
      'bookloom-ai-title-sqlite-',
    );
    final database = AppDatabase.memory();
    final repository = BookRepository(database, support);
    final session = EditorSession(repository: repository);
    const source = '第二章 😀新题\r\n正文🙂';
    const blocks = <Block>[
      TextBlock(id: 'body-a', text: source),
      FootnoteBlock(id: 'note', text: '原脚注', marker: '①'),
      DividerBlock(id: 'divider'),
    ];
    final book = Book(
      id: 'title-book',
      meta: BookMeta(title: '合成标题测试'),
      chapters: const [
        Chapter(id: 'volume', bookId: 'title-book', title: '第一卷', level: 1),
        Chapter(
          id: 'a',
          bookId: 'title-book',
          title: '错误目录标题',
          parentId: 'volume',
          blocks: blocks,
        ),
        Chapter(
          id: 'b',
          bookId: 'title-book',
          title: '第三章 后文',
          parentId: 'volume',
          order: 1,
          blocks: [TextBlock(id: 'body-b', text: '未选择章节正文')],
        ),
      ],
      createdAt: DateTime.utc(2026, 11, 7),
      updatedAt: DateTime.utc(2026, 11, 7),
    );
    try {
      await repository.createBook(
        book,
        source: SourceImport(
          format: 'txt',
          originalName: 'synthetic.txt',
          openRead: () => Stream.value(utf8.encode(source)),
        ),
      );
      await session.open(book.id);
      final originalCount = session.book!.wordCount;
      final proposal = _renameChapter(
        session,
        source: source,
        original: '第二章 😀新题',
      );
      await session.applyAiChanges(
        textProposals: [proposal],
        splitProposals: const [],
        selectedIds: {proposal.id},
      );
      await session.undo();
      expect(session.activeChapter!.title, '错误目录标题');
      await session.redo();
      await session.flush();
      final reloaded = (await repository.loadBook(book.id))!;
      expect(reloaded.chapters.map((chapter) => chapter.id), [
        'volume',
        'a',
        'b',
      ]);
      expect(reloaded.chapters[1].title, '第二章 😀新题');
      expect(reloaded.chapters[1].parentId, 'volume');
      expect(reloaded.chapters[1].order, 0);
      expect(reloaded.wordCount, originalCount);
      expect((await repository.loadChapter(book.id, 'a'))!.blocks, blocks);
      expect(
        (await repository.loadChapter(book.id, 'b'))!.blocks.single.plainText,
        '未选择章节正文',
      );
      final original = (await repository.loadSource(book.id))!;
      expect(
        await (await repository.resolveSource(original)).readAsString(),
        source,
      );
      await session.readAiSelectionChapter('b');
      final output = '${support.path}/corrected.txt';
      writeDocument(
        ExportSnapshot(book: session.book!),
        output,
        format: ExportFormat.txt,
      );
      final exported = await File(output).readAsString();
      expect(exported, contains('第二章 😀新题'));
      expect(exported, isNot(contains('错误目录标题')));
      expect(RegExp('第二章 😀新题').allMatches(exported), hasLength(2));
      expect(exported, contains('正文🙂'));
    } finally {
      session.dispose();
      await database.close();
      await support.delete(recursive: true);
    }
  });

  test(
    'saves split resources and word count through SQLite and reloads',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'bookloom-ai-change-',
      );
      final database = AppDatabase.memory();
      final repository = BookRepository(database, support);
      final session = EditorSession(
        repository: repository,
        debounce: const Duration(milliseconds: 800),
      );
      const bookId = 'sqlite-book';
      const source = '😀前缀\r\n第二章\r\n后缀🙂';
      final chapters = <Chapter>[
        const Chapter(id: 'volume', bookId: bookId, title: '第一卷', level: 1),
        const Chapter(
          id: 'a',
          bookId: bookId,
          title: '合并稿',
          parentId: 'volume',
          order: 0,
          blocks: <Block>[
            TextBlock(id: 'body-a', text: source),
            ImageBlock(id: 'image', assetId: 'image-asset', caption: '插图说明'),
            FootnoteBlock(id: 'footnote', text: '脚注内容', marker: '1'),
            DividerBlock(id: 'divider'),
            TextBlock(id: 'ending', text: '独立尾段'),
          ],
        ),
        const Chapter(
          id: 'b',
          bookId: bookId,
          title: '未选章节',
          parentId: 'volume',
          order: 1,
          blocks: <Block>[TextBlock(id: 'body-b', text: '未选章节正文')],
        ),
      ];
      final book = Book(
        id: bookId,
        meta: BookMeta(title: '隔离书稿', author: '合成作者'),
        chapters: chapters,
        createdAt: DateTime.utc(2026, 11, 7),
        updatedAt: DateTime.utc(2026, 11, 7),
        wordCount: chapters.fold<int>(
          0,
          (sum, chapter) => sum + WordCount.ofBlocks(chapter.blocks),
        ),
      );

      try {
        await repository.createBook(
          book,
          assets: <AssetImport>[
            AssetImport(
              id: 'image-asset',
              kind: 'image',
              mime: 'image/png',
              extension: 'png',
              maxBytes: 32,
              openRead: () =>
                  Stream<List<int>>.value(<int>[0x89, 0x50, 0x4e, 0x47]),
            ),
          ],
        );
        await session.open(bookId);
        final before = _replace(
          session,
          id: 'before',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '前缀',
          before: '😀',
          after: '\r\n',
          replacement: '前',
        );
        final after = _replace(
          session,
          id: 'after',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '后缀',
          before: '\r\n',
          after: '🙂',
          replacement: '补充🙂',
        );
        final split = _split(
          session,
          id: 'split',
          chapterId: 'a',
          blockId: 'body-a',
          source: source,
          original: '第二章',
          before: '😀前缀\r\n',
          after: '\r\n',
          removeTitleLine: true,
        );
        final untouched = _replace(
          session,
          id: 'unselected',
          chapterId: 'b',
          blockId: 'body-b',
          source: '未选章节正文',
          original: '未选章节',
          before: '',
          after: '正文',
          replacement: '不应替换',
        );
        final initialSeq = session.saveSeq;

        await session.applyAiChanges(
          textProposals: <AiTextProposal>[before, after, untouched],
          splitProposals: <AiChapterSplitProposal>[split],
          selectedIds: const <String>{'before', 'after', 'split'},
        );
        final appliedIds = session.book!.chapters
            .map((chapter) => chapter.id)
            .toList();
        expect(session.saveSeq, initialSeq + 1);
        expect(session.book!.chapters[1].parentId, 'volume');

        await session.undo();
        expect(session.book!.chapters.map((chapter) => chapter.id), [
          'volume',
          'a',
          'b',
        ]);
        expect(session.canUndo, isFalse);
        expect(session.canRedo, isTrue);
        expect((session.activeChapter!.blocks.first as TextBlock).text, source);

        await session.redo();
        expect(session.book!.chapters.map((chapter) => chapter.id), appliedIds);
        expect(session.canUndo, isTrue);
        expect(session.canRedo, isFalse);
        await session.flush();

        final reloaded = (await repository.loadBook(bookId))!;
        expect(reloaded.chapters.map((chapter) => chapter.id), appliedIds);
        final splitChapter = reloaded.chapters.singleWhere(
          (chapter) =>
              chapter.id != 'volume' && chapter.id != 'a' && chapter.id != 'b',
        );
        expect(splitChapter.title, '第二章');
        expect(splitChapter.parentId, 'volume');
        expect(splitChapter.order, 1);

        final loadedBodies = <String, Chapter>{};
        for (final chapter in reloaded.chapters.where(
          (item) => !item.isVolume,
        )) {
          loadedBodies[chapter.id] = (await repository.loadChapter(
            bookId,
            chapter.id,
          ))!;
        }
        expect(loadedBodies['a']!.blocks, const <Block>[
          TextBlock(id: 'body-a', text: '😀前\r\n'),
        ]);
        final splitBlocks = loadedBodies[splitChapter.id]!.blocks;
        expect(splitBlocks.first, isA<TextBlock>());
        expect(splitBlocks.skip(1), <Block>[
          const ImageBlock(
            id: 'image',
            assetId: 'image-asset',
            caption: '插图说明',
          ),
          const FootnoteBlock(id: 'footnote', text: '脚注内容', marker: '1'),
          const DividerBlock(id: 'divider'),
          const TextBlock(id: 'ending', text: '独立尾段'),
        ]);
        final splitText = splitBlocks.first as TextBlock;
        expect(splitText.id, isNot('body-a'));
        expect(splitText.text, '补充🙂🙂');
        expect(loadedBodies['b']!.blocks, const <Block>[
          TextBlock(id: 'body-b', text: '未选章节正文'),
        ]);
        final assets = await repository.loadAssets(bookId);
        expect(assets.map((asset) => asset.id), ['image-asset']);
        expect(
          await (await repository.resolveAsset(assets.single)).exists(),
          isTrue,
        );

        final persistedWordCount = reloaded.chapters
            .where((chapter) => !chapter.isVolume)
            .fold<int>(
              0,
              (sum, chapter) =>
                  sum + WordCount.ofBlocks(loadedBodies[chapter.id]!.blocks),
            );
        expect(reloaded.wordCount, persistedWordCount);
        expect(session.book!.wordCount, persistedWordCount);
      } finally {
        session.dispose();
        await database.close();
        await support.delete(recursive: true);
      }
    },
  );
}

AiTextProposal _renameChapter(
  EditorSession session, {
  required String source,
  required String original,
}) {
  final target = _target(
    session,
    chapterId: 'a',
    blockId: 'body-a',
    source: source,
    original: original,
    before: '',
    after: '',
  );
  return AiTextProposal(
    id: 'rename-chapter',
    action: AiTextProposalAction.renameChapter,
    target: target,
    range: _locate(target, 'a', 'body-a', source),
    replacement: original.trim(),
    originalTitle: session.book!.chapters
        .singleWhere((chapter) => chapter.id == 'a')
        .title,
    reason: '原文起始标题明确，与当前目录不一致。',
  );
}

AiTextProposal _removeBlock(EditorSession session, {required String source}) {
  final target = _target(
    session,
    chapterId: 'a',
    blockId: 'body-a',
    source: source,
    original: source,
    before: '',
    after: '',
  );
  return AiTextProposal(
    id: 'remove-block',
    action: AiTextProposalAction.removeBlock,
    target: target,
    range: _locate(target, 'a', 'body-a', source),
    replacement: '',
    reason: '整块合成广告，显式移除文字块。',
  );
}

AiChapterSplitProposal _split(
  EditorSession session, {
  required String id,
  required String chapterId,
  required String blockId,
  required String source,
  required String original,
  required String before,
  required String after,
  bool removeTitleLine = true,
}) {
  final target = _target(
    session,
    chapterId: chapterId,
    blockId: blockId,
    source: source,
    original: original,
    before: before,
    after: after,
  );
  return AiChapterSplitProposal(
    id: id,
    target: target,
    range: _locate(target, chapterId, blockId, source),
    title: original.trim(),
    removeTitleLine: removeTitleLine,
    reason: '合成章节边界',
  );
}

AiTextProposal _replace(
  EditorSession session, {
  required String id,
  required String chapterId,
  required String blockId,
  required String source,
  required String original,
  required String before,
  required String after,
  required String replacement,
}) {
  final target = _target(
    session,
    chapterId: chapterId,
    blockId: blockId,
    source: source,
    original: original,
    before: before,
    after: after,
  );
  return AiTextProposal(
    id: id,
    action: AiTextProposalAction.replaceText,
    target: target,
    range: _locate(target, chapterId, blockId, source),
    replacement: replacement,
    reason: '合成文本变更',
  );
}

ProposalTextTarget _target(
  EditorSession session, {
  required String chapterId,
  required String blockId,
  required String source,
  required String original,
  required String before,
  required String after,
}) => ProposalTextTarget(
  bookId: session.book!.id,
  sessionId: session.sessionId!,
  sessionRevision: session.saveSeq,
  chapterId: chapterId,
  blockId: blockId,
  originalText: original,
  before: before,
  after: after,
);

ProposalTextRange _locate(
  ProposalTextTarget target,
  String chapterId,
  String blockId,
  String source,
) => target.locate(
  currentBookId: target.bookId,
  currentSessionId: target.sessionId,
  currentSessionRevision: target.sessionRevision,
  currentChapterId: chapterId,
  currentBlockId: blockId,
  currentText: source,
);

class _MemoryStore implements EditorBookStore {
  _MemoryStore({
    this.firstBodyText = '😀开篇\r\n第二章\r\n结尾',
    this.firstAdditionalBlocks = const <Block>[],
  }) {
    _addBook(
      _book('book', <Chapter>[
        const Chapter(id: 'a', bookId: 'book', title: '合并稿'),
        const Chapter(id: 'b', bookId: 'book', title: '未选章节', order: 1),
      ]),
      <Chapter>[
        Chapter(
          id: 'a',
          bookId: 'book',
          title: '合并稿',
          blocks: <Block>[
            TextBlock(id: 'body-a', text: firstBodyText),
            ...firstAdditionalBlocks,
          ],
        ),
        const Chapter(
          id: 'b',
          bookId: 'book',
          title: '未选章节',
          order: 1,
          blocks: <Block>[TextBlock(id: 'body-b', text: '未选择章节正文')],
        ),
      ],
    );
    _addBook(
      _book('other', const <Chapter>[
        Chapter(id: 'c', bookId: 'other', title: '新书'),
      ]),
      const <Chapter>[
        Chapter(
          id: 'c',
          bookId: 'other',
          title: '新书',
          blocks: <Block>[TextBlock(id: 'body-c', text: '新书正文')],
        ),
      ],
    );
  }

  final Map<String, Book> _books = <String, Book>{};
  final String firstBodyText;
  final List<Block> firstAdditionalBlocks;
  final Map<(String, String), Chapter> bodies = <(String, String), Chapter>{};
  final List<String> loadedChapterIds = <String>[];

  void _addBook(Book book, List<Chapter> sourceBodies) {
    _books[book.id] = book.copyWith(
      chapters: <Chapter>[
        for (final chapter in book.chapters)
          chapter.copyWith(blocks: const <Block>[]),
      ],
      wordCount: sourceBodies.fold<int>(
        0,
        (sum, chapter) => sum + WordCount.ofBlocks(chapter.blocks),
      ),
    );
    for (final chapter in sourceBodies) {
      bodies[(book.id, chapter.id)] = chapter;
    }
  }

  @override
  Future<Book?> loadBook(String bookId) async => _books[bookId];

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async {
    loadedChapterIds.add(chapterId);
    return bodies[(bookId, chapterId)];
  }

  @override
  Future<Book> saveBook(
    Book source, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    final current = _books[source.id];
    if (current == null || current.revision != expectedRevision) {
      throw StateError('Unexpected synthetic-store revision');
    }
    for (final id in deletedChapterIds) {
      bodies.remove((source.id, id));
    }
    for (final chapter in source.chapters) {
      final oldBody = bodies[(source.id, chapter.id)];
      bodies[(source.id, chapter.id)] = chapter.copyWith(
        blocks: dirtyChapterIds.contains(chapter.id)
            ? chapter.blocks
            : oldBody?.blocks ?? chapter.blocks,
      );
    }
    final wordCount = source.chapters.fold<int>(
      0,
      (sum, chapter) =>
          sum + WordCount.ofBlocks(bodies[(source.id, chapter.id)]!.blocks),
    );
    final saved = source.copyWith(
      chapters: <Chapter>[
        for (final chapter in source.chapters)
          chapter.copyWith(blocks: const <Block>[]),
      ],
      revision: expectedRevision + 1,
      wordCount: wordCount,
    );
    _books[source.id] = saved;
    return saved;
  }
}

Book _book(String id, List<Chapter> chapters) => Book(
  id: id,
  meta: BookMeta(title: id, author: '合成作者'),
  chapters: chapters,
  createdAt: DateTime.utc(2026, 11, 7),
  updatedAt: DateTime.utc(2026, 11, 7),
);

class _PausedJobs extends BackgroundJobs {
  final Completer<void> started = Completer<void>();
  final Completer<void> resume = Completer<void>();
  bool _busy = false;

  @override
  bool get isBusy => _busy;

  @override
  Future<R> run<T, R>(
    T input,
    FutureOr<R> Function(T, void Function(double, String)) compute, {
    required int revision,
    Duration timeout = const Duration(minutes: 2),
    void Function(JobProgress)? onProgress,
  }) async {
    _busy = true;
    started.complete();
    try {
      await resume.future;
      return await compute(input, (fraction, stage) {
        onProgress?.call(JobProgress(1, revision, fraction, stage));
      });
    } finally {
      _busy = false;
    }
  }

  @override
  void cancelActive() {}
}
