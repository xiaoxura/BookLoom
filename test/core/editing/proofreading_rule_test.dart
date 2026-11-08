import 'dart:convert';

import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_store.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> ruleJson({
  String kind = 'advertisement',
  String target = 'body_line',
  String mode = 'literal',
  String pattern = '点击阅读',
  String action = 'exact_deletion',
  List<String>? positiveExamples,
  List<String>? negativeExamples,
}) => <String, Object>{
  'schema_version': 1,
  'name': '清理推广语',
  'kind': kind,
  'target': target,
  'match': <String, Object>{
    'mode': mode,
    'pattern': pattern,
    'case_sensitive': true,
  },
  'action': action,
  'positive_examples': positiveExamples ?? <String>['点击阅读本书'],
  'negative_examples': negativeExamples ?? <String>['普通剧情'],
  'reason': '匹配明确的推广短语，等待试跑。',
};

RuleProposal decode(
  Map<String, Object?> value, {
  String bookId = 'book-a',
  ProofreadingRuleScope scope = ProofreadingRuleScope.book,
  bool globalScopeConfirmed = false,
  ProofreadingRuleSource source = ProofreadingRuleSource.ai,
  List<String>? requiredPositiveExamples,
  List<String>? requiredNegativeExamples,
}) => RuleProposalDecoder.decode(
  jsonEncode(value),
  proposalId: 'local-proposal',
  ruleId: 'local-rule',
  bookId: bookId,
  source: source,
  requiredPositiveExamples: requiredPositiveExamples ?? ['点击阅读本书'],
  requiredNegativeExamples: requiredNegativeExamples ?? ['普通剧情'],
  scope: scope,
  globalScopeConfirmed: globalScopeConfirmed,
);

void main() {
  test('number capture preserves base title and exact numeral evidence', () {
    ProofreadingRule create({
      String pattern = r'^([^:]+):(夜雨😀)$',
      String positive = '12:夜雨😀',
      int? titleGroup = 2,
      int? numberGroup = 1,
      int level = 2,
    }) => ProofreadingRule.create(
      id: 'numbered',
      name: '章号映射',
      kind: ProofreadingRuleKind.chapter,
      source: ProofreadingRuleSource.user,
      bookId: 'book-a',
      target: ProofreadingRuleTarget.headingLine,
      mode: ProofreadingMatchMode.safeRegex,
      pattern: pattern,
      titleCaptureGroup: titleGroup,
      numberCaptureGroup: numberGroup,
      headingLevel: level,
      caseSensitive: true,
      action: ProofreadingRuleAction.chapterCandidate,
      positiveExamples: [positive],
      negativeExamples: const ['普通正文'],
    );

    final numbered = create();
    for (final (text, number) in [
      (' 12 ', 12),
      ('十三', 13),
      ('壹拾叁', 13),
      ('999999999', 999999999),
    ]) {
      final match = numbered.matchSample('$text:夜雨😀').single;
      expect(match.mappedTitle, '夜雨😀');
      expect(match.mappedNumber, number);
      expect(match.numberText, text.trim());
    }
    for (final text in ['0', '-1', '1.2', '1000000000', '未知', ' ']) {
      expect(
        () => numbered.matchScanText('$text:夜雨😀').toList(),
        throwsA(isA<ValidationFailure>()),
      );
    }
    final optional = create(pattern: r'^(12)?:(夜雨😀)$');
    expect(
      () => optional.matchScanText(':夜雨😀').toList(),
      throwsA(isA<ValidationFailure>()),
    );
    final empty = create(pattern: r'^([^:]*):(夜雨😀)$');
    expect(
      () => empty.matchScanText(':夜雨😀').toList(),
      throwsA(isA<ValidationFailure>()),
    );
    for (final group in [-1, 3]) {
      expect(
        () => create(numberGroup: group),
        throwsA(isA<ValidationFailure>()),
      );
    }
    expect(() => create(titleGroup: null), throwsA(isA<ValidationFailure>()));
    final whole = create(
      pattern: r'^((12))$',
      positive: '12',
      numberGroup: 0,
    ).matchSample('12').single;
    expect(whole.mappedNumber, 12);
    expect(whole.numberText, '12');
    final prefixed = create(
      pattern: r'^(12):(第十二章 夜雨😀)$',
      positive: '12:第十二章 夜雨😀',
    );
    expect(
      prefixed.matchSample('12:第十二章 夜雨😀').single.mappedTitle,
      '第十二章 夜雨😀',
    );
    expect(
      () => create(
        pattern: r'^(12):(第十二章 夜雨😀)$',
        positive: '12:第十二章 夜雨😀',
        level: 1,
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => create(pattern: r'^(12):(第十三章 夜雨😀)$', positive: '12:第十三章 夜雨😀'),
      throwsA(isA<ValidationFailure>()),
    );
    final legacy = create(numberGroup: null).matchSample('12:夜雨😀').single;
    expect(legacy.mappedNumber, isNull);
    expect(legacy.numberText, isNull);
  });

  test(
    'AI number mapping is optional, strict and requires a title capture',
    () {
      final base = ruleJson(
        kind: 'chapter',
        target: 'heading_line',
        mode: 'safe_regex',
        pattern: r'^(12):(夜雨😀)$',
        action: 'chapter_candidate',
        positiveExamples: ['12:夜雨😀'],
      );
      final match = base['match'] as Map<String, Object>;
      RuleProposal proposal(Map<String, Object?> value) =>
          decode(value, requiredPositiveExamples: ['12:夜雨😀']);
      final validMatch = {...match, 'title_capture_group': 2};
      expect(
        proposal({...base, 'match': validMatch}).rule.numberCaptureGroup,
        isNull,
      );
      expect(
        proposal({
          ...base,
          'match': {...validMatch, 'number_capture_group': 1},
        }).rule.numberCaptureGroup,
        1,
      );
      for (final invalid in <Object?>[null, true, 1.0, -1, 3, '1']) {
        expect(
          () => proposal({
            ...base,
            'match': {...validMatch, 'number_capture_group': invalid},
          }),
          throwsA(isA<ValidationFailure>()),
        );
      }
      expect(
        () => proposal({
          ...base,
          'match': {...match, 'number_capture_group': 1},
        }),
        throwsA(isA<ValidationFailure>()),
      );
      for (final value in [
        ruleJson(),
        {
          ...base,
          'match': {...validMatch, 'mode': 'literal'},
        },
      ]) {
        final rawMatch = value['match'] as Map<String, Object>;
        expect(
          () => decode({
            ...value,
            'match': {...rawMatch, 'number_capture_group': 0},
          }),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );

  test('heading level defaults to chapters and validates AI root values', () {
    final base = ruleJson(
      kind: 'chapter',
      target: 'heading_line',
      action: 'chapter_candidate',
    );
    expect(decode(base).rule.headingLevel, 2);
    expect(decode({...base, 'heading_level': 1}).rule.headingLevel, 1);
    expect(decode({...base, 'heading_level': 2}).rule.headingLevel, 2);
    for (final invalid in <Object?>[null, true, 1.0, 0, 3, '1']) {
      expect(
        () => decode({...base, 'heading_level': invalid}),
        throwsA(isA<ValidationFailure>()),
      );
    }
    expect(
      () => decode({...ruleJson(), 'heading_level': 1}),
      throwsA(isA<ValidationFailure>()),
    );
    expect(decode({...ruleJson(), 'heading_level': 2}).rule.headingLevel, 2);
    final match = base['match'] as Map<String, Object>;
    expect(
      () => decode({
        ...base,
        'match': {...match, 'heading_level': 1},
      }),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => decode({...base, 'unknown_level': 1}),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('keeps identity and default book scope local', () {
    final proposal = decode(ruleJson(negativeExamples: ['普通剧情']));
    final rule = proposal.rule;
    expect(proposal.proposalId, 'local-proposal');
    expect(proposal.requiredPositiveExamples, ['点击阅读本书']);
    expect(proposal.requiredNegativeExamples, ['普通剧情']);
    expect(rule.id, 'local-rule');
    expect(rule.bookId, 'book-a');
    expect(rule.source, ProofreadingRuleSource.ai);
    expect(rule.scope, ProofreadingRuleScope.book);
    expect(rule.enabled, isTrue);
    expect(rule.appliesToBook('book-a'), isTrue);
    expect(rule.appliesToBook('book-b'), isFalse);
    expect(rule.target, ProofreadingRuleTarget.bodyLine);
    expect(rule.action, ProofreadingRuleAction.exactDeletion);
    expect(proposal.reason, contains('试跑'));
  });

  test('global scope requires explicit local confirmation', () {
    expect(
      () => decode(ruleJson(), scope: ProofreadingRuleScope.global),
      throwsA(isA<ValidationFailure>()),
    );
    final global = decode(
      ruleJson(),
      scope: ProofreadingRuleScope.global,
      globalScopeConfirmed: true,
      source: ProofreadingRuleSource.user,
    ).rule;
    expect(global.appliesToBook('book-b'), isTrue);
    expect(global.source, ProofreadingRuleSource.user);
    expect(
      () => decode(ruleJson(), source: ProofreadingRuleSource.builtIn),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('rejects model-owned scope, identity, source and script fields', () {
    for (final field in <String, Object>{
      'scope': 'global',
      'book_id': 'book-b',
      'id': 'built-in-id',
      'source': 'built_in',
      'script': 'deleteAll()',
      'required_positive_examples': ['点击阅读本书'],
    }.entries) {
      expect(
        () => decode({...ruleJson(), field.key: field.value}),
        throwsA(isA<ValidationFailure>()),
      );
    }
    final value = ruleJson();
    final match = Map<String, Object>.from(value['match']! as Map);
    expect(
      () => decode({
        ...value,
        'match': {...match, 'script': 'run()'},
      }),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'accepts chapter candidate and advertisement candidate combinations',
    () {
      final chapter = decode(
        ruleJson(
          kind: 'chapter',
          target: 'heading_line',
          mode: 'safe_regex',
          pattern: r'^第[一二三]章',
          action: 'chapter_candidate',
          positiveExamples: ['第一章 风起', '第二章 风起'],
          negativeExamples: ['他说第一章很好看'],
        ),
        requiredPositiveExamples: ['第一章 风起'],
        requiredNegativeExamples: ['他说第一章很好看'],
      ).rule;
      expect(chapter.kind, ProofreadingRuleKind.chapter);
      expect(chapter.matchSample('第三章 归来').single.startUtf16, 0);
      final advertisement = decode(
        ruleJson(
          target: 'paragraph',
          action: 'advertisement_candidate',
          negativeExamples: ['普通剧情'],
        ),
      ).rule;
      expect(advertisement.target, ProofreadingRuleTarget.paragraph);
    },
  );

  test(
    'rejects action and target combinations outside the first rule types',
    () {
      for (final value in <Map<String, Object>>[
        ruleJson(kind: 'chapter', action: 'chapter_candidate'),
        ruleJson(kind: 'chapter', target: 'heading_line'),
        ruleJson(target: 'heading_line'),
        ruleJson(action: 'chapter_candidate'),
        ruleJson(kind: 'script', action: 'run_script'),
      ]) {
        expect(() => decode(value), throwsA(isA<ValidationFailure>()));
      }
    },
  );

  test('uses safe regex and rejects unsafe or zero-length patterns', () {
    for (final pattern in <String>[
      r'(a+)+',
      r'(a|aa)+',
      r'(a)\1',
      r'(?=广告)',
      r'^',
      r'广告|\b',
      r'(广告)?',
    ]) {
      expect(
        () => decode(
          ruleJson(
            mode: 'safe_regex',
            pattern: pattern,
            positiveExamples: ['广告'],
            negativeExamples: ['普通剧情'],
          ),
        ),
        throwsA(isA<ValidationFailure>()),
        reason: pattern,
      );
    }
  });

  test('literal mode does not interpret metacharacters', () {
    final rule = decode(
      ruleJson(
        pattern: '第.*章',
        positiveExamples: ['他说第.*章是代码'],
        negativeExamples: ['第一章 正文'],
      ),
      requiredPositiveExamples: ['第.*章'],
      requiredNegativeExamples: ['第一章 正文'],
    ).rule;
    expect(rule.matchSample('第一章 正文'), isEmpty);
    expect(rule.matchSample('第.*章').single.endUtf16, 4);
  });

  test('maps chapter captures and preserves the legacy full-line title', () {
    Map<String, Object> chapterRule({Object? group, bool includeGroup = true}) {
      final value = ruleJson(
        kind: 'chapter',
        target: 'heading_line',
        mode: 'safe_regex',
        pattern: r'^【([^】]+)】(夜雨😀)',
        action: 'chapter_candidate',
        positiveExamples: ['【卷二】夜雨😀'],
        negativeExamples: ['普通正文'],
      );
      if (includeGroup) {
        (value['match']! as Map<String, Object>)['title_capture_group'] =
            group!;
      }
      return value;
    }

    RuleProposal proposal(Map<String, Object?> value) => decode(
      value,
      requiredPositiveExamples: ['【卷二】夜雨😀'],
      requiredNegativeExamples: ['普通正文'],
    );

    expect(
      proposal(chapterRule(includeGroup: false)).rule
          .matchSample('【卷二】夜雨😀')
          .single
          .mappedTitle,
      isNull,
    );
    expect(
      proposal(chapterRule(group: 0)).rule
          .matchSample('【卷二】夜雨😀')
          .single
          .mappedTitle,
      '【卷二】夜雨😀',
    );
    expect(
      proposal(chapterRule(group: 2)).rule
          .matchSample('【卷二】夜雨😀')
          .single
          .mappedTitle,
      '夜雨😀',
    );
    for (final group in <Object?>[-1, 3, null, true, 1.0, '1']) {
      final value = <String, Object?>{
        ...chapterRule(includeGroup: false),
        'match': <String, Object?>{
          ...(chapterRule(includeGroup: false)['match']!
              as Map<String, Object>),
          'title_capture_group': group,
        },
      };
      expect(() => proposal(value), throwsA(isA<ValidationFailure>()));
    }
    for (final value in [
      ruleJson(),
      ruleJson(
        kind: 'chapter',
        target: 'heading_line',
        action: 'chapter_candidate',
        pattern: '【卷二】夜雨😀',
        positiveExamples: ['【卷二】夜雨😀'],
      ),
    ]) {
      (value['match']! as Map<String, Object>)['title_capture_group'] = 0;
      expect(() => proposal(value), throwsA(isA<ValidationFailure>()));
    }
  });

  test(
    'rejects empty, absent, long, multiline and invalid UTF-16 captures',
    () {
      ProofreadingRule create(String pattern, int group, String sample) =>
          ProofreadingRule.create(
            id: 'title',
            name: '标题',
            kind: ProofreadingRuleKind.chapter,
            source: ProofreadingRuleSource.user,
            bookId: 'book-a',
            target: ProofreadingRuleTarget.headingLine,
            mode: ProofreadingMatchMode.safeRegex,
            pattern: pattern,
            titleCaptureGroup: group,
            caseSensitive: true,
            action: ProofreadingRuleAction.chapterCandidate,
            positiveExamples: [sample],
            negativeExamples: const ['普通正文'],
          );

      final optional = create(r'^(标题)(旧)?', 2, '标题旧');
      expect(optional.matchScanText('标题旧').single.mappedTitle, '旧');
      expect(
        () => optional.matchScanText('标题').toList(),
        throwsA(isA<ValidationFailure>()),
      );
      final whitespace = create(r'^(标题)([ a-z]+)', 2, '标题x');
      expect(
        () => whitespace.matchScanText('标题  ').toList(),
        throwsA(isA<ValidationFailure>()),
      );
      final long = create(r'^(标题)([a-z]+)', 2, '标题a');
      expect(
        () => long.matchScanText('标题${'a' * 257}').toList(),
        throwsA(isA<ValidationFailure>()),
      );
      final multiline = create(r'^(标题)([\sa-z]+)', 2, '标题x');
      expect(
        () => multiline.matchScanText('标题\n').toList(),
        throwsA(isA<ValidationFailure>()),
      );
      final invalidSurrogate = create(r'^(标题)(.)', 2, '标题x');
      expect(
        () => invalidSurrogate
            .matchScanText('标题${String.fromCharCode(0xd800)}')
            .toList(),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('requires every positive and excludes ordinary-story negatives', () {
    for (final value in <Map<String, Object>>[
      ruleJson(positiveExamples: []),
      ruleJson(positiveExamples: ['点击阅读', '普通正文']),
      ruleJson(negativeExamples: ['他点击阅读了信件']),
    ]) {
      expect(() => decode(value), throwsA(isA<ValidationFailure>()));
    }
    final rule = decode(
      ruleJson(
        pattern: '本站广告',
        positiveExamples: ['本站广告：请访问'],
        negativeExamples: ['他提到了本站，但没有推广'],
      ),
      requiredPositiveExamples: ['本站广告：请访问'],
      requiredNegativeExamples: ['他提到了本站，但没有推广'],
    ).rule;
    expect(rule.matchSample('他提到了本站，但没有推广'), isEmpty);
  });

  test('rejects a model-consistent rule that misses the user selection', () {
    expect(
      () => decode(ruleJson(), requiredPositiveExamples: ['用户选中的本站广告']),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('rejects a model-consistent rule that hits a local story negative', () {
    expect(
      () => decode(ruleJson(), requiredNegativeExamples: ['他点击阅读了信件']),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('retains immutable local examples for validation after editing', () {
    final selected = ['😀点击阅读本书'];
    final excluded = ['普通剧情'];
    final proposal = decode(
      ruleJson(),
      requiredPositiveExamples: selected,
      requiredNegativeExamples: excluded,
    );
    selected.clear();
    excluded.add('外部修改');
    expect(proposal.requiredPositiveExamples, ['😀点击阅读本书']);
    expect(proposal.requiredNegativeExamples, ['普通剧情']);
    expect(proposal.rule.matchSample('😀点击阅读本书').single.startUtf16, 2);
    expect(
      () => proposal.requiredPositiveExamples.add('伪造样例'),
      throwsUnsupportedError,
    );
    expect(proposal.requiredNegativeExamples.clear, throwsUnsupportedError);
    expect(
      () => decode(
        ruleJson(pattern: '另一广告', positiveExamples: ['另一广告']),
        requiredPositiveExamples: proposal.requiredPositiveExamples,
        requiredNegativeExamples: proposal.requiredNegativeExamples,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('requires local positives and enforces their independent budgets', () {
    final invalid = <(List<String>, List<String>)>[
      (<String>[], <String>[]),
      (List<String>.filled(13, '点击阅读'), <String>[]),
      (<String>['点击阅读'], List<String>.filled(13, '普通剧情')),
      (<String>['点击阅读${'文' * 2045}'], <String>[]),
      (<String>['点击阅读'], <String>['文' * 2049]),
      (List<String>.filled(5, '点击阅读${'文' * 1800}'), <String>[]),
      (<String>['😀' * 1023 + '点击阅读'], <String>[]),
      (<String>['点击阅读${String.fromCharCode(0xd800)}'], <String>[]),
      (<String>['点击阅读\n正文'], <String>[]),
    ];
    for (final (positives, negatives) in invalid) {
      expect(
        () => decode(
          ruleJson(),
          requiredPositiveExamples: positives,
          requiredNegativeExamples: negatives,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('reports exact UTF-16 match spans without editing source', () {
    final text = '😀前点击阅读后点击阅读';
    final rule = decode(ruleJson(negativeExamples: ['普通剧情'])).rule;
    final matches = rule.matchSample(text);
    expect(matches.map((match) => match.startUtf16), [3, 8]);
    expect(matches.map((match) => match.endUtf16), [7, 12]);
    expect(text, '😀前点击阅读后点击阅读');
    expect(matches.clear, throwsUnsupportedError);
  });

  test('enforces UTF-16 pattern, sample, count and total budgets', () {
    for (final value in <Map<String, Object>>[
      ruleJson(pattern: '😀' * 129, positiveExamples: ['😀' * 129]),
      ruleJson(pattern: 'x' * 257, positiveExamples: ['x' * 257]),
      ruleJson(positiveExamples: ['x' * 2049]),
      ruleJson(positiveExamples: List<String>.filled(13, '点击阅读')),
      ruleJson(
        positiveExamples: List<String>.filled(5, '点击阅读${'文' * 1800}'),
        negativeExamples: ['普通剧情'],
      ),
      ruleJson(pattern: String.fromCharCode(0xd800)),
      ruleJson(positiveExamples: ['点击阅读\n正文']),
    ]) {
      expect(() => decode(value), throwsA(isA<ValidationFailure>()));
    }
    expect(
      () =>
          decode(ruleJson(negativeExamples: ['普通剧情'])).rule
              .matchSample('文' * 2049),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'rejects duplicate JSON keys, unknown fields and malformed envelopes',
    () {
      final valid = jsonEncode(ruleJson());
      for (final response in <String>[
        valid.replaceFirst(
          '"schema_version":1',
          '"schema_version":2,"schema_version":1',
        ),
        valid.replaceFirst('"name":"清理推广语"', r'"name":"x","\u006eame":"清理推广语"'),
        valid.replaceFirst(
          '"mode":"literal"',
          '"script":"run()","mode":"literal"',
        ),
        '```json\n$valid\n```',
        '私密内容' * 6000,
      ]) {
        expect(
          () => RuleProposalDecoder.decode(
            response,
            proposalId: 'local-proposal',
            ruleId: 'local-rule',
            bookId: 'book-a',
            source: ProofreadingRuleSource.ai,
            requiredPositiveExamples: ['点击阅读本书'],
            requiredNegativeExamples: ['普通剧情'],
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );

  test(
    'keeps examples immutable and does not echo untrusted input in errors',
    () {
      final positives = ['点击阅读'];
      final negatives = ['普通剧情'];
      final rule = ProofreadingRule.create(
        id: 'local-rule',
        name: '推广',
        kind: ProofreadingRuleKind.advertisement,
        source: ProofreadingRuleSource.user,
        bookId: 'book-a',
        target: ProofreadingRuleTarget.bodyLine,
        mode: ProofreadingMatchMode.literal,
        pattern: '点击阅读',
        caseSensitive: true,
        action: ProofreadingRuleAction.advertisementCandidate,
        positiveExamples: positives,
        negativeExamples: negatives,
      );
      positives.add('外部修改');
      negatives.clear();
      expect(rule.positiveExamples, ['点击阅读']);
      expect(rule.negativeExamples, ['普通剧情']);
      expect(() => rule.positiveExamples.add('新项'), throwsUnsupportedError);
      try {
        decode(ruleJson(pattern: '秘密敏感词', positiveExamples: ['普通剧情']));
        fail('Expected validation failure');
      } on ValidationFailure catch (error) {
        expect(error.toString(), isNot(contains('秘密')));
        expect(error.toString(), isNot(contains('普通剧情')));
      }
    },
  );

  group('exclude text', () {
    ProofreadingRule rule({
      String? exclude,
      bool caseSensitive = false,
      ProofreadingRuleTarget target = ProofreadingRuleTarget.paragraph,
    }) => ProofreadingRule.create(
      id: 'excluded',
      name: '带排除条件的推广',
      kind: ProofreadingRuleKind.advertisement,
      source: ProofreadingRuleSource.user,
      bookId: 'book-a',
      target: target,
      mode: ProofreadingMatchMode.literal,
      pattern: 'ad',
      excludePattern: exclude,
      caseSensitive: caseSensitive,
      action: ProofreadingRuleAction.advertisementCandidate,
      positiveExamples: const ['ad'],
      negativeExamples: const [],
    );

    test('suppresses only matches whose line contains the exclude text', () {
      final without = rule();
      final withExclude = rule(exclude: 'skip');
      const text = 'ad 一行\nskip ad 行\nad 三行';
      expect(without.matchScanText(text).map((match) => match.startUtf16), [
        0,
        11,
        16,
      ]);
      expect(withExclude.matchScanText(text).map((match) => match.startUtf16), [
        0,
        16,
      ]);
      expect(withExclude.excludePattern, 'skip');
    });

    test('follows the rule case-sensitivity for exclusion', () {
      const text = 'ad\nSKIP ad';
      expect(
        rule(
          exclude: 'skip',
          caseSensitive: false,
        ).matchScanText(text).map((match) => match.startUtf16),
        [0],
      );
      expect(
        rule(
          exclude: 'skip',
          caseSensitive: true,
        ).matchScanText(text).map((match) => match.startUtf16),
        [0, 8],
      );
    });

    test('keeps excluded matches out of heading lookups too', () {
      final heading = ProofreadingRule.create(
        id: 'excluded-heading',
        name: '标题排除',
        kind: ProofreadingRuleKind.chapter,
        source: ProofreadingRuleSource.user,
        bookId: 'book-a',
        target: ProofreadingRuleTarget.headingLine,
        mode: ProofreadingMatchMode.literal,
        pattern: 'ad',
        excludePattern: '引用',
        caseSensitive: false,
        action: ProofreadingRuleAction.chapterCandidate,
        positiveExamples: const ['ad'],
        negativeExamples: const [],
      );
      expect(heading.matchScanText('ad 标题').map((match) => match.startUtf16), [
        0,
      ]);
      expect(heading.matchScanText('ad 引用标题'), isEmpty);
    });

    test('changes fingerprints and is rejected when malformed', () {
      expect(
        proofreadingRuleFingerprint(rule()),
        isNot(proofreadingRuleFingerprint(rule(exclude: 'skip'))),
      );
      expect(
        proofreadingRuleFingerprint(rule(exclude: 'skip')),
        isNot(proofreadingRuleFingerprint(rule(exclude: 'skip-else'))),
      );
      for (final exclude in <String>[
        'a\nb',
        ' ',
        List.filled(257, 'x').join(),
      ]) {
        expect(
          () => rule(exclude: exclude),
          throwsA(isA<ValidationFailure>()),
          reason: exclude,
        );
      }
    });
  });

  group('whole-line condition', () {
    test('ignores outer whitespace only and rejects paragraph targets', () {
      ProofreadingRule wholeLine({String? exclude, bool whole = true}) =>
          ProofreadingRule.create(
            id: 'whole-line',
            name: '整行推广',
            kind: ProofreadingRuleKind.advertisement,
            source: ProofreadingRuleSource.user,
            bookId: 'book-a',
            target: ProofreadingRuleTarget.bodyLine,
            mode: ProofreadingMatchMode.literal,
            pattern: '广告',
            excludePattern: exclude,
            wholeLineOnly: whole,
            caseSensitive: false,
            action: ProofreadingRuleAction.advertisementCandidate,
            positiveExamples: const ['广告'],
            negativeExamples: const [],
          );

      expect(wholeLine().matchScanText('广告').map((match) => match.startUtf16), [
        0,
      ]);
      expect(
        wholeLine().matchScanText('  广告  ').map((match) => match.startUtf16),
        [2],
      );
      expect(wholeLine().matchScanText('广告正文'), isEmpty);
      expect(wholeLine().matchScanText('正文广告'), isEmpty);
      expect(wholeLine().matchScanText('正文广告正文'), isEmpty);
      expect(wholeLine().matchScanText('   '), isEmpty);
      // NBSP and ideographic space follow Dart's trim semantics.
      expect(
        wholeLine()
            .matchScanText('\u00a0广告\u3000')
            .map((match) => match.startUtf16),
        [1],
      );
      expect(
        wholeLine(exclude: '引用')
            .matchScanText('广告')
            .map((match) => match.startUtf16),
        [0],
      );
      expect(
        () => ProofreadingRule.create(
          id: 'paragraph-whole-line',
          name: '无效果',
          kind: ProofreadingRuleKind.advertisement,
          source: ProofreadingRuleSource.user,
          bookId: 'book-a',
          target: ProofreadingRuleTarget.paragraph,
          mode: ProofreadingMatchMode.literal,
          pattern: '广告',
          wholeLineOnly: true,
          caseSensitive: false,
          action: ProofreadingRuleAction.advertisementCandidate,
          positiveExamples: const ['广告'],
          negativeExamples: const [],
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        proofreadingRuleFingerprint(wholeLine()),
        isNot(proofreadingRuleFingerprint(wholeLine(whole: false))),
      );
    });
  });

  test('duplicate copies every field and turns built-ins into user rules', () {
    final original = ProofreadingRule.create(
      id: 'builtin',
      name: '内置规则',
      kind: ProofreadingRuleKind.advertisement,
      source: ProofreadingRuleSource.builtIn,
      bookId: 'book-a',
      target: ProofreadingRuleTarget.bodyLine,
      mode: ProofreadingMatchMode.literal,
      pattern: '推广',
      excludePattern: '引用',
      wholeLineOnly: true,
      caseSensitive: false,
      action: ProofreadingRuleAction.advertisementCandidate,
      positiveExamples: const <String>['推广'],
      negativeExamples: const <String>[],
      scope: ProofreadingRuleScope.global,
      globalScopeConfirmed: true,
      enabled: false,
      priority: 5,
    );
    final copy = original.duplicate(id: 'copy', name: '内置规则（副本）');
    expect(copy.id, 'copy');
    expect(copy.name, '内置规则（副本）');
    expect(copy.source, ProofreadingRuleSource.user);
    expect(copy.scope, ProofreadingRuleScope.global);
    expect(copy.pattern, '推广');
    expect(copy.excludePattern, '引用');
    expect(copy.wholeLineOnly, isTrue);
    expect(copy.enabled, isFalse);
    expect(copy.priority, 5);
  });
}
