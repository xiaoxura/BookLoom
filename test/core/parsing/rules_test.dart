import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/parsing/rules.dart';
import 'package:bookloom/core/parsing/txt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _body(ParseOptions options, String text) =>
    parseTxtText(
          text,
          bookId: 'rules-book',
          filename: '规则.txt',
          options: options,
        ).chapters
        .expand((chapter) => chapter.blocks.whereType<TextBlock>())
        .map((block) => block.text)
        .toList();

void main() {
  test('all six named presets are available', () {
    expect(rulePresetIds, <String>[
      'auto',
      'ixdzs',
      'biquge',
      'numbered',
      'bare-number',
      'english',
    ]);
    for (final id in rulePresetIds) {
      expect(getRulePreset(id)?.id, id);
    }
    expect(getRulePreset('missing'), isNull);
  });

  test('numbered and bare-number presets recognize nonstandard headings', () {
    const numbered = '1. 初见\n灯亮了。\n2、 再会\n门开了。';
    final withNumbered = parseTxtText(
      numbered,
      bookId: 'rules-book',
      filename: '编号.txt',
      options: const ParseOptions(rulePreset: 'numbered'),
    );
    expect(withNumbered.chapters.map((chapter) => chapter.title), <String>[
      '1. 初见',
      '2、 再会',
    ]);
    expect(
      parseTxtText(numbered, bookId: 'rules-book', filename: '编号.txt').chapters,
      hasLength(1),
    );

    final bare = parseTxtText(
      '12\n灯亮了。\n13\n门开了。',
      bookId: 'rules-book',
      filename: '裸号.txt',
      options: const ParseOptions(rulePreset: 'bare-number'),
    );
    expect(bare.chapters.map((chapter) => chapter.title), <String>['12', '13']);
  });

  test('english preset classifies Part as volume and Section as chapter', () {
    final result = parseTxtText(
      'Part II\nSection 2 Harbor\nA quiet morning.\nPage 9\nAnother note.',
      bookId: 'rules-book',
      filename: 'Harbor.txt',
      options: const ParseOptions(rulePreset: 'english'),
    );
    expect(result.chapters.map((chapter) => chapter.level), <int>[1, 2, 2]);
    expect(result.chapters[1].parentId, result.chapters.first.id);
  });

  test('custom chapter and volume patterns must match the whole line', () {
    final options = ParseOptions(
      ruleSpec: RuleSpec(
        name: '章节标记',
        chapter: r'BOOK [0-9]+',
        volume: r'PART [0-9]+',
      ).toMap(),
    );
    final result = parseTxtText(
      'PART 1\nBOOK 1\n灯亮了。\nBOOK 2 附注\n这行仍是正文。',
      bookId: 'rules-book',
      filename: '标记.txt',
      options: options,
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      'PART 1',
      'BOOK 1',
    ]);
    expect(_body(options, 'BOOK 2 附注\n这行仍是正文。').join(), contains('BOOK 2 附注'));
  });

  test(
    'drop removes complete lines even when built-in ad filtering is off',
    () {
      final options = ParseOptions(
        filterAds: false,
        ruleSpec: RuleSpec(name: '站点行', drop: <String>[r'^站点公告']).toMap(),
      );
      final body = _body(
        options,
        '第一章 开始\n灯亮了。\n站点公告 请换地址\n门开了。\n请记住本站域名 www.example.com',
      );
      expect(body.join(), isNot(contains('站点公告')));
      expect(body.join(), contains('请记住本站域名'));
      expect(body, contains('门开了。'));
    },
  );

  test('inlineJunk strips only a recognized heading prefix', () {
    final options = ParseOptions(
      ruleSpec: RuleSpec(name: '水印', inlineJunk: <String>[r'我的站点水印']).toMap(),
    );
    final result = parseTxtText(
      '我的站点水印第1章 开始\n灯亮了。\n我的站点水印第2章 继续\n门开了。',
      bookId: 'rules-book',
      filename: '水印.txt',
      options: options,
    );
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第1章 开始',
      '第2章 继续',
    ]);
    expect(
      result.chapters
          .expand((chapter) => chapter.blocks)
          .map((block) => block.plainText)
          .join(),
      isNot(contains('我的站点水印')),
    );
    expect(
      _body(options, '第一章 开始\n灯亮了，我的站点水印仍在这里。').join(),
      contains('我的站点水印仍在这里'),
    );
  });

  test('preset and custom rules combine drop lists and custom heading', () {
    final options = ParseOptions(
      rulePreset: 'ixdzs',
      ruleSpec: RuleSpec(
        name: '补充',
        chapter: r'BOOK [0-9]+',
        drop: <String>[r'额外公告'],
      ).toMap(),
    );
    final result = parseTxtText(
      'BOOK 1\n灯亮了。\nixdzs 下载阅读\n额外公告 请忽略\n门开了。',
      bookId: 'rules-book',
      filename: '混合.txt',
      options: options,
    );
    expect(result.chapters.single.title, 'BOOK 1');
    final body = result.chapters.single.blocks
        .map((block) => block.plainText)
        .join();
    expect(body, contains('灯亮了。'));
    expect(body, contains('门开了。'));
    expect(body, isNot(contains('ixdzs')));
    expect(body, isNot(contains('额外公告')));
  });

  test('bounded JSON import and export round-trip a rule', () {
    const json =
        r'{"id":"local","name":"本地规则","chapter":"^BOOK [0-9]+$","drop":["站点公告"]}';
    final rule = RuleSpec.fromJsonString(json);
    expect(rule.id, 'local');
    expect(RuleSpec.fromJsonString(rule.toJsonString()).toMap(), rule.toMap());
    expect(rule.toJsonString(), isNot(contains('filterAds')));
  });

  test(
    'validation reports exact fields, types, unknown keys and size limits',
    () {
      expect(validateRuleSpec(null), contains(r'$'));
      expect(
        validateRuleSpec(<String, Object?>{'name': 'x', 'extra': 1}),
        contains('extra'),
      );
      expect(validateRuleSpec(<String, Object?>{'name': ''}), contains('name'));
      expect(
        validateRuleSpec(<String, Object?>{'name': 'x', 'drop': 'text'}),
        contains('drop'),
      );
      expect(
        validateRuleSpec(<String, Object?>{
          'name': 'x',
          'drop': <Object?>['ok', 5],
        }),
        contains('drop[1]'),
      );
      expect(
        validateRuleSpec(<String, Object?>{'name': 'x', 'chapter': '['}),
        contains('chapter'),
      );
      expect(
        validateRuleSpec(<String, Object?>{'name': 'x' * 81}),
        contains('name'),
      );
      expect(
        validateRuleSpec(<String, Object?>{
          'name': 'x',
          'drop': List<String>.filled(17, 'watermark'),
        }),
        contains('drop'),
      );
      expect(
        validateRuleSpec(<String, Object?>{
          'name': 'x',
          'chapter': 'x' * 257,
        }),
        contains('chapter'),
      );
      expect(
        () => RuleSpec.fromJsonString(' ' * 16385),
        throwsA(isA<RuleValidationException>()),
      );
    },
  );

  test('dangerous and JS/Dart incompatible patterns are rejected', () {
    for (final pattern in <String>[
      r'(a+)+',
      r'(a|aa)+',
      r'.*',
      r'(?=第1章)第1章',
      r'(?<=x)y',
      r'(x)\1',
      r'a{0,128}a{0,128}',
      r'[a-z]+[a-z]+',
      r'\p{Han}',
      r'\A第1章',
      r'\u4e00',
      r'\b',
      r'^$',
    ]) {
      expect(
        validateRuleSpec(<String, Object?>{'name': '危险', 'chapter': pattern}),
        contains('chapter'),
        reason: pattern,
      );
    }
  });

  test(
    'bad import leaves an existing valid rule and parsing result intact',
    () {
      final current = RuleSpec(name: '当前规则', chapter: r'BOOK [0-9]+');
      expect(
        () => RuleSpec.fromJsonString('{"name":"坏规则","chapter":"(a+)+"}'),
        throwsA(isA<RuleValidationException>()),
      );
      expect(current.name, '当前规则');
      final options = ParseOptions(ruleSpec: current.toMap());
      expect(
        parseTxtText(
          'BOOK 1\n灯亮了。',
          bookId: 'rules-book',
          filename: '保持.txt',
          options: options,
        ).chapters.single.title,
        'BOOK 1',
      );
    },
  );

  test('long lines skip custom matching, remain in text and emit warning', () {
    final options = ParseOptions(
      filterAds: false,
      ruleSpec: RuleSpec(name: '限长', drop: <String>[r'水印']).toMap(),
    );
    final result = parseTxtText(
      '第一章 开始\n水印${'字' * 600}\n灯亮了。',
      bookId: 'rules-book',
      filename: '长行.txt',
      options: options,
    );
    expect(
      result.warnings.map((warning) => warning.code),
      contains('rule_line_too_long'),
    );
    expect(
      result.chapters.single.blocks.map((block) => block.plainText).join(),
      contains('水印'),
    );
  });
}
