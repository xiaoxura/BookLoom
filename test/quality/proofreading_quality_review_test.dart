import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/proofreading_quality.dart';
import '../../tool/src/proofreading_quality_review.dart';

String _repoCorpus() =>
    File('test/fixtures/proofreading/quality-corpus.json').readAsStringSync();

Map<String, dynamic> _template(String corpusRaw) =>
    jsonDecode(exportReviewTemplate(corpusRaw)) as Map<String, dynamic>;

String _approved(
  Map<String, dynamic> template, {
  String reviewer = 'synthetic-reviewer',
  String reviewedAt = '2026-11-07',
}) {
  template['reviewer'] = reviewer;
  template['reviewed_at'] = reviewedAt;
  for (final label in template['labels'] as List) {
    (label as Map<String, dynamic>)['decision'] = 'approved';
  }
  return jsonEncode(template);
}

void main() {
  test('the template names every label and binds the corpus digest', () {
    final corpusRaw = _repoCorpus();
    final template = _template(corpusRaw);
    final corpus = QualityCorpus.decode(corpusRaw);

    expect(template['schema_version'], 1);
    expect(template['corpus_sha256'], qualityCorpusDigest(corpusRaw));
    expect(template['reviewer'], '');
    expect(template['reviewed_at'], '');
    final labels = template['labels'] as List;
    expect(labels, hasLength(30));
    expect(labels.map((label) => (label as Map)['decision']).toSet(), {
      'pending',
    });
    expect(
      labels.map((label) => '${label['case_id']}/${label['label_id']}').toSet(),
      {
        for (final qualityCase in corpus.cases)
          for (final label in qualityCase.labels)
            '${qualityCase.id}/${label.id}',
      },
    );
  });

  test('finalizing all approvals stamps review evidence', () {
    final corpusRaw = _repoCorpus();
    final reviewRaw = _approved(_template(corpusRaw));

    final reviewedRaw = finalizeReviewedCorpus(corpusRaw, reviewRaw);
    final reviewed = QualityCorpus.decode(reviewedRaw);

    expect(reviewed.humanReviewed, isTrue);
    expect(reviewed.isExternal, isFalse);
    expect(reviewed.cases, hasLength(28));
    expect(reviewed.cases.expand((item) => item.labels), hasLength(30));
    final review = reviewed.provenance['review'] as Map<String, Object?>;
    expect(review['reviewer'], 'synthetic-reviewer');
    expect(review['reviewed_at'], '2026-11-07');
    expect(review['scope'], 'all_labels');
    expect(review['approved_labels'], 30);
    expect(
      review['review_file_sha256'],
      sha256.convert(utf8.encode(reviewRaw)).toString(),
    );
    expect(reviewed.provenance['kind'], 'assistant_authored_synthetic');
    expect(reviewedRaw, isNot(corpusRaw));
    expect(QualityCorpus.decode(corpusRaw).humanReviewed, isFalse);
    final report = QualityEvaluator.evaluateRules(reviewed).toJson();
    expect(
      (report['provenance'] as Map<String, Object?>)['human_reviewed'],
      isTrue,
    );
    expect(report['realProviderQualityVerified'], isFalse);
  });

  test('finalizing requires the exact reviewed corpus bytes', () {
    final corpusRaw = _repoCorpus();
    final reviewRaw = _approved(_template(corpusRaw));
    final editedCorpus = corpusRaw.replaceFirst('完全原创合成场景', '完全原创合成场景（修订）');

    expect(editedCorpus, isNot(corpusRaw));
    expect(QualityCorpus.decode(editedCorpus).humanReviewed, isFalse);
    expect(
      () => finalizeReviewedCorpus(editedCorpus, reviewRaw),
      throwsA(isA<QualityReviewError>()),
    );
  });

  test('incomplete, unknown or duplicate decisions are rejected', () {
    final corpusRaw = _repoCorpus();
    final base = _template(corpusRaw);

    Map<String, dynamic> copy() =>
        jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    void approveAll(Map<String, dynamic> value) {
      value['reviewer'] = 'r';
      value['reviewed_at'] = '2026-11-07';
      for (final label in value['labels'] as List) {
        (label as Map<String, dynamic>)['decision'] = 'approved';
      }
    }

    final missing = copy();
    approveAll(missing);
    (missing['labels'] as List).removeLast();
    expect(
      () => finalizeReviewedCorpus(corpusRaw, jsonEncode(missing)),
      throwsA(isA<QualityReviewError>()),
    );

    final duplicate = copy();
    approveAll(duplicate);
    final labels = duplicate['labels'] as List;
    labels.add(jsonDecode(jsonEncode(labels.first)));
    expect(
      () => finalizeReviewedCorpus(corpusRaw, jsonEncode(duplicate)),
      throwsA(isA<QualityReviewError>()),
    );

    final unknown = copy();
    approveAll(unknown);
    ((unknown['labels'] as List).first as Map)['label_id'] = 'unknown';
    expect(
      () => finalizeReviewedCorpus(corpusRaw, jsonEncode(unknown)),
      throwsA(isA<QualityReviewError>()),
    );

    final wrongOriginal = copy();
    approveAll(wrongOriginal);
    ((wrongOriginal['labels'] as List).first as Map)['original'] = 'changed';
    expect(
      () => finalizeReviewedCorpus(corpusRaw, jsonEncode(wrongOriginal)),
      throwsA(isA<QualityReviewError>()),
    );

    for (final decision in ['pending', 'challenged']) {
      final partial = copy();
      approveAll(partial);
      ((partial['labels'] as List).last as Map)['decision'] = decision;
      expect(
        () => finalizeReviewedCorpus(corpusRaw, jsonEncode(partial)),
        throwsA(isA<QualityReviewError>()),
        reason: decision,
      );
    }
  });

  test('review metadata, schema and strict JSON are validated', () {
    final corpusRaw = _repoCorpus();
    final base = _template(corpusRaw);
    String review(Map<String, dynamic> value) => jsonEncode(value);

    for (final pair in <(String, String)>[
      ('', '2026-11-07'),
      (' reviewer ', '2026-11-07'),
      ('reviewer\u0001', '2026-11-07'),
      ('reviewer', '2026-1-1'),
      ('reviewer', '2026-13-40'),
    ]) {
      final value = jsonDecode(review(base)) as Map<String, dynamic>;
      value['reviewer'] = pair.$1;
      value['reviewed_at'] = pair.$2;
      for (final label in value['labels'] as List) {
        (label as Map<String, dynamic>)['decision'] = 'approved';
      }
      expect(
        () => finalizeReviewedCorpus(corpusRaw, review(value)),
        throwsA(isA<QualityReviewError>()),
        reason: '$pair',
      );
    }

    final extra = _template(corpusRaw)..['extra'] = 1;
    expect(
      () => finalizeReviewedCorpus(corpusRaw, review(extra)),
      throwsA(isA<QualityReviewError>()),
    );
    final badDecision = _template(corpusRaw);
    ((badDecision['labels'] as List).first as Map)['decision'] = 'maybe';
    expect(
      () => finalizeReviewedCorpus(corpusRaw, review(badDecision)),
      throwsA(isA<QualityReviewError>()),
    );
    expect(
      () => finalizeReviewedCorpus(
        corpusRaw,
        '{"schema_version":1,"schema_version":1}',
      ),
      throwsA(isA<QualityReviewError>()),
    );
    expect(
      () => finalizeReviewedCorpus(corpusRaw, 'not json'),
      throwsA(isA<QualityReviewError>()),
    );
  });

  test('external corpora require consent for template and finalize', () {
    final externalRaw = _repoCorpus()
        .replaceFirst(
          '"kind": "assistant_authored_synthetic"',
          '"kind": "external_unverified"',
        )
        .replaceFirst(
          '"contains_user_manuscripts": false',
          '"contains_user_manuscripts": true',
        );

    expect(() => exportReviewTemplate(externalRaw), throwsFormatException);
    final template = jsonDecode(
      exportReviewTemplate(externalRaw, allowExternal: true),
    ) as Map<String, dynamic>;
    final reviewed = finalizeReviewedCorpus(
      externalRaw,
      _approved(template),
      allowExternal: true,
    );
    final corpus = QualityCorpus.decode(reviewed, allowExternal: true);
    expect(corpus.isExternal, isTrue);
    expect(corpus.humanReviewed, isTrue);
  });

  test('review progress counts decisions without stamping the corpus', () {
    final corpusRaw = _repoCorpus();
    final template = _template(corpusRaw);

    final pending = inspectReviewProgress(corpusRaw, jsonEncode(template));
    expect(pending.total, 30);
    expect(pending.approved, 0);
    expect(pending.pending, 30);
    expect(pending.complete, isFalse);

    final approved = inspectReviewProgress(
      corpusRaw,
      _approved(jsonDecode(jsonEncode(template)) as Map<String, dynamic>),
    );
    expect(approved.approved, 30);
    expect(approved.pending, 0);
    expect(approved.complete, isTrue);

    final challenged = jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
    challenged['reviewer'] = 'reviewer';
    challenged['reviewed_at'] = '2026-11-07';
    final labels = challenged['labels'] as List;
    (labels.first as Map)['decision'] = 'challenged';
    for (final label in labels.skip(1)) {
      (label as Map)['decision'] = 'approved';
    }
    final mixed = inspectReviewProgress(corpusRaw, jsonEncode(challenged));
    expect(mixed.approved, 29);
    expect(mixed.challenged, 1);
    expect(mixed.challengedIds, hasLength(1));
    expect(mixed.complete, isFalse);
  });

  test('review progress validates coverage and digest', () {
    final corpusRaw = _repoCorpus();
    final template = _template(corpusRaw);

    final missing = jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
    (missing['labels'] as List).removeLast();
    expect(
      () => inspectReviewProgress(corpusRaw, jsonEncode(missing)),
      throwsA(isA<QualityReviewError>()),
    );

    final wrongDigest =
        jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
    wrongDigest['corpus_sha256'] = '0' * 64;
    expect(
      () => inspectReviewProgress(corpusRaw, jsonEncode(wrongDigest)),
      throwsA(isA<QualityReviewError>()),
    );

    final badIdentity = jsonDecode(jsonEncode(template)) as Map<String, dynamic>
      ..['reviewer'] = 'reviewer';
    badIdentity['reviewed_at'] = '2026-13-40';
    expect(
      () => inspectReviewProgress(corpusRaw, jsonEncode(badIdentity)),
      throwsA(isA<QualityReviewError>()),
    );
  });
}
