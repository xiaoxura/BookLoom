import 'package:bookloom/core/model/block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Block', () {
    test('text blocks expose their text and are equal by content', () {
      const TextBlock a = TextBlock(id: 'b1', text: '第一章 风起');
      const TextBlock b = TextBlock(id: 'b1', text: '第一章 风起');
      expect(a.plainText, '第一章 风起');
      expect(a.kind, BlockKind.paragraph);
      expect(a, b);
    });

    test('image blocks keep asset reference and caption', () {
      const ImageBlock block = ImageBlock(
        id: 'b2',
        assetId: 'a1',
        caption: '插图',
      );
      expect(block.kind, BlockKind.image);
      expect(block.plainText, '插图');
    });

    test('sealed hierarchy can be switched exhaustively', () {
      String describe(Block block) => switch (block) {
        TextBlock() => 'text',
        ImageBlock() => 'image',
        FootnoteBlock() => 'footnote',
        DividerBlock() => 'divider',
      };

      expect(describe(const TextBlock(id: '1', text: 'x')), 'text');
      expect(describe(const ImageBlock(id: '2', assetId: 'a')), 'image');
      expect(describe(const FootnoteBlock(id: '3', text: 'n')), 'footnote');
      expect(describe(const DividerBlock(id: '4')), 'divider');
    });

    test('wire values round-trip for persistence', () {
      for (final BlockKind kind in BlockKind.values) {
        expect(BlockKind.fromWire(kind.wire), kind);
      }
    });
  });
}
