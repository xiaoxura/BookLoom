import 'dart:convert';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/proofreading_quality.dart';

void main() {
  test('mapped title uses the full original UTF-16 heading span', () {
    final report = _evaluate(
      _corpus(
        original: '【😀归来】',
        title: '😀归来',
        pattern: r'【(😀归来)】',
        titleGroup: 1,
        titleRange: _range(1, 5),
      ),
    );
    _expectExact(report);
    expect(report.caseResults.single['scan_matches'], 1);
  });

  test('number capture composes a final title longer than its source span', () {
    final report = _evaluate(
      _corpus(
        original: '2夜',
        title: '第2章 夜',
        pattern: r'(2)(夜)',
        titleGroup: 2,
        numberGroup: 1,
        number: 2,
        titleRange: _range(1, 2),
        numberRange: _range(0, 1),
      ),
    );
    _expectExact(report);
    final wholePrefix = _evaluate(
      _corpus(
        original: '第2章 夜',
        title: '第2章 夜',
        pattern: '第2章 夜',
        number: 2,
        titleRange: _range(4, 5),
        numberRange: _range(1, 2),
      ),
    );
    _expectExact(wholePrefix);
  });

  test('mapped volume compiles an intro and reparents following chapters', () {
    final report = _evaluate(
      _corpus(
        original: '2夜',
        title: '第2卷 夜',
        pattern: r'(2)(夜)',
        titleGroup: 2,
        numberGroup: 1,
        number: 2,
        titleRange: _range(1, 2),
        numberRange: _range(0, 1),
        labelLevel: 1,
        ruleLevel: 1,
        following: true,
      ),
    );
    _expectExact(report);
  });

  test(
    'same span with wrong valid title, removal flag or level is FP and FN',
    () {
      final variants = [
        _corpus(
          original: '【夜】',
          title: '夜',
          pattern: r'(【夜】)',
          titleGroup: 1,
          titleRange: _range(1, 2),
        ),
        _corpus(removeTitleLine: false),
        _corpus(ruleLevel: 1),
      ];
      for (final value in variants) {
        final report = _evaluate(value);
        expect(report.summary['action_tp'], 0);
        expect(report.summary['action_fp'], 1);
        expect(report.summary['action_fn'], 1);
        expect(report.summary['invalid_cases'], 0);
        expect(report.summary['compile_blocked_cases'], 0);
        expect(report.summary['effective_mismatch_cases'], 1);
        expect(report.hasStrictFailure, isTrue);
      }
    },
  );

  test('optional label and rule fields reject invalid types and evidence', () {
    final invalidFields = <Map<String, Object?>>[
      {'heading_level': null},
      {'heading_level': 0},
      {'heading_level': 3},
      {'heading_level': '1'},
      {'heading_number': null},
      {'heading_number': 0},
      {'heading_number': -1},
      {'heading_number': 1000000000},
      {'heading_number': 2.0},
      {'heading_number': 2},
      {'title_evidence_range': null},
      {
        'title_evidence_range': {'start_utf16': 1},
      },
      {
        'title_evidence_range': {'start_utf16': 1, 'end_utf16': 2, 'extra': 0},
      },
      {'title_evidence_range': _range(-1, 2)},
      {'title_evidence_range': _range(1, 1)},
      {'title_evidence_range': _range(1, 99)},
      {'title_evidence_range': _range(2, 5)},
      {'number_evidence_range': null},
      {'number_evidence_range': _range(1, 2)},
      {
        'number_evidence_range': {'start_utf16': '0', 'end_utf16': 1},
      },
    ];
    for (final fields in invalidFields) {
      final value = _corpus(
        original: '【😀归来】',
        title: '【😀归来】',
        pattern: r'【😀归来】',
      );
      _label(value).addAll(fields);
      expect(
        () => QualityCorpus.decode(jsonEncode(value)),
        throwsFormatException,
        reason: '$fields',
      );
    }
    final nonSplit = _corpus();
    _label(nonSplit).addAll({
      'action': 'none',
      'acceptable_assessments': ['suspected_missing'],
      'title': '',
      'remove_title_line': false,
      'heading_level': 2,
    });
    expect(
      () => QualityCorpus.decode(jsonEncode(nonSplit)),
      throwsFormatException,
      reason: 'Non-split labels reject even explicit default heading metadata.',
    );
    for (final level in [null, 0, 3, '1', 1.0]) {
      final value = _corpus();
      _definition(value)['heading_level'] = level;
      expect(
        () => QualityCorpus.decode(jsonEncode(value)),
        throwsA(anyOf(isA<FormatException>(), isA<ValidationFailure>())),
        reason: 'rule level $level',
      );
    }
  });

  test('ordinary AI wire cannot inject mapping or heading-level fields', () {
    final corpus = QualityCorpus.decode(jsonEncode(_corpus()));
    final clean = QualityEvaluator.evaluateResponses(corpus, {
      'mapping': [jsonEncode(_response())],
    });
    _expectExact(clean);
    for (final field in <Map<String, Object?>>[
      {'heading_level': 1},
      {'heading_number': 2},
      {'title_evidence_range': _range(0, 3)},
      {'number_evidence_range': _range(1, 2)},
      {'title_source_range': _range(0, 3)},
      {'number_capture_group': 1},
    ]) {
      final response = _response();
      ((response['proposals'] as List).single as Map).addAll(field);
      final report = QualityEvaluator.evaluateResponses(corpus, {
        'mapping': [jsonEncode(response)],
      });
      expect(report.summary['invalid_cases'], 1, reason: '$field');
      expect(report.summary['action_tp'], 0);
      expect(report.summary['action_fn'], 1);
      expect(report.summary['effective_change_cases'], 0);
    }
  });
}

QualityReport _evaluate(Map<String, Object?> value) =>
    QualityEvaluator.evaluateRules(QualityCorpus.decode(jsonEncode(value)));

void _expectExact(QualityReport report) {
  expect(report.summary['action_tp'], 1);
  expect(report.summary['action_fp'], 0);
  expect(report.summary['action_fn'], 0);
  expect(report.summary['invalid_cases'], 0);
  expect(report.summary['compile_blocked_cases'], 0);
  expect(report.summary['effective_change_cases'], 1);
  expect(report.caseResults.single['expected_after_equal'], true);
  expect(report.hasStrictFailure, isFalse);
  expect(report.toJson()['realProviderQualityVerified'], false);
}

Map<String, Object?> _range(int start, int end) => {
  'start_utf16': start,
  'end_utf16': end,
};

Map<String, Object?> _label(Map<String, Object?> value) =>
    (((value['cases'] as List).single as Map)['labels'] as List).single
        as Map<String, Object?>;

Map<String, Object?> _definition(Map<String, Object?> value) =>
    ((value['rules'] as List).single as Map)['definition']
        as Map<String, Object?>;

Map<String, Object?> _corpus({
  String original = '第二章',
  String title = '第二章',
  String pattern = '第二章',
  int? titleGroup,
  int? numberGroup,
  int? number,
  Map<String, Object?>? titleRange,
  Map<String, Object?>? numberRange,
  int? labelLevel,
  int? ruleLevel,
  bool removeTitleLine = true,
  bool following = false,
}) {
  final suffix = '${removeTitleLine ? '' : '$original\r\n'}正文';
  final image = <String, Object?>{
    'id': 'image',
    'kind': 'image',
    'asset_id': 'asset',
    'caption': null,
    'alt': '',
  };
  Map<String, Object?> normalized(
    String title,
    List<Object> blocks, {
    int level = 2,
    int? parent,
    bool frontMatter = false,
  }) => {
    'title': title,
    'level': level,
    'parent_index': parent,
    'front_matter': frontMatter,
    'blocks': blocks,
  };
  return {
    'schema_version': 1,
    'provenance': {
      'kind': 'assistant_authored_synthetic',
      'contains_user_manuscripts': false,
      'human_reviewed': false,
      'notes':
          'Independent synthetic mapping regression; not the reference corpus.',
    },
    'rules': [
      {
        'id': 'mapping-rule',
        'definition': <String, Object?>{
          'schema_version': 1,
          'name': 'Synthetic mapping',
          'kind': 'chapter',
          'target': 'heading_line',
          'heading_level': ?ruleLevel,
          'match': {
            'mode': 'safe_regex',
            'pattern': pattern,
            'case_sensitive': true,
            'title_capture_group': ?titleGroup,
            'number_capture_group': ?numberGroup,
          },
          'action': 'chapter_candidate',
          'positive_examples': [original],
          'negative_examples': ['普通正文'],
          'reason': 'Synthetic exact mapping.',
        },
      },
    ],
    'cases': [
      {
        'id': 'mapping',
        'description': 'Synthetic mapping',
        'tags': ['synthetic'],
        'intent': 'missing_chapter',
        'chunk_characters': 16384,
        'rule_ids': ['mapping-rule'],
        'chapters': [
          {
            'id': 'chapter',
            'title': '原章',
            'level': 2,
            'parent_id': null,
            'front_matter': false,
            'blocks': [
              {
                'id': 'body',
                'kind': 'paragraph',
                'text': '前🙂\r\n$original\r\n正文',
              },
              image,
            ],
          },
          if (following)
            {
              'id': 'following',
              'title': '后续章',
              'level': 2,
              'parent_id': null,
              'front_matter': false,
              'blocks': [
                {'id': 'following-body', 'kind': 'paragraph', 'text': '后续正文'},
              ],
            },
        ],
        'labels': [
          <String, Object?>{
            'id': 'label',
            'chapter_id': 'chapter',
            'block_id': 'body',
            'start_utf16': '前🙂\r\n'.length,
            'end_utf16': '前🙂\r\n'.length + original.length,
            'original': original,
            'acceptable_assessments': ['missed_heading'],
            'action': 'split_chapter',
            'title': title,
            'remove_title_line': removeTitleLine,
            'reason': 'Synthetic mapping label.',
            'heading_level': ?labelLevel,
            'heading_number': ?number,
            'title_evidence_range': ?titleRange,
            'number_evidence_range': ?numberRange,
          },
        ],
        'expected_after': [
          normalized('原章', [
            {'kind': 'paragraph', 'text': '前🙂\r\n'},
          ]),
          if (labelLevel == 1) normalized(title, [], level: 1),
          normalized(
            labelLevel == 1 ? '' : title,
            [
              {'kind': 'paragraph', 'text': suffix},
              image,
            ],
            parent: labelLevel == 1 ? 1 : null,
            frontMatter: labelLevel == 1,
          ),
          if (following)
            normalized('后续章', [
              {'kind': 'paragraph', 'text': '后续正文'},
            ], parent: labelLevel == 1 ? 1 : null),
        ],
      },
    ],
  };
}

Map<String, Object?> _response() => {
  'schema_version': 1,
  'findings': [
    {
      'id': 'finding',
      'category': 'missing_chapter',
      'assessment': 'missed_heading',
      'chapter_id': 'chapter',
      'block_id': 'body',
      'original': '第二章',
      'before': '前🙂\r\n',
      'after': '\r\n正文',
      'reason': 'Synthetic independent heading.',
    },
  ],
  'proposals': [
    <String, Object?>{
      'id': 'proposal',
      'finding_id': 'finding',
      'action': 'split_chapter',
      'chapter_id': 'chapter',
      'block_id': 'body',
      'original': '第二章',
      'before': '前🙂\r\n',
      'after': '\r\n正文',
      'title': '第二章',
      'remove_title_line': true,
      'reason': 'Synthetic split.',
    },
  ],
  'rule_proposals': <Object>[],
};
