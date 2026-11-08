import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
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
import 'package:bookloom/core/storage/settings_store.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late AppDatabase originalDb;
  late AppDatabase destinationDb;
  late BookRepository original;
  late BookRepository destination;
  late BookBackup exporter;
  late BookBackup importer;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookloom-backup-');
    final originalHome = Directory('${root.path}/original');
    final destinationHome = Directory('${root.path}/destination');
    await originalHome.create();
    await destinationHome.create();
    originalDb = AppDatabase.openAt(File('${originalHome.path}/books.db'));
    destinationDb = AppDatabase.openAt(
      File('${destinationHome.path}/books.db'),
    );
    original = BookRepository(originalDb, originalHome);
    destination = BookRepository(destinationDb, destinationHome);
    exporter = BookBackup(
      original,
      scratchDirectory: Directory('${root.path}/export-cache'),
      appVersion: 'test',
    );
    importer = BookBackup(
      destination,
      scratchDirectory: Directory('${root.path}/restore-cache'),
      appVersion: 'test',
    );
  });

  tearDown(() async {
    await originalDb.close();
    await destinationDb.close();
    await root.delete(recursive: true);
  });

  group('rule-carrying backups', () {
    ProofreadingRule rule() => ProofreadingRule.create(
      id: 'restored-rule',
      name: '恢复规则',
      kind: ProofreadingRuleKind.advertisement,
      source: ProofreadingRuleSource.user,
      bookId: 'source-book',
      target: ProofreadingRuleTarget.bodyLine,
      mode: ProofreadingMatchMode.literal,
      pattern: '推广',
      caseSensitive: false,
      action: ProofreadingRuleAction.advertisementCandidate,
      positiveExamples: const <String>['推广'],
      negativeExamples: const <String>[],
    );

    test('v3 export carries rules and restore never applies them', () async {
      await _createOriginal(original);
      final rulesJson = encodeProofreadingRules(<ProofreadingRule>[rule()]);
      final output = await exporter.exportBooks(
        <String>['source-book'],
        '${root.path}/rules.bookloom',
        rulesJson: rulesJson,
      );
      final decoded = archive.ZipDecoder().decodeBytes(
        await output.readAsBytes(),
      );
      final contents = <String, List<int>>{
        for (final entry in decoded.files) entry.name: entry.content,
      };
      expect(contents.keys, contains('rules.json'));
      final manifest = jsonDecode(
        utf8.decode(contents['manifest.json']!),
      ) as Map<String, dynamic>;
      expect(manifest['formatVersion'], 3);
      expect(manifest['ruleCount'], 1);

      final preview = await importer.prepareRestore(
        output.path,
        maxOutputBytes: 16 * 1024 * 1024,
      );
      expect(preview.formatVersion, 3);
      expect(preview.ruleCount, 1);
      expect(preview.rulesJson, rulesJson);
      final applied = await importer.applyRestore(preview);
      expect(applied.restoredIds, <String>['source-book']);
      expect(
        await SettingsStore(destinationDb)
            .read(SettingsProofreadingRuleStore.settingsKey),
        isNull,
      );
    });

    test('v3 rules payload and count are validated before apply', () async {
      await _createOriginal(original);
      final rulesJson = encodeProofreadingRules(<ProofreadingRule>[rule()]);
      final output = await exporter.exportBooks(
        <String>['source-book'],
        '${root.path}/rules.bookloom',
        rulesJson: rulesJson,
      );

      final missing = File('${root.path}/missing.bookloom');
      await _rewriteZip(output, missing, (contents) {
        contents.remove('rules.json');
      });
      await expectLater(
        importer.prepareRestore(missing.path, maxOutputBytes: 16 * 1024 * 1024),
        throwsA(isA<FormatException>()),
      );

      final mismatch = File('${root.path}/mismatch.bookloom');
      await _rewriteZip(output, mismatch, (contents) {
        final manifest = jsonDecode(
          utf8.decode(contents['manifest.json']!),
        ) as Map<String, dynamic>;
        manifest['ruleCount'] = 2;
        contents['manifest.json'] = utf8.encode(jsonEncode(manifest));
      });
      await expectLater(
        importer.prepareRestore(
          mismatch.path,
          maxOutputBytes: 16 * 1024 * 1024,
        ),
        throwsA(isA<FormatException>()),
      );

      final malformed = File('${root.path}/malformed.bookloom');
      await _rewriteZip(output, malformed, (contents) {
        contents['rules.json'] = utf8.encode('not json');
      });
      await expectLater(
        importer.prepareRestore(
          malformed.path,
          maxOutputBytes: 16 * 1024 * 1024,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('legacy exports reject a rules entry and invalid payloads', () async {
      await _createOriginal(original);
      final legacy = await exporter.exportBooks(<String>[
        'source-book',
      ], '${root.path}/legacy.bookloom');
      final rulesJson = encodeProofreadingRules(<ProofreadingRule>[rule()]);
      final tampered = File('${root.path}/legacy-rules.bookloom');
      await _rewriteZip(legacy, tampered, (contents) {
        contents['rules.json'] = utf8.encode(rulesJson);
      });
      await expectLater(
        importer.prepareRestore(
          tampered.path,
          maxOutputBytes: 16 * 1024 * 1024,
        ),
        throwsA(isA<FormatException>()),
      );

      for (final payload in <String>[
        'not json',
        '[]',
        '{"schema_version":2,"rules":[]}',
        '{"schema_version":1,"rules":[{"id":"x"}]}',
        '{"schema_version":1,"extra":true,"rules":[]}',
        '{"schema_version":1,"rules":[{"id":"a","book_id":"source-book"},{"id":"a","book_id":"source-book"}]}',
      ]) {
        await expectLater(
          exporter.exportBooks(
            <String>['source-book'],
            '${root.path}/bad-${payload.hashCode}.bookloom',
            rulesJson: payload,
          ),
          throwsA(isA<FormatException>()),
          reason: payload,
        );
      }
      await expectLater(
        exporter.exportBooks(
          <String>['source-book'],
          '${root.path}/too-large.bookloom',
          rulesJson: jsonEncode(<String, Object?>{
            'schema_version': 1,
            'rules': <Object?>[],
            'padding': 'x' * (2 * 1024 * 1024),
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test(
    'v2 round trip restores content, options, source and asset hashes',
    () async {
      await _createOriginal(original);
      await original.addAsset(
        'source-book',
        AssetImport(
          id: 'cover-1-thumb',
          kind: 'image',
          mime: 'image/png',
          extension: 'png',
          openRead: () => Stream<List<int>>.value(<int>[9, 9]),
        ),
      );
      await original.addAsset(
        'source-book',
        AssetImport(
          id: 'old-cover',
          kind: 'cover',
          mime: 'image/png',
          extension: 'png',
          openRead: () => Stream<List<int>>.value(<int>[8, 8]),
        ),
      );
      final output = await exporter.exportBooks(<String>[
        'source-book',
      ], '${root.path}/whole.bookloom');
      final names = archive.ZipDecoder()
          .decodeBytes(await output.readAsBytes())
          .files
          .map((entry) => entry.name)
          .toSet();
      expect(names, contains('assets/source-book/cover-1.png'));
      expect(names, contains('assets/source-book/font-1.ttf'));
      expect(names, contains('assets/source-book/inline-1.png'));
      expect(names, isNot(contains('assets/source-book/cover-1-thumb.png')));
      expect(names, isNot(contains('assets/source-book/old-cover.png')));
      final preview = await importer.prepareRestore(
        output.path,
        maxOutputBytes: 16 * 1024 * 1024,
      );
      expect(preview.formatVersion, 2);
      expect(preview.books.single.title, '原书');
      expect(preview.books.single.hasSource, isTrue);
      expect(preview.books.single.assetCount, 3);
      final applied = await importer.applyRestore(preview);
      expect(applied.failures, isEmpty);
      expect(applied.restoredIds, <String>['source-book']);
      final book = (await destination.loadBook('source-book'))!;
      expect(book.meta.author, '作者');
      expect(book.meta.publishedAt, DateTime.utc(2020, 5, 4));
      expect(book.meta.tags, <String>['标签']);
      expect(book.parseOptions.encoding, 'gb18030');
      expect(book.layout.customCss, 'p { color: #123456; }');
      expect(book.coverMode, model.CoverMode.image);
      expect(book.coverAssetId, isNotNull);
      expect(book.layout.embeddedFontAssetId, isNotNull);
      final chapter = (await destination.loadChapter(
        'source-book',
        book.chapters.single.id,
      ))!;
      expect(chapter.blocks.first, isA<model.TextBlock>());
      expect((chapter.blocks.first as model.TextBlock).text, '甲乙丙');
      final inlineImage = chapter.blocks.last as model.ImageBlock;
      expect(
        (await destination.loadAssets('source-book')).map((asset) => asset.id),
        contains(inlineImage.assetId),
      );
      final restoredSource = (await destination.loadSource('source-book'))!;
      expect(
        await (await destination.resolveSource(restoredSource)).readAsString(),
        '原始文本',
      );
      expect(await destination.loadAssets('source-book'), hasLength(3));
      for (final asset in await destination.loadAssets('source-book')) {
        final bytes = await (await destination.resolveAsset(asset))
            .readAsBytes();
        expect(bytes.length, asset.byteSize);
        expect(asset.sha256, isNotEmpty);
      }
    },
  );

  test('skip, copy and overwrite keep unrelated books isolated', () async {
    await _createOriginal(original);
    final now = DateTime.utc(2026, 11, 5);
    await destination.createBook(
      model.Book(
        id: 'source-book',
        meta: BookMeta(title: '旧副本'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await destination.createBook(
      model.Book(
        id: 'unrelated',
        meta: BookMeta(title: '不能删除'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final output = await exporter.exportBooks(<String>[
      'source-book',
    ], '${root.path}/conflict.bookloom');
    final skipped = await importer.applyRestore(
      await importer.prepareRestore(
        output.path,
        maxOutputBytes: 16 * 1024 * 1024,
      ),
      policy: RestoreConflictPolicy.skip,
    );
    expect(skipped.skippedIds, <String>['source-book']);
    expect((await destination.loadBook('source-book'))!.meta.title, '旧副本');

    final copied = await importer.applyRestore(
      await importer.prepareRestore(
        output.path,
        maxOutputBytes: 16 * 1024 * 1024,
      ),
      policy: RestoreConflictPolicy.copy,
    );
    expect(copied.failures, isEmpty);
    final newId = copied.restoredIds.single;
    expect(newId, isNot('source-book'));
    final copy = (await destination.loadBook(newId))!;
    expect(copy.meta.title, '原书');
    expect(copy.chapters.single.id, isNot('chapter-1'));
    expect(copy.coverAssetId, isNot('cover-1'));
    expect((await destination.loadBook('source-book'))!.meta.title, '旧副本');

    final overwritten = await importer.applyRestore(
      await importer.prepareRestore(
        output.path,
        maxOutputBytes: 16 * 1024 * 1024,
      ),
      policy: RestoreConflictPolicy.overwrite,
    );
    expect(overwritten.failures, isEmpty);
    expect(overwritten.restoredIds, <String>['source-book']);
    expect((await destination.loadBook('source-book'))!.meta.title, '原书');
    expect((await destination.loadBook('unrelated'))!.meta.title, '不能删除');
    expect((await destination.loadBook(newId))!.meta.title, '原书');
  });

  test(
    'bad ZIP paths and write budget fail before changing current books',
    () async {
      final now = DateTime.utc(2026, 11, 5);
      await destination.createBook(
        model.Book(
          id: 'keep',
          meta: BookMeta(title: '保留'),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final malicious = archive.Archive()
        ..addFile(
          archive.ArchiveFile.string(
            'manifest.json',
            jsonEncode(<String, Object?>{
              'format': 'bookloom-backup',
              'formatVersion': 2,
              'appVersion': 'test',
              'exportedAt': now.toIso8601String(),
              'bookCount': 0,
              'includesSources': false,
              'payloadBytes': 0,
            }),
          ),
        )
        ..addFile(archive.ArchiveFile.string('../escaped.txt', 'unsafe'));
      final badFile = File('${root.path}/bad.bookloom');
      await badFile.writeAsBytes(archive.ZipEncoder().encodeBytes(malicious));
      await expectLater(
        importer.prepareRestore(badFile.path, maxOutputBytes: 1024 * 1024),
        throwsA(isA<ValidationFailure>()),
      );
      await _createOriginal(original);
      final valid = await exporter.exportBooks(<String>[
        'source-book',
      ], '${root.path}/budget.bookloom');
      await expectLater(
        importer.prepareRestore(valid.path, maxOutputBytes: 16),
        throwsA(isA<ValidationFailure>()),
      );
      expect((await destination.loadBook('keep'))!.meta.title, '保留');
      expect(await File('${root.path}/escaped.txt').exists(), isFalse);
    },
  );

  test('restore marker recovery removes unreferenced new files only', () async {
    final now = DateTime.utc(2026, 11, 5);
    await destination.createBook(
      model.Book(
        id: 'marker-book',
        meta: BookMeta(title: '旧书'),
        createdAt: now,
        updatedAt: now,
      ),
      source: SourceImport(
        format: 'txt',
        originalName: 'old.txt',
        openRead: () => Stream<List<int>>.value(<int>[4]),
      ),
      assets: <AssetImport>[
        AssetImport(
          id: 'old-id',
          kind: 'image',
          mime: 'image/png',
          extension: 'png',
          openRead: () => Stream<List<int>>.value(<int>[5]),
        ),
      ],
    );
    await destinationDb.customStatement(
      'UPDATE sources SET stored_path = ? WHERE book_id = ?',
      <Object>[r'books\marker-book\source.txt', 'marker-book'],
    );
    await destinationDb.customStatement(
      'UPDATE assets SET stored_path = ? WHERE book_id = ?',
      <Object>[r'books\marker-book\assets\old-id.png', 'marker-book'],
    );
    final bookDir = Directory('${root.path}/destination/books/marker-book');
    await Directory('${bookDir.path}/assets').create(recursive: true);
    final pending = File('${bookDir.path}/assets/new-id.png');
    await pending.writeAsBytes(<int>[1, 2, 3]);
    await File('${root.path}/destination/operations/restore-pending.json')
        .writeAsString(
          jsonEncode(<String, Object?>{
            'kind': 'restore',
            'bookId': 'marker-book',
            'paths': <String>[
              'source.txt',
              r'assets\old-id.png',
              r'assets\new-id.png',
            ],
          }),
        );
    final restarted = BookRepository(
      destinationDb,
      Directory('${root.path}/destination'),
    );
    await restarted.listSummaries();
    expect(await pending.exists(), isFalse);
    expect(await File('${bookDir.path}/source.txt').exists(), isTrue);
    expect(await File('${bookDir.path}/assets/old-id.png').exists(), isTrue);
    expect((await restarted.loadBook('marker-book'))!.meta.title, '旧书');
  });

  test('overwrite collects old resources with Windows stored paths', () async {
    await _createOriginal(original);
    final now = DateTime.utc(2026, 11, 5);
    await destination.createBook(
      model.Book(
        id: 'source-book',
        meta: BookMeta(title: '旧书'),
        createdAt: now,
        updatedAt: now,
      ),
      source: SourceImport(
        format: 'txt',
        originalName: 'old.txt',
        openRead: () => Stream<List<int>>.value(<int>[4]),
      ),
      assets: <AssetImport>[
        AssetImport(
          id: 'old-id',
          kind: 'image',
          mime: 'image/png',
          extension: 'png',
          openRead: () => Stream<List<int>>.value(<int>[5]),
        ),
      ],
    );
    await destinationDb.customStatement(
      'UPDATE sources SET stored_path = ? WHERE book_id = ?',
      <Object>[r'books\source-book\source.txt', 'source-book'],
    );
    await destinationDb.customStatement(
      'UPDATE assets SET stored_path = ? WHERE book_id = ?',
      <Object>[r'books\source-book\assets\old-id.png', 'source-book'],
    );
    final output = await exporter.exportBooks(<String>[
      'source-book',
    ], '${root.path}/legacy-overwrite.bookloom');
    final result = await importer.applyRestore(
      await importer.prepareRestore(
        output.path,
        maxOutputBytes: 16 * 1024 * 1024,
      ),
      policy: RestoreConflictPolicy.overwrite,
    );
    expect(result.failures, isEmpty);
    expect(result.restoredIds, <String>['source-book']);
    final bookDir = Directory('${root.path}/destination/books/source-book');
    expect(await File('${bookDir.path}/source.txt').exists(), isFalse);
    expect(await File('${bookDir.path}/assets/old-id.png').exists(), isFalse);
    expect((await destination.loadBook('source-book'))!.meta.title, '原书');
  });

  test('tampered staged resource fails before overwrite commits', () async {
    await _createOriginal(original);
    final now = DateTime.utc(2026, 11, 5);
    await destination.createBook(
      model.Book(
        id: 'source-book',
        meta: BookMeta(title: '安全旧书'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final output = await exporter.exportBooks(<String>[
      'source-book',
    ], '${root.path}/tamper.bookloom');
    final preview = await importer.prepareRestore(
      output.path,
      maxOutputBytes: 16 * 1024 * 1024,
    );
    final stage = Directory('${root.path}/restore-cache')
        .listSync()
        .whereType<Directory>()
        .single;
    await File('${stage.path}/entries/assets/source-book/cover-1.png')
        .writeAsBytes(<int>[0, 0, 0, 0]);
    final applied = await importer.applyRestore(
      preview,
      policy: RestoreConflictPolicy.overwrite,
    );
    expect(applied.restoredIds, isEmpty);
    expect(applied.failures, contains('source-book'));
    expect((await destination.loadBook('source-book'))!.meta.title, '安全旧书');
    expect(await destination.loadAssets('source-book'), isEmpty);
  });

  test(
    'cancel before restore commit leaves every selected book untouched',
    () async {
      await _createOriginal(original);
      final now = DateTime.utc(2026, 11, 5);
      await original.createBook(
        model.Book(
          id: 'second-book',
          meta: BookMeta(title: '第二本'),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final output = await exporter.exportBooks(<String>[
        'source-book',
        'second-book',
      ], '${root.path}/cancel.bookloom');
      final preview = await importer.prepareRestore(
        output.path,
        maxOutputBytes: 16 * 1024 * 1024,
      );
      final applying = importer.applyRestore(preview);
      importer.cancel();
      final result = await applying;
      expect(result.restoredIds, isEmpty);
      expect(result.cancelledIds, <String>['source-book', 'second-book']);
      expect(await destination.loadBook('source-book'), isNull);
      expect(await destination.loadBook('second-book'), isNull);
    },
  );

  test('v2 chunks escaped long text without an oversized record', () async {
    final now = DateTime.utc(2026, 11, 5);
    final text = List<String>.filled(210000, '\u0001').join();
    await original.createBook(
      model.Book(
        id: 'long-book',
        meta: BookMeta(title: '长文本'),
        chapters: <model.Chapter>[
          model.Chapter(
            id: 'long-chapter',
            bookId: 'long-book',
            title: '正文',
            blocks: <model.Block>[model.TextBlock(id: 'long-text', text: text)],
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    final output = await exporter.exportBooks(
      <String>['long-book'],
      '${root.path}/long.bookloom',
      includeSources: false,
    );
    final preview = await importer.prepareRestore(
      output.path,
      maxOutputBytes: 16 * 1024 * 1024,
    );
    expect(preview.includesSources, isFalse);
    final result = await importer.applyRestore(preview);
    expect(result.failures, isEmpty);
    final book = (await destination.loadBook('long-book'))!;
    final chapter = (await destination.loadChapter(
      book.id,
      book.chapters.single.id,
    ))!;
    expect((chapter.blocks.single as model.TextBlock).text, text);
  });

  test('bounded v1 JSON restores legacy seconds and text field', () async {
    final now = DateTime.utc(2026, 11, 5);
    await original.createBook(
      model.Book(
        id: 'legacy-book',
        meta: BookMeta(title: '旧格式'),
        chapters: const <model.Chapter>[
          model.Chapter(
            id: 'legacy-chapter',
            bookId: 'legacy-book',
            title: '正文',
            blocks: <model.Block>[
              model.TextBlock(id: 'legacy-text', text: '旧正文'),
            ],
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    final book =
        (await originalDb.select(originalDb.books).getSingle()).toJson()
          ..remove('revision')
          ..remove('coverMode')
          ..remove('parseOptionsJson');
    book['createdAt'] = now.millisecondsSinceEpoch ~/ 1000;
    book['updatedAt'] = now.millisecondsSinceEpoch ~/ 1000;
    final chapter =
        (await originalDb.select(originalDb.chapters).getSingle()).toJson()
          ..remove('frontMatter');
    chapter['createdAt'] = now.millisecondsSinceEpoch ~/ 1000;
    chapter['updatedAt'] = now.millisecondsSinceEpoch ~/ 1000;
    final block = (await originalDb.select(originalDb.blocks).getSingle())
        .toJson();
    block['text'] = block.remove('content');
    block['createdAt'] = now.millisecondsSinceEpoch ~/ 1000;
    final zipped = archive.Archive()
      ..addFile(
        archive.ArchiveFile.string(
          'manifest.json',
          jsonEncode(<String, Object?>{
            'format': 'bookloom-backup',
            'formatVersion': 1,
            'bookCount': 1,
            'includesSources': false,
          }),
        ),
      )
      ..addFile(
        archive.ArchiveFile.string(
          'library.json',
          jsonEncode(<String, Object?>{
            'books': <Object?>[book],
            'chapters': <Object?>[chapter],
            'blocks': <Object?>[block],
          }),
        ),
      );
    final input = File('${root.path}/legacy.bookloom');
    await input.writeAsBytes(archive.ZipEncoder().encodeBytes(zipped));
    final preview = await importer.prepareRestore(
      input.path,
      maxOutputBytes: 1024 * 1024,
    );
    expect(preview.formatVersion, 1);
    final applied = await importer.applyRestore(preview);
    expect(applied.failures, isEmpty);
    final restored = (await destination.loadBook('legacy-book'))!;
    expect(restored.createdAt, now);
    final restoredChapter = (await destination.loadChapter(
      restored.id,
      restored.chapters.single.id,
    ))!;
    expect((restoredChapter.blocks.single as model.TextBlock).text, '旧正文');
  });

  test('corrupt and over-budget archives report distinct failures', () async {
    final corrupt = File('${root.path}/corrupt.bookloom');
    await corrupt.writeAsString('not a bookloom backup');
    await expectLater(
      importer.prepareRestore(corrupt.path, maxOutputBytes: 1024 * 1024),
      throwsA(
        isA<ValidationFailure>().having(
          (error) => error.message,
          'message',
          contains('无效或已损坏'),
        ),
      ),
    );

    await _createOriginal(original);
    final output = await exporter.exportBooks(<String>[
      'source-book',
    ], '${root.path}/small.bookloom');
    await expectLater(
      importer.prepareRestore(output.path, maxOutputBytes: 32),
      throwsA(
        isA<ValidationFailure>().having(
          (error) => error.message,
          'message',
          contains('预算'),
        ),
      ),
    );
  });
}

Future<void> _createOriginal(BookRepository repository) async {
  final now = DateTime.utc(2026, 11, 5);
  final book = model.Book(
    id: 'source-book',
    meta: BookMeta(
      title: '原书',
      author: '作者',
      tags: <String>['标签'],
      publishedAt: DateTime.utc(2020, 5, 4),
    ),
    chapters: const <model.Chapter>[
      model.Chapter(
        id: 'chapter-1',
        bookId: 'source-book',
        title: '正文',
        blocks: <model.Block>[
          model.TextBlock(id: 'text-1', text: '甲乙丙'),
          model.ImageBlock(id: 'image-1', assetId: 'inline-1'),
        ],
      ),
    ],
    layout: LayoutOptions(
      customCss: 'p { color: #123456; }',
      embeddedFontAssetId: 'font-1',
    ),
    coverOptions: CoverOptions(palette: 'forest'),
    parseOptions: const ParseOptions(encoding: 'gb18030'),
    coverMode: model.CoverMode.image,
    coverAssetId: 'cover-1',
    createdAt: now,
    updatedAt: now,
  );
  await repository.createBook(
    book,
    source: SourceImport(
      id: 'source-1',
      format: 'txt',
      originalName: '原书.txt',
      openRead: () => Stream<List<int>>.value(utf8.encode('原始文本')),
    ),
    assets: <AssetImport>[
      AssetImport(
        id: 'cover-1',
        kind: 'cover',
        mime: 'image/png',
        extension: 'png',
        openRead: () => Stream<List<int>>.value(<int>[1, 2, 3, 4]),
      ),
      AssetImport(
        id: 'font-1',
        kind: 'font',
        mime: 'font/ttf',
        extension: 'ttf',
        openRead: () => Stream<List<int>>.value(<int>[5, 6, 7]),
      ),
      AssetImport(
        id: 'inline-1',
        kind: 'image',
        mime: 'image/png',
        extension: 'png',
        openRead: () => Stream<List<int>>.value(<int>[7, 8, 9]),
      ),
    ],
  );
}

Future<void> _rewriteZip(
  File source,
  File destination,
  void Function(Map<String, List<int>> contents) mutate,
) async {
  final decoded = archive.ZipDecoder().decodeBytes(await source.readAsBytes());
  final contents = <String, List<int>>{
    for (final entry in decoded.files) entry.name: entry.content,
  };
  mutate(contents);
  final manifest = jsonDecode(
    utf8.decode(contents['manifest.json']!),
  ) as Map<String, dynamic>;
  manifest['payloadBytes'] = contents.entries
      .where((entry) => entry.key != 'manifest.json')
      .fold<int>(0, (sum, entry) => sum + entry.value.length);
  contents['manifest.json'] = utf8.encode(jsonEncode(manifest));
  final rewritten = archive.Archive();
  for (final entry in contents.entries) {
    rewritten.addFile(
      archive.ArchiveFile(entry.key, entry.value.length, entry.value),
    );
  }
  await destination.writeAsBytes(archive.ZipEncoder().encodeBytes(rewritten));
}
