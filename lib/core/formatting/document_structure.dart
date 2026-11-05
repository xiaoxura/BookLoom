import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';

/// Returns a validated, ordered two-level chapter list.
List<Chapter> orderedChapters(Book book) {
  if (book.chapters.isEmpty) {
    throw ArgumentError('Book has no chapters to export');
  }
  final byId = <String, Chapter>{};
  for (final chapter in book.chapters) {
    if (chapter.bookId != book.id || byId.containsKey(chapter.id)) {
      throw ArgumentError('Invalid chapter identity: ${chapter.id}');
    }
    byId[chapter.id] = chapter;
    if (chapter.level == 1) {
      if (chapter.parentId != null || chapter.frontMatter) {
        throw ArgumentError('Volume cannot have a parent or be front matter');
      }
    } else if (chapter.level != 2) {
      throw ArgumentError('Invalid chapter level: ${chapter.id}');
    }
    for (final block in chapter.blocks) {
      if (block is ImageBlock) {
        throw UnsupportedError(
          'Image blocks need an asset resolver: ${block.assetId}',
        );
      }
    }
  }
  final roots = <Chapter>[];
  final children = <String, List<Chapter>>{};
  for (final chapter in book.chapters) {
    final parentId = chapter.parentId;
    if (parentId == null) {
      roots.add(chapter);
    } else if (chapter.level == 2 && byId[parentId]?.level == 1) {
      children.putIfAbsent(parentId, () => <Chapter>[]).add(chapter);
    } else {
      throw ArgumentError('Invalid chapter parent: ${chapter.id}');
    }
  }
  int compare(Chapter a, Chapter b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  }

  roots.sort(compare);
  for (final siblings in children.values) {
    siblings.sort(compare);
  }
  return <Chapter>[
    for (final root in roots) ...<Chapter>[
      root,
      if (root.level == 1) ...?children[root.id],
    ],
  ];
}

String xmlEscape(String value) {
  final buffer = StringBuffer();
  for (final codePoint in value.runes) {
    if (codePoint != 9 &&
        codePoint != 10 &&
        codePoint != 13 &&
        (codePoint < 0x20 ||
            codePoint > 0x10ffff ||
            (codePoint >= 0xd800 && codePoint <= 0xdfff) ||
            codePoint == 0xfffe ||
            codePoint == 0xffff)) {
      continue;
    }
    buffer.write(switch (codePoint) {
      0x26 => '&amp;',
      0x3c => '&lt;',
      0x3e => '&gt;',
      0x22 => '&quot;',
      0x27 => '&apos;',
      _ => String.fromCharCode(codePoint),
    });
  }
  return buffer.toString();
}
