/// Identity of a content block. Mirrors the `blocks.kind` column.
enum BlockKind {
  paragraph('paragraph'),
  image('image'),
  footnote('footnote'),
  divider('divider');

  const BlockKind(this.wire);

  /// Stable value stored in SQLite and backup files.
  final String wire;

  static BlockKind fromWire(String value) =>
      BlockKind.values.firstWhere((BlockKind k) => k.wire == value);
}

/// A unit of book content.
///
/// Blocks exist from day one so images, footnotes and breaks do not force a
/// migration away from `List<String> paragraphs` (see docs/03-data-model.md).
sealed class Block {
  const Block({required this.id, required this.kind});

  final String id;
  final BlockKind kind;

  String get plainText;

  @override
  bool operator ==(Object other) =>
      other is Block && other.runtimeType == runtimeType && other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, id);
}

final class TextBlock extends Block {
  const TextBlock({required super.id, required this.text})
    : super(kind: BlockKind.paragraph);

  final String text;

  @override
  String get plainText => text;

  @override
  bool operator ==(Object other) =>
      other is TextBlock && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

final class ImageBlock extends Block {
  const ImageBlock({
    required super.id,
    required this.assetId,
    this.caption,
    this.alt = '',
  }) : super(kind: BlockKind.image);

  final String assetId;
  final String? caption;
  final String alt;

  @override
  String get plainText => caption ?? alt;

  @override
  bool operator ==(Object other) =>
      other is ImageBlock &&
      other.id == id &&
      other.assetId == assetId &&
      other.caption == caption &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(id, assetId, caption, alt);
}

final class FootnoteBlock extends Block {
  const FootnoteBlock({required super.id, required this.text, this.marker})
    : super(kind: BlockKind.footnote);

  final String text;
  final String? marker;

  @override
  String get plainText => text;

  @override
  bool operator ==(Object other) =>
      other is FootnoteBlock &&
      other.id == id &&
      other.text == text &&
      other.marker == marker;

  @override
  int get hashCode => Object.hash(id, text, marker);
}

/// Scene break or page break inside a chapter.
final class DividerBlock extends Block {
  const DividerBlock({required super.id}) : super(kind: BlockKind.divider);

  @override
  String get plainText => '';

  @override
  bool operator ==(Object other) => other is DividerBlock && other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, id);
}
