import 'package:bookloom/core/editing/ai_change_application.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_scan.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/editing/rule_scan_changes.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deletes only the UTF-16 match, preserving the rest of the block', () {
    const source = '😀开头\r\n广告正文';
    final book = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: source)]),
    ]);
    final match = _scan(book, [_rule('ad', '广告')]).single;
    final changes = _build(book, [match]);
    final proposal = changes.textProposals.single;

    expect(changes.splitProposals, isEmpty);
    expect(changes.selectedIds, {'rule-change-0'});
    expect(proposal.action, AiTextProposalAction.deleteText);
    expect(proposal.range.start, 6);
    expect(proposal.target.originalText, '广告');
    expect(proposal.replacement, '');
    expect(RuleScanChanges.describe(book, match).sourceTextAfter, '😀开头\r\n正文');
    expect(changes.textProposals.clear, throwsUnsupportedError);
    expect(changes.splitProposals.clear, throwsUnsupportedError);
    expect(() => changes.selectedIds.add('extra'), throwsUnsupportedError);

    final result = _compile(book, changes);
    expect((result.single.blocks.single as TextBlock).text, '😀开头\r\n正文');
    expect((book.chapters.single.blocks.single as TextBlock).text, source);
  });

  test('uses up to 1024 UTF-16 context units to distinguish repeated text', () {
    final source = '广告${'x' * 100}甲广告${'x' * 100}乙';
    final book = _book([
      _chapter('chapter', [TextBlock(id: 'body', text: source)]),
    ]);
    final matches = _scan(book, [_rule('ad', '广告')]);
    final changes = _build(book, matches);

    expect(changes.textProposals, hasLength(2));
    expect(changes.textProposals.first.target.after.length, greaterThan(80));
    expect(changes.textProposals[1].range.start, source.lastIndexOf('广告'));
    expect(
      ((_compile(book, changes).single.blocks.single) as TextBlock).text,
      '${'x' * 100}甲${'x' * 100}乙',
    );
  });

  test('context windows never split an emoji surrogate pair', () {
    final source = '😀${'x' * 1023}广告${'x' * 1023}😀';
    final book = _book([
      _chapter('chapter', [TextBlock(id: 'body', text: source)]),
    ]);
    final match = _scan(book, [_rule('ad', '广告')]).single;
    final target = _build(book, [match]).textProposals.single.target;

    expect(target.before, 'x' * 1023);
    expect(target.after, 'x' * 1023);
    expect(target.before.length, lessThanOrEqualTo(1024));
    expect(target.after.length, lessThanOrEqualTo(1024));
  });

  test('rejects a repeated occurrence with identical bounded context', () {
    final source = '${'x' * 1200}广告${'x' * 2400}广告${'x' * 1200}';
    final book = _book([
      _chapter('chapter', [TextBlock(id: 'body', text: source)]),
    ]);
    final matches = _scan(book, [_rule('ad', '广告')]);
    expect(
      () => _build(book, [matches.first]),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('promotes the full trimmed heading line, not the matched substring', () {
    const source = '😀序言\r\n  第二章 新篇  \r\n正文';
    final book = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: source)]),
    ]);
    final match = _scan(book, [
      _rule('heading', '第二章', action: ProofreadingRuleAction.chapterCandidate),
    ]).single;
    final changes = _build(book, [match]);
    final split = changes.splitProposals.single;
    final description = RuleScanChanges.describe(book, match);

    expect(split.title, '第二章 新篇');
    expect(split.target.originalText, '第二章 新篇');
    expect(split.removeTitleLine, isTrue);
    expect(split.range.start, source.indexOf('第二章'));
    expect(description.headingTitle, '第二章 新篇');
    expect(description.titleLine, '  第二章 新篇  ');
    expect(description.sourceTextBefore, source);
    expect(description.sourceTextAfter, '😀序言\r\n正文');
    expect(
      split.titleLineIn(source, split.range).start,
      source.indexOf('  第二章'),
    );
  });

  test('isolated CR is rejected consistently before preview and writes', () {
    for (final source in ['第二章\r正文', '第二章\r']) {
      final book = _book([
        _chapter('chapter', [TextBlock(id: 'body', text: source)]),
      ]);
      final match = _scan(book, [
        _rule(
          'heading',
          '第二章',
          action: ProofreadingRuleAction.chapterCandidate,
        ),
      ]).single;

      expect(
        () => RuleScanChanges.describe(book, match),
        throwsA(isA<ValidationFailure>()),
      );
      expect(RuleScanChanges.supportsHeadingLineEnding(source, 3), isFalse);
      expect(() => _build(book, [match]), throwsA(isA<ValidationFailure>()));
      expect((book.chapters.single.blocks.single as TextBlock).text, source);
    }
  });

  test(
    'mapped title changes the catalog but removes the complete source line',
    () {
      const heading = '【第二章 😀新篇】';
      const source = '😀序言\r\n  $heading  \r\n正文';
      final book = _book([
        _chapter('chapter', [const TextBlock(id: 'body', text: source)]),
      ]);
      final match = _scan(book, [
        _rule(
          'mapped',
          r'【(第二章 😀新篇)】',
          action: ProofreadingRuleAction.chapterCandidate,
          mode: ProofreadingMatchMode.safeRegex,
          titleCaptureGroup: 1,
          positiveExamples: const [heading],
        ),
      ]).single;
      final changes = _build(book, [match]);
      final split = changes.splitProposals.single;
      final description = RuleScanChanges.describe(book, match);

      expect(match.mappedTitle, '第二章 😀新篇');
      expect(split.title, match.mappedTitle);
      expect(split.target.originalText, heading);
      expect(split.titleEvidenceRange!.start, 1);
      expect(description.headingTitle, split.title);
      expect(description.titleLine, '  $heading  ');
      expect(description.sourceTextAfter, '😀序言\r\n正文');
      final result = _compile(
        book,
        changes,
        identities: {
          split.id: const AiChapterSplitIdentity(
            chapterId: 'mapped-chapter',
            blockId: 'mapped-body',
          ),
        },
      );
      expect(result[1].title, '第二章 😀新篇');
      expect((result[1].blocks.single as TextBlock).text, '正文');
      expect((result.first.blocks.single as TextBlock).text, '😀序言\r\n');

      for (final evidence in <ProposalTextRange?>[
        null,
        const ProposalTextRange(-1, 4),
        const ProposalTextRange(0, 500),
        const ProposalTextRange(0, 1),
      ]) {
        final forged = AiChapterSplitProposal(
          id: split.id,
          target: split.target,
          range: split.range,
          title: split.title,
          removeTitleLine: true,
          reason: split.reason,
          titleEvidenceRange: evidence,
        );
        expect(
          () => forged.titleLineIn(source, forged.range),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );

  test('mapping cannot take title text outside the matched span', () {
    const source = '第二章 新篇\n正文';
    final book = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: source)]),
    ]);
    final match = _scan(book, [
      _rule('heading', '第二章', action: ProofreadingRuleAction.chapterCandidate),
    ]).single;
    final forged = _withMappedTitle(match, '新篇');
    expect(() => _build(book, [forged]), throwsA(isA<ValidationFailure>()));
    expect(
      () => RuleScanChanges.describe(book, forged),
      throwsA(isA<ValidationFailure>()),
    );
    final deletion = _scan(book, [_rule('ad', '第二章')]).single;
    expect(
      () => _build(book, [_withMappedTitle(deletion, '第二章')]),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('mapped title limit does not truncate its longer source heading', () {
    final heading = '${'x' * 300}第二章';
    final source = '$heading\n正文';
    final book = _book([
      _chapter('chapter', [TextBlock(id: 'body', text: source)]),
    ]);
    final match = _scan(book, [
      _rule(
        'mapped',
        r'^x{300}(第二章)$',
        action: ProofreadingRuleAction.chapterCandidate,
        mode: ProofreadingMatchMode.safeRegex,
        titleCaptureGroup: 1,
        positiveExamples: [heading],
      ),
    ]).single;
    final changes = _build(book, [match]);
    final proposal = changes.splitProposals.single;
    expect(proposal.title, '第二章');
    expect(proposal.target.originalText, heading);
    expect(
      proposal.titleLineIn(source, proposal.range).end,
      heading.length + 1,
    );
    expect(RuleScanChanges.describe(book, match).sourceTextAfter, '正文');
    final result = _compile(
      book,
      changes,
      identities: {
        proposal.id: const AiChapterSplitIdentity(
          chapterId: 'mapped-chapter',
          blockId: 'mapped-body',
        ),
      },
    );
    expect(result[1].title, '第二章');
    expect((result[1].blocks.single as TextBlock).text, '正文');
  });

  test(
    'repeated capture text supplies evidence without inventing group offsets',
    () {
      const heading = '第二章【第二章】';
      final book = _book([
        _chapter('chapter', [
          const TextBlock(id: 'body', text: '$heading\n正文'),
        ]),
      ]);
      final match = _scan(book, [
        _rule(
          'mapped',
          r'^(第二章)【(第二章)】$',
          action: ProofreadingRuleAction.chapterCandidate,
          mode: ProofreadingMatchMode.safeRegex,
          titleCaptureGroup: 2,
          positiveExamples: const [heading],
        ),
      ]).single;
      final changes = _build(book, [match]);
      final proposal = changes.splitProposals.single;
      final evidence = proposal.titleEvidenceRange!;
      expect(proposal.title, '第二章');
      expect(
        proposal.target.originalText.substring(evidence.start, evidence.end),
        proposal.title,
      );
      expect(RuleScanChanges.describe(book, match).sourceTextAfter, '正文');
      final result = _compile(
        book,
        changes,
        identities: {
          proposal.id: const AiChapterSplitIdentity(
            chapterId: 'repeated-chapter',
            blockId: 'repeated-body',
          ),
        },
      );
      expect(result[1].title, '第二章');
      expect((result[1].blocks.single as TextBlock).text, '正文');
    },
  );

  test('rejects two candidates on one complete heading line', () {
    const source = '第二章 新篇\r\n正文';
    final book = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: source)]),
    ]);
    final matches = _scan(book, [
      _rule('first', '第二章', action: ProofreadingRuleAction.chapterCandidate),
      _rule('second', '新篇', action: ProofreadingRuleAction.chapterCandidate),
    ]);
    expect(matches, hasLength(2));
    expect(() => _build(book, matches), throwsA(isA<ValidationFailure>()));
  });

  test('rejects deletion on the heading line and overlapping deletions', () {
    const source = '第二章 广告\r\n正文';
    final book = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: source)]),
    ]);
    final matches = _scan(book, [
      _rule('heading', '第二章', action: ProofreadingRuleAction.chapterCandidate),
      _rule('ad', '广告'),
      _rule('overlap', '章 广告'),
    ]);
    expect(
      () => _build(book, matches.take(2).toList()),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => _build(book, [matches.first, matches.last]),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('rejects stale, foreign and forged match source or range', () {
    const source = '广告正文';
    final book = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: source)]),
    ]);
    final match = _scan(book, [_rule('ad', '广告')]).single;
    RuleScanMatch changed({
      String? chapterId,
      String? blockId,
      String? excerpt,
      int? start,
      int? end,
      int? lineNumber,
    }) => RuleScanMatch(
      chapterId: chapterId ?? match.chapterId,
      chapterTitle: match.chapterTitle,
      blockId: blockId ?? match.blockId,
      lineNumber: lineNumber ?? match.lineNumber,
      startUtf16: start ?? match.startUtf16,
      endUtf16: end ?? match.endUtf16,
      action: match.action,
      ruleIds: match.ruleIds,
      excerpt: excerpt ?? match.excerpt,
      before: match.before,
      after: match.after,
    );

    for (final forged in [
      changed(chapterId: 'foreign'),
      changed(blockId: 'foreign'),
      changed(excerpt: '正文'),
      changed(start: 1),
      changed(end: source.length + 1),
      changed(lineNumber: 2),
    ]) {
      expect(() => _build(book, [forged]), throwsA(isA<ValidationFailure>()));
    }
    final otherBook = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: '另一书稿')]),
    ]);
    expect(() => _build(otherBook, [match]), throwsA(isA<ValidationFailure>()));
  });

  test('does not turn advertisement candidates into deletions', () {
    final book = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: '作者广告')]),
    ]);
    final match = _scan(book, [
      _rule(
        'candidate',
        '作者广告',
        action: ProofreadingRuleAction.advertisementCandidate,
      ),
    ]).single;
    expect(RuleScanChanges.describe(book, match).sourceTextAfter, '作者广告');
    expect(() => _build(book, [match]), throwsA(isA<ValidationFailure>()));
  });

  test('mixed compile preserves resources and other chapters', () {
    const source = '😀序广告\r\n  第二章 新篇  \r\n正文';
    final book = _book([
      const Chapter(id: 'volume', bookId: 'book', title: '卷', level: 1),
      _chapter('chapter', [
        const TextBlock(id: 'body', text: source),
        const ImageBlock(id: 'image', assetId: 'asset'),
        const FootnoteBlock(id: 'note', text: '注释'),
        const DividerBlock(id: 'divider'),
      ], parentId: 'volume'),
      _chapter('untouched', [
        const TextBlock(id: 'other', text: '保留'),
      ], parentId: 'volume'),
    ]);
    final matches = _scan(book, [
      _rule('ad', '广告'),
      _rule('heading', '第二章', action: ProofreadingRuleAction.chapterCandidate),
    ]);
    final changes = _build(book, matches);
    final splitId = changes.splitProposals.single.id;
    final result = _compile(
      book,
      changes,
      identities: {
        splitId: const AiChapterSplitIdentity(
          chapterId: 'new-chapter',
          blockId: 'new-body',
        ),
      },
    );

    expect(result.map((chapter) => chapter.id), [
      'volume',
      'chapter',
      'new-chapter',
      'untouched',
    ]);
    expect((result[1].blocks.single as TextBlock).text, '😀序\r\n');
    expect(result[2].title, '第二章 新篇');
    expect(result[2].parentId, 'volume');
    expect(result[2].blocks, const <Block>[
      TextBlock(id: 'new-body', text: '正文'),
      ImageBlock(id: 'image', assetId: 'asset'),
      FootnoteBlock(id: 'note', text: '注释'),
      DividerBlock(id: 'divider'),
    ]);
    expect(result.last.blocks.single.plainText, '保留');
    expect((book.chapters[1].blocks.first as TextBlock).text, source);
  });

  test('rejects empty or over-budget selection', () {
    final book = _book([
      _chapter('chapter', [const TextBlock(id: 'body', text: '广告')]),
    ]);
    final match = _scan(book, [_rule('ad', '广告')]).single;
    expect(() => _build(book, []), throwsA(isA<ValidationFailure>()));
    expect(
      () => _build(book, List.filled(101, match)),
      throwsA(isA<ValidationFailure>()),
    );
  });
}

Book _book(List<Chapter> chapters) => Book(
  id: 'book',
  meta: BookMeta(title: '测试书稿'),
  chapters: chapters,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Chapter _chapter(String id, List<Block> blocks, {String? parentId}) => Chapter(
  id: id,
  bookId: 'book',
  title: '原章节$id',
  parentId: parentId,
  blocks: blocks,
);

ProofreadingRule _rule(
  String id,
  String pattern, {
  ProofreadingRuleAction action = ProofreadingRuleAction.exactDeletion,
  ProofreadingRuleTarget target = ProofreadingRuleTarget.bodyLine,
  ProofreadingMatchMode mode = ProofreadingMatchMode.literal,
  int? titleCaptureGroup,
  List<String>? positiveExamples,
}) => ProofreadingRule.create(
  id: id,
  name: id,
  kind: action == ProofreadingRuleAction.chapterCandidate
      ? ProofreadingRuleKind.chapter
      : ProofreadingRuleKind.advertisement,
  source: ProofreadingRuleSource.user,
  bookId: 'book',
  target: action == ProofreadingRuleAction.chapterCandidate
      ? ProofreadingRuleTarget.headingLine
      : target,
  mode: mode,
  titleCaptureGroup: titleCaptureGroup,
  pattern: pattern,
  caseSensitive: true,
  action: action,
  positiveExamples: positiveExamples ?? [pattern],
  negativeExamples: const ['无关正文'],
);

RuleScanMatch _withMappedTitle(RuleScanMatch match, String title) =>
    RuleScanMatch(
      chapterId: match.chapterId,
      chapterTitle: match.chapterTitle,
      blockId: match.blockId,
      lineNumber: match.lineNumber,
      startUtf16: match.startUtf16,
      endUtf16: match.endUtf16,
      action: match.action,
      ruleIds: match.ruleIds,
      excerpt: match.excerpt,
      before: match.before,
      after: match.after,
      mappedTitle: title,
    );

List<RuleScanMatch> _scan(Book book, List<ProofreadingRule> rules) =>
    ProofreadingRuleScan.scan(
      book,
      selectedRules: rules,
      loadedChapterIds: book.chapters.map((chapter) => chapter.id).toSet(),
    ).samples;

RuleScanChangeSet _build(Book book, List<RuleScanMatch> matches) =>
    RuleScanChanges.build(
      snapshot: book,
      sessionId: 'session',
      saveSeq: 7,
      selectedMatches: matches,
    );

List<Chapter> _compile(
  Book book,
  RuleScanChangeSet changes, {
  Map<String, AiChapterSplitIdentity> identities = const {},
}) => AiChangeApplication.compile(
  book: book,
  sessionId: 'session',
  saveSeq: 7,
  textProposals: changes.textProposals,
  splitProposals: changes.splitProposals,
  selectedIds: changes.selectedIds,
  splitIdentities: identities,
  byteBudget: 1024 * 1024,
);
