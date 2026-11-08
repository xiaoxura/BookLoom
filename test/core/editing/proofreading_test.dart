import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/editing/safe_regex.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

Book book(List<Chapter> chapters) => Book(
  id: 'book',
  meta: BookMeta(title: '测试书'),
  chapters: chapters,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Chapter chapter(
  String id,
  String title, {
  String? parentId,
  int level = 2,
  bool frontMatter = false,
  List<Block> blocks = const <Block>[],
}) => Chapter(
  id: id,
  bookId: 'book',
  title: title,
  parentId: parentId,
  level: level,
  frontMatter: frontMatter,
  blocks: blocks,
);

TextBlock text(String id, String value) => TextBlock(id: id, text: value);

void main() {
  test('audit covers ten kinds with chapter and block locations', () {
    final report = Proofreading.audit(
      book(<Chapter>[
        chapter('v1', '第一卷', level: 1),
        chapter(
          'c1',
          '第一章 起始',
          parentId: 'v1',
          blocks: <Block>[text('b1', '字' * 100)],
        ),
        chapter('c3', '第3章 空白', parentId: 'v1'),
        chapter(
          'c3b',
          '第3章 空白',
          parentId: 'v1',
          blocks: <Block>[text('ad', '请记住本站'), text('dup', '字' * 100)],
        ),
        chapter(
          'c4',
          '第4章 漫长',
          parentId: 'v1',
          blocks: <Block>[text('long', '字' * 30001)],
        ),
        chapter('v2', '第二卷', level: 1),
      ]),
    );
    for (final kind in AuditIssueKind.values) {
      expect(report.counts[kind], greaterThan(0), reason: '$kind');
    }
    expect(report.counts[AuditIssueKind.missingNumber], 1);
    expect(report.counts[AuditIssueKind.duplicateNumber], 1);
    expect(report.counts[AuditIssueKind.emptyChapter], 1);
    expect(report.counts[AuditIssueKind.duplicateTitle], 1);
    expect(report.counts[AuditIssueKind.emptyVolume], 1);
    expect(report.counts[AuditIssueKind.titleFormat], 1);
    expect(report.counts[AuditIssueKind.duplicateContent], 1);
    expect(
      report.issues
          .singleWhere((issue) => issue.kind == AuditIssueKind.duplicateContent)
          .blockId,
      'dup',
    );
    expect(
      report.issues
          .singleWhere((issue) => issue.kind == AuditIssueKind.titleFormat)
          .chapterId,
      'c1',
    );
    final ad = report.issues.singleWhere(
      (issue) => issue.kind == AuditIssueKind.adLeftover,
    );
    expect((ad.chapterId, ad.blockId), ('c3b', 'ad'));
    expect(report.total, report.counts.values.reduce((a, b) => a + b));
  });

  test('audit counts all findings but retains twenty per kind', () {
    final chapters = <Chapter>[
      for (var i = 1; i <= 25; i++) chapter('c$i', '第$i章'),
    ];
    final report = Proofreading.audit(book(chapters));
    expect(report.counts[AuditIssueKind.emptyChapter], 25);
    expect(
      report.issues.where((issue) => issue.kind == AuditIssueKind.emptyChapter),
      hasLength(20),
    );
  });

  test(
    'audit treats a combined chapter as an interval without a false gap',
    () {
      final report = Proofreading.audit(
        book(<Chapter>[
          chapter('one', '第1章 起始', blocks: <Block>[text('b1', '字' * 120)]),
          chapter('range', '第2~3章合章', blocks: <Block>[text('b2', '字' * 120)]),
          chapter('four', '第4章 归途', blocks: <Block>[text('b3', '字' * 120)]),
        ]),
      );
      expect(report.counts[AuditIssueKind.missingNumber], 0);
      expect(report.counts[AuditIssueKind.duplicateNumber], 0);
    },
  );

  test('audit reports range overlap and the real gap after its union', () {
    final report = Proofreading.audit(
      book(<Chapter>[
        chapter('range', '第1～3章 开始'),
        chapter('overlap', '第3-5章 重叠'),
        chapter('inside', '第4章 重复'),
        chapter('after', '第7章 继续'),
      ]),
    );
    expect(report.counts[AuditIssueKind.duplicateNumber], 2);
    expect(report.counts[AuditIssueKind.missingNumber], 1);
    expect(
      report.issues
          .where((issue) => issue.kind == AuditIssueKind.duplicateNumber)
          .map((issue) => issue.chapterId),
      <String>['overlap', 'inside'],
    );
    final gap = report.issues.singleWhere(
      (issue) => issue.kind == AuditIssueKind.missingNumber,
    );
    expect(gap.chapterId, 'after');
    expect(gap.message, contains('6 至 6'));
  });

  test('audit scans a wide range without expanding each covered number', () {
    final report = Proofreading.audit(
      book(<Chapter>[
        chapter('wide', '第1—99999999章 合章'),
        chapter('overlap', '第99999999章 重复'),
      ]),
    );
    expect(report.counts[AuditIssueKind.missingNumber], 0);
    expect(report.counts[AuditIssueKind.duplicateNumber], 1);
  });

  test('Chinese and formal numerals report only chapter two as missing', () {
    for (final (first, third) in <(String, String)>[
      ('第一章 起始', '第三章 继续'),
      ('第壹章 起始', '第叁章 继续'),
    ]) {
      final report = Proofreading.audit(
        book(<Chapter>[chapter('first', first), chapter('third', third)]),
      );
      final gaps = report.issues
          .where((issue) => issue.kind == AuditIssueKind.missingNumber)
          .map((issue) => issue.numberGap!)
          .toList();

      expect(
        gaps.map((gap) => (gap.firstMissing, gap.lastMissing)),
        <(int, int)>[(2, 2)],
        reason: '$first → $third',
      );
      expect(report.counts[AuditIssueKind.duplicateNumber], 0);
    }
  });

  test(
    'zero glyphs in the tens place and 两 keep chapter numbers contiguous',
    () {
      for (final titles in <List<String>>[
        <String>['第1～102章', '第一百〇三章', '第104章'],
        <String>['第1～102章', '第一百零三章', '第104章'],
        <String>['第一章', '第两章', '第三章'],
      ]) {
        final report = Proofreading.audit(
          book(<Chapter>[
            for (final (index, title) in titles.indexed)
              chapter('c$index', title),
          ]),
        );

        expect(
          report.counts[AuditIssueKind.missingNumber],
          0,
          reason: titles.join(', '),
        );
        expect(
          report.counts[AuditIssueKind.duplicateNumber],
          0,
          reason: titles.join(', '),
        );
      }
    },
  );

  test('numbering restarts by volume and keeps numeral style and suffix', () {
    final source = book(<Chapter>[
      chapter('v1', '第一卷', level: 1),
      chapter('a', '第七章 开始', parentId: 'v1'),
      chapter('b', '第08章·继续', parentId: 'v1'),
      chapter('extra', '番外 一', parentId: 'v1'),
      chapter('v2', '第二卷', level: 1),
      chapter('c', '第九章 重启', parentId: 'v2'),
      chapter('d', '第10章 结束', parentId: 'v2'),
    ]);
    final preview = Proofreading.previewRenumber(source, baseRevision: 17);
    expect(preview.baseRevision, 17);
    expect(preview.patches.map((patch) => patch.after), <String>[
      '第一章 开始',
      '第02章·继续',
      '第一章 重启',
      '第2章 结束',
    ]);
    expect(preview.patches.every((patch) => patch.blockId == null), isTrue);
    expect(preview.patches.any((patch) => patch.chapterId == 'extra'), isFalse);
    expect(source.chapters[1].title, '第七章 开始');
  });

  test(
    'renumber preserves range width, separator, span, and chapter count',
    () {
      final source = book(<Chapter>[
        chapter('start', '第7章 开始'),
        chapter('range', '第08～09章现代番，一百三十'),
        chapter('end', '第10章 结束'),
      ]);
      final preview = Proofreading.previewRenumber(source, baseRevision: 9);
      expect(preview.baseRevision, 9);
      expect(preview.patches.map((patch) => patch.after), <String>[
        '第1章 开始',
        '第02～03章现代番，一百三十',
        '第4章 结束',
      ]);
      expect(preview.patches.map((patch) => patch.chapterId), <String>[
        'start',
        'range',
        'end',
      ]);
      expect(preview.samples[1].match, '08～09');
      expect(source.chapters, hasLength(3));
      expect(source.chapters[1].title, '第08～09章现代番，一百三十');
    },
  );

  test('renumber rejects a reversed range rather than skipping it', () {
    for (final title in <String>['第8~7章 倒序', '第0~1章 零起点']) {
      expect(
        () => Proofreading.previewRenumber(
          book(<Chapter>[chapter('invalid', title)]),
          baseRevision: 0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('renumber advances past an unchanged range and rejects overflow', () {
    final unchanged = Proofreading.previewRenumber(
      book(<Chapter>[
        chapter('one', '第1章 开始'),
        chapter('range', '第2~3章 合章'),
        chapter('four', '第4章 结束'),
      ]),
      baseRevision: 0,
    );
    expect(unchanged.hits, 0);
    expect(
      () => Proofreading.previewRenumber(
        book(<Chapter>[
          chapter('range', '第1~99999999章 合章'),
          chapter('next', '第2章 后续'),
        ]),
        baseRevision: 0,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('missed chapter candidates carry chapter and block identities', () {
    final source = book(<Chapter>[
      chapter(
        'a',
        '第1章 正文',
        blocks: <Block>[
          text('ordinary', '第9章讲的是一段往事。'),
          text('candidate', '第2章 失落'),
          const FootnoteBlock(id: 'foot', text: '第3章 脚注'),
        ],
      ),
    ]);
    final found = Proofreading.findMissedChapters(source);
    expect(found, hasLength(1));
    expect((found.single.chapterId, found.single.blockId), ('a', 'candidate'));
    expect(found.single.blockIndex, 1);
  });

  test('missed candidates in an already imported book include both gaps', () {
    final source = book(<Chapter>[
      chapter(
        'c848',
        '第848章 背叛',
        blocks: <Block>[
          text('prose', '第849章的草稿整理好了吗?'),
          text('unrelated', '第900章教训小媳妇?'),
          text('question', '第849章教训小媳妇?'),
        ],
      ),
      chapter('c850', '第850章 珍贵的眼泪'),
      chapter(
        'c1044',
        '第1044章 现代番，一百二十八',
        blocks: <Block>[
          text('range', '第1045~1046章现代番，一百三十'),
          text('watermark', '内容还在处理中第1045～1046章现代番，一百三十'),
          text('range-prose', '第1045~1046章的故事仍在继续'),
        ],
      ),
      chapter('c1047', '第1047章 现代番，一百三十一'),
    ]);
    final found = Proofreading.findMissedChapters(source);
    expect(found.map((candidate) => candidate.blockId), <String>[
      'question',
      'range',
      'watermark',
    ]);
    expect(found.first.chapterId, 'c848');
    expect(found.first.blockIndex, 2);
    expect(found.last.chapterId, 'c1044');
  });

  test('literal replacement treats dollar syntax literally and scans only title/body', () {
    final source = book(<Chapter>[
      chapter(
        'a',
        '甲甲',
        blocks: <Block>[
          text('p', '甲'),
          const FootnoteBlock(id: 'f', text: '甲'),
        ],
      ),
    ]);
    final preview = Proofreading.previewReplace(
      source,
      baseRevision: 5,
      options: const ReplaceOptions(find: '甲', replace: r'$1$&$$'),
    );
    expect(preview.hits, 3);
    expect(preview.patches, hasLength(2));
    expect(preview.patches.first.after, r'$1$&$$$1$&$$');
    expect(preview.patches.last.after, r'$1$&$$');
    expect(preview.patches.any((patch) => patch.blockId == 'f'), isFalse);
    expect(preview.samples.first.before, isEmpty);
    expect(preview.samples.first.after, '甲');
  });

  test(
    'regex replacement supports captures, whole match and escaped dollar',
    () {
      final source = book(<Chapter>[chapter('a', '第12章')]);
      final preview = Proofreading.previewReplace(
        source,
        baseRevision: 3,
        options: const ReplaceOptions(
          find: r'(第)(\d+)',
          replace: r'$2-$$-$&-$1',
          scope: ReplaceScope.title,
          regex: true,
        ),
      );
      expect(preview.hits, 1);
      expect(preview.patches.single.after, r'12-$-第12-第章');
      expect(preview.samples.single.match, '第12');
    },
  );

  test('Unicode zero-width match advances and preserves surrogate pairs', () {
    final preview = Proofreading.previewReplace(
      book(<Chapter>[
        chapter('a', '标题', blocks: <Block>[text('p', '😀')]),
      ]),
      baseRevision: 0,
      options: const ReplaceOptions(
        find: r'^|$',
        replace: '*',
        scope: ReplaceScope.body,
        regex: true,
      ),
    );
    expect(preview.hits, 2);
    expect(preview.patches.single.after, '*😀*');
  });

  test('unsafe and unsupported regex syntax is rejected before scanning', () {
    for (final pattern in <String>[
      r'(a+)+',
      r'(a|aa)+',
      r'a+a+',
      r'(a+)(a+)',
      r'.*',
      r'(a)\1',
      r'(?<=a)b',
      r'\p{L}',
    ]) {
      expect(
        () => SafeRegex.compile(pattern, caseSensitive: true),
        throwsA(isA<ValidationFailure>()),
        reason: pattern,
      );
    }
    expect(
      () => Proofreading.previewReplace(
        book(<Chapter>[chapter('a', '第1章')]),
        baseRevision: 0,
        options: const ReplaceOptions(
          find: r'(第)',
          replace: r"$'",
          regex: true,
        ),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('input limits are validated', () {
    final source = book(<Chapter>[chapter('a', '标题')]);
    expect(
      () => Proofreading.previewReplace(
        source,
        baseRevision: 0,
        options: ReplaceOptions(find: 'a' * 201, replace: ''),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => Proofreading.previewReplace(
        source,
        baseRevision: 0,
        options: ReplaceOptions(find: 'a', replace: 'b' * 501),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('duplicate content compares paragraphs inside different blocks', () {
    Chapter body(String id, String title, String value) => Chapter(
      id: id,
      bookId: 'book',
      title: title,
      blocks: <Block>[text('b-$id', value)],
    );
    final shared = '乙' * 150;
    final across = Proofreading.audit(
      book(<Chapter>[
        body('c1', '第1章 一', '${'甲' * 200}\n\n$shared'),
        body('c2', '第2章 二', '$shared\n\n${'丙' * 200}'),
      ]),
    );
    expect(across.counts[AuditIssueKind.duplicateContent], 1);
    expect(
      across.issues
          .singleWhere((value) => value.kind == AuditIssueKind.duplicateContent)
          .chapterId,
      'c2',
    );

    final inside = Proofreading.audit(
      book(<Chapter>[body('c1', '第1章 一', '${'丁' * 150}\n\n${'丁' * 150}')]),
    );
    expect(inside.counts[AuditIssueKind.duplicateContent], 1);

    final distinct = Proofreading.audit(
      book(<Chapter>[
        body('c1', '第1章 一', '${'甲' * 150}\n\n${'乙' * 150}'),
        body('c2', '第2章 二', '${'丙' * 150}\n\n${'丁' * 150}'),
      ]),
    );
    expect(distinct.counts[AuditIssueKind.duplicateContent], 0);
  });

  test('title format audit needs a clear majority and skips ties', () {
    Chapter numbered(String id, String title) => Chapter(
      id: id,
      bookId: 'book',
      title: title,
      blocks: <Block>[text('b-$id', '字' * 120)],
    );
    final mixed = Proofreading.audit(
      book(<Chapter>[
        numbered('a', '第1章 起'),
        numbered('b', '第2章 承'),
        numbered('c', '第3章 转'),
        numbered('d', '第四章 合'),
      ]),
    );
    expect(mixed.counts[AuditIssueKind.titleFormat], 1);
    final issue = mixed.issues.singleWhere(
      (value) => value.kind == AuditIssueKind.titleFormat,
    );
    expect(issue.chapterId, 'd');
    expect(issue.message, contains('中文数字'));

    final tie = Proofreading.audit(
      book(<Chapter>[
        numbered('a', '第1章 起'),
        numbered('b', '第2章 承'),
        numbered('c', '第三章 转'),
        numbered('d', '第四章 合'),
      ]),
    );
    expect(tie.counts[AuditIssueKind.titleFormat], 0);

    final uniform = Proofreading.audit(
      book(<Chapter>[
        numbered('a', '第1章 起'),
        numbered('b', '第2章 承'),
        numbered('c', '第3章 转'),
      ]),
    );
    expect(uniform.counts[AuditIssueKind.titleFormat], 0);

    final marker = Proofreading.audit(
      book(<Chapter>[
        numbered('a', '第1章 起'),
        numbered('b', '第2章 承'),
        numbered('c', '第3章 转'),
        numbered('d', '第4回 合'),
      ]),
    );
    expect(marker.counts[AuditIssueKind.titleFormat], 1);
    expect(
      marker.issues
          .singleWhere((value) => value.kind == AuditIssueKind.titleFormat)
          .message,
      allOf(contains('回'), contains('章')),
    );

    final markerTie = Proofreading.audit(
      book(<Chapter>[
        numbered('a', '第1章 起'),
        numbered('b', '第2章 承'),
        numbered('c', '第3回 转'),
        numbered('d', '第4回 合'),
      ]),
    );
    expect(markerTie.counts[AuditIssueKind.titleFormat], 0);
  });

  test(
    'duplicate content audit ignores short blocks and normalizes spacing',
    () {
      Chapter body(String id, String title, List<Block> blocks) =>
          Chapter(id: id, bookId: 'book', title: title, blocks: blocks);
      final long = '甲' * 200;
      final report = Proofreading.audit(
        book(<Chapter>[
          body('c1', '第1章 一', <Block>[text('a', long)]),
          body('c2', '第2章 二', <Block>[text('b', '  $long  ')]),
          body('c3', '第3章 三', <Block>[text('short', '甲' * 50)]),
        ]),
      );
      expect(report.counts[AuditIssueKind.duplicateContent], 1);
      final issue = report.issues.singleWhere(
        (value) => value.kind == AuditIssueKind.duplicateContent,
      );
      expect(issue.chapterId, 'c2');
      expect(issue.blockId, 'b');
      expect(issue.message, contains('第 1 项'));

      final repeated = Proofreading.audit(
        book(<Chapter>[
          body('c1', '第1章 一', <Block>[text('a', long)]),
          body('c2', '第2章 二', <Block>[text('b', long)]),
          body('c3', '第3章 三', <Block>[text('c', long)]),
        ]),
      );
      expect(repeated.counts[AuditIssueKind.duplicateContent], 2);
    },
  );
}
