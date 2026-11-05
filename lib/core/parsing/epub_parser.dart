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

ParsedStructure parseEpubZip(
  SafeZipArchive zip, {
  required String bookId,
  required String filename,
}) {
  final names = {for (final entry in zip.entries) entry.name};
  if (names.contains('META-INF/rights.xml') ||
      names.contains('META-INF/license.lcpl')) {
    throw const ImportFailure('此 EPUB 使用数字版权保护，无法导入。');
  }
  if (names.contains('META-INF/encryption.xml')) {
    final encryption = zip.readXml('META-INF/encryption.xml');
    final algorithms = _elements(
      encryption,
      'EncryptionMethod',
    ).map((e) => _attribute(e, 'Algorithm') ?? '').toList();
    if (algorithms.isEmpty ||
        algorithms.any(
          (value) =>
              value != 'http://www.idpf.org/2008/embedding' &&
              value != 'http://ns.adobe.com/pdf/enc#RC',
        )) {
      throw const ImportFailure('此 EPUB 使用数字版权保护，无法导入。');
    }
  }
  if (!names.contains('META-INF/container.xml')) {
    throw const ImportFailure('EPUB 缺少 container.xml。');
  }
  final container = zip.readXml('META-INF/container.xml');
  final rootfile = _elements(container, 'rootfile').firstOrNull;
  final opfPath = rootfile == null ? null : _attribute(rootfile, 'full-path');
  if (opfPath == null || opfPath.isEmpty || !names.contains(opfPath)) {
    throw const ImportFailure('EPUB 的 OPF 路径无效。');
  }
  if (!_xmlName(opfPath)) {
    throw const ImportFailure('EPUB 的 OPF 文件格式无效。');
  }
  final opf = zip.readXml(opfPath);
  if (opf.rootElement.name.local != 'package') {
    throw const ImportFailure('EPUB 的 OPF 结构无效。');
  }
  final manifest = <String, _Item>{};
  final warnings = <ParseWarning>[];
  final warningCodes = <String>{};
  void warn(String code, String message, [String? path]) {
    if (warningCodes.add(code)) {
      warnings.add(
        ParseWarning(code: code, message: message, sourcePath: path),
      );
    }
  }

  for (final element in _elements(opf, 'item')) {
    final id = _attribute(element, 'id');
    final href = _attribute(element, 'href');
    if (id == null || href == null || id.isEmpty) continue;
    final path = _resolve(opfPath, href).$1;
    if (!names.contains(path)) {
      throw ImportFailure('EPUB 清单引用了缺失文件：$path。');
    }
    manifest[id] = _Item(
      id,
      path,
      _attribute(element, 'media-type') ?? '',
      (_attribute(element, 'properties') ?? '').split(RegExp(r'\s+')).toSet(),
    );
  }
  if (manifest.isEmpty) throw const ImportFailure('EPUB 清单为空。');
  final spine = _elements(opf, 'itemref')
      .map((e) => _attribute(e, 'idref'))
      .whereType<String>()
      .map((id) => manifest[id])
      .toList();
  if (spine.isEmpty || spine.any((item) => item == null)) {
    throw const ImportFailure('EPUB 阅读顺序引用无效。');
  }
  final nav = manifest.values
      .where((item) => item.properties.contains('nav'))
      .firstOrNull;
  final ncxId = _elements(opf, 'spine').firstOrNull;
  final ncx =
      manifest[_attribute(ncxId, 'toc')] ??
      manifest.values
          .where((item) => item.mediaType == 'application/x-dtbncx+xml')
          .firstOrNull;
  final auxiliaryPages = <String, Set<String>>{};
  void markAuxiliary(String base, String href, String role) {
    final path = _resolve(base, href).$1;
    if (names.contains(path)) {
      auxiliaryPages.putIfAbsent(path, () => {}).add(role);
    }
  }

  for (final reference in _elements(opf, 'reference')) {
    final href = _attribute(reference, 'href');
    if (href == null) continue;
    for (final role in const ['toc', 'cover']) {
      if (_hasType(reference, role)) markAuxiliary(opfPath, href, role);
    }
  }
  var toc = <_TocEntry>[];
  if (nav != null) {
    final navDocument = zip.readXml(nav.path);
    toc = _readNav(navDocument, nav.path, names);
    for (final landmarks in _elements(
      navDocument,
      'nav',
    ).where((element) => _hasType(element, 'landmarks'))) {
      for (final link in _elements(landmarks, 'a')) {
        final href = _attribute(link, 'href');
        if (href == null) continue;
        for (final role in const ['toc', 'cover']) {
          if (_hasType(link, role)) markAuxiliary(nav.path, href, role);
        }
      }
    }
  }
  if (toc.isEmpty && ncx != null) {
    toc = _readNcx(zip, ncx.path, names);
  }
  final coverId = _elements(opf, 'meta')
      .where((e) => _attribute(e, 'name')?.toLowerCase() == 'cover')
      .map((e) => _attribute(e, 'content'))
      .firstOrNull;
  final coverCandidate =
      manifest[coverId] ??
      manifest.values
          .where((item) => item.properties.contains('cover-image'))
          .firstOrNull ??
      manifest.values
          .where(
            (item) =>
                item.mediaType.startsWith('image/') &&
                p.posix.basename(item.path).toLowerCase().contains('cover'),
          )
          .firstOrNull;
  final cover = coverCandidate != null && _isRasterCover(coverCandidate)
      ? coverCandidate
      : null;
  if (coverCandidate != null && cover == null) {
    warn('lost_cover', '原书封面格式不受支持，已跳过封面。', coverCandidate.path);
  }
  if (manifest.values.any((item) => item.mediaType == 'text/css')) {
    warn('lost_css', '原书复杂 CSS 排版未恢复。');
  }
  if (manifest.values.any(
    (item) =>
        item.mediaType.startsWith('font/') || item.mediaType.contains('font'),
  )) {
    warn('lost_fonts', '原书嵌入字体未恢复。');
  }

  final pieces = <_Piece>[];
  final usedToc = <_TocEntry>{};
  for (final item in spine.whereType<_Item>()) {
    final navPage =
        item.properties.contains('nav') ||
        (nav != null && item.path == nav.path);
    if (item.mediaType != 'application/xhtml+xml' &&
        item.mediaType != 'text/html' &&
        item.mediaType != 'application/xml') {
      warn('lost_spine_media', '部分非 XHTML 正文未恢复。', item.path);
      continue;
    }
    final document = zip.readXml(item.path);
    final body = _elements(document, 'body').firstOrNull;
    if (body == null) {
      warn('missing_body', '部分章节没有可识别的正文。', item.path);
      continue;
    }
    final roles = auxiliaryPages[item.path] ?? const <String>{};
    final tocPage = roles.contains('toc');
    final coverPage = roles.contains('cover');
    if (navPage && !_hasNarrativeText(body, const {'toc'})) continue;
    final fileToc = toc.where((entry) => entry.path == item.path).toList();
    for (final entry in fileToc.where((entry) => entry.anchor == null)) {
      pieces.add(
        _Piece.heading(entry.title, entry.isParent ? 1 : 2, item.path),
      );
      usedToc.add(entry);
    }
    void warnOmittedDescendants(XmlElement element, bool coverContext) {
      for (final child in element.descendants.whereType<XmlElement>()) {
        final childTag = child.name.local.toLowerCase();
        if (childTag == 'img' || childTag == 'image') {
          if (!coverContext) warn('lost_images', '章节插图未恢复。', item.path);
        } else if (childTag == 'table') {
          warn('lost_tables', '表格结构已转为普通文字。', item.path);
        } else if (childTag == 'aside' ||
            const {'footnote', 'noteref'}.contains(_attribute(child, 'type'))) {
          warn('lost_footnotes', '脚注关联未恢复。', item.path);
        } else if (childTag == 'script') {
          warn('lost_scripts', '原书脚本已移除。', item.path);
        }
      }
    }

    void walk(XmlElement element, bool inToc, bool inCover) {
      final tag = element.name.local.toLowerCase();
      final tocContext =
          inToc ||
          (const {'section', 'div'}.contains(tag) && _hasType(element, 'toc'));
      final coverContext =
          inCover ||
          (const {'section', 'div'}.contains(tag) &&
              _hasType(element, 'cover'));
      if (const {
        'nav',
        'script',
        'style',
        'svg',
        'math',
        'form',
        'audio',
        'video',
      }.contains(tag)) {
        if (tag == 'script') warn('lost_scripts', '原书脚本已移除。', item.path);
        return;
      }
      if (tag == 'img' || tag == 'image') {
        if (!coverContext) warn('lost_images', '章节插图未恢复。', item.path);
        return;
      }
      if (tag == 'li' &&
          tocContext &&
          _isVerifiedTocItem(element, item.path, toc)) {
        for (final child in element.children.whereType<XmlElement>()) {
          if (const {'ol', 'ul'}.contains(child.name.local.toLowerCase())) {
            walk(child, tocContext, coverContext);
          }
        }
        return;
      }
      if (tag == 'li' &&
          tocContext &&
          _elements(
            element,
            'a',
          ).any((link) => _attribute(link, 'href') != null)) {
        warn('ambiguous_toc_content', '目录页含无法确认的链接列表项，已按正文保留。', item.path);
      }
      if (tag == 'table') warn('lost_tables', '表格结构已转为普通文字。', item.path);
      if (tag == 'aside' || _attribute(element, 'type') == 'footnote') {
        warn('lost_footnotes', '脚注关联未恢复。', item.path);
      }
      final anchors = <String>{};
      if (_attribute(element, 'id') case final String id) anchors.add(id);
      if (const {
        'h1',
        'h2',
        'h3',
        'p',
        'li',
        'blockquote',
        'pre',
        'td',
        'th',
      }.contains(tag)) {
        for (final child in element.descendants.whereType<XmlElement>()) {
          if (_attribute(child, 'id') case final String id) anchors.add(id);
        }
      }
      final marker = fileToc
          .where(
            (entry) =>
                entry.anchor != null &&
                anchors.contains(entry.anchor) &&
                !usedToc.contains(entry),
          )
          .firstOrNull;
      if (marker != null) {
        pieces.add(
          _Piece.heading(marker.title, marker.isParent ? 1 : 2, item.path),
        );
        usedToc.add(marker);
      }
      if (const {'h1', 'h2', 'h3'}.contains(tag)) {
        warnOmittedDescendants(element, coverContext);
        if ((tocContext || coverContext) && marker == null) return;
        if (fileToc.isEmpty || toc.isEmpty) {
          final title = _inlineText(element).trim();
          if (title.isNotEmpty) {
            pieces.add(_Piece.heading(title, int.parse(tag[1]), item.path));
          }
        }
        return;
      }
      if (const {'p', 'li', 'blockquote', 'pre', 'td', 'th'}.contains(tag)) {
        warnOmittedDescendants(element, coverContext);
        final text = _inlineText(element).trim();
        if (text.isNotEmpty) pieces.add(_Piece.text(text, item.path));
        return;
      }
      for (final child in element.children.whereType<XmlElement>()) {
        walk(child, tocContext, coverContext);
      }
    }

    for (final element in body.children.whereType<XmlElement>()) {
      walk(element, tocPage, coverPage);
    }
  }
  if (usedToc.length < toc.length) {
    warn('unresolved_toc', '部分目录锚点没有对应正文，已保留可识别内容。');
  }
  final chapters = _buildChapters(pieces, bookId, warnings);
  if (chapters.isEmpty) throw const ImportFailure('EPUB 没有可导入的正文。');
  final metadata = _metadata(opf, filename);
  return ParsedStructure(
    ParseResult(
      format: ImportFormat.epub,
      suggestedMeta: metadata,
      chapters: chapters,
      warnings: warnings,
      sourceLocations: {
        for (final chapter in chapters)
          chapter.id: ParseSourceLocation(
            sourcePath: pieces
                .where((piece) => piece.title == chapter.title)
                .map((piece) => piece.path)
                .firstOrNull,
          ),
      },
    ),
    coverEntryPath: cover?.path,
  );
}

class _Item {
  const _Item(this.id, this.path, this.mediaType, this.properties);
  final String id;
  final String path;
  final String mediaType;
  final Set<String> properties;
}

class _TocEntry {
  const _TocEntry(this.path, this.anchor, this.title, this.isParent);
  final String path;
  final String? anchor;
  final String title;
  final bool isParent;
}

class _Piece {
  const _Piece(this.title, this.level, this.text, this.path);
  factory _Piece.heading(String title, int level, String path) =>
      _Piece(title, level, null, path);
  factory _Piece.text(String text, String path) =>
      _Piece(null, null, text, path);
  final String? title;
  final int? level;
  final String? text;
  final String path;
}

List<Chapter> _buildChapters(
  List<_Piece> pieces,
  String bookId,
  List<ParseWarning> warnings,
) {
  final headings = pieces.where((piece) => piece.title != null).toList();
  final h1AsVolume =
      headings.any((piece) => piece.level == 1) &&
      headings.any((piece) => piece.level == 2 || piece.level == 3);
  final chapters = <_ChapterDraft>[];
  _ChapterDraft? current;
  String? volumeId;
  for (final piece in pieces) {
    if (piece.title case final String title) {
      final volume = piece.level == 1 && h1AsVolume;
      final chapter = _ChapterDraft(
        id: _uuid.v4(),
        title: title,
        level: volume ? 1 : 2,
        parentId: volume ? null : volumeId,
      );
      if (volume) volumeId = chapter.id;
      chapters.add(chapter);
      current = chapter;
    } else if (piece.text case final String text) {
      current ??= _ChapterDraft(
        id: _uuid.v4(),
        title: headings.isEmpty ? '正文' : '前言',
        level: 2,
        frontMatter: headings.isNotEmpty,
      );
      if (!chapters.contains(current)) chapters.add(current);
      for (final chunk in _chunks(text)) {
        current.blocks.add(TextBlock(id: _uuid.v4(), text: chunk));
      }
    }
  }
  if (headings.isEmpty) {
    warnings.add(
      const ParseWarning(code: 'no_headings', message: '没有识别到章节标题，已按单章导入。'),
    );
  }
  return [
    for (final (index, draft) in chapters.indexed)
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

List<_TocEntry> _readNav(XmlDocument doc, String path, Set<String> names) {
  final nav = _elements(doc, 'nav').where((e) {
    return _hasType(e, 'toc') || _attribute(e, 'role') == 'doc-toc';
  }).firstOrNull;
  if (nav == null) return [];
  final entries = <_TocEntry>[];
  void scan(XmlElement list) {
    for (final li in list.children.whereType<XmlElement>().where(
      (e) => e.name.local == 'li',
    )) {
      final link = li.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'a')
          .firstOrNull;
      final nested = li.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'ol')
          .firstOrNull;
      final href = link == null ? null : _attribute(link, 'href');
      if (href != null) {
        final target = _resolve(path, href);
        if (names.contains(target.$1)) {
          entries.add(
            _TocEntry(
              target.$1,
              target.$2,
              _inlineText(link!).trim(),
              nested != null,
            ),
          );
        }
      }
      if (nested != null) scan(nested);
    }
  }

  final list = nav.children
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'ol')
      .firstOrNull;
  if (list != null) scan(list);
  return entries.where((entry) => entry.title.isNotEmpty).toList();
}

List<_TocEntry> _readNcx(SafeZipArchive zip, String path, Set<String> names) {
  final doc = zip.readXml(path);
  final map = _elements(doc, 'navMap').firstOrNull;
  if (map == null) return [];
  final entries = <_TocEntry>[];
  void scan(XmlElement parent) {
    for (final point in parent.children.whereType<XmlElement>().where(
      (e) => e.name.local == 'navPoint',
    )) {
      final content = _elements(point, 'content').firstOrNull;
      final src = content == null ? null : _attribute(content, 'src');
      if (src != null) {
        final target = _resolve(path, src);
        if (names.contains(target.$1)) {
          final label =
              _elements(point, 'text').firstOrNull?.innerText.trim() ?? '';
          final nested = point.children.whereType<XmlElement>().any(
            (e) => e.name.local == 'navPoint',
          );
          entries.add(_TocEntry(target.$1, target.$2, label, nested));
        }
      }
      scan(point);
    }
  }

  scan(map);
  return entries.where((entry) => entry.title.isNotEmpty).toList();
}

BookMeta _metadata(XmlDocument opf, String filename) {
  String? first(String name) => _elements(
    opf,
    name,
  ).map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).firstOrNull;
  final meta = _elements(opf, 'meta');
  String? property(String value) => meta
      .where((e) => _attribute(e, 'property') == value)
      .map((e) => e.innerText.trim())
      .where((s) => s.isNotEmpty)
      .firstOrNull;
  String? calibre(String value) => meta
      .where((e) => _attribute(e, 'name') == value)
      .map((e) => _attribute(e, 'content'))
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .firstOrNull;
  final date = first('date');
  DateTime? published;
  if (date != null && date.length >= 4) {
    published = DateTime.tryParse(
      date.length >= 10 ? date.substring(0, 10) : date,
    );
  }
  return BookMeta(
    title: first('title') ?? p.basenameWithoutExtension(filename),
    author: first('creator') ?? calibre('calibre:author') ?? '',
    language: first('language') ?? 'zh-CN',
    description: first('description') ?? '',
    series: property('belongs-to-collection') ?? calibre('calibre:series'),
    publisher: first('publisher'),
    tags: _elements(
      opf,
      'subject',
    ).map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).toList(),
    publishedAt: published,
  );
}

Iterable<XmlElement> _elements(XmlNode node, String local) => node.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

String? _attribute(XmlElement? element, String local) {
  if (element == null) return null;
  for (final attr in element.attributes) {
    if (attr.name.local == local) return attr.value;
  }
  return null;
}

(String, String?) _resolve(String base, String href) {
  final raw = href.trim();
  if (raw.isEmpty ||
      raw.startsWith('/') ||
      raw.startsWith('//') ||
      RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(raw)) {
    throw const ImportFailure('EPUB 包含外部或绝对路径引用。');
  }
  final hash = raw.indexOf('#');
  final withoutFragment = hash < 0 ? raw : raw.substring(0, hash);
  final fragment = hash < 0
      ? null
      : Uri.decodeComponent(raw.substring(hash + 1));
  final query = withoutFragment.indexOf('?');
  final encodedPath = query < 0
      ? withoutFragment
      : withoutFragment.substring(0, query);
  final relative = Uri.decodeComponent(encodedPath);
  if (relative.contains('\\') ||
      relative.contains(':') ||
      relative.startsWith('/')) {
    throw const ImportFailure('EPUB 包含不安全资源路径。');
  }
  final path = relative.isEmpty
      ? base
      : p.posix.normalize(p.posix.join(p.posix.dirname(base), relative));
  if (path == '.' ||
      path == '..' ||
      path.startsWith('../') ||
      p.posix.isAbsolute(path)) {
    throw const ImportFailure('EPUB 资源路径越过压缩包边界。');
  }
  return (path, fragment?.isEmpty == true ? null : fragment);
}

String _inlineText(XmlNode node) {
  if (node is XmlText) return node.value;
  if (node is XmlCDATA) return node.value;
  if (node is! XmlElement) return '';
  final tag = node.name.local.toLowerCase();
  if (const {
    'script',
    'style',
    'nav',
    'svg',
    'math',
    'img',
    'image',
  }.contains(tag)) {
    return '';
  }
  if (tag == 'br') return '\n';
  final text = node.children.map(_inlineText).join();
  return text.replaceAll(RegExp(r'[\t\r\n ]+'), ' ');
}

bool _xmlName(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.opf') || lower.endsWith('.xml');
}

bool _isRasterCover(_Item item) {
  final media = item.mediaType.toLowerCase();
  return const {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  }.contains(media);
}

bool _hasType(XmlElement element, String role) =>
    (_attribute(element, 'type') ?? '').split(RegExp(r'\s+')).contains(role);

/// Suppress a TOC list item only when its sole visible content is one local
/// link to an entry already established by nav or NCX. Nested lists are
/// checked item by item by the caller.
bool _isVerifiedTocItem(XmlElement item, String pagePath, List<_TocEntry> toc) {
  XmlElement? link;
  for (final child in item.children) {
    if (child is XmlText && child.value.trim().isNotEmpty) return false;
    if (child is XmlCDATA && child.value.trim().isNotEmpty) return false;
    if (child is! XmlElement) continue;
    final tag = child.name.local.toLowerCase();
    if (tag == 'ol' || tag == 'ul') continue;
    if (tag != 'a' || link != null) return false;
    link = child;
  }
  final href = link == null ? null : _attribute(link, 'href');
  if (href == null) return false;
  try {
    final target = _resolve(pagePath, href);
    return toc.any(
      (entry) => entry.path == target.$1 && entry.anchor == target.$2,
    );
  } on ImportFailure {
    return false;
  } on FormatException {
    return false;
  }
}

/// A guide or landmarks reference identifies an auxiliary page, but it may
/// also carry prose. Keep the page when text exists outside its heading,
/// navigation links/lists, and cover art.
bool _hasNarrativeText(XmlElement root, Set<String> roles) {
  bool visit(XmlNode node, bool auxiliary) {
    if (node is XmlText) return !auxiliary && node.value.trim().isNotEmpty;
    if (node is XmlCDATA) return !auxiliary && node.value.trim().isNotEmpty;
    if (node is! XmlElement) return false;
    final tag = node.name.local.toLowerCase();
    if (const {
      'script',
      'style',
      'svg',
      'math',
      'img',
      'image',
    }.contains(tag)) {
      return false;
    }
    final structural =
        const {'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'nav'}.contains(tag) ||
        (roles.contains('toc') && const {'ol', 'ul', 'li', 'a'}.contains(tag));
    return node.children.any((child) => visit(child, auxiliary || structural));
  }

  return visit(root, false);
}
