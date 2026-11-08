import 'package:bookloom/core/editing/book_intro.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bookId = 'book';

  Chapter chapter(
    String id,
    String title, {
    List<Block> blocks = const <Block>[],
    bool frontMatter = false,
  }) => Chapter(
    id: id,
    bookId: bookId,
    title: title,
    blocks: blocks,
    frontMatter: frontMatter,
  );

  TextBlock text(String id, String value) => TextBlock(id: id, text: value);

  test('recognizes the screenshot style with wrapped meta lines', () {
    final result = detectBookIntro([
      chapter(
        'intro',
        '前言',
        frontMatter: true,
        blocks: [
          text('b1', '『萌师在上：逆徒别乱来/作者:风与天幕』'),
          text('b2', '『状态:已完结』'),
          text('b3', '『内容简介:穿进修仙小说，肯定要和主角抢机缘啊！我想做女版的嘛！』'),
          text('b4', '正文'),
        ],
      ),
      chapter('c1', '第1章', blocks: [text('b5', '正文开始')]),
    ]);
    expect(result, isNotNull);
    expect(result!.chapterId, 'intro');
    expect(result.description, '穿进修仙小说，肯定要和主角抢机缘啊！我想做女版的嘛！');
  });

  test(
    'recognizes plain marker after book meta and stops at the next meta',
    () {
      final result = detectBookIntro([
        chapter(
          'intro',
          '前言',
          frontMatter: true,
          blocks: [
            text('b1', '『作者:风与天幕』'),
            text('b2', '内容简介：穿进修仙小说。'),
            text('b3', '『字数:100万』'),
            text('b4', '后续内容。'),
          ],
        ),
      ]);
      expect(result!.description, '穿进修仙小说。');
    },
  );

  test('multi-paragraph description ends at a meta or body boundary', () {
    final result = detectBookIntro([
      chapter(
        'intro',
        '前言',
        frontMatter: true,
        blocks: [
          text('b1', '内容简介：'),
          text('b2', '第一段简介。'),
          text('b3', '第二段简介。'),
          text('b4', '『状态:连载中』'),
          text('b5', '不该出现的内容。'),
        ],
      ),
    ]);
    expect(result!.description, '第一段简介。\n第二段简介。');
  });

  test('a chapter titled 内容简介 is itself the description', () {
    final result = detectChapterIntro(
      chapter(
        'intro',
        '内容简介',
        frontMatter: true,
        blocks: [text('b1', '河口有座灯塔。'), text('b2', '作者：林澈')],
      ),
    );
    expect(result!.description, '河口有座灯塔。');
  });

  test('non-candidate and story chapters are never treated as intros', () {
    expect(
      detectBookIntro([
        chapter('c1', '第1章 起航', blocks: [text('b1', '『内容简介:误报』')]),
      ]),
      isNull,
    );
    expect(
      detectChapterIntro(
        chapter(
          'intro',
          '前言',
          frontMatter: true,
          blocks: [text('b1', '一座灯塔，一段传说，他们重新出发了。')],
        ),
      ),
      isNull,
    );
  });

  test('candidates beyond the first few chapters are ignored', () {
    final chapters = <Chapter>[
      for (var i = 1; i <= 6; i++) chapter('c$i', '第$i章'),
    ];
    chapters[4] = chapter(
      'intro',
      '前言',
      frontMatter: true,
      blocks: [text('b1', '『内容简介:太靠后』')],
    );
    expect(detectBookIntro(chapters), isNull);
  });

  test('oversized descriptions stay unrecognized', () {
    final result = detectChapterIntro(
      chapter(
        'intro',
        '前言',
        frontMatter: true,
        blocks: [text('b1', '『内容简介:${'潮' * 2001}』')],
      ),
    );
    expect(result, isNull);
  });

  test('wrapped multi-line description keeps the final closer stripped', () {
    final result = detectChapterIntro(
      chapter(
        'intro',
        '文案',
        blocks: [text('b1', '『内容简介:远航。'), text('b2', '返航。』')],
      ),
    );
    expect(result!.description, '远航。\n返航。');
  });
}
