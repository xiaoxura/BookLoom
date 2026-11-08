import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/editing/rule_heading_mapping.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mapped visible prefixes retain the same number in manuscript audit',
    () {
      for (final (title, number) in [
        ('第１３章 风雨', 13),
        ('第壹拾參章 风雨', 13),
        ('第二〇二四章 风雨', 2024),
        ('第999999999章 风雨', 999999999),
        ('第十三集 风雨', 13),
        ('正文·第 １３ 回 风雨', 13),
      ]) {
        final mapped = RuleHeadingMapping.composeTitle(
          title: title,
          number: number,
          headingLevel: 2,
        );
        final now = DateTime.utc(2026, 11, 7);
        final report = Proofreading.audit(
          Book(
            id: 'book',
            meta: BookMeta(title: 'number mapping'),
            createdAt: now,
            updatedAt: now,
            chapters: [
              Chapter(
                id: 'before',
                bookId: 'book',
                title: '第1~${number - 1}章 前文',
              ),
              Chapter(id: 'mapped', bookId: 'book', title: mapped),
              Chapter(id: 'duplicate', bookId: 'book', title: '第$number章 同号'),
            ],
          ),
        );
        expect(report.counts[AuditIssueKind.missingNumber], 0, reason: title);
        expect(report.counts[AuditIssueKind.duplicateNumber], 1, reason: title);
      }
    },
  );
  test('parses explicit positive numerals without inferring sequence', () {
    for (final entry in <String, int>{
      '13': 13,
      '００１３': 13,
      '十三': 13,
      '一十三': 13,
      '壹拾參': 13,
      '二〇二四': 2024,
      '兩百零三': 203,
      '一千零一十': 1010,
      '一万零一': 10001,
      '十二万三千四百五十六': 123456,
      '一億零一萬零一': 100010001,
      '九亿九千九百九十九万九千九百九十九': 999999999,
      '999999999': 999999999,
    }.entries) {
      expect(
        RuleHeadingMapping.parseNumber(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
    for (final raw in [
      '',
      '0',
      '零',
      '-1',
      '+1',
      '1.5',
      '1e2',
      '13~14',
      '十三到十四',
      '一百二',
      '十二三',
      '百百',
      '十十',
      '一万万',
      '一亿亿',
      '1000000000',
      '十亿',
      '第十三章',
      '一2',
      '一千零零一',
      '😀',
    ]) {
      expect(RuleHeadingMapping.parseNumber(raw), isNull, reason: raw);
    }
  });

  test(
    'composes a visible number and preserves equivalent source prefixes',
    () {
      expect(
        RuleHeadingMapping.composeTitle(
          title: '夜雨😀',
          number: 13,
          headingLevel: 2,
        ),
        '第13章 夜雨😀',
      );
      expect(
        RuleHeadingMapping.composeTitle(
          title: '归来',
          number: 2,
          headingLevel: 1,
        ),
        '第2卷 归来',
      );
      expect(
        RuleHeadingMapping.composeTitle(
          title: '第十三回 夜雨',
          number: 13,
          headingLevel: 2,
        ),
        '第十三回 夜雨',
      );
      expect(
        RuleHeadingMapping.composeTitle(
          title: '第２卷 归来',
          number: 2,
          headingLevel: 1,
        ),
        '第２卷 归来',
      );
      for (final (title, number, level) in [
        ('第十二章 夜雨', 13, 2),
        ('第十三卷 夜雨', 13, 2),
        ('第十三章 夜雨', 13, 1),
        ('第 12 章 夜雨', 13, 2),
        ('正文·第 十二 章 夜雨', 13, 2),
        ('第 13 卷 夜雨', 13, 2),
        ('第13~14章 夜雨', 13, 2),
        ('正文·第 十三 ～ 十四 回 夜雨', 13, 2),
        ('第十十章 夜雨', 20, 2),
        (' 夜雨', 13, 2),
        ('夜\n雨', 13, 2),
        ('夜雨', 0, 2),
        ('夜雨', 13, 3),
        ('夜雨', 1000000000, 2),
        ('雨' * 256, 13, 2),
      ]) {
        expect(
          () => RuleHeadingMapping.composeTitle(
            title: title,
            number: number,
            headingLevel: level,
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );
}
