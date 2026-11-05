import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bookloom/core/formatting/document_structure.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/formatting/output_file.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/io/safe_zip_archive.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:xml/xml.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _rels = 'http://schemas.openxmlformats.org/package/2006/relationships';

/// Writes minimal editable WordprocessingML to a task-private output path.
/// Cover images, embedded fonts and extra metadata are not represented here.
void writeDocx(ExportSnapshot snapshot, String outputPath) {
  final chapters = orderedChapters(snapshot.book);
  writeStagedFile(outputPath, (candidatePath) {
    _writePackage(candidatePath, snapshot, chapters);
    validateDocx(candidatePath);
  });
}

void _writePackage(
  String path,
  ExportSnapshot snapshot,
  List<Chapter> chapters,
) {
  final documentPath = '$path.document.xml';
  try {
    final document = File(documentPath).openSync(mode: FileMode.write);
    try {
      _writeDocumentXml(document, snapshot, chapters);
      document.flushSync();
    } finally {
      document.closeSync();
    }

    final output = OutputFileStream(path);
    final encoder = ZipEncoder(streamed: true)..startEncode(output, level: 6);
    try {
      void put(String name, String value) =>
          encoder.add(ArchiveFile.string(name, value));
      put('[Content_Types].xml', _contentTypes);
      put('_rels/.rels', _packageRels);
      put('docProps/core.xml', _core(snapshot));
      put(
        'word/styles.xml',
        _styles(snapshot.book.layout, snapshot.book.meta.language),
      );
      put('word/_rels/document.xml.rels', _documentRels);
      encoder.add(
        ArchiveFile.stream('word/document.xml', InputFileStream(documentPath)),
      );
      encoder.endEncode();
    } finally {
      output.closeSync();
    }
  } finally {
    final file = File(documentPath);
    if (file.existsSync()) file.deleteSync();
  }
}

void _writeDocumentXml(
  RandomAccessFile file,
  ExportSnapshot snapshot,
  List<Chapter> chapters,
) {
  final meta = snapshot.book.meta;
  final title = meta.title.trim().isEmpty ? '未命名' : meta.title.trim();
  file.writeStringSync(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="$_w" xmlns:r="$_r"><w:body>',
  );
  file.writeStringSync(_paragraph(title, style: 'Title'));
  if (meta.author.trim().isNotEmpty) {
    file.writeStringSync(
      _paragraph('作者：${meta.author.trim()}', style: 'Author'),
    );
  }
  for (final chapter in chapters) {
    if (!chapter.frontMatter) {
      final style = chapter.level == 1 ? 'Heading1' : 'Heading2';
      file.writeStringSync(
        _heading(
          chapter.title.trim(),
          style,
          separate:
              snapshot.book.layout.separateChapterNumber && chapter.level == 2,
        ),
      );
    }
    for (final block in chapter.blocks) {
      switch (block) {
        case TextBlock(:final text):
          if (text.trim().isNotEmpty) file.writeStringSync(_paragraph(text));
        case FootnoteBlock(:final text, :final marker):
          file.writeStringSync(
            _paragraph('${marker == null ? '' : '$marker '}$text'),
          );
        case DividerBlock():
          file.writeStringSync(_paragraph('* * *'));
        case ImageBlock():
          throw StateError('Image block should have been rejected');
      }
    }
  }
  file.writeStringSync(
    '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
    'w:header="851" w:footer="992" w:gutter="0"/></w:sectPr>'
    '</w:body></w:document>',
  );
}

String _paragraph(String text, {String? style}) =>
    '<w:p>${style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>'}'
    '<w:r><w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r></w:p>';

String _heading(String title, String style, {required bool separate}) {
  final match = separate
      ? RegExp(r'^(第\s*[0-9零〇一二三四五六七八九十百千万两]+\s*[章节回话])\s*(\S.*)$')
            .firstMatch(title)
      : null;
  if (match == null) return _paragraph(title, style: style);
  return '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>'
      '<w:r><w:t xml:space="preserve">${xmlEscape(match[1]!)}</w:t></w:r>'
      '<w:r><w:br/></w:r>'
      '<w:r><w:t xml:space="preserve">${xmlEscape(match[2]!)}</w:t></w:r></w:p>';
}

String _styles(LayoutOptions layout, String language) {
  final font = switch (layout.font) {
    LayoutFont.serif => ('宋体', 'Times New Roman'),
    LayoutFont.sans => ('黑体', 'Arial'),
    LayoutFont.kai => ('楷体', 'Times New Roman'),
  };
  final fonts =
      '<w:rFonts w:ascii="${font.$2}" w:hAnsi="${font.$2}" '
      'w:eastAsia="${font.$1}"/>';
  final line = (layout.lineHeight * 240).round();
  final after = (layout.paragraphSpacing * 240).round();
  final indent = layout.indent ? 480 : 0;
  final justify = layout.justify ? 'both' : 'left';
  final lang = xmlEscape(language.trim().isEmpty ? 'zh-CN' : language.trim());
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="$_w">'
      '<w:docDefaults><w:rPrDefault><w:rPr>$fonts<w:sz w:val="24"/>'
      '<w:lang w:val="$lang" w:eastAsia="$lang"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:line="$line" w:lineRule="auto" '
      'w:after="$after"/><w:jc w:val="$justify"/></w:pPr></w:pPrDefault>'
      '</w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/><w:pPr><w:ind w:firstLine="$indent"/>'
      '<w:spacing w:line="$line" w:lineRule="auto" w:after="$after"/>'
      '<w:jc w:val="$justify"/></w:pPr><w:rPr>$fonts</w:rPr></w:style>'
      '${_paragraphStyle('Title', 'Title', font: fonts, size: 44, before: 240, after: 240)}'
      '${_paragraphStyle('Author', 'Author', font: fonts, size: 24, after: 240)}'
      '${_paragraphStyle('Heading1', 'heading 1', font: fonts, size: 36, before: 480, after: 240, outline: 0)}'
      '${_paragraphStyle('Heading2', 'heading 2', font: fonts, size: 30, before: 360, after: 180, outline: 1)}'
      '</w:styles>';
}

String _paragraphStyle(
  String id,
  String name, {
  required String font,
  required int size,
  int before = 0,
  int after = 0,
  int? outline,
}) =>
    '<w:style w:type="paragraph" w:styleId="$id">'
    '<w:name w:val="$name"/><w:basedOn w:val="Normal"/>'
    '<w:next w:val="Normal"/><w:pPr>'
    '${outline == null ? '' : '<w:keepNext/><w:outlineLvl w:val="$outline"/>'}'
    '<w:ind w:firstLine="0"/><w:jc w:val="center"/>'
    '<w:spacing w:before="$before" w:after="$after"/></w:pPr>'
    '<w:rPr>$font${outline == null ? '' : '<w:b/>'}'
    '<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr></w:style>';

String _core(ExportSnapshot snapshot) {
  final meta = snapshot.book.meta;
  final title = meta.title.trim().isEmpty ? '未命名' : meta.title.trim();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>${xmlEscape(title)}</dc:title>'
      '${meta.author.trim().isEmpty ? '' : '<dc:creator>${xmlEscape(meta.author.trim())}</dc:creator>'}'
      '<dc:language>${xmlEscape(meta.language.trim().isEmpty ? 'zh-CN' : meta.language.trim())}</dc:language>'
      '</cp:coreProperties>';
}

const _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '</Types>';

const _packageRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="$_rels">'
    '<Relationship Id="rId1" Type="$_r/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="$_rels/metadata/core-properties" Target="docProps/core.xml"/>'
    '</Relationships>';

const _documentRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="$_rels">'
    '<Relationship Id="rId1" Type="$_r/styles" Target="styles.xml"/>'
    '</Relationships>';

/// Bounded structural validation of the OOXML package, not a Word open test.
void validateDocx(String path) {
  const limits = InputLimits(
    maxArchiveBytes: 128 * 1024 * 1024,
    maxEntries: 100,
    maxEntryBytes: 32 * 1024 * 1024,
    maxOutputBytes: 64 * 1024 * 1024,
    maxXmlBytes: 32 * 1024 * 1024,
    maxXmlDepth: 128,
    maxXmlContentCharacters: 32 * 1024 * 1024,
  );
  final zip = SafeZipArchive.open(path, limits: limits);
  try {
    const required = <String>{
      '[Content_Types].xml',
      '_rels/.rels',
      'docProps/core.xml',
      'word/document.xml',
      'word/styles.xml',
      'word/_rels/document.xml.rels',
    };
    final names = <String>{for (final entry in zip.entries) entry.name};
    if (!names.containsAll(required)) {
      throw const FormatException('Incomplete DOCX package');
    }
    final types = zip.readXml('[Content_Types].xml');
    for (final part in <String>[
      '/word/document.xml',
      '/word/styles.xml',
      '/docProps/core.xml',
    ]) {
      if (!types
          .findAllElements('Override', namespaceUri: '*')
          .any((element) => element.getAttribute('PartName') == part)) {
        throw FormatException('Missing DOCX content type: $part');
      }
    }
    final rels = zip.readXml('_rels/.rels');
    if (!rels
        .findAllElements('Relationship', namespaceUri: '*')
        .any(
          (element) => element.getAttribute('Target') == 'word/document.xml',
        )) {
      throw const FormatException('Missing DOCX document relationship');
    }
    final wordRels = zip.readXml('word/_rels/document.xml.rels');
    if (!wordRels
        .findAllElements('Relationship', namespaceUri: '*')
        .any((element) => element.getAttribute('Target') == 'styles.xml')) {
      throw const FormatException('Missing DOCX styles relationship');
    }
    final styles = zip.readXml('word/styles.xml');
    final styleIds = <String>{
      for (final element in styles.findAllElements('style', namespaceUri: '*'))
        if (element.getAttribute('styleId', namespaceUri: _w)
            case final String id)
          id,
    };
    if (!styleIds.containsAll(<String>{
      'Normal',
      'Title',
      'Heading1',
      'Heading2',
    })) {
      throw const FormatException('Missing DOCX paragraph styles');
    }
    final document = zip.readXml('word/document.xml');
    if (document.rootElement.name.local != 'document' ||
        document.findAllElements('body', namespaceUri: '*').length != 1 ||
        document.findAllElements('sectPr', namespaceUri: '*').length != 1) {
      throw const FormatException('Invalid DOCX document body');
    }
    zip.readXml('docProps/core.xml');
  } finally {
    zip.close();
  }
}
