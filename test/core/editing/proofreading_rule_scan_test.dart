import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_scan.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:flutter_test/flutter_test.dart';

ProofreadingRule rule(
  String id,
  String pattern, {
  ProofreadingRuleKind kind = ProofreadingRuleKind.advertisement,
  ProofreadingRuleTarget target = ProofreadingRuleTarget.bodyLine,
  ProofreadingRuleAction action = ProofreadingRuleAction.exactDeletion,
  ProofreadingMatchMode mode = ProofreadingMatchMode.literal,
  ProofreadingRuleScope scope = ProofreadingRuleScope.book,
  String bookId = 'book',
  int priority = 0,
  bool enabled = true,
  String? positive,
  String? exclude,
  bool wholeLine = false,
  int? titleCaptureGroup,
  int? numberCaptureGroup,
  int headingLevel = 2,
}) => ProofreadingRule.create(
  id: id,
  name: id,
  kind: kind,
  source: ProofreadingRuleSource.user,
  bookId: bookId,
  target: target,
  mode: mode,
  pattern: pattern,
  excludePattern: exclude,
  wholeLineOnly: wholeLine,
  titleCaptureGroup: titleCaptureGroup,
  numberCaptureGroup: numberCaptureGroup,
  headingLevel: headingLevel,
  caseSensitive: true,
  action: action,
  positiveExamples: [positive ?? pattern],
  negativeExamples: const ['无关正文'],
  scope: scope,
  globalScopeConfirmed: scope == ProofreadingRuleScope.global,
  enabled: enabled,
  priority: priority,
);

Book book(List<Chapter> chapters) => Book(
  id: 'book',
  meta: BookMeta(title: '试跑书'),
  chapters: chapters,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  revision: 7,
);

Chapter chapter(String id, List<Block> blocks, {int level = 2}) => Chapter(
  id: id,
  bookId: 'book',
  title: '现有标题$id',
  level: level,
  blocks: blocks,
);

RuleScanResult scan(
  Book source,
  List<ProofreadingRule> rules, {
  RuleScanLimits limits = const RuleScanLimits(),
  bool Function()? isCancelled,
}) => ProofreadingRuleScan.scan(
  source,
  selectedRules: rules,
  loadedChapterIds: source.chapters.map((chapter) => chapter.id).toSet(),
  limits: limits,
  isCancelled: isCancelled,
);

void main() {
  test('number and numeral evidence participate in scan identity', () {
    for (final (pattern, text, expectedNumbers, expectedText) in [
      (r'^(1)(2):(夜雨😀)$', '12:夜雨😀', [1, 2], ['1', '2']),
      (r'^(0(1)):(夜雨😀)$', '01:夜雨😀', [1, 1], ['01', '1']),
    ]) {
      final source = book([
        chapter('one', [TextBlock(id: 'body', text: text)]),
      ]);
      final result = scan(source, [
        for (final group in [1, 2])
          rule(
            'number-$group',
            pattern,
            kind: ProofreadingRuleKind.chapter,
            target: ProofreadingRuleTarget.headingLine,
            action: ProofreadingRuleAction.chapterCandidate,
            mode: ProofreadingMatchMode.safeRegex,
            titleCaptureGroup: 3,
            numberCaptureGroup: group,
            positive: text,
          ),
      ]);
      expect(result.distinctMatches, 2);
      expect(result.samples.map((match) => match.mappedTitle), [
        '夜雨😀',
        '夜雨😀',
      ]);
      expect(
        result.samples.map((match) => match.mappedNumber),
        expectedNumbers,
      );
      expect(result.samples.map((match) => match.numberText), expectedText);
      expect(result.totalConflicts, 1);
      expect(
        result.conflictSamples.single.kind,
        RuleScanConflictKind.chapterBoundary,
      );
      expect(
        result.conflictSamples.single.first.numberText,
        expectedText.first,
      );
    }
  });

  test('an invalid later number aborts the entire trial', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '12:夜雨😀\n0:夜雨😀')]),
    ]);
    final heading = rule(
      'number',
      r'^([^:]+):(夜雨😀)$',
      kind: ProofreadingRuleKind.chapter,
      target: ProofreadingRuleTarget.headingLine,
      action: ProofreadingRuleAction.chapterCandidate,
      mode: ProofreadingMatchMode.safeRegex,
      titleCaptureGroup: 2,
      numberCaptureGroup: 1,
      positive: '12:夜雨😀',
    );
    expect(() => scan(source, [heading]), throwsA(isA<ValidationFailure>()));
  });

  test('same title and range at different levels remain conflicting', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '卷二')]),
    ]);
    final result = scan(source, [
      for (final level in [1, 2])
        rule(
          'heading-$level',
          '卷二',
          kind: ProofreadingRuleKind.chapter,
          target: ProofreadingRuleTarget.headingLine,
          action: ProofreadingRuleAction.chapterCandidate,
          headingLevel: level,
        ),
    ]);
    expect(result.distinctMatches, 2);
    expect(result.samples.map((match) => match.headingLevel), [1, 2]);
    expect(result.totalConflicts, 1);
    expect(
      result.conflictSamples.single.kind,
      RuleScanConflictKind.chapterBoundary,
    );
    expect(result.conflictSamples.single.first.headingLevel, 1);
    expect(result.conflictSamples.single.second.headingLevel, 2);
  });

  test(
    'scans all loaded body text and limits display without losing totals',
    () {
      final source = book([
        chapter('volume', const [], level: 1),
        chapter('one', [
          const TextBlock(id: 'body-1', text: '第一章 新篇\r\n广告😀广告\n尾声'),
          const ImageBlock(id: 'image', assetId: 'cover', caption: '广告'),
          const FootnoteBlock(id: 'footnote', text: '广告'),
          const DividerBlock(id: 'divider'),
        ]),
        chapter('two', [const TextBlock(id: 'body-2', text: '广告')]),
      ]);
      final heading = rule(
        'heading',
        r'^第一章',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
        mode: ProofreadingMatchMode.safeRegex,
        priority: 10,
        positive: '第一章 新篇',
      );
      final ad = rule('ad', '广告');
      final paragraph = rule(
        'paragraph',
        '广告😀广告',
        target: ProofreadingRuleTarget.paragraph,
        action: ProofreadingRuleAction.advertisementCandidate,
      );
      final result = scan(source, [
        ad,
        paragraph,
        heading,
      ], limits: const RuleScanLimits(maxSamples: 2));
      expect(result.executedRuleIds, ['heading', 'ad', 'paragraph']);
      expect(result.matchesByRuleId, {'heading': 1, 'ad': 3, 'paragraph': 1});
      expect(result.totalMatches, 5);
      expect(result.distinctMatches, 5);
      expect(result.samples, hasLength(2));
      expect(result.hiddenMatches, 3);
      expect(result.samples.first.chapterId, 'one');
      expect(result.samples.first.chapterTitle, '现有标题one');
      expect(result.samples.first.blockId, 'body-1');
      expect(result.samples.first.startUtf16, 0);
      expect(result.samples[1].startUtf16, 8);
      expect(result.coverage.chapters, 3);
      expect(result.coverage.textBlocks, 2);
      expect(result.coverage.otherBlocks, 3);
      expect(result.coverage.bodyLines, 4);
      expect(result.coverage.inputUtf16, greaterThan(0));
      expect(result.coverage.scanUnits, 10);
      expect(result.coverage.scanUtf16, greaterThan(0));
      expect(source.chapters[1].blocks[1], isA<ImageBlock>());
      expect((source.chapters[1].blocks[2] as FootnoteBlock).text, '广告');
    },
  );

  test(
    'requires complete bodies and respects explicit selection and scope',
    () {
      final source = book([
        chapter('one', [const TextBlock(id: 'body', text: '广告')]),
        chapter('unloaded', const []),
      ]);
      expect(
        () => ProofreadingRuleScan.scan(
          source,
          selectedRules: [rule('ad', '广告')],
          loadedChapterIds: {'one'},
        ),
        throwsA(isA<ValidationFailure>()),
      );
      final result = scan(source, [
        rule('disabled', '广告', enabled: false),
        rule('other-book', '广告', bookId: 'other'),
        rule('selected-global', '广告', scope: ProofreadingRuleScope.global),
      ]);
      expect(result.executedRuleIds, ['selected-global']);
      expect(result.matchesByRuleId, {'selected-global': 1});
      expect(scan(source, []).totalMatches, 0);
      expect(
        () => scan(source, [rule('same', '广告'), rule('same', '广告')]),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('orders by priority and ID, deduplicates same action and range', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '广告 广告')]),
    ]);
    final result = scan(source, [
      rule('z', '广告', priority: 5),
      rule('a', '广告', priority: 5),
      rule('later', '广告', priority: -1),
    ]);
    expect(result.executedRuleIds, ['a', 'z', 'later']);
    expect(result.totalMatches, 6);
    expect(result.distinctMatches, 2);
    expect(result.samples.map((match) => match.startUtf16), [0, 3]);
    expect(result.samples.first.ruleIds, ['a', 'z', 'later']);
    expect(result.totalConflicts, 0);
  });

  test(
    'same range with different mapped titles remains a chapter conflict',
    () {
      final source = book([
        chapter('one', [const TextBlock(id: 'body', text: '【卷二】夜雨😀')]),
      ]);
      final result = scan(source, [
        rule(
          'whole',
          r'【([^】]+)】(夜雨😀)',
          kind: ProofreadingRuleKind.chapter,
          target: ProofreadingRuleTarget.headingLine,
          action: ProofreadingRuleAction.chapterCandidate,
          mode: ProofreadingMatchMode.safeRegex,
          titleCaptureGroup: 0,
          positive: '【卷二】夜雨😀',
        ),
        rule(
          'title',
          r'【([^】]+)】(夜雨😀)',
          kind: ProofreadingRuleKind.chapter,
          target: ProofreadingRuleTarget.headingLine,
          action: ProofreadingRuleAction.chapterCandidate,
          mode: ProofreadingMatchMode.safeRegex,
          titleCaptureGroup: 2,
          positive: '【卷二】夜雨😀',
        ),
      ]);
      expect(result.totalMatches, 2);
      expect(result.distinctMatches, 2);
      expect(result.samples.map((match) => match.mappedTitle).toSet(), {
        '【卷二】夜雨😀',
        '夜雨😀',
      });
      expect(result.totalConflicts, 1);
      expect(
        result.conflictSamples.single.kind,
        RuleScanConflictKind.chapterBoundary,
      );
      expect(
        {
          result.conflictSamples.single.first.mappedTitle,
          result.conflictSamples.single.second.mappedTitle,
        },
        {'【卷二】夜雨😀', '夜雨😀'},
      );
    },
  );

  test('invalid later capture aborts the whole book trial', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '标题旧\n标题')]),
    ]);
    final heading = rule(
      'optional-title',
      r'^(标题)(旧)?',
      kind: ProofreadingRuleKind.chapter,
      target: ProofreadingRuleTarget.headingLine,
      action: ProofreadingRuleAction.chapterCandidate,
      mode: ProofreadingMatchMode.safeRegex,
      titleCaptureGroup: 2,
      positive: '标题旧',
    );
    expect(() => scan(source, [heading]), throwsA(isA<ValidationFailure>()));
  });

  test('reports competing boundaries and overlapping destructive ranges', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '第一章 广告')]),
    ]);
    final result = scan(source, [
      rule(
        'h1',
        '第一章',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
      ),
      rule(
        'h2',
        '第一章 广告',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
      ),
      rule('d1', '第一章'),
      rule('d2', '一章'),
    ]);
    expect(result.totalConflicts, 6);
    expect(result.conflictSamples.map((conflict) => conflict.kind).toSet(), {
      RuleScanConflictKind.chapterBoundary,
      RuleScanConflictKind.deletionAndChapter,
      RuleScanConflictKind.overlappingDeletions,
    });
    expect(
      () => scan(source, [
        rule(
          'heading',
          '第一章',
          kind: ProofreadingRuleKind.chapter,
          target: ProofreadingRuleTarget.headingLine,
          action: ProofreadingRuleAction.chapterCandidate,
        ),
        rule(
          'other-heading',
          '第一章 广告',
          kind: ProofreadingRuleKind.chapter,
          target: ProofreadingRuleTarget.headingLine,
          action: ProofreadingRuleAction.chapterCandidate,
        ),
        rule('deletion', '第一章'),
      ], limits: const RuleScanLimits(maxConflicts: 1)),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('detects a deletion spanning into a later candidate line', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '第1章\n广告')]),
    ]);
    final result = scan(source, [
      rule(
        'heading',
        '广告',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
      ),
      rule(
        'spanning-deletion',
        r'章\s+广',
        target: ProofreadingRuleTarget.paragraph,
        mode: ProofreadingMatchMode.safeRegex,
        positive: '章 广',
      ),
      rule('same-line-deletion', '广告'),
    ]);
    expect(result.totalConflicts, 3);
    expect(
      result.conflictSamples
          .where(
            (conflict) =>
                conflict.kind == RuleScanConflictKind.deletionAndChapter,
          )
          .length,
      2,
    );
  });

  test('counts 19000 disjoint deletions in one line without conflicts', () {
    final source = book([
      chapter('one', [TextBlock(id: 'body', text: 'a' * 19000)]),
    ]);
    final result = scan(source, [
      rule('single-character', 'a'),
    ], limits: const RuleScanLimits(maxSamples: 2));
    expect(result.matchesByRuleId, {'single-character': 19000});
    expect(result.totalMatches, 19000);
    expect(result.distinctMatches, 19000);
    expect(result.samples, hasLength(2));
    expect(result.hiddenMatches, 18998);
    expect(result.totalConflicts, 0);
    expect(result.coverage.scanUtf16, 19000);
  });

  test('cancels during dense single-line conflict processing', () {
    final source = book([
      chapter('one', [TextBlock(id: 'body', text: 'a' * 2000)]),
    ]);
    var checks = 0;
    expect(
      () => scan(source, [
        rule('single-character', 'a'),
      ], isCancelled: () => ++checks > 5000),
      throwsA(isA<TaskCancelled>()),
    );
    expect(checks, 5001);
  });

  test('cancels while pairing chapter candidates on one line', () {
    final source = book([
      chapter('one', [TextBlock(id: 'body', text: 'a' * 180)]),
    ]);
    var checks = 0;
    expect(
      () => scan(
        source,
        [
          rule(
            'heading',
            'a',
            kind: ProofreadingRuleKind.chapter,
            target: ProofreadingRuleTarget.headingLine,
            action: ProofreadingRuleAction.chapterCandidate,
          ),
        ],
        limits: const RuleScanLimits(maxConflicts: 20000, maxSamples: 0),
        isCancelled: () => ++checks > 5000,
      ),
      throwsA(isA<TaskCancelled>()),
    );
    expect(checks, 5001);
  });

  test('uses UTF-16 offsets across emoji and CRLF without splitting pairs', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '😀\r\n广告😀尾')]),
    ]);
    final result = scan(source, [rule('emoji', '😀'), rule('ad', '广告')]);
    expect(result.samples.map((match) => (match.startUtf16, match.endUtf16)), [
      (4, 6),
      (0, 2),
      (6, 8),
    ]);
    expect(result.samples.map((match) => match.lineNumber), [2, 1, 2]);
    expect(result.samples.map((match) => match.excerpt), ['广告', '😀', '😀']);
    expect(result.samples.first.before, '😀\r\n');
    expect(result.samples.first.after, '😀尾');
  });

  test('fails explicitly on input, work, hit, and line budgets', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '广告 广告')]),
    ]);
    final ad = rule('ad', '广告');
    for (final limits in [
      const RuleScanLimits(maxInputUtf16: 2),
      const RuleScanLimits(maxScanUtf16: 2),
      const RuleScanLimits(maxMatches: 1),
      const RuleScanLimits(maxLines: 0),
    ]) {
      expect(
        () => scan(source, [ad], limits: limits),
        throwsA(isA<ValidationFailure>()),
      );
    }
    final long = book([
      chapter('one', [TextBlock(id: 'body', text: '字' * 32769)]),
    ]);
    expect(() => scan(long, [ad]), throwsA(isA<ValidationFailure>()));
  });

  test('snapshots mutable lists before cancellation callbacks', () {
    final blocks = <Block>[const TextBlock(id: 'body', text: '广告')];
    final chapters = <Chapter>[chapter('one', blocks)];
    final source = book(chapters);
    var called = false;
    final result = scan(
      source,
      [rule('ad', '广告')],
      isCancelled: () {
        if (!called) {
          called = true;
          blocks.clear();
          chapters.clear();
        }
        return false;
      },
    );
    expect(result.totalMatches, 1);
    expect(result.coverage.chapters, 1);
    expect(chapters, isEmpty);
  });

  test('cancellation returns no partial result', () {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '广告 广告')]),
    ]);
    var calls = 0;
    expect(
      () => scan(source, [rule('ad', '广告')], isCancelled: () => ++calls > 5),
      throwsA(isA<TaskCancelled>()),
    );
  });

  test('background scan transfers the snapshot through an isolate', () async {
    final source = book([
      chapter('one', [const TextBlock(id: 'body', text: '广告')]),
    ]);
    final jobs = BackgroundJobs();
    try {
      final result = await ProofreadingRuleScan.scanInBackground(
        source,
        selectedRules: [rule('ad', '广告')],
        loadedChapterIds: {'one'},
        jobs: jobs,
        revision: 7,
      );
      expect(result.totalMatches, 1);
    } finally {
      jobs.dispose();
    }
  });

  test('excluded lines drop matches before counts and conflicts', () {
    final excluded = rule('excluded', '广告', exclude: '引用');
    final kept = rule('kept', '广告');
    final source = book([
      chapter('a', [const TextBlock(id: 'p1', text: '广告正文\n他念道“广告”引用\n广告结尾')]),
    ]);

    final without = ProofreadingRuleScan.scan(
      source,
      selectedRules: [kept],
      loadedChapterIds: {'a'},
    );
    final withExclude = ProofreadingRuleScan.scan(
      source,
      selectedRules: [excluded],
      loadedChapterIds: {'a'},
    );

    expect(without.totalMatches, 3);
    expect(withExclude.totalMatches, 2);
    expect(withExclude.samples.map((sample) => sample.lineNumber), [1, 3]);
    expect(withExclude.totalConflicts, 0);
    expect(withExclude.hiddenMatches, 0);
  });

  test('whole-line rules skip prose lines that merely contain the text', () {
    final exact = rule('exact', '广告', wholeLine: true);
    final source = book([
      chapter('a', [const TextBlock(id: 'p1', text: '广告\n广告正文\n正文广告')]),
    ]);

    final whole = ProofreadingRuleScan.scan(
      source,
      selectedRules: [exact],
      loadedChapterIds: {'a'},
    );
    final loose = ProofreadingRuleScan.scan(
      source,
      selectedRules: [rule('loose', '广告')],
      loadedChapterIds: {'a'},
    );

    expect(loose.totalMatches, 3);
    expect(whole.totalMatches, 1);
    expect(whole.samples.single.lineNumber, 1);
    expect(whole.totalConflicts, 0);
  });
}
