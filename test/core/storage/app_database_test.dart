import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/settings_store.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SettingsStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = SettingsStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('inserts a book with a chapter and blocks', () async {
    final DateTime now = DateTime.utc(2026, 11, 4);

    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: 'book-1',
            title: '测试书',
            author: const Value('作者'),
            chapterCount: const Value(1),
            wordCount: const Value(6),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            id: 'chapter-1',
            bookId: 'book-1',
            title: '第一章',
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.blocks)
        .insert(
          BlocksCompanion.insert(
            id: 'block-1',
            chapterId: 'chapter-1',
            sortOrder: 0,
            kind: 'paragraph',
            content: const Value('春江潮水连海平'),
            createdAt: now,
          ),
        );

    final book = await db.select(db.books).getSingle();
    final chapter = await db.select(db.chapters).getSingle();
    final block = await db.select(db.blocks).getSingle();

    expect(book.title, '测试书');
    expect(book.wordCount, 6);
    expect(chapter.bookId, 'book-1');
    expect(block.content, '春江潮水连海平');
    expect(block.kind, 'paragraph');
  });

  test('appearance defaults when nothing is stored', () async {
    final Appearance appearance = await store.readAppearance();
    expect(appearance.themeMode, AppThemeMode.system);
    expect(appearance.glass, GlassQuality.strong);
  });

  test('appearance round-trips through the settings table', () async {
    await store.writeAppearance(
      const Appearance(themeMode: AppThemeMode.dark, glass: GlassQuality.soft),
    );
    expect(
      await store.readAppearance(),
      const Appearance(themeMode: AppThemeMode.dark, glass: GlassQuality.soft),
    );

    await store.writeAppearance(
      const Appearance(themeMode: AppThemeMode.light, glass: GlassQuality.off),
    );
    expect(
      await store.readAppearance(),
      const Appearance(themeMode: AppThemeMode.light, glass: GlassQuality.off),
    );
  });

  test('unknown stored values fall back to defaults', () async {
    await store.write('appearance.themeMode', 'sepia');
    await store.write('appearance.glass', 'molten');
    final Appearance appearance = await store.readAppearance();
    expect(appearance.themeMode, AppThemeMode.system);
    expect(appearance.glass, GlassQuality.strong);
  });

  test('foreign keys cascade when a book is deleted', () async {
    final DateTime now = DateTime.utc(2026, 11, 4);
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: 'b',
            title: 't',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            id: 'c',
            bookId: 'b',
            title: 'c1',
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.delete(db.books).go();

    expect(await db.select(db.chapters).get(), isEmpty);
  });
}
