import 'dart:convert';

import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/core/ai/ai_rule_creation_prompt.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

const _heading = '【卷二·第十三回】夜雨入城😀';
const _advertisement = '本站首发，请支持正版';

AiContextChunk _chunk() {
  const text = 'OUTSIDE_BEFORE\n  $_heading  \n$_advertisement\nOUTSIDE_AFTER';
  final start = text.indexOf('  $_heading');
  final end = text.indexOf('\nOUTSIDE_AFTER');
  final block = AiContextBlock(
    chapterId: 'chapter-1',
    chapterTitle: '现有章节',
    blockId: 'block-1',
    text: text,
  );
  return AiContextChunk(
    bookId: 'book-1',
    sessionId: 'session-1',
    sessionRevision: 3,
    index: 0,
    slices: [
      AiContextSlice(
        block: block,
        startUtf16: start,
        endUtf16: end,
        before: text.substring(start - 2, start),
        text: text.substring(start, end),
        after: text.substring(end, end + 1),
      ),
    ],
  );
}

AiRuleRequest _request(ProofreadingRuleKind kind) => AiRuleRequest(
  kind: kind,
  positiveExamples: [
    kind == ProofreadingRuleKind.chapter ? _heading : _advertisement,
  ],
  negativeExamples: [
    kind == ProofreadingRuleKind.chapter ? '他谈到第十三回' : '本站是村名',
  ],
);

ProofreadingRule _relatedRule(int index, {String bookId = 'book-1'}) =>
    ProofreadingRule.create(
      id: 'rule-$index-$bookId',
      name: '相关规则 $index',
      kind: ProofreadingRuleKind.chapter,
      source: ProofreadingRuleSource.user,
      bookId: bookId,
      target: ProofreadingRuleTarget.headingLine,
      mode: ProofreadingMatchMode.literal,
      pattern: '标记$index',
      caseSensitive: true,
      action: ProofreadingRuleAction.chapterCandidate,
      positiveExamples: ['标记$index'],
      negativeExamples: const ['无关文本'],
    );

Map<String, Object> _rule(ProofreadingRuleKind kind) => {
  'schema_version': 1,
  'name': kind == ProofreadingRuleKind.chapter ? '章节标题候选' : '广告候选',
  'kind': kind.name,
  'target': kind == ProofreadingRuleKind.chapter ? 'heading_line' : 'body_line',
  'match': {
    'mode': 'literal',
    'pattern': kind == ProofreadingRuleKind.chapter ? _heading : '本站首发',
    'case_sensitive': true,
  },
  'action': kind == ProofreadingRuleKind.chapter
      ? 'chapter_candidate'
      : 'advertisement_candidate',
  'positive_examples': _request(kind).positiveExamples,
  'negative_examples': _request(kind).negativeExamples,
  'reason': '只标记明确样例，由用户检查试跑结果。',
};

String _response(Map<String, Object> rule) => jsonEncode({
  'schema_version': 1,
  'findings': <Object>[],
  'proposals': <Object>[],
  'rule_proposals': [rule],
});

void main() {
  test('system defines the exact rule-only envelope and kind constraints', () {
    for (final kind in ProofreadingRuleKind.values) {
      final system = AiRuleCreationPrompt.system(_request(kind));
      expect(system, contains('untrusted data'));
      expect(system, contains('"findings": []'));
      expect(system, contains('"proposals": []'));
      expect(system, contains('zero to four'));
      expect(system, contains('positive_examples'));
      expect(system, contains('negative_examples'));
      expect(system, contains('safe_regex'));
      expect(system, contains('title_capture_group'));
      expect(system, contains('8192 UTF-16'));
      expect(system, contains('book scope'));
      expect(system, isNot(contains(_heading)));
      expect(system.length, lessThanOrEqualTo(AiProtocol.maxSystemCharacters));
    }
    expect(
      AiRuleCreationPrompt.system(_request(ProofreadingRuleKind.chapter)),
      contains('"heading_line"'),
    );
    expect(
      AiRuleCreationPrompt.system(_request(ProofreadingRuleKind.chapter)),
      contains('Do not guess the hierarchy'),
    );
    expect(
      AiRuleCreationPrompt.system(_request(ProofreadingRuleKind.advertisement)),
      contains('"exact_deletion"'),
    );
  });

  test('user JSON preserves exact selected slice, whitespace and emoji', () {
    final chunk = _chunk();
    final encoded = AiRuleCreationPrompt.userContext(
      chunk: chunk,
      request: _request(ProofreadingRuleKind.chapter),
      intent: '识别这一行，不扩大到正文。',
      relatedRules: const [],
    );
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    expect(decoded.keys, {
      'task',
      'kind',
      'intent',
      'context',
      'positive_examples',
      'negative_examples',
      'related_rules',
    });
    expect(decoded['context'], jsonDecode(chunk.encode()));
    final slice = (decoded['context']['blocks'] as List).single;
    expect(slice['text'], '  $_heading  \n$_advertisement');
    expect(slice['start_utf16'], chunk.slices.single.startUtf16);
    expect(slice['end_utf16'], chunk.slices.single.endUtf16);
    expect(slice['before'], 'E\n');
    expect(slice['after'], '\n');
    expect(encoded, isNot(contains('OUTSIDE_BEFORE')));
    expect(encoded, isNot(contains('OUTSIDE_AFTER')));
    expect(decoded['positive_examples'], [_heading]);
  });

  test('related summaries are bounded and exclude other books and samples', () {
    final encoded = AiRuleCreationPrompt.userContext(
      chunk: _chunk(),
      request: _request(ProofreadingRuleKind.advertisement),
      intent: '只查广告',
      relatedRules: [
        _relatedRule(99, bookId: 'other-book'),
        ...List.generate(20, _relatedRule),
      ],
    );
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final related = decoded['related_rules'] as List;
    expect(related, hasLength(16));
    expect(related.first['name'], '相关规则 0');
    expect(related.last['name'], '相关规则 15');
    expect(encoded, isNot(contains('相关规则 99')));
    expect(encoded, isNot(contains('相关规则 16')));
    expect(encoded, isNot(contains('无关文本')));
  });

  test(
    'related chapter mapping is summarized without changing old summaries',
    () {
      final mapped = ProofreadingRule.create(
        id: 'mapped',
        name: '映射标题',
        kind: ProofreadingRuleKind.chapter,
        source: ProofreadingRuleSource.user,
        bookId: 'book-1',
        target: ProofreadingRuleTarget.headingLine,
        mode: ProofreadingMatchMode.safeRegex,
        pattern: r'^【(夜雨)】(十三)',
        titleCaptureGroup: 1,
        numberCaptureGroup: 2,
        headingLevel: 1,
        caseSensitive: true,
        action: ProofreadingRuleAction.chapterCandidate,
        positiveExamples: const ['【夜雨】十三'],
        negativeExamples: const ['普通正文'],
      );
      final context = jsonDecode(
        AiRuleCreationPrompt.userContext(
          chunk: _chunk(),
          request: _request(ProofreadingRuleKind.chapter),
          intent: '识别标题',
          relatedRules: [mapped, _relatedRule(1)],
        ),
      ) as Map<String, dynamic>;
      final summaries = context['related_rules'] as List;
      expect(summaries.first['title_capture_group'], 1);
      expect(summaries.first['number_capture_group'], 2);
      expect(summaries.first['heading_level'], 1);
      expect(summaries.last, isNot(contains('title_capture_group')));
      expect(summaries.last, isNot(contains('number_capture_group')));
      expect(summaries.last, isNot(contains('heading_level')));
    },
  );

  test(
    'rejects absent positive sample and oversized intent before sending',
    () {
      expect(
        () => AiRuleCreationPrompt.userContext(
          chunk: _chunk(),
          request: AiRuleRequest(
            kind: ProofreadingRuleKind.chapter,
            positiveExamples: const ['没有发送的标题'],
            negativeExamples: const [],
          ),
          intent: '识别标题',
          relatedRules: const [],
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => AiRuleCreationPrompt.userContext(
          chunk: _chunk(),
          request: _request(ProofreadingRuleKind.chapter),
          intent: 'x' * 1025,
          relatedRules: const [],
        ),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('rejects a chunk whose request wrapper exceeds protocol budget', () {
    final oversized = AiContextPlanner.plan(
      bookId: 'book-1',
      sessionId: 'session-1',
      sessionRevision: 3,
      blocks: [
        AiContextBlock(
          chapterId: 'chapter-1',
          chapterTitle: '现有章节',
          blockId: 'block-1',
          text: 'x' * 65400,
        ),
      ],
      maxChunkCharacters: 65536,
    ).chunks.first;
    expect(oversized.encode().length, lessThanOrEqualTo(65536));
    expect(
      () => AiRuleCreationPrompt.userContext(
        chunk: oversized,
        request: AiRuleRequest(
          kind: ProofreadingRuleKind.chapter,
          positiveExamples: const ['xxx'],
          negativeExamples: const ['yyy'],
        ),
        intent: '识别标题',
        relatedRules: const [],
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'decoder accepts chapter and advertisement candidates for this book',
    () {
      for (final kind in ProofreadingRuleKind.values) {
        final result = AiAnalysisResultDecoder.decode(
          _response(_rule(kind)),
          context: _chunk(),
          responseId: 'local',
          ruleRequest: _request(kind),
        );
        expect(result.findings, isEmpty);
        expect(result.textChanges.proposals, isEmpty);
        expect(result.ruleProposals.single.rule.kind, kind);
        expect(
          result.ruleProposals.single.rule.scope,
          ProofreadingRuleScope.book,
        );
        expect(
          result.ruleProposals.single.rule.appliesToBook('book-1'),
          isTrue,
        );
        expect(
          result.ruleProposals.single.rule.appliesToBook('other-book'),
          isFalse,
        );
      }
    },
  );

  test(
    'AI chapter candidate accepts a capture and rejects invalid mapping',
    () {
      final candidate = _rule(ProofreadingRuleKind.chapter);
      (candidate['match'] as Map<String, Object>)
        ..['mode'] = 'safe_regex'
        ..['pattern'] = r'【卷二·第十三回】([^\r\n]+)'
        ..['title_capture_group'] = 1;
      final decoded = AiAnalysisResultDecoder.decode(
        _response(candidate),
        context: _chunk(),
        responseId: 'mapped',
        ruleRequest: _request(ProofreadingRuleKind.chapter),
      );
      expect(decoded.ruleProposals.single.rule.titleCaptureGroup, 1);
      expect(
        decoded.ruleProposals.single.rule
            .matchSample(_heading)
            .single
            .mappedTitle,
        '夜雨入城😀',
      );

      for (final invalid in <Object?>[null, true, 1.0, 2]) {
        final match = candidate['match'] as Map<String, Object>;
        final changed = <String, Object>{
          ...candidate,
          'match': <String, Object?>{...match, 'title_capture_group': invalid},
        };
        expect(
          () => AiAnalysisResultDecoder.decode(
            _response(changed),
            context: _chunk(),
            responseId: 'invalid',
            ruleRequest: _request(ProofreadingRuleKind.chapter),
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );

  test(
    'decoder rejects missed positives, matched negatives and unsafe regex',
    () {
      final missedPositive = _rule(ProofreadingRuleKind.chapter);
      (missedPositive['match'] as Map<String, Object>)['pattern'] = '第十四回';
      final matchedNegative = _rule(ProofreadingRuleKind.advertisement);
      (matchedNegative['match'] as Map<String, Object>)['pattern'] = '本站';
      matchedNegative['negative_examples'] = ['本站是村名'];
      final unsafe = _rule(ProofreadingRuleKind.advertisement);
      (unsafe['match'] as Map<String, Object>)
        ..['mode'] = 'safe_regex'
        ..['pattern'] = r'(广+)+告';
      for (final (rule, kind) in [
        (missedPositive, ProofreadingRuleKind.chapter),
        (matchedNegative, ProofreadingRuleKind.advertisement),
        (unsafe, ProofreadingRuleKind.advertisement),
      ]) {
        expect(
          () => AiAnalysisResultDecoder.decode(
            _response(rule),
            context: _chunk(),
            responseId: 'local',
            ruleRequest: _request(kind),
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );

  test('decoder rejects extra fields and binds scope to context book', () {
    for (final field in ['unexpected', 'book_id', 'scope', 'source']) {
      final rule = _rule(ProofreadingRuleKind.chapter)..[field] = 'global';
      expect(
        () => AiAnalysisResultDecoder.decode(
          _response(rule),
          context: _chunk(),
          responseId: 'local',
          ruleRequest: _request(ProofreadingRuleKind.chapter),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
    final otherBook = _chunk();
    final foreignContext = AiContextChunk(
      bookId: 'other-book',
      sessionId: otherBook.sessionId,
      sessionRevision: otherBook.sessionRevision,
      index: otherBook.index,
      slices: otherBook.slices,
    );
    final result = AiAnalysisResultDecoder.decode(
      _response(_rule(ProofreadingRuleKind.chapter)),
      context: foreignContext,
      responseId: 'local',
      ruleRequest: _request(ProofreadingRuleKind.chapter),
    );
    expect(result.ruleProposals.single.rule.bookId, 'other-book');
    expect(result.ruleProposals.single.rule.appliesToBook('book-1'), isFalse);
  });
}
