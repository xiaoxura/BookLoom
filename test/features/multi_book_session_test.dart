import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Block, Book, Chapter;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory support;
  late AppDatabase database;
  late BookRepository repository;
  EditorSession? session;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('bookloom-multi-book-');
    database = AppDatabase.openAt(File('${support.path}/library.sqlite'));
    repository = BookRepository(database, support);
  });

  tearDown(() async {
    session?.dispose();
    session = null;
    await database.close();
    await support.delete(recursive: true);
  });

  test('one session flushes 20 books on switch; restart, rename and delete stay isolated', () async {
    for (var index = 0; index < 20; index++) {
      await _createBook(repository, index);
    }

    session = EditorSession(repository: repository);
    for (var index = 0; index < 20; index++) {
      await session!.open(_bookId(index));
      expect(session!.book!.id, _bookId(index));
      session!.editBookMeta(session!.book!.meta.copyWith(title: '编辑书 $index'));
      session!.editChapterTitle(_chapterId(index), '编辑章节 $index');
      session!.editBlockText(_blockId(index), '保存后的正文 $index');
      expect(session!.dirty, isTrue);
    }
    // Opening the first book also flushes the twentieth without an
    // explicit save call, and verifies the first book survived 19 switches.
    await session!.open(_bookId(0));
    expect(session!.book!.meta.title, '编辑书 0');
    expect(
      (session!.activeChapter!.blocks.single as TextBlock).text,
      '保存后的正文 0',
    );
    await session!.close();
    session = null;

    final renamed = (await repository.loadBook(_bookId(5)))!;
    await repository.renameBook(
      _bookId(5),
      '最终更名',
      expectedRevision: renamed.revision,
    );
    await repository.deleteBook(_bookId(10));

    await database.close();
    database = AppDatabase.openAt(File('${support.path}/library.sqlite'));
    repository = BookRepository(database, support);
    final summaries = await repository.listSummaries();
    expect(summaries, hasLength(19));
    expect(summaries.map((book) => book.id), isNot(contains(_bookId(10))));
    expect(await repository.loadBook(_bookId(10)), isNull);
    expect(
      await Directory('${support.path}/books/${_bookId(10)}').exists(),
      isFalse,
    );

    final allPaths = <String>{};
    for (var index = 0; index < 20; index++) {
      if (index == 10) continue;
      final id = _bookId(index);
      final book = (await repository.loadBook(id))!;
      expect(book.meta.title, index == 5 ? '最终更名' : '编辑书 $index');
      expect(book.meta.author, '作者 $index');
      expect(book.meta.tags, <String>['多书', '$index']);
      expect(book.parseOptions.encoding, 'utf-8');
      expect(book.layout.customCss, 'p { margin: ${index}px; }');
      expect(book.coverOptions.palette, index.isEven ? 'forest' : 'sea');
      expect(book.coverMode, CoverMode.image);
      expect(book.coverAssetId, _coverId(index));
      expect(book.layout.embeddedFontAssetId, _fontId(index));
      expect(book.chapters.single.title, '编辑章节 $index');
      expect(
        (await repository.loadChapter(
          id,
          _chapterId(index),
        ))!.blocks.single.plainText,
        '保存后的正文 $index',
      );

      final source = (await repository.loadSource(id))!;
      expect(source.id, _sourceId(index));
      expect(source.bookId, id);
      expect(source.originalName, '原文-$index.txt');
      expect(source.storedPath, startsWith('books/$id/'));
      expect(source.sha256, sha256.convert(_sourceBytes(index)).toString());
      expect(
        await (await repository.resolveSource(source)).readAsBytes(),
        _sourceBytes(index),
      );
      expect(allPaths.add(source.storedPath), isTrue);

      final assets = await repository.loadAssets(id);
      expect(assets, hasLength(2));
      for (final asset in assets) {
        expect(asset.bookId, id);
        expect(asset.storedPath, startsWith('books/$id/assets/'));
        expect(allPaths.add(asset.storedPath), isTrue);
        final expected = asset.id == _coverId(index)
            ? _coverBytes(index)
            : _fontBytes(index);
        expect(asset.id, anyOf(_coverId(index), _fontId(index)));
        expect(asset.sha256, sha256.convert(expected).toString());
        expect(
          await (await repository.resolveAsset(asset)).readAsBytes(),
          expected,
        );
      }
    }
  });

  test(
    'a failed save keeps the active book dirty until retry permits a switch',
    () async {
      await _createBook(repository, 0);
      await _createBook(repository, 1);
      final store = _FailOnceStore(repository);
      session = EditorSession.withStore(store: store);
      await session!.open(_bookId(0));
      session!.editBlockText(_blockId(0), '尚未提交的正文');
      store.failNextSave = true;

      await expectLater(
        session!.open(_bookId(1)),
        throwsA(isA<StorageFailure>()),
      );
      expect(session!.book!.id, _bookId(0));
      expect(session!.activeChapterId, _chapterId(0));
      expect(session!.activeChapter!.blocks.single.plainText, '尚未提交的正文');
      expect(session!.dirty, isTrue);
      expect(session!.saveError, isA<StorageFailure>());
      expect(
        (await repository.loadChapter(
          _bookId(0),
          _chapterId(0),
        ))!.blocks.single.plainText,
        '初始正文 0',
      );

      await session!.retrySave();
      expect(session!.dirty, isFalse);
      expect(session!.saveError, isNull);
      await session!.open(_bookId(1));
      expect(session!.book!.id, _bookId(1));
      expect(session!.activeChapter!.blocks.single.plainText, '初始正文 1');
      expect(
        (await repository.loadChapter(
          _bookId(0),
          _chapterId(0),
        ))!.blocks.single.plainText,
        '尚未提交的正文',
      );
      await session!.close();
      session = null;
    },
  );
}

class _FailOnceStore implements EditorBookStore {
  _FailOnceStore(this.repository);

  final BookRepository repository;
  bool failNextSave = false;

  @override
  Future<Book?> loadBook(String bookId) => repository.loadBook(bookId);

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) =>
      repository.loadChapter(bookId, chapterId);

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) {
    if (failNextSave) {
      failNextSave = false;
      throw const FileSystemException('Injected save failure');
    }
    return repository.saveBook(
      book,
      expectedRevision: expectedRevision,
      dirtyChapterIds: dirtyChapterIds,
      deletedChapterIds: deletedChapterIds,
    );
  }
}

Future<void> _createBook(BookRepository repository, int index) async {
  final id = _bookId(index);
  final now = DateTime.utc(2026, 11, 5).add(Duration(seconds: index));
  await repository.createBook(
    Book(
      id: id,
      meta: BookMeta(
        title: '原书 $index',
        author: '作者 $index',
        tags: <String>['多书', '$index'],
      ),
      chapters: <Chapter>[
        Chapter(
          id: _chapterId(index),
          bookId: id,
          title: '初始章节 $index',
          blocks: <Block>[TextBlock(id: _blockId(index), text: '初始正文 $index')],
        ),
      ],
      layout: LayoutOptions(
        customCss: 'p { margin: ${index}px; }',
        embeddedFontAssetId: _fontId(index),
      ),
      coverOptions: CoverOptions(palette: index.isEven ? 'forest' : 'sea'),
      parseOptions: const ParseOptions(encoding: 'utf-8'),
      coverMode: CoverMode.image,
      coverAssetId: _coverId(index),
      createdAt: now,
      updatedAt: now,
    ),
    source: SourceImport(
      id: _sourceId(index),
      format: 'txt',
      originalName: '原文-$index.txt',
      openRead: () => Stream<List<int>>.value(_sourceBytes(index)),
    ),
    assets: <AssetImport>[
      AssetImport(
        id: _coverId(index),
        kind: 'cover',
        mime: 'image/png',
        extension: 'png',
        openRead: () => Stream<List<int>>.value(_coverBytes(index)),
      ),
      AssetImport(
        id: _fontId(index),
        kind: 'font',
        mime: 'font/ttf',
        extension: 'ttf',
        openRead: () => Stream<List<int>>.value(_fontBytes(index)),
      ),
    ],
  );
}

String _bookId(int index) => 'multi-book-$index';
String _chapterId(int index) => 'chapter-$index';
String _blockId(int index) => 'block-$index';
String _sourceId(int index) => 'source-$index';
String _coverId(int index) => 'cover-$index';
String _fontId(int index) => 'font-$index';
List<int> _sourceBytes(int index) => utf8.encode('独立原文 $index');
List<int> _coverBytes(int index) => utf8.encode('cover bytes $index');
List<int> _fontBytes(int index) => utf8.encode('font bytes $index');
