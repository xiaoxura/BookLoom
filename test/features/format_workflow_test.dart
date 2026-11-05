import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/formatting/docx/docx_export.dart';
import 'package:bookloom/core/formatting/epub/epub_validator.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/io/safe_zip_archive.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/export/application/export_service.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:xml/xml.dart';

const _originalTitles = <String>[
  '第一卷 初航',
  '第一章 出港',
  '第二章 风向',
  '第二卷 归岸',
  '第一章 返航',
  '第二章 抵岸',
];
const _editedTitles = <String>[
  '第一卷 初航',
  '第一章 新港',
  '第二章 风向',
  '第二卷 归岸',
  '第一章 返航',
  '第二章 抵岸',
];
const _editedBody = '修订：潮声，灯火！😀 & <岸>';
const _css = '.proof { color: #345; }';

enum _Input { txt, epub3, docx }

class _LocalSaveFiles implements FileService {
  _LocalSaveFiles(this.target);

  final File target;
  String? suggestedName;
  String? mimeType;

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) async {
    expect(await prepared.exists(), isTrue);
    this.suggestedName = suggestedName;
    this.mimeType = mimeType;
    await prepared.copy(target.path);
    return SaveSaved(target.uri);
  }

  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const <String>['txt', 'epub', 'docx'],
  }) async => <PickedInput>[];

  @override
  Future<void> clearTemporaryFiles() async {}
}

void main() {
  late Directory directory;
  late AppDatabase database;
  late BookRepository repository;
  late BackgroundJobs jobs;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bookloom-matrix-');
    database = AppDatabase.openAt(File('${directory.path}/books.sqlite'));
    repository = BookRepository(database, directory);
    jobs = BackgroundJobs();
  });
  tearDown(() async {
    jobs.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  for (final input in _Input.values) {
    test('${input.name} import, edit, reopen, and six real exports', () async {
      final source = _writeSource(directory, input);
      final originalHash = (await sha256.bind(source.openRead()).first)
          .toString();
      final importer = ImportService(
        repository: repository,
        jobs: jobs,
        temporaryDirectory: Directory('${directory.path}/cache'),
      );
      final prepared = await importer.prepare(
        PickedInput(
          name: source.uri.pathSegments.last,
          size: await source.length(),
          openRead: source.openRead,
        ),
      );
      expect(await repository.listSummaries(), isEmpty);
      expect(
        prepared.result.chapters
            .where((chapter) => !chapter.frontMatter)
            .map((chapter) => chapter.title),
        _originalTitles,
      );
      // A generated TOC or cover page must not become duplicate book text.
      final frontText = prepared.result.chapters
          .where((chapter) => chapter.frontMatter)
          .expand((chapter) => chapter.blocks)
          .map((block) => block.plainText)
          .join('\n');
      expect(frontText, isNot(contains('第一章 出港')));
      if (input == _Input.epub3) {
        expect(
          prepared.result.warnings.map((warning) => warning.code),
          contains('lost_css'),
        );
        expect(prepared.result.suggestedMeta.series, '海路集');
        expect(prepared.result.suggestedMeta.publisher, '自编社');
        expect(prepared.result.suggestedMeta.tags, containsAll(['远航', '海风']));
        expect(prepared.cover, isNotNull);
        expect(
          sha256.convert(await prepared.cover!.file.readAsBytes()).toString(),
          _coverHash.toString(),
        );
      } else {
        // DOCX and TXT do not carry the source EPUB's series/description.
        expect(prepared.result.suggestedMeta.series, isNull);
        expect(prepared.result.suggestedMeta.description, isEmpty);
        expect(prepared.cover, isNull);
      }

      var stored = await importer.commit(prepared);
      expect(
        (await sha256.bind(source.openRead()).first).toString(),
        originalHash,
      );
      if (input == _Input.epub3) {
        expect(stored.coverMode, CoverMode.image);
        final asset = (await repository.loadAssets(stored.id))
            .singleWhere((item) => item.id == stored.coverAssetId);
        expect(asset.mime, 'image/jpeg');
        expect(asset.sha256, _coverHash.toString());
        expect(
          sha256
              .convert(
                await (await repository.resolveAsset(asset)).readAsBytes(),
              )
              .toString(),
          _coverHash.toString(),
        );
      }

      // The repository contract stores sort_order within each sibling group.
      final siblingIndex = <String?, int>{};
      stored = await repository.saveBook(
        stored.copyWith(
          chapters: [
            for (final chapter in stored.chapters)
              chapter.copyWith(
                order: siblingIndex.update(
                  chapter.parentId,
                  (next) => next + 1,
                  ifAbsent: () => 0,
                ),
              ),
          ],
        ),
        expectedRevision: stored.revision,
        dirtyChapterIds: <String>{},
      );
      final session = EditorSession(repository: repository);
      await session.open(stored.id);
      final target = session.book!.chapters.singleWhere(
        (chapter) => chapter.title == '第一章 出港',
      );
      await session.selectChapter(target.id);
      final block = session.activeChapter!.blocks.whereType<TextBlock>().first;
      session.editBlockText(block.id, _editedBody);
      session.editChapterTitle(target.id, '第一章 新港');
      session.editBookMeta(
        BookMeta(
          title: '潮汐修订稿',
          author: '林岸',
          language: 'zh-CN',
          description: '扩展简介：远航与返航。',
          series: '海路集',
          publisher: '自编社',
          tags: <String>['远航', '海风'],
          publishedAt: DateTime.utc(2026, 11, 5),
        ),
      );
      session.editLayout(session.book!.layout.copyWith(customCss: _css));
      await session.close();

      await database.close();
      database = AppDatabase.openAt(File('${directory.path}/books.sqlite'));
      repository = BookRepository(database, directory);
      final reopened = EditorSession(repository: repository);
      await reopened.open(stored.id, chapterId: target.id);
      expect(reopened.book!.meta.title, '潮汐修订稿');
      expect(reopened.book!.meta.series, '海路集');
      expect(reopened.book!.layout.customCss, _css);
      expect(reopened.activeChapter!.blocks.first.plainText, _editedBody);
      expect(
        reopened.book!.chapters
            .where((chapter) => !chapter.frontMatter)
            .map((chapter) => chapter.title),
        _editedTitles,
      );
      for (final volume in reopened.book!.chapters.where(
        (chapter) => chapter.isVolume,
      )) {
        expect(
          reopened.book!.chapters
              .where((chapter) => chapter.parentId == volume.id)
              .map((chapter) => chapter.order),
          <int>[0, 1],
        );
      }
      await reopened.close();

      for (final format in ExportFormat.values) {
        final output = File(
          '${directory.path}/${input.name}-${format.name}.${format.extension}',
        );
        final files = _LocalSaveFiles(output);
        final exporter = ExportService(
          repository: repository,
          files: files,
          jobs: jobs,
          temporaryDirectory: Directory('${directory.path}/cache'),
        );
        expect(
          await exporter.exportBook(stored.id, format: format),
          isA<SaveSaved>(),
          reason: '${input.name} → ${format.name}',
        );
        expect(await output.length(), greaterThan(0));
        expect(files.mimeType, format.mimeType);
        expect(files.suggestedName, '潮汐修订稿.${format.extension}');
        _inspectOutput(output, format, expectCover: input == _Input.epub3);
      }
      expect(
        (await sha256.bind(source.openRead()).first).toString(),
        originalHash,
      );
      expect(
        await Directory('${directory.path}/cache').list().toList(),
        isEmpty,
      );
    });
  }
}

final _coverBytes = () {
  final pixels = image.Image(width: 2, height: 3, numChannels: 3);
  image.fill(pixels, color: image.ColorRgb8(32, 80, 120));
  return image.encodeJpg(pixels, quality: 90);
}();
final _coverHash = sha256.convert(_coverBytes);

File _writeSource(Directory directory, _Input input) {
  final extension = input == _Input.epub3 ? 'epub' : input.name;
  final source = File('${directory.path}/潮汐测试.$extension');
  if (input == _Input.txt) {
    source.writeAsStringSync(
      '第一卷 初航\n'
      '第一章 出港\n港口响起汽笛，海鸟掠过。😀\n'
      '第二章 风向\n风向忽然转北。\n'
      '第二卷 归岸\n'
      '第一章 返航\n灯塔又出现了。\n'
      '第二章 抵岸\n岸边有人等候！',
    );
  } else {
    writeDocument(
      ExportSnapshot(
        book: _sourceBook(),
        coverBytes: input == _Input.epub3
            ? Uint8List.fromList(_coverBytes)
            : null,
      ),
      source.path,
      format: input == _Input.epub3 ? ExportFormat.epub3 : ExportFormat.docx,
    );
  }
  return source;
}

Book _sourceBook() {
  const id = 'source-book';
  const texts = <String>['港口响起汽笛，海鸟掠过。😀', '风向忽然转北。', '灯塔又出现了。', '岸边有人等候！'];
  Chapter chapter(
    String chapterId,
    String title,
    int order, {
    int level = 2,
    String? parentId,
    String? text,
  }) => Chapter(
    id: chapterId,
    bookId: id,
    title: title,
    order: order,
    level: level,
    parentId: parentId,
    blocks: text == null
        ? const <Block>[]
        : <Block>[TextBlock(id: '$chapterId-text', text: text)],
  );
  return Book(
    id: id,
    meta: BookMeta(
      title: '潮汐测试',
      author: '林岸',
      language: 'zh-CN',
      description: '扩展简介：远航与返航。',
      series: '海路集',
      publisher: '自编社',
      tags: <String>['远航', '海风'],
      publishedAt: DateTime.utc(2026, 11, 5),
    ),
    chapters: <Chapter>[
      chapter('volume-a', _originalTitles[0], 0, level: 1),
      chapter(
        'a-1',
        _originalTitles[1],
        0,
        parentId: 'volume-a',
        text: texts[0],
      ),
      chapter(
        'a-2',
        _originalTitles[2],
        1,
        parentId: 'volume-a',
        text: texts[1],
      ),
      chapter('volume-b', _originalTitles[3], 1, level: 1),
      chapter(
        'b-1',
        _originalTitles[4],
        0,
        parentId: 'volume-b',
        text: texts[2],
      ),
      chapter(
        'b-2',
        _originalTitles[5],
        1,
        parentId: 'volume-b',
        text: texts[3],
      ),
    ],
    createdAt: DateTime.utc(2026, 11, 5),
    updatedAt: DateTime.utc(2026, 11, 5),
  );
}

void _inspectOutput(
  File output,
  ExportFormat format, {
  required bool expectCover,
}) {
  switch (format) {
    case ExportFormat.epub3 || ExportFormat.epub2:
      final version = format == ExportFormat.epub2 ? 2 : 3;
      validateEpub(output.path, version: version);
      final zip = SafeZipArchive.open(
        output.path,
        limits: const ImportLimits(),
      );
      try {
        final names = zip.entries.map((entry) => entry.name).toSet();
        final opf = zip.readXml('OEBPS/content.opf').toXmlString();
        final toc = _epubXhtml(zip, 'OEBPS/text/toc.xhtml', version).innerText;
        _expectOrder(toc, _editedTitles);
        final body = zip.entries
            .where(
              (entry) =>
                  RegExp(r'^OEBPS/text/c\d+-\d+\.xhtml$').hasMatch(entry.name),
            )
            .map((entry) => _epubXhtml(zip, entry.name, version).innerText)
            .join('\n');
        _expectOrder(body, _editedTitles);
        expect(body, contains(_editedBody));
        expect(opf, contains('潮汐修订稿'));
        expect(opf, contains('林岸'));
        expect(opf, contains('zh-CN'));
        expect(opf, contains('扩展简介：远航与返航。'));
        expect(opf, contains('自编社'));
        expect(opf, contains('2026-11-05'));
        expect(opf, contains('远航'));
        final cssFile = File('${output.path}.css');
        try {
          zip.extractToFile('OEBPS/styles/style.css', cssFile);
          expect(cssFile.readAsStringSync(), contains(_css));
        } finally {
          if (cssFile.existsSync()) cssFile.deleteSync();
        }
        if (version == 3) {
          expect(names, contains('OEBPS/nav.xhtml'));
          expect(opf, contains('belongs-to-collection'));
          expect(opf, contains('海路集'));
        } else {
          expect(names, isNot(contains('OEBPS/nav.xhtml')));
          expect(opf, isNot(contains('belongs-to-collection')));
        }
        if (expectCover) {
          expect(names, contains('OEBPS/images/cover.jpg'));
          expect(
            zip.readXml('OEBPS/content.opf').toXmlString(),
            contains('image/jpeg'),
          );
        } else {
          expect(
            names.where((name) => name.startsWith('OEBPS/images/')),
            isEmpty,
          );
        }
      } finally {
        zip.close();
      }
    case ExportFormat.docx:
      validateDocx(output.path);
      final zip = SafeZipArchive.open(
        output.path,
        limits: const ImportLimits(),
      );
      try {
        final document = zip.readXml('word/document.xml').innerText;
        _expectOrder(document, _editedTitles);
        expect(document, contains(_editedBody));
        expect(document, contains('潮汐修订稿'));
        final xml = zip.readXml('word/document.xml').toXmlString();
        expect(RegExp('w:val="Heading1"').allMatches(xml).length, 2);
        expect(RegExp('w:val="Heading2"').allMatches(xml).length, 4);
        expect(
          zip.entries.where((entry) => entry.name.startsWith('word/media/')),
          isEmpty,
        );
        expect(xml, isNot(contains('扩展简介：远航与返航。')));
        expect(xml, isNot(contains(_css)));
      } finally {
        zip.close();
      }
    case ExportFormat.html:
      final html = output.readAsStringSync();
      _expectOrder(html, _editedTitles);
      expect(html, contains('修订：潮声，灯火！😀 &amp; &lt;岸&gt;'));
      expect(html, contains(_css));
      expect(
        RegExp(r'<section class="chapter" id="c-\d+">').allMatches(html).length,
        greaterThanOrEqualTo(6),
      );
      expect(html, isNot(contains('扩展简介：远航与返航。')));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<link')));
    case ExportFormat.txt:
      final txt = output.readAsStringSync();
      _expectOrder(txt, _editedTitles);
      expect(txt, contains(_editedBody));
      expect(txt, isNot(contains('扩展简介：远航与返航。')));
      expect(txt, isNot(contains(_css)));
    case ExportFormat.markdown:
      final markdown = output.readAsStringSync();
      _expectOrder(markdown, _editedTitles);
      expect(markdown, contains('修订：潮声，灯火！😀 &amp; &lt;岸&gt;'));
      expect(markdown, contains('## 第一卷 初航'));
      expect(markdown, contains('### 第一章 新港'));
      expect(markdown, isNot(contains('扩展简介：远航与返航。')));
      expect(markdown, isNot(contains(_css)));
  }
}

void _expectOrder(String text, List<String> titles) {
  var previous = -1;
  for (final title in titles) {
    final next = text.indexOf(title, previous + 1);
    expect(next, greaterThan(previous), reason: title);
    previous = next;
  }
}

XmlDocument _epubXhtml(SafeZipArchive zip, String name, int version) {
  if (version == 3) return zip.readXml(name);
  final source = utf8.decode(zip.readXmlBytes(name));
  return XmlDocument.parse(
    source.replaceFirst(
      '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" '
          '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">',
      '',
    ),
  );
}
