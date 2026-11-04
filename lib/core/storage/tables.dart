import 'package:drift/drift.dart';

/// Logical schema mirroring docs/03-data-model.md, expressed for Drift.
///
/// Rules: ids are UUID strings, timestamps are UTC, binary content lives on
/// disk and only its path/metadata is stored here.

@TableIndex(name: 'books_updated_at', columns: {#updatedAt})
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get language => text().withDefault(const Constant('zh-CN'))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get series => text().nullable()();
  TextColumn get publisher => text().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get publishedAt => text().nullable()();
  TextColumn get coverAssetId => text().nullable()();
  IntColumn get chapterCount => integer().withDefault(const Constant(0))();
  IntColumn get wordCount => integer().withDefault(const Constant(0))();
  TextColumn get layoutJson => text().withDefault(const Constant('{}'))();
  TextColumn get coverOptionsJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  RealColumn get progress => real().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class Sources extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().unique()();
  TextColumn get format => text()();
  TextColumn get originalName => text()();
  TextColumn get storedPath => text()();
  IntColumn get byteSize => integer()();
  TextColumn get sha256 => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@TableIndex(name: 'chapters_book_order', columns: {#bookId, #sortOrder})
class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get parentId => text().nullable().references(
    Chapters,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get title => text()();
  IntColumn get level => integer().withDefault(const Constant(2))();
  IntColumn get sortOrder => integer()();
  IntColumn get wordCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@TableIndex(name: 'blocks_chapter_order', columns: {#chapterId, #sortOrder})
@TableIndex(name: 'blocks_asset', columns: {#assetId})
class Blocks extends Table {
  TextColumn get id => text()();
  TextColumn get chapterId =>
      text().references(Chapters, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  TextColumn get kind => text()();

  /// Column is named `text` in SQLite; the Dart getter cannot be called `text`
  /// because that would shadow drift's top-level `text()` builder.
  TextColumn get content => text().named('text').nullable()();
  TextColumn get assetId => text().nullable()();
  TextColumn get metaJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@TableIndex(name: 'assets_book_kind', columns: {#bookId, #kind})
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get mime => text()();
  TextColumn get storedPath => text()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get byteSize => integer()();
  TextColumn get sha256 => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Key/value preferences (appearance, last opened book, etc.).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}
