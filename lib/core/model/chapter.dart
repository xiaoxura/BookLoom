import 'package:bookloom/core/model/block.dart';

/// A chapter (level 2) or a volume (level 1). Volumes own chapters through
/// [parentId]; top-level chapters have no parent.
class Chapter {
  const Chapter({
    required this.id,
    required this.bookId,
    required this.title,
    this.parentId,
    this.level = 2,
    this.order = 0,
    this.blocks = const <Block>[],
    this.frontMatter = false,
  });

  final String id;
  final String bookId;
  final String title;
  final String? parentId;
  final int level;
  final int order;
  final List<Block> blocks;

  /// True for preface content, which is exported without an invented title.
  final bool frontMatter;

  bool get isVolume => level == 1;

  Chapter copyWith({
    String? title,
    String? parentId,
    int? level,
    int? order,
    List<Block>? blocks,
    bool? frontMatter,
    bool clearParent = false,
  }) => Chapter(
    id: id,
    bookId: bookId,
    title: title ?? this.title,
    parentId: clearParent ? null : (parentId ?? this.parentId),
    level: level ?? this.level,
    order: order ?? this.order,
    blocks: blocks ?? this.blocks,
    frontMatter: frontMatter ?? this.frontMatter,
  );
}
