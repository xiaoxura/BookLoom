import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/app/offline_dictionaries.dart';
import 'package:bookloom/core/conversion/opencc_converter.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PickedInput _input(String name, Uint8List bytes) => PickedInput(
  name: name,
  size: bytes.length,
  openRead: () => Stream<List<int>>.value(bytes),
);

String _chapterText(Iterable<TextBlock> blocks) =>
    blocks.map((block) => block.text).join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase database;
  late BookRepository repository;
  late BackgroundJobs jobs;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'bookloom-offline-conversion-',
    );
    database = AppDatabase.openAt(File('${root.path}/books.sqlite'));
    repository = BookRepository(database, root);
    jobs = BackgroundJobs();
  });

  tearDown(() async {
    jobs.dispose();
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'imports simplified and Taiwan text with cached bundled dictionaries',
    () async {
      var loadCount = 0;
      Future<Map<String, String>> loadDictionaries() async {
        loadCount++;
        final dictionaries = await loadOfflineDictionaries();
        expect(
          dictionaries.keys,
          unorderedEquals(OpenCcConverter.requiredDictionaryFiles),
        );
        return dictionaries;
      }

      final importer = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: Directory('${root.path}/cache'),
        loadDictionaries: loadDictionaries,
      );
      expect(loadCount, 0);

      final simplifiedSource = Uint8List.fromList(
        utf8.encode(
          '內容簡介：江流宛轉遶芳甸，一目瞭然。\n'
          '第一章 江流宛轉\n江流宛轉遶芳甸\n一目瞭然。',
        ),
      );
      final simplifiedPrepared = await importer.prepare(
        _input('《臺灣測試》作者：陳雲.txt', simplifiedSource),
        options: const ParseOptions(convertMode: ConvertMode.simplified),
      );
      expect(loadCount, 1);
      expect(simplifiedPrepared.result.suggestedMeta.title, '台湾测试');
      expect(simplifiedPrepared.result.suggestedMeta.author, '陈云');
      expect(
        simplifiedPrepared.result.suggestedMeta.description,
        '江流宛转绕芳甸，一目了然。',
      );
      final simplifiedChapter = simplifiedPrepared.result.chapters.firstWhere(
        (chapter) => !chapter.frontMatter && !chapter.isVolume,
      );
      expect(simplifiedChapter.title, '第一章 江流宛转');
      expect(
        _chapterText(simplifiedChapter.blocks.whereType<TextBlock>()),
        contains('江流宛转绕芳甸'),
      );
      expect(
        _chapterText(simplifiedChapter.blocks.whereType<TextBlock>()),
        contains('一目了然。'),
      );
      final simplifiedBook = await importer.commit(simplifiedPrepared);
      final savedSimplifiedBook = (await repository.loadBook(
        simplifiedBook.id,
      ))!;
      final savedSimplifiedChapterSummary = savedSimplifiedBook.chapters
          .firstWhere((chapter) => !chapter.frontMatter && !chapter.isVolume);
      final savedSimplifiedChapter = await repository.loadChapter(
        simplifiedBook.id,
        savedSimplifiedChapterSummary.id,
      );
      expect(savedSimplifiedBook.meta.title, '台湾测试');
      expect(savedSimplifiedBook.meta.author, '陈云');
      expect(savedSimplifiedBook.meta.description, '江流宛转绕芳甸，一目了然。');
      expect(savedSimplifiedChapter!.title, '第一章 江流宛转');
      expect(
        _chapterText(savedSimplifiedChapter.blocks.whereType<TextBlock>()),
        contains('江流宛转绕芳甸'),
      );
      final savedSimplifiedSource = (await repository.loadSource(
        simplifiedBook.id,
      ))!;
      expect(savedSimplifiedSource.byteSize, simplifiedSource.length);
      expect(
        savedSimplifiedSource.sha256,
        sha256.convert(simplifiedSource).toString(),
      );
      expect(
        await (await repository.resolveSource(savedSimplifiedSource))
            .readAsBytes(),
        simplifiedSource,
      );

      final taiwanSource = Uint8List.fromList(
        utf8.encode(
          '內容簡介：鼠标里面的硅二极管坏了，导致光标分辨率降低。\n'
          '第一章 鼠标工具\n鼠标里面的硅二极管坏了，导致光标分辨率降低。',
        ),
      );
      final taiwanPrepared = await importer.prepare(
        _input('《鼠标测试》作者：张云.txt', taiwanSource),
        options: const ParseOptions(convertMode: ConvertMode.taiwan),
      );
      expect(loadCount, 1);
      expect(taiwanPrepared.result.suggestedMeta.title, '滑鼠測試');
      expect(taiwanPrepared.result.suggestedMeta.author, '張雲');
      expect(
        taiwanPrepared.result.suggestedMeta.description,
        '滑鼠裡面的矽二極體壞了，導致游標解析度降低。',
      );
      final taiwanChapter = taiwanPrepared.result.chapters.firstWhere(
        (chapter) => !chapter.frontMatter && !chapter.isVolume,
      );
      expect(taiwanChapter.title, '第一章 滑鼠工具');
      expect(
        _chapterText(taiwanChapter.blocks.whereType<TextBlock>()),
        '滑鼠裡面的矽二極體壞了，導致游標解析度降低。',
      );
      final taiwanBook = await importer.commit(taiwanPrepared);
      final savedTaiwanBook = (await repository.loadBook(taiwanBook.id))!;
      final savedTaiwanChapterSummary = savedTaiwanBook.chapters.firstWhere(
        (chapter) => !chapter.frontMatter && !chapter.isVolume,
      );
      final savedTaiwanChapter = await repository.loadChapter(
        taiwanBook.id,
        savedTaiwanChapterSummary.id,
      );
      expect(savedTaiwanBook.meta.title, '滑鼠測試');
      expect(savedTaiwanBook.meta.author, '張雲');
      expect(savedTaiwanBook.meta.description, '滑鼠裡面的矽二極體壞了，導致游標解析度降低。');
      expect(savedTaiwanChapter!.title, '第一章 滑鼠工具');
      expect(
        _chapterText(savedTaiwanChapter.blocks.whereType<TextBlock>()),
        '滑鼠裡面的矽二極體壞了，導致游標解析度降低。',
      );
      final savedTaiwanSource = (await repository.loadSource(taiwanBook.id))!;
      expect(savedTaiwanSource.byteSize, taiwanSource.length);
      expect(savedTaiwanSource.sha256, sha256.convert(taiwanSource).toString());
      expect(
        await (await repository.resolveSource(savedTaiwanSource)).readAsBytes(),
        taiwanSource,
      );
      expect(await repository.listSummaries(), hasLength(2));
    },
  );

  test(
    'retries the bundled dictionary load after an initial failure',
    () async {
      var attempts = 0;
      Future<Map<String, String>> loadWithOneFailure() async {
        attempts++;
        if (attempts == 1) {
          throw const FormatException('temporary asset failure');
        }
        return loadOfflineDictionaries();
      }

      final cache = Directory('${root.path}/retry-cache');
      final importer = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: cache,
        loadDictionaries: loadWithOneFailure,
      );
      final bytes = Uint8List.fromList(utf8.encode('第一章 重试\n离线词典已加载。'));
      PickedInput input() => _input('重试.txt', bytes);

      await expectLater(
        importer.prepare(
          input(),
          options: const ParseOptions(convertMode: ConvertMode.simplified),
        ),
        throwsA(isA<ImportFailure>()),
      );
      expect(attempts, 1);
      expect(await cache.list().toList(), isEmpty);
      expect(await repository.listSummaries(), isEmpty);

      final prepared = await importer.prepare(
        input(),
        options: const ParseOptions(convertMode: ConvertMode.simplified),
      );
      expect(attempts, 2);
      expect(prepared.result.chapters, hasLength(1));
      await importer.discard(prepared);
      expect(await cache.list().toList(), isEmpty);
      expect(await repository.listSummaries(), isEmpty);
    },
  );
}
