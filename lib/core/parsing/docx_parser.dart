import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../errors/app_failure.dart';
import '../io/safe_zip_archive.dart';
import '../model/block.dart';
import '../model/chapter.dart';
import '../model/metadata.dart';
import '../model/parse_result.dart';
import 'structured_import.dart';

const _uuid = Uuid();

ParsedStructure parseDocxZip(
  SafeZipArchive zip, {
  required String bookId,
  required String filename,
}) {
  final names = {for (final entry in zip.entries) entry.name};
  if (names.contains('EncryptionInfo') || names.contains('EncryptedPackage')) {
    throw const ImportFailure('此 DOCX 已加密，无法导入。');
  }
  if (!names.contains('word/document.xml')) {
    throw const ImportFailure('DOCX 缺少正文 document.xml。');
  }
  final styles = names.contains('word/styles.xml')
      ? _readStyles(zip.readXml('word/styles.xml'))
      : <String, _Style>{};
  final document = zip.readXml('word/document.xml');
  final body = _elements(document, 'body').firstOrNull;
  if (body == null) throw const ImportFailure('DOCX 正文结构无效。');
  final warnings = <ParseWarning>[];
  void warn(String code, String message, [String? path]) {
    if (!warnings.any((warning) => warning.code == code)) {
      warnings.add(
        ParseWarning(code: code, message: message, sourcePath: path),
      );
    }
  }

  if (_elements(body, 'drawing').isNotEmpty ||
      _elements(body, 'pict').isNotEmpty) {
    warn('lost_images', '文档插图未恢复。', 'word/document.xml');
  }
  if (_elements(body, 'tbl').isNotEmpty) {
    warn('lost_tables', '表格结构已转为普通文字。', 'word/document.xml');
  }
  if (_elements(body, 'txbxContent').isNotEmpty) {
    warn('lost_textboxes', '文本框布局未恢复。', 'word/document.xml');
  }
  if (_elements(body, 'numPr').isNotEmpty) {
    warn('lost_numbering', '自动编号格式未恢复。', 'word/document.xml');
  }
  if (names.contains('word/footnotes.xml') ||
      names.contains('word/endnotes.xml')) {
    warn('lost_footnotes', '脚注和尾注关联未恢复。');
  }
  if (names.any(
        (name) => name.startsWith('word/header') && name.endsWith('.xml'),
      ) ||
      names.any(
        (name) => name.startsWith('word/footer') && name.endsWith('.xml'),
      )) {
    warn('lost_headers_footers', '页眉页脚未恢复。');
  }
  final paragraphs = <_Paragraph>[];
  for (final element in _elements(body, 'p')) {
    final text = _paragraphText(element).trim();
    if (text.isEmpty) continue;
    final properties = element.children
        .whereType<XmlElement>()
        .where((child) => child.name.local == 'pPr')
        .firstOrNull;
    final styleId = properties == null
        ? null
        : _elements(
            properties,
            'pStyle',
          ).map((e) => _attribute(e, 'val')).firstOrNull;
    final directOutline = properties == null
        ? null
        : _elements(
            properties,
            'outlineLvl',
          ).map((e) => int.tryParse(_attribute(e, 'val') ?? '')).firstOrNull;
    final level = directOutline == null
        ? _styleLevel(styleId, styles)
        : directOutline + 1;
    paragraphs.add(_Paragraph(text, level == 1 || level == 2 ? level : null));
  }
  if (paragraphs.isEmpty) throw const ImportFailure('DOCX 没有可导入的文字。');
  if (!paragraphs.any((paragraph) => paragraph.heading == null)) {
    throw const ImportFailure('DOCX 只有标题，没有可导入的正文。');
  }
  final hasH1 = paragraphs.any((paragraph) => paragraph.heading == 1);
  final hasH2 = paragraphs.any((paragraph) => paragraph.heading == 2);
  final hasHeadings = hasH1 || hasH2;
  if (!hasHeadings) {
    warn('no_headings', '没有识别到标题样式，已按单章导入。');
  }
  final drafts = <_ChapterDraft>[];
  _ChapterDraft? current;
  String? volumeId;
  for (final paragraph in paragraphs) {
    final heading = paragraph.heading;
    if (heading != null) {
      final volume = heading == 1 && hasH2;
      current = _ChapterDraft(
        id: _uuid.v4(),
        title: paragraph.text,
        level: volume ? 1 : 2,
        parentId: volume ? null : volumeId,
      );
      if (volume) volumeId = current.id;
      drafts.add(current);
    } else {
      current ??= _ChapterDraft(
        id: _uuid.v4(),
        title: hasHeadings ? '前言' : '正文',
        frontMatter: hasHeadings,
        level: 2,
      );
      if (!drafts.contains(current)) drafts.add(current);
      for (final chunk in _chunks(paragraph.text)) {
        current.blocks.add(TextBlock(id: _uuid.v4(), text: chunk));
      }
    }
  }
  final chapters = [
    for (final (index, draft) in drafts.indexed)
      Chapter(
        id: draft.id,
        bookId: bookId,
        title: draft.title,
        level: draft.level,
        parentId: draft.parentId,
        frontMatter: draft.frontMatter,
        order: index,
        blocks: draft.blocks,
      ),
  ];
  final core = names.contains('docProps/core.xml')
      ? zip.readXml('docProps/core.xml')
      : null;
  final coverPath = names
      .where(
        (name) =>
            name.startsWith('word/media/') &&
            RegExp(
              r'(^|/)cover\.(?:jpe?g|png|gif|webp)$',
              caseSensitive: false,
            ).hasMatch(name),
      )
      .firstOrNull;
  return ParsedStructure(
    ParseResult(
      format: ImportFormat.docx,
      suggestedMeta: _metadata(core, filename),
      chapters: chapters,
      warnings: warnings,
      sourceLocations: {
        for (final chapter in chapters)
          chapter.id: const ParseSourceLocation(
            sourcePath: 'word/document.xml',
          ),
      },
    ),
    coverEntryPath: coverPath,
  );
}

class _Paragraph {
  const _Paragraph(this.text, this.heading);
  final String text;
  final int? heading;
}

class _Style {
  const _Style(this.level, this.parent);
  final int? level;
  final String? parent;
}

Map<String, _Style> _readStyles(XmlDocument document) {
  final styles = <String, _Style>{};
  for (final style in _elements(document, 'style')) {
    final id = _attribute(style, 'styleId');
    if (id == null) continue;
    final name =
        _elements(
          style,
          'name',
        ).map((e) => _attribute(e, 'val')).whereType<String>().firstOrNull ??
        id;
    final outline = _elements(
      style,
      'outlineLvl',
    ).map((e) => int.tryParse(_attribute(e, 'val') ?? '')).firstOrNull;
    final parent = _elements(
      style,
      'basedOn',
    ).map((e) => _attribute(e, 'val')).firstOrNull;
    styles[id] = _Style(
      outline == null ? _headingName(name) : outline + 1,
      parent,
    );
  }
  return styles;
}

int? _styleLevel(String? styleId, Map<String, _Style> styles) {
  if (styleId == null) return null;
  final visited = <String>{};
  var id = styleId;
  while (visited.add(id)) {
    final style = styles[id];
    if (style == null) return _headingName(id);
    if (style.level != null) return style.level;
    if (style.parent == null) return _headingName(id);
    id = style.parent!;
  }
  return null;
}

int? _headingName(String name) {
  final normalized = name.replaceAll(RegExp(r'[\s_-]+'), '').toLowerCase();
  final match = RegExp(
    r'^(?:heading|标题|標題|一级标题|二级标题|überschrift|titre|encabezado|見出し)([12])$',
  ).firstMatch(normalized);
  if (match != null) return int.parse(match.group(1)!);
  if (normalized == '一级标题') return 1;
  if (normalized == '二级标题') return 2;
  return null;
}

String _paragraphText(XmlElement paragraph) {
  final buffer = StringBuffer();
  void walk(XmlNode node) {
    if (node is! XmlElement) return;
    final tag = node.name.local;
    if (tag == 't') {
      buffer.write(node.innerText);
      return;
    }
    if (tag == 'tab') {
      buffer.write('\t');
      return;
    }
    if (tag == 'br' || tag == 'cr') {
      buffer.write('\n');
      return;
    }
    if (const {'del', 'instrText', 'drawing', 'pict', 'object'}.contains(tag)) {
      return;
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(paragraph);
  return buffer.toString();
}

BookMeta _metadata(XmlDocument? core, String filename) {
  String? first(String local) => core == null
      ? null
      : _elements(
          core,
          local,
        ).map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).firstOrNull;
  final date = first('created') ?? first('modified');
  DateTime? published;
  if (date != null && date.length >= 10) {
    published = DateTime.tryParse(date.substring(0, 10));
  }
  return BookMeta(
    title: first('title') ?? p.basenameWithoutExtension(filename),
    author: first('creator') ?? '',
    language: first('language') ?? 'zh-CN',
    description: first('description') ?? '',
    tags: [if (first('subject') case final String subject) subject],
    publishedAt: published,
  );
}

class _ChapterDraft {
  _ChapterDraft({
    required this.id,
    required this.title,
    required this.level,
    this.parentId,
    this.frontMatter = false,
  });
  final String id;
  final String title;
  final int level;
  final String? parentId;
  final bool frontMatter;
  final List<Block> blocks = [];
}

Iterable<String> _chunks(String text) sync* {
  final runes = <int>[];
  for (final rune in text.runes) {
    runes.add(rune);
    if (runes.length >= 20000) {
      yield String.fromCharCodes(runes);
      runes.clear();
    }
  }
  if (runes.isNotEmpty) yield String.fromCharCodes(runes);
}

Iterable<XmlElement> _elements(XmlNode node, String local) => node.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

String? _attribute(XmlElement element, String local) {
  for (final attr in element.attributes) {
    if (attr.name.local == local) return attr.value;
  }
  return null;
}
