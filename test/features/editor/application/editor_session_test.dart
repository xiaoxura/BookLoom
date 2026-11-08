import 'dart:async';

import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryStore store;
  late EditorSession session;

  setUp(() {
    store = _MemoryStore();
    session = EditorSession.withStore(
      store: store,
      debounce: const Duration(milliseconds: 800),
    );
  });

  tearDown(() => session.dispose());

  test('loads only the active body and saves only its dirty blocks', () async {
    await session.open('book');
    expect(store.loadedChapterIds, <String>['a']);
    expect(session.book!.chapters[1].blocks, isEmpty);

    session.editBlockText('p1', '修改后的正文');
    expect(session.dirty, isTrue);
    await session.flush();
    expect(store.savedDirtyIds.single, <String>{'a'});
    expect(session.activeChapter!.blocks.single.plainText, '修改后的正文');
    expect(session.dirty, isFalse);
    expect(session.book!.revision, 1);

    await session.selectChapter('b');
    expect(store.loadedChapterIds, <String>['a', 'b']);
    expect(session.activeChapterId, 'b');
    expect(session.book!.chapters.first.blocks, isEmpty);
  });

  test(
    'selection context loads a distant large chapter without activating it',
    () async {
      await session.open('book');
      final originalSession = session.sessionId;
      final originalRevision = session.saveSeq;
      final longText = '正文' * 400000;
      store._bodies['b'] = store._bodies['b']!.copyWith(
        blocks: [TextBlock(id: 'p2', text: longText)],
      );
      final chapter = await session.readAiSelectionChapter('b');
      expect(chapter.blocks.single.plainText, longText);
      expect(session.activeChapterId, 'a');
      expect(session.activeChapter!.blocks.single.plainText, '原文');
      expect(session.sessionId, originalSession);
      expect(session.saveSeq, originalRevision);
      expect(session.dirty, false);
      expect(session.canUndo, false);
      expect(store.saveCalls, 0);
      expect(store.loadedChapterIds, ['a', 'b']);
    },
  );

  test(
    'selection context drains autosave before loading the remote source',
    () async {
      await session.open('book');
      session.editBlockText('p1', '待保存修改');
      final revision = session.saveSeq;
      final gate = Completer<void>();
      store.saveGate = gate;
      final saving = session.flush();
      final reading = session.readAiSelectionChapter('b');
      await Future<void>.delayed(Duration.zero);
      expect(store.loadedChapterIds, ['a']);
      gate.complete();
      await saving;
      await reading;
      final request = AiAdvertisementRequest.fromSelection(
        book: session.book!,
        sessionId: session.sessionId!,
        sessionRevision: revision,
        chapterId: 'b',
        blockId: 'p2',
        startUtf16: 0,
        endUtf16: 2,
        original: '后文',
      );
      await session.flush();
      request.validate(
        book: session.book!,
        sessionId: session.sessionId!,
        sessionRevision: session.saveSeq,
      );
      expect(session.activeChapterId, 'a');
      expect(session.activeChapter!.blocks.single.plainText, '待保存修改');
      expect(session.saveSeq, revision);
      expect(session.dirty, false);
      expect(store.saveCalls, 1);
    },
  );

  test('selection context refuses cancellation and concurrent edits', () async {
    await session.open('book');
    await expectLater(
      session.readAiSelectionChapter('b', isCancelled: () => true),
      throwsA(isA<TaskCancelled>()),
    );
    expect(store.loadedChapterIds, ['a']);
    final gate = Completer<void>();
    store.loadGate = gate;
    final reading = session.readAiSelectionChapter('b');
    await Future<void>.delayed(Duration.zero);
    session.editBlockText('p1', '继续编辑');
    gate.complete();
    await expectLater(reading, throwsA(isA<ValidationFailure>()));
    expect(session.activeChapterId, 'a');
    expect(session.activeChapter!.blocks.single.plainText, '继续编辑');
    await session.flush();
  });

  test(
    'AI snapshot preserves ordered local resources without sending them',
    () async {
      const mixed = <Block>[
        ImageBlock(
          id: 'before-image',
          assetId: 'private-image',
          caption: '本地图注',
        ),
        TextBlock(id: 'p2', text: '第三章 标题\n远章正文'),
        FootnoteBlock(id: 'note', text: '不外发的脚注', marker: '①'),
        DividerBlock(id: 'divider'),
        TextBlock(id: 'tail', text: '末段'),
      ];
      store._bodies['b'] = store._bodies['b']!.copyWith(blocks: mixed);
      await session.open('book');
      final revision = session.saveSeq;
      final snapshot = await session.readAiContextSnapshot(['b']);
      expect(snapshot.blocks.map((block) => block.text), [
        '第三章 标题\n远章正文',
        '末段',
      ]);
      expect(snapshot.chapters.keys, ['b']);
      expect(snapshot.chapters['b']!.blocks, mixed);
      expect(session.activeChapterId, 'a');
      expect(session.saveSeq, revision);
      expect(session.canUndo, false);
      expect(store.saveCalls, 0);
      expect(snapshot.blocks.clear, throwsUnsupportedError);
      expect(snapshot.chapters.clear, throwsUnsupportedError);
      expect(
        () => snapshot.chapters['b']!.blocks.clear(),
        throwsUnsupportedError,
      );
      session.editBlockText('p1', '触发自动保存与远章淘汰');
      await session.flush();
      expect(
        session.book!.chapters
            .singleWhere((chapter) => chapter.id == 'b')
            .blocks,
        isEmpty,
      );
      expect(snapshot.chapters['b']!.blocks, mixed);
    },
  );

  test(
    'AI snapshot waits for an in-flight save before remote loading',
    () async {
      await session.open('book');
      session.editBlockText('p1', '待保存正文');
      final gate = Completer<void>();
      store.saveGate = gate;
      final saving = session.flush();
      final reading = session.readAiContextSnapshot(['a', 'b']);
      await Future<void>.delayed(Duration.zero);
      expect(store.loadedChapterIds, ['a']);
      gate.complete();
      await saving;
      final snapshot = await reading;
      expect(snapshot.blocks.map((block) => block.text), ['待保存正文', '后文']);
      expect(snapshot.chapters.keys, ['a', 'b']);
      expect(store.saveCalls, 1);
      expect(session.activeChapterId, 'a');
    },
  );

  test(
    'AI snapshot releases clean remote bodies across batches and cancellation',
    () async {
      final chapters = <Chapter>[
        for (var index = 0; index < 3; index++)
          Chapter(
            id: 'remote-$index',
            bookId: 'book',
            title: '远章$index',
            order: index + 2,
            blocks: [TextBlock(id: 'remote-body-$index', text: '远章正文$index')],
          ),
      ];
      store._book = store._book.copyWith(
        chapters: [
          ...store._book.chapters,
          ...chapters.map((chapter) => chapter.copyWith(blocks: const [])),
        ],
      );
      store._bodies.addEntries(
        chapters.map((chapter) => MapEntry(chapter.id, chapter)),
      );
      await session.open('book');
      for (final chapter in chapters) {
        final snapshot = await session.readAiContextSnapshot([chapter.id]);
        expect(snapshot.chapters[chapter.id]!.blocks, chapter.blocks);
        expect(
          session.book!.chapters
              .where((item) => item.id != 'a')
              .every((item) => item.blocks.isEmpty),
          true,
        );
        expect(session.activeChapter!.blocks.single.plainText, '原文');
      }
      final gate = Completer<void>();
      store.loadGate = gate;
      var cancelled = false;
      final reading = session.readAiContextSnapshot([
        'b',
      ], isCancelled: () => cancelled);
      await Future<void>.delayed(Duration.zero);
      cancelled = true;
      gate.complete();
      await expectLater(reading, throwsA(isA<TaskCancelled>()));
      expect(
        session.book!.chapters
            .singleWhere((chapter) => chapter.id == 'b')
            .blocks,
        isEmpty,
      );
      expect(store.saveCalls, 0);
      expect(session.canUndo, false);
    },
  );

  test('AI snapshot refuses cancelled, changed and unsaved input', () async {
    await session.open('book');
    await expectLater(
      session.readAiContextSnapshot(['b'], isCancelled: () => true),
      throwsA(isA<TaskCancelled>()),
    );
    expect(store.loadedChapterIds, ['a']);
    final gate = Completer<void>();
    store.loadGate = gate;
    final reading = session.readAiContextSnapshot(['b']);
    await Future<void>.delayed(Duration.zero);
    session.editBlockText('p1', '并发编辑');
    gate.complete();
    await expectLater(reading, throwsA(isA<ValidationFailure>()));
    store.failNext = true;
    await expectLater(
      session.readAiContextSnapshot(['b']),
      throwsA(isA<StorageFailure>()),
    );
    expect(session.dirty, true);
    await session.flush();
  });

  test('AI snapshot bounds non-text blocks as well as network text', () async {
    store._bodies['b'] = store._bodies['b']!.copyWith(
      blocks: [
        const TextBlock(id: 'p2', text: '正文'),
        for (var index = 0; index < 10000; index++)
          DividerBlock(id: 'divider-$index'),
      ],
    );
    await session.open('book');
    await expectLater(
      session.readAiContextSnapshot(['b']),
      throwsA(isA<ValidationFailure>()),
    );
    expect(store.saveCalls, 0);
    expect(session.canUndo, false);
  });

  test('debounce saves after idle interval', () async {
    await session.open('book');
    session.editBlockText('p1', '一');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    session.editBlockText('p1', '一二');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(store.saveCalls, 0);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(store.saveCalls, 1);
    expect(session.dirty, isFalse);
  });

  test(
    'edit during in-flight save remains dirty until the next commit',
    () async {
      await session.open('book');
      final gate = Completer<void>();
      store.saveGate = gate;
      session.editBlockText('p1', '第一次');
      final flushing = session.flush();
      await Future<void>.delayed(Duration.zero);
      expect(session.isSaving, isTrue);
      session.editBlockText('p1', '第二次');
      gate.complete();
      await flushing;
      expect(store.saveCalls, 2);
      expect(session.book!.revision, 2);
      expect(session.activeChapter!.blocks.single.plainText, '第二次');
      expect(session.dirty, isFalse);
    },
  );

  test(
    'failed save retains content and blocks chapter switch until retry',
    () async {
      await session.open('book');
      session.editBlockText('p1', '待重试');
      store.failNext = true;
      await expectLater(
        session.selectChapter('b'),
        throwsA(isA<StorageFailure>()),
      );
      expect(session.activeChapterId, 'a');
      expect(session.activeChapter!.blocks.single.plainText, '待重试');
      expect(session.dirty, isTrue);
      expect(session.saveError, isA<StorageFailure>());
      await session.retrySave();
      await session.selectChapter('b');
      expect(session.activeChapterId, 'b');
      expect(session.dirty, isFalse);
    },
  );

  test(
    'merge saves target blocks and deletion; undo restores both bodies',
    () async {
      await session.open('book');
      await session.mergeWithPrevious('b');
      expect(session.book!.chapters, hasLength(1));
      expect(session.activeChapter!.blocks.map((block) => block.id), <String>[
        'p1',
        'p2',
      ]);
      await session.flush();
      expect(store.savedDirtyIds.last, <String>{'a'});
      expect(store.savedDeletedIds.last, <String>{'b'});

      await session.undo();
      expect(session.book!.chapters, hasLength(2));
      expect(session.book!.chapters[0].blocks.single.id, 'p1');
      expect(session.book!.chapters[1].blocks.single.id, 'p2');
      await session.flush();
      expect(store.savedDirtyIds.last, <String>{'a', 'b'});
      expect(store._bodies['b']!.blocks.single.id, 'p2');
    },
  );

  test('created chapter is editable and survives save and reopen', () async {
    await session.open('book');
    final volumeId = await session.createVolume('  第一卷  ');
    final chapterId = await session.createChapter('  新章  ', volumeId: volumeId);
    final created = session.activeChapter!;
    expect(session.activeChapterId, chapterId);
    expect(created.title, '新章');
    expect(created.parentId, volumeId);
    expect(created.blocks, hasLength(1));
    expect(created.blocks.single, isA<TextBlock>());
    expect(created.blocks.single.plainText, isEmpty);
    session.editBlockText(created.blocks.single.id, '新正文');
    await session.flush();
    expect(store.savedDirtyIds.single, <String>{volumeId, chapterId});
    expect(store._bodies[volumeId]!.blocks, isEmpty);
    expect(store._bodies[chapterId]!.blocks.single.plainText, '新正文');

    await session.open('book', chapterId: chapterId);
    expect(session.activeChapter!.blocks.single.plainText, '新正文');
    expect(session.book!.chapters.last.parentId, volumeId);
    expect(session.book!.chapters.last.order, 0);
  });

  test('new chapter is autosaved without an explicit flush', () async {
    await session.open('book');
    final chapterId = await session.createChapter('新章');
    await Future<void>.delayed(const Duration(milliseconds: 950));
    expect(store.saveCalls, 1);
    expect(store._bodies[chapterId]!.blocks.single.plainText, isEmpty);
    expect(session.dirty, isFalse);
  });

  test(
    'batch move keeps unloaded bodies and undo/redo as one command',
    () async {
      await session.open('book');
      final volumeId = await session.createVolume('第一卷');
      await session.flush();
      expect(store.loadedChapterIds, <String>['a']);

      await session.moveChaptersToVolume(<String>{
        'b',
        'a',
      }, volumeId: volumeId);
      expect(session.book!.chapters.map((chapter) => chapter.id), <String>[
        volumeId,
        'a',
        'b',
      ]);
      expect(session.book!.chapters.last.parentId, volumeId);
      expect(session.activeChapterId, 'a');
      expect(session.activeChapter!.isVolume, isFalse);
      expect(store.loadedChapterIds, <String>['a']);
      await session.flush();
      expect(store.savedDirtyIds.last, isEmpty);
      expect(store._bodies['b']!.blocks.single.plainText, '后文');

      await session.undo();
      expect(session.book!.chapters.map((chapter) => chapter.id), <String>[
        'a',
        'b',
        volumeId,
      ]);
      expect(session.book!.chapters[1].parentId, isNull);
      expect(session.activeChapterId, 'a');
      expect(session.activeChapter!.isVolume, isFalse);
      await session.flush();
      await session.redo();
      expect(session.book!.chapters.last.parentId, volumeId);
      expect(session.activeChapterId, 'a');
      expect(session.activeChapter!.isVolume, isFalse);
      await session.flush();
      await session.selectChapter('b');
      expect(session.activeChapter!.blocks.single.plainText, '后文');
      expect(store._bodies['a']!.blocks.single.plainText, '原文');
    },
  );

  test(
    'invalid structure arguments leave state and history untouched',
    () async {
      await session.open('book');
      final volumeId = await session.createVolume('第一卷');
      final nestedId = await session.createChapter('卷内章', volumeId: volumeId);
      await session.flush();
      final before = session.book!.chapters;
      final seq = session.saveSeq;
      final loaded = List<String>.of(store.loadedChapterIds);

      await expectLater(
        session.createVolume('  '),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        session.createChapter('新章', volumeId: 'missing'),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        session.createChapter('新章', beforeChapterId: nestedId),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        session.createChapter('新章', beforeChapterId: 'a', afterChapterId: 'b'),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        session.moveChaptersToVolume(<String>{'b', volumeId}, volumeId: null),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        session.moveChaptersToVolume(<String>{'missing'}, volumeId: volumeId),
        throwsA(isA<ValidationFailure>()),
      );
      expect(session.book!.chapters, same(before));
      expect(session.saveSeq, seq);
      expect(session.dirty, isFalse);
      expect(store.loadedChapterIds, loaded);
      expect(session.activeChapterId, nestedId);
    },
  );

  test(
    'volume-only book never activates a volume on open, undo or delete',
    () async {
      store._book = store._book.copyWith(
        chapters: const <Chapter>[
          Chapter(id: 'v', bookId: 'book', title: '卷', level: 1),
        ],
      );
      store._bodies
        ..clear()
        ..['v'] = const Chapter(id: 'v', bookId: 'book', title: '卷', level: 1);
      await session.open('book');
      expect(session.activeChapterId, isNull);
      expect(store.loadedChapterIds, isEmpty);
      await expectLater(
        session.selectChapter('v'),
        throwsA(isA<ValidationFailure>()),
      );

      final chapterId = await session.createChapter('第一章', volumeId: 'v');
      expect(session.activeChapterId, chapterId);
      await session.undo();
      expect(session.activeChapterId, isNull);
      await session.redo();
      expect(session.activeChapterId, chapterId);
      await session.deleteChapter(chapterId);
      expect(session.activeChapterId, isNull);
      expect(session.book!.chapters.single.id, 'v');
    },
  );

  test('deleting chapters beside an unsaved volume never selects it', () async {
    await session.open('book');
    final volumeId = await session.createVolume('空卷');
    await session.deleteChapter('b');
    expect(session.activeChapterId, 'a');
    await session.deleteChapter('a');
    expect(session.activeChapterId, isNull);
    expect(session.book!.chapters.single.id, volumeId);
    await session.deleteChapter(volumeId);
    expect(session.activeChapterId, isNull);
    expect(session.book!.chapters, isEmpty);
    expect(store.loadedChapterIds, isNot(contains(volumeId)));
  });

  test('text edits coalesce; new branch clears redo', () async {
    await session.open('book');
    session.editBlockText('p1', '甲');
    session.editBlockText('p1', '甲乙');
    await session.undo();
    expect(session.activeChapter!.blocks.single.plainText, '原文');
    expect(session.canUndo, isFalse);
    expect(session.canRedo, isTrue);
    await session.redo();
    expect(session.activeChapter!.blocks.single.plainText, '甲乙');
    await session.undo();
    session.editBlockText('p1', '新分支');
    expect(session.canRedo, isFalse);
  });

  test('structure and metadata share undo history', () async {
    await session.open('book');
    session.editChapterTitle('a', '新标题');
    session.editBookMeta(session.book!.meta.copyWith(author: '新作者'));
    expect(session.book!.meta.author, '新作者');
    await session.undo();
    expect(session.book!.meta.author, '原作者');
    await session.undo();
    expect(session.book!.chapters.first.title, '第一章');
    await session.redo();
    expect(session.book!.chapters.first.title, '新标题');
  });

  test(
    'layout and cover changes share undo without losing image choice',
    () async {
      await session.open('book');
      session.editLayout(session.book!.layout.copyWith(font: LayoutFont.kai));
      session.editCoverOptions(
        session.book!.coverOptions.copyWith(palette: 'forest'),
      );
      session.setCoverImage('cover-asset');
      session.setCoverTemplate();
      expect(session.book!.coverMode, CoverMode.template);
      expect(session.book!.coverAssetId, 'cover-asset');
      await session.undo();
      expect(session.book!.coverMode, CoverMode.image);
      await session.undo();
      expect(session.book!.coverAssetId, isNull);
      await session.undo();
      expect(session.book!.coverOptions.palette, 'auto');
      await session.undo();
      expect(session.book!.layout.font, LayoutFont.serif);
    },
  );

  test('undoing an unloaded title edit keeps a later loaded body', () async {
    await session.open('book');
    session.editChapterTitle('b', '改名');
    await session.selectChapter('b');
    expect(session.activeChapter!.blocks.single.plainText, '后文');
    await session.undo();
    expect(session.activeChapterId, 'a');
    expect(session.book!.chapters[1].title, '第二章');
    expect(session.book!.chapters[1].blocks.single.plainText, '后文');
  });

  test(
    'history budget counts changed text rather than a shared chapter body',
    () async {
      session.dispose();
      store._bodies['a'] = Chapter(
        id: 'a',
        bookId: 'book',
        title: '第一章',
        blocks: <Block>[TextBlock(id: 'p1', text: '长' * 10000)],
      );
      session = EditorSession.withStore(store: store, historyByteBudget: 100);
      await session.open('book');
      session.editChapterTitle('a', '新标题');
      expect(session.canUndo, isTrue);
      await session.undo();
      expect(session.activeChapter!.blocks.single.plainText.length, 10000);
    },
  );

  test('split and undo restore block ownership and saved summary', () async {
    await session.open('book');
    final newId = await session.splitAtParagraph('a', 'p1');
    expect(session.book!.chapters, hasLength(3));
    expect(session.activeChapterId, newId);
    await session.flush();
    expect(store.savedDirtyIds.single, <String>{'a', newId});
    expect(session.book!.wordCount, WordCount.ofText('后文'));
    await session.undo();
    expect(session.book!.chapters, hasLength(2));
    expect(session.book!.chapters.first.blocks.single.id, 'p1');
    await session.flush();
    expect(store.savedDeletedIds.last, <String>{newId});
    expect(
      session.book!.wordCount,
      WordCount.ofText('原文') + WordCount.ofText('后文'),
    );
  });

  test(
    'undoing an unsaved split does not delete a never-persisted chapter',
    () async {
      await session.open('book');
      final newId = await session.splitAtParagraph('a', 'p1');
      await session.undo();
      await session.flush();
      expect(store.savedDeletedIds.single, isEmpty);
      expect(store.savedDirtyIds.single, <String>{'a'});
      expect(store._bodies.containsKey(newId), isFalse);
    },
  );

  test(
    'deletion during an in-flight create is sent in the next save',
    () async {
      await session.open('book');
      final newId = await session.splitAtParagraph('a', 'p1');
      final gate = Completer<void>();
      store.saveGate = gate;
      final flushing = session.flush();
      await Future<void>.delayed(Duration.zero);
      await session.undo();
      gate.complete();
      await flushing;
      expect(store.savedDeletedIds.last, <String>{newId});
      expect(store._bodies.containsKey(newId), isFalse);
      expect(session.dirty, isFalse);
    },
  );

  test(
    'batch replace applies to the whole book as one undoable command',
    () async {
      await session.open('book');
      final preview = await session.previewReplace(
        const ReplaceOptions(find: '文', replace: '章'),
      );
      expect(preview.baseRevision, session.saveSeq);
      expect(preview.hits, 2);
      expect(preview.patches, hasLength(2));
      await session.applyToolPreview(preview);
      expect(session.activeChapter!.blocks.single.plainText, '原章');
      expect(session.book!.chapters[1].blocks.single.plainText, '后章');
      await session.undo();
      expect(session.activeChapter!.blocks.single.plainText, '原文');
      expect(session.book!.chapters[1].blocks.single.plainText, '后文');
      expect(session.canUndo, isFalse);
    },
  );

  test('stale preview refuses to overwrite an intervening edit', () async {
    await session.open('book');
    final preview = await session.previewReplace(
      const ReplaceOptions(find: '原文', replace: '替换'),
    );
    session.editBlockText('p1', '新编辑');
    await expectLater(
      session.applyToolPreview(preview),
      throwsA(isA<ValidationFailure>()),
    );
    expect(session.activeChapter!.blocks.single.plainText, '新编辑');
  });

  test(
    'oversize preview is rejected atomically under undo byte budget',
    () async {
      session.dispose();
      session = EditorSession.withStore(store: store, historyByteBudget: 100);
      await session.open('book');
      final preview = await session.previewReplace(
        ReplaceOptions(find: '原文', replace: '长' * 100),
      );
      await expectLater(
        session.applyToolPreview(preview),
        throwsA(isA<ValidationFailure>()),
      );
      expect(session.activeChapter!.blocks.single.plainText, '原文');
      expect(session.canUndo, isFalse);
    },
  );

  test('confirmed reparse replaces chapters but keeps book metadata', () async {
    await session.open('book');
    final originalMeta = session.book!.meta;
    final replacement = <Chapter>[
      const Chapter(
        id: 'new-a',
        bookId: 'book',
        title: '重识别章',
        blocks: <Block>[TextBlock(id: 'new-p', text: '重识别正文')],
      ),
    ];
    session.replaceAllChapters(
      replacement,
      const ParseOptions(encoding: 'utf-8', filterAds: false),
      expectedSaveSeq: session.saveSeq,
    );
    expect(session.book!.meta, same(originalMeta));
    expect(session.book!.chapters.single.id, 'new-a');
    expect(session.canUndo, isFalse);
    await session.flush();
    expect(store.savedDeletedIds.single, <String>{'a', 'b'});
    expect(store.savedDirtyIds.single, <String>{'new-a'});
    expect(store._bodies['new-a']!.blocks.single.plainText, '重识别正文');
  });

  test('history retains at most the latest fifty commands', () async {
    await session.open('book');
    for (var i = 0; i < 60; i++) {
      session.editChapterTitle('a', '章节 $i');
    }
    for (var i = 0; i < 50; i++) {
      await session.undo();
    }
    expect(session.canUndo, isFalse);
    expect(session.book!.chapters.first.title, '章节 9');
  });
}

class _MemoryStore implements EditorBookStore {
  _MemoryStore() {
    final now = DateTime.utc(2026, 11, 4);
    _book = Book(
      id: 'book',
      meta: BookMeta(title: '书', author: '原作者'),
      chapters: const <Chapter>[
        Chapter(id: 'a', bookId: 'book', title: '第一章', order: 0),
        Chapter(id: 'b', bookId: 'book', title: '第二章', order: 1),
      ],
      createdAt: now,
      updatedAt: now,
      wordCount: WordCount.ofText('原文') + WordCount.ofText('后文'),
    );
    _bodies['a'] = const Chapter(
      id: 'a',
      bookId: 'book',
      title: '第一章',
      order: 0,
      blocks: <Block>[TextBlock(id: 'p1', text: '原文')],
    );
    _bodies['b'] = const Chapter(
      id: 'b',
      bookId: 'book',
      title: '第二章',
      order: 1,
      blocks: <Block>[TextBlock(id: 'p2', text: '后文')],
    );
  }

  late Book _book;
  final Map<String, Chapter> _bodies = <String, Chapter>{};
  final List<String> loadedChapterIds = <String>[];
  final List<Set<String>> savedDirtyIds = <Set<String>>[];
  final List<Set<String>> savedDeletedIds = <Set<String>>[];
  Completer<void>? saveGate;
  Completer<void>? loadGate;
  bool failNext = false;
  int saveCalls = 0;

  @override
  Future<Book?> loadBook(String bookId) async =>
      bookId == 'book' ? _book : null;

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async {
    loadedChapterIds.add(chapterId);
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
    return _bodies[chapterId];
  }

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    saveCalls++;
    savedDirtyIds.add(Set<String>.of(dirtyChapterIds));
    savedDeletedIds.add(Set<String>.of(deletedChapterIds));
    final gate = saveGate;
    saveGate = null;
    if (gate != null) await gate.future;
    if (failNext) {
      failNext = false;
      throw const StorageFailure('模拟保存失败');
    }
    if (expectedRevision != _book.revision) {
      throw const StorageFailure('版本冲突');
    }
    if (!deletedChapterIds.every(_bodies.containsKey)) {
      throw const StorageFailure('删除了未入库的章节');
    }
    for (final chapter in book.chapters) {
      if (!_bodies.containsKey(chapter.id) &&
          !dirtyChapterIds.contains(chapter.id)) {
        throw const StorageFailure('新章节缺少正文写入标记');
      }
    }
    for (final id in deletedChapterIds) {
      _bodies.remove(id);
    }
    for (final chapter in book.chapters) {
      if (dirtyChapterIds.contains(chapter.id)) _bodies[chapter.id] = chapter;
    }
    final count = _bodies.values.fold<int>(
      0,
      (total, chapter) => total + WordCount.ofBlocks(chapter.blocks),
    );
    _book = book.copyWith(
      chapters: <Chapter>[
        for (final chapter in book.chapters)
          chapter.copyWith(blocks: const <Block>[]),
      ],
      revision: expectedRevision + 1,
      wordCount: count,
    );
    return _book;
  }
}
