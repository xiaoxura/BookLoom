import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/formatting/document_structure.dart';
import 'package:bookloom/core/formatting/docx/docx_export.dart';
import 'package:bookloom/core/formatting/epub/epub_export.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/formatting/output_file.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/layout_options.dart';

enum ExportFormat {
  epub3('epub', 'application/epub+zip'),
  epub2('epub', 'application/epub+zip'),
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  html('html', 'text/html; charset=utf-8'),
  txt('txt', 'text/plain; charset=utf-8'),
  markdown('md', 'text/markdown; charset=utf-8');

  const ExportFormat(this.extension, this.mimeType);
  final String extension;
  final String mimeType;
}

/// Writes one format to a task-private path, then validates and commits it.
/// The caller must load every chapter's blocks and own the destination folder.
void writeDocument(
  ExportSnapshot snapshot,
  String outputPath, {
  required ExportFormat format,
}) {
  switch (format) {
    case ExportFormat.epub3:
      writeEpub(snapshot, outputPath);
    case ExportFormat.epub2:
      writeEpub(snapshot, outputPath, version: 2);
    case ExportFormat.docx:
      writeDocx(snapshot, outputPath);
    case ExportFormat.html || ExportFormat.txt || ExportFormat.markdown:
      final chapters = orderedChapters(snapshot.book);
      writeStagedFile(outputPath, (candidatePath) {
        final file = File(candidatePath).openSync(mode: FileMode.write);
        try {
          switch (format) {
            case ExportFormat.html:
              _writeHtml(file, snapshot, chapters);
            case ExportFormat.txt:
              _writeTxt(file, chapters);
            case ExportFormat.markdown:
              _writeMarkdown(file, snapshot, chapters);
            default:
              throw StateError('Unexpected document format');
          }
          file.flushSync();
        } finally {
          file.closeSync();
        }
        if (File(candidatePath).lengthSync() == 0) {
          throw const FormatException('Export is empty');
        }
        if (format == ExportFormat.html) {
          _validateHtml(candidatePath, chapters.length);
        }
      });
  }
}

void _writeTxt(RandomAccessFile file, List<Chapter> chapters) {
  var first = true;
  for (final chapter in chapters) {
    final hasBody = chapter.blocks.any(
      (block) => _plainBlock(block).trim().isNotEmpty,
    );
    if (chapter.frontMatter && !hasBody) continue;
    if (!first) file.writeStringSync('\n\n\n');
    first = false;
    if (!chapter.frontMatter) {
      file.writeStringSync(chapter.title.trim());
      if (hasBody) file.writeStringSync('\n\n');
    }
    var firstBlock = true;
    for (final block in chapter.blocks) {
      final plain = _plainBlock(block).trim();
      if (plain.isEmpty) continue;
      if (!firstBlock) file.writeStringSync('\n\n');
      firstBlock = false;
      file.writeStringSync(plain);
    }
  }
  file.writeStringSync('\n');
}

void _writeMarkdown(
  RandomAccessFile file,
  ExportSnapshot snapshot,
  List<Chapter> chapters,
) {
  final meta = snapshot.book.meta;
  final hasVolume = chapters.any((chapter) => chapter.level == 1);
  file.writeStringSync(
    '# ${_markdown(meta.title.trim().isEmpty ? '未命名' : meta.title.trim())}\n\n',
  );
  if (meta.author.trim().isNotEmpty) {
    file.writeStringSync('> 作者：${_markdown(meta.author.trim())}\n\n');
  }
  for (final chapter in chapters) {
    if (!chapter.frontMatter) {
      final level = chapter.level == 1 || !hasVolume ? '##' : '###';
      file.writeStringSync('$level ${_markdown(chapter.title.trim())}\n\n');
    }
    for (final block in chapter.blocks) {
      final plain = _plainBlock(block);
      if (plain.trim().isEmpty) continue;
      file.writeStringSync('${_markdown(plain)}\n\n');
    }
  }
}

String _markdown(String value) {
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return escaped.replaceAllMapped(
    RegExp(r'([`*_{}\[\]()#+.!|\-])'),
    (match) => '\\${match[1]}',
  );
}

void _writeHtml(
  RandomAccessFile file,
  ExportSnapshot snapshot,
  List<Chapter> chapters,
) {
  final meta = snapshot.book.meta;
  final title = meta.title.trim().isEmpty ? '未命名' : meta.title.trim();
  final language = meta.language.trim().isEmpty
      ? 'zh-CN'
      : meta.language.trim();
  file.writeStringSync(
    '<!doctype html>\n<html lang="${xmlEscape(language)}"><head>'
    '<meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/>'
    '<title>${xmlEscape(title)}</title><style>${_htmlCss(snapshot.book.layout)}</style>'
    '</head><body><header class="book"><h1>${xmlEscape(title)}</h1>'
    '${meta.author.trim().isEmpty ? '' : '<p>${xmlEscape(meta.author.trim())}</p>'}'
    '</header><nav class="toc" aria-label="目录"><h2>目录</h2>',
  );
  final roots = _tocTree(chapters);
  file.writeStringSync(_htmlToc(roots));
  file.writeStringSync('</nav><main>');
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    file.writeStringSync('<section class="chapter" id="c-${i + 1}">');
    if (!chapter.frontMatter) {
      final heading = chapter.level == 1 ? 'h1' : 'h2';
      final headingClass = chapter.level == 1
          ? 'volume-title'
          : 'chapter-title';
      file.writeStringSync(
        '<$heading class="$headingClass">'
        '${_htmlHeading(chapter, snapshot.book.layout)}</$heading>',
      );
    }
    for (final block in chapter.blocks) {
      switch (block) {
        case TextBlock(:final text):
          file.writeStringSync('<p>${xmlEscape(text)}</p>');
        case FootnoteBlock(:final text, :final marker):
          file.writeStringSync(
            '<aside class="footnote"><p>'
            '${marker == null ? '' : '${xmlEscape(marker)} '}${xmlEscape(text)}</p></aside>',
          );
        case DividerBlock():
          file.writeStringSync('<hr class="scene-break"/>');
        case ImageBlock():
          throw StateError('Image block should have been rejected');
      }
    }
    file.writeStringSync('</section>');
  }
  file.writeStringSync('</main></body></html>\n');
}

class _TocNode {
  _TocNode(this.title, this.index, this.isVolume);
  final String title;
  final int index;
  final bool isVolume;
  final List<_TocNode> children = <_TocNode>[];
}

List<_TocNode> _tocTree(List<Chapter> chapters) {
  final roots = <_TocNode>[];
  _TocNode? volume;
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    final node = _TocNode(
      chapter.title.trim().isEmpty ? '未命名章节' : chapter.title,
      i + 1,
      chapter.level == 1,
    );
    if (chapter.level == 1) {
      roots.add(node);
      volume = node;
    } else if (chapter.parentId != null) {
      volume!.children.add(node);
    } else {
      roots.add(node);
      volume = null;
    }
  }
  return roots;
}

String _htmlToc(List<_TocNode> nodes) =>
    '<ol>${nodes.map((node) => '<li class="${node.isVolume ? 'toc-volume' : 'toc-chapter'}">'
        '<a href="#c-${node.index}">${xmlEscape(node.title)}</a>'
        '${node.children.isEmpty ? '' : _htmlToc(node.children)}</li>').join()}</ol>';

String _htmlHeading(Chapter chapter, LayoutOptions layout) {
  final title = chapter.title.trim().isEmpty ? '未命名章节' : chapter.title.trim();
  final match = chapter.level == 2 && layout.separateChapterNumber
      ? RegExp(r'^(第\s*[0-9零〇一二三四五六七八九十百千万两]+\s*[章节回话])\s*(\S.*)$')
            .firstMatch(title)
      : null;
  return match == null
      ? xmlEscape(title)
      : '<span class="chapter-number">${xmlEscape(match[1]!)}</span>${xmlEscape(match[2]!)}';
}

String _htmlCss(LayoutOptions layout) {
  final family = switch (layout.font) {
    LayoutFont.serif => '"Songti SC", "Noto Serif CJK SC", "SimSun", serif',
    LayoutFont.sans =>
      '"PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei", sans-serif',
    LayoutFont.kai => '"Kaiti SC", "KaiTi", serif',
  };
  return ':root { color-scheme: light; } html { background: #f2ede3; } '
      'body { margin: 0 auto; padding: 40px 24px 80px; max-width: 46em; '
      'background: #fbf8f1; color: #2c2923; font-family: $family; '
      'line-height: ${layout.lineHeight}; text-align: ${layout.justify ? 'justify' : 'left'}; } '
      'nav.toc { padding: 1em; border: 1px solid #d9cfbd; } '
      'nav.toc ol { padding-left: 1.4em; } nav.toc a { color: inherit; } '
      'section.chapter { margin: 0 0 2.2em; } '
      'h1.volume-title, h2.chapter-title { text-align: center; } '
      '.chapter-number { display: block; } '
      'p { margin: 0 0 ${layout.paragraphSpacing}em; '
      'text-indent: ${layout.indent ? '2em' : '0'}; } '
      '${layout.customCss}';
}

String _plainBlock(Block block) => switch (block) {
  TextBlock(:final text) => text,
  FootnoteBlock(:final text, :final marker) =>
    '${marker == null ? '' : '$marker '}$text',
  DividerBlock() => '* * *',
  ImageBlock() => throw StateError('Image block should have been rejected'),
};

void _validateHtml(String path, int expectedSections) {
  final file = File(path).openSync();
  try {
    final length = file.lengthSync();
    if (length < 50 || ascii.decode(file.readSync(16)) != '<!doctype html>\n') {
      throw const FormatException('Incomplete HTML');
    }
    file.setPositionSync(length - 8);
    if (ascii.decode(file.readSync(8)) != '</html>\n') {
      throw const FormatException('Incomplete HTML');
    }
    file.setPositionSync(0);
    final sections = <int>[];
    final links = <int>[];
    var carry = '';
    var inBody = false;
    const bodyStart = '</style></head><body>';
    final sectionTag = RegExp(r'<section class="chapter" id="c-(\d+)">');
    final linkTag = RegExp(r'<a href="#c-(\d+)">');
    while (file.positionSync() < length) {
      final chunk = file.readSync(64 * 1024);
      if (chunk.isEmpty) break;
      var text = carry + latin1.decode(chunk);
      if (!inBody) {
        final start = text.indexOf(bodyStart);
        if (start < 0) {
          carry = text.substring(
            text.length > bodyStart.length - 1
                ? text.length - bodyStart.length + 1
                : 0,
          );
          continue;
        }
        text = text.substring(start + bodyStart.length);
        carry = '';
        inBody = true;
      }
      for (final match in sectionTag.allMatches(text)) {
        if (match.end > carry.length) sections.add(int.parse(match[1]!));
      }
      for (final match in linkTag.allMatches(text)) {
        if (match.end > carry.length) links.add(int.parse(match[1]!));
      }
      carry = text.substring(text.length > 64 ? text.length - 64 : 0);
    }
    if (!inBody ||
        sections.length != expectedSections ||
        links.length != expectedSections ||
        List.generate(
          expectedSections,
          (index) => index + 1,
        ).any((id) => sections[id - 1] != id || links[id - 1] != id)) {
      throw const FormatException('HTML navigation anchors are incomplete');
    }
  } finally {
    file.closeSync();
  }
}
