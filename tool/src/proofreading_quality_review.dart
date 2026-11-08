import 'dart:convert';

import 'package:bookloom/core/ai/ai_json.dart';
import 'package:crypto/crypto.dart';

import 'proofreading_quality.dart';

const int reviewTemplateMaxBytes = 4 * 1024 * 1024;
const int reviewMaxEntries = 100000;

/// Digest of the exact corpus bytes a review template was created from.
String qualityCorpusDigest(String raw) =>
    sha256.convert(utf8.encode(raw)).toString();

final class QualityReviewError implements Exception {
  const QualityReviewError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Builds a review template that names every label in [corpusRaw].
///
/// Completing the template does not edit the corpus: the reviewer fixes the
/// corpus first, regenerates the template, then marks every label as approved.
String exportReviewTemplate(String corpusRaw, {bool allowExternal = false}) {
  final corpus = QualityCorpus.decode(corpusRaw, allowExternal: allowExternal);
  return const JsonEncoder.withIndent('  ').convert({
    'schema_version': 1,
    'corpus_sha256': qualityCorpusDigest(corpusRaw),
    'reviewer': '',
    'reviewed_at': '',
    'labels': [
      for (final qualityCase in corpus.cases)
        for (final label in qualityCase.labels)
          {
            'case_id': qualityCase.id,
            'label_id': label.id,
            'original': label.original,
            'action': label.action,
            'decision': 'pending',
            'note': '',
          },
    ],
  });
}

final class ReviewProgress {
  const ReviewProgress({
    required this.total,
    required this.approved,
    required this.pending,
    required this.challenged,
    required this.pendingIds,
    required this.challengedIds,
  });

  final int total;
  final int approved;
  final int pending;
  final int challenged;
  final List<String> pendingIds;
  final List<String> challengedIds;

  bool get complete => approved == total && total > 0;
}

/// Counts decisions without writing or stamping a reviewed corpus.
ReviewProgress inspectReviewProgress(
  String corpusRaw,
  String reviewRaw, {
  bool allowExternal = false,
}) {
  final corpus = QualityCorpus.decode(corpusRaw, allowExternal: allowExternal);
  final review = _decodeReview(reviewRaw);
  if (review.corpusDigest != qualityCorpusDigest(corpusRaw)) {
    throw const QualityReviewError(
      'review corpus digest does not match the corpus file',
    );
  }
  if (review.reviewer.trim().isNotEmpty || review.reviewedAt.isNotEmpty) {
    try {
      validateReviewIdentity(
        reviewer: review.reviewer,
        reviewedAt: review.reviewedAt,
      );
    } on FormatException catch (error) {
      throw QualityReviewError(error.message);
    }
  }
  final expected = <String>{};
  for (final qualityCase in corpus.cases) {
    for (final label in qualityCase.labels) {
      expected.add('${qualityCase.id}\u0000${label.id}');
    }
  }
  final seen = <String>{};
  var approved = 0;
  var pending = 0;
  var challenged = 0;
  final pendingIds = <String>[];
  final challengedIds = <String>[];
  for (final entry in review.labels) {
    final key = '${entry.caseId}\u0000${entry.labelId}';
    if (!expected.contains(key)) {
      throw QualityReviewError(
        'review names an unknown label: ${entry.labelId}',
      );
    }
    if (!seen.add(key)) {
      throw QualityReviewError('duplicate review label: ${entry.labelId}');
    }
    final label = _label(corpus, entry.caseId, entry.labelId);
    if (entry.original != label.original) {
      throw QualityReviewError(
        'reviewed original differs from the corpus: ${entry.labelId}',
      );
    }
    switch (entry.decision) {
      case 'approved':
        approved++;
      case 'pending':
        pending++;
        pendingIds.add('${entry.caseId}/${entry.labelId}');
      case 'challenged':
        challenged++;
        challengedIds.add('${entry.caseId}/${entry.labelId}');
    }
  }
  if (seen.length != expected.length) {
    throw QualityReviewError(
      'review covers ${seen.length} of ${expected.length} labels',
    );
  }
  return ReviewProgress(
    total: expected.length,
    approved: approved,
    pending: pending,
    challenged: challenged,
    pendingIds: List<String>.unmodifiable(pendingIds),
    challengedIds: List<String>.unmodifiable(challengedIds),
  );
}

QualityLabel _label(QualityCorpus corpus, String caseId, String labelId) {
  for (final qualityCase in corpus.cases) {
    if (qualityCase.id != caseId) continue;
    for (final label in qualityCase.labels) {
      if (label.id == labelId) return label;
    }
  }
  throw QualityReviewError('review names an unknown label: $labelId');
}

/// Stamps reviewed provenance only when the review file covers every label of
/// the same corpus bytes and every decision is approved.
String finalizeReviewedCorpus(
  String corpusRaw,
  String reviewRaw, {
  bool allowExternal = false,
}) {
  final corpus = QualityCorpus.decode(corpusRaw, allowExternal: allowExternal);
  final review = _decodeReview(reviewRaw);
  if (review.corpusDigest != qualityCorpusDigest(corpusRaw)) {
    throw const QualityReviewError(
      'review corpus digest does not match the corpus file',
    );
  }
  try {
    validateReviewIdentity(
      reviewer: review.reviewer,
      reviewedAt: review.reviewedAt,
    );
  } on FormatException catch (error) {
    throw QualityReviewError(error.message);
  }
  final expected = <String, QualityLabel>{};
  for (final qualityCase in corpus.cases) {
    for (final label in qualityCase.labels) {
      expected['${qualityCase.id}\u0000${label.id}'] = label;
    }
  }
  final seen = <String>{};
  final unapproved = <String>[];
  for (final entry in review.labels) {
    final key = '${entry.caseId}\u0000${entry.labelId}';
    final label = expected[key];
    if (label == null) {
      throw QualityReviewError(
        'review names an unknown label: ${entry.labelId}',
      );
    }
    if (!seen.add(key)) {
      throw QualityReviewError('duplicate review label: ${entry.labelId}');
    }
    if (entry.original != label.original) {
      throw QualityReviewError(
        'reviewed original differs from the corpus: ${entry.labelId}',
      );
    }
    if (entry.decision != 'approved') {
      unapproved.add('${entry.caseId}/${entry.labelId}');
    }
  }
  if (seen.length != expected.length) {
    throw QualityReviewError(
      'review covers ${seen.length} of ${expected.length} labels',
    );
  }
  if (unapproved.isNotEmpty) {
    final shown = unapproved.take(5).join(', ');
    final suffix = unapproved.length > 5 ? ' …' : '';
    throw QualityReviewError('unapproved labels: $shown$suffix');
  }

  final Object? decoded;
  try {
    decoded = decodeStrictAiJson(corpusRaw);
  } on FormatException {
    throw const QualityReviewError('corpus is not strict JSON');
  }
  final root = decoded as Map<String, dynamic>;
  final provenance = root['provenance'] as Map<String, dynamic>;
  provenance['human_reviewed'] = true;
  provenance['review'] = <String, Object?>{
    'reviewer': review.reviewer,
    'reviewed_at': review.reviewedAt,
    'scope': 'all_labels',
    'review_file_sha256': sha256.convert(utf8.encode(reviewRaw)).toString(),
    'approved_labels': expected.length,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(root);
  final checked = QualityCorpus.decode(encoded, allowExternal: allowExternal);
  if (checked.cases.length != corpus.cases.length ||
      checked.cases.expand((item) => item.labels).length != expected.length) {
    throw const QualityReviewError('reviewed corpus changed its label count');
  }
  return '$encoded\n';
}

final class _ReviewFile {
  const _ReviewFile({
    required this.corpusDigest,
    required this.reviewer,
    required this.reviewedAt,
    required this.labels,
  });

  final String corpusDigest;
  final String reviewer;
  final String reviewedAt;
  final List<_ReviewLabel> labels;
}

final class _ReviewLabel {
  const _ReviewLabel({
    required this.caseId,
    required this.labelId,
    required this.original,
    required this.decision,
  });

  final String caseId;
  final String labelId;
  final String original;
  final String decision;
}

_ReviewFile _decodeReview(String raw) {
  if (utf8.encode(raw).length > reviewTemplateMaxBytes) {
    throw const QualityReviewError('review file exceeds 4 MiB');
  }
  final Object? decoded;
  try {
    decoded = decodeStrictAiJson(raw);
  } on FormatException {
    throw const QualityReviewError('review file is not strict JSON');
  }
  final root = _object(decoded, {
    'schema_version',
    'corpus_sha256',
    'reviewer',
    'reviewed_at',
    'labels',
  });
  if (root['schema_version'] != 1) {
    throw const QualityReviewError('unsupported review schema');
  }
  final digest = _string(root, 'corpus_sha256', 64);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw const QualityReviewError('invalid corpus digest');
  }
  final values = root['labels'];
  if (values is! List || values.length > reviewMaxEntries) {
    throw const QualityReviewError('invalid review labels');
  }
  final labels = <_ReviewLabel>[];
  for (final value in values) {
    final item = _object(value, {
      'case_id',
      'label_id',
      'original',
      'action',
      'decision',
      'note',
    });
    final decision = _string(item, 'decision', 16);
    if (!const {'approved', 'pending', 'challenged'}.contains(decision)) {
      throw const QualityReviewError('invalid review decision');
    }
    _string(item, 'note', 2000, allowEmpty: true);
    labels.add(
      _ReviewLabel(
        caseId: _string(item, 'case_id', 128),
        labelId: _string(item, 'label_id', 128),
        original: _string(item, 'original', 32768),
        decision: decision,
      ),
    );
  }
  return _ReviewFile(
    corpusDigest: digest,
    reviewer: _string(root, 'reviewer', 120, allowEmpty: true),
    reviewedAt: _string(root, 'reviewed_at', 10, allowEmpty: true),
    labels: labels,
  );
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    throw const QualityReviewError('invalid review field set');
  }
  return value;
}

String _string(
  Map<String, dynamic> value,
  String key,
  int limit, {
  bool allowEmpty = false,
}) {
  final item = value[key];
  if (item is! String ||
      item.length > limit ||
      (!allowEmpty && item.trim().isEmpty)) {
    throw QualityReviewError('invalid review field: $key');
  }
  return item;
}
