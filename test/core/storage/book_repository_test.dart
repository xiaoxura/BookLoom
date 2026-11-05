import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Block, Book, Chapter;
import 'package:bookloom/core/storage/book_files.dart' show BookFiles;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory support;
  late AppDatabase db;
  late BookRepository repository;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('bookloom-storage-');
    db = AppDatabase.openAt(File('${support.path}/bookloom.db'));
    repository = BookRepository(db, support);
  });

  tearDown(() async {
    await db.close();
    await support.delete(recursive: true);
  });

  test(
    'imports source and assets, hashes bytes, then lazily loads chapters',
    () async {
      final now = DateTime.utc(2026, 11, 4);
      final book = _book('book-a', now, <Chapter>[
        const Chapter(
          id: 'chapter-a',
          bookId: 'book-a',
          title: '正文',
          blocks: <Block>[TextBlock(id: 'block-a', text: '甲 乙')],
        ),
      ]);
      final created = await repository.createBook(
        book,
        source: SourceImport(
          format: 'txt',
          originalName: 'original.txt',
          openRead: () => Stream<List<int>>.value(utf8.encode('甲 乙')),
        ),
        assets: <AssetImport>[
          AssetImport(
            id: 'cover-a',
            kind: 'cover',
            mime: 'image/png',
            extension: 'png',
            openRead: () => Stream<List<int>>.value(<int>[1, 2, 3]),
          ),
        ],
      );
      expect(created.revision, 0);
      expect(created.wordCount, 2);
      expect(created.chapters.single.blocks, isEmpty);
      expect(
        (await repository.loadChapter('book-a', 'chapter-a'))!.blocks,
        <Block>[const TextBlock(id: 'block-a', text: '甲 乙')],
      );
      final source = (await repository.loadSource('book-a'))!;
      expect(source.byteSize, utf8.encode('甲 乙').length);
      expect(
        source.sha256,
        '15b6e61aa2444ea8224bbbfea246baeea63e15f25178ccaef3cd97d7f644a209',
      );
      expect(
        await (await repository.resolveSource(source)).readAsString(),
        '甲 乙',
      );
      expect(await repository.listSummaries(), hasLength(1));
    },
  );

  test(
    'missing source reattaches only matching bytes at the original path',
    () async {
      final now = DateTime.utc(2026, 11, 4);
      await repository.createBook(
        _book('reattach-book', now, const <Chapter>[]),
        source: SourceImport(
          id: 'source-reattach',
          format: 'txt',
          originalName: 'old.txt',
          openRead: () => Stream<List<int>>.value(utf8.encode('原始内容')),
        ),
      );
      final source = (await repository.loadSource('reattach-book'))!;
      final original = await repository.resolveSource(source);
      await original.delete();
      await expectLater(
        repository.reattachMissingSource(
          'reattach-book',
          SourceImport(
            format: 'epub',
            originalName: 'wrong.epub',
            openRead: () => Stream<List<int>>.value(utf8.encode('原始内容')),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.reattachMissingSource(
          'reattach-book',
          SourceImport(
            format: 'txt',
            originalName: 'wrong.txt',
            openRead: () => Stream<List<int>>.value(utf8.encode('另一正文')),
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await original.exists(), isFalse);
      final repaired = await repository.reattachMissingSource(
        'reattach-book',
        SourceImport(
          format: 'txt',
          originalName: 'new-location.txt',
          openRead: () => Stream<List<int>>.value(utf8.encode('原始内容')),
        ),
      );
      expect(repaired.id, source.id);
      expect(repaired.storedPath, source.storedPath);
      expect(repaired.sha256, source.sha256);
      expect(await original.readAsString(), '原始内容');
      expect(
        (await repository.loadSource('reattach-book'))!.originalName,
        'old.txt',
      );
      await expectLater(
        repository.reattachMissingSource(
          'reattach-book',
          SourceImport(
            format: 'txt',
            originalName: 'duplicate.txt',
            openRead: () => Stream<List<int>>.value(utf8.encode('原始内容')),
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await Directory('${support.path}/staging').list().toList(),
        isEmpty,
      );
      await repository.files.writeMarker(
        'reattach-recovery',
        kind: 'reattach_source',
        bookId: 'reattach-book',
        assetId: source.id,
        relativePath: 'source.txt',
        sha256: source.sha256,
      );
      final abandoned = await repository.files.createStaging(
        'reattach-recovery',
      );
      await File('${abandoned.path}/source.txt').writeAsString('partial');
      final restarted = BookRepository(db, support);
      await restarted.listSummaries();
      expect(await original.readAsString(), '原始内容');
      expect(await abandoned.exists(), isFalse);
      expect(
        await File('${support.path}/operations/reattach-recovery.json')
            .exists(),
        isFalse,
      );
    },
  );

  test(
    'dirty chapter save preserves unloaded bodies and rejects stale revision',
    () async {
      final now = DateTime.utc(2026, 11, 4);
      await repository.createBook(
        _book('book-b', now, <Chapter>[
          const Chapter(
            id: 'chapter-b1',
            bookId: 'book-b',
            title: '一',
            blocks: <Block>[TextBlock(id: 'block-b1', text: '甲')],
          ),
          const Chapter(
            id: 'chapter-b2',
            bookId: 'book-b',
            title: '二',
            order: 1,
            blocks: <Block>[TextBlock(id: 'block-b2', text: '乙丙')],
          ),
        ]),
      );
      final structural = (await repository.loadBook('book-b'))!;
      final edited = structural.copyWith(
        chapters: <Chapter>[
          structural.chapters.first.copyWith(
            blocks: const <Block>[TextBlock(id: 'block-new', text: '甲乙丙丁')],
          ),
          structural.chapters.last,
        ],
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      final saved = await repository.saveBook(
        edited,
        expectedRevision: 0,
        dirtyChapterIds: const <String>{'chapter-b1'},
      );
      expect(saved.revision, 1);
      expect(saved.wordCount, 6);
      expect(
        (await repository.loadChapter('book-b', 'chapter-b2'))!.blocks,
        <Block>[const TextBlock(id: 'block-b2', text: '乙丙')],
      );
      await expectLater(
        repository.saveBook(
          edited,
          expectedRevision: 0,
          dirtyChapterIds: const <String>{'chapter-b1'},
        ),
        throwsA(isA<BookConflictException>()),
      );
    },
  );

  test('deleting a volume preserves children moved to the top level', () async {
    final now = DateTime.utc(2026, 11, 4);
    await repository.createBook(
      _book('volume-book', now, const <Chapter>[
        Chapter(id: 'old-volume', bookId: 'volume-book', title: '卷一', level: 1),
        Chapter(
          id: 'kept-child',
          bookId: 'volume-book',
          title: '正文',
          parentId: 'old-volume',
          blocks: <Block>[TextBlock(id: 'kept-text', text: '保留')],
        ),
      ]),
    );
    final structure = (await repository.loadBook('volume-book'))!;
    final saved = await repository.saveBook(
      structure.copyWith(
        chapters: <Chapter>[
          structure.chapters.last.copyWith(clearParent: true),
        ],
      ),
      expectedRevision: 0,
      dirtyChapterIds: const <String>{},
      deletedChapterIds: const <String>{'old-volume'},
    );
    expect(saved.chapters.single.parentId, isNull);
    expect(saved.wordCount, 2);
    expect(
      (await repository.loadChapter('volume-book', 'kept-child'))!.blocks,
      <Block>[const TextBlock(id: 'kept-text', text: '保留')],
    );
  });

  test('loads same-level order as a stable volume and chapter tree', () async {
    final now = DateTime.utc(2026, 11, 4);
    final created = await repository.createBook(
      _book('ordered-book', now, const <Chapter>[
        Chapter(
          id: 'volume-b',
          bookId: 'ordered-book',
          title: '卷二',
          level: 1,
          order: 1,
        ),
        Chapter(
          id: 'child-b',
          bookId: 'ordered-book',
          title: '二章',
          parentId: 'volume-b',
          order: 0,
        ),
        Chapter(
          id: 'child-a',
          bookId: 'ordered-book',
          title: '一章',
          parentId: 'volume-a',
          order: 0,
        ),
        Chapter(
          id: 'volume-a',
          bookId: 'ordered-book',
          title: '卷一',
          level: 1,
          order: 0,
        ),
        Chapter(id: 'top-level', bookId: 'ordered-book', title: '附录', order: 2),
      ]),
    );
    expect(created.chapters.map((chapter) => chapter.id), <String>[
      'volume-a',
      'child-a',
      'volume-b',
      'child-b',
      'top-level',
    ]);
    expect(
      (await repository.loadBook('ordered-book'))!.chapters.map((c) => c.id),
      <String>['volume-a', 'child-a', 'volume-b', 'child-b', 'top-level'],
    );
  });

  test('rejects cross-book image and cover references', () async {
    final now = DateTime.utc(2026, 11, 4);
    await repository.createBook(
      _book('owner', now, const <Chapter>[]),
      assets: <AssetImport>[
        AssetImport(
          id: 'private-image',
          kind: 'image',
          mime: 'image/png',
          extension: 'png',
          openRead: () => Stream<List<int>>.value(<int>[1]),
        ),
      ],
    );
    await expectLater(
      repository.createBook(
        _book('other', now, const <Chapter>[
          Chapter(
            id: 'other-chapter',
            bookId: 'other',
            title: 'c',
            blocks: <Block>[
              ImageBlock(id: 'foreign-image', assetId: 'private-image'),
            ],
          ),
        ]).copyWith(coverAssetId: 'private-image'),
      ),
      throwsArgumentError,
    );
    expect(await repository.loadBook('other'), isNull);
    expect(await repository.loadBook('owner'), isNotNull);
  });

  test('budget and DB failure remove only this import files', () async {
    final now = DateTime.utc(2026, 11, 4);
    await repository.createBook(
      _book('existing', now, const <Chapter>[
        Chapter(
          id: 'shared-block-chapter',
          bookId: 'existing',
          title: 'c',
          blocks: <Block>[TextBlock(id: 'shared-block', text: '甲')],
        ),
      ]),
    );
    await expectLater(
      repository.createBook(
        _book('too-large', now, const <Chapter>[]),
        source: SourceImport(
          format: 'txt',
          originalName: 'big.txt',
          maxBytes: 2,
          openRead: () => Stream<List<int>>.value(<int>[1, 2, 3]),
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      repository.createBook(
        _book('rolled-back', now, const <Chapter>[
          Chapter(
            id: 'new-chapter',
            bookId: 'rolled-back',
            title: 'c',
            blocks: <Block>[TextBlock(id: 'shared-block', text: '乙')],
          ),
        ]),
        source: SourceImport(
          format: 'txt',
          originalName: 'small.txt',
          openRead: () => Stream<List<int>>.value(<int>[1]),
        ),
      ),
      throwsA(anything),
    );
    expect(await repository.loadBook('too-large'), isNull);
    expect(await repository.loadBook('rolled-back'), isNull);
    expect(await Directory('${support.path}/books/existing').exists(), isTrue);
    expect(
      await Directory('${support.path}/books/rolled-back').exists(),
      isFalse,
    );
  });

  test('startup recovery removes only an uncommitted book directory', () async {
    final now = DateTime.utc(2026, 11, 4);
    await repository.createBook(_book('committed', now, const <Chapter>[]));
    await repository.files.ensureRoot();
    final abandoned = Directory('${support.path}/books/abandoned');
    await abandoned.create();
    await File('${abandoned.path}/source.txt').writeAsString('partial');
    await repository.files.writeMarker(
      'stale-operation',
      kind: 'create',
      bookId: 'abandoned',
    );
    final restarted = BookRepository(db, support);
    expect(await restarted.listSummaries(), hasLength(1));
    expect(await abandoned.exists(), isFalse);
    expect(await Directory('${support.path}/books/committed').exists(), isTrue);
    expect(
      await File('${support.path}/operations/stale-operation.json').exists(),
      isFalse,
    );
  });

  test('delete recovery distinguishes precommit and committed books', () async {
    final now = DateTime.utc(2026, 11, 4);
    await repository.createBook(_book('keep-book', now, const <Chapter>[]));
    await repository.createBook(_book('gone-book', now, const <Chapter>[]));
    await repository.files.writeMarker(
      'delete-before-commit',
      kind: 'delete',
      bookId: 'keep-book',
    );
    await repository.files.writeMarker(
      'delete-after-commit',
      kind: 'delete',
      bookId: 'gone-book',
    );
    await (db.delete(
      db.books,
    )..where((table) => table.id.equals('gone-book'))).go();
    final restarted = BookRepository(db, support);
    expect(await restarted.listSummaries(), hasLength(1));
    expect(await Directory('${support.path}/books/keep-book').exists(), isTrue);
    expect(
      await Directory('${support.path}/books/gone-book').exists(),
      isFalse,
    );
    expect(
      await File('${support.path}/operations/delete-before-commit.json')
          .exists(),
      isFalse,
    );
    expect(
      await File('${support.path}/operations/delete-after-commit.json')
          .exists(),
      isFalse,
    );
  });

  test(
    'asset ID conflict removes this book file and recovery uses owner and hash',
    () async {
      final now = DateTime.utc(2026, 11, 4);
      await repository.createBook(
        _book('asset-owner', now, const <Chapter>[]),
        assets: <AssetImport>[
          AssetImport(
            id: 'shared-id',
            kind: 'image',
            mime: 'image/png',
            extension: 'png',
            openRead: () => Stream<List<int>>.value(<int>[1]),
          ),
        ],
      );
      await repository.createBook(_book('asset-other', now, const <Chapter>[]));
      await expectLater(
        repository.addAsset(
          'asset-other',
          AssetImport(
            id: 'shared-id',
            kind: 'image',
            mime: 'image/jpeg',
            extension: 'jpg',
            openRead: () => Stream<List<int>>.value(<int>[2]),
          ),
        ),
        throwsA(anything),
      );
      final orphan = File(
        '${support.path}/books/asset-other/assets/shared-id.jpg',
      );
      expect(await orphan.exists(), isFalse);
      await orphan.parent.create(recursive: true);
      await orphan.writeAsBytes(<int>[2]);
      await repository.files.writeMarker(
        'foreign-asset-recovery',
        kind: 'asset',
        bookId: 'asset-other',
        assetId: 'shared-id',
        relativePath: 'assets/shared-id.jpg',
        sha256: 'wrong-hash',
      );
      final committedAsset = (await repository.loadAssets('asset-owner'))
          .single;
      await repository.files.writeMarker(
        'committed-asset-recovery',
        kind: 'asset',
        bookId: 'asset-owner',
        assetId: committedAsset.id,
        relativePath: 'assets/shared-id.png',
        sha256: committedAsset.sha256,
      );
      final restarted = BookRepository(db, support);
      await restarted.listSummaries();
      expect(await orphan.exists(), isFalse);
      expect(await repository.loadAssets('asset-owner'), hasLength(1));
      expect(
        await File('${support.path}/books/asset-owner/assets/shared-id.png')
            .exists(),
        isTrue,
      );
    },
  );

  test(
    'old cover file is collected only after its reference changes',
    () async {
      final now = DateTime.utc(2026, 11, 4);
      await repository.createBook(
        _book(
          'cover-book',
          now,
          const <Chapter>[],
        ).copyWith(coverAssetId: 'old-cover', coverMode: CoverMode.image),
        assets: <AssetImport>[
          AssetImport(
            id: 'old-cover',
            kind: 'cover',
            mime: 'image/png',
            extension: 'png',
            openRead: () => Stream<List<int>>.value(<int>[1, 2]),
          ),
        ],
      );
      expect(
        await repository.removeUnusedAsset('cover-book', 'old-cover'),
        isFalse,
      );
      final book = (await repository.loadBook('cover-book'))!;
      await repository.saveBook(
        book.copyWith(clearCoverAssetId: true, coverMode: CoverMode.template),
        expectedRevision: 0,
        dirtyChapterIds: const <String>{},
      );
      expect(
        await repository.removeUnusedAsset('cover-book', 'old-cover'),
        isTrue,
      );
      expect(await repository.loadAssets('cover-book'), isEmpty);
      expect(
        await File('${support.path}/books/cover-book/assets/old-cover.png')
            .exists(),
        isFalse,
      );
    },
  );

  test('damaged old marker does not block opening committed books', () async {
    final now = DateTime.utc(2026, 11, 4);
    await repository.createBook(_book('readable', now, const <Chapter>[]));
    await File('${support.path}/operations/damaged.json').writeAsString('{');
    await File('${support.path}/operations/incomplete.tmp').writeAsString('{');
    final restarted = BookRepository(db, support);
    expect(await restarted.listSummaries(), hasLength(1));
    expect(
      await File('${support.path}/operations/damaged.json').exists(),
      isTrue,
    );
    expect(
      await File('${support.path}/operations/incomplete.tmp').exists(),
      isFalse,
    );
  });

  test('rejects path traversal and symlinked book data', () async {
    final now = DateTime.utc(2026, 11, 4);
    await repository.createBook(_book('safe', now, const <Chapter>[]));
    await expectLater(
      repository.files.resolveStoredPath(
        'safe',
        'books/safe/../other/source.txt',
      ),
      throwsArgumentError,
    );
    final outside = await Directory.systemTemp.createTemp('bookloom-outside-');
    addTearDown(() => outside.delete(recursive: true));
    await Link('${support.path}/books/safe/source.txt')
        .create('${outside.path}/target');
    await expectLater(
      repository.files.resolveStoredPath('safe', 'books/safe/source.txt'),
      throwsA(isA<FileSystemException>()),
    );
    final ancestorLink = Link('${support.path}/linked-support');
    await ancestorLink.create(outside.path);
    await expectLater(
      BookFiles(Directory('${ancestorLink.path}/nested')).ensureRoot(),
      throwsA(isA<FileSystemException>()),
    );
    final staging = await repository.files.createStaging('path-probe');
    await expectLater(
      repository.files.stageStream(
        staging: staging,
        id: 'unsafe',
        relative: '../escaped.txt',
        openRead: () => Stream<List<int>>.value(<int>[1]),
        maxBytes: 10,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.files.stageStream(
        staging: outside,
        id: 'unsafe',
        relative: 'escaped.txt',
        openRead: () => Stream<List<int>>.value(<int>[1]),
        maxBytes: 10,
      ),
      throwsArgumentError,
    );
    expect(await File('${support.path}/staging/escaped.txt').exists(), isFalse);
    expect(await File('${outside.path}/escaped.txt').exists(), isFalse);
  });

  test('v1 migration retains settings, cleans orphan references and recounts', () async {
    await db.close();
    final file = File('${support.path}/legacy.db');
    final legacy = _V1Database(file);
    await legacy.customStatement(
      "INSERT INTO settings VALUES ('appearance.themeMode', 'dark')",
    );
    final timestamp = DateTime.utc(2026, 11, 4).millisecondsSinceEpoch ~/ 1000;
    await legacy.customStatement(
      'INSERT INTO books (id,title,cover_asset_id,chapter_count,word_count,created_at,updated_at) '
      "VALUES ('legacy','旧书','missing',99,999,$timestamp,$timestamp)",
    );
    await legacy.customStatement(
      'INSERT INTO books (id,title,cover_asset_id,created_at,updated_at) '
      "VALUES ('covered','有封面','valid-cover',$timestamp,$timestamp)",
    );
    await legacy.customStatement(
      'INSERT INTO assets (id,book_id,kind,mime,stored_path,byte_size,sha256,created_at) '
      "VALUES ('valid-cover','covered','cover','image/png','books/covered/assets/valid-cover.png',3,'valid-hash',$timestamp)",
    );
    await legacy.customStatement(
      "INSERT INTO sources VALUES ('orphan','gone','txt','old.txt','books/gone/source.txt',1,'x',$timestamp)",
    );
    await legacy.customStatement(
      "INSERT INTO sources VALUES ('valid-source','legacy','txt','kept.txt','books/legacy/source.txt',4,'known-hash',$timestamp)",
    );
    await Directory('${support.path}/books/legacy').create(recursive: true);
    await File('${support.path}/books/legacy/source.txt').writeAsString('kept');
    await legacy.customStatement(
      'INSERT INTO chapters (id,book_id,title,sort_order,word_count,created_at,updated_at) '
      "VALUES ('legacy-chapter','legacy','正文',0,999,$timestamp,$timestamp)",
    );
    await legacy.customStatement(
      'INSERT INTO blocks (id,chapter_id,sort_order,kind,text,asset_id,created_at) '
      "VALUES ('legacy-block','legacy-chapter',0,'paragraph','甲 😀','missing',$timestamp)",
    );
    await legacy.customStatement(
      'INSERT INTO blocks (id,chapter_id,sort_order,kind,asset_id,meta_json,created_at) '
      "VALUES ('broken-image','legacy-chapter',1,'image','missing','{\"caption\":\"旧插图\"}',$timestamp)",
    );
    await legacy.close();
    db = AppDatabase.openAt(file);
    repository = BookRepository(db, support);
    final migrated = (await repository.loadBook('legacy'))!;
    expect(migrated.wordCount, 11);
    expect(migrated.chapters.single.frontMatter, isFalse);
    expect(migrated.coverAssetId, isNull);
    expect(migrated.coverMode, CoverMode.template);
    final covered = (await repository.loadBook('covered'))!;
    expect(covered.coverAssetId, 'valid-cover');
    expect(covered.coverMode, CoverMode.image);
    expect(migrated.createdAt, DateTime.utc(2026, 11, 4));
    expect(
      await (db.select(db.settings)).getSingle(),
      isA<Setting>().having((row) => row.value, 'value', 'dark'),
    );
    final source = (await repository.loadSource('legacy'))!;
    expect(source.id, 'valid-source');
    expect(source.sha256, 'known-hash');
    expect(source.createdAt.toUtc(), DateTime.utc(2026, 11, 4));
    expect(
      await (await repository.resolveSource(source)).readAsString(),
      'kept',
    );
    expect(await db.select(db.sources).get(), hasLength(1));
    final blocks = await db.select(db.blocks).get();
    expect(blocks.every((block) => block.assetId == null), isTrue);
    final loaded = (await repository.loadChapter('legacy', 'legacy-chapter'))!;
    expect(loaded.blocks, <Block>[
      const TextBlock(id: 'legacy-block', text: '甲 😀'),
      const TextBlock(id: 'broken-image', text: '[图片缺失] 旧插图'),
    ]);
    await db.delete(db.books).go();
    expect(await db.select(db.chapters).get(), isEmpty);
  });

  test('failed v1 migration rolls back DDL and retries cleanly', () async {
    await db.close();
    final file = File('${support.path}/retry.db');
    final legacy = _V1Database(file);
    final timestamp = DateTime.utc(2026, 11, 4).millisecondsSinceEpoch ~/ 1000;
    await legacy.customStatement(
      "INSERT INTO books (id,title,created_at,updated_at) VALUES ('retry','保留',$timestamp,$timestamp)",
    );
    await legacy.customStatement(
      "INSERT INTO chapters (id,book_id,title,sort_order,created_at,updated_at) VALUES ('retry-chapter','retry','正文',0,$timestamp,$timestamp)",
    );
    await legacy.customStatement(
      "CREATE TRIGGER fail_recount BEFORE UPDATE OF word_count ON chapters BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await legacy.close();

    db = AppDatabase.openAt(file);
    await expectLater(
      db.customSelect('SELECT id FROM books').get(),
      throwsA(anything),
    );
    await db.close();

    final inspect = _V1Database(file);
    final version = await inspect
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 1);
    final columns = await inspect
        .customSelect('PRAGMA table_info(books)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      isNot(contains('revision')),
    );
    expect(await inspect.customSelect('SELECT id FROM sources').get(), isEmpty);
    await inspect.customStatement('DROP TRIGGER fail_recount');
    await inspect.close();

    db = AppDatabase.openAt(file);
    repository = BookRepository(db, support);
    expect((await repository.loadBook('retry'))!.revision, 0);
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();
    db = AppDatabase.openAt(file);
    repository = BookRepository(db, support);
    expect(
      (await repository.loadBook('retry'))!.chapters.single.id,
      'retry-chapter',
    );
    final repairedVersion = await db
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(repairedVersion.read<int>('user_version'), 2);
  });
}

Book _book(String id, DateTime now, List<Chapter> chapters) => Book(
  id: id,
  meta: BookMeta(title: id),
  chapters: chapters,
  createdAt: now,
  updatedAt: now,
);

class _V1Database extends AppDatabase {
  _V1Database(File file) : super(NativeDatabase(file));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final statement in <String>[
        "CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL DEFAULT '', language TEXT NOT NULL DEFAULT 'zh-CN', description TEXT NOT NULL DEFAULT '', series TEXT, publisher TEXT, tags_json TEXT NOT NULL DEFAULT '[]', published_at TEXT, cover_asset_id TEXT, chapter_count INTEGER NOT NULL DEFAULT 0, word_count INTEGER NOT NULL DEFAULT 0, layout_json TEXT NOT NULL DEFAULT '{}', cover_options_json TEXT NOT NULL DEFAULT '{}', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, last_opened_at INTEGER, progress REAL NOT NULL DEFAULT 0)",
        'CREATE TABLE sources (id TEXT PRIMARY KEY, book_id TEXT NOT NULL UNIQUE, format TEXT NOT NULL, original_name TEXT NOT NULL, stored_path TEXT NOT NULL, byte_size INTEGER NOT NULL, sha256 TEXT NOT NULL, created_at INTEGER NOT NULL)',
        'CREATE TABLE chapters (id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE, parent_id TEXT REFERENCES chapters(id) ON DELETE CASCADE, title TEXT NOT NULL, level INTEGER NOT NULL DEFAULT 2, sort_order INTEGER NOT NULL, word_count INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
        "CREATE TABLE blocks (id TEXT PRIMARY KEY, chapter_id TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE, sort_order INTEGER NOT NULL, kind TEXT NOT NULL, text TEXT, asset_id TEXT, meta_json TEXT NOT NULL DEFAULT '{}', created_at INTEGER NOT NULL)",
        'CREATE TABLE assets (id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE, kind TEXT NOT NULL, mime TEXT NOT NULL, stored_path TEXT NOT NULL, width INTEGER, height INTEGER, byte_size INTEGER NOT NULL, sha256 TEXT NOT NULL, created_at INTEGER NOT NULL)',
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      ]) {
        await customStatement(statement);
      }
    },
  );
}
