import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/parsing/txt_encoding.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

/// Self-authored fixtures for external validators and a bounded core benchmark.
/// This measures parsing/export only; it is not an editable-UI timing claim.
void main(List<String> args) {
  if (args.isEmpty) throw ArgumentError('Pass a task-owned output directory.');
  final directory = Directory(args.first)..createSync(recursive: true);
  const id = '123e4567-e89b-42d3-a456-426614174000';
  final now = DateTime.utc(2026, 11, 5);
  Book book;
  final parseWatch = Stopwatch()..start();
  if (args.contains('--million')) {
    final text = StringBuffer();
    final paragraph = List.filled(1000, '甲').join();
    for (var i = 1; i <= 1000; i++) {
      text.writeln('第$i章 测试章节\n$paragraph\n');
    }
    final parsed = parseTxtBytes(
      Uint8List.fromList(utf8.encode(text.toString())),
      bookId: id,
      filename: '性能测试.txt',
    );
    book = Book(
      id: id,
      meta: parsed.suggestedMeta,
      chapters: parsed.chapters,
      createdAt: now,
      updatedAt: now,
    );
    final words = book.chapters.fold<int>(
      0,
      (count, chapter) => count + WordCount.ofBlocks(chapter.blocks),
    );
    if (words != 1000000 || book.chapters.length != 1000) {
      throw StateError(
        'Benchmark content differs: $words / ${book.chapters.length}',
      );
    }
  } else {
    book = Book(
      id: id,
      createdAt: now,
      updatedAt: now,
      meta: BookMeta(
        title: '原生工作台验证',
        author: 'Bookloom',
        description: '自编验证文字。\n不包含用户书稿。',
        series: '验证集',
        publisher: 'Bookloom',
        tags: ['测试', '本地'],
        publishedAt: DateTime.utc(2026, 11, 5),
      ),
      chapters: [
        Chapter(id: 'v1', bookId: id, title: '第一卷 清晨', level: 1, order: 0),
        Chapter(
          id: 'c1',
          bookId: id,
          title: '第一章 出发',
          parentId: 'v1',
          level: 2,
          order: 0,
          blocks: const [
            TextBlock(id: 'p1', text: '窗外的船帆渐渐远去。 & < > " 引号与符号保持文字。'),
          ],
        ),
        Chapter(id: 'v2', bookId: id, title: '第二卷 返航', level: 1, order: 1),
        Chapter(
          id: 'c2',
          bookId: id,
          title: '第一章 灯火',
          parentId: 'v2',
          level: 2,
          order: 0,
          blocks: const [TextBlock(id: 'p2', text: '傍晚时分，海边亮起了灯。😀')],
        ),
      ],
    );
  }
  parseWatch.stop();
  final fontArgument = args.indexOf('--font');
  final fonts = <ExportFont>[];
  if (fontArgument >= 0) {
    if (fontArgument + 1 >= args.length) {
      throw ArgumentError('--font requires a local licensed font path.');
    }
    final file = File(args[fontArgument + 1]);
    fonts.add(
      ExportFont(
        assetId: 'validation-font',
        fileName: p.basename(file.path),
        bytes: file.readAsBytesSync(),
      ),
    );
    book = book.copyWith(
      layout: book.layout.copyWith(embeddedFontAssetId: 'validation-font'),
    );
  }
  final cover = image.Image(width: 1200, height: 1800);
  image.fill(cover, color: image.ColorRgb8(32, 48, 64));
  final snapshot = ExportSnapshot(
    book: book,
    coverBytes: image.encodeJpg(cover),
    coverMime: 'image/jpeg',
    fonts: fonts,
  );
  final exportWatch = Stopwatch()..start();
  final formats = args.contains('--million')
      ? [ExportFormat.epub3]
      : ExportFormat.values;
  for (final format in formats) {
    writeDocument(
      snapshot,
      p.join(directory.path, '${format.name}.${format.extension}'),
      format: format,
    );
  }
  exportWatch.stop();
  final result = {
    'kind': args.contains('--million')
        ? 'core-million-character'
        : 'external-format-fixture',
    'chapters': book.chapters.length,
    'wordCount': book.chapters.fold<int>(
      0,
      (count, chapter) => count + WordCount.ofBlocks(chapter.blocks),
    ),
    'parseMilliseconds': parseWatch.elapsedMilliseconds,
    'exportMilliseconds': exportWatch.elapsedMilliseconds,
    'peakRssBytes': ProcessInfo.maxRss,
    'editableUiMeasured': false,
    'embeddedFont': fonts.isNotEmpty,
  };
  File(p.join(directory.path, 'metrics.json'))
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln(jsonEncode(result));
}
