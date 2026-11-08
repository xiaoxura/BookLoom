import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/proofreading_quality.dart';

void main() {
  test(
    'counts exact deletion, protected false positive, and empty response FN',
    () {
      final corpus = QualityCorpus.decode(
        jsonEncode({
          'schema_version': 1,
          'provenance': {
            'kind': 'assistant_authored_synthetic',
            'contains_user_manuscripts': false,
            'human_reviewed': false,
            'notes': 'Small synthetic metric fixture.',
          },
          'rules': [_rule()],
          'cases': [
            _case('positive', '广告', 'delete_text', '广告', ''),
            _case('protected', '广告', 'none', '广告', '广告'),
          ],
        }),
      );

      final rules = QualityEvaluator.evaluateRules(corpus);
      expect(rules.summary['action_tp'], 1);
      expect(rules.summary['action_fp'], 1);
      expect(rules.summary['action_fn'], 0);
      expect(rules.summary['protected_false_positives'], 1);
      expect(rules.summary['effective_cases'], 1);
      expect(rules.summary['effective_change_cases'], 1);
      expect(rules.caseResults.last['expected_after_equal'], false);
      expect(rules.toJson()['realProviderQualityVerified'], false);

      final empty = QualityEvaluator.evaluateResponses(corpus, {
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
      });
      expect(empty.summary['action_tp'], 0);
      expect(empty.summary['action_fn'], 1);
      expect(empty.summary['classification_fn'], 2);
      expect(empty.caseResults.first['false_negative_label_ids'], [
        'label-positive',
      ]);
      expect(empty.summary['action_precision'], isNull);
      expect(empty.summary['classification_precision'], isNull);
      expect(empty.summary['effective_change_cases'], 0);
    },
  );

  test('replay decodes and compiles exact action, rejects missing cases', () {
    final corpus = QualityCorpus.decode(
      jsonEncode({
        'schema_version': 1,
        'provenance': {
          'kind': 'assistant_authored_synthetic',
          'contains_user_manuscripts': false,
          'human_reviewed': false,
          'notes': 'Small synthetic metric fixture.',
        },
        'rules': [_rule()],
        'cases': [_case('positive', '广告', 'delete_text', '广告', '')],
      }),
    );
    final response = jsonEncode({
      'schema_version': 1,
      'findings': [
        {
          'id': 'finding',
          'category': 'advertisement',
          'assessment': 'advertisement',
          'chapter_id': 'chapter',
          'block_id': 'body',
          'original': '广告',
          'before': '',
          'after': '',
          'reason': 'Synthetic exact span.',
        },
      ],
      'proposals': [
        {
          'id': 'proposal',
          'finding_id': 'finding',
          'action': 'delete_text',
          'chapter_id': 'chapter',
          'block_id': 'body',
          'original': '广告',
          'before': '',
          'after': '',
          'replacement': '',
          'reason': 'Synthetic exact deletion.',
        },
      ],
      'rule_proposals': <Object>[],
    });
    final report = QualityEvaluator.evaluateResponses(corpus, {
      'positive': [response],
    });
    expect(report.summary['action_tp'], 1);
    expect(report.summary['classification_tp'], 1);
    expect(report.summary['effective_change_cases'], 1);
    expect(report.hasStrictFailure, false);
    expect(
      () => QualityEvaluator.evaluateResponses(corpus, {}),
      throwsFormatException,
    );
    expect(
      () => QualityEvaluator.evaluateResponses(corpus, {'positive': []}),
      throwsFormatException,
    );
  });

  test('remove_block replay removes only the text block', () {
    final corpus = _removalCorpus();
    expect(corpus.cases.single.plan.chunks, hasLength(1));

    final report = QualityEvaluator.evaluateResponses(corpus, {
      'remove': [_removalResponse('remove_block')],
    });
    expect(report.summary['action_tp'], 1);
    expect(report.summary['action_fp'], 0);
    expect(report.summary['action_fn'], 0);
    expect(report.summary['classification_tp'], 1);
    expect(report.summary['invalid_cases'], 0);
    expect(report.summary['compile_blocked_cases'], 0);
    expect(report.summary['effective_change_cases'], 1);
    expect(report.caseResults.single['expected_after_equal'], true);
    expect(report.hasStrictFailure, false);
    expect(report.toJson()['realProviderQualityVerified'], false);
  });

  test('delete_text cannot satisfy remove_block label or expected result', () {
    final report = QualityEvaluator.evaluateResponses(_removalCorpus(), {
      'remove': [_removalResponse('delete_text')],
    });
    expect(report.summary['action_tp'], 0);
    expect(report.summary['action_fp'], 1);
    expect(report.summary['action_fn'], 1);
    expect(report.summary['classification_tp'], 1);
    expect(report.summary['compile_blocked_cases'], 0);
    expect(report.caseResults.single['false_negative_label_ids'], [
      'label-remove',
    ]);
    expect(report.caseResults.single['expected_after_equal'], false);
  });

  test('replace_text stays outside response replay action scope', () {
    final response =
        jsonDecode(_removalResponse('replace_text')) as Map<String, dynamic>;
    (response['proposals'] as List).single['replacement'] = '改';
    final report = QualityEvaluator.evaluateResponses(_removalCorpus(), {
      'remove': [jsonEncode(response)],
    });
    expect(report.summary['invalid_cases'], 0);
    expect(report.summary['compile_blocked_cases'], 1);
    expect(report.summary['action_tp'], 0);
    expect(report.summary['action_fp'], 1);
    expect(report.summary['action_fn'], 1);
    expect(report.caseResults.single['expected_after_equal'], false);
  });

  test('rename_chapter changes only the directory title', () {
    final corpus = _renameCorpus();
    final report = QualityEvaluator.evaluateResponses(corpus, {
      'rename': [_renameResponse()],
    });
    expect(report.summary['action_tp'], 1);
    expect(report.summary['action_fp'], 0);
    expect(report.summary['action_fn'], 0);
    expect(report.summary['classification_tp'], 1);
    expect(report.summary['invalid_cases'], 0);
    expect(report.summary['compile_blocked_cases'], 0);
    expect(report.summary['effective_change_cases'], 1);
    expect(report.caseResults.single['expected_after_equal'], true);
    expect(report.hasStrictFailure, false);
    expect(report.toJson()['realProviderQualityVerified'], false);
    expect(corpus.cases.single.source.chapters.single.title, '错误目录名');
    expect(corpus.cases.single.source.chapters.single.blocks, hasLength(6));
  });

  test('body replacement cannot count as a chapter title correction', () {
    final response = jsonDecode(_renameResponse()) as Map<String, dynamic>;
    final proposal =
        (response['proposals'] as List).single as Map<String, dynamic>;
    proposal['action'] = 'replace_text';
    proposal['replacement'] = '其他正文';
    proposal.remove('original_title');
    final report = QualityEvaluator.evaluateResponses(_renameCorpus(), {
      'rename': [jsonEncode(response)],
    });
    expect(report.summary['action_tp'], 0);
    expect(report.summary['action_fn'], 1);
    expect(report.summary['invalid_cases'], 1);
    expect(report.caseResults.single['expected_after_equal'], false);
  });

  test('missing rename and protected rename report FN and FP', () {
    final empty = QualityEvaluator.evaluateResponses(_renameCorpus(), {
      'rename': [
        jsonEncode({
          'schema_version': 1,
          'findings': <Object>[],
          'proposals': <Object>[],
          'rule_proposals': <Object>[],
        }),
      ],
    });
    expect(empty.summary['action_fn'], 1);
    expect(empty.summary['classification_fn'], 1);
    expect(empty.summary['effective_change_cases'], 0);

    final protected = _renameCorpusValue();
    final qualityCase =
        (protected['cases'] as List).single as Map<String, Object?>;
    final label =
        (qualityCase['labels'] as List).single as Map<String, Object?>;
    label['action'] = 'none';
    label['title'] = '';
    label['acceptable_assessments'] = ['suspected_missing'];
    final expected =
        (qualityCase['expected_after'] as List).single as Map<String, Object?>;
    expected['title'] = '错误目录名';
    final report = QualityEvaluator.evaluateResponses(
      QualityCorpus.decode(jsonEncode(protected)),
      {
        'rename': [_renameResponse()],
      },
    );
    expect(report.summary['action_tp'], 0);
    expect(report.summary['action_fp'], 1);
    expect(report.summary['protected_false_positives'], 1);
    expect(report.summary['classification_fp'], 1);
    expect(report.summary['classification_fn'], 1);
    expect(report.caseResults.single['expected_after_equal'], false);
  });

  test('rename label requires the complete first heading and exact title', () {
    void reject(
      void Function(Map<String, Object?>, Map<String, Object?>) edit,
    ) {
      final raw = _renameCorpusValue();
      final qualityCase = (raw['cases'] as List).single as Map<String, Object?>;
      final label =
          (qualityCase['labels'] as List).single as Map<String, Object?>;
      edit(qualityCase, label);
      expect(
        () => QualityCorpus.decode(jsonEncode(raw)),
        throwsFormatException,
      );
    }

    reject((qualityCase, label) => qualityCase['intent'] = 'advertisement');
    reject(
      (qualityCase, label) =>
          label['acceptable_assessments'] = ['suspected_missing'],
    );
    reject((qualityCase, label) => label['title'] = '错误标题');
    reject((qualityCase, label) {
      final chapter = (qualityCase['chapters'] as List).single as Map;
      final body = (chapter['blocks'] as List)[1] as Map;
      body['text'] = ' \r\n  第2章\u2028新标题  \r\n正文仍在';
      label['original'] = '第2章\u2028新标题';
      label['title'] = '第2章\u2028新标题';
      label['end_utf16'] =
          (label['start_utf16'] as int) + '第2章\u2028新标题'.length;
    });
    reject((qualityCase, label) => label['remove_title_line'] = true);
    reject(
      (qualityCase, label) =>
          label['end_utf16'] = (label['end_utf16'] as int) - 1,
    );
    reject(
      (qualityCase, label) =>
          (qualityCase['chapters'] as List).single['title'] = '第2章 新标题',
    );
    reject((qualityCase, label) => label['block_id'] = 'tail');
    reject((qualityCase, label) {
      final chapter = (qualityCase['chapters'] as List).single as Map;
      final body = (chapter['blocks'] as List)[1] as Map;
      body['text'] = '正文起始\r\n  第2章 新标题  \r\n正文仍在';
      final start = (body['text'] as String).indexOf('第2章 新标题');
      label['start_utf16'] = start;
      label['end_utf16'] = start + '第2章 新标题'.length;
    });
    reject((qualityCase, label) {
      qualityCase['chunk_characters'] = 512;
      final chapter = (qualityCase['chapters'] as List).single as Map;
      final body = (chapter['blocks'] as List)[1] as Map;
      body['text'] = '${' ' * 600}第2章 新标题\n正文仍在';
      label['start_utf16'] = 600;
      label['end_utf16'] = 600 + '第2章 新标题'.length;
    });
  });

  test('rename replay rejects a stale old title or invented new title', () {
    for (final field in ['original_title', 'replacement']) {
      final response = jsonDecode(_renameResponse()) as Map<String, dynamic>;
      final proposal =
          (response['proposals'] as List).single as Map<String, dynamic>;
      proposal[field] = field == 'original_title' ? '过期目录' : '第三章 新标题';
      final report = QualityEvaluator.evaluateResponses(_renameCorpus(), {
        'rename': [jsonEncode(response)],
      });
      expect(report.summary['action_tp'], 0);
      expect(report.summary['action_fn'], 1);
      expect(report.summary['invalid_cases'], 1);
      expect(report.caseResults.single['expected_after_equal'], false);
    }
  });

  test('remove_block requires a whole advertisement block', () {
    final partial = _removalCorpusValue();
    final partialCase =
        (partial['cases'] as List).single as Map<String, Object?>;
    final partialLabel =
        (partialCase['labels'] as List).single as Map<String, Object?>;
    partialLabel['end_utf16'] = 1;
    partialLabel['original'] = '广';
    expect(
      () => QualityCorpus.decode(jsonEncode(partial)),
      throwsFormatException,
    );

    final wrongAssessment = _removalCorpusValue();
    final wrongLabel =
        (((wrongAssessment['cases'] as List).single
                        as Map<String, Object?>)['labels']
                    as List)
                .single
            as Map<String, Object?>;
    wrongLabel['acceptable_assessments'] = ['advertisement', 'undetermined'];
    expect(
      () => QualityCorpus.decode(jsonEncode(wrongAssessment)),
      throwsFormatException,
    );

    for (final field in ['title', 'remove_title_line']) {
      final withSplitField = _removalCorpusValue();
      final label =
          (((withSplitField['cases'] as List).single
                          as Map<String, Object?>)['labels']
                      as List)
                  .single
              as Map<String, Object?>;
      label[field] = field == 'title' ? 'Title' : true;
      expect(
        () => QualityCorpus.decode(jsonEncode(withSplitField)),
        throwsFormatException,
      );
    }

    final response =
        jsonDecode(_removalResponse('remove_block')) as Map<String, dynamic>;
    (response['findings'] as List).single['original'] = '广';
    (response['findings'] as List).single['after'] = '告';
    (response['proposals'] as List).single['original'] = '广';
    (response['proposals'] as List).single['after'] = '告';
    final report = QualityEvaluator.evaluateResponses(_removalCorpus(), {
      'remove': [jsonEncode(response)],
    });
    expect(report.summary['invalid_cases'], 1);
    expect(report.summary['action_tp'], 0);
    expect(report.summary['action_fn'], 1);
    expect(report.caseResults.single['expected_after_equal'], false);
  });

  test('empty response misses remove_block label', () {
    final report = QualityEvaluator.evaluateResponses(_removalCorpus(), {
      'remove': [
        jsonEncode({
          'schema_version': 1,
          'findings': <Object>[],
          'proposals': <Object>[],
          'rule_proposals': <Object>[],
        }),
      ],
    });
    expect(report.summary['action_tp'], 0);
    expect(report.summary['action_fn'], 1);
    expect(report.summary['classification_fn'], 1);
    expect(report.summary['effective_change_cases'], 0);
    expect(report.caseResults.single['expected_after_equal'], false);
  });

  test('invalid label offset and overlap cannot inflate metrics', () {
    final base = {
      'schema_version': 1,
      'provenance': {
        'kind': 'assistant_authored_synthetic',
        'contains_user_manuscripts': false,
        'human_reviewed': false,
        'notes': 'Small synthetic metric fixture.',
      },
      'rules': [_rule()],
      'cases': [_case('positive', '😀广告', 'delete_text', '广告', '😀')],
    };
    final item = ((base['cases'] as List).single as Map<String, Object?>);
    final label = (item['labels'] as List).single as Map<String, Object?>;
    label['start_utf16'] = 1;
    label['end_utf16'] = 3;
    expect(() => QualityCorpus.decode(jsonEncode(base)), throwsFormatException);

    label['start_utf16'] = 2;
    label['end_utf16'] = 4;
    (item['labels'] as List).add(<String, Object?>{...label, 'id': 'overlap'});
    expect(() => QualityCorpus.decode(jsonEncode(base)), throwsFormatException);
  });

  test('batch and corpus reject duplicate JSON keys', () {
    expect(
      () => QualityResponseBatch.decode(
        '{"schema_version":1,"schema_version":1,'
        '"origin":"synthetic_reference","cases":{}}',
      ),
      throwsFormatException,
    );
    expect(
      () => QualityResponseBatch.decode(
        '{"schema_version":1,"origin":"external_unverified",'
        '"cases":{"case":[],"case":[]}}',
      ),
      throwsFormatException,
    );
    expect(
      () => QualityResponseBatch.decode(
        r'{"schema_version":1,"origin":"external_unverified",'
        r'"cases":{"case":[],"\u0063ase":[]}}',
      ),
      throwsFormatException,
    );
    final batch = QualityResponseBatch.decode(
      '{"schema_version":1,"origin":"synthetic_reference",'
      '"cases":{"case":["{}"]}}',
    );
    expect(batch.origin, 'synthetic_reference');
    expect(batch.responsesByCase['case'], ['{}']);
    expect(
      () => QualityCorpus.decode(
        '{"schema_version":1,"schema_version":1, "provenance":{},'
        '"rules":[],"cases":[]}',
      ),
      throwsFormatException,
    );
  });

  test('rejects a split label inside a prose line', () {
    final item = _case('inline', '正文第2章后续', 'none', '第2章', '正文第2章后续');
    item['intent'] = 'missing_chapter';
    item['rule_ids'] = <String>[];
    final label = ((item['labels'] as List).single as Map<String, Object?>);
    label['action'] = 'split_chapter';
    label['acceptable_assessments'] = ['missed_heading'];
    label['title'] = '第2章';
    label['remove_title_line'] = true;
    expect(
      () => QualityCorpus.decode(
        jsonEncode({
          'schema_version': 1,
          'provenance': {
            'kind': 'assistant_authored_synthetic',
            'contains_user_manuscripts': false,
            'human_reviewed': false,
            'notes': 'Synthetic.',
          },
          'rules': <Object>[],
          'cases': [item],
        }),
      ),
      throwsFormatException,
    );
  });
}

QualityCorpus _removalCorpus() =>
    QualityCorpus.decode(jsonEncode(_removalCorpusValue()));

QualityCorpus _renameCorpus() =>
    QualityCorpus.decode(jsonEncode(_renameCorpusValue()));

Map<String, Object?> _renameCorpusValue() {
  const heading = '第2章 新标题';
  const body = ' \r\n  第2章 新标题  \r\n正文仍在';
  final start = body.indexOf(heading);
  final blocks = <Map<String, Object?>>[
    {'id': 'empty', 'kind': 'paragraph', 'text': '  '},
    {'id': 'body', 'kind': 'paragraph', 'text': body},
    {'id': 'tail', 'kind': 'paragraph', 'text': '后续正文'},
    {
      'id': 'image',
      'kind': 'image',
      'asset_id': 'asset-1',
      'caption': '插图',
      'alt': '图示',
    },
    {'id': 'footnote', 'kind': 'footnote', 'text': '注释', 'marker': '*'},
    {'id': 'divider', 'kind': 'divider'},
  ];
  return {
    'schema_version': 1,
    'provenance': {
      'kind': 'assistant_authored_synthetic',
      'contains_user_manuscripts': false,
      'human_reviewed': false,
      'notes': 'Synthetic chapter title correction.',
    },
    'rules': <Object>[],
    'cases': [
      {
        'id': 'rename',
        'description': 'Correct a directory title using body heading evidence.',
        'tags': ['synthetic'],
        'intent': 'missing_chapter',
        'chunk_characters': 16384,
        'rule_ids': <String>[],
        'chapters': [
          {
            'id': 'chapter',
            'title': '错误目录名',
            'level': 2,
            'parent_id': null,
            'front_matter': false,
            'blocks': blocks,
          },
        ],
        'labels': [
          {
            'id': 'label-rename',
            'chapter_id': 'chapter',
            'block_id': 'body',
            'start_utf16': start,
            'end_utf16': start + heading.length,
            'original': heading,
            'acceptable_assessments': ['missed_heading'],
            'action': 'rename_chapter',
            'title': heading,
            'remove_title_line': false,
            'reason': 'The body heading corrects the directory title.',
          },
        ],
        'expected_after': [
          {
            'title': heading,
            'level': 2,
            'parent_index': null,
            'front_matter': false,
            'blocks': [
              for (final block in blocks)
                if (block['kind'] != 'paragraph')
                  block
                else
                  {'kind': 'paragraph', 'text': block['text']},
            ],
          },
        ],
      },
    ],
  };
}

String _renameResponse() => jsonEncode({
  'schema_version': 1,
  'findings': [
    {
      'id': 'finding',
      'category': 'missing_chapter',
      'assessment': 'missed_heading',
      'chapter_id': 'chapter',
      'block_id': 'body',
      'original': '第2章 新标题',
      'before': '  ',
      'after': '  \r\n',
      'reason': 'Independent heading at the start of the first text block.',
    },
  ],
  'proposals': [
    {
      'id': 'proposal',
      'finding_id': 'finding',
      'action': 'rename_chapter',
      'chapter_id': 'chapter',
      'block_id': 'body',
      'original': '第2章 新标题',
      'before': '  ',
      'after': '  \r\n',
      'replacement': '第2章 新标题',
      'original_title': '错误目录名',
      'reason': 'Correct the directory title and retain body text.',
    },
  ],
  'rule_proposals': <Object>[],
});

Map<String, Object?> _removalCorpusValue() {
  final item = _case('remove', '广告', 'remove_block', '广告', '');
  item['rule_ids'] = <String>[];
  final chapters = item['chapters'] as List<Map<String, Object?>>;
  final body = chapters.single;
  body['parent_id'] = 'volume';
  body['blocks'] = [
    ...(body['blocks'] as List),
    {
      'id': 'cover',
      'kind': 'image',
      'asset_id': 'cover-asset',
      'caption': null,
      'alt': 'Cover',
    },
  ];
  chapters.insert(0, {
    'id': 'volume',
    'title': 'Volume',
    'level': 1,
    'parent_id': null,
    'front_matter': false,
    'blocks': <Object>[],
  });
  chapters.add({
    'id': 'second',
    'title': 'Second',
    'level': 2,
    'parent_id': 'volume',
    'front_matter': false,
    'blocks': [
      {'id': 'kept', 'kind': 'paragraph', 'text': '正文'},
    ],
  });

  final expected = item['expected_after'] as List<Map<String, Object?>>;
  final first = expected.single;
  first['parent_index'] = 0;
  first['blocks'] = [
    {
      'id': 'cover',
      'kind': 'image',
      'asset_id': 'cover-asset',
      'caption': null,
      'alt': 'Cover',
    },
  ];
  expected.insert(0, {
    'title': 'Volume',
    'level': 1,
    'parent_index': null,
    'front_matter': false,
    'blocks': <Object>[],
  });
  expected.add({
    'title': 'Second',
    'level': 2,
    'parent_index': 0,
    'front_matter': false,
    'blocks': [
      {'kind': 'paragraph', 'text': '正文'},
    ],
  });
  return {
    'schema_version': 1,
    'provenance': {
      'kind': 'assistant_authored_synthetic',
      'contains_user_manuscripts': false,
      'human_reviewed': false,
      'notes': 'Small synthetic block removal fixture.',
    },
    'rules': <Object>[],
    'cases': [item],
  };
}

String _removalResponse(String action) => jsonEncode({
  'schema_version': 1,
  'findings': [
    {
      'id': 'finding',
      'category': 'advertisement',
      'assessment': 'advertisement',
      'chapter_id': 'chapter',
      'block_id': 'body',
      'original': '广告',
      'before': '',
      'after': '',
      'reason': 'Synthetic full block.',
    },
  ],
  'proposals': [
    {
      'id': 'proposal',
      'finding_id': 'finding',
      'action': action,
      'chapter_id': 'chapter',
      'block_id': 'body',
      'original': '广告',
      'before': '',
      'after': '',
      'replacement': '',
      'reason': 'Synthetic full block action.',
    },
  ],
  'rule_proposals': <Object>[],
});

Map<String, Object?> _rule() => {
  'id': 'delete-ad',
  'definition': {
    'schema_version': 1,
    'name': 'Synthetic deletion',
    'kind': 'advertisement',
    'target': 'paragraph',
    'match': {'mode': 'literal', 'pattern': '广告', 'case_sensitive': true},
    'action': 'exact_deletion',
    'positive_examples': ['广告'],
    'negative_examples': ['正文'],
    'reason': 'Synthetic fixture rule.',
  },
};

Map<String, Object?> _case(
  String id,
  String text,
  String action,
  String original,
  String after,
) {
  final start = text.indexOf(original);
  return {
    'id': id,
    'description': 'Synthetic $id',
    'tags': ['synthetic'],
    'intent': 'advertisement',
    'chunk_characters': 16384,
    'rule_ids': ['delete-ad'],
    'chapters': [
      {
        'id': 'chapter',
        'title': 'First',
        'level': 2,
        'parent_id': null,
        'front_matter': false,
        'blocks': [
          {'id': 'body', 'kind': 'paragraph', 'text': text},
        ],
      },
    ],
    'labels': <Map<String, Object?>>[
      {
        'id': 'label-$id',
        'chapter_id': 'chapter',
        'block_id': 'body',
        'start_utf16': start,
        'end_utf16': start + original.length,
        'original': original,
        'acceptable_assessments': [
          action == 'none' ? 'not_advertisement' : 'advertisement',
        ],
        'action': action,
        'title': '',
        'remove_title_line': false,
        'reason': 'Synthetic label.',
      },
    ],
    'expected_after': [
      {
        'title': 'First',
        'level': 2,
        'parent_index': null,
        'front_matter': false,
        'blocks': [
          {'kind': 'paragraph', 'text': after},
        ],
      },
    ],
  };
}
