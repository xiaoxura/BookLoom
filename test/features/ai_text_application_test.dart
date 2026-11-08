import 'dart:async';
import 'dart:io';

import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Book, Chapter, Block;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryStore store;
  late EditorSession session;
  var closed = false;

  setUp(() {
    store = _MemoryStore();
    session = EditorSession.withStore(
      store: store,
      debounce: const Duration(milliseconds: 800),
    );
    closed = false;
  });

  tearDown(() {
    if (!closed) session.dispose();
  });

  AiTextProposal proposal(
    String id,
    String original, {
    String chapterId = 'a',
    String blockId = 'p1',
    String? source,
    String before = '',
    String after = '',
    String replacement = '',
    AiTextProposalAction action = AiTextProposalAction.deleteText,
    ProposalTextRange? storedRange,
    String? sessionId,
    int? saveSeq,
  }) {
    final text =
        source ??
        (store.bodies[chapterId]!.blocks.firstWhere(
          (block) => block.id == blockId,
        ) as TextBlock).text;
    final target = ProposalTextTarget(
      bookId: 'book',
      sessionId: sessionId ?? session.sessionId!,
      sessionRevision: saveSeq ?? session.saveSeq,
      chapterId: chapterId,
      blockId: blockId,
      originalText: original,
      before: before,
      after: after,
    );
    final range =
        storedRange ??
        target.locate(
          currentBookId: 'book',
          currentSessionId: target.sessionId,
          currentSessionRevision: target.sessionRevision,
          currentChapterId: chapterId,
          currentBlockId: blockId,
          currentText: text,
        );
    return AiTextProposal(
      id: id,
      action: action,
      target: target,
      range: range,
      replacement: replacement,
      reason: '人工确认的建议',
    );
  }

  test('two suggestions in one block form one undoable command', () async {
    await session.open('book');
    final first = proposal('first', '广告', after: '和');
    final second = proposal('second', '广告', before: '和');
    final unchanged = proposal(
      'unselected',
      '尾文',
      replacement: '结尾',
      action: AiTextProposalAction.replaceText,
    );
    final originalSession = session.sessionId;

    await session.applyAiTextProposals(
      [first, second, unchanged],
      selectedIds: {'first', 'second'},
    );
    expect(session.sessionId, originalSession);
    expect(session.saveSeq, first.target.sessionRevision + 1);
    expect((session.activeChapter!.blocks.first as TextBlock).text, '😀和。尾文');
    expect(session.activeChapter!.blocks.map((block) => block.id), [
      'p1',
      'image',
      'footnote',
    ]);
    expect(
      session.activeChapter!.blocks[1],
      const ImageBlock(id: 'image', assetId: 'asset', caption: '插图'),
    );
    expect(
      session.activeChapter!.blocks[2],
      const FootnoteBlock(id: 'footnote', text: '注释', marker: '1'),
    );
    expect(session.book!.chapters.map((chapter) => chapter.id), ['a', 'b']);
    expect(store.loadedChapterIds, ['a']);

    await session.undo();
    expect(
      (session.activeChapter!.blocks.first as TextBlock).text,
      '😀广告和广告。尾文',
    );
    expect(session.canUndo, isFalse);
    await session.redo();
    expect((session.activeChapter!.blocks.first as TextBlock).text, '😀和。尾文');
    await session.flush();
    expect(store.savedDirtyIds.single, {'a'});
    expect(store.bodies['a']!.blocks[1], isA<ImageBlock>());
    expect(store.bodies['a']!.blocks[2], isA<FootnoteBlock>());
  });

  test(
    'repeated text needs unique context and UTF-16 ranges stay exact',
    () async {
      await session.open('book');
      final ambiguous = AiTextProposal(
        id: 'ambiguous',
        action: AiTextProposalAction.deleteText,
        target: ProposalTextTarget(
          bookId: 'book',
          sessionId: session.sessionId!,
          sessionRevision: session.saveSeq,
          chapterId: 'a',
          blockId: 'p1',
          originalText: '广告',
        ),
        range: const ProposalTextRange(2, 4),
        replacement: '',
        reason: '重复文本',
      );
      await expectLater(
        session.applyAiTextProposals([ambiguous], selectedIds: {'ambiguous'}),
        throwsA(isA<ValidationFailure>()),
      );
      final contextual = proposal('contextual', '广告', before: '😀');
      final forgedBoundary = AiTextProposal(
        id: 'boundary',
        action: contextual.action,
        target: contextual.target,
        range: const ProposalTextRange(1, 4),
        replacement: contextual.replacement,
        reason: contextual.reason,
      );
      await expectLater(
        session.applyAiTextProposals(
          [forgedBoundary],
          selectedIds: {'boundary'},
        ),
        throwsA(isA<ValidationFailure>()),
      );
      await session.applyAiTextProposals(
        [contextual],
        selectedIds: {'contextual'},
      );
      expect(
        (session.activeChapter!.blocks.first as TextBlock).text,
        '😀和广告。尾文',
      );
    },
  );

  test(
    'conflicts, forged content and duplicate IDs fail without half batch',
    () async {
      await session.open('book');
      final first = proposal('first', '广告', before: '😀');
      final overlap = proposal('overlap', '广告和', before: '😀');
      final forged = proposal(
        'forged',
        '尾文',
        replacement: '尾文',
        action: AiTextProposalAction.replaceText,
      );
      final badUtf16 = proposal(
        'bad',
        '尾文',
        replacement: String.fromCharCode(0xd800),
        action: AiTextProposalAction.replaceText,
      );
      final originalSeq = session.saveSeq;
      for (final (items, selected) in [
        (<AiTextProposal>[first, overlap], <String>{'first', 'overlap'}),
        (<AiTextProposal>[first, forged], <String>{'first', 'forged'}),
        (<AiTextProposal>[first, badUtf16], <String>{'first', 'bad'}),
        (<AiTextProposal>[first, first], <String>{'first'}),
        (<AiTextProposal>[first], <String>{'unknown'}),
      ]) {
        await expectLater(
          session.applyAiTextProposals(items, selectedIds: selected),
          throwsA(isA<ValidationFailure>()),
        );
        expect(session.saveSeq, originalSeq);
        expect(session.canUndo, isFalse);
        expect(
          (session.activeChapter!.blocks.first as TextBlock).text,
          '😀广告和广告。尾文',
        );
      }
      await session.applyAiTextProposals([first], selectedIds: {});
      expect(session.saveSeq, originalSeq);
    },
  );

  test(
    'uses current unsaved body and loads only selected target chapters',
    () async {
      await session.open('book');
      session.editBlockText('p1', '新广告正文');
      final current = proposal('current', '广告', source: '新广告正文', before: '新');
      final other = proposal('other', '广告', chapterId: 'b', blockId: 'p2');
      await session.applyAiTextProposals(
        [current, other],
        selectedIds: {'current', 'other'},
      );
      expect((session.activeChapter!.blocks.first as TextBlock).text, '新正文');
      expect(
        (session.book!.chapters.last.blocks.first as TextBlock).text,
        '后文',
      );
      expect(store.loadedChapterIds, ['a', 'b']);
      await session.undo();
      expect((session.activeChapter!.blocks.first as TextBlock).text, '新广告正文');
      expect(
        (session.book!.chapters.last.blocks.first as TextBlock).text,
        '后文广告',
      );
    },
  );

  test(
    'in-flight save keeps loaded targets until the AI command finishes',
    () async {
      store.book = store.book.copyWith(
        chapters: [
          ...store.book.chapters,
          const Chapter(id: 'c', bookId: 'book', title: '第三章', order: 2),
        ],
      );
      store.bodies['c'] = const Chapter(
        id: 'c',
        bookId: 'book',
        title: '第三章',
        order: 2,
        blocks: <Block>[TextBlock(id: 'p3', text: '第三广告')],
      );
      await session.open('book');
      session.editBlockText('p1', '未保存的正文');
      final saveGate = Completer<void>();
      store.saveGate = saveGate;
      final flushing = session.flush();
      await Future<void>.delayed(Duration.zero);
      expect(session.isSaving, isTrue);

      final inB = proposal(
        'in-b',
        '广告',
        chapterId: 'b',
        blockId: 'p2',
        replacement: '正文',
        action: AiTextProposalAction.replaceText,
      );
      final inC = proposal(
        'in-c',
        '广告',
        chapterId: 'c',
        blockId: 'p3',
        replacement: '正文',
        action: AiTextProposalAction.replaceText,
      );
      store.gatedChapterId = 'c';
      store.chapterReadStarted = Completer<void>();
      store.chapterReadGate = Completer<void>();
      final applying = session.applyAiTextProposals(
        [inB, inC],
        selectedIds: {'in-b', 'in-c'},
      );
      await store.chapterReadStarted!.future;
      expect(session.book!.chapters[1].blocks.single, isA<TextBlock>());
      saveGate.complete();
      await flushing;
      expect(session.dirty, isFalse);
      expect(session.book!.chapters[1].blocks.single, isA<TextBlock>());
      store.chapterReadGate!.complete();

      await applying;
      expect(
        (session.book!.chapters[1].blocks.single as TextBlock).text,
        '后文正文',
      );
      expect(
        (session.book!.chapters[2].blocks.single as TextBlock).text,
        '第三正文',
      );
      expect((session.activeChapter!.blocks.first as TextBlock).text, '未保存的正文');
      await session.flush();
      expect((store.bodies['b']!.blocks.single as TextBlock).text, '后文正文');
      expect((store.bodies['c']!.blocks.single as TextBlock).text, '第三正文');
    },
  );

  test('closing during target load rejects the pending application', () async {
    await session.open('book');
    final pending = proposal('pending', '广告', chapterId: 'b', blockId: 'p2');
    store.chapterReadStarted = Completer<void>();
    store.chapterReadGate = Completer<void>();
    final applying = session.applyAiTextProposals(
      [pending],
      selectedIds: {'pending'},
    );
    await store.chapterReadStarted!.future;
    await session.close();
    closed = true;
    store.chapterReadGate!.complete();
    await expectLater(applying, throwsA(isA<StateError>()));
    expect(session.sessionId, isNull);
    expect((store.bodies['b']!.blocks.single as TextBlock).text, '后文广告');
  });

  test('cancelTool prevents a late worker result from applying', () async {
    session.dispose();
    final jobs = _PausedJobs();
    session = EditorSession.withStore(
      store: store,
      jobs: jobs,
      debounce: const Duration(milliseconds: 800),
    );
    await session.open('book');
    final pending = proposal('pending', '广告', before: '😀');
    final applying = session.applyAiTextProposals(
      [pending],
      selectedIds: {'pending'},
    );
    await jobs.started.future;
    expect(session.isToolRunning, isTrue);
    session.cancelTool();
    jobs.resume.complete();
    await expectLater(applying, throwsA(isA<TaskCancelled>()));
    expect(session.isToolRunning, isFalse);
    expect(session.canUndo, isFalse);
    expect(
      (session.activeChapter!.blocks.first as TextBlock).text,
      '😀广告和广告。尾文',
    );
  });

  for (final redo in [false, true]) {
    final operation = redo ? 'redo' : 'undo';

    test('$operation loading blocks AI before its history commit', () async {
      await session.open('book');
      await session.selectChapter('b');
      session.editBlockText('p2', '修改后的正文');
      if (redo) await session.undo();
      await session.flush();
      await session.selectChapter('a');
      final pending = proposal('pending', '广告', before: '😀');
      store.chapterReadGate = Completer<void>();
      store.chapterReadStarted = Completer<void>();
      final applyingHistory = redo ? session.redo() : session.undo();
      await store.chapterReadStarted!.future;

      await expectLater(
        session.applyAiTextProposals([pending], selectedIds: {'pending'}),
        throwsA(isA<ValidationFailure>()),
      );
      store.chapterReadGate!.complete();
      await applyingHistory;
      store.chapterReadGate = null;
      expect(
        (session.activeChapter!.blocks.first as TextBlock).text,
        redo ? '修改后的正文' : '后文广告',
      );
      expect(session.canUndo, redo);
      expect(session.canRedo, !redo);
      if (redo) {
        await session.undo();
      } else {
        await session.redo();
      }
      expect(
        (session.activeChapter!.blocks.first as TextBlock).text,
        redo ? '后文广告' : '修改后的正文',
      );
    });

    test('AI worker blocks $operation without moving its cursor', () async {
      session.dispose();
      final jobs = _PausedJobs();
      session = EditorSession.withStore(
        store: store,
        jobs: jobs,
        debounce: const Duration(milliseconds: 800),
      );
      await session.open('book');
      await session.selectChapter('b');
      session.editBlockText('p2', '修改后的正文');
      if (redo) await session.undo();
      await session.flush();
      await session.selectChapter('a');
      final pending = proposal('pending', '广告', before: '😀');
      final applying = session.applyAiTextProposals(
        [pending],
        selectedIds: {'pending'},
      );
      await jobs.started.future;

      await expectLater(
        redo ? session.redo() : session.undo(),
        throwsA(isA<ValidationFailure>()),
      );
      expect(session.canUndo, !redo);
      expect(session.canRedo, redo);
      if (redo) session.cancelTool();
      jobs.resume.complete();
      if (redo) {
        await expectLater(applying, throwsA(isA<TaskCancelled>()));
        await session.redo();
        expect(
          (session.activeChapter!.blocks.first as TextBlock).text,
          '修改后的正文',
        );
      } else {
        await applying;
        await session.undo();
        expect(
          (session.activeChapter!.blocks.first as TextBlock).text,
          '😀广告和广告。尾文',
        );
        await session.undo();
        expect((session.activeChapter!.blocks.first as TextBlock).text, '后文广告');
        await session.redo();
        expect(
          (session.activeChapter!.blocks.first as TextBlock).text,
          '修改后的正文',
        );
      }
    });
  }

  test('editing while the worker runs rejects its old revision', () async {
    session.dispose();
    final jobs = _PausedJobs();
    session = EditorSession.withStore(
      store: store,
      jobs: jobs,
      debounce: const Duration(milliseconds: 800),
    );
    await session.open('book');
    final pending = proposal('pending', '广告', before: '😀');
    final applying = session.applyAiTextProposals(
      [pending],
      selectedIds: {'pending'},
    );
    await jobs.started.future;
    session.editBlockText('p1', '人工修改');
    jobs.resume.complete();
    await expectLater(applying, throwsA(isA<ValidationFailure>()));
    expect(session.isToolRunning, isFalse);
    expect((session.activeChapter!.blocks.first as TextBlock).text, '人工修改');
  });

  test(
    'switching chapters while loading another target keeps prior target',
    () async {
      store.book = store.book.copyWith(
        chapters: [
          ...store.book.chapters,
          const Chapter(id: 'c', bookId: 'book', title: '第三章', order: 2),
        ],
      );
      store.bodies['c'] = const Chapter(
        id: 'c',
        bookId: 'book',
        title: '第三章',
        order: 2,
        blocks: <Block>[TextBlock(id: 'p3', text: '第三章正文')],
      );
      await session.open('book');
      final inA = proposal(
        'in-a',
        '广告',
        before: '😀',
        replacement: '正文',
        action: AiTextProposalAction.replaceText,
      );
      final inB = proposal(
        'in-b',
        '广告',
        chapterId: 'b',
        blockId: 'p2',
        replacement: '正文',
        action: AiTextProposalAction.replaceText,
      );
      store.chapterReadStarted = Completer<void>();
      store.chapterReadGate = Completer<void>();
      final applying = session.applyAiTextProposals(
        [inA, inB],
        selectedIds: {'in-a', 'in-b'},
      );
      await store.chapterReadStarted!.future;
      await session.selectChapter('c');
      expect(session.activeChapterId, 'c');
      store.chapterReadGate!.complete();

      await applying;
      expect(
        (session.book!.chapters.first.blocks.first as TextBlock).text,
        '😀正文和广告。尾文',
      );
      expect(
        (session.book!.chapters[1].blocks.single as TextBlock).text,
        '后文正文',
      );
      expect(session.activeChapterId, 'c');
      await session.flush();
      expect((store.bodies['a']!.blocks.first as TextBlock).text, '😀正文和广告。尾文');
      expect((store.bodies['b']!.blocks.single as TextBlock).text, '后文正文');
    },
  );

  test(
    'caller mutations during lazy load cannot change proposal or selection',
    () async {
      await session.open('book');
      final selected = proposal(
        'selected',
        '广告',
        chapterId: 'b',
        blockId: 'p2',
        replacement: '正文',
        action: AiTextProposalAction.replaceText,
      );
      final unselected = proposal(
        'unselected',
        '后文',
        chapterId: 'b',
        blockId: 'p2',
        replacement: '伪文',
        action: AiTextProposalAction.replaceText,
      );
      final proposals = <AiTextProposal>[selected, unselected];
      final selectedIds = <String>{'selected'};
      store.chapterReadStarted = Completer<void>();
      store.chapterReadGate = Completer<void>();

      final applying = session.applyAiTextProposals(
        proposals,
        selectedIds: selectedIds,
      );
      await store.chapterReadStarted!.future;
      proposals[0] = AiTextProposal(
        id: selected.id,
        action: selected.action,
        target: selected.target,
        range: selected.range,
        replacement: '篡改',
        reason: selected.reason,
      );
      selectedIds
        ..clear()
        ..add('unselected');
      store.chapterReadGate!.complete();

      await applying;
      expect(
        (session.book!.chapters.last.blocks.single as TextBlock).text,
        '后文正文',
      );
      expect(
        (session.activeChapter!.blocks.first as TextBlock).text,
        '😀广告和广告。尾文',
      );
    },
  );

  test('delete_text clears characters without removing the block', () async {
    await session.open('book');
    final wholeBlock = proposal('whole', '后文广告', chapterId: 'b', blockId: 'p2');
    await session.applyAiTextProposals([wholeBlock], selectedIds: {'whole'});
    final block = session.book!.chapters.last.blocks.single as TextBlock;
    expect(block.id, 'p2');
    expect(block.text, isEmpty);
    await session.undo();
    expect(
      (session.book!.chapters.last.blocks.single as TextBlock).text,
      '后文广告',
    );
  });

  test(
    'undo budget rejects the entire batch before changing content',
    () async {
      session.dispose();
      session = EditorSession.withStore(
        store: store,
        debounce: const Duration(milliseconds: 800),
        historyByteBudget: 8,
      );
      await session.open('book');
      final item = proposal('too-large', '广告', before: '😀');
      final originalSeq = session.saveSeq;
      await expectLater(
        session.applyAiTextProposals([item], selectedIds: {'too-large'}),
        throwsA(isA<ValidationFailure>()),
      );
      expect(session.saveSeq, originalSeq);
      expect(session.canUndo, isFalse);
      expect(
        (session.activeChapter!.blocks.first as TextBlock).text,
        '😀广告和广告。尾文',
      );
    },
  );

  test('old revision, reopen and closed session reject proposals', () async {
    final observedSessionIds = <String?>[];
    session.addListener(() => observedSessionIds.add(session.sessionId));
    await session.open('book');
    expect(observedSessionIds.last, session.sessionId);
    final old = proposal('old', '广告', before: '😀');
    final firstId = session.sessionId;
    session.editBlockText('p1', '新正文');
    await expectLater(
      session.applyAiTextProposals([old], selectedIds: {'old'}),
      throwsA(isA<ValidationFailure>()),
    );
    await session.open('book');
    expect(session.sessionId, isNot(firstId));
    await expectLater(
      session.applyAiTextProposals([old], selectedIds: {'old'}),
      throwsA(isA<ValidationFailure>()),
    );
    await session.close();
    closed = true;
    expect(session.sessionId, isNull);
    await expectLater(
      session.applyAiTextProposals([old], selectedIds: {'old'}),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'a pending reopen invalidates proposals before its read completes',
    () async {
      await session.open('book');
      final pending = proposal('pending', '广告', before: '😀');
      store.readGate = Completer<void>();
      final reopening = session.open('book');
      await Future<void>.delayed(Duration.zero);
      expect(session.sessionId, isNull);
      await expectLater(
        session.applyAiTextProposals([pending], selectedIds: {'pending'}),
        throwsA(isA<ValidationFailure>()),
      );
      store.readGate!.complete();
      await reopening;
      expect(session.sessionId, isNot(pending.target.sessionId));
    },
  );

  test(
    'failed reopen gives the retained book a fresh session identity',
    () async {
      await session.open('book');
      final old = proposal('old', '广告', before: '😀');
      await expectLater(
        session.open('missing'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(session.book!.id, 'book');
      expect(session.sessionId, isNot(old.target.sessionId));
      await expectLater(
        session.applyAiTextProposals([old], selectedIds: {'old'}),
        throwsA(isA<ValidationFailure>()),
      );
      final current = proposal('current', '广告', before: '😀');
      await session.applyAiTextProposals([current], selectedIds: {'current'});
      expect(
        (session.activeChapter!.blocks.first as TextBlock).text,
        '😀和广告。尾文',
      );
    },
  );

  test('save failure retains applied text and existing retry path', () async {
    await session.open('book');
    final pending = proposal('pending', '广告', before: '😀');
    await session.applyAiTextProposals([pending], selectedIds: {'pending'});
    store.failNext = true;
    await expectLater(session.flush(), throwsA(isA<StorageFailure>()));
    expect(session.dirty, isTrue);
    expect(session.saveError, isA<StorageFailure>());
    expect((session.activeChapter!.blocks.first as TextBlock).text, '😀和广告。尾文');
    await session.retrySave();
    expect(session.dirty, isFalse);
    expect((store.bodies['a']!.blocks.first as TextBlock).text, '😀和广告。尾文');
  });

  test(
    'real in-memory repository persists one undoable text command',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'bookloom-ai-text-',
      );
      final database = AppDatabase.memory();
      final repository = BookRepository(database, support);
      final now = DateTime.utc(2026, 11, 6);
      final persistedSession = EditorSession(
        repository: repository,
        debounce: const Duration(milliseconds: 800),
      );
      try {
        await repository.createBook(
          Book(
            id: 'persisted',
            meta: BookMeta(title: '书', author: '作者'),
            chapters: const <Chapter>[
              Chapter(
                id: 'chapter',
                bookId: 'persisted',
                title: '第一章',
                blocks: <Block>[TextBlock(id: 'block', text: '😀广告结尾')],
              ),
            ],
            createdAt: now,
            updatedAt: now,
          ),
        );
        await persistedSession.open('persisted');
        final target = ProposalTextTarget(
          bookId: 'persisted',
          sessionId: persistedSession.sessionId!,
          sessionRevision: persistedSession.saveSeq,
          chapterId: 'chapter',
          blockId: 'block',
          originalText: '广告',
          before: '😀',
        );
        final item = AiTextProposal(
          id: 'replace',
          action: AiTextProposalAction.replaceText,
          target: target,
          range: const ProposalTextRange(2, 4),
          replacement: '正文',
          reason: '替换',
        );
        await persistedSession.applyAiTextProposals(
          [item],
          selectedIds: {'replace'},
        );
        await persistedSession.flush();
        expect(
          (await repository.loadChapter('persisted', 'chapter'))!.blocks.single,
          const TextBlock(id: 'block', text: '😀正文结尾'),
        );
        await persistedSession.undo();
        await persistedSession.flush();
        expect(
          (await repository.loadChapter('persisted', 'chapter'))!.blocks.single,
          const TextBlock(id: 'block', text: '😀广告结尾'),
        );
      } finally {
        persistedSession.dispose();
        await database.close();
        await support.delete(recursive: true);
      }
    },
  );
}

class _MemoryStore implements EditorBookStore {
  _MemoryStore() {
    final now = DateTime.utc(2026, 11, 6);
    book = Book(
      id: 'book',
      meta: BookMeta(title: '书', author: '作者'),
      chapters: const <Chapter>[
        Chapter(id: 'a', bookId: 'book', title: '第一章', order: 0),
        Chapter(id: 'b', bookId: 'book', title: '第二章', order: 1),
      ],
      createdAt: now,
      updatedAt: now,
      wordCount: WordCount.ofText('😀广告和广告。尾文') + WordCount.ofText('后文广告'),
    );
    bodies['a'] = const Chapter(
      id: 'a',
      bookId: 'book',
      title: '第一章',
      order: 0,
      blocks: <Block>[
        TextBlock(id: 'p1', text: '😀广告和广告。尾文'),
        ImageBlock(id: 'image', assetId: 'asset', caption: '插图'),
        FootnoteBlock(id: 'footnote', text: '注释', marker: '1'),
      ],
    );
    bodies['b'] = const Chapter(
      id: 'b',
      bookId: 'book',
      title: '第二章',
      order: 1,
      blocks: <Block>[TextBlock(id: 'p2', text: '后文广告')],
    );
  }

  late Book book;
  final Map<String, Chapter> bodies = {};
  final List<String> loadedChapterIds = [];
  final List<Set<String>> savedDirtyIds = [];
  Completer<void>? readGate;
  Completer<void>? saveGate;
  Completer<void>? chapterReadGate;
  Completer<void>? chapterReadStarted;
  String gatedChapterId = 'b';
  bool failNext = false;

  @override
  Future<Book?> loadBook(String bookId) async {
    final gate = readGate;
    if (gate != null) await gate.future;
    return bookId == book.id ? book : null;
  }

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async {
    loadedChapterIds.add(chapterId);
    if (chapterId == gatedChapterId && chapterReadGate != null) {
      chapterReadStarted?.complete();
      await chapterReadGate!.future;
    }
    return bookId == book.id ? bodies[chapterId] : null;
  }

  @override
  Future<Book> saveBook(
    Book source, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    savedDirtyIds.add(Set<String>.of(dirtyChapterIds));
    final gate = saveGate;
    saveGate = null;
    if (gate != null) await gate.future;
    if (failNext) {
      failNext = false;
      throw const StorageFailure('模拟保存失败');
    }
    if (expectedRevision != book.revision) {
      throw const StorageFailure('版本冲突');
    }
    for (final chapter in source.chapters) {
      if (dirtyChapterIds.contains(chapter.id)) bodies[chapter.id] = chapter;
    }
    book = source.copyWith(
      chapters: [
        for (final chapter in source.chapters)
          chapter.copyWith(blocks: const <Block>[]),
      ],
      revision: expectedRevision + 1,
      wordCount: bodies.values.fold<int>(
        0,
        (sum, chapter) => sum + WordCount.ofBlocks(chapter.blocks),
      ),
    );
    return book;
  }
}

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
