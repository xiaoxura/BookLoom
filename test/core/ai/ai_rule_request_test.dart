import 'dart:convert';

import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

AiRuleRequest _request(
  List<String> positive, [
  List<String> negative = const [],
]) => AiRuleRequest(
  kind: ProofreadingRuleKind.advertisement,
  positiveExamples: positive,
  negativeExamples: negative,
);

void main() {
  test(
    'request copies examples, preserves exact UTF-16 and serializes metadata',
    () {
      final positive = ['广告😀'];
      final request = _request(positive, ['剧情引文']);
      positive.clear();
      request.validate();
      expect(request.positiveExamples, ['广告😀']);
      expect(request.negativeExamples.clear, throwsUnsupportedError);
      expect(request.toJson(), {
        'kind': 'advertisement',
        'positive_examples': ['广告😀'],
        'negative_examples': ['剧情引文'],
      });
    },
  );

  test('twelve examples per polarity and exactly 8192 units are allowed', () {
    _request(
      List.generate(12, (index) => '广告$index'),
      List.generate(12, (index) => '剧情$index'),
    ).validate();
    _request(List.generate(4, (index) => '$index${'广' * 2047}')).validate();
    expect(
      () => _request(List.generate(4, (index) => '$index${'广' * 2047}'), [
        '额',
      ]).validate(),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'invalid counts, duplicates, conflicting polarity and malformed text fail',
    () {
      for (final request in [
        _request([]),
        _request(List.generate(13, (index) => '$index')),
        _request(['广告'], List.generate(13, (index) => '$index')),
        _request(['广告', '广告']),
        _request(['广告'], ['剧情', '剧情']),
        _request(['广告'], ['广告']),
        _request(['\ud800']),
        _request(['广告'], ['\udc00']),
        _request(['广告\n正文']),
        _request(['广告\r正文']),
        _request(['广告\u2028正文']),
        _request(['广告\u2029正文']),
        _request(['  ']),
        _request(['广' * 2049]),
      ]) {
        expect(request.validate, throwsA(isA<ValidationFailure>()));
      }
    },
  );

  test('only full core examples qualify, not surrounding context', () {
    const block = AiContextBlock(
      chapterId: 'chapter',
      chapterTitle: '正文',
      blockId: 'block',
      text: '前文广告正文后文',
    );
    final chunk = AiContextChunk(
      bookId: 'book',
      sessionId: 'session',
      sessionRevision: 1,
      index: 0,
      slices: [
        const AiContextSlice(
          block: block,
          startUtf16: 2,
          endUtf16: 6,
          before: '前文',
          text: '广告正文',
          after: '后文',
        ),
      ],
    );
    _request(['广告', '正文']).validate(context: chunk);
    for (final sample in ['前文', '文广告', '正文后']) {
      expect(
        () => _request([sample]).validate(context: chunk),
        throwsA(isA<ValidationFailure>()),
      );
    }
    expect(
      () => AiAnalysisResultDecoder.decode(
        jsonEncode({
          'schema_version': 1,
          'findings': <Object>[],
          'proposals': <Object>[],
          'rule_proposals': <Object>[],
        }),
        context: chunk,
        responseId: 'response',
        ruleRequest: _request(['前文']),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
