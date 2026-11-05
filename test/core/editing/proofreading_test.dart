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
  test('audit covers eight kinds with chapter and block locations', () {
    final report = Proofreading.audit(
      book(<Chapter>[
        chapter('v1', '第一卷', level: 1),
        chapter(
          'c1',
          '第1章 起始',
          parentId: 'v1',
          blocks: <Block>[text('b1', '字' * 120)],
        ),
        chapter('c3', '第3章 空白', parentId: 'v1'),
        chapter(
          'c3b',
          '第3章 空白',
          parentId: 'v1',
          blocks: <Block>[text('ad', '请记住本站')],
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
}
