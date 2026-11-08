import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_proofreading_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/proofreading_quality.dart'
    show validateReferenceCorpusCoverage;
import '../../tool/src/proofreading_quality.dart';

void main() {
  late QualityCorpus corpus;

  setUpAll(() {
    corpus = QualityCorpus.decode(
      File('test/fixtures/proofreading/quality-corpus.json').readAsStringSync(),
    );
  });

  test(
    'the corpus retains protected challenges and explicit synthetic origin',
    () {
      final raw = jsonDecode(
        File('test/fixtures/proofreading/quality-corpus.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(raw['provenance'], containsPair('human_reviewed', false));
      expect(
        raw['provenance'],
        containsPair('contains_user_manuscripts', false),
      );
      expect(corpus.cases, hasLength(28));
      expect(corpus.cases.expand((value) => value.labels), hasLength(30));
      expect(
        corpus.cases
            .singleWhere((value) => value.id == 'chunk-boundary')
            .plan
            .chunks
            .length,
        greaterThan(1),
      );
      expect(
        corpus.cases.where((value) => value.tags.contains('protected')).length,
        greaterThanOrEqualTo(8),
      );
    },
  );

  test('the CLI rejects a shrunken or relabeled reference corpus', () {
    expect(() => validateReferenceCorpusCoverage(corpus), returnsNormally);
    final raw = jsonDecode(
      File('test/fixtures/proofreading/quality-corpus.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final cases = raw['cases'] as List;
    final removed = cases.removeLast();
    expect(
      () => validateReferenceCorpusCoverage(
        QualityCorpus.decode(jsonEncode(raw)),
      ),
      throwsFormatException,
    );
    cases.add(removed);
    ((cases.first as Map<String, dynamic>)['labels'] as List).clear();
    expect(
      () => validateReferenceCorpusCoverage(
        QualityCorpus.decode(jsonEncode(raw)),
      ),
      throwsFormatException,
    );
  });

  test(
    'synthetic references traverse the real decoder and change compiler',
    () {
      final evaluation = QualityEvaluator.evaluateResponses(
        corpus,
        referenceResponses(corpus),
      );
      final summary = evaluation.summary;
      expect(summary['case_count'], 28);
      expect(summary['action_tp'], 20);
      expect(summary['action_fp'], 0);
      expect(summary['action_fn'], 0);
      expect(summary['classification_tp'], 30);
      expect(summary['classification_fp'], 0);
      expect(summary['classification_fn'], 0);
      expect(summary['protected_false_positives'], 0);
      expect(summary['invalid_cases'], 0);
      expect(summary['compile_blocked_cases'], 0);
      expect(summary['effective_cases'], 28);
      expect(summary['effective_change_cases'], 19);
      expect(summary['effective_mismatch_cases'], 0);
      final metrics = summary['action_metrics'] as Map<String, Object?>;
      Map<String, Object?> action(String name) =>
          metrics[name] as Map<String, Object?>;
      expect(action('delete_text')['tp'], 9);
      expect(action('remove_block')['tp'], 2);
      expect(action('split_chapter')['tp'], 6);
      expect(action('rename_chapter')['tp'], 3);
      for (final name in metrics.keys) {
        expect(action(name)['fp'], 0, reason: name);
        expect(action(name)['fn'], 0, reason: name);
      }
      expect(evaluation.hasStrictFailure, isFalse);
      expect(evaluation.toJson()['realProviderQualityVerified'], isFalse);
      expect(evaluation.toJson()['qualityPassed'], isFalse);
    },
  );

  test('empty responses still account for every corpus case and chunk', () {
    final responses = <String, List<String>>{
      for (final qualityCase in corpus.cases)
        qualityCase.id: [
          for (final _ in qualityCase.plan.chunks)
            jsonEncode({
              'schema_version': 1,
              'findings': <Object>[],
              'proposals': <Object>[],
              'rule_proposals': <Object>[],
            }),
        ],
    };
    final evaluation = QualityEvaluator.evaluateResponses(corpus, responses);
    expect(evaluation.summary['action_tp'], 0);
    expect(evaluation.summary['action_fn'], 20);
    final emptyMetrics =
        evaluation.summary['action_metrics'] as Map<String, Object?>;
    Map<String, Object?> emptyAction(String name) =>
        emptyMetrics[name] as Map<String, Object?>;
    expect(emptyAction('delete_text')['fn'], 9);
    expect(emptyAction('remove_block')['fn'], 2);
    expect(emptyAction('split_chapter')['fn'], 6);
    expect(emptyAction('rename_chapter')['fn'], 3);
    expect(evaluation.summary['classification_fn'], 30);
    expect(evaluation.summary['action_precision'], isNull);
    expect(evaluation.summary['action_recall'], 0);
    expect(evaluation.summary['effective_change_cases'], 0);
    expect(evaluation.hasStrictFailure, isTrue);
  });

  test('a valid response can still be a protected false positive', () {
    final responses = referenceResponses(corpus);
    final response =
        jsonDecode(responses['story-quote']!.single) as Map<String, dynamic>;
    final finding =
        (response['findings'] as List).single as Map<String, dynamic>;
    finding['assessment'] = 'advertisement';
    response['proposals'] = [
      {
        'id': 'wrong-delete',
        'finding_id': finding['id'],
        'action': 'delete_text',
        'chapter_id': finding['chapter_id'],
        'block_id': finding['block_id'],
        'original': finding['original'],
        'before': finding['before'],
        'after': finding['after'],
        'replacement': '',
        'reason': '故意构造结构合法但语义错误的测试响应。',
      },
    ];
    responses['story-quote'] = [jsonEncode(response)];
    final evaluation = QualityEvaluator.evaluateResponses(corpus, responses);
    expect(evaluation.summary['invalid_cases'], 0);
    expect(evaluation.summary['action_fp'], 1);
    expect(evaluation.summary['protected_false_positives'], 1);
    expect(evaluation.summary['classification_fp'], 1);
    expect(evaluation.summary['classification_fn'], 1);
    expect(evaluation.summary['effective_mismatch_cases'], 1);
    expect(evaluation.hasStrictFailure, isTrue);
  });

  test('fixed rule baseline reports rather than hides its blind spots', () {
    final evaluation = QualityEvaluator.evaluateRules(corpus);
    expect(evaluation.summary['action_tp'], 14);
    expect(evaluation.summary['action_fp'], 5);
    expect(evaluation.summary['action_fn'], 6);
    final ruleMetrics =
        evaluation.summary['action_metrics'] as Map<String, Object?>;
    Map<String, Object?> ruleAction(String name) =>
        ruleMetrics[name] as Map<String, Object?>;
    expect(ruleAction('delete_text')['tp'], 8);
    expect(ruleAction('delete_text')['fp'], 4);
    expect(ruleAction('delete_text')['fn'], 1);
    expect(ruleAction('remove_block')['tp'], 0);
    expect(ruleAction('remove_block')['fn'], 2);
    expect(ruleAction('split_chapter')['tp'], 6);
    expect(ruleAction('split_chapter')['fp'], 1);
    expect(ruleAction('rename_chapter')['tp'], 0);
    expect(ruleAction('rename_chapter')['fn'], 3);
    expect(evaluation.summary['protected_false_positives'], 3);
    expect(evaluation.summary['classification_status'], 'not_applicable');
    expect(evaluation.summary['classification_recall'], isNull);
    expect(evaluation.summary['invalid_cases'], 0);
    expect(evaluation.summary['compile_blocked_cases'], 0);
    expect(evaluation.summary['effective_cases'], 19);
    expect(evaluation.summary['effective_change_cases'], 12);
    expect(evaluation.summary['effective_mismatch_cases'], 9);
    expect(evaluation.hasStrictFailure, isTrue);
    for (final id in [
      'block-remove-site-ad',
      'block-remove-between-resources',
    ]) {
      final result = evaluation.caseResults.singleWhere(
        (value) => value['id'] == id,
      );
      expect(result['action_fp'], 1, reason: id);
      expect(result['action_fn'], 1, reason: id);
      expect(result['expected_after_equal'], isFalse, reason: id);
    }
    final mixed = evaluation.caseResults.singleWhere(
      (value) => value['id'] == 'block-mixed-ad-stays-text',
    );
    expect(mixed['action_tp'], 1);
    expect(mixed['expected_after_equal'], isTrue);
    for (final id in [
      'rename-wrong-directory-title',
      'rename-empty-directory-title',
      'rename-emoji-heading',
    ]) {
      final rename = evaluation.caseResults.singleWhere(
        (value) => value['id'] == id,
      );
      expect(rename['action_fn'], 1, reason: id);
      expect(rename['expected_after_equal'], isFalse, reason: id);
    }
  });

  test('emptying a whole advertisement block is not counted as removal', () {
    final responses = referenceResponses(corpus);
    final response = jsonDecode(
      responses['block-remove-site-ad']!.single,
    ) as Map<String, dynamic>;
    final proposal =
        (response['proposals'] as List).single as Map<String, dynamic>;
    expect(proposal['action'], 'remove_block');
    proposal['action'] = 'delete_text';
    responses['block-remove-site-ad'] = [jsonEncode(response)];

    final evaluation = QualityEvaluator.evaluateResponses(corpus, responses);
    final result = evaluation.caseResults.singleWhere(
      (value) => value['id'] == 'block-remove-site-ad',
    );

    expect(result['action_tp'], 0);
    expect(result['action_fp'], 1);
    expect(result['action_fn'], 1);
    expect(result['expected_after_equal'], isFalse);
    expect(result['invalid_result'], isNull);
    expect(result['compile_blocked'], isNull);
    expect(evaluation.summary['effective_mismatch_cases'], 1);
    expect(evaluation.summary['protected_false_positives'], 0);
    expect(evaluation.hasStrictFailure, isTrue);
  });

  test(
    'an invalid later chunk discards earlier valid proposals in that case',
    () {
      final responses = referenceResponses(corpus);
      final firstResponse = jsonDecode(
        responses['chunk-boundary']!.first,
      ) as Map<String, dynamic>;
      final qualityCase = corpus.cases.singleWhere(
        (value) => value.id == 'chunk-boundary',
      );
      final slice = qualityCase.plan.chunks.first.slices.first;
      const original = '起始。';
      final target = {
        'chapter_id': slice.block.chapterId,
        'block_id': slice.block.blockId,
        'original': original,
        'before': '',
        'after': slice.block.text.substring(
          original.length,
          original.length + 32,
        ),
        'reason': '本例故意构造第一块合法提案，再令后块无效。',
      };
      firstResponse['findings'] = [
        {
          'id': 'first-finding',
          'category': 'advertisement',
          'assessment': 'advertisement',
          ...target,
        },
      ];
      firstResponse['proposals'] = [
        {
          'id': 'first-delete',
          'finding_id': 'first-finding',
          'action': 'delete_text',
          'replacement': '',
          ...target,
        },
      ];
      responses['chunk-boundary']![0] = jsonEncode(firstResponse);
      responses['chunk-boundary']![responses['chunk-boundary']!.length - 1] =
          '{';
      final evaluation = QualityEvaluator.evaluateResponses(corpus, responses);
      final result = evaluation.caseResults.singleWhere(
        (value) => value['id'] == 'chunk-boundary',
      );
      expect(result['invalid_result'], isNotNull);
      expect(result['action_tp'], 0);
      expect(result['action_fp'], 0);
      expect(result['action_fn'], 1);
      expect(result['expected_after_equal'], isFalse);
      expect(evaluation.summary['invalid_cases'], 1);
      expect(evaluation.summary['effective_cases'], 27);
    },
  );

  test('duplicate exact edits count as extras and block the whole compile', () {
    final responses = referenceResponses(corpus);
    final response =
        jsonDecode(responses['site-banner']!.single) as Map<String, dynamic>;
    final proposals = response['proposals'] as List;
    proposals.add({
      ...proposals.single as Map<String, dynamic>,
      'id': 'duplicate-delete',
    });
    responses['site-banner'] = [jsonEncode(response)];
    final evaluation = QualityEvaluator.evaluateResponses(corpus, responses);
    expect(evaluation.summary['action_tp'], 20);
    expect(evaluation.summary['action_fp'], 1);
    expect(evaluation.summary['compile_blocked_cases'], 1);
    expect(evaluation.summary['effective_mismatch_cases'], 1);
    expect(evaluation.hasStrictFailure, isTrue);
  });
  test('markdown report is human-readable and does not leak corpus text', () {
    final rules = qualityMarkdownReport(QualityEvaluator.evaluateRules(corpus));
    expect(rules, contains('# Bookloom proofreading quality report'));
    expect(rules, contains('## Per action'));
    expect(rules, contains('delete_text'));
    expect(rules, contains('rename_chapter'));
    expect(rules, contains('rename-wrong-directory-title'));
    expect(rules, isNot(contains('请记住本站')));
    expect(rules, isNot(contains('她推开门')));

    final reference = qualityMarkdownReport(
      QualityEvaluator.evaluateResponses(corpus, referenceResponses(corpus)),
    );
    expect(reference, contains('_None._'));
    expect(reference, contains('| delete_text | 9 | 0 | 0 |'));
    expect(reference, contains('Real-provider quality verified: `false`'));
  });
}

Map<String, List<String>> referenceResponses(QualityCorpus corpus) => {
  for (final qualityCase in corpus.cases)
    qualityCase.id: [
      for (final chunk in qualityCase.plan.chunks)
        _referenceResponse(qualityCase, chunk),
    ],
};

String _referenceResponse(QualityCase qualityCase, AiContextChunk chunk) {
  final findings = <Map<String, Object?>>[];
  final proposals = <Map<String, Object?>>[];
  for (final label in qualityCase.labels) {
    final slices = chunk.slices.where(
      (slice) =>
          slice.block.chapterId == label.chapterId &&
          slice.block.blockId == label.blockId &&
          slice.startUtf16 <= label.startUtf16 &&
          slice.endUtf16 >= label.endUtf16,
    );
    if (slices.isEmpty) continue;
    final slice = slices.single;
    final text = slice.block.text;
    var beforeStart = label.startUtf16 - 32;
    if (beforeStart < 0) beforeStart = 0;
    if (beforeStart > 0 && _isLowSurrogate(text.codeUnitAt(beforeStart))) {
      beforeStart++;
    }
    var afterEnd = label.endUtf16 + 32;
    if (afterEnd > text.length) afterEnd = text.length;
    if (afterEnd < text.length && _isLowSurrogate(text.codeUnitAt(afterEnd))) {
      afterEnd--;
    }
    final target = <String, Object?>{
      'chapter_id': label.chapterId,
      'block_id': label.blockId,
      'original': label.original,
      'before': text.substring(beforeStart, label.startUtf16),
      'after': text.substring(label.endUtf16, afterEnd),
      'reason': label.reason,
    };
    findings.add({
      'id': label.id,
      'category': qualityCase.intent == AiProofreadingIntent.advertisement
          ? 'advertisement'
          : 'missing_chapter',
      'assessment': label.acceptableAssessments.first,
      ...target,
    });
    if (label.action == 'none') continue;
    proposals.add({
      'id': 'change-${label.id}',
      'finding_id': label.id,
      'action': label.action,
      ...target,
      if (label.action == 'delete_text' || label.action == 'remove_block')
        'replacement': '',
      if (label.action == 'rename_chapter') ...{
        'replacement': label.title,
        'original_title': qualityCase.source.chapters
            .singleWhere((chapter) => chapter.id == label.chapterId)
            .title,
      },
      if (label.action == 'split_chapter') ...{
        'title': label.title,
        'remove_title_line': label.removeTitleLine,
      },
    });
  }
  return jsonEncode({
    'schema_version': 1,
    'findings': findings,
    'proposals': proposals,
    'rule_proposals': <Object>[],
  });
}

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
