import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/editor/application/book_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('font signature rejection leaves the book untouched; references isolate cleanup', () async {
    final root = await Directory.systemTemp.createTemp('bookloom-font-assets-');
    final database = AppDatabase.memory();
    addTearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    final repository = BookRepository(database, root);
    final now = DateTime.utc(2026, 1, 1);
    for (final id in ['bookA', 'bookB']) {
      await repository.createBook(
        Book(
          id: id,
          meta: BookMeta(title: id),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    final assets = BookAssets(
      repository: repository,
      files: NativeFileService(),
    );
    PickedInput input(String name, List<int> bytes) => PickedInput(
      name: name,
      size: bytes.length,
      openRead: () => Stream<List<int>>.value(bytes),
    );

    await expectLater(
      assets.importFont('bookA', input('wrong.ttf', 'wOF2'.codeUnits)),
      throwsFormatException,
    );
    expect(await repository.loadAssets('bookA'), isEmpty);

    final stored = await assets.importFont(
      'bookA',
      input('type.ttf', Uint8List.fromList([0, 1, 0, 0, 0, 1, 0, 0])),
    );
    expect((await assets.findAsset('bookA', stored.id))?.mime, 'font/ttf');
    expect(await repository.loadAssets('bookB'), isEmpty);

    final book = (await repository.loadBook('bookA'))!;
    await repository.saveBook(
      book.copyWith(
        layout: book.layout.copyWith(embeddedFontAssetId: stored.id),
      ),
      expectedRevision: book.revision,
      dirtyChapterIds: const {},
    );
    expect(await assets.cleanupUnreferenced('bookA'), 0);
    final linked = (await repository.loadBook('bookA'))!;
    await repository.saveBook(
      linked.copyWith(
        layout: linked.layout.copyWith(clearEmbeddedFontAssetId: true),
      ),
      expectedRevision: linked.revision,
      dirtyChapterIds: const {},
    );
    expect(await assets.cleanupUnreferenced('bookA'), 1);
    expect(await repository.loadAssets('bookA'), isEmpty);
  });
}
