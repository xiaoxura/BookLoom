import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/formatting/epub/epub_export.dart';
import 'package:bookloom/core/formatting/epub/epub_validator.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  late Directory temporary;
  setUp(
    () =>
        temporary = Directory.systemTemp.createTempSync('bookloom-epub-test-'),
  );
  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'writes a stored first mimetype and complete, linked EPUB 3 structure',
    () {
      final output = '${temporary.path}/book.epub';
      final book = _book(<Chapter>[
        _chapter(
          'preface',
          '前言',
          0,
          frontMatter: true,
          blocks: <Block>[const TextBlock(id: 'p1', text: '无题序文 & <海>。')],
        ),
        _chapter('volume', '第一卷 潮声', 1, level: 1),
        _chapter(
          'first',
          '第一章 守塔人',
          2,
          parentId: 'volume',
          blocks: <Block>[const TextBlock(id: 'p2', text: '夜里有灯。')],
        ),
        _chapter(
          'second',
          '第二章 归航',
          3,
          parentId: 'volume',
          blocks: <Block>[const TextBlock(id: 'p3', text: '船回来了。')],
        ),
      ]);
      writeEpub(ExportSnapshot(book: book), output);
      expect(() => validateEpub(output), returnsNormally);

      final bytes = File(output).readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(0, Endian.little), 0x04034b50);
      expect(header.getUint16(8, Endian.little), 0);
      expect(_text(bytes, 'mimetype'), 'application/epub+zip');
      final opf = _text(bytes, 'OEBPS/content.opf');
      expect(opf, contains('version="3.0"'));
      expect(opf, contains('properties="nav"'));
      expect(opf, contains('application/x-dtbncx+xml'));
      expect(opf, contains('id="toc-page" href="text/toc.xhtml"'));
      expect(_text(bytes, 'OEBPS/nav.xhtml'), contains('epub:type="toc"'));
      expect(_text(bytes, 'OEBPS/toc.ncx'), contains('<navPoint'));
      final toc = _text(bytes, 'OEBPS/text/toc.xhtml');
      expect(toc, contains('第一卷 潮声'));
      expect(toc, contains('第一章 守塔人'));
      expect(toc, contains('href="../text/c0003-1.xhtml#heading"'));
      expect(
        _text(bytes, 'OEBPS/text/c0001-1.xhtml'),
        isNot(contains('<h2 id="heading"')),
      );
      expect(
        _text(bytes, 'OEBPS/text/c0001-1.xhtml'),
        contains('无题序文 &amp; &lt;海&gt;。'),
      );
      expect(
        _text(bytes, 'OEBPS/text/c0003-1.xhtml'),
        contains('<h2 id="heading" class="chapter-title">第一章 守塔人</h2>'),
      );
    },
  );

  test(
    'escapes metadata and body, preserves calendar date and embeds assets',
    () {
      final output = '${temporary.path}/assets.epub';
      final book = _book(
        <Chapter>[
          _chapter(
            'one',
            '第1章 A & B <测试>',
            0,
            blocks: <Block>[
              const TextBlock(id: 'p1', text: 'x < y && y > z\u0001。'),
              const DividerBlock(id: 'd1'),
              const FootnoteBlock(id: 'f1', text: '注释 & 更多', marker: '*'),
            ],
          ),
        ],
        meta: BookMeta(
          title: '标题 & <符号>',
          author: '作者"甲',
          language: 'zh-CN',
          description: '简介 & <词>',
          publisher: '出版社',
          series: '系列 <甲>',
          tags: <String>['海洋', '海洋', '航行'],
          publishedAt: DateTime(2026, 1, 2),
        ),
        layout: LayoutOptions(
          separateChapterNumber: true,
          embeddedFontAssetId: 'font-a',
          customCss: '.extra { color: #345; }',
        ),
      );
      final cover = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/W9sAAAAASUVORK5CYII=',
        ),
      );
      final font = ExportFont(
        assetId: 'font-a',
        fileName: 'Own.ttf',
        bytes: Uint8List.fromList(<int>[0, 1, 0, 0]),
      );
      writeEpub(
        ExportSnapshot(
          book: book,
          coverBytes: cover,
          coverMime: 'image/png',
          fonts: <ExportFont>[font],
        ),
        output,
      );
      expect(() => validateEpub(output), returnsNormally);
      final bytes = File(output).readAsBytesSync();
      final opf = _text(bytes, 'OEBPS/content.opf');
      expect(opf, contains('<dc:title>标题 &amp; &lt;符号&gt;</dc:title>'));
      expect(opf, contains('<dc:creator>作者&quot;甲</dc:creator>'));
      expect(opf, contains('<dc:date>2026-01-02</dc:date>'));
      expect(opf, contains('belongs-to-collection'));
      expect(RegExp('<dc:subject>').allMatches(opf).length, 2);
      expect(opf, contains('properties="cover-image"'));
      expect(opf, contains('href="fonts/font-1.ttf"'));
      final chapter = _text(bytes, 'OEBPS/text/c0001-1.xhtml');
      expect(chapter, contains('x &lt; y &amp;&amp; y &gt; z。'));
      expect(chapter, contains('class="chapter-number">第1章</span>'));
      expect(chapter, contains('epub:type="footnote"'));
      expect(
        _text(bytes, 'OEBPS/styles/style.css'),
        contains('../fonts/font-1.ttf'),
      );
      expect(
        _text(bytes, 'OEBPS/styles/style.css'),
        contains('.extra { color: #345; }'),
      );
      expect(_entry(bytes, 'OEBPS/images/cover.png').content, cover);
    },
  );

  test('splits only above 40000 non-whitespace runes, at block boundaries', () {
    final body = List<String>.filled(39999, '字').join();
    final output = '${temporary.path}/long.epub';
    final book = _book(<Chapter>[
      _chapter(
        'long',
        '长章',
        0,
        blocks: <Block>[
          TextBlock(id: 'a', text: '$body\u2003😀'),
          const TextBlock(id: 'b', text: '尾'),
        ],
      ),
    ]);
    writeEpub(ExportSnapshot(book: book), output);
    final bytes = File(output).readAsBytesSync();
    expect(
      _entryNames(bytes).where((name) => name.startsWith('OEBPS/text/c0001-')),
      <String>['OEBPS/text/c0001-1.xhtml', 'OEBPS/text/c0001-2.xhtml'],
    );
    expect(_text(bytes, 'OEBPS/text/c0001-1.xhtml'), contains('$body\u2003😀'));
    expect(_text(bytes, 'OEBPS/text/c0001-2.xhtml'), contains('<p>尾</p>'));
    expect(
      RegExp('<navPoint ').allMatches(_text(bytes, 'OEBPS/toc.ncx')).length,
      1,
    );
    expect(
      RegExp('<li>').allMatches(_text(bytes, 'OEBPS/text/toc.xhtml')).length,
      1,
    );

    final exact = '${temporary.path}/exact.epub';
    writeEpub(
      ExportSnapshot(
        book: _book(<Chapter>[
          _chapter(
            'exact',
            '边界',
            0,
            blocks: <Block>[
              TextBlock(id: 'a', text: body),
              const TextBlock(id: 'b', text: '字'),
            ],
          ),
        ]),
      ),
      exact,
    );
    expect(
      _entryNames(File(exact).readAsBytesSync())
          .where((name) => name.startsWith('OEBPS/text/c0001-'))
          .length,
      1,
    );
  });

  test(
    'rejects invalid hierarchy and an existing destination without changing it',
    () {
      final output = '${temporary.path}/invalid.epub';
      expect(
        () => writeEpub(
          ExportSnapshot(
            book: _book(<Chapter>[
              _chapter('orphan', '孤章', 0, parentId: 'missing'),
            ]),
          ),
          output,
        ),
        throwsArgumentError,
      );
      expect(File(output).existsSync(), isFalse);
      File(output).writeAsStringSync('keep');
      expect(
        () => writeEpub(
          ExportSnapshot(book: _book(<Chapter>[_chapter('valid', '有效', 0)])),
          output,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(output).readAsStringSync(), 'keep');
    },
  );

  test('exports a book without an author', () {
    final output = '${temporary.path}/anonymous.epub';
    writeEpub(
      ExportSnapshot(
        book: _book(<Chapter>[
          _chapter(
            'one',
            '短章',
            0,
            blocks: <Block>[const TextBlock(id: 'p', text: '短文。')],
          ),
        ], meta: BookMeta(title: '无署名短篇')),
      ),
      output,
    );
    expect(() => validateEpub(output), returnsNormally);
    expect(
      _text(File(output).readAsBytesSync(), 'OEBPS/content.opf'),
      isNot(contains('<dc:creator>')),
    );
  });

  test('GIF and WebP covers normalize to matching JPEG bytes and MIME in both EPUB versions', () {
    final source = image.Image(width: 2, height: 2, numChannels: 3);
    image.fill(source, color: image.ColorRgb8(24, 75, 120));
    final covers = <(String, Uint8List)>[
      ('image/gif', image.encodeGif(source)),
      ('image/webp', image.encodeWebP(source)),
    ];
    for (final (mime, bytes) in covers) {
      for (final format in <ExportFormat>[
        ExportFormat.epub2,
        ExportFormat.epub3,
      ]) {
        final output =
            '${temporary.path}/${format.name}-${mime.split('/').last}.epub';
        writeDocument(
          ExportSnapshot(
            book: _book(<Chapter>[
              _chapter(
                'one',
                '第一章',
                0,
                blocks: <Block>[const TextBlock(id: 'body', text: '这是一篇自编短文。')],
              ),
            ]),
            coverBytes: bytes,
            coverMime: mime,
          ),
          output,
          format: format,
        );
        expect(
          () => validateEpub(
            output,
            version: format == ExportFormat.epub2 ? 2 : 3,
          ),
          returnsNormally,
        );
        final package = File(output).readAsBytesSync();
        final cover = Uint8List.fromList(
          _entry(package, 'OEBPS/images/cover.jpg').content,
        );
        expect(cover.take(3), <int>[0xff, 0xd8, 0xff]);
        expect(image.decodeJpg(cover)?.width, 2);
        expect(image.decodeJpg(cover)?.height, 2);
        final opf = _text(package, 'OEBPS/content.opf');
        expect(
          opf,
          contains('href="images/cover.jpg" media-type="image/jpeg"'),
        );
        expect(_entryNames(package), isNot(contains('OEBPS/images/cover.gif')));
        expect(
          _entryNames(package),
          isNot(contains('OEBPS/images/cover.webp')),
        );
      }
    }
  });

  test('does not silently discard image blocks without an asset resolver', () {
    final output = '${temporary.path}/image.epub';
    expect(
      () => writeEpub(
        ExportSnapshot(
          book: _book(<Chapter>[
            _chapter(
              'one',
              '插图章',
              0,
              blocks: <Block>[
                const ImageBlock(id: 'image', assetId: 'image-1'),
              ],
            ),
          ]),
        ),
        output,
      ),
      throwsUnsupportedError,
    );
    expect(File(output).existsSync(), isFalse);
    expect(temporary.listSync(), isEmpty);
  });

  test('validator rejects a broken navigation anchor', () {
    final output = '${temporary.path}/valid.epub';
    writeEpub(
      ExportSnapshot(
        book: _book(<Chapter>[
          _chapter(
            'one',
            '一',
            0,
            blocks: <Block>[const TextBlock(id: 'p', text: '正文')],
          ),
        ]),
      ),
      output,
    );
    final original = ZipDecoder().decodeBytes(File(output).readAsBytesSync());
    final broken = Archive();
    for (final entry in original) {
      final content = entry.name == 'OEBPS/nav.xhtml'
          ? utf8.encode(
              utf8.decode(entry.content).replaceFirst('#heading', '#missing'),
            )
          : entry.content;
      final next = ArchiveFile.bytes(entry.name, content);
      if (entry.name == 'mimetype') next.compression = CompressionType.none;
      broken.add(next);
    }
    final badPath = '${temporary.path}/broken.epub';
    File(badPath)
        .writeAsBytesSync(ZipEncoder(streamed: true).encodeBytes(broken));
    expect(() => validateEpub(badPath), throwsFormatException);
  });
}

Book _book(List<Chapter> chapters, {BookMeta? meta, LayoutOptions? layout}) =>
    Book(
      id: 'book-1',
      meta: meta ?? BookMeta(title: '短篇', author: '自编作者'),
      chapters: chapters,
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

ArchiveFile _entry(List<int> bytes, String name) =>
    ZipDecoder().decodeBytes(bytes).firstWhere((entry) => entry.name == name);

Iterable<String> _entryNames(List<int> bytes) =>
    ZipDecoder().decodeBytes(bytes).map((entry) => entry.name);

String _text(List<int> bytes, String name) =>
    utf8.decode(_entry(bytes, name).content);
