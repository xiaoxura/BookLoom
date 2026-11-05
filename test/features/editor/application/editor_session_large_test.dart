import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter_test/flutter_test.dart';

// Run only in a planned large-book test window:
// flutter test --dart-define=BOOKLOOM_EDITOR_LARGE=1 \
//   test/features/editor/application/editor_session_large_test.dart
const bool _runLarge = String.fromEnvironment('BOOKLOOM_EDITOR_LARGE') == '1';

void main() {
  test(
    'one-million-character conversion applies as one sparse undoable edit',
    () async {
      final store = _LargeBookStore();
      final session = EditorSession.withStore(store: store);
      addTearDown(session.dispose);
      await session.open('large-book');

      final patches = <TextPatch>[];
      for (final chapter in store.bodies.values) {
        for (final block in chapter.blocks) {
          final paragraph = block as TextBlock;
          patches.add(
            TextPatch(
              chapterId: chapter.id,
              blockId: paragraph.id,
              before: paragraph.text,
              after: paragraph.text.replaceAll('後', '后'),
            ),
          );
        }
      }
      expect(patches, hasLength(1000));
      expect(
        patches.fold<int>(0, (length, patch) => length + patch.before.length),
        1000000,
      );

      await session.applyToolPreview(
        ToolPreview(
          baseRevision: session.saveSeq,
          hits: patches.length,
          patches: patches,
          samples: const <ReplaceSample>[],
        ),
      );
      expect(session.canUndo, isTrue);
      expect(
        session.book!.chapters
            .expand((chapter) => chapter.blocks)
            .cast<TextBlock>()
            .every((block) => !block.text.contains('後')),
        isTrue,
      );

      await session.undo();
      expect(session.canUndo, isFalse);
      expect(session.canRedo, isTrue);
      expect(
        session.book!.chapters
            .expand((chapter) => chapter.blocks)
            .cast<TextBlock>()
            .every((block) => !block.text.contains('后')),
        isTrue,
      );
    },
    skip: _runLarge ? false : 'Set BOOKLOOM_EDITOR_LARGE=1 in a planned window',
  );
}

class _LargeBookStore implements EditorBookStore {
  _LargeBookStore() {
    final chapters = <Chapter>[];
    for (var chapterIndex = 0; chapterIndex < 10; chapterIndex++) {
      final id = 'chapter-$chapterIndex';
      final blocks = <Block>[];
      for (var blockIndex = 0; blockIndex < 100; blockIndex++) {
        final suffix = (chapterIndex * 100 + blockIndex).toString().padLeft(
          4,
          '0',
        );
        blocks.add(TextBlock(id: 'block-$suffix', text: '${'後' * 996}$suffix'));
      }
      final chapter = Chapter(
        id: id,
        bookId: 'large-book',
        title: '第${chapterIndex + 1}章',
        order: chapterIndex,
        blocks: blocks,
      );
      bodies[id] = chapter;
      chapters.add(chapter.copyWith(blocks: const <Block>[]));
    }
    final now = DateTime.utc(2026, 11, 5);
    _book = Book(
      id: 'large-book',
      meta: BookMeta(title: '长篇测试', author: '测试'),
      chapters: chapters,
      createdAt: now,
      updatedAt: now,
    );
  }

  final Map<String, Chapter> bodies = <String, Chapter>{};
  late Book _book;

  @override
  Future<Book?> loadBook(String bookId) async =>
      bookId == _book.id ? _book : null;

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async =>
      bookId == _book.id ? bodies[chapterId] : null;

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    for (final id in deletedChapterIds) {
      bodies.remove(id);
    }
    for (final chapter in book.chapters) {
      if (dirtyChapterIds.contains(chapter.id)) bodies[chapter.id] = chapter;
    }
    _book = book.copyWith(
      revision: expectedRevision + 1,
      chapters: <Chapter>[
        for (final chapter in book.chapters)
          chapter.copyWith(blocks: const <Block>[]),
      ],
    );
    return _book;
  }
}
