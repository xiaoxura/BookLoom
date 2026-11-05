import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/formatting/docx/docx_export.dart';
import 'package:bookloom/core/formatting/epub/epub_validator.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/parsing/txt_parser.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Block, Book, Chapter;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  setUp(
    () => temporary = Directory.systemTemp.createTempSync(
      'bookloom-format-test-',
    ),
  );
  tearDown(() => temporary.deleteSync(recursive: true));

  test('EPUB 2 has XHTML 1.1, NCX and toc without EPUB 3 fields', () {
    final output = '${temporary.path}/legacy.epub';
    final cover = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/W9sAAAAASUVORK5CYII=',
      ),
    );
    final snapshot = ExportSnapshot(
      book: _book(layout: LayoutOptions(embeddedFontAssetId: 'font')),
      coverBytes: cover,
      coverMime: 'image/png',
      fonts: <ExportFont>[
        ExportFont(
          assetId: 'font',
          fileName: 'own.ttf',
          bytes: Uint8List.fromList(<int>[0, 1, 0, 0]),
        ),
      ],
    );
    writeDocument(snapshot, output, format: ExportFormat.epub2);
    expect(() => validateEpub(output, version: 2), returnsNormally);
    final bytes = File(output).readAsBytesSync();
    final names = _names(bytes);
    expect(
      names,
      containsAll(<String>[
        'OEBPS/toc.ncx',
        'OEBPS/text/toc.xhtml',
        'OEBPS/text/cover.xhtml',
        'OEBPS/images/cover.png',
        'OEBPS/fonts/font-1.ttf',
      ]),
    );
    expect(names, isNot(contains('OEBPS/nav.xhtml')));
    final opf = _zipText(bytes, 'OEBPS/content.opf');
    expect(opf, contains('version="2.0"'));
    expect(opf, isNot(contains('properties="nav"')));
    expect(opf, isNot(contains('dcterms:modified')));
    expect(opf, isNot(contains('belongs-to-collection')));
    expect(opf, isNot(contains('properties="cover-image"')));
    expect(opf, contains('name="cover" content="cover-image"'));
    final chapter = _zipText(bytes, 'OEBPS/text/c0003-1.xhtml');
    expect(chapter, contains('XHTML 1.1'));
    expect(chapter, isNot(contains('epub:type')));
    expect(chapter, isNot(contains('xmlns:epub')));
    expect(chapter, contains('<div class="chapter">'));
    expect(
      _zipText(bytes, 'OEBPS/text/toc.xhtml'),
      contains('href="../text/c0003-1.xhtml#heading"'),
    );
  });

  test(
    'DOCX contains editable OOXML, title and heading styles, escaped text',
    () {
      final output = '${temporary.path}/book.docx';
      writeDocument(
        ExportSnapshot(
          book: _book(
            layout: LayoutOptions(
              separateChapterNumber: true,
              lineHeight: 1.75,
              indent: true,
              justify: true,
            ),
          ),
        ),
        output,
        format: ExportFormat.docx,
      );
      expect(() => validateDocx(output), returnsNormally);
      final bytes = File(output).readAsBytesSync();
      expect(
        _names(bytes),
        containsAll(<String>[
          '[Content_Types].xml',
          '_rels/.rels',
          'docProps/core.xml',
          'word/document.xml',
          'word/styles.xml',
          'word/_rels/document.xml.rels',
        ]),
      );
      final document = _zipText(bytes, 'word/document.xml');
      expect(document, contains('w:val="Title"'));
      expect(document, contains('w:val="Heading1"'));
      expect(document, contains('w:val="Heading2"'));
      expect(document, contains('序文 &amp; &lt;航海&gt;'));
      expect(document, contains('<w:br/>'));
      expect(document, contains('<w:sectPr>'));
      expect(document, isNot(contains('w:val="front"')));
      final styles = _zipText(bytes, 'word/styles.xml');
      expect(styles, contains('w:line="420"'));
      expect(styles, contains('w:firstLine="480"'));
      expect(styles, contains('w:val="both"'));
      expect(styles, contains('宋体'));
      expect(
        _names(bytes).where((name) => name.startsWith('word/media/')),
        isEmpty,
      );
    },
  );

  test(
    'single HTML has inline CSS, matching anchors and no external assets',
    () {
      final output = '${temporary.path}/book.html';
      writeDocument(
        ExportSnapshot(
          book: _book(
            layout: LayoutOptions(
              lineHeight: 1.8,
              customCss: '.extra { color: red; }',
            ),
          ),
        ),
        output,
        format: ExportFormat.html,
      );
      final html = File(output).readAsStringSync();
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('<style>'));
      expect(html, contains('line-height: 1.8'));
      expect(html, contains('.extra { color: red; }'));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<link')));
      expect(html, isNot(contains('src=')));
      expect(html, contains('序文 &amp; &lt;航海&gt;'));
      final links = RegExp(r'href="#(c-\d+)"')
          .allMatches(html)
          .map((match) => match[1])
          .toList();
      final ids = RegExp(r'id="(c-\d+)"')
          .allMatches(html)
          .map((match) => match[1])
          .toList();
      expect(links, ids);
      expect(html, contains('class="toc-volume"'));
      expect(html, contains('class="toc-chapter"'));
      final preface = html.split('id="c-1"')[1].split('</section>')[0];
      expect(preface, isNot(contains('前言</h2>')));
    },
  );

  test('HTML navigation validation ignores anchor-shaped text in CSS', () {
    final output = '${temporary.path}/css-anchors.html';
    const css = '.x::before { content: \'id="c-1" href="#c-1"\'; }';
    writeDocument(
      ExportSnapshot(
        book: _book(layout: LayoutOptions(customCss: css)),
      ),
      output,
      format: ExportFormat.html,
    );
    final html = File(output).readAsStringSync();
    expect(html, contains(css));
    expect(
      RegExp(r'<section class="chapter" id="c-\d+">').allMatches(html).length,
      3,
    );
    expect(RegExp(r'<a href="#c-\d+">').allMatches(html).length, 3);
  });

  test('TXT uses recognizable headings and round-trips through TXT parser', () {
    final output = '${temporary.path}/book.txt';
    writeDocument(
      ExportSnapshot(book: _book()),
      output,
      format: ExportFormat.txt,
    );
    final text = File(output).readAsStringSync();
    expect(text, startsWith('序文 & <航海>。\n\n\n第一卷 海路'));
    expect(text, contains('第一章 起航\n\n船灯亮了。\n\n海风正好。'));
    expect(text, isNot(contains('前言\n')));
    final parsed = parseTxtText(
      text,
      bookId: 'roundtrip',
      filename: 'book.txt',
    );
    expect(parsed.chapters.map((chapter) => chapter.title), <String>[
      '前言',
      '第一卷 海路',
      '第一章 起航',
    ]);
    expect(
      parsed.chapters.last.blocks.whereType<TextBlock>().map(
        (block) => block.text,
      ),
      <String>['船灯亮了。', '海风正好。'],
    );
  });

  test('Markdown escapes active syntax and uses volume/chapter levels', () {
    final output = '${temporary.path}/book.md';
    final book = _book(
      chapters: <Chapter>[
        _chapter(
          'one',
          '第一章 [链接] & <脚本>',
          0,
          blocks: <Block>[const TextBlock(id: 'text', text: '# 不是标题 *强调* <b>')],
        ),
      ],
    );
    writeDocument(
      ExportSnapshot(book: book),
      output,
      format: ExportFormat.markdown,
    );
    final markdown = File(output).readAsStringSync();
    expect(markdown, contains('## 第一章 \\[链接\\] &amp; &lt;脚本&gt;'));
    expect(markdown, contains('\\# 不是标题 \\*强调\\* &lt;b&gt;'));
    expect(markdown, isNot(contains('<b>')));
    expect(markdown, isNot(contains('### 第一章')));
  });

  test('facade rejects an existing destination without replacing it', () {
    final output = '${temporary.path}/keep.txt';
    File(output).writeAsStringSync('keep');
    expect(
      () => writeDocument(
        ExportSnapshot(book: _book()),
        output,
        format: ExportFormat.txt,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(output).readAsStringSync(), 'keep');
  });

  test(
    'all six formats retain sibling order after a two-volume book reopens',
    () async {
      final databaseFile = File('${temporary.path}/bookloom.sqlite');
      var database = AppDatabase.openAt(databaseFile);
      try {
        var repository = BookRepository(database, temporary);
        final chapters = <Chapter>[
          _chapter('volume-a', '卷甲', 0, level: 1),
          _chapter(
            'a-1',
            '甲一',
            0,
            parentId: 'volume-a',
            blocks: <Block>[const TextBlock(id: 'body-a-1', text: '甲一正文')],
          ),
          _chapter(
            'a-2',
            '甲二',
            1,
            parentId: 'volume-a',
            blocks: <Block>[const TextBlock(id: 'body-a-2', text: '甲二正文')],
          ),
          _chapter('volume-b', '卷乙', 1, level: 1),
          _chapter(
            'b-1',
            '乙一',
            0,
            parentId: 'volume-b',
            blocks: <Block>[const TextBlock(id: 'body-b-1', text: '乙一正文')],
          ),
          _chapter(
            'b-2',
            '乙二',
            1,
            parentId: 'volume-b',
            blocks: <Block>[const TextBlock(id: 'body-b-2', text: '乙二正文')],
          ),
        ];
        await repository.createBook(_book(chapters: chapters));
        await database.close();
        database = AppDatabase.openAt(databaseFile);
        repository = BookRepository(database, temporary);
        final reopened = (await repository.loadBook('book-1'))!;
        final loaded = <Chapter>[];
        for (final chapter in reopened.chapters) {
          loaded.add((await repository.loadChapter('book-1', chapter.id))!);
        }
        final snapshot = ExportSnapshot(
          book: reopened.copyWith(chapters: loaded),
        );
        const titles = <String>['卷甲', '甲一', '甲二', '卷乙', '乙一', '乙二'];
        expect(loaded.map((chapter) => chapter.title), titles);
        for (final format in ExportFormat.values) {
          final output =
              '${temporary.path}/reopened-${format.name}.${format.extension}';
          writeDocument(snapshot, output, format: format);
          final data = switch (format) {
            ExportFormat.epub3 || ExportFormat.epub2 => _zipText(
              File(output).readAsBytesSync(),
              'OEBPS/text/toc.xhtml',
            ),
            ExportFormat.docx => _zipText(
              File(output).readAsBytesSync(),
              'word/document.xml',
            ),
            ExportFormat.html ||
            ExportFormat.txt ||
            ExportFormat.markdown => File(output).readAsStringSync(),
          };
          var previous = -1;
          for (final title in titles) {
            final next = data.indexOf(title);
            expect(
              next,
              greaterThan(previous),
              reason: '${format.name}: $title',
            );
            previous = next;
          }
        }
      } finally {
        await database.close();
      }
    },
  );
}

Book _book({List<Chapter>? chapters, BookMeta? meta, LayoutOptions? layout}) =>
    Book(
      id: 'book-1',
      meta: meta ?? BookMeta(title: '潮汐 & 灯', author: '林舟', series: '航海系列'),
      chapters:
          chapters ??
          <Chapter>[
            _chapter(
              'front',
              '前言',
              0,
              frontMatter: true,
              blocks: <Block>[const TextBlock(id: 'f', text: '序文 & <航海>。')],
            ),
            _chapter('volume', '第一卷 海路', 1, level: 1),
            _chapter(
              'chapter',
              '第一章 起航',
              2,
              parentId: 'volume',
              blocks: <Block>[
                const TextBlock(id: 'a', text: '船灯亮了。'),
                const TextBlock(id: 'b', text: '海风正好。'),
              ],
            ),
          ],
      layout: layout,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

Chapter _chapter(
  String id,
  String title,
  int order, {
  int level = 2,
  String? parentId,
  bool frontMatter = false,
  List<Block> blocks = const <Block>[],
}) => Chapter(
  id: id,
  bookId: 'book-1',
  title: title,
  order: order,
  level: level,
  parentId: parentId,
  frontMatter: frontMatter,
  blocks: blocks,
);

Iterable<String> _names(List<int> bytes) =>
    ZipDecoder().decodeBytes(bytes).map((entry) => entry.name);

String _zipText(List<int> bytes, String name) => utf8.decode(
  ZipDecoder()
      .decodeBytes(bytes)
      .firstWhere((entry) => entry.name == name)
      .content,
);
