import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookloom/core/formatting/document_structure.dart';
import 'package:bookloom/core/formatting/epub/epub_validator.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/formatting/output_file.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:image/image.dart' as image;
import 'package:uuid/uuid.dart';

const int _maxDocumentCharacters = 40000;
const int _maxFontBytes = 20 * 1024 * 1024;

/// Writes an EPUB 3 to a temporary file beside [outputPath], checks its
/// structure, then renames it into place. The caller supplies a task-private
/// directory and owns that directory across worker cancellation. Run this
/// synchronous function in a worker isolate for large books.
void writeEpub(ExportSnapshot snapshot, String outputPath, {int version = 3}) {
  if (version != 3 && version != 2) {
    throw UnsupportedError('EPUB $version export is not implemented');
  }
  final normalized = _normalizeCover(snapshot);
  writeStagedFile(outputPath, (candidatePath) {
    _writePackage(normalized, candidatePath, version: version);
    validateEpub(candidatePath, version: version);
  });
}

/// EPUB 2/3 use a JPEG representation for imported GIF/WebP covers. Decode
/// only frame zero, and reject oversized dimensions before allocating pixels.
ExportSnapshot _normalizeCover(ExportSnapshot snapshot) {
  final bytes = snapshot.coverBytes;
  if (bytes == null ||
      (snapshot.coverMime != 'image/gif' &&
          snapshot.coverMime != 'image/webp')) {
    return snapshot;
  }
  if (bytes.isEmpty || bytes.length > ImportLimits.maxEncodedCoverBytes) {
    throw const FormatException('Cover image exceeds the encoded size budget');
  }
  final image.Image? firstFrame;
  final int width;
  final int height;
  final int x;
  final int y;
  if (snapshot.coverMime == 'image/gif') {
    final decoder = image.GifDecoder()..maxPixels = ImportLimits.maxCoverPixels;
    final info = decoder.startDecode(bytes);
    if (info == null || info.frames.isEmpty) {
      throw const FormatException('Invalid GIF cover');
    }
    width = info.width;
    height = info.height;
    x = info.frames.first.x;
    y = info.frames.first.y;
    firstFrame = decoder.decodeFrame(0);
  } else {
    final decoder = image.WebPDecoder()
      ..maxPixels = ImportLimits.maxCoverPixels;
    final info = decoder.startDecode(bytes);
    if (info == null || (info.hasAnimation && info.frames.isEmpty)) {
      throw const FormatException('Invalid WebP cover');
    }
    width = info.width;
    height = info.height;
    x = info.hasAnimation ? info.frames.first.x : 0;
    y = info.hasAnimation ? info.frames.first.y : 0;
    firstFrame = decoder.decodeFrame(0);
  }
  if (width <= 0 ||
      height <= 0 ||
      width * height > ImportLimits.maxCoverPixels ||
      firstFrame == null) {
    throw const FormatException('Cover dimensions or first frame are invalid');
  }
  final canvas = image.Image(width: width, height: height, numChannels: 3);
  image.fill(canvas, color: image.ColorRgb8(255, 255, 255));
  image.compositeImage(canvas, firstFrame, dstX: x, dstY: y);
  final jpeg = image.encodeJpg(canvas, quality: 85);
  if (jpeg.isEmpty || jpeg.length > ImportLimits.maxFormatEntryBytes) {
    throw const FormatException(
      'Converted cover exceeds the EPUB resource budget',
    );
  }
  return ExportSnapshot(
    book: snapshot.book,
    coverBytes: jpeg,
    coverMime: 'image/jpeg',
    fonts: snapshot.fonts,
  );
}

class _Document {
  const _Document(this.id, this.href, this.chapter, this.part, this.blocks);

  final String id;
  final String href;
  final Chapter chapter;
  final int part;
  final List<Block> blocks;

  String get target =>
      part == 1 && !chapter.frontMatter ? '$href#heading' : href;
}

class _Navigation {
  _Navigation(this.title, this.target);

  final String title;
  final String target;
  final List<_Navigation> children = <_Navigation>[];
}

class _FontResource {
  const _FontResource(this.path, this.mime, this.format, this.font);

  final String path;
  final String mime;
  final String format;
  final ExportFont font;
}

void _writePackage(
  ExportSnapshot snapshot,
  String path, {
  required int version,
}) {
  final chapters = orderedChapters(snapshot.book);
  final docs = _documents(chapters);
  final navigation = _navigation(chapters, docs);
  final fonts = _fonts(snapshot.fonts);
  final selectedFont = _selectedFont(snapshot, fonts);
  final coverPath = _coverPath(snapshot);
  final title = snapshot.book.meta.title.trim().isEmpty
      ? '未命名'
      : snapshot.book.meta.title.trim();
  final author = snapshot.book.meta.author.trim();
  final language = snapshot.book.meta.language.trim().isEmpty
      ? 'zh-CN'
      : snapshot.book.meta.language.trim();
  final identifier = 'urn:uuid:${const Uuid().v4()}';
  final modified =
      '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

  final output = OutputFileStream(path);
  final encoder = ZipEncoder(streamed: true)..startEncode(output, level: 6);
  try {
    void put(String name, String content) =>
        encoder.add(ArchiveFile.string(name, content));
    void putBytes(String name, Uint8List bytes, {bool stored = false}) {
      final file = ArchiveFile.typedData(name, bytes);
      if (stored) file.compression = CompressionType.none;
      encoder.add(file);
    }

    // EPUB's first local entry must be stored and have no data descriptor.
    putBytes(
      'mimetype',
      Uint8List.fromList('application/epub+zip'.codeUnits),
      stored: true,
    );
    put('META-INF/container.xml', _container);
    put(
      'OEBPS/content.opf',
      _opf(
        snapshot,
        docs,
        coverPath,
        fonts,
        title,
        author,
        language,
        identifier,
        modified,
        epub2: version == 2,
      ),
    );
    if (version == 3) {
      put(
        'OEBPS/nav.xhtml',
        _navDocument(navigation, coverPath != null, language),
      );
    }
    put(
      'OEBPS/toc.ncx',
      _ncx(
        navigation,
        title,
        author,
        language,
        identifier,
        epub2: version == 2,
      ),
    );
    put(
      'OEBPS/text/toc.xhtml',
      _xhtml(
        '目录',
        language,
        '../styles/style.css',
        '<div class="toc-page"><h1>目录</h1>${_navList(navigation, prefix: '../')}</div>',
        epub2: version == 2,
      ),
    );
    put(
      'OEBPS/styles/style.css',
      _stylesheet(snapshot.book.layout, selectedFont),
    );
    if (coverPath != null) {
      putBytes('OEBPS/$coverPath', snapshot.coverBytes!, stored: true);
      put(
        'OEBPS/text/cover.xhtml',
        _xhtml(
          '封面',
          language,
          '../styles/style.css',
          '<div class="cover-page"><img src="../$coverPath" alt="封面"/></div>',
          epub2: version == 2,
        ),
      );
    }
    for (final font in fonts) {
      putBytes('OEBPS/${font.path}', font.font.bytes);
    }
    for (final doc in docs) {
      put(
        'OEBPS/${doc.href}',
        _xhtml(
          doc.chapter.title,
          language,
          '../styles/style.css',
          _chapterBody(doc, snapshot.book.layout, epub2: version == 2),
          epub2: version == 2,
        ),
      );
    }
    encoder.endEncode();
  } finally {
    output.closeSync();
  }
}

List<_Document> _documents(List<Chapter> chapters) {
  final docs = <_Document>[];
  for (var chapterIndex = 0; chapterIndex < chapters.length; chapterIndex++) {
    final chapter = chapters[chapterIndex];
    final parts = <List<Block>>[];
    var current = <Block>[];
    var count = 0;
    for (final block in chapter.blocks) {
      if (block is ImageBlock) {
        throw UnsupportedError(
          'Image blocks need an asset resolver: ${block.assetId}',
        );
      }
      final blockCount = block is TextBlock ? WordCount.ofText(block.text) : 0;
      if (current.isNotEmpty && count + blockCount > _maxDocumentCharacters) {
        parts.add(current);
        current = <Block>[];
        count = 0;
      }
      current.add(block);
      count += blockCount;
    }
    parts.add(current);
    for (var partIndex = 0; partIndex < parts.length; partIndex++) {
      final stem =
          'c${(chapterIndex + 1).toString().padLeft(4, '0')}-${partIndex + 1}';
      docs.add(
        _Document(
          'doc${chapterIndex + 1}_${partIndex + 1}',
          'text/$stem.xhtml',
          chapter,
          partIndex + 1,
          parts[partIndex],
        ),
      );
    }
  }
  return docs;
}

List<_Navigation> _navigation(List<Chapter> chapters, List<_Document> docs) {
  final roots = <_Navigation>[];
  final volumes = <String, _Navigation>{};
  var docIndex = 0;
  for (final chapter in chapters) {
    final firstDoc = docs[docIndex];
    final node = _Navigation(
      chapter.title.trim().isEmpty ? '未命名章节' : chapter.title,
      firstDoc.target,
    );
    if (chapter.level == 1) {
      roots.add(node);
      volumes[chapter.id] = node;
    } else if (chapter.parentId != null) {
      volumes[chapter.parentId]!.children.add(node);
    } else {
      roots.add(node);
    }
    while (docIndex < docs.length && docs[docIndex].chapter.id == chapter.id) {
      docIndex++;
    }
  }
  return roots;
}

String? _coverPath(ExportSnapshot snapshot) {
  final bytes = snapshot.coverBytes;
  if (bytes == null) return null;
  if (bytes.isEmpty) throw ArgumentError('Cover image is empty');
  return switch (snapshot.coverMime) {
    'image/jpeg' => 'images/cover.jpg',
    'image/png' => 'images/cover.png',
    _ => throw ArgumentError('Unsupported cover MIME: ${snapshot.coverMime}'),
  };
}

List<_FontResource> _fonts(List<ExportFont> input) {
  final resources = <_FontResource>[];
  final ids = <String>{};
  for (final font in input) {
    if (!ids.add(font.assetId)) throw ArgumentError('Duplicate font asset ID');
    if (font.bytes.isEmpty || font.bytes.length > _maxFontBytes) {
      throw ArgumentError('Font must be 1–20 MiB or less');
    }
    final extension = font.fileName.split('.').last.toLowerCase();
    final kind = switch (extension) {
      'ttf' => ('font/ttf', 'truetype'),
      'otf' => ('font/otf', 'opentype'),
      'woff' => ('font/woff', 'woff'),
      'woff2' => ('font/woff2', 'woff2'),
      _ => throw ArgumentError('Unsupported font format: ${font.fileName}'),
    };
    resources.add(
      _FontResource(
        'fonts/font-${resources.length + 1}.$extension',
        kind.$1,
        kind.$2,
        font,
      ),
    );
  }
  return resources;
}

_FontResource? _selectedFont(
  ExportSnapshot snapshot,
  List<_FontResource> fonts,
) {
  final selected = snapshot.book.layout.embeddedFontAssetId;
  if (selected == null) return null;
  for (final font in fonts) {
    if (font.font.assetId == selected) return font;
  }
  throw ArgumentError('Selected embedded font is missing: $selected');
}

const _container =
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

String _opf(
  ExportSnapshot snapshot,
  List<_Document> docs,
  String? coverPath,
  List<_FontResource> fonts,
  String title,
  String author,
  String language,
  String identifier,
  String modified, {
  required bool epub2,
}) {
  final meta = snapshot.book.meta;
  final metadata = <String>[
    '<dc:identifier id="bookid">${_xml(identifier)}</dc:identifier>',
    '<dc:title>${_xml(title)}</dc:title>',
    if (author.isNotEmpty) '<dc:creator>${_xml(author)}</dc:creator>',
    '<dc:language>${_xml(language)}</dc:language>',
    if (meta.publishedAt case final DateTime date)
      '<dc:date>${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}</dc:date>',
    if (meta.description.trim().isNotEmpty)
      '<dc:description>${_xml(meta.description.trim())}</dc:description>',
    if ((meta.publisher ?? '').trim().isNotEmpty)
      '<dc:publisher>${_xml(meta.publisher!.trim())}</dc:publisher>',
    for (final tag in meta.tags) '<dc:subject>${_xml(tag)}</dc:subject>',
    if (!epub2 && (meta.series ?? '').trim().isNotEmpty) ...<String>[
      '<meta property="belongs-to-collection" id="series">${_xml(meta.series!.trim())}</meta>',
      '<meta refines="#series" property="collection-type">series</meta>',
    ],
    if (!epub2) '<meta property="dcterms:modified">$modified</meta>',
    if (coverPath != null) '<meta name="cover" content="cover-image"/>',
  ];
  final manifest = <String>[
    if (!epub2) '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
    '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
    '<item id="css" href="styles/style.css" media-type="text/css"/>',
    if (coverPath != null) ...<String>[
      '<item id="cover-image" href="$coverPath" media-type="${_xml(snapshot.coverMime)}"${epub2 ? '' : ' properties="cover-image"'}/>',
      '<item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml"/>',
    ],
    '<item id="toc-page" href="text/toc.xhtml" media-type="application/xhtml+xml"/>',
    for (var i = 0; i < fonts.length; i++)
      '<item id="font-${i + 1}" href="${fonts[i].path}" media-type="${fonts[i].mime}"/>',
    for (final doc in docs)
      '<item id="${doc.id}" href="${doc.href}" media-type="application/xhtml+xml"/>',
  ];
  final spine = <String>[
    if (coverPath != null) '<itemref idref="cover"/>',
    '<itemref idref="toc-page"/>',
    for (final doc in docs) '<itemref idref="${doc.id}"/>',
  ];
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="${epub2 ? '2.0' : '3.0'}" '
      'unique-identifier="bookid"${epub2 ? '' : ' xml:lang="${_xml(language)}"'}>'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">${metadata.join()}</metadata>'
      '<manifest>${manifest.join()}</manifest>'
      '<spine toc="ncx">${spine.join()}</spine>'
      '<guide>${coverPath == null ? '' : '<reference type="cover" title="封面" href="text/cover.xhtml"/>'}'
      '<reference type="toc" title="目录" href="text/toc.xhtml"/>'
      '<reference type="text" title="正文" href="${docs.first.href}"/></guide>'
      '</package>';
}

String _navDocument(List<_Navigation> nodes, bool hasCover, String language) {
  final landmarks = <String>[
    if (hasCover)
      '<li><a epub:type="cover" href="text/cover.xhtml">封面</a></li>',
    '<li><a epub:type="bodymatter" href="${nodes.first.target.split('#').first}">正文</a></li>',
  ];
  return _xhtml(
    '目录',
    language,
    'styles/style.css',
    '<nav epub:type="toc" id="toc"><h1>目录</h1>${_navList(nodes, prefix: '')}</nav>'
        '<nav epub:type="landmarks" id="landmarks" hidden="hidden"><ol>${landmarks.join()}</ol></nav>',
  );
}

String _navList(List<_Navigation> nodes, {required String prefix}) =>
    '<ol>${nodes.map((node) => '<li><a href="$prefix${_xml(node.target)}">${_xml(node.title)}</a>'
        '${node.children.isEmpty ? '' : _navList(node.children, prefix: prefix)}</li>').join()}</ol>';

String _ncx(
  List<_Navigation> nodes,
  String title,
  String author,
  String language,
  String identifier, {
  required bool epub2,
}) {
  var order = 0;
  String points(List<_Navigation> values) => values.map((node) {
    final current = ++order;
    return '<navPoint id="np$current" playOrder="$current">'
        '<navLabel><text>${_xml(node.title)}</text></navLabel>'
        '<content src="${_xml(node.target)}"/>${points(node.children)}</navPoint>';
  }).join();
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '${epub2 ? '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">\n' : ''}'
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="${_xml(language)}">'
      '<head><meta name="dtb:uid" content="${_xml(identifier)}"/>'
      '<meta name="dtb:depth" content="2"/>'
      '<meta name="dtb:totalPageCount" content="0"/>'
      '<meta name="dtb:maxPageNumber" content="0"/></head>'
      '<docTitle><text>${_xml(title)}</text></docTitle>'
      '${author.isEmpty ? '' : '<docAuthor><text>${_xml(author)}</text></docAuthor>'}'
      '<navMap>${points(nodes)}</navMap></ncx>';
}

String _xhtml(
  String title,
  String language,
  String cssHref,
  String body, {
  bool epub2 = false,
}) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '${epub2 ? '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n' : ''}'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    '${epub2 ? '' : 'xmlns:epub="http://www.idpf.org/2007/ops" '}'
    'xml:lang="${_xml(language)}"${epub2 ? '' : ' lang="${_xml(language)}"'}>'
    '<head>${epub2 ? '<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>' : '<meta charset="utf-8"/>'}<title>${_xml(title)}</title>'
    '<link rel="stylesheet" type="text/css" href="${_xml(cssHref)}"/></head>'
    '<body>$body</body></html>';

String _chapterBody(_Document doc, LayoutOptions layout, {bool epub2 = false}) {
  final content = StringBuffer();
  if (doc.part == 1 && !doc.chapter.frontMatter) {
    final headingTag = doc.chapter.level == 1 ? 'h1' : 'h2';
    final headingClass = doc.chapter.level == 1
        ? 'volume-title'
        : 'chapter-title';
    content.write('<$headingTag id="heading" class="$headingClass">');
    final match = layout.separateChapterNumber && doc.chapter.level == 2
        ? RegExp(r'^(第\s*[0-9零〇一二三四五六七八九十百千万两]+\s*[章节回话])\s*(\S.*)$')
              .firstMatch(doc.chapter.title)
        : null;
    if (match == null) {
      content.write(_xml(doc.chapter.title));
    } else {
      content.write(
        '<span class="chapter-number">${_xml(match[1]!)}</span>${_xml(match[2]!)}',
      );
    }
    content.write('</$headingTag>');
  }
  for (final block in doc.blocks) {
    switch (block) {
      case TextBlock(:final text):
        content.write('<p>${_xml(text)}</p>');
      case FootnoteBlock(:final text, :final marker):
        content.write(
          epub2
              ? '<div class="footnote"><p>'
              : '<aside epub:type="footnote"><p>',
        );
        if (marker != null) {
          content.write('<span class="note-marker">${_xml(marker)}</span> ');
        }
        content.write('${_xml(text)}</p>${epub2 ? '</div>' : '</aside>'}');
      case DividerBlock():
        content.write('<hr class="scene-break"/>');
      case ImageBlock():
        throw StateError('Image block should have been rejected');
    }
  }
  return epub2
      ? '<div class="chapter">$content</div>'
      : '<section epub:type="${doc.chapter.level == 1 ? 'part' : 'chapter'}">$content</section>';
}

String _stylesheet(LayoutOptions layout, _FontResource? font) {
  final family = switch (layout.font) {
    LayoutFont.serif => '"Songti SC", "Noto Serif CJK SC", "SimSun", serif',
    LayoutFont.sans =>
      '"PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei", sans-serif',
    LayoutFont.kai => '"Kaiti SC", "KaiTi", "STKaiti", serif',
  };
  final embedded = font == null
      ? ''
      : '@font-face { font-family: "EmbeddedFont"; '
            'src: url("../${font.path}") format("${font.format}"); }\n';
  final selected = font == null ? family : '"EmbeddedFont", $family';
  return '@charset "utf-8";\n$embedded'
      'html, body { margin: 0; padding: 0; }\n'
      'body { font-family: $selected; line-height: ${layout.lineHeight}; '
      'text-align: ${layout.justify ? 'justify' : 'left'}; overflow-wrap: break-word; }\n'
      'p { margin: 0 0 ${layout.paragraphSpacing}em; '
      'text-indent: ${layout.indent ? '2em' : '0'}; }\n'
      'h1.volume-title, h2.chapter-title { text-align: center; page-break-before: always; }\n'
      'h1.volume-title { font-size: 1.7em; margin: 3em 0 2em; }\n'
      'h2.chapter-title { font-size: 1.35em; margin: 2em 0 1.2em; }\n'
      '.chapter-number { display: block; font-size: 0.62em; margin-bottom: 0.4em; }\n'
      '.toc-page { padding: 1em 0; } .toc-page li { margin: 0.45em 0; }\n'
      '.toc-page a { color: inherit; text-decoration: none; }\n'
      '.cover-page { text-align: center; } .cover-page img { max-width: 100%; max-height: 100%; }\n'
      '.scene-break { width: 30%; margin: 1.5em auto; }\n'
      '${layout.customCss.trim().isEmpty ? '' : '${layout.customCss}\n'}';
}

String _xml(String value) => xmlEscape(value);
