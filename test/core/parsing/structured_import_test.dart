import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/parsing/structured_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory taskDirectory;

  setUp(() {
    taskDirectory = Directory.systemTemp.createTempSync('bookloom-structure-');
  });
  tearDown(() {
    if (taskDirectory.existsSync()) taskDirectory.deleteSync(recursive: true);
  });

  File zipFile(String filename, Map<String, List<int>> entries) {
    final data = archive.Archive();
    for (final entry in entries.entries) {
      data.add(archive.ArchiveFile.bytes(entry.key, entry.value));
    }
    final file = File('${taskDirectory.path}/$filename');
    file.writeAsBytesSync(archive.ZipEncoder().encode(data));
    return file;
  }

  Map<String, List<int>> strings(Map<String, String> entries) => {
    for (final entry in entries.entries) entry.key: utf8.encode(entry.value),
  };

  String text(StructuredImport parsed) => parsed.result.chapters
      .expand((chapter) => chapter.blocks)
      .whereType<TextBlock>()
      .map((block) => block.text)
      .join('\n');

  const container =
      '<container><rootfiles><rootfile full-path="OPS/package.opf"/>'
      '</rootfiles></container>';
  const chapterOne =
      '<html><body><h1 id="one">忽略的章名</h1><p>第一段正文。</p>'
      '<script>不要导入脚本</script><img src="illustration.png"/></body></html>';
  const chapterTwo = '<html><body><p>第二段正文。</p></body></html>';
  const nav =
      '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
      '<nav epub:type="toc"><ol>'
      '<li><a href="Text/ch%201.xhtml#one">目录第一章</a></li>'
      '<li><a href="Text/ch2.xhtml">目录第二章</a></li>'
      '</ol></nav></body></html>';
  const ncx =
      '<ncx><navMap><navPoint><navLabel><text>错误 NCX 标题</text>'
      '</navLabel><content src="Text/ch%201.xhtml"/></navPoint>'
      '</navMap></ncx>';
  const opf =
      '<package xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<metadata><dc:title>测试书</dc:title><dc:creator>作者</dc:creator>'
      '<dc:language>zh-CN</dc:language><dc:subject>小说</dc:subject>'
      '<meta name="calibre:series" content="系列甲"/>'
      '<meta name="cover" content="cover"/></metadata>'
      '<manifest>'
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
      '<item id="one" href="Text/ch%201.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="two" href="Text/ch2.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="cover" href="cover.png" media-type="image/png"/>'
      '</manifest><spine toc="ncx"><itemref idref="nav"/>'
      '<itemref idref="one"/><itemref idref="two"/></spine></package>';

  test('EPUB follows nav and spine, stages cover, keeps metadata', () {
    final cover = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9m3x8AAAAASUVORK5CYII=',
    );
    final file = zipFile('novel.epub', {
      ...strings({
        'META-INF/container.xml': container,
        'OPS/package.opf': opf,
        'OPS/nav.xhtml': nav,
        'OPS/toc.ncx': ncx,
        'OPS/Text/ch 1.xhtml': chapterOne,
        'OPS/Text/ch2.xhtml': chapterTwo,
      }),
      'OPS/cover.png': cover,
    });
    final result = parseStructuredFileSync(
      file.path,
      bookId: 'book-1',
      filename: 'novel.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(result.result.suggestedMeta.title, '测试书');
    expect(result.result.suggestedMeta.author, '作者');
    expect(result.result.suggestedMeta.series, '系列甲');
    expect(result.result.chapters.map((chapter) => chapter.title), [
      '目录第一章',
      '目录第二章',
    ]);
    expect(text(result), contains('第一段正文。'));
    expect(text(result), contains('第二段正文。'));
    expect(text(result), isNot(contains('不要导入脚本')));
    expect(text(result), isNot(contains('目录第一章')));
    expect(
      result.result.warnings.map((warning) => warning.code),
      containsAll(['lost_scripts', 'lost_images']),
    );
    expect(result.cover?.mime, 'image/png');
    expect(result.cover?.width, 1);
    expect(result.cover?.file.readAsBytesSync(), cover);
  });

  test('EPUB preserves paragraph text and warns once for an inline image', () {
    final file = zipFile(
      'inline-image.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf':
            '<package><manifest><item id="body" href="body.xhtml" '
            'media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="body"/></spine></package>',
        'OPS/body.xhtml':
            '<html><body><p>图示前<img src="a.png"/>图示后</p></body></html>',
      }),
    );
    final parsed = parseStructuredFileSync(
      file.path,
      bookId: 'book-inline-image',
      filename: 'inline-image.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(text(parsed), '图示前图示后');
    expect(
      parsed.result.warnings.where((warning) => warning.code == 'lost_images'),
      hasLength(1),
    );
  });

  test('EPUB resolves a TOC anchor nested inside a heading', () {
    final file = zipFile(
      'nested-anchor.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf':
            '<package><manifest>'
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="body" href="body.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest><spine><itemref idref="body"/></spine></package>',
        'OPS/nav.xhtml':
            '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
            '<nav epub:type="toc"><ol><li><a href="body.xhtml#ch1">目录章名</a>'
            '</li></ol></nav></body></html>',
        'OPS/body.xhtml':
            '<html><body><h2><span id="ch1">正文标题</span></h2>'
            '<p>正文内容</p></body></html>',
      }),
    );
    final parsed = parseStructuredFileSync(
      file.path,
      bookId: 'book-nested-anchor',
      filename: 'nested-anchor.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(parsed.result.chapters.single.title, '目录章名');
    expect(parsed.result.chapters.single.frontMatter, isFalse);
    expect(text(parsed), '正文内容');
    expect(
      parsed.result.warnings.map((warning) => warning.code),
      isNot(contains('unresolved_toc')),
    );
  });

  test('EPUB resolves a TOC anchor nested inside a paragraph', () {
    final file = zipFile(
      'paragraph-anchor.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf':
            '<package><manifest>'
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="body" href="body.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest><spine><itemref idref="body"/></spine></package>',
        'OPS/nav.xhtml':
            '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
            '<nav epub:type="toc"><ol><li><a href="body.xhtml#ch1">目录章名</a>'
            '</li></ol></nav></body></html>',
        'OPS/body.xhtml':
            '<html><body><p><a id="ch1"></a>正文开头</p></body></html>',
      }),
    );
    final parsed = parseStructuredFileSync(
      file.path,
      bookId: 'book-paragraph-anchor',
      filename: 'paragraph-anchor.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(parsed.result.chapters.single.title, '目录章名');
    expect(parsed.result.chapters.single.frontMatter, isFalse);
    expect(text(parsed), '正文开头');
    expect(
      parsed.result.warnings.map((warning) => warning.code),
      isNot(contains('unresolved_toc')),
    );
  });

  test('EPUB 3 skips semantic spine toc and cover pages', () {
    final file = zipFile(
      'semantic-epub3.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf':
            '<package><manifest>'
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="toc" href="text/toc.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="body" href="text/body.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest><spine><itemref idref="cover"/><itemref idref="toc"/>'
            '<itemref idref="body"/></spine>'
            '<guide><reference type="cover" href="text/cover.xhtml"/>'
            '<reference type="toc" href="text/toc.xhtml"/></guide></package>',
        'OPS/nav.xhtml':
            '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
            '<nav epub:type="toc"><ol><li><a href="text/body.xhtml#ch">正文目录名</a></li></ol></nav>'
            '<nav epub:type="landmarks"><ol>'
            '<li><a epub:type="cover" href="text/cover.xhtml">封面</a></li>'
            '<li><a epub:type="toc" href="text/toc.xhtml">目录</a></li>'
            '</ol></nav></body></html>',
        'OPS/text/cover.xhtml':
            '<html><body><div><img src="../cover.png"/></div></body></html>',
        'OPS/text/toc.xhtml':
            '<html><body><div><h1>目录</h1><ol>'
            '<li><a href="body.xhtml#ch">重复目录项</a></li>'
            '</ol></div></body></html>',
        'OPS/text/body.xhtml':
            '<html><body><h1 id="ch">正文标题</h1><p>唯一正文</p></body></html>',
      }),
    );
    final parsed = parseStructuredFileSync(
      file.path,
      bookId: 'book-semantic-3',
      filename: 'semantic-epub3.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(parsed.result.chapters.map((chapter) => chapter.title), ['正文目录名']);
    expect(text(parsed), '唯一正文');
    expect(
      parsed.result.warnings.map((warning) => warning.code),
      isNot(contains('lost_images')),
    );
  });

  test('EPUB keeps prose outside nav in a manifest nav spine page', () {
    final file = zipFile(
      'mixed-nav.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf':
            '<package><manifest>'
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="body" href="body.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest><spine><itemref idref="nav"/><itemref idref="body"/></spine></package>',
        'OPS/nav.xhtml':
            '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
            '<nav epub:type="toc"><ol><li><a href="body.xhtml#ch">目录项</a></li></ol></nav>'
            '<p>导航页外的前言</p></body></html>',
        'OPS/body.xhtml':
            '<html><body><h1 id="ch">原标题</h1><p>正文内容</p></body></html>',
      }),
    );
    final parsed = parseStructuredFileSync(
      file.path,
      bookId: 'book-mixed-nav',
      filename: 'mixed-nav.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(text(parsed), '导航页外的前言\n正文内容');
    expect(text(parsed), isNot(contains('目录项')));
    expect(parsed.result.chapters.first.frontMatter, isTrue);
  });

  test(
    'EPUB 2 guide skips toc but retains extra prose and ordinary toc name',
    () {
      final guided = zipFile(
        'semantic-epub2.epub',
        strings({
          'META-INF/container.xml': container,
          'OPS/package.opf':
              '<package version="2.0"><manifest>'
              '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
              '<item id="toc" href="text/toc.xhtml" media-type="application/xhtml+xml"/>'
              '<item id="body" href="text/body.xhtml" media-type="application/xhtml+xml"/>'
              '</manifest><spine toc="ncx"><itemref idref="toc"/><itemref idref="body"/></spine>'
              '<guide><reference type="toc" href="text/toc.xhtml"/></guide></package>',
          'OPS/toc.ncx':
              '<ncx><navMap><navPoint><navLabel><text>正文章</text></navLabel>'
              '<content src="text/body.xhtml#ch"/></navPoint></navMap></ncx>',
          'OPS/text/toc.xhtml':
              '<html><body><h1>目录</h1><ol>'
              '<li><a href="body.xhtml#ch">重复目录项</a></li>'
              '<li><a href="body.xhtml#ch">链接名</a>叙事尾巴</li>'
              '</ol>'
              '<p>保留的前言</p></body></html>',
          'OPS/text/body.xhtml':
              '<html><body><h1 id="ch">正文标题</h1><p>正文内容</p></body></html>',
        }),
      );
      final parsed = parseStructuredFileSync(
        guided.path,
        bookId: 'book-semantic-2',
        filename: 'semantic-epub2.epub',
        temporaryDirectory: taskDirectory,
      );
      expect(text(parsed), '链接名叙事尾巴\n保留的前言\n正文内容');
      expect(text(parsed), isNot(contains('重复目录项')));
      expect(
        parsed.result.warnings.map((warning) => warning.code),
        contains('ambiguous_toc_content'),
      );

      final ordinary = zipFile(
        'ordinary-toc-name.epub',
        strings({
          'META-INF/container.xml': container,
          'OPS/package.opf':
              '<package><manifest><item id="body" href="text/toc.xhtml" '
              'media-type="application/xhtml+xml"/></manifest>'
              '<spine><itemref idref="body"/></spine></package>',
          'OPS/text/toc.xhtml':
              '<html><body><h1>目录</h1><p>这本来就是正文</p></body></html>',
        }),
      );
      final second = parseStructuredFileSync(
        ordinary.path,
        bookId: 'book-ordinary-name',
        filename: 'ordinary-toc-name.epub',
        temporaryDirectory: taskDirectory,
      );
      expect(second.result.chapters.single.title, '目录');
      expect(text(second), '这本来就是正文');
    },
  );

  test('EPUB falls back from nav to NCX, then to headings', () {
    final ncxOnly = zipFile(
      'ncx.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf': opf
            .replaceFirst(' properties="nav"', '')
            .replaceFirst('<meta name="cover" content="cover"/>', '')
            .replaceFirst(
              '<item id="cover" href="cover.png" media-type="image/png"/>',
              '',
            ),
        'OPS/nav.xhtml': nav,
        'OPS/toc.ncx': ncx,
        'OPS/Text/ch 1.xhtml': chapterOne,
        'OPS/Text/ch2.xhtml': chapterTwo,
      }),
    );
    final first = parseStructuredFileSync(
      ncxOnly.path,
      bookId: 'book-2',
      filename: 'ncx.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(first.result.chapters.first.title, '错误 NCX 标题');

    final headingsOnly = zipFile(
      'headings.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf':
            '<package><metadata><title>无目录</title></metadata><manifest>'
            '<item id="one" href="Text/ch%201.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest><spine><itemref idref="one"/></spine></package>',
        'OPS/Text/ch 1.xhtml': chapterOne,
      }),
    );
    final second = parseStructuredFileSync(
      headingsOnly.path,
      bookId: 'book-3',
      filename: 'headings.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(second.result.chapters.first.title, '忽略的章名');
  });

  test('EPUB rejects DRM and XML DTD', () {
    final drm = zipFile(
      'drm.epub',
      strings({'META-INF/rights.xml': '<rights/>'}),
    );
    expect(
      () => parseStructuredFileSync(
        drm.path,
        bookId: 'book-4',
        filename: 'drm.epub',
        temporaryDirectory: taskDirectory,
      ),
      throwsA(isA<ImportFailure>()),
    );
    final dtd = zipFile(
      'dtd.epub',
      strings({
        'META-INF/container.xml':
            '<!DOCTYPE a [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
            '<container><rootfiles><rootfile full-path="OPS/package.opf"/>'
            '</rootfiles></container>',
      }),
    );
    expect(
      () => parseStructuredFileSync(
        dtd.path,
        bookId: 'book-5',
        filename: 'dtd.epub',
        temporaryDirectory: taskDirectory,
      ),
      throwsA(isA<ImportFailure>()),
    );
  });

  test('EPUB skips SVG cover and rejects escaping manifest paths', () {
    final svgOpf = opf.replaceFirst(
      'href="cover.png" media-type="image/png"',
      'href="cover.svg" media-type="image/svg+xml"',
    );
    final svgFile = zipFile(
      'svg.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf': svgOpf,
        'OPS/nav.xhtml': nav,
        'OPS/toc.ncx': ncx,
        'OPS/Text/ch 1.xhtml': chapterOne,
        'OPS/Text/ch2.xhtml': chapterTwo,
        'OPS/cover.svg': '<svg><script>do not run</script></svg>',
      }),
    );
    final parsed = parseStructuredFileSync(
      svgFile.path,
      bookId: 'book-svg',
      filename: 'svg.epub',
      temporaryDirectory: taskDirectory,
    );
    expect(parsed.cover, isNull);
    expect(
      parsed.result.warnings.map((warning) => warning.code),
      contains('lost_cover'),
    );

    final escapeFile = zipFile(
      'escape.epub',
      strings({
        'META-INF/container.xml': container,
        'OPS/package.opf':
            '<package><manifest><item id="body" href="%2e%2e/%2e%2e/x.xhtml" '
            'media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="body"/></spine></package>',
      }),
    );
    expect(
      () => parseStructuredFileSync(
        escapeFile.path,
        bookId: 'book-escape',
        filename: 'escape.epub',
        temporaryDirectory: taskDirectory,
      ),
      throwsA(isA<ImportFailure>()),
    );
  });

  const styles =
      '<styles><style styleId="Heading1"><name val="一级标题"/></style>'
      '<style styleId="Heading2"><name val="Heading 2"/></style>'
      '<style styleId="Custom"><pPr><outlineLvl val="0"/></pPr></style>'
      '</styles>';
  const core =
      '<cp:coreProperties xmlns:cp="x" xmlns:dc="y">'
      '<dc:title>文档书</dc:title><dc:creator>文档作者</dc:creator>'
      '</cp:coreProperties>';
  String paragraph(String value, [String? style]) =>
      '<p>${style == null ? '' : '<pPr><pStyle val="$style"/></pPr>'}'
      '<r><t>$value</t></r></p>';

  test('DOCX local heading 1 becomes chapters without heading 2', () {
    final file = zipFile(
      'one.docx',
      strings({
        'word/document.xml':
            '<document><body>${paragraph('前面的话')}${paragraph('第一章', 'Heading1')}'
            '${paragraph('正文一')}${paragraph('第二章', 'Heading1')}'
            '${paragraph('正文二')}</body></document>',
        'word/styles.xml': styles,
        'docProps/core.xml': core,
      }),
    );
    final parsed = parseStructuredFileSync(
      file.path,
      bookId: 'book-6',
      filename: 'one.docx',
      temporaryDirectory: taskDirectory,
    );
    expect(parsed.result.suggestedMeta.title, '文档书');
    expect(parsed.result.suggestedMeta.author, '文档作者');
    expect(parsed.result.chapters.map((chapter) => chapter.title), [
      '前言',
      '第一章',
      '第二章',
    ]);
    expect(parsed.result.chapters.first.frontMatter, isTrue);
    expect(
      parsed.result.chapters.every((chapter) => !chapter.isVolume),
      isTrue,
    );
  });

  test('DOCX heading 1 with heading 2 forms volumes and warns on loss', () {
    final file = zipFile(
      'two.docx',
      strings({
        'word/document.xml':
            '<document><body>${paragraph('卷一', 'Custom')}'
            '${paragraph('章一', 'Heading2')}${paragraph('内容')}'
            '<tbl><tr><tc>${paragraph('表格文字')}</tc></tr></tbl>'
            '<drawing/><txbxContent>${paragraph('文本框文字')}</txbxContent>'
            '</body></document>',
        'word/styles.xml': styles,
        'word/footnotes.xml': '<footnotes/>',
        'word/header1.xml': '<hdr/>',
      }),
    );
    final parsed = parseStructuredFileSync(
      file.path,
      bookId: 'book-7',
      filename: 'two.docx',
      temporaryDirectory: taskDirectory,
    );
    final volume = parsed.result.chapters.first;
    final chapter = parsed.result.chapters[1];
    expect(volume.title, '卷一');
    expect(volume.isVolume, isTrue);
    expect(chapter.parentId, volume.id);
    expect(text(parsed), contains('表格文字'));
    expect(
      parsed.result.warnings.map((warning) => warning.code),
      containsAll([
        'lost_tables',
        'lost_textboxes',
        'lost_footnotes',
        'lost_headers_footers',
      ]),
    );
  });

  test('DOCX without heading styles imports one chapter with warning', () {
    final file = zipFile(
      'plain.docx',
      strings({
        'word/document.xml':
            '<document><body>${paragraph('没有样式的内容')}</body></document>',
      }),
    );
    final parsed = parseStructuredFileSync(
      file.path,
      bookId: 'book-8',
      filename: 'plain.docx',
      temporaryDirectory: taskDirectory,
    );
    expect(parsed.result.chapters.single.title, '正文');
    expect(
      parsed.result.warnings.map((warning) => warning.code),
      contains('no_headings'),
    );
  });
}
