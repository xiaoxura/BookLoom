import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/parsing/txt_encoding.dart';
import 'package:bookloom/core/parsing/txt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> bodyOf(Chapter chapter) => chapter.blocks
    .whereType<TextBlock>()
    .map((TextBlock block) => block.text)
    .toList();

void main() {
  const bookId = 'book-test';

  test('empty or whitespace-only TXT yields no importable chapters', () {
    for (final text in <String>['', '  \r\n\u3000\u200b\t']) {
      final result = parseTxtText(text, bookId: bookId, filename: '空书.txt');
      expect(result.chapters, isEmpty);
      expect(
        result.warnings.map((warning) => warning.code),
        contains('empty_source'),
      );
    }
  });

  test('self-authored fixture yields front matter, volumes, chapters, and source lines', () {
    final text = File('test/fixtures/txt/lighthouse.txt').readAsStringSync();
    final result = parseTxtText(text, bookId: bookId, filename: '灯塔.txt');
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '内容简介',
      '第一卷 海边来信',
      '第一章 守灯人',
      '第二章 雨夜',
      '第二卷 归航',
      '第三章 新地图',
    ]);
    expect(result.chapters.first.frontMatter, isTrue);
    expect(result.chapters[1].level, 1);
    expect(result.chapters[2].parentId, result.chapters[1].id);
    expect(result.chapters[5].parentId, result.chapters[4].id);
    expect(result.chapters[2].order, 2);
    expect(bodyOf(result.chapters[2]), <String>['阿澄在清晨点亮灯。', '远处有船慢慢靠岸。']);
    expect(result.sourceLocations[result.chapters[2].id]?.line, 5);
  });

  test(
    'normalizes line endings and invisible controls without losing content',
    () {
      final result = parseTxtText(
        '\uFEFF第一章 起航\r\n海\u0000面\u200b明亮。\r第二章 返港\n船回来了。',
        bookId: bookId,
        filename: '航线.txt',
      );
      expect(result.chapters.map((chapter) => chapter.title), <String>[
        '第一章 起航',
        '第二章 返港',
      ]);
      expect(bodyOf(result.chapters.first), <String>['海面明亮。']);
    },
  );

  test('Unicode line and paragraph separators preserve text boundaries', () {
    final result = parseTxtText(
      '第一章 星光\u2028The harbor was quiet\u2028and the sky was clear.\u2029A new day began.',
      bookId: bookId,
      filename: '星光.txt',
    );
    expect(result.chapters.single.title, '第一章 星光');
    expect(bodyOf(result.chapters.single), <String>[
      'The harbor was quiet and the sky was clear.',
      'A new day began.',
    ]);
  });

  test('keeps indented physical lines as separate paragraphs', () {
    final result = parseTxtText(
      '第一章 灯火\n　　第一盏灯亮了。\n　　第二盏灯也亮了。',
      bookId: bookId,
      filename: '灯火.txt',
    );
    expect(bodyOf(result.chapters.single), <String>['第一盏灯亮了。', '第二盏灯也亮了。']);
  });

  test('joins hard-wrapped Chinese and English lines correctly', () {
    final result = parseTxtText(
      '第一章 夜航\n海风越过船舷，\n吹动了纸灯。\n\nThe harbor was still and\nthe lights were warm.',
      bookId: bookId,
      filename: '夜航.txt',
    );
    expect(bodyOf(result.chapters.single), <String>[
      '海风越过船舷，吹动了纸灯。'.replaceFirst('， ', '，'),
      'The harbor was still and the lights were warm.',
    ]);
  });

  test('ad filtering is optional and keeps adjacent paragraphs separate', () {
    const text = '第一章 开门\n门开了。\n请记住本站域名 www.example.com\n风进来了。';
    final filtered = parseTxtText(text, bookId: bookId, filename: '开门.txt');
    final kept = parseTxtText(
      text,
      bookId: bookId,
      filename: '开门.txt',
      options: const ParseOptions(filterAds: false),
    );
    expect(bodyOf(filtered.chapters.single), <String>['门开了。', '风进来了。']);
    expect(bodyOf(kept.chapters.single).join(), contains('www.example.com'));
  });

  test('recovers a chapter heading after an inline site watermark', () {
    final result = parseTxtText(
      '内容简介\n故事发生在河边。\n内容还在处理中第1章 新桥\n桥边站着一个人。',
      bookId: bookId,
      filename: '新桥.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '内容简介',
      '第1章 新桥',
    ]);
    expect(bodyOf(result.chapters.last), <String>['桥边站着一个人。']);
  });

  test('long unpunctuated body is split into bounded blocks', () {
    final result = parseTxtText(
      '第一章 长夜\n${'灯' * 25000}',
      bookId: bookId,
      filename: '长夜.txt',
    );
    expect(bodyOf(result.chapters.single).map((part) => part.length), <int>[
      20000,
      5000,
    ]);
  });

  test('long paragraph chunks never cut a surrogate pair', () {
    final result = parseTxtText(
      '第一章 星图\n${'灯' * 19999}🧭灯',
      bookId: bookId,
      filename: '星图.txt',
    );
    final body = bodyOf(result.chapters.single);
    expect(body, hasLength(2));
    expect(body.first, '灯' * 19999);
    expect(body.last, '🧭灯');
  });

  test('infers title and author from filename and leading text', () {
    final filename = parseTxtText(
      '第一章 风声\n风从窗边经过。',
      bookId: bookId,
      filename: '《风声》 （校对版全本）作者：林澈.txt',
    );
    expect(filename.suggestedMeta.title, '风声');
    expect(filename.suggestedMeta.author, '林澈');

    final leading = parseTxtText(
      '《另一座城》\n作者：陆青\n\n第一章 清晨\n天亮了。',
      bookId: bookId,
      filename: '下载文件.txt',
    );
    expect(leading.suggestedMeta.title, '另一座城');
    expect(leading.suggestedMeta.author, '陆青');
  });

  test(
    'suggests a separate description after a preface without removing it',
    () {
      final result = parseTxtText(
        '前言\n写在前面的话。\n内容简介\n河口有座灯塔。\n\n'
        '守灯人每天记录潮汐。\n第一卷 海边\n第一章 起航\n船离开了港口。',
        bookId: bookId,
        filename: '海边.txt',
      );
      expect(result.suggestedMeta.description, '河口有座灯塔。\n\n守灯人每天记录潮汐。');
      expect(result.chapters.map((chapter) => chapter.title), <String>[
        '前言',
        '内容简介',
        '第一卷 海边',
        '第一章 起航',
      ]);
      expect(bodyOf(result.chapters[1]), <String>['河口有座灯塔。', '守灯人每天记录潮汐。']);
      expect(bodyOf(result.chapters.last), <String>['船离开了港口。']);
    },
  );

  test(
    'accepts explicit same-line description labels and retains their text',
    () {
      for (final label in <String>[
        '内容简介',
        '作品简介',
        '图书简介',
        '简介',
        '文案',
        '內容簡介',
        '作品簡介',
        '圖書簡介',
        '簡介',
      ]) {
        final result = parseTxtText(
          '$label：河口有座灯塔\n第一章 起航\n船离开了港口。',
          bookId: bookId,
          filename: '海边.txt',
        );
        expect(result.suggestedMeta.description, '河口有座灯塔');
        expect(bodyOf(result.chapters.first).join(), contains('河口有座灯塔'));
        expect(bodyOf(result.chapters.last), <String>['船离开了港口。']);
      }
    },
  );

  test('does not infer description from prose or a label inside a chapter', () {
    for (final text in <String>[
      '第一章 起航\n她读过内容简介，却不记得故事。',
      '第一章 起航\n简介\n这只是她写在笔记上的标题。',
      '前言\n这里提到了作品简介，但没有单独的简介区。\n第一章 起航\n船出发了。',
    ]) {
      final result = parseTxtText(text, bookId: bookId, filename: '海边.txt');
      expect(result.suggestedMeta.description, isEmpty);
    }
  });

  test('traditional synopsis ends before following bibliographic fields', () {
    final result = parseTxtText(
      '內容簡介\n燈塔裡的故事。\n分類：奇幻\n字數：十萬\n第一章 啟航\n船離港了。',
      bookId: bookId,
      filename: '海邊.txt',
    );
    expect(result.suggestedMeta.description, '燈塔裡的故事。');
    expect(result.chapters.first.frontMatter, isTrue);
    expect(bodyOf(result.chapters.first).join(), contains('分類：奇幻'));
    expect(bodyOf(result.chapters.last), ['船離港了。']);
  });

  test('same-line description obeys the extraction length limit', () {
    final result = parseTxtText(
      '内容简介：${'潮' * 2001}\n第一章 起航\n船离开了港口。',
      bookId: bookId,
      filename: '海边.txt',
    );
    expect(result.suggestedMeta.description, isEmpty);
    expect(bodyOf(result.chapters.first).join(), contains('潮' * 2001));
  });

  test(
    'empty introduction and following metadata do not become description',
    () {
      final empty = parseTxtText(
        '内容简介\n\n第一章 起航\n船离开了港口。',
        bookId: bookId,
        filename: '海边.txt',
      );
      expect(empty.suggestedMeta.description, isEmpty);

      final metadata = parseTxtText(
        '图书简介\n河口有座灯塔。\n作者：林澈\n分类：奇幻\n第一章 起航\n船出发了。',
        bookId: bookId,
        filename: '海边.txt',
      );
      expect(metadata.suggestedMeta.description, '河口有座灯塔。');
      expect(bodyOf(metadata.chapters.first).join(), contains('作者：林澈'));
    },
  );

  test(
    'rejects unbounded introduction text without changing source chapters',
    () {
      final longText = '灯' * 2001;
      final result = parseTxtText(
        '简介\n$longText\n第一章 起航\n船离开了港口。',
        bookId: bookId,
        filename: '海边.txt',
      );
      expect(result.suggestedMeta.description, isEmpty);
      expect(bodyOf(result.chapters.first).join(), contains(longText));
      expect(bodyOf(result.chapters.last), <String>['船离开了港口。']);
    },
  );

  test('automatic and manual chapter rules share description extraction', () {
    const text = '文案：河口有座灯塔\n第一章 起航\n船离开了港口。';
    for (final options in <ParseOptions>[
      const ParseOptions(),
      const ParseOptions(rulePreset: 'numbered'),
      const ParseOptions(
        rulePreset: 'custom',
        ruleSpec: <String, Object?>{
          'name': '数字章节',
          'chapter': r'\d{1,4}、.{1,20}',
        },
      ),
    ]) {
      final result = parseTxtText(
        text,
        bookId: bookId,
        filename: '海边.txt',
        options: options,
      );
      expect(result.suggestedMeta.description, '河口有座灯塔');
    }
  });

  test('GB18030 bytes use the same description parser', () {
    final result = parseTxtBytes(
      Uint8List.fromList(<int>[
        0xc4,
        0xda,
        0xc8,
        0xdd,
        0xbc,
        0xf2,
        0xbd,
        0xe9,
        0xa3,
        0xba,
        0xb7,
        0xe7,
        0xb5,
        0xc6,
        0xa1,
        0xa3,
        0x0a,
        0xb5,
        0xda,
        0xd2,
        0xbb,
        0xd5,
        0xc2,
        0x20,
        0xb3,
        0xf6,
        0xb7,
        0xa2,
        0x0a,
        0xb7,
        0xe7,
        0xb5,
        0xc6,
        0xc1,
        0xc1,
        0xc1,
        0xcb,
        0xa1,
        0xa3,
      ]),
      bookId: bookId,
      filename: '海边.txt',
      options: const ParseOptions(encoding: 'gb18030'),
    );
    expect(result.actualEncoding, 'gb18030');
    expect(result.suggestedMeta.description, '风灯。');
    expect(bodyOf(result.chapters.last), <String>['风灯亮了。']);
  });

  test('a preface is front matter and keeps its original body', () {
    final result = parseTxtText(
      '开篇的话写在这里。\n还有一句。\n\n第一章 早晨\n街上有人。',
      bookId: bookId,
      filename: '早晨.txt',
    );
    expect(result.chapters.first.title, '前言');
    expect(result.chapters.first.frontMatter, isTrue);
    expect(bodyOf(result.chapters.first), <String>['开篇的话写在这里。', '还有一句。']);
  });

  test('heading punctuation and attached title text survive cleanup', () {
    final result = parseTxtText(
      '第1章开始\n门开了。\n第2章 谁家的？你家的\n有人回答。\n第3章 可怕！细思极恐\n灯灭了。',
      bookId: bookId,
      filename: '谜题.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第1章 开始',
      '第2章 谁家的？你家的',
      '第3章 可怕！细思极恐',
    ]);
  });

  test('recognizes an attached question title between numbered chapters', () {
    final result = parseTxtText(
      '内容简介：一段自编简介。\n'
      '第848章 背叛\n港口起了风。\n'
      '第849章教训小媳妇?\n她走进灯塔。\n'
      '第850章 珍贵的眼泪\n天亮了。',
      bookId: bookId,
      filename: '灯塔.txt',
    );
    expect(result.suggestedMeta.description, '一段自编简介。');
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '内容简介',
      '第848章 背叛',
      '第849章 教训小媳妇?',
      '第850章 珍贵的眼泪',
    ]);
    expect(bodyOf(result.chapters[2]), <String>['她走进灯塔。']);
    expect(result.sourceLocations[result.chapters[2].id]?.line, 4);
  });

  test('rejects attached chapter references without rejecting de titles', () {
    final result = parseTxtText(
      '第848章 背叛\n'
      '第849章的草稿整理好了吗?\n'
      '第850章 珍贵的眼泪\n'
      '第851章的确如此?\n'
      '第852章 的故事?\n第853章 结束\n灯熄灭了。',
      bookId: bookId,
      filename: '自编.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第848章 背叛',
      '第850章 珍贵的眼泪',
      '第851章 的确如此?',
      '第852章 的故事?',
      '第853章 结束',
    ]);
    expect(bodyOf(result.chapters.first), contains('第849章的草稿整理好了吗?'));
  });

  test('rejects a range reference but preserves a real combined title', () {
    final result = parseTxtText(
      '第1044章 开始\n第1045~1046章的故事仍在继续\n'
      '第1045~1046章现代番，一百三十\n灯亮了。\n第1047章 结束',
      bookId: bookId,
      filename: '自编.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第1044章 开始',
      '第1045~1046章现代番，一百三十',
      '第1047章 结束',
    ]);
    expect(bodyOf(result.chapters.first), contains('第1045~1046章的故事仍在继续'));
  });

  test(
    'uses custom numbered chapter neighbors for default question titles',
    () {
      final result = parseTxtText(
        '内容简介：灯塔的故事。\n第848章 背叛\n'
        '第849章教训小媳妇?\n灯亮了。\n第850章 珍贵的眼泪',
        bookId: bookId,
        filename: '自编.txt',
        options: const ParseOptions(
          rulePreset: 'custom',
          ruleSpec: <String, Object?>{
            'name': '带空格章节',
            'chapter': r'第\d{1,4}章 .{1,30}',
          },
        ),
      );
      expect(
        result.chapters.map((chapter) => chapter.title),
        contains('第849章 教训小媳妇?'),
      );
      expect(result.suggestedMeta.description, '灯塔的故事。');
    },
  );

  test('does not use custom volumes as numbered chapter neighbors', () {
    final result = parseTxtText(
      '序章\n灯亮了。\n第848章 背叛\n第849章教训小媳妇?\n灯熄灭了。',
      bookId: bookId,
      filename: '自编.txt',
      options: const ParseOptions(
        rulePreset: 'custom',
        ruleSpec: <String, Object?>{'name': '特殊卷', 'volume': r'第848章 .{1,30}'},
      ),
    );
    expect(
      result.chapters.map((chapter) => chapter.title),
      isNot(contains('第849章 教训小媳妇?')),
    );
    expect(result.chapters.expand(bodyOf), contains('第849章教训小媳妇?'));
  });

  test(
    'recognizes adjacent Chinese numbered questions but not unrelated ones',
    () {
      for (final numbers in <List<String>>[
        ['一', '二', '三'],
        ['九', '十', '十一'],
        ['九十九', '一百', '一百零一'],
      ]) {
        final result = parseTxtText(
          '第${numbers[0]}章 开始\n第${numbers[1]}章题目?\n'
          '灯亮了。\n第九百章结局会怎样?\n第${numbers[2]}章 结束',
          bookId: bookId,
          filename: '自编.txt',
        );
        expect(result.chapters.map((chapter) => chapter.title), <String>[
          '第${numbers[0]}章 开始',
          '第${numbers[1]}章 题目?',
          '第${numbers[2]}章 结束',
        ]);
        expect(bodyOf(result.chapters[1]), contains('第九百章结局会怎样?'));
      }
    },
  );

  test('keeps combined chapter ranges as one original heading', () {
    for (final separator in <String>['~', '～', '-', '—']) {
      final rangeTitle = '第1045${separator}1046章现代番，一百三十';
      final result = parseTxtText(
        '第1044章 现代番，一百二十八\n旧信到了。\n'
        '$rangeTitle\n两封信放在桌上。\n'
        '第1047章 现代番，一百三十一\n回信来了。',
        bookId: bookId,
        filename: '书信.txt',
      );
      expect(result.chapters.map((chapter) => chapter.title), <String>[
        '第1044章 现代番，一百二十八',
        rangeTitle,
        '第1047章 现代番，一百三十一',
      ]);
      expect(bodyOf(result.chapters[1]), <String>['两封信放在桌上。']);
    }
  });

  test('accepts an exclamation title and a prefixed chapter heading', () {
    final result = parseTxtText(
      '正文 第1章 起航\n船离开了港口。\n'
      '正文 第2章返航!\n船回来了。\n'
      '正文 第3章 靠岸\n潮水退去。',
      bookId: bookId,
      filename: '航线.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '正文 第1章 起航',
      '正文 第2章返航!',
      '正文 第3章 靠岸',
    ]);
    expect(bodyOf(result.chapters[1]), <String>['船回来了。']);
  });

  test('keeps consecutive punctuated chapter titles in order', () {
    final result = parseTxtText(
      '第1章 起航\n船离开了港口。\n'
      '第2章 风会停吗?\n风仍在吹。\n'
      '第3章雨停了，船回来了?\n船靠岸了。',
      bookId: bookId,
      filename: '航线.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第1章 起航',
      '第2章 风会停吗?',
      '第3章 雨停了，船回来了?',
    ]);
    expect(bodyOf(result.chapters.last), <String>['船靠岸了。']);
  });

  test('combined chapters still participate in leading TOC removal', () {
    const title = '第1045~1046章现代番，一百三十';
    const text =
        '目录\n第1044章 旧信\n$title\n第1047章 回信\n第1048章 尾声\n\n'
        '第1044章 旧信\n旧信到了。\n$title\n两封信放在桌上。\n'
        '第1047章 回信\n回信来了。\n第1048章 尾声\n灯熄了。';
    final result = parseTxtText(text, bookId: bookId, filename: '书信.txt');
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第1044章 旧信',
      title,
      '第1047章 回信',
      '第1048章 尾声',
    ]);
    expect(bodyOf(result.chapters[1]), <String>['两封信放在桌上。']);
  });

  test('built-in rule presets keep automatic chapter recognition', () {
    const text =
        '第848章 背叛\n港口起了风。\n'
        '第849章教训小媳妇?\n她走进灯塔。\n'
        '第850章 珍贵的眼泪\n天亮了。';
    for (final preset in <String>['auto', 'ixdzs', 'biquge', 'numbered']) {
      final result = parseTxtText(
        text,
        bookId: bookId,
        filename: '灯塔.txt',
        options: ParseOptions(rulePreset: preset),
      );
      expect(result.chapters.map((chapter) => chapter.title), <String>[
        '第848章 背叛',
        '第849章 教训小媳妇?',
        '第850章 珍贵的眼泪',
      ]);
    }
  });

  test(
    'does not promote question-like narrative with unrelated chapter numbers',
    () {
      final result = parseTxtText(
        '第848章 背叛\n港口起了风。\n'
        '第900章的草稿整理好了吗?\n'
        '第849章教训小媳妇?\n她走进灯塔。\n'
        '第850章 珍贵的眼泪\n天亮了。',
        bookId: bookId,
        filename: '灯塔.txt',
      );
      expect(result.chapters.map((chapter) => chapter.title), <String>[
        '第848章 背叛',
        '第849章 教训小媳妇?',
        '第850章 珍贵的眼泪',
      ]);
      expect(bodyOf(result.chapters.first).join(), contains('第900章的草稿整理好了吗?'));
    },
  );

  test('does not treat a chapter-like sentence or part word as a heading', () {
    final result = parseTxtText(
      '第1章 开始\n她翻到第2章，问结局会怎样?\n'
      '第2部门终于开门了!\n第2章 结束\n门关了。',
      bookId: bookId,
      filename: '故事.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第1章 开始',
      '第2章 结束',
    ]);
    expect(bodyOf(result.chapters.first).join(), contains('她翻到第2章，问结局会怎样?'));
    expect(bodyOf(result.chapters.first).join(), contains('第2部门终于开门了!'));
  });

  test('part words are body text while a separated 部 heading is a volume', () {
    final result = parseTxtText(
      '第一部分 概述\n第一部门打开了门。\n第一部队走过桥。\n第一部件放在桌上。\n\n第二部 归途\n第一章 回家\n她终于回家了。',
      bookId: bookId,
      filename: '归途.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '前言',
      '第二部 归途',
      '第一章 回家',
    ]);
    expect(bodyOf(result.chapters.first).join(), contains('第一部分'));
  });

  test('final chapter, afterword, Section, and Page are headings', () {
    final result = parseTxtText(
      '第一章 开始\n路很长。\n最终章 归途\n路到尽头。\n完本感言\n谢谢读者。\nSection 2 Notes\nA short note.\nPage 9\nOne last line.',
      bookId: bookId,
      filename: '长路.txt',
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第一章 开始',
      '最终章 归途',
      '完本感言',
      'Section 2 Notes',
      'Page 9',
    ]);
  });

  test('dense leading table of contents is dropped only when body follows', () {
    final toc = List<String>.generate(
      8,
      (i) => '第${i + 1}章 标题${i + 1}',
    ).join('\n');
    final body = List<String>.generate(
      8,
      (i) => '第${i + 1}章 标题${i + 1}\n第${i + 1}段从灯塔出发。',
    ).join('\n\n');
    final result = parseTxtText(
      '$toc\n\n$body',
      bookId: bookId,
      filename: '灯塔.txt',
    );
    expect(result.chapters, hasLength(8));
    expect(bodyOf(result.chapters.first), <String>['第1段从灯塔出发。']);
  });

  test(
    'four-entry table of contents is removed when matching body follows',
    () {
      const text =
          '目录\n第1章 甲\n第2章 乙\n第3章 丙\n第4章 丁\n\n'
          '第1章 甲\n甲走到桥边。\n第2章 乙\n乙看见灯塔。\n'
          '第3章 丙\n丙打开了门。\n第4章 丁\n丁写下地图。';
      final result = parseTxtText(text, bookId: bookId, filename: '四章.txt');
      expect(result.chapters.map((chapter) => chapter.title), <String>[
        '第1章 甲',
        '第2章 乙',
        '第3章 丙',
        '第4章 丁',
      ]);
      expect(bodyOf(result.chapters.first), <String>['甲走到桥边。']);
      expect(result.chapters.first.frontMatter, isFalse);
    },
  );

  test(
    'closely spaced volume chapters with one-line bodies stay structured',
    () {
      const text = '第1卷\n第1章\n甲。\n第2章\n乙。\n第2卷\n第3章\n丙。';
      final result = parseTxtText(text, bookId: bookId, filename: '短章.txt');
      expect(result.chapters.map((chapter) => chapter.title), <String>[
        '第1卷',
        '第1章',
        '第2章',
        '第2卷',
        '第3章',
      ]);
      expect(result.chapters.map((chapter) => chapter.level), <int>[
        1,
        2,
        2,
        1,
        2,
      ]);
      expect(bodyOf(result.chapters[1]), <String>['甲。']);
      expect(bodyOf(result.chapters[2]), <String>['乙。']);
      expect(bodyOf(result.chapters[4]), <String>['丙。']);
      expect(result.chapters[1].parentId, result.chapters[0].id);
      expect(result.chapters[2].parentId, result.chapters[0].id);
      expect(result.chapters[4].parentId, result.chapters[3].id);
    },
  );

  test(
    'a heading-only document degrades instead of creating empty chapters',
    () {
      final text = List<String>.generate(40, (i) => '第${i + 1}章 标题').join('\n');
      final result = parseTxtText(text, bookId: bookId, filename: '只有目录.txt');
      expect(result.chapters, hasLength(1));
      expect(
        result.warnings.map((warning) => warning.code),
        contains('no_headings'),
      );
      expect(bodyOf(result.chapters.single).join(), contains('第1章 标题'));
    },
  );

  test('midbook 目录 text is retained as body', () {
    final result = parseTxtText(
      '第一章 出发\n目录放在书桌上。\n\n第二章 返回\n她照着目录找到了路。',
      bookId: bookId,
      filename: '路线.txt',
    );
    expect(result.chapters, hasLength(2));
    expect(bodyOf(result.chapters.first), contains('目录放在书桌上。'));
  });

  test('blank-separated untitled blocks become chapters', () {
    final text = List<String>.generate(
      6,
      (i) => '场景${i + 1}\n灯亮了。\n门打开了。',
    ).join('\n\n');
    final result = parseTxtText(text, bookId: bookId, filename: '场景.txt');
    expect(result.chapters, hasLength(6));
    expect(result.chapters.first.title, '场景1');
  });

  test('unstructured text degrades to one chapter with a warning', () {
    final result = parseTxtText(
      '只有一段话。\n还有一段话。',
      bookId: bookId,
      filename: '短文.txt',
    );
    expect(result.chapters, hasLength(1));
    expect(result.chapters.single.title, '正文');
    expect(
      result.warnings.map((warning) => warning.code),
      contains('no_headings'),
    );
  });

  test('chapter and block ids are UUID v4 and unique', () {
    final result = parseTxtText(
      '第一章 起点\n灯亮了。\n第二章 终点\n门关了。',
      bookId: bookId,
      filename: '路线.txt',
    );
    final ids = <String>[
      ...result.chapters.map((chapter) => chapter.id),
      ...result.chapters.expand(
        (chapter) => chapter.blocks.map((block) => block.id),
      ),
    ];
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });
}
