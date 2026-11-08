import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/proofreading_quality.dart';
import '../../tool/src/proofreading_quality_live.dart';

Map<String, dynamic> _root() => jsonDecode(
  File('test/fixtures/proofreading/quality-corpus.json').readAsStringSync(),
) as Map<String, dynamic>;

String _withProvenance(Map<String, Object?> changes) {
  final root = _root();
  final provenance = root['provenance'] as Map<String, dynamic>;
  provenance.addAll(changes);
  return jsonEncode(root);
}

void main() {
  test('the repository corpus stays unreviewed synthetic material', () {
    final corpus = QualityCorpus.decode(
      File('test/fixtures/proofreading/quality-corpus.json').readAsStringSync(),
    );

    expect(corpus.isExternal, isFalse);
    expect(corpus.containsUserManuscripts, isFalse);
    expect(corpus.humanReviewed, isFalse);
    expect(corpus.provenance['kind'], 'assistant_authored_synthetic');
    expect(corpus.provenance.containsKey('review'), isFalse);
  });

  test('external corpora require explicit consent to load', () {
    final raw = _withProvenance({
      'kind': 'external_unverified',
      'contains_user_manuscripts': true,
    });

    expect(() => QualityCorpus.decode(raw), throwsFormatException);
    final corpus = QualityCorpus.decode(raw, allowExternal: true);
    expect(corpus.isExternal, isTrue);
    expect(corpus.containsUserManuscripts, isTrue);
    expect(corpus.humanReviewed, isFalse);
  });

  test('a reviewed external corpus keeps auditable review evidence', () {
    final raw = _withProvenance({
      'kind': 'external_unverified',
      'contains_user_manuscripts': true,
      'human_reviewed': true,
      'review': {
        'reviewer': 'synthetic-reviewer',
        'reviewed_at': '2026-11-07',
        'scope': 'all_labels',
      },
    });
    final corpus = QualityCorpus.decode(raw, allowExternal: true);
    final report = QualityEvaluator.evaluateRules(corpus).toJson();

    expect(corpus.humanReviewed, isTrue);
    expect(corpus.provenance['review'], isA<Map<String, Object?>>());
    final provenance = report['provenance'] as Map<String, Object?>;
    expect(provenance['kind'], 'external_unverified');
    expect(provenance['human_reviewed'], isTrue);
    expect(
      (provenance['review'] as Map<String, Object?>)['scope'],
      'all_labels',
    );
    expect(report['realProviderQualityVerified'], isFalse);
  });

  test('invalid provenance and review evidence are rejected', () {
    final invalid = <String>[
      _withProvenance({'kind': 'unknown_kind'}),
      _withProvenance({'contains_user_manuscripts': true}),
      _withProvenance({'human_reviewed': true}),
      _withProvenance({
        'human_reviewed': true,
        'review': {
          'reviewer': '',
          'reviewed_at': '2026-11-07',
          'scope': 'all_labels',
        },
      }),
      _withProvenance({
        'human_reviewed': true,
        'review': {
          'reviewer': 'reviewer',
          'reviewed_at': '2026-13-40',
          'scope': 'all_labels',
        },
      }),
      _withProvenance({
        'human_reviewed': true,
        'review': {
          'reviewer': 'reviewer',
          'reviewed_at': '2026-1-1',
          'scope': 'all_labels',
        },
      }),
      _withProvenance({
        'human_reviewed': true,
        'review': {
          'reviewer': 'reviewer',
          'reviewed_at': '2026-11-07',
          'scope': 'some_labels',
        },
      }),
      _withProvenance({
        'human_reviewed': true,
        'review': {
          'reviewer': 'reviewer\u0001',
          'reviewed_at': '2026-11-07',
          'scope': 'all_labels',
        },
      }),
      _withProvenance({
        'human_reviewed': false,
        'review': {
          'reviewer': 'reviewer',
          'reviewed_at': '2026-11-07',
          'scope': 'all_labels',
        },
      }),
      _withProvenance({'contains_user_manuscripts': 'yes'}),
      _withProvenance({'human_reviewed': 'no'}),
    ];
    for (final raw in invalid) {
      expect(
        () => QualityCorpus.decode(raw, allowExternal: true),
        throwsFormatException,
        reason: raw.substring(raw.indexOf('"provenance"'), 0 + 120),
      );
    }
  });

  test('sending an external corpus needs the second explicit opt-in', () {
    QualityCliOptions.parse(
      [
        '--live',
        '--format=chat',
        '--base-url=http://127.0.0.1:1',
        '--model=m',
        '--key-env=TEST_KEY',
      ],
      const {'TEST_KEY': 'sk-secret'},
    );
    final external = QualityCorpus.decode(
      _withProvenance({
        'kind': 'external_unverified',
        'contains_user_manuscripts': true,
      }),
      allowExternal: true,
    );
    final synthetic = QualityCorpus.decode(
      File('test/fixtures/proofreading/quality-corpus.json').readAsStringSync(),
    );

    expect(
      () => validateLiveCorpusConsent(external, sendExternal: false),
      throwsFormatException,
    );
    validateLiveCorpusConsent(external, sendExternal: true);
    expect(
      () => validateLiveCorpusConsent(synthetic, sendExternal: true),
      throwsFormatException,
    );
    validateLiveCorpusConsent(synthetic, sendExternal: false);
  });

  test('CLI corpus flags require their companions', () {
    final options = QualityCliOptions.parse([
      '--corpus=other.json',
      '--allow-external',
      '--strict',
    ], const {});
    expect(options.corpusPath, 'other.json');
    expect(options.allowExternal, isTrue);
    expect(options.sendExternal, isFalse);
    expect(options.strict, isTrue);

    final sending = QualityCliOptions.parse(
      [
        '--live',
        '--format=chat',
        '--base-url=http://127.0.0.1:1',
        '--model=m',
        '--key-env=TEST_KEY',
        '--corpus=other.json',
        '--allow-external',
        '--send-external',
      ],
      const {'TEST_KEY': 'sk-secret'},
    );
    expect(sending.live, isNotNull);
    expect(sending.sendExternal, isTrue);
    expect(sending.allowExternal, isTrue);

    for (final arguments in <List<String>>[
      ['--allow-external'],
      ['--send-external'],
      ['--corpus=other.json', '--send-external'],
      ['--corpus='],
    ]) {
      expect(
        () => QualityCliOptions.parse(arguments, const {}),
        throwsFormatException,
        reason: '$arguments',
      );
    }
  });

  test('an external corpus evaluates with its own provenance', () {
    final corpus = QualityCorpus.decode(
      _withProvenance({
        'kind': 'external_unverified',
        'contains_user_manuscripts': true,
        'human_reviewed': true,
        'review': {
          'reviewer': 'synthetic-reviewer',
          'reviewed_at': '2026-11-07',
          'scope': 'all_labels',
        },
      }),
      allowExternal: true,
    );

    final report = QualityEvaluator.evaluateRules(corpus);
    expect(report.summary['case_count'], corpus.cases.length);
    expect(
      report.toJson()['provenance'],
      isNot(containsPair('kind', 'assistant_authored_synthetic')),
    );
    expect(report.toJson()['realProviderQualityVerified'], isFalse);
  });
}
