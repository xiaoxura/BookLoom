import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/import/application/batch_service.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class _SavedZipFiles implements FileService {
  _SavedZipFiles(this.destination);

  final File destination;

  @override
  Future<void> clearTemporaryFiles() async {}

  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const ['txt', 'epub', 'docx'],
  }) async => [];

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) async {
    await prepared.copy(destination.path);
    return SaveSaved(destination.uri);
  }
}

Book _sourceBook(int index) {
  final id = 'source-$index';
  final now = DateTime.utc(2026);
  return Book(
    id: id,
    meta: BookMeta(title: '同名书稿', author: '测试作者'),
    chapters: [
      Chapter(
        id: '$id-chapter',
        bookId: id,
        title: '第一章 测试',
        blocks: [TextBlock(id: '$id-block', text: '第 $index 本的正文。')],
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('ten mixed inputs: partial ZIP, repair and failed-only retry', () async {
    final root = await Directory.systemTemp.createTemp('bookloom-mixed-batch-');
    final sourceDir = await Directory('${root.path}/sources').create();
    final database = AppDatabase.openAt(File('${root.path}/test.sqlite'));
    final repository = BookRepository(database, root);
    final jobs = BackgroundJobs();
    final files = _SavedZipFiles(File('${root.path}/saved.zip'));
    final importer = ImportService(
      repository: repository,
      jobs: jobs,
      temporaryDirectory: Directory('${root.path}/workbench'),
    );
    final batch = BatchService(
      repository: repository,
      files: files,
      jobs: jobs,
      importService: importer,
      temporaryDirectory: Directory('${root.path}/workbench'),
    );
    try {
      final sources = <File>[];
      for (var index = 0; index < 9; index++) {
        final extension = switch (index % 3) {
          0 => 'txt',
          1 => 'epub',
          _ => 'docx',
        };
        final source = File('${sourceDir.path}/book-$index.$extension');
        if (extension == 'txt') {
          await source.writeAsString('第一章 测试\n第 $index 本的正文。');
        } else {
          writeDocument(
            ExportSnapshot(book: _sourceBook(index)),
            source.path,
            format: extension == 'epub'
                ? ExportFormat.epub3
                : ExportFormat.docx,
          );
        }
        sources.add(source);
      }
      final validEpub = File('${sourceDir.path}/repair.epub');
      writeDocument(
        ExportSnapshot(book: _sourceBook(9)),
        validEpub.path,
        format: ExportFormat.epub3,
      );
      final repairedBytes = await validEpub.readAsBytes();
      expect(repairedBytes.length, greaterThan(12));
      expect(repairedBytes.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
      final brokenSource = File('${sourceDir.path}/broken.epub');
      await brokenSource.writeAsBytes(repairedBytes.sublist(0, 12));
      sources.add(brokenSource);
      final before = <String, String>{
        for (final source in sources)
          source.path: sha256.convert(await source.readAsBytes()).toString(),
      };

      var repaired = false;
      final attempts = List<int>.filled(10, 0);
      final inputs = <PickedInput>[];
      for (var index = 0; index < sources.length; index++) {
        final itemIndex = index;
        final source = sources[index];
        inputs.add(
          PickedInput(
            name: source.uri.pathSegments.last,
            size: await source.length(),
            openRead: () {
              attempts[itemIndex]++;
              if (itemIndex == 9 && repaired) {
                return Stream<List<int>>.value(repairedBytes);
              }
              return source.openRead();
            },
          ),
        );
      }
      await batch.enqueue(
        inputs,
        mode: BatchMode.convertFiles,
        format: ExportFormat.txt,
      );

      final processingCounts = List<int>.filled(10, 0);
      final progressEvents = List<int>.filled(10, 0);
      final previous = List<BatchItemStatus>.filled(
        10,
        BatchItemStatus.waiting,
      );
      batch.addListener(() {
        final items = batch.items;
        for (var index = 0; index < items.length; index++) {
          if (items[index].status == BatchItemStatus.processing &&
              previous[index] != BatchItemStatus.processing) {
            processingCounts[index]++;
          }
          if (items[index].status == BatchItemStatus.processing &&
              items[index].progress != null) {
            progressEvents[index]++;
          }
          previous[index] = items[index].status;
        }
      });

      await batch.start();
      expect(
        batch.items.where((item) => item.status == BatchItemStatus.success),
        hasLength(9),
      );
      expect(batch.items.last.status, BatchItemStatus.failed);
      expect(batch.items.last.error, isNotEmpty);
      expect(await repository.listSummaries(), isEmpty);
      final firstNames = [
        for (final item in batch.items.take(9)) item.outputName!,
      ];
      expect(firstNames.toSet(), hasLength(9));
      expect(
        firstNames.any((name) => RegExp(r' \(\d+\)\.txt$').hasMatch(name)),
        isTrue,
      );
      expect(await batch.saveZip(), isA<SaveSaved>());
      final firstZip = ZipDecoder().decodeBytes(
        await files.destination.readAsBytes(),
      );
      final firstEntries = {for (final entry in firstZip) entry.name: entry};
      expect(
        firstEntries.keys,
        containsAll([...firstNames, 'result-manifest.json']),
      );
      expect(firstEntries.length, 10);
      final firstManifest = jsonDecode(
        utf8.decode(firstEntries['result-manifest.json']!.content),
      ) as Map<String, dynamic>;
      final firstResults = firstManifest['results'] as List<dynamic>;
      expect(firstResults, hasLength(10));
      expect((firstResults.last as Map<String, dynamic>)['status'], 'failed');
      expect((firstResults.last as Map<String, dynamic>)['output'], isNull);
      final successfulProgress = progressEvents.take(9).toList();
      expect(successfulProgress, everyElement(greaterThan(0)));

      repaired = true;
      await batch.retryFailed();
      expect(
        batch.items.every((item) => item.status == BatchItemStatus.success),
        isTrue,
      );
      expect(attempts.take(9), everyElement(1));
      expect(attempts.last, 2);
      expect(processingCounts.take(9), everyElement(1));
      expect(processingCounts.last, 2);
      expect(progressEvents.take(9), successfulProgress);
      expect([
        for (final item in batch.items.take(9)) item.outputName,
      ], firstNames);
      expect(await repository.listSummaries(), isEmpty);
      expect(await batch.saveZip(), isA<SaveSaved>());
      final finalZip = ZipDecoder().decodeBytes(
        await files.destination.readAsBytes(),
      );
      final finalNames = finalZip.map((entry) => entry.name).toSet();
      expect(finalNames.length, 11);
      expect(
        finalNames,
        containsAll([
          ...firstNames,
          batch.items.last.outputName,
          'result-manifest.json',
        ]),
      );
      final finalManifest = jsonDecode(
        utf8.decode(
          finalZip
              .firstWhere((entry) => entry.name == 'result-manifest.json')
              .content,
        ),
      ) as Map<String, dynamic>;
      expect(
        (finalManifest['results'] as List<dynamic>).every(
          (result) => (result as Map<String, dynamic>)['status'] == 'success',
        ),
        isTrue,
      );
      for (final source in sources) {
        expect(
          sha256.convert(await source.readAsBytes()).toString(),
          before[source.path],
          reason: source.path,
        );
      }
    } finally {
      await batch.shutdown();
      jobs.dispose();
      await database.close();
      await root.delete(recursive: true);
    }
  });
}
