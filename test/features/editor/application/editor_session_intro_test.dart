import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bookId = 'book';
  final now = DateTime.utc(2026);

  EditorSession sessionFor(_IntroStore store) => EditorSession.withStore(
    store: store,
    debounce: const Duration(milliseconds: 800),
  );

  test(
    'open recognizes the intro chapter, fills the description and hides it',
    () async {
      final savedDirty = <Set<String>>[];
      final store = _IntroStore(
        Book(
          id: bookId,
          meta: BookMeta(title: '萌师在上：逆徒别乱来'),
          chapters: const [
            Chapter(id: 'intro', bookId: bookId, title: '前言', order: 0),
            Chapter(id: 'c1', bookId: bookId, title: '第1章 穿越重生', order: 1),
          ],
          createdAt: now,
          updatedAt: now,
        ),
        {
          'intro': const Chapter(
            id: 'intro',
            bookId: bookId,
            title: '前言',
            frontMatter: true,
            order: 0,
            blocks: <Block>[
              TextBlock(id: 'b1', text: '『萌师在上：逆徒别乱来/作者:风与天幕』'),
              TextBlock(id: 'b2', text: '『状态:已完结』'),
              TextBlock(id: 'b3', text: '『内容简介:穿进修仙小说，肯定要和主角抢机缘啊！』'),
              TextBlock(id: 'b4', text: '正文'),
            ],
          ),
          'c1': const Chapter(
            id: 'c1',
            bookId: bookId,
            title: '第1章 穿越重生',
            order: 1,
            blocks: <Block>[TextBlock(id: 'p1', text: '正文开始')],
          ),
        },
        savedDirty,
      );
      final session = sessionFor(store);
      await session.open(bookId);
      expect(session.introChapterId, 'intro');
      expect(session.book!.meta.description, '穿进修仙小说，肯定要和主角抢机缘啊！');
      // The recognized intro chapter never becomes the default chapter.
      expect(session.activeChapterId, 'c1');
      // The auto-filled description persists even without user edits.
      expect(session.dirty, isTrue);
      await session.flush();
      expect(savedDirty.single, <String>{}, reason: '仅元数据变化，无章节块改动');
      expect(store.book.meta.description, '穿进修仙小说，肯定要和主角抢机缘啊！');
      session.dispose();
    },
  );

  test('an existing description is never overridden by recognition', () async {
    final savedDirty = <Set<String>>[];
    final store = _IntroStore(
      Book(
        id: bookId,
        meta: BookMeta(title: '书', description: '作者手填的简介'),
        chapters: const [
          Chapter(id: 'intro', bookId: bookId, title: '前言', order: 0),
          Chapter(id: 'c1', bookId: bookId, title: '第1章', order: 1),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      {
        'intro': const Chapter(
          id: 'intro',
          bookId: bookId,
          title: '前言',
          frontMatter: true,
          order: 0,
          blocks: <Block>[TextBlock(id: 'b1', text: '『内容简介:自动简介』')],
        ),
        'c1': const Chapter(
          id: 'c1',
          bookId: bookId,
          title: '第1章',
          order: 1,
          blocks: <Block>[TextBlock(id: 'p1', text: '正文')],
        ),
      },
      savedDirty,
    );
    final session = sessionFor(store);
    await session.open(bookId);
    expect(session.introChapterId, 'intro');
    expect(session.book!.meta.description, '作者手填的简介');
    expect(session.dirty, isFalse);
    expect(savedDirty, isEmpty);
    session.dispose();
  });

  test(
    'without an intro carrier nothing hides and the default chapter stays',
    () async {
      final savedDirty = <Set<String>>[];
      final store = _IntroStore(
        Book(
          id: bookId,
          meta: BookMeta(title: '书'),
          chapters: const [
            Chapter(id: 'c1', bookId: bookId, title: '第1章 起航', order: 0),
            Chapter(id: 'c2', bookId: bookId, title: '第2章', order: 1),
          ],
          createdAt: now,
          updatedAt: now,
        ),
        {
          'c1': const Chapter(
            id: 'c1',
            bookId: bookId,
            title: '第1章 起航',
            order: 0,
            blocks: <Block>[TextBlock(id: 'p1', text: '正文')],
          ),
          'c2': const Chapter(
            id: 'c2',
            bookId: bookId,
            title: '第2章',
            order: 1,
            blocks: <Block>[TextBlock(id: 'p2', text: '后文')],
          ),
        },
        savedDirty,
      );
      final session = sessionFor(store);
      await session.open(bookId);
      expect(session.introChapterId, isNull);
      expect(session.activeChapterId, 'c1');
      expect(session.dirty, isFalse);
      expect(savedDirty, isEmpty);
      session.dispose();
    },
  );

  test(
    'reparse hides the parsed intro chapter and skips its selection',
    () async {
      final savedDirty = <Set<String>>[];
      final store = _IntroStore(
        Book(
          id: bookId,
          meta: BookMeta(title: '书', author: '原作者'),
          chapters: const [
            Chapter(id: 'a', bookId: bookId, title: '第1章', order: 0),
          ],
          createdAt: now,
          updatedAt: now,
        ),
        {
          'a': const Chapter(
            id: 'a',
            bookId: bookId,
            title: '第1章',
            order: 0,
            blocks: <Block>[TextBlock(id: 'p1', text: '正文')],
          ),
        },
        savedDirty,
      );
      final session = sessionFor(store);
      await session.open(bookId);
      final originalMeta = session.book!.meta;
      const replacement = <Chapter>[
        Chapter(
          id: 'intro',
          bookId: bookId,
          title: '前言',
          frontMatter: true,
          order: 0,
          blocks: <Block>[TextBlock(id: 'b1', text: '『内容简介:自动简介』')],
        ),
        Chapter(
          id: 'new-a',
          bookId: bookId,
          title: '第1章',
          order: 1,
          blocks: <Block>[TextBlock(id: 'np1', text: '新正文')],
        ),
      ];
      session.replaceAllChapters(
        replacement,
        const ParseOptions(encoding: 'utf-8', filterAds: false),
        expectedSaveSeq: session.saveSeq,
      );
      expect(session.introChapterId, 'intro');
      expect(session.activeChapterId, 'new-a');
      // A reparse keeps the book metadata untouched; the description is filled
      // on the next open, exactly like a stored book.
      expect(session.book!.meta, same(originalMeta));
      expect(session.canUndo, isFalse);
      await session.flush();
      session.dispose();
    },
  );
}

class _IntroStore implements EditorBookStore {
  _IntroStore(this.book, this.bodies, this.savedDirty);

  Book book;
  final Map<String, Chapter> bodies;
  final List<Set<String>> savedDirty;

  @override
  Future<Book?> loadBook(String bookId) async =>
      bookId == book.id ? book : null;

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async =>
      bodies[chapterId];

  @override
  Future<Book> saveBook(
    Book next, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    savedDirty.add(Set<String>.of(dirtyChapterIds));
    final chapters = <Chapter>[
      for (final chapter in next.chapters)
        bodies.containsKey(chapter.id) && chapter.blocks.isEmpty
            ? chapter.copyWith(blocks: bodies[chapter.id]!.blocks)
            : chapter,
    ];
    book = next.copyWith(
      chapters: chapters,
      revision: expectedRevision + 1,
      wordCount: next.chapters.fold<int>(
        0,
        (total, chapter) => total + WordCount.ofBlocks(chapter.blocks),
      ),
    );
    return book;
  }
}
