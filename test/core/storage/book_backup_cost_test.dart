import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/model/block.dart' as model;
import 'package:bookloom/core/model/book.dart' as model;
import 'package:bookloom/core/model/chapter.dart' as model;
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/book_backup.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// Run only in the parent's dedicated resource window:
// flutter test --dart-define=BOOKLOOM_BACKUP_COST=1 \
//   test/core/storage/book_backup_cost_test.dart
const bool _runCost = String.fromEnvironment('BOOKLOOM_BACKUP_COST') == '1';
const int _mib = 1024 * 1024;

void main() {
  test(
    '20-book backup clears an isolated library and restores >256 MiB sources',
    () async {
      final free = await Process.run('df', <String>[
        '-B1',
        '--output=avail',
        '/dev/shm',
      ]);
      expect(free.exitCode, 0);
      final available = int.parse(
        (free.stdout as String).trim().split(RegExp(r'\s+')).last,
      );
      expect(
        available,
        greaterThan(2 * 1024 * _mib),
        reason: 'Keep desktop memory headroom above this 1.5 GiB test budget',
      );

      final root = await Directory('/dev/shm').createTemp('bookloom-cost-');
      AppDatabase? database;
      try {
        final home = Directory('${root.path}/library');
        await home.create();
        database = AppDatabase.openAt(File('${home.path}/books.db'));
        var repository = BookRepository(database, home);
        final expectedSources = <String, (int, String)>{};
        final expectedAssets = <String, (String, String)>{};
        final now = DateTime.utc(2026, 11, 5);
        final coverBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lZkAAAAASUVORK5CYII=',
        );
        final fontBytes = Uint8List.fromList(<int>[0, 1, 0, 0, 0, 1, 0, 0]);
        for (var index = 0; index < 20; index++) {
          final id = 'book-$index';
          final sourceBytes = index == 0
              ? 81 * _mib
              : index < 3
              ? 80 * _mib
              : index == 3
              ? 40 * _mib
              : 0;
          final book = model.Book(
            id: id,
            meta: BookMeta(
              title: '测试书 $index',
              author: '作者 $index',
              tags: <String>['独立', '$index'],
              publishedAt: DateTime.utc(2020, 5, 4),
            ),
            chapters: <model.Chapter>[
              model.Chapter(
                id: 'volume-$index',
                bookId: id,
                title: '卷',
                level: 1,
                order: 0,
              ),
              model.Chapter(
                id: 'chapter-$index',
                bookId: id,
                title: '正文',
                parentId: 'volume-$index',
                order: 0,
                blocks: <model.Block>[
                  model.TextBlock(id: 'text-$index', text: '正文 $index'),
                ],
              ),
            ],
            coverOptions: CoverOptions(palette: 'forest'),
            layout: LayoutOptions(
              customCss: 'p { margin: ${index}px; }',
              embeddedFontAssetId: index == 0 ? 'font-0' : null,
            ),
            parseOptions: const ParseOptions(encoding: 'gb18030'),
            coverMode: index == 0
                ? model.CoverMode.image
                : model.CoverMode.template,
            coverAssetId: index == 0 ? 'cover-0' : null,
            createdAt: now,
            updatedAt: now,
          );
          await repository.createBook(
            book,
            source: sourceBytes == 0
                ? null
                : SourceImport(
                    id: 'source-$index',
                    format: 'txt',
                    originalName: '原文-$index.txt',
                    maxBytes: sourceBytes,
                    openRead: () => _sourceBytes(sourceBytes),
                  ),
            assets: index == 0
                ? <AssetImport>[
                    AssetImport(
                      id: 'cover-0',
                      kind: 'cover',
                      mime: 'image/png',
                      extension: 'png',
                      openRead: () => Stream<List<int>>.value(coverBytes),
                    ),
                    AssetImport(
                      id: 'font-0',
                      kind: 'font',
                      mime: 'font/ttf',
                      extension: 'ttf',
                      openRead: () => Stream<List<int>>.value(fontBytes),
                    ),
                  ]
                : const <AssetImport>[],
          );
          if (sourceBytes > 0) {
            final source = (await repository.loadSource(id))!;
            expectedSources[id] = (source.byteSize, source.sha256);
          }
        }
        for (final asset in await repository.loadAssets('book-0')) {
          expectedAssets[asset.kind] = (asset.sha256, asset.mime);
        }

        final backup = BookBackup(
          repository,
          scratchDirectory: Directory('${root.path}/scratch'),
          appVersion: 'cost-test',
        );
        final archive = await backup.exportBooks(<String>[
          for (var i = 0; i < 20; i++) 'book-$i',
        ], '${root.path}/library.bookloom');
        await database.close();
        database = null;
        await home.delete(recursive: true); // Only this test's library.
        await home.create();
        database = AppDatabase.openAt(File('${home.path}/books.db'));
        repository = BookRepository(database, home);
        final restore = BookBackup(
          repository,
          scratchDirectory: Directory('${root.path}/restore-scratch'),
          appVersion: 'cost-test',
        );
        final preview = await restore.prepareRestore(
          archive.path,
          maxOutputBytes: 320 * _mib,
        );
        expect(preview.books, hasLength(20));
        expect(preview.actualBytes, greaterThan(256 * _mib));
        expect(preview.estimatedRequiredBytes, lessThan(1536 * _mib));
        final applied = await restore.applyRestore(preview);
        expect(applied.failures, isEmpty);
        expect(applied.cancelledIds, isEmpty);
        expect(applied.restoredIds, hasLength(20));

        for (var index = 0; index < 20; index++) {
          final id = 'book-$index';
          final book = (await repository.loadBook(id))!;
          expect(book.meta.title, '测试书 $index');
          expect(book.meta.author, '作者 $index');
          expect(book.meta.publishedAt, DateTime.utc(2020, 5, 4));
          expect(book.meta.tags, <String>['独立', '$index']);
          expect(book.parseOptions.encoding, 'gb18030');
          expect(book.coverOptions.palette, 'forest');
          expect(book.layout.customCss, 'p { margin: ${index}px; }');
          expect(book.chapters, hasLength(2));
          expect(book.chapters.first.level, 1);
          expect(book.chapters.last.parentId, book.chapters.first.id);
          final chapter = (await repository.loadChapter(
            id,
            book.chapters.last.id,
          ))!;
          expect((chapter.blocks.single as model.TextBlock).text, '正文 $index');
          final source = await repository.loadSource(id);
          if (index < 4) {
            expect(source, isNotNull);
            expect((source!.byteSize, source.sha256), expectedSources[id]);
            expect(
              await (await repository.resolveSource(source)).length(),
              source.byteSize,
            );
          } else {
            expect(source, isNull);
          }
        }
        final covered = (await repository.loadBook('book-0'))!;
        expect(covered.coverMode, model.CoverMode.image);
        expect(covered.coverAssetId, isNotNull);
        expect(covered.layout.embeddedFontAssetId, isNotNull);
        final assets = await repository.loadAssets('book-0');
        expect(assets, hasLength(2));
        for (final asset in assets) {
          expect((asset.sha256, asset.mime), expectedAssets[asset.kind]);
          expect(
            await (await repository.resolveAsset(asset)).length(),
            asset.byteSize,
          );
        }
      } finally {
        try {
          await database?.close();
        } finally {
          if (await root.exists()) await root.delete(recursive: true);
        }
      }
    },
    skip: _runCost ? false : 'Set BOOKLOOM_BACKUP_COST=1 in a planned window',
  );
}

Stream<List<int>> _sourceBytes(int byteCount) async* {
  final buffer = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0x41);
  var remaining = byteCount;
  while (remaining > 0) {
    final length = remaining < buffer.length ? remaining : buffer.length;
    yield length == buffer.length
        ? buffer
        : Uint8List.sublistView(buffer, 0, length);
    remaining -= length;
  }
}
