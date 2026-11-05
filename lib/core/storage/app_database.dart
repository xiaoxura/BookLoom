import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../text/word_count.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// SQLite database. Schema changes require a `schemaVersion` bump plus a
/// migration (and a migration test) — see docs/03-data-model.md §10.
@DriftDatabase(tables: [Books, Sources, Chapters, Blocks, Assets, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the database on a background isolate so large queries never block
  /// the UI thread.
  static AppDatabase openAt(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));

  /// In-memory database for tests.
  static AppDatabase memory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // Drift invokes onUpgrade without an implicit transaction. SQLite
        // DDL is transactional, so keep user_version and every v2 step atomic.
        await transaction(_upgradeToV2);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Drift's default DateTimeColumn converter stores Unix *seconds*.
      // Do not reinterpret v1 values as milliseconds when migrating.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _upgradeToV2() async {
    if (!await _hasColumn('books', 'cover_mode')) {
      await customStatement(
        "ALTER TABLE books ADD COLUMN cover_mode TEXT NOT NULL DEFAULT 'template'",
      );
    }
    if (!await _hasColumn('books', 'parse_options_json')) {
      await customStatement(
        "ALTER TABLE books ADD COLUMN parse_options_json TEXT NOT NULL DEFAULT '{}'",
      );
    }
    if (!await _hasColumn('books', 'revision')) {
      await customStatement(
        'ALTER TABLE books ADD COLUMN revision INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!await _hasColumn('chapters', 'front_matter')) {
      await customStatement(
        'ALTER TABLE chapters ADD COLUMN front_matter INTEGER NOT NULL DEFAULT 0',
      );
    }

    // Old sources had no FK. Remove orphan rows before rebuilding that table.
    await customStatement(
      'DELETE FROM sources WHERE book_id NOT IN (SELECT id FROM books)',
    );
    if (!await _sourcesHaveBookFk()) {
      await customStatement('ALTER TABLE sources RENAME TO sources_v1');
      await customStatement('''
      CREATE TABLE sources (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL UNIQUE REFERENCES books(id) ON DELETE CASCADE,
        format TEXT NOT NULL,
        original_name TEXT NOT NULL,
        stored_path TEXT NOT NULL,
        byte_size INTEGER NOT NULL,
        sha256 TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
      await customStatement('''
      INSERT INTO sources (id, book_id, format, original_name, stored_path,
                           byte_size, sha256, created_at)
      SELECT id, book_id, format, original_name, stored_path,
             byte_size, sha256, created_at FROM sources_v1
    ''');
      await customStatement('DROP TABLE sources_v1');
    }

    // v1 did not constrain these references. Keep valid book data while
    // clearing references that can never be resolved within the same book.
    await customStatement('''
      UPDATE books SET cover_asset_id = NULL
      WHERE cover_asset_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM assets a
        WHERE a.id = books.cover_asset_id AND a.book_id = books.id
      )
    ''');
    // v1 expressed a custom cover through cover_asset_id alone. Carry that
    // meaning into the explicit v2 mode after invalid references are cleared.
    await customStatement('''
      UPDATE books SET cover_mode = 'image'
      WHERE cover_asset_id IS NOT NULL
    ''');
    final brokenImages = await customSelect('''
      SELECT b.id, b.meta_json FROM blocks b
      JOIN chapters c ON c.id = b.chapter_id
      WHERE b.kind = 'image' AND NOT EXISTS (
        SELECT 1 FROM assets a
        WHERE a.id = b.asset_id AND a.book_id = c.book_id
      )
    ''').get();
    for (final image in brokenImages) {
      var placeholder = '[图片缺失]';
      try {
        final meta = jsonDecode(image.read<String>('meta_json'));
        if (meta is Map<String, dynamic>) {
          final caption = meta['caption'] ?? meta['alt'];
          if (caption is String && caption.trim().isNotEmpty) {
            placeholder = '[图片缺失] ${caption.trim()}';
          }
        }
      } on FormatException {
        // Keep an explicit placeholder even when old metadata is malformed.
      }
      await customUpdate(
        "UPDATE blocks SET kind = 'paragraph', text = ?, asset_id = NULL, meta_json = '{}' WHERE id = ?",
        variables: <Variable<Object>>[
          Variable<String>(placeholder),
          Variable<String>(image.read<String>('id')),
        ],
      );
    }
    await customStatement('''
      UPDATE blocks SET asset_id = NULL
      WHERE asset_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM assets a
        JOIN chapters c ON c.book_id = a.book_id
        WHERE c.id = blocks.chapter_id AND a.id = blocks.asset_id
      )
    ''');

    // Count paragraph text only. The same WordCount rule is used by the
    // editor and all later incremental saves.
    final chapterIds = await customSelect('SELECT id FROM chapters').get();
    for (final chapter in chapterIds) {
      final id = chapter.read<String>('id');
      final paragraphs = await customSelect(
        "SELECT text FROM blocks WHERE chapter_id = ? AND kind = 'paragraph'",
        variables: <Variable<Object>>[Variable<String>(id)],
      ).get();
      var count = 0;
      for (final row in paragraphs) {
        count += WordCount.ofText(row.readNullable<String>('text') ?? '');
      }
      await customUpdate(
        'UPDATE chapters SET word_count = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<int>(count),
          Variable<String>(id),
        ],
      );
    }
    await customStatement('''
      UPDATE books SET
        chapter_count = (SELECT COUNT(*) FROM chapters WHERE book_id = books.id),
        word_count = COALESCE((SELECT SUM(word_count) FROM chapters
                               WHERE book_id = books.id), 0)
    ''');
    // Drift also sets schemaVersion after onUpgrade returns. Set it here so
    // a crash between this transaction and that later write cannot strand a
    // fully migrated database at user_version=1.
    await customStatement('PRAGMA user_version = 2');
  }

  Future<bool> _hasColumn(String table, String name) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == name);
  }

  Future<bool> _sourcesHaveBookFk() async {
    final rows = await customSelect('PRAGMA foreign_key_list(sources)').get();
    return rows.any(
      (row) =>
          row.read<String>('table') == 'books' &&
          row.read<String>('from') == 'book_id' &&
          row.read<String>('on_delete').toUpperCase() == 'CASCADE',
    );
  }
}
