import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WordCount', () {
    test('counts every non-whitespace rune', () {
      expect(WordCount.ofText('春江潮水'), 4);
      expect(WordCount.ofText('春江 潮水'), 4);
      expect(WordCount.ofText('a b c'), 3);
    });

    test('ignores newlines, tabs and ideographic spaces', () {
      expect(WordCount.ofText('第一行\n第二行'), 6);
      expect(WordCount.ofText('\t \u3000\n\r'), 0);
      expect(WordCount.ofText(''), 0);
    });

    test('counts punctuation like txt2book does', () {
      expect(WordCount.ofText('你好，世界。'), 6);
    });

    test('counts surrogate pairs as one character', () {
      expect(WordCount.ofText('𠮷'), 1);
    });

    test('sums text blocks only', () {
      const List<Block> blocks = <Block>[
        TextBlock(id: '1', text: '一二三'),
        ImageBlock(id: '2', assetId: 'a1', caption: '图注'),
        DividerBlock(id: '3'),
        TextBlock(id: '4', text: '四五'),
      ];
      expect(WordCount.ofBlocks(blocks), 5);
    });
  });
}
