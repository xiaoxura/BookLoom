import '../model/block.dart';

/// Word/character counting shared by the shelf, the editor and the auditor.
///
/// Current rule (kept identical to txt2book so golden cases stay comparable):
/// every non-whitespace rune counts as one. CJK punctuation counts, as it does
/// upstream. A "Chinese characters + English words" mode can be added later
/// without touching call sites.
abstract final class WordCount {
  static const Set<int> _whitespace = <int>{
    0x0009, // tab
    0x000A, // line feed
    0x000B, // vertical tab
    0x000C, // form feed
    0x000D, // carriage return
    0x0020, // space
    0x00A0, // no-break space
    0x3000, // ideographic space
    0xFEFF, // zero width no-break space
  };

  static int ofText(String text) {
    var count = 0;
    for (final int rune in text.runes) {
      if (!_whitespace.contains(rune)) count++;
    }
    return count;
  }

  /// Counts text blocks only; images, dividers and footnotes are excluded.
  static int ofBlocks(Iterable<Block> blocks) {
    var total = 0;
    for (final Block block in blocks) {
      if (block is TextBlock) total += ofText(block.text);
    }
    return total;
  }
}
