import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;

import '../model/block.dart' as model;
import '../model/book.dart' as model;
import '../model/chapter.dart' as model;
import '../model/cover_options.dart';
import '../model/layout_options.dart';
import '../model/metadata.dart';
import '../model/parse_options.dart';
import '../text/word_count.dart';
import 'app_database.dart';
import 'book_files.dart';

export 'book_files.dart'
    show AssetImport, OpenInputStream, SourceImport, StoredFile;

class BookConflictException implements Exception {
  const BookConflictException(this.bookId);
  final String bookId;

  @override
  String toString() => 'Book $bookId has a newer revision';
}

class BookSummary {
  const BookSummary({
    required this.id,
    required this.title,
    required this.author,
    required this.chapterCount,
    required this.wordCount,
    required this.updatedAt,
    required this.revision,
    required this.coverMode,
    required this.coverOptions,
    this.coverAssetId,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String author;
  final int chapterCount;
  final int wordCount;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final int revision;
  final model.CoverMode coverMode;
  final CoverOptions coverOptions;
  final String? coverAssetId;
}

/// Stores one current copy of each book. Bodies are loaded only by
/// [loadChapter]; [loadBook] reads metadata and the structural chapter list.
class BookRepository {
  BookRepository(this.db, Directory appSupportDirectory)
    : files = BookFiles(appSupportDirectory);

  final AppDatabase db;
  final BookFiles files;
  late final Future<void> _ready = recoverPendingOperations();

  Future<List<BookSummary>> listSummaries({String search = ''}) async {
    await _ready;
    final query = db.select(db.books)
      ..orderBy(<drift.OrderingTerm Function($BooksTable)>[
        (table) => drift.OrderingTerm.desc(table.updatedAt),
      ]);
    if (search.trim().isNotEmpty) {
      final pattern = '%${_escapeLike(search.trim())}%';
      query.where(
        (table) =>
            table.title.like(pattern, escapeChar: r'\') |
            table.author.like(pattern, escapeChar: r'\'),
      );
    }
    return (await query.get()).map(_summary).toList(growable: false);
  }

  Stream<List<BookSummary>> watchSummaries({String search = ''}) async* {
    await _ready;
    final query = db.select(db.books)
      ..orderBy(<drift.OrderingTerm Function($BooksTable)>[
        (table) => drift.OrderingTerm.desc(table.updatedAt),
      ]);
    if (search.trim().isNotEmpty) {
      final pattern = '%${_escapeLike(search.trim())}%';
      query.where(
        (table) =>
            table.title.like(pattern, escapeChar: r'\') |
            table.author.like(pattern, escapeChar: r'\'),
      );
    }
    yield* query.watch().map(
      (rows) => rows.map(_summary).toList(growable: false),
    );
  }

  Future<model.Book?> loadBook(String bookId) async {
    await _ready;
    files.checkId(bookId);
    return db.transaction(() async {
      final row = await (db.select(
        db.books,
      )..where((table) => table.id.equals(bookId))).getSingleOrNull();
      if (row == null) return null;
      final chapters = await (db.select(
        db.chapters,
      )..where((table) => table.bookId.equals(bookId))).get();
      return _fromRows(row, _orderedChapters(chapters));
    });
  }

  Future<model.Chapter?> loadChapter(String bookId, String chapterId) async {
    await _ready;
    files.checkId(bookId);
    files.checkId(chapterId);
    return db.transaction(() async {
      final chapter =
          await (db.select(db.chapters)..where(
                (table) =>
                    table.bookId.equals(bookId) & table.id.equals(chapterId),
              ))
              .getSingleOrNull();
      if (chapter == null) return null;
      final rows =
          await (db.select(db.blocks)
                ..where((table) => table.chapterId.equals(chapterId))
                ..orderBy(<drift.OrderingTerm Function($BlocksTable)>[
                  (table) => drift.OrderingTerm.asc(table.sortOrder),
                ]))
              .get();
      return _chapter(chapter, rows.map(_block).toList(growable: false));
    });
  }

  Future<Source?> loadSource(String bookId) async {
    await _ready;
    files.checkId(bookId);
    return (db.select(
      db.sources,
    )..where((table) => table.bookId.equals(bookId))).getSingleOrNull();
  }

  Future<List<Asset>> loadAssets(String bookId) async {
    await _ready;
    files.checkId(bookId);
    return (db.select(
      db.assets,
    )..where((table) => table.bookId.equals(bookId))).get();
  }

  Future<File> resolveSource(Source source) =>
      files.resolveStoredPath(source.bookId, source.storedPath);

  /// Repairs a missing app-owned source with the exact original bytes. The
  /// source row, ID and relative path are unchanged, so reparsing continues to
  /// use the immutable original rather than the picked file's external path.
  Future<StoredFile> reattachMissingSource(
    String bookId,
    SourceImport input,
  ) async {
    await _ready;
    files.checkId(bookId);
    final source = await loadSource(bookId);
    if (source == null) throw StateError('Book has no source to reattach');
    if (input.format != source.format ||
        (input.id != null && input.id != source.id)) {
      throw ArgumentError('Selected source format or ID does not match');
    }
    final bookRelative = files.bookRelativePath(bookId);
    final relative = p.relative(source.storedPath, from: bookRelative);
    if (p.dirname(relative) != '.' ||
        !RegExp(r'^source(?:-[A-Za-z0-9_-]+)?\.(?:txt|epub|docx)$')
            .hasMatch(relative) ||
        p.extension(relative) != '.${source.format}') {
      throw const FormatException('Unsafe stored source path');
    }
    final destination = await files.resolveStoredPath(
      bookId,
      source.storedPath,
    );
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Original source file is already present');
    }
    if (source.byteSize < 0 || input.maxBytes < source.byteSize) {
      throw ArgumentError('Selected source exceeds its approved byte budget');
    }
    final operationId = files.newId();
    await files.writeMarker(
      operationId,
      kind: 'reattach_source',
      bookId: bookId,
      assetId: source.id,
      relativePath: relative,
      sha256: source.sha256,
    );
    try {
      final staging = await files.createStaging(operationId);
      final staged = await files.stageStream(
        staging: staging,
        id: source.id,
        relative: relative,
        openRead: input.openRead,
        maxBytes: input.maxBytes,
      );
      if (staged.byteSize != source.byteSize ||
          staged.sha256 != source.sha256) {
        throw const FormatException(
          'Selected file does not match the original source',
        );
      }
      final current = await loadSource(bookId);
      if (current == null ||
          current.id != source.id ||
          current.storedPath != source.storedPath ||
          current.sha256 != source.sha256 ||
          current.byteSize != source.byteSize) {
        throw StateError('Source changed while reattaching');
      }
      await files.moveStagedAsset(operationId, bookId, relative);
      try {
        await files.deleteStaging(operationId);
        await files.removeMarker(operationId);
      } on FileSystemException {
        // The source row already refers to the moved file. Startup recovery
        // will clean staging and the durable operation marker.
      }
      return StoredFile(
        id: source.id,
        storedPath: source.storedPath,
        byteSize: source.byteSize,
        sha256: source.sha256,
      );
    } catch (_) {
      await files.deleteStaging(operationId);
      await files.removeMarker(operationId);
      rethrow;
    }
  }

  Future<File> resolveAsset(Asset asset) =>
      files.resolveStoredPath(asset.bookId, asset.storedPath);

  Future<model.Book> createBook(
    model.Book book, {
    SourceImport? source,
    List<AssetImport> assets = const <AssetImport>[],
  }) async {
    await _ready;
    files.checkId(book.id);
    _validateStructure(book);
    final operationId = files.newId();
    final stagedAssets = <(AssetImport, StoredFile)>[];
    StoredFile? stagedSource;
    var moved = false;
    await files.ensureRoot();
    await files.writeMarker(operationId, kind: 'create', bookId: book.id);
    try {
      await files.createStaging(operationId);
      if (source != null) {
        if (!const <String>{'txt', 'epub', 'docx'}.contains(source.format)) {
          throw ArgumentError.value(source.format, 'source.format');
        }
        final id = source.id ?? files.newId();
        stagedSource = await files.stageStream(
          staging: Directory(
            p.join(files.supportDirectory.path, 'staging', operationId),
          ),
          id: id,
          relative: 'source.${source.format}',
          openRead: source.openRead,
          maxBytes: source.maxBytes,
        );
      }
      for (final input in assets) {
        final id = input.id ?? files.newId();
        _validateAssetImport(input, id);
        final staged = await files.stageStream(
          staging: Directory(
            p.join(files.supportDirectory.path, 'staging', operationId),
          ),
          id: id,
          relative: p.join('assets', '$id.${input.extension}'),
          openRead: input.openRead,
          maxBytes: input.maxBytes,
        );
        stagedAssets.add((input, staged));
      }
      await files.moveStagedBook(operationId, book.id);
      moved = true;
      await db.transaction(() async {
        final availableAssets = <String>{
          for (final (_, staged) in stagedAssets) staged.id,
        };
        _validateResourceRefs(book, availableAssets);
        await db.into(db.books).insert(_bookInsert(book, revision: 0));
        for (final (input, staged) in stagedAssets) {
          await db
              .into(db.assets)
              .insert(_assetInsert(book.id, input, staged, book.createdAt));
        }
        if (source != null && stagedSource != null) {
          await db
              .into(db.sources)
              .insert(
                SourcesCompanion.insert(
                  id: stagedSource.id,
                  bookId: book.id,
                  format: source.format,
                  originalName: source.originalName,
                  storedPath: files.storedPathFor(
                    book.id,
                    stagedSource.storedPath,
                  ),
                  byteSize: stagedSource.byteSize,
                  sha256: stagedSource.sha256,
                  createdAt: book.createdAt.toUtc(),
                ),
              );
        }
        final insertOrder = [...book.chapters]
          ..sort((a, b) => a.level.compareTo(b.level));
        for (final chapter in insertOrder) {
          await db
              .into(db.chapters)
              .insert(_chapterInsert(chapter, book.createdAt));
          await _replaceBlocks(chapter);
        }
      });
      try {
        await files.removeMarker(operationId);
      } on FileSystemException {
        // Committed data is usable; startup recovery will remove the marker.
      }
      return book.copyWith(
        chapters: <model.Chapter>[
          for (final chapter in _orderedTree<model.Chapter>(
            book.chapters,
            idOf: (chapter) => chapter.id,
            parentOf: (chapter) => chapter.parentId,
            orderOf: (chapter) => chapter.order,
          ))
            chapter.copyWith(blocks: const <model.Block>[]),
        ],
        revision: 0,
        wordCount: _countBook(book),
      );
    } catch (_) {
      if (moved) {
        final exists = await (db.select(
          db.books,
        )..where((table) => table.id.equals(book.id))).getSingleOrNull();
        if (exists == null) await files.deleteBookDirectory(book.id);
      }
      await files.deleteStaging(operationId);
      await files.removeMarker(operationId);
      rethrow;
    }
  }

  /// Replaces blocks only for [dirtyChapterIds], then updates summary counts
  /// by the changed chapters' deltas in the same SQLite transaction.
  Future<model.Book> saveBook(
    model.Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    await _ready;
    files.checkId(book.id);
    _validateStructure(book);
    final chapterById = <String, model.Chapter>{
      for (final chapter in book.chapters) chapter.id: chapter,
    };
    if (!dirtyChapterIds.every(chapterById.containsKey) ||
        chapterById.keys.any(deletedChapterIds.contains)) {
      throw ArgumentError(
        'Dirty/deleted chapter IDs conflict with book structure',
      );
    }
    var savedWordCount = 0;
    await db.transaction(() async {
      final existingBook = await (db.select(
        db.books,
      )..where((table) => table.id.equals(book.id))).getSingleOrNull();
      if (existingBook == null) throw StateError('Book does not exist');
      if (existingBook.revision != expectedRevision) {
        throw BookConflictException(book.id);
      }
      final availableAssets =
          (await (db.select(
                db.assets,
              )..where((table) => table.bookId.equals(book.id))).get())
              .map((asset) => asset.id)
              .toSet();
      _validateResourceRefs(
        book,
        availableAssets,
        dirtyChapterIds: dirtyChapterIds,
      );
      final existingChapters = await (db.select(
        db.chapters,
      )..where((table) => table.bookId.equals(book.id))).get();
      final oldById = <String, Chapter>{
        for (final chapter in existingChapters) chapter.id: chapter,
      };
      if (!deletedChapterIds.every(oldById.containsKey) ||
          oldById.keys.any(
            (id) =>
                !chapterById.containsKey(id) && !deletedChapterIds.contains(id),
          )) {
        throw ArgumentError('Every removed chapter must be listed as deleted');
      }
      for (final chapter in book.chapters) {
        if (!oldById.containsKey(chapter.id) &&
            !dirtyChapterIds.contains(chapter.id)) {
          throw ArgumentError('New chapter must be dirty: ${chapter.id}');
        }
      }
      // A retained child must be detached before its old volume is deleted:
      // the v1 FK cascades through parent_id. Insert new volumes first so a
      // later reparent to a new volume has a valid target.
      final insertedVolumes = <String>{};
      for (final chapter in book.chapters) {
        if (oldById[chapter.id] == null && chapter.level == 1) {
          await db
              .into(db.chapters)
              .insert(_chapterInsert(chapter, book.updatedAt));
          insertedVolumes.add(chapter.id);
        }
      }
      for (final chapter in book.chapters) {
        if (deletedChapterIds.contains(oldById[chapter.id]?.parentId)) {
          await (db.update(db.chapters)
                ..where((table) => table.id.equals(chapter.id)))
              .write(const ChaptersCompanion(parentId: drift.Value(null)));
        }
      }
      var delta = 0;
      for (final id in deletedChapterIds) {
        final old = oldById[id]!;
        delta -= old.wordCount;
        await (db.delete(
          db.chapters,
        )..where((table) => table.id.equals(id))).go();
      }
      for (final chapter in book.chapters) {
        final old = oldById[chapter.id];
        final dirty = dirtyChapterIds.contains(chapter.id);
        final count = dirty
            ? WordCount.ofBlocks(chapter.blocks)
            : old!.wordCount;
        if (old == null) {
          if (!insertedVolumes.contains(chapter.id)) {
            await db
                .into(db.chapters)
                .insert(_chapterInsert(chapter, book.updatedAt));
          }
        } else if (old.title != chapter.title ||
            old.parentId != chapter.parentId ||
            old.level != chapter.level ||
            old.sortOrder != chapter.order ||
            old.frontMatter != chapter.frontMatter ||
            dirty) {
          await (db.update(
            db.chapters,
          )..where((table) => table.id.equals(chapter.id))).write(
            ChaptersCompanion(
              title: drift.Value(chapter.title),
              parentId: drift.Value(chapter.parentId),
              level: drift.Value(chapter.level),
              sortOrder: drift.Value(chapter.order),
              frontMatter: drift.Value(chapter.frontMatter),
              wordCount: drift.Value(count),
              updatedAt: drift.Value(book.updatedAt.toUtc()),
            ),
          );
        }
        if (dirty) {
          delta += count - (old?.wordCount ?? 0);
          await _replaceBlocks(chapter);
        }
      }
      savedWordCount = existingBook.wordCount + delta;
      final updated =
          await (db.update(db.books)..where(
                (table) =>
                    table.id.equals(book.id) &
                    table.revision.equals(expectedRevision),
              ))
              .write(
                _bookUpdate(
                  book,
                  revision: expectedRevision + 1,
                  chapterCount: book.chapters.length,
                  wordCount: savedWordCount,
                ),
              );
      if (updated != 1) throw BookConflictException(book.id);
    });
    return book.copyWith(
      revision: expectedRevision + 1,
      wordCount: savedWordCount,
      updatedAt: book.updatedAt.toUtc(),
    );
  }

  Future<model.Book> renameBook(
    String bookId,
    String title, {
    required int expectedRevision,
  }) async {
    final book = await loadBook(bookId);
    if (book == null) throw StateError('Book does not exist');
    return saveBook(
      book.copyWith(
        meta: book.meta.copyWith(title: title),
        updatedAt: DateTime.now().toUtc(),
      ),
      expectedRevision: expectedRevision,
      dirtyChapterIds: const <String>{},
    );
  }

  Future<void> openBook(String bookId) async {
    await _ready;
    files.checkId(bookId);
    final changed =
        await (db.update(
          db.books,
        )..where((table) => table.id.equals(bookId))).write(
          BooksCompanion(lastOpenedAt: drift.Value(DateTime.now().toUtc())),
        );
    if (changed == 0) throw StateError('Book does not exist');
  }

  Future<void> deleteBook(String bookId) async {
    await _ready;
    files.checkId(bookId);
    final operationId = files.newId();
    final existing = await (db.select(
      db.books,
    )..where((table) => table.id.equals(bookId))).getSingleOrNull();
    if (existing == null) return;
    await files.writeMarker(operationId, kind: 'delete', bookId: bookId);
    try {
      await db.transaction(() async {
        await (db.delete(
          db.books,
        )..where((table) => table.id.equals(bookId))).go();
      });
      await files.deleteBookDirectory(bookId);
      await files.removeMarker(operationId);
    } catch (_) {
      // The marker allows startup recovery to finish only a committed delete.
      rethrow;
    }
  }

  Future<StoredFile> addAsset(String bookId, AssetImport input) async {
    await _ready;
    files.checkId(bookId);
    final id = input.id ?? files.newId();
    _validateAssetImport(input, id);
    final operationId = files.newId();
    await files.ensureRoot();
    await files.writeMarker(
      operationId,
      kind: 'stage_asset',
      bookId: bookId,
      assetId: id,
    );
    final relative = p.join('assets', '$id.${input.extension}');
    final finalMarkerId = '$operationId-final';
    var moved = false;
    try {
      final staging = await files.createStaging(operationId);
      final staged = await files.stageStream(
        staging: staging,
        id: id,
        relative: relative,
        openRead: input.openRead,
        maxBytes: input.maxBytes,
      );
      await files.writeMarker(
        finalMarkerId,
        kind: 'asset',
        bookId: bookId,
        assetId: id,
        relativePath: relative,
        sha256: staged.sha256,
      );
      await files.moveStagedAsset(operationId, bookId, relative);
      moved = true;
      await db.transaction(() async {
        final book = await (db.select(
          db.books,
        )..where((table) => table.id.equals(bookId))).getSingleOrNull();
        if (book == null) throw StateError('Book does not exist');
        await db
            .into(db.assets)
            .insert(
              _assetInsert(bookId, input, staged, DateTime.now().toUtc()),
            );
      });
      try {
        await files.deleteStaging(operationId);
        await files.removeMarker(finalMarkerId);
        await files.removeMarker(operationId);
      } on FileSystemException {
        // DB commit succeeded; markers allow later cleanup.
      }
      return StoredFile(
        id: id,
        storedPath: files.storedPathFor(bookId, relative),
        byteSize: staged.byteSize,
        sha256: staged.sha256,
      );
    } catch (_) {
      if (moved) {
        // moveStagedAsset only succeeds for a previously absent path. The
        // transaction failed, so this exact file belongs to this operation.
        await files.deleteAssetFile(bookId, relative);
      }
      await files.deleteStaging(operationId);
      await files.removeMarker(finalMarkerId);
      await files.removeMarker(operationId);
      rethrow;
    }
  }

  /// Removes an asset only after all current book references have moved away.
  /// A marker finishes file cleanup if SQLite committed before a crash.
  Future<bool> removeUnusedAsset(String bookId, String assetId) async {
    await _ready;
    files.checkId(bookId);
    files.checkId(assetId);
    final operationId = files.newId();
    final removed = await db.transaction(() async {
      final asset =
          await (db.select(db.assets)..where(
                (table) =>
                    table.id.equals(assetId) & table.bookId.equals(bookId),
              ))
              .getSingleOrNull();
      if (asset == null) return null;
      final relative = p.relative(
        asset.storedPath,
        from: files.bookRelativePath(bookId),
      );
      await files.resolveStoredPath(bookId, asset.storedPath);
      if (p.dirname(relative) != 'assets' ||
          !p.basename(relative).startsWith('$assetId.')) {
        throw const FormatException('Unexpected asset path');
      }
      final cover =
          await (db.select(db.books)
                ..where((table) => table.coverAssetId.equals(assetId))
                ..limit(1))
              .getSingleOrNull();
      final block =
          await (db.select(db.blocks)
                ..where((table) => table.assetId.equals(assetId))
                ..limit(1))
              .getSingleOrNull();
      final books = await db.select(db.books).get();
      final fontReferenced = books.any(
        (book) => book.layoutJson.contains(assetId),
      );
      if (cover != null || block != null || fontReferenced) return null;
      await files.writeMarker(
        operationId,
        kind: 'delete_asset',
        bookId: bookId,
        assetId: assetId,
        relativePath: relative,
        sha256: asset.sha256,
      );
      await (db.delete(db.assets)..where(
            (table) => table.id.equals(assetId) & table.bookId.equals(bookId),
          ))
          .go();
      return relative;
    });
    if (removed == null) {
      await files.removeMarker(operationId);
      return false;
    }
    try {
      await files.deleteAssetFile(bookId, removed);
      await files.removeMarker(operationId);
    } on FileSystemException {
      // The committed deletion is visible; recovery will retry file cleanup.
    }
    return true;
  }

  /// Runs on first repository access, before exposing any books to callers.
  Future<void> recoverPendingOperations() async {
    for (final (operationId, marker) in await files.readMarkers()) {
      try {
        final kind = marker['kind'];
        final bookId = marker['bookId'];
        if (bookId is! String || kind is! String) {
          throw const FormatException('Bad operation marker');
        }
        files.checkId(bookId);
        if (kind == 'create' || kind == 'delete') {
          final book = await (db.select(
            db.books,
          )..where((table) => table.id.equals(bookId))).getSingleOrNull();
          if (book == null) await files.deleteBookDirectory(bookId);
        } else if (kind == 'stage_asset') {
          // Only staging was touched; no final asset move occurred yet.
        } else if (kind == 'reattach_source') {
          final sourceId = marker['assetId'];
          final relative = marker['relativePath'];
          final digest = marker['sha256'];
          if (sourceId is! String ||
              relative is! String ||
              digest is! String ||
              p.dirname(relative) != '.' ||
              !RegExp(r'^source(?:-[A-Za-z0-9_-]+)?\.(?:txt|epub|docx)$')
                  .hasMatch(relative)) {
            continue;
          }
          files.checkId(sourceId);
          final storedPath = files.storedPathFor(bookId, relative);
          final currentSource =
              await (db.select(db.sources)
                    ..where((table) => table.storedPath.equals(storedPath))
                    ..limit(1))
                  .getSingleOrNull();
          final currentAsset =
              await (db.select(db.assets)
                    ..where((table) => table.storedPath.equals(storedPath))
                    ..limit(1))
                  .getSingleOrNull();
          if (currentSource == null && currentAsset == null) {
            await files.deleteAssetFile(bookId, relative);
          }
        } else if (kind == 'asset') {
          final assetId = marker['assetId'];
          final relative = marker['relativePath'];
          final digest = marker['sha256'];
          if (assetId is! String || relative is! String || digest is! String) {
            // Retain an old/incomplete marker rather than guessing a path.
            continue;
          }
          files.checkId(assetId);
          if (p.dirname(relative) != 'assets' ||
              !p.basename(relative).startsWith('$assetId.')) {
            continue;
          }
          final asset = await (db.select(
            db.assets,
          )..where((table) => table.id.equals(assetId))).getSingleOrNull();
          final storedPath = files.storedPathFor(bookId, relative);
          if (asset == null ||
              asset.bookId != bookId ||
              asset.storedPath != storedPath ||
              asset.sha256 != digest) {
            await files.deleteAssetFile(bookId, relative);
          }
        } else if (kind == 'delete_asset') {
          final assetId = marker['assetId'];
          final relative = marker['relativePath'];
          if (assetId is! String || relative is! String) continue;
          files.checkId(assetId);
          if (p.dirname(relative) != 'assets' ||
              !p.basename(relative).startsWith('$assetId.')) {
            continue;
          }
          final asset =
              await (db.select(db.assets)..where(
                    (table) =>
                        table.id.equals(assetId) & table.bookId.equals(bookId),
                  ))
                  .getSingleOrNull();
          final oldPath = files.storedPathFor(bookId, relative);
          // A reused ID may now point to a different filename. Keep a file
          // whenever a current row points at this exact path, even if its hash
          // changed, to avoid removing the replacement's content.
          if (asset == null || asset.storedPath != oldPath) {
            await files.deleteAssetFile(bookId, relative);
          }
        } else if (kind == 'restore') {
          final paths = marker['paths'];
          if (paths is! List || paths.length > 100000) continue;
          for (final value in paths) {
            if (value is! String || !_restoreManagedPath(value)) {
              throw const FormatException('Unsafe restore marker path');
            }
            final storedPath = files.storedPathFor(bookId, value);
            final source =
                await (db.select(db.sources)
                      ..where((table) => table.storedPath.equals(storedPath))
                      ..limit(1))
                    .getSingleOrNull();
            final asset =
                await (db.select(db.assets)
                      ..where((table) => table.storedPath.equals(storedPath))
                      ..limit(1))
                    .getSingleOrNull();
            if (source == null && asset == null) {
              await files.deleteAssetFile(bookId, value);
            }
          }
          final book = await (db.select(
            db.books,
          )..where((table) => table.id.equals(bookId))).getSingleOrNull();
          if (book == null) await files.deleteBookDirectory(bookId);
        } else {
          throw FormatException('Unknown operation kind: $kind');
        }
        await files.deleteStaging(operationId);
        await files.removeMarker(operationId);
      } on FormatException {
        // Preserve malformed markers for diagnosis; do not block the shelf.
      } on ArgumentError {
        // A tampered path must never be used for cleanup.
      } on FileSystemException {
        // Keep the marker so the next startup can retry cleanup.
      }
    }
  }

  static String _escapeLike(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static bool _restoreManagedPath(String relative) {
    if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
      return false;
    }
    final name = p.basename(relative);
    if (p.dirname(relative) == 'assets' &&
        RegExp(r'^[A-Za-z0-9_-]+\.[a-z0-9]{1,8}$').hasMatch(name)) {
      return true;
    }
    return p.dirname(relative) == '.' &&
        RegExp(r'^source(?:-[A-Za-z0-9_-]+)?\.(?:txt|epub|docx)$')
            .hasMatch(name);
  }

  BookSummary _summary(Book row) => BookSummary(
    id: row.id,
    title: row.title,
    author: row.author,
    chapterCount: row.chapterCount,
    wordCount: row.wordCount,
    updatedAt: row.updatedAt.toUtc(),
    lastOpenedAt: row.lastOpenedAt?.toUtc(),
    revision: row.revision,
    coverMode: model.CoverMode.fromWire(row.coverMode),
    coverOptions: CoverOptions.fromJson(_jsonMap(row.coverOptionsJson)),
    coverAssetId: row.coverAssetId,
  );

  model.Book _fromRows(Book row, List<Chapter> chapters) => model.Book(
    id: row.id,
    meta: BookMeta.fromJson(<String, Object?>{
      'title': row.title,
      'author': row.author,
      'language': row.language,
      'description': row.description,
      'series': row.series,
      'publisher': row.publisher,
      'tags': jsonDecode(row.tagsJson),
      'publishedAt': row.publishedAt,
    }),
    chapters: chapters.map(_chapter).toList(growable: false),
    coverOptions: CoverOptions.fromJson(_jsonMap(row.coverOptionsJson)),
    layout: LayoutOptions.fromJson(_jsonMap(row.layoutJson)),
    parseOptions: ParseOptions.fromJson(_jsonMap(row.parseOptionsJson)),
    coverMode: model.CoverMode.fromWire(row.coverMode),
    coverAssetId: row.coverAssetId,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    lastOpenedAt: row.lastOpenedAt?.toUtc(),
    wordCount: row.wordCount,
    revision: row.revision,
  );

  static Map<String, Object?> _jsonMap(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }
    return value.cast<String, Object?>();
  }

  static List<Chapter> _orderedChapters(List<Chapter> chapters) =>
      _orderedTree<Chapter>(
        chapters,
        idOf: (chapter) => chapter.id,
        parentOf: (chapter) => chapter.parentId,
        orderOf: (chapter) => chapter.sortOrder,
      );

  static List<T> _orderedTree<T>(
    List<T> items, {
    required String Function(T) idOf,
    required String? Function(T) parentOf,
    required int Function(T) orderOf,
  }) {
    final byId = <String, T>{for (final item in items) idOf(item): item};
    final children = <String, List<T>>{};
    final roots = <T>[];
    for (final item in items) {
      final parentId = parentOf(item);
      if (parentId == null || !byId.containsKey(parentId)) {
        roots.add(item);
      } else {
        children.putIfAbsent(parentId, () => <T>[]).add(item);
      }
    }
    int compare(T a, T b) {
      final byOrder = orderOf(a).compareTo(orderOf(b));
      return byOrder != 0 ? byOrder : idOf(a).compareTo(idOf(b));
    }

    roots.sort(compare);
    for (final siblings in children.values) {
      siblings.sort(compare);
    }
    final ordered = <T>[];
    final seen = <String>{};
    void append(T item) {
      if (!seen.add(idOf(item))) return;
      ordered.add(item);
      for (final child in children[idOf(item)] ?? <T>[]) {
        append(child);
      }
    }

    for (final root in roots) {
      append(root);
    }
    // Preserve damaged legacy rows too; editing can then repair them.
    for (final item in items) {
      append(item);
    }
    return ordered;
  }

  model.Chapter _chapter(Chapter row, [List<model.Block> blocks = const []]) =>
      model.Chapter(
        id: row.id,
        bookId: row.bookId,
        title: row.title,
        parentId: row.parentId,
        level: row.level,
        order: row.sortOrder,
        frontMatter: row.frontMatter,
        blocks: blocks,
      );

  model.Block _block(Block row) => switch (row.kind) {
    'paragraph' => model.TextBlock(id: row.id, text: row.content ?? ''),
    'image' => model.ImageBlock(
      id: row.id,
      assetId:
          row.assetId ??
          (throw const FormatException('Image block has no asset')),
      caption: _jsonMap(row.metaJson)['caption'] as String?,
      alt: _jsonMap(row.metaJson)['alt'] as String? ?? '',
    ),
    'footnote' => model.FootnoteBlock(
      id: row.id,
      text: row.content ?? '',
      marker: _jsonMap(row.metaJson)['marker'] as String?,
    ),
    'divider' => model.DividerBlock(id: row.id),
    _ => throw FormatException('Unknown block kind: ${row.kind}'),
  };

  BooksCompanion _bookInsert(model.Book book, {required int revision}) =>
      BooksCompanion.insert(
        id: book.id,
        title: book.meta.title,
        author: drift.Value(book.meta.author),
        language: drift.Value(book.meta.language),
        description: drift.Value(book.meta.description),
        series: drift.Value(book.meta.series),
        publisher: drift.Value(book.meta.publisher),
        tagsJson: drift.Value(jsonEncode(book.meta.tags)),
        publishedAt: drift.Value(_publishedAt(book.meta)),
        coverAssetId: drift.Value(book.coverAssetId),
        coverMode: drift.Value(book.coverMode.wire),
        parseOptionsJson: drift.Value(jsonEncode(book.parseOptions.toJson())),
        revision: drift.Value(revision),
        chapterCount: drift.Value(book.chapters.length),
        wordCount: drift.Value(_countBook(book)),
        layoutJson: drift.Value(jsonEncode(book.layout.toJson())),
        coverOptionsJson: drift.Value(jsonEncode(book.coverOptions.toJson())),
        createdAt: book.createdAt.toUtc(),
        updatedAt: book.updatedAt.toUtc(),
        lastOpenedAt: drift.Value(book.lastOpenedAt?.toUtc()),
      );

  BooksCompanion _bookUpdate(
    model.Book book, {
    required int revision,
    required int chapterCount,
    required int wordCount,
  }) => BooksCompanion(
    title: drift.Value(book.meta.title),
    author: drift.Value(book.meta.author),
    language: drift.Value(book.meta.language),
    description: drift.Value(book.meta.description),
    series: drift.Value(book.meta.series),
    publisher: drift.Value(book.meta.publisher),
    tagsJson: drift.Value(jsonEncode(book.meta.tags)),
    publishedAt: drift.Value(_publishedAt(book.meta)),
    coverAssetId: drift.Value(book.coverAssetId),
    coverMode: drift.Value(book.coverMode.wire),
    parseOptionsJson: drift.Value(jsonEncode(book.parseOptions.toJson())),
    revision: drift.Value(revision),
    chapterCount: drift.Value(chapterCount),
    wordCount: drift.Value(wordCount),
    layoutJson: drift.Value(jsonEncode(book.layout.toJson())),
    coverOptionsJson: drift.Value(jsonEncode(book.coverOptions.toJson())),
    updatedAt: drift.Value(book.updatedAt.toUtc()),
  );

  static String? _publishedAt(BookMeta meta) =>
      meta.toJson()['publishedAt'] as String?;

  ChaptersCompanion _chapterInsert(model.Chapter chapter, DateTime now) =>
      ChaptersCompanion.insert(
        id: chapter.id,
        bookId: chapter.bookId,
        parentId: drift.Value(chapter.parentId),
        title: chapter.title,
        level: drift.Value(chapter.level),
        sortOrder: chapter.order,
        frontMatter: drift.Value(chapter.frontMatter),
        wordCount: drift.Value(WordCount.ofBlocks(chapter.blocks)),
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );

  Future<void> _replaceBlocks(model.Chapter chapter) async {
    await (db.delete(
      db.blocks,
    )..where((table) => table.chapterId.equals(chapter.id))).go();
    for (var i = 0; i < chapter.blocks.length; i++) {
      final block = chapter.blocks[i];
      await db
          .into(db.blocks)
          .insert(
            BlocksCompanion.insert(
              id: block.id,
              chapterId: chapter.id,
              sortOrder: i,
              kind: block.kind.wire,
              content: drift.Value(switch (block) {
                final model.TextBlock b => b.text,
                final model.FootnoteBlock b => b.text,
                _ => null,
              }),
              assetId: drift.Value(switch (block) {
                final model.ImageBlock b => b.assetId,
                _ => null,
              }),
              metaJson: drift.Value(
                jsonEncode(switch (block) {
                  final model.ImageBlock b => <String, Object?>{
                    'caption': b.caption,
                    'alt': b.alt,
                  },
                  final model.FootnoteBlock b => <String, Object?>{
                    'marker': b.marker,
                  },
                  _ => <String, Object?>{},
                }),
              ),
              createdAt: DateTime.now().toUtc(),
            ),
          );
    }
  }

  AssetsCompanion _assetInsert(
    String bookId,
    AssetImport input,
    StoredFile staged,
    DateTime now,
  ) => AssetsCompanion.insert(
    id: staged.id,
    bookId: bookId,
    kind: input.kind,
    mime: input.mime,
    storedPath: files.storedPathFor(bookId, staged.storedPath),
    width: drift.Value(input.width),
    height: drift.Value(input.height),
    byteSize: staged.byteSize,
    sha256: staged.sha256,
    createdAt: now.toUtc(),
  );

  static int _countBook(model.Book book) => book.chapters.fold<int>(
    0,
    (sum, chapter) => sum + WordCount.ofBlocks(chapter.blocks),
  );

  void _validateStructure(model.Book book) {
    files.checkId(book.id);
    final chapters = <String, model.Chapter>{};
    final blockIds = <String>{};
    for (final chapter in book.chapters) {
      files.checkId(chapter.id);
      if (chapter.bookId != book.id || chapters.containsKey(chapter.id)) {
        throw ArgumentError('Duplicate or cross-book chapter: ${chapter.id}');
      }
      if (chapter.level != 1 && chapter.level != 2) {
        throw ArgumentError('Only two chapter levels are supported');
      }
      chapters[chapter.id] = chapter;
      for (final block in chapter.blocks) {
        files.checkId(block.id);
        if (!blockIds.add(block.id)) {
          throw ArgumentError('Duplicate block: ${block.id}');
        }
      }
    }
    for (final chapter in book.chapters) {
      if (chapter.level == 1 && chapter.parentId != null) {
        throw ArgumentError('A volume cannot have a parent');
      }
      final parentId = chapter.parentId;
      if (parentId != null &&
          (chapter.level != 2 || chapters[parentId]?.level != 1)) {
        throw ArgumentError('Chapter parent must be a volume in the same book');
      }
    }
  }

  void _validateResourceRefs(
    model.Book book,
    Set<String> available, {
    Set<String>? dirtyChapterIds,
  }) {
    if (book.coverAssetId != null && !available.contains(book.coverAssetId)) {
      throw ArgumentError('Cover asset is missing or belongs to another book');
    }
    final fontId = book.layout.embeddedFontAssetId;
    if (fontId != null && !available.contains(fontId)) {
      throw ArgumentError('Font asset is missing or belongs to another book');
    }
    for (final chapter in book.chapters) {
      if (dirtyChapterIds != null && !dirtyChapterIds.contains(chapter.id)) {
        continue;
      }
      for (final block in chapter.blocks) {
        if (block is model.ImageBlock && !available.contains(block.assetId)) {
          throw ArgumentError(
            'Image asset is missing or belongs to another book',
          );
        }
      }
    }
  }

  void _validateAssetImport(AssetImport input, String id) {
    files.checkId(id);
    if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(input.extension) ||
        !const <String>{'image', 'cover', 'font'}.contains(input.kind) ||
        input.mime.isEmpty ||
        input.maxBytes <= 0) {
      throw ArgumentError('Invalid asset import');
    }
  }
}
