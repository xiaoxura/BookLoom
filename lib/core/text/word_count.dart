import 'package:bookloom/core/model/block.dart';

/// Word/character counting shared by the shelf, the editor and the auditor.
///
/// Every rune outside the ECMAScript `\s` whitespace set counts as one.
/// Punctuation counts; chapter titles are not passed to [ofBlocks].
abstract final class WordCount {
  static const Set<int> _whitespace = <int>{
    0x0009, // tab
    0x000A, // line feed
    0x000B, // vertical tab
    0x000C, // form feed
    0x000D, // carriage return
    0x0020, // space
    0x00A0, // no-break space
    0x1680, // ogham space mark
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005,
    0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
    0x2028, // line separator
    0x2029, // paragraph separator
    0x202F, // narrow no-break space
    0x205F, // medium mathematical space
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
