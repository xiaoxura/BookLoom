import 'dart:convert';

import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading_finding.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

AiContextChunk _context() => AiContextPlanner.plan(
  bookId: 'book',
  sessionId: 'session',
  sessionRevision: 9,
  blocks: [
    const AiContextBlock(
      chapterId: 'chapter',
      chapterTitle: '第一章',
      blockId: 'block',
      text: '第十三章 风雨\n正文广告正文',
    ),
  ],
).chunks.single;

Map<String, Object> _text() => {
  'id': 'text-1',
  'finding_id': 'finding-1',
  'action': 'delete_text',
  'chapter_id': 'chapter',
  'block_id': 'block',
  'original': '广告',
  'before': '',
  'after': '',
  'replacement': '',
  'reason': '精确候选删除，等待人工选择。',
};

Map<String, Object> _finding() => {
  'id': 'finding-1',
  'category': 'advertisement',
  'assessment': 'undetermined',
  'chapter_id': 'chapter',
  'block_id': 'block',
  'original': '广告',
  'before': '',
  'after': '',
  'reason': '可能是引文，暂无法确定。',
};

const _advertisementBlock = '整块推广😀广告';

AiContextChunk _advertisementContext() => AiContextPlanner.plan(
  bookId: 'book',
  sessionId: 'session',
  sessionRevision: 9,
  blocks: [
    const AiContextBlock(
      chapterId: 'chapter',
      chapterTitle: '第一章',
      blockId: 'block',
      text: _advertisementBlock,
    ),
  ],
).chunks.single;

Map<String, Object> _blockFinding() => _finding()
  ..['original'] = _advertisementBlock
  ..['assessment'] = 'advertisement';

Map<String, Object> _blockRemoval() => _text()
  ..['action'] = 'remove_block'
  ..['original'] = _advertisementBlock;

Map<String, Object> _headingFinding() => _finding()
  ..['category'] = 'missing_chapter'
  ..['assessment'] = 'missed_heading'
  ..['original'] = '第十三章 风雨';

Map<String, Object> _rename() => _text()
  ..['action'] = 'rename_chapter'
  ..['original'] = '第十三章 风雨'
  ..['replacement'] = '第十三章 风雨'
  ..['original_title'] = '第一章';

Map<String, Object> _rule() => {
  'schema_version': 1,
  'name': '章节候选',
  'kind': 'chapter',
  'target': 'heading_line',
  'match': {
    'mode': 'safe_regex',
    'pattern': r'^第[一二三四五六七八九十百0-9]{1,8}章',
    'case_sensitive': true,
  },
  'action': 'chapter_candidate',
  'positive_examples': ['第十三章 风雨'],
  'negative_examples': ['他提到第十三章'],
  'reason': '保守识别标题行。',
};

AiRuleRequest _request({
  List<String> positive = const ['第十三章 风雨'],
  List<String> negative = const ['他提到第十三章'],
}) => AiRuleRequest(
  kind: ProofreadingRuleKind.chapter,
  positiveExamples: positive,
  negativeExamples: negative,
);

Map<String, Object> _envelope({
  List<Object> findings = const [],
  List<Object> proposals = const [],
  List<Object> rules = const [],
}) => {
  'schema_version': 1,
  'findings': findings,
  'proposals': proposals,
  'rule_proposals': rules,
};

void main() {
  test(
    'decodes three distinct products with local rule identity and scope',
    () {
      final result = AiAnalysisResultDecoder.decode(
        jsonEncode(
          _envelope(
            findings: [_finding()..['assessment'] = 'advertisement'],
            proposals: [_text()],
            rules: [_rule()],
          ),
        ),
        context: _context(),
        responseId: 'local-response',
        ruleRequest: _request(),
      );
      expect(result.responseId, 'local-response');
      expect(
        result.findings.single.assessment,
        FindingAssessment.advertisement,
      );
      expect(result.textChanges.proposals.single.replacement, '');
      expect(result.findingIdByTextProposalId['text-1'], 'finding-1');
      expect(result.findingIdByTextProposalId.clear, throwsUnsupportedError);
      final rule = result.ruleProposals.single;
      expect(rule.proposalId, 'local-response-rule-0');
      expect(rule.rule.id, 'local-response-candidate-0');
      expect(rule.rule.scope, ProofreadingRuleScope.book);
      expect(rule.rule.source, ProofreadingRuleSource.ai);
      expect(rule.rule.appliesToBook('another-book'), isFalse);
      expect(result.findings.clear, throwsUnsupportedError);
      expect(result.ruleProposals.clear, throwsUnsupportedError);
    },
  );

  test('diagnostic-only and no-action responses remain legitimate', () {
    for (final envelope in [
      _envelope(),
      _envelope(findings: [_finding()]),
    ]) {
      final result = AiAnalysisResultDecoder.decode(
        jsonEncode(envelope),
        context: _context(),
        responseId: 'local',
      );
      expect(result.textChanges.proposals, isEmpty);
      expect(result.ruleProposals, isEmpty);
    }
  });

  test('uncertain or non-advertisement evidence cannot also be changed', () {
    for (final assessment in [
      'undetermined',
      'author_note',
      'story_quote',
      'not_advertisement',
    ]) {
      expect(
        () => AiAnalysisResultDecoder.decode(
          jsonEncode(
            _envelope(
              findings: [_finding()..['assessment'] = assessment],
              proposals: [_text()],
            ),
          ),
          context: _context(),
          responseId: 'local',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('whole-block advertisement removal retains its linked finding', () {
    final result = AiAnalysisResultDecoder.decode(
      jsonEncode(
        _envelope(findings: [_blockFinding()], proposals: [_blockRemoval()]),
      ),
      context: _advertisementContext(),
      responseId: 'local',
    );
    final removal = result.textChanges.proposals.single;
    expect(removal.action, AiTextProposalAction.removeBlock);
    expect(removal.range.start, 0);
    expect(removal.range.end, _advertisementBlock.length);
    expect(removal.replacement, '');
    expect(result.findingIdByTextProposalId[removal.id], 'finding-1');
  });

  test('reliable opening heading can rename the directory title', () {
    final result = AiAnalysisResultDecoder.decode(
      jsonEncode(
        _envelope(findings: [_headingFinding()], proposals: [_rename()]),
      ),
      context: _context(),
      responseId: 'local',
    );
    final change = result.textChanges.proposals.single;
    expect(change.action, AiTextProposalAction.renameChapter);
    expect(change.originalTitle, '第一章');
    expect(change.replacement, '第十三章 风雨');
    expect(change.range.start, 0);
    expect(result.findingIdByTextProposalId[change.id], 'finding-1');
  });

  test('rename requires exactly its original title and reliable finding', () {
    final invalid = [
      (finding: _headingFinding(), change: _rename()..remove('original_title')),
      (finding: _headingFinding(), change: _rename()..['original_title'] = 1),
      (
        finding: _headingFinding(),
        change: _rename()..['original_title'] = 'x' * 513,
      ),
      (
        finding: _headingFinding(),
        change: _rename()..['original_title'] = '第二章',
      ),
      (finding: _headingFinding(), change: _rename()..['original_title'] = ''),
      (finding: _headingFinding(), change: _rename()..['extra'] = 'unexpected'),
      (
        finding: _headingFinding()..['assessment'] = 'merged_content',
        change: _rename(),
      ),
      (
        finding: _headingFinding()..['assessment'] = 'numbering_suspect',
        change: _rename(),
      ),
      (
        finding: _headingFinding()..['assessment'] = 'undetermined',
        change: _rename(),
      ),
      (
        finding: _headingFinding()
          ..['category'] = 'other'
          ..['assessment'] = 'observed',
        change: _rename(),
      ),
      (
        finding: _headingFinding(),
        change: _rename()..['finding_id'] = 'unknown',
      ),
      (finding: _headingFinding()..['original'] = '第十三章', change: _rename()),
    ];
    for (final testCase in invalid) {
      expect(
        () => AiAnalysisResultDecoder.decode(
          jsonEncode(
            _envelope(
              findings: [testCase.finding],
              proposals: [testCase.change],
            ),
          ),
          context: _context(),
          responseId: 'local',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('rename accepts an exact empty or whitespace trusted title', () {
    for (final oldTitle in ['', '  ']) {
      final context = AiContextPlanner.plan(
        bookId: 'book',
        sessionId: 'session',
        sessionRevision: 9,
        blocks: [
          AiContextBlock(
            chapterId: 'chapter',
            chapterTitle: oldTitle,
            blockId: 'block',
            text: '第十三章 风雨\n正文',
          ),
        ],
      ).chunks.single;
      final result = AiAnalysisResultDecoder.decode(
        jsonEncode(
          _envelope(
            findings: [_headingFinding()],
            proposals: [_rename()..['original_title'] = oldTitle],
          ),
        ),
        context: context,
        responseId: 'local',
      );
      expect(result.textChanges.proposals.single.originalTitle, oldTitle);
      expect(result.textChanges.proposals.single.replacement, '第十三章 风雨');
    }
  });

  test('uncertain overlapping heading evidence rejects rename', () {
    final protected = _headingFinding()
      ..['id'] = 'uncertain'
      ..['assessment'] = 'undetermined';
    expect(
      () => AiAnalysisResultDecoder.decode(
        jsonEncode(
          _envelope(
            findings: [_headingFinding(), protected],
            proposals: [_rename()],
          ),
        ),
        context: _context(),
        responseId: 'local',
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'remove_block requires full source, core, and advertisement finding',
    () {
      final block = _advertisementContext().slices.single.block;
      final partialCore = AiContextChunk(
        bookId: 'book',
        sessionId: 'session',
        sessionRevision: 9,
        index: 0,
        slices: [
          AiContextSlice(
            block: block,
            startUtf16: 0,
            endUtf16: 2,
            before: '',
            text: block.text.substring(0, 2),
            after: block.text.substring(2),
          ),
        ],
      );
      final cases = [
        (
          context: _advertisementContext(),
          finding: _blockFinding(),
          change: _blockRemoval()..['original'] = '推广',
        ),
        (
          context: partialCore,
          finding: _blockFinding(),
          change: _blockRemoval(),
        ),
        (
          context: _advertisementContext(),
          finding: _blockFinding(),
          change: _blockRemoval()..['replacement'] = '改写',
        ),
        (
          context: _advertisementContext(),
          finding: _blockFinding()..['original'] = '推广',
          change: _blockRemoval(),
        ),
        (
          context: _advertisementContext(),
          finding: _blockFinding()
            ..['category'] = 'other'
            ..['assessment'] = 'observed',
          change: _blockRemoval(),
        ),
      ];
      for (final testCase in cases) {
        expect(
          () => AiAnalysisResultDecoder.decode(
            jsonEncode(
              _envelope(
                findings: [testCase.finding],
                proposals: [testCase.change],
              ),
            ),
            context: testCase.context,
            responseId: 'local',
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );

  test('protected evidence overlapping removal rejects the entire result', () {
    for (final assessment in [
      'undetermined',
      'author_note',
      'story_quote',
      'not_advertisement',
    ]) {
      final protected = _finding()
        ..['id'] = 'protected'
        ..['original'] = '😀'
        ..['assessment'] = assessment;
      expect(
        () => AiAnalysisResultDecoder.decode(
          jsonEncode(
            _envelope(
              findings: [_blockFinding(), protected],
              proposals: [_blockRemoval()],
            ),
          ),
          context: _advertisementContext(),
          responseId: 'local',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test(
    'text changes must link a determinate finding covering the full range',
    () {
      final knownFinding = _finding()..['assessment'] = 'advertisement';
      for (final change in [
        _text()..remove('finding_id'),
        _text()..['finding_id'] = 'unknown',
        _text()..['original'] = '正文广告正文',
      ]) {
        expect(
          () => AiAnalysisResultDecoder.decode(
            jsonEncode(
              _envelope(findings: [knownFinding], proposals: [change]),
            ),
            context: _context(),
            responseId: 'local',
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
      final header = _finding()
        ..['original'] = '第十三章 风雨'
        ..['assessment'] = 'author_note';
      expect(
        () => AiAnalysisResultDecoder.decode(
          jsonEncode(_envelope(findings: [header], proposals: [_text()])),
          context: _context(),
          responseId: 'local',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('rules require a local request and positive sample in sent content', () {
    final response = jsonEncode(_envelope(rules: [_rule()]));
    expect(
      () => AiAnalysisResultDecoder.decode(
        response,
        context: _context(),
        responseId: 'local',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => AiAnalysisResultDecoder.decode(
        response,
        context: _context(),
        responseId: 'local',
        ruleRequest: _request(positive: ['第十四章 晴天']),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => AiAnalysisResultDecoder.decode(
        response,
        context: _context(),
        responseId: 'local',
        ruleRequest: _request(negative: ['第十三章 风雨']),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('models cannot choose rule source, global scope or arbitrary ids', () {
    for (final extra in ['scope', 'id', 'source', 'script', 'priority']) {
      final rule = _rule()..[extra] = 'malicious';
      expect(
        () => AiAnalysisResultDecoder.decode(
          jsonEncode(_envelope(rules: [rule])),
          context: _context(),
          responseId: 'local',
          ruleRequest: _request(),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('rejects cross-product ids and more than the combined item budget', () {
    final duplicate = _text()..['id'] = 'finding-1';
    expect(
      () => AiAnalysisResultDecoder.decode(
        jsonEncode(_envelope(findings: [_finding()], proposals: [duplicate])),
        context: _context(),
        responseId: 'local',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => AiAnalysisResultDecoder.decode(
        jsonEncode(
          _envelope(
            findings: List.generate(
              100,
              (index) => _finding()..['id'] = 'f$index',
            ),
            proposals: [_text()],
          ),
        ),
        context: _context(),
        responseId: 'local',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => AiAnalysisResultDecoder.decode(
        jsonEncode(_envelope(rules: List.generate(5, (_) => _rule()))),
        context: _context(),
        responseId: 'local',
        ruleRequest: _request(),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('duplicate keys are rejected before nested re-encoding', () {
    final response = jsonEncode(_envelope(rules: [_rule()])).replaceFirst(
      '"kind":"chapter"',
      '"kind":"advertisement","kind":"chapter"',
    );
    expect(
      () => AiAnalysisResultDecoder.decode(
        response,
        context: _context(),
        responseId: 'local',
        ruleRequest: _request(),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'one invalid product rejects the complete result without raw errors',
    () {
      final invalid = _text()..['action'] = 'private-marker-script';
      try {
        AiAnalysisResultDecoder.decode(
          jsonEncode(_envelope(findings: [_finding()], proposals: [invalid])),
          context: _context(),
          responseId: 'local',
        );
        fail('Invalid product accepted');
      } on ValidationFailure catch (error) {
        expect(error.toString(), isNot(contains('private-marker')));
        expect(error.cause, isNull);
      }
    },
  );

  test('strict envelope, local id, version and response size are bounded', () {
    for (final response in [
      jsonEncode({'schema_version': 1, 'proposals': <Object>[]}),
      jsonEncode(_envelope()..['script'] = 'run()'),
      jsonEncode(_envelope()..['schema_version'] = true),
      jsonEncode(_envelope()..['findings'] = 'not-a-list'),
      'x' * 65537,
    ]) {
      expect(
        () => AiAnalysisResultDecoder.decode(
          response,
          context: _context(),
          responseId: 'local',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
    expect(
      () => AiAnalysisResultDecoder.decode(
        jsonEncode(_envelope()),
        context: _context(),
        responseId: 'id/with/slash',
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
