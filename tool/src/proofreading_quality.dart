import 'dart:convert';

import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_proofreading_prompt.dart';
import 'package:bookloom/core/editing/ai_change_application.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/chapter_edits.dart';
import 'package:bookloom/core/editing/proofreading_finding.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_scan.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/editing/rule_heading_mapping.dart';
import 'package:bookloom/core/editing/rule_scan_changes.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';

class QualityCorpus {
  QualityCorpus._(this.cases, this.provenance);

  final List<QualityCase> cases;
  final Map<String, Object?> provenance;

  bool get isExternal => provenance['kind'] == 'external_unverified';
  bool get containsUserManuscripts =>
      provenance['contains_user_manuscripts'] == true;
  bool get humanReviewed => provenance['human_reviewed'] == true;

  /// [allowExternal] must be set by an explicit user flag before a corpus
  /// derived from real manuscripts can be loaded at all.
  static QualityCorpus decode(String raw, {bool allowExternal = false}) {
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      _bad('corpus exceeds 2 MiB');
    }
    final root = _object(_strictJson(raw, 2 * 1024 * 1024), {
      'schema_version',
      'provenance',
      'rules',
      'cases',
    });
    if (root['schema_version'] != 1) _bad('unsupported corpus schema');
    final provenance = _objectWithOptional(
      root['provenance'],
      {'kind', 'contains_user_manuscripts', 'human_reviewed', 'notes'},
      {'review'},
    );
    final kind = _string(provenance, 'kind', 64);
    if (kind != 'assistant_authored_synthetic' &&
        kind != 'external_unverified') {
      _bad('unsupported corpus provenance kind');
    }
    final contains = provenance['contains_user_manuscripts'];
    final reviewed = provenance['human_reviewed'];
    if (contains is! bool || reviewed is! bool) {
      _bad('corpus provenance flags must be booleans');
    }
    if (kind == 'assistant_authored_synthetic' && contains) {
      _bad('synthetic corpus cannot contain user manuscripts');
    }
    if (kind == 'external_unverified' && !allowExternal) {
      _bad('external corpus requires explicit --allow-external consent');
    }
    _validateReview(provenance, reviewed: reviewed);
    _string(provenance, 'notes', 2048, empty: true);
    final definitions = <String, Map<String, Object?>>{};
    for (final value in _list(root['rules'], 32)) {
      final entry = _object(value, {'id', 'definition'});
      final id = _string(entry, 'id', 128);
      if (!definitions.containsKey(id)) {
        definitions[id] = _objectWithOptional(
          entry['definition'],
          {
            'schema_version',
            'name',
            'kind',
            'target',
            'match',
            'action',
            'positive_examples',
            'negative_examples',
            'reason',
          },
          {'heading_level'},
        );
      } else {
        _bad('duplicate rule id: $id');
      }
    }
    final cases = <QualityCase>[];
    final caseIds = <String>{};
    for (final value in _list(root['cases'], 64)) {
      final entry = _object(value, {
        'id',
        'description',
        'tags',
        'intent',
        'chunk_characters',
        'rule_ids',
        'chapters',
        'labels',
        'expected_after',
      });
      final id = _string(entry, 'id', 128);
      if (!caseIds.add(id)) _bad('duplicate case id: $id');
      final description = _string(entry, 'description', 2048);
      final tags = _strings(entry['tags'], 32, 64);
      final intent = switch (entry['intent']) {
        'advertisement' => AiProofreadingIntent.advertisement,
        'missing_chapter' => AiProofreadingIntent.missingChapter,
        _ => _bad('invalid intent in $id'),
      };
      final chunkCharacters = _integer(entry, 'chunk_characters', 512, 16384);
      final chapterValues = _list(entry['chapters'], 512);
      if (chapterValues.isEmpty) _bad('case $id has no chapters');
      final chapters = <Chapter>[];
      final chapterIds = <String>{};
      final blockTexts = <String, (String, String)>{};
      for (final (index, chapterValue) in chapterValues.indexed) {
        final chapter = _object(chapterValue, {
          'id',
          'title',
          'level',
          'parent_id',
          'front_matter',
          'blocks',
        });
        final chapterId = _string(chapter, 'id', 128);
        if (!chapterIds.add(chapterId)) {
          _bad('duplicate chapter id: $chapterId');
        }
        final title = _string(chapter, 'title', 512, empty: true);
        final level = _integer(chapter, 'level', 1, 2);
        final parentId = _nullableString(chapter, 'parent_id', 128);
        final frontMatter = _boolean(chapter, 'front_matter');
        final blocks = <Block>[];
        for (final blockValue in _list(chapter['blocks'], 10000)) {
          final rawBlock = _objectAny(blockValue);
          final kind = rawBlock['kind'];
          final expectedKeys = switch (kind) {
            'paragraph' => {'id', 'kind', 'text'},
            'image' => {'id', 'kind', 'asset_id', 'caption', 'alt'},
            'footnote' => {'id', 'kind', 'text', 'marker'},
            'divider' => {'id', 'kind'},
            _ => _bad('unknown block kind in $id'),
          };
          _keys(rawBlock, expectedKeys);
          final blockId = _string(rawBlock, 'id', 128);
          if (blocks.any((block) => block.id == blockId) ||
              chapters.any(
                (prior) => prior.blocks.any((block) => block.id == blockId),
              )) {
            _bad('duplicate block id: $blockId');
          }
          switch (kind) {
            case 'paragraph':
              final text = _string(rawBlock, 'text', 32768, empty: true);
              blockTexts[blockId] = (chapterId, text);
              blocks.add(TextBlock(id: blockId, text: text));
            case 'image':
              blocks.add(
                ImageBlock(
                  id: blockId,
                  assetId: _string(rawBlock, 'asset_id', 128),
                  caption: _nullableString(rawBlock, 'caption', 32768),
                  alt: _string(rawBlock, 'alt', 32768, empty: true),
                ),
              );
            case 'footnote':
              blocks.add(
                FootnoteBlock(
                  id: blockId,
                  text: _string(rawBlock, 'text', 32768, empty: true),
                  marker: _nullableString(rawBlock, 'marker', 128),
                ),
              );
            case 'divider':
              blocks.add(DividerBlock(id: blockId));
          }
        }
        if (level == 1 && (parentId != null || blocks.isNotEmpty)) {
          _bad('volume must be a top-level empty container: $chapterId');
        }
        if (parentId != null &&
            !chapters.any(
              (prior) => prior.id == parentId && prior.level == 1,
            )) {
          _bad('parent must be a preceding volume: $chapterId');
        }
        chapters.add(
          Chapter(
            id: chapterId,
            bookId: id,
            title: title,
            level: level,
            parentId: parentId,
            frontMatter: frontMatter,
            order: index,
            blocks: List<Block>.unmodifiable(blocks),
          ),
        );
      }
      final labels = <QualityLabel>[];
      final labelIds = <String>{};
      for (final value in _list(entry['labels'], 1000)) {
        final label = _objectWithOptional(
          value,
          {
            'id',
            'chapter_id',
            'block_id',
            'start_utf16',
            'end_utf16',
            'original',
            'acceptable_assessments',
            'action',
            'title',
            'remove_title_line',
            'reason',
          },
          {
            'heading_level',
            'heading_number',
            'title_evidence_range',
            'number_evidence_range',
          },
        );
        final labelId = _string(label, 'id', 128);
        if (!labelIds.add(labelId)) _bad('duplicate label id: $labelId');
        final chapterId = _string(label, 'chapter_id', 128);
        final blockId = _string(label, 'block_id', 128);
        final location = blockTexts[blockId];
        final start = _integer(label, 'start_utf16', 0, 32768);
        final end = _integer(label, 'end_utf16', 1, 32768);
        final original = _string(label, 'original', 32768);
        if (location == null ||
            location.$1 != chapterId ||
            start >= end ||
            end > location.$2.length ||
            !_boundary(location.$2, start) ||
            !_boundary(location.$2, end) ||
            location.$2.substring(start, end) != original) {
          _bad('label source mismatch: $labelId');
        }
        final assessments = _strings(label['acceptable_assessments'], 9, 32);
        if (assessments.isEmpty ||
            assessments.toSet().length != assessments.length ||
            assessments.any(
              (assessment) => !_assessmentsFor(intent).contains(assessment),
            )) {
          _bad('invalid assessments: $labelId');
        }
        final action = _string(label, 'action', 32);
        if (!{
              'none',
              'delete_text',
              'remove_block',
              'split_chapter',
              'rename_chapter',
            }.contains(action) ||
            intent == AiProofreadingIntent.advertisement &&
                {'split_chapter', 'rename_chapter'}.contains(action) ||
            intent == AiProofreadingIntent.missingChapter &&
                {'delete_text', 'remove_block'}.contains(action)) {
          _bad('invalid label action: $labelId');
        }
        final title = _string(label, 'title', 256, empty: true);
        final removeTitleLine = _boolean(label, 'remove_title_line');
        final headingLevel = label.containsKey('heading_level')
            ? _integer(label, 'heading_level', 1, 2)
            : 2;
        final headingNumber = label.containsKey('heading_number')
            ? _integer(label, 'heading_number', 1, RuleHeadingMapping.maxNumber)
            : null;
        final titleEvidenceRange = _evidenceRange(
          label,
          'title_evidence_range',
          original,
        );
        final numberEvidenceRange = _evidenceRange(
          label,
          'number_evidence_range',
          original,
        );
        if (action != 'split_chapter' &&
            const {
              'heading_level',
              'heading_number',
              'title_evidence_range',
              'number_evidence_range',
            }.any(label.containsKey)) {
          _bad('non-split label has heading mapping fields: $labelId');
        }
        if (action == 'split_chapter') {
          if (!assessments.any(
            (item) => {'missed_heading', 'merged_content'}.contains(item),
          )) {
            _bad('invalid split label: $labelId');
          }
          try {
            AiChapterSplitProposal(
              id: labelId,
              target: ProposalTextTarget(
                bookId: id,
                sessionId: 'quality-session',
                sessionRevision: 0,
                chapterId: chapterId,
                blockId: blockId,
                originalText: original,
              ),
              range: ProposalTextRange(start, end),
              title: title,
              removeTitleLine: removeTitleLine,
              reason: 'Synthetic label',
              headingLevel: headingLevel,
              headingNumber: headingNumber,
              titleEvidenceRange: titleEvidenceRange,
              numberEvidenceRange: numberEvidenceRange,
            ).titleLineIn(location.$2, ProposalTextRange(start, end));
          } on Object {
            _bad('split label is not an independent heading: $labelId');
          }
        } else if (action == 'rename_chapter') {
          final chapter = chapters.singleWhere((item) => item.id == chapterId);
          final firstText = chapter.blocks
              .whereType<TextBlock>()
              .where((block) => block.text.trim().isNotEmpty)
              .firstOrNull;
          final firstLine = firstText == null
              ? null
              : RegExp(r'[^\r\n]+')
                    .allMatches(firstText.text)
                    .where((match) => match.group(0)!.trim().isNotEmpty)
                    .firstOrNull;
          if (assessments.length != 1 ||
              assessments.single != 'missed_heading' ||
              removeTitleLine ||
              title != original.trim() ||
              RegExp(r'[\x00-\x1f\x7f\u2028\u2029]').hasMatch(title) ||
              title == chapter.title ||
              firstText?.id != blockId ||
              firstLine == null ||
              start < firstLine.start ||
              end > firstLine.end ||
              firstText!.text
                  .substring(firstLine.start, start)
                  .trim()
                  .isNotEmpty ||
              firstText.text.substring(end, firstLine.end).trim().isNotEmpty) {
            _bad('invalid rename label: $labelId');
          }
        } else if (title.isNotEmpty || removeTitleLine) {
          _bad('non-split label has split fields: $labelId');
        }
        if (action == 'delete_text' && !assessments.contains('advertisement')) {
          _bad('deletion label must allow advertisement: $labelId');
        }
        if (action == 'remove_block' &&
            (assessments.length != 1 ||
                assessments.single != 'advertisement' ||
                start != 0 ||
                end != location.$2.length)) {
          _bad(
            'block removal label must cover an advertisement block: $labelId',
          );
        }
        labels.add(
          QualityLabel(
            id: labelId,
            chapterId: chapterId,
            blockId: blockId,
            startUtf16: start,
            endUtf16: end,
            original: original,
            acceptableAssessments: List<String>.unmodifiable(assessments),
            action: action,
            title: title,
            removeTitleLine: removeTitleLine,
            headingLevel: headingLevel,
            headingNumber: headingNumber,
            titleEvidenceRange: titleEvidenceRange,
            numberEvidenceRange: numberEvidenceRange,
            reason: _string(label, 'reason', 1024),
          ),
        );
      }
      for (final (index, label) in labels.indexed) {
        if (labels
            .skip(index + 1)
            .any(
              (other) =>
                  other.blockId == label.blockId &&
                  label.startUtf16 < other.endUtf16 &&
                  other.startUtf16 < label.endUtf16,
            )) {
          _bad('overlapping labels in $id');
        }
      }
      ChapterEdits.normalize(chapters);
      final ruleIds = _strings(entry['rule_ids'], 32, 128);
      if (ruleIds.toSet().length != ruleIds.length) {
        _bad('duplicate rule reference in $id');
      }
      final rules = <ProofreadingRule>[];
      for (final ruleId in ruleIds) {
        final definition = definitions[ruleId];
        if (definition == null) _bad('unknown rule: $ruleId');
        final positive = _strings(definition['positive_examples'], 12, 2048);
        final negative = _strings(definition['negative_examples'], 12, 2048);
        rules.add(
          RuleProposalDecoder.decode(
            jsonEncode(definition),
            proposalId: 'quality-proposal-$ruleId',
            ruleId: ruleId,
            bookId: id,
            source: ProofreadingRuleSource.user,
            requiredPositiveExamples: positive,
            requiredNegativeExamples: negative,
          ).rule,
        );
      }
      final source = Book(
        id: id,
        meta: BookMeta(title: id),
        chapters: List<Chapter>.unmodifiable(chapters),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final expectedAfter = <Map<String, Object?>>[];
      for (final value in _list(entry['expected_after'], 1024)) {
        expectedAfter.add(_normalizedChapter(value));
      }
      for (final (index, chapter) in expectedAfter.indexed) {
        final parent = chapter['parent_index'];
        if (parent != null &&
            (chapter['level'] != 2 ||
                parent is! int ||
                parent >= index ||
                expectedAfter[parent]['level'] != 1)) {
          _bad('invalid expected_after parent_index in $id');
        }
      }
      final qualityCase = QualityCase._(
        id,
        description,
        List<String>.unmodifiable(tags),
        intent,
        source,
        List<QualityLabel>.unmodifiable(labels),
        List<ProofreadingRule>.unmodifiable(rules),
        List<Map<String, Object?>>.unmodifiable(expectedAfter),
        chunkCharacters,
      );
      qualityCase.plan;
      for (final label in labels.where(
        (label) => label.action == 'rename_chapter',
      )) {
        final text = _text(source, label.chapterId, label.blockId);
        final line = RegExp(r'[^\r\n]+')
            .allMatches(text)
            .firstWhere((match) => match.group(0)!.trim().isNotEmpty);
        if (!qualityCase.plan.chunks.any(
          (chunk) => chunk.slices.any(
            (slice) =>
                slice.block.blockId == label.blockId &&
                slice.startUtf16 <= line.start &&
                slice.endUtf16 >= line.end,
          ),
        )) {
          _bad('rename label heading is not fully visible: ${label.id}');
        }
      }
      cases.add(qualityCase);
    }
    if (cases.isEmpty) _bad('corpus has no cases');
    return QualityCorpus._(
      List<QualityCase>.unmodifiable(cases),
      Map<String, Object?>.unmodifiable(provenance),
    );
  }
}

class QualityResponseBatch {
  QualityResponseBatch._(this.origin, this.responsesByCase);

  final String origin;
  final Map<String, List<String>> responsesByCase;

  static QualityResponseBatch decode(String raw) {
    if (utf8.encode(raw).length > 4 * 1024 * 1024) {
      _bad('response batch exceeds 4 MiB');
    }
    final root = _object(_strictJson(raw, 4 * 1024 * 1024), {
      'schema_version',
      'origin',
      'cases',
    });
    if (root['schema_version'] != 1 ||
        !{
          'synthetic_reference',
          'external_unverified',
        }.contains(root['origin'])) {
      _bad('invalid response batch schema or origin');
    }
    final rawCases = _objectAny(root['cases']);
    if (rawCases.length > 64) _bad('too many response cases');
    final responses = <String, List<String>>{};
    for (final entry in rawCases.entries) {
      if (entry.key.trim().isEmpty ||
          entry.key.length > 128 ||
          !_validUtf16(entry.key)) {
        _bad('invalid response case id');
      }
      final values = _list(entry.value, 128);
      responses[entry.key] = List<String>.unmodifiable([
        for (final value in values)
          _string(
            {'response': value},
            'response',
            4 * 1024 * 1024,
            empty: true,
          ),
      ]);
    }
    return QualityResponseBatch._(
      root['origin'] as String,
      Map<String, List<String>>.unmodifiable(responses),
    );
  }
}

void _validateReview(
  Map<String, Object?> provenance, {
  required bool reviewed,
}) {
  final raw = provenance['review'];
  if (!reviewed) {
    if (raw != null) _bad('unreviewed corpus must not carry review evidence');
    return;
  }
  final review = _objectWithOptional(
    raw,
    {'reviewer', 'reviewed_at', 'scope'},
    {'review_file_sha256', 'approved_labels'},
  );
  validateReviewIdentity(
    reviewer: _string(review, 'reviewer', 120),
    reviewedAt: _string(review, 'reviewed_at', 10),
  );
  if (_string(review, 'scope', 32) != 'all_labels') {
    _bad('review scope must cover all labels');
  }
  if (review.containsKey('review_file_sha256') &&
      !RegExp(r'^[0-9a-f]{64}$')
          .hasMatch(_string(review, 'review_file_sha256', 64))) {
    _bad('invalid review file digest');
  }
  if (review.containsKey('approved_labels')) {
    final approved = review['approved_labels'];
    if (approved is! int || approved < 0 || approved > 100000) {
      _bad('invalid approved label count');
    }
  }
}

/// Shared reviewer/date checks for corpora and review files.
void validateReviewIdentity({
  required String reviewer,
  required String reviewedAt,
}) {
  if (reviewer != reviewer.trim() ||
      reviewer.isEmpty ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(reviewer)) {
    _bad('invalid review reviewer');
  }
  final parsed = DateTime.tryParse(reviewedAt);
  if (parsed == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(reviewedAt) ||
      parsed.toIso8601String().substring(0, 10) != reviewedAt) {
    _bad('invalid review date');
  }
}

class QualityCase {
  QualityCase._(
    this.id,
    this.description,
    this.tags,
    this.intent,
    this.source,
    this.labels,
    this.rules,
    this.expectedAfter,
    this.chunkCharacters,
  );

  final String id;
  final String description;
  final List<String> tags;
  final AiProofreadingIntent intent;
  final Book source;
  final List<QualityLabel> labels;
  final List<ProofreadingRule> rules;
  final List<Map<String, Object?>> expectedAfter;
  final int chunkCharacters;

  late final AiContextPlan plan = AiContextPlanner.plan(
    bookId: source.id,
    sessionId: 'quality-session',
    sessionRevision: 0,
    blocks: [
      for (final chapter in source.chapters)
        for (final block in chapter.blocks)
          if (block is TextBlock)
            AiContextBlock(
              chapterId: chapter.id,
              chapterTitle: chapter.title,
              blockId: block.id,
              text: block.text,
            ),
    ],
    maxChunkCharacters: chunkCharacters,
  );
}

class QualityLabel {
  const QualityLabel({
    required this.id,
    required this.chapterId,
    required this.blockId,
    required this.startUtf16,
    required this.endUtf16,
    required this.original,
    required this.acceptableAssessments,
    required this.action,
    required this.title,
    required this.removeTitleLine,
    required this.reason,
    this.headingLevel = 2,
    this.headingNumber,
    this.titleEvidenceRange,
    this.numberEvidenceRange,
  });

  final String id;
  final String chapterId;
  final String blockId;
  final int startUtf16;
  final int endUtf16;
  final String original;
  final List<String> acceptableAssessments;
  final String action;
  final String title;
  final bool removeTitleLine;
  final String reason;
  final int headingLevel;
  final int? headingNumber;
  final ProposalTextRange? titleEvidenceRange;
  final ProposalTextRange? numberEvidenceRange;
}

class QualityReport {
  QualityReport._(this.mode, this.provenance, this.caseResults, this.summary);

  final String mode;
  final Map<String, Object?> provenance;
  final List<Map<String, Object?>> caseResults;
  final Map<String, Object?> summary;

  bool get hasStrictFailure =>
      (summary['action_fp'] as int) > 0 ||
      (summary['action_fn'] as int) > 0 ||
      (summary['classification_fp'] as int? ?? 0) > 0 ||
      (summary['classification_fn'] as int? ?? 0) > 0 ||
      (summary['invalid_cases'] as int) > 0 ||
      (summary['compile_blocked_cases'] as int) > 0 ||
      (summary['effective_mismatch_cases'] as int) > 0;

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'mode': mode,
    'provenance': provenance,
    'realProviderQualityVerified': false,
    'qualityPassed': false,
    'summary': summary,
    'cases': caseResults,
  };
}

/// Human-readable, deterministic summary without corpus text.
String qualityMarkdownReport(QualityReport report) {
  final summary = report.summary;
  int value(String key) => (summary[key] as int?) ?? 0;
  String percent(String key) {
    final raw = summary[key];
    return raw is num ? '${(raw * 100).toStringAsFixed(2)}%' : 'n/a';
  }

  final out = StringBuffer()
    ..writeln('# Bookloom proofreading quality report')
    ..writeln()
    ..writeln('- Mode: `${report.mode}`')
    ..writeln('- Corpus kind: `${report.provenance['kind'] ?? 'unknown'}`')
    ..writeln(
      '- Human reviewed: `${report.provenance['human_reviewed'] ?? false}`',
    )
    ..writeln(
      '- Contains user manuscripts: '
      '`${report.provenance['contains_user_manuscripts'] ?? false}`',
    )
    ..writeln('- Real-provider quality verified: `false`')
    ..writeln('- Quality passed: `false`')
    ..writeln()
    ..writeln('## Totals')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('| --- | --- |')
    ..writeln('| Cases | ${value('case_count')} |')
    ..writeln(
      '| Action TP / FP / FN | ${value('action_tp')} / '
      '${value('action_fp')} / ${value('action_fn')} |',
    )
    ..writeln(
      '| Action precision / recall | ${percent('action_precision')} / '
      '${percent('action_recall')} |',
    )
    ..writeln(
      '| Classification | ${summary['classification_status']} '
      '(${value('classification_tp')} TP, ${value('classification_fp')} FP, '
      '${value('classification_fn')} FN) |',
    )
    ..writeln(
      '| Protected false positives | ${value('protected_false_positives')} |',
    )
    ..writeln(
      '| Full results | ${value('effective_cases')} / '
      '${value('case_count')} |',
    )
    ..writeln('| Effective change cases | ${value('effective_change_cases')} |')
    ..writeln('| Effective mismatches | ${value('effective_mismatch_cases')} |')
    ..writeln(
      '| Invalid / blocked | ${value('invalid_cases')} / '
      '${value('compile_blocked_cases')} |',
    )
    ..writeln()
    ..writeln('## Per action')
    ..writeln()
    ..writeln('| Action | TP | FP | FN | Precision | Recall |')
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  final metrics = summary['action_metrics'] as Map<String, Object?>?;
  if (metrics != null) {
    for (final entry in metrics.entries) {
      final values = entry.value as Map<String, Object?>;
      out.writeln(
        '| ${entry.key} | ${values['tp']} | ${values['fp']} | '
        '${values['fn']} | '
        '${values['precision'] is num ? '${((values['precision'] as num) * 100).toStringAsFixed(2)}%' : 'n/a'} | '
        '${values['recall'] is num ? '${((values['recall'] as num) * 100).toStringAsFixed(2)}%' : 'n/a'} |',
      );
    }
  }
  out
    ..writeln()
    ..writeln('## Cases needing attention')
    ..writeln();
  var failures = 0;
  for (final result in report.caseResults) {
    final actionFn = (result['action_fn'] as int?) ?? 0;
    final classificationFn = (result['classification_fn'] as int?) ?? 0;
    final mismatch = result['expected_after_equal'] != true;
    if (actionFn == 0 && classificationFn == 0 && !mismatch) continue;
    failures++;
    out.writeln(
      '- `${result['id']}`: action TP ${result['action_tp']} / '
      'FP ${result['action_fp']} / FN $actionFn; '
      'classification FN $classificationFn; '
      'expected-after ${mismatch ? 'mismatch' : 'match'}.',
    );
  }
  if (failures == 0) out.writeln('_None._');
  return out.toString();
}

abstract final class QualityEvaluator {
  static QualityReport evaluateRules(QualityCorpus corpus) =>
      _evaluate(corpus, 'offline-rules', (qualityCase) {
        final scan = ProofreadingRuleScan.scan(
          qualityCase.source,
          selectedRules: qualityCase.rules,
          loadedChapterIds: qualityCase.source.chapters
              .map((chapter) => chapter.id)
              .toSet(),
          limits: const RuleScanLimits(maxSamples: 20000),
        );
        if (scan.hiddenMatches != 0 ||
            scan.hiddenConflicts != 0 ||
            scan.samples.length != scan.distinctMatches) {
          throw const FormatException('rule scan omitted matches or conflicts');
        }
        final findings = <_Prediction>[];
        final executable = <RuleScanMatch>[];
        for (final match in scan.samples) {
          if (match.action == ProofreadingRuleAction.chapterCandidate) {
            final title = RuleScanChanges.describe(
              qualityCase.source,
              match,
            ).headingTitle!;
            final text = _text(
              qualityCase.source,
              match.chapterId,
              match.blockId,
            );
            final lineStart = match.startUtf16 == 0
                ? 0
                : text.lastIndexOf('\n', match.startUtf16 - 1) + 1;
            final lineEnd = text.indexOf('\n', match.startUtf16);
            final raw = text.substring(
              lineStart,
              lineEnd < 0 ? text.length : lineEnd,
            );
            final start = lineStart + raw.length - raw.trimLeft().length;
            findings.add(
              _Prediction(
                'split_chapter',
                match.chapterId,
                match.blockId,
                start,
                start + raw.trim().length,
                'missed_heading',
                title: title,
                removeTitleLine: true,
                headingLevel: match.headingLevel,
                headingNumber: match.mappedNumber,
              ),
            );
            executable.add(match);
          } else {
            findings.add(
              _Prediction(
                match.action == ProofreadingRuleAction.exactDeletion
                    ? 'delete_text'
                    : 'none',
                match.chapterId,
                match.blockId,
                match.startUtf16,
                match.endUtf16,
                match.action == ProofreadingRuleAction.exactDeletion
                    ? 'advertisement'
                    : 'undetermined',
              ),
            );
            if (match.action == ProofreadingRuleAction.exactDeletion) {
              executable.add(match);
            }
          }
        }
        List<Chapter>? compiled;
        String? blocked;
        if (executable.isNotEmpty) {
          try {
            final changes = RuleScanChanges.build(
              snapshot: qualityCase.source,
              sessionId: 'quality-session',
              saveSeq: 0,
              selectedMatches: executable,
            );
            compiled = _compile(
              qualityCase,
              changes.textProposals,
              changes.splitProposals,
              changes.selectedIds,
            );
          } on Object catch (error) {
            blocked = '$error';
          }
        } else {
          compiled = qualityCase.source.chapters;
        }
        return _Evaluation(findings, findings, compiled, blocked, null, {
          'scan_matches': scan.distinctMatches,
          'scan_conflicts': scan.totalConflicts,
          'scan_coverage_chapters': scan.coverage.chapters,
          'scan_coverage_text_blocks': scan.coverage.textBlocks,
        });
      });

  static QualityReport evaluateResponses(
    QualityCorpus corpus,
    Map<String, List<String>> responsesByCase,
  ) {
    final ids = corpus.cases.map((item) => item.id).toSet();
    if (responsesByCase.keys.toSet().length != ids.length ||
        !responsesByCase.keys.toSet().containsAll(ids)) {
      _bad('responses must cover exactly every case');
    }
    for (final qualityCase in corpus.cases) {
      if (responsesByCase[qualityCase.id]!.length !=
          qualityCase.plan.chunks.length) {
        _bad('response count differs from chunk count: ${qualityCase.id}');
      }
    }
    return _evaluate(corpus, 'response-replay', (qualityCase) {
      final results = <AiAnalysisResult>[];
      final responses = responsesByCase[qualityCase.id]!;
      for (final (index, raw) in responses.indexed) {
        try {
          if (raw.length > 65536) {
            throw const FormatException('response too large');
          }
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic> ||
              decoded['rule_proposals'] is! List ||
              (decoded['rule_proposals'] as List).isNotEmpty) {
            throw const FormatException(
              'rule proposals are outside proofreading task',
            );
          }
          final result = AiAnalysisResultDecoder.decode(
            raw,
            context: qualityCase.plan.chunks[index],
            responseId: 'quality-${corpus.cases.indexOf(qualityCase)}-$index',
          );
          if (!_matchesIntent(qualityCase.intent, result)) {
            throw const FormatException('response intent mismatch');
          }
          results.add(result);
        } on Object catch (error) {
          return _Evaluation(
            const [],
            const [],
            null,
            null,
            'chunk $index: $error',
            const {},
          );
        }
      }
      final findings = <_Prediction>[];
      final actions = <_Prediction>[];
      final texts = <AiTextProposal>[];
      final splits = <AiChapterSplitProposal>[];
      for (final (index, result) in results.indexed) {
        for (final finding in result.findings) {
          findings.add(
            _Prediction(
              'none',
              finding.chapterId,
              finding.blockId!,
              finding.range!.start,
              finding.range!.end,
              _assessmentWire(finding.assessment),
            ),
          );
        }
        for (final (proposalIndex, proposal)
            in result.textChanges.proposals.indexed) {
          final local = AiTextProposal(
            id: 'quality-text-$index-$proposalIndex',
            action: proposal.action,
            target: proposal.target,
            range: proposal.range,
            replacement: proposal.replacement,
            reason: proposal.reason,
            originalTitle: proposal.originalTitle,
          );
          texts.add(local);
          actions.add(
            _Prediction(
              switch (proposal.action) {
                AiTextProposalAction.deleteText => 'delete_text',
                AiTextProposalAction.removeBlock => 'remove_block',
                AiTextProposalAction.replaceText => 'replace_text',
                AiTextProposalAction.renameChapter => 'rename_chapter',
              },
              proposal.target.chapterId,
              proposal.target.blockId,
              proposal.range.start,
              proposal.range.end,
              null,
              title: proposal.action == AiTextProposalAction.renameChapter
                  ? proposal.replacement
                  : '',
            ),
          );
        }
        for (final (proposalIndex, proposal) in result.chapterSplits.indexed) {
          final local = AiChapterSplitProposal(
            id: 'quality-split-$index-$proposalIndex',
            target: proposal.target,
            range: proposal.range,
            title: proposal.title,
            removeTitleLine: proposal.removeTitleLine,
            reason: proposal.reason,
          );
          splits.add(local);
          actions.add(
            _Prediction(
              'split_chapter',
              proposal.target.chapterId,
              proposal.target.blockId,
              proposal.range.start,
              proposal.range.end,
              null,
              title: proposal.title,
              removeTitleLine: proposal.removeTitleLine,
            ),
          );
        }
      }
      List<Chapter>? compiled;
      String? blocked;
      if (texts.any(
        (proposal) => proposal.action == AiTextProposalAction.replaceText,
      )) {
        blocked = 'replace_text is outside quality corpus action scope';
      } else {
        try {
          compiled = _compile(qualityCase, texts, splits, {
            ...texts.map((proposal) => proposal.id),
            ...splits.map((proposal) => proposal.id),
          });
        } on Object catch (error) {
          blocked = '$error';
        }
      }
      return _Evaluation(findings, actions, compiled, blocked, null, {
        'chunks': qualityCase.plan.chunks.length,
      });
    });
  }

  static List<Map<String, Object?>> normalizeChapters(List<Chapter> chapters) {
    final indices = {
      for (final (index, chapter) in chapters.indexed) chapter.id: index,
    };
    return [
      for (final chapter in chapters)
        <String, Object?>{
          'title': chapter.title,
          'level': chapter.level,
          'parent_index': chapter.parentId == null
              ? null
              : indices[chapter.parentId],
          'front_matter': chapter.frontMatter,
          'blocks': [
            for (final block in chapter.blocks) _normalizedBlock(block),
          ],
        },
    ];
  }
}

class _Prediction {
  const _Prediction(
    this.action,
    this.chapterId,
    this.blockId,
    this.start,
    this.end,
    this.assessment, {
    this.title = '',
    this.removeTitleLine = false,
    this.headingLevel = 2,
    this.headingNumber,
  });
  final String action;
  final String chapterId;
  final String blockId;
  final int start;
  final int end;
  final String? assessment;
  final String title;
  final bool removeTitleLine;
  final int headingLevel;
  final int? headingNumber;

  Map<String, Object?> toJson() => {
    'action': action,
    'chapter_id': chapterId,
    'block_id': blockId,
    'start_utf16': start,
    'end_utf16': end,
    if (assessment != null) 'assessment': assessment,
    if (action == 'split_chapter' || action == 'rename_chapter') 'title': title,
    if (action == 'split_chapter') ...{
      'remove_title_line': removeTitleLine,
      'heading_level': headingLevel,
      if (headingNumber != null) 'heading_number': headingNumber,
    },
  };
}

class _Evaluation {
  const _Evaluation(
    this.findings,
    this.actions,
    this.compiled,
    this.blocked,
    this.invalid,
    this.details,
  );
  final List<_Prediction> findings;
  final List<_Prediction> actions;
  final List<Chapter>? compiled;
  final String? blocked;
  final String? invalid;
  final Map<String, Object?> details;
}

QualityReport _evaluate(
  QualityCorpus corpus,
  String mode,
  _Evaluation Function(QualityCase) run,
) {
  final classificationApplies = mode == 'response-replay';
  final cases = <Map<String, Object?>>[];
  var actionTp = 0, actionFp = 0, actionFn = 0;
  final actionTpBy = <String, int>{};
  final actionFpBy = <String, int>{};
  final actionFnBy = <String, int>{};
  var classificationTp = 0, classificationFp = 0, classificationFn = 0;
  var protectedFp = 0, invalidCases = 0, blockedCases = 0;
  var effectiveCases = 0, effectiveChangeCases = 0, mismatchCases = 0;
  for (final qualityCase in corpus.cases) {
    _Evaluation evaluation;
    try {
      evaluation = run(qualityCase);
    } on Object catch (error) {
      evaluation = _Evaluation(
        const [],
        const [],
        null,
        null,
        '$error',
        const {},
      );
    }
    if (evaluation.invalid != null) invalidCases++;
    if (evaluation.blocked != null) blockedCases++;
    final actionable = qualityCase.labels
        .where((label) => label.action != 'none')
        .toList();
    final usedActions = <int>{};
    final falseActions = <Map<String, Object?>>[];
    final missedActions = <String>[];
    for (final label in actionable) {
      final match = evaluation.actions.indexed
          .where(
            (entry) =>
                !usedActions.contains(entry.$1) && _sameAction(entry.$2, label),
          )
          .firstOrNull;
      if (match == null) {
        actionFn++;
        actionFnBy.update(
          label.action,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        missedActions.add(label.id);
      } else {
        actionTp++;
        actionTpBy.update(
          label.action,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        usedActions.add(match.$1);
      }
    }
    var caseActionFp = 0;
    var caseProtectedFp = 0;
    for (final (index, prediction) in evaluation.actions.indexed) {
      if (prediction.action == 'none' || usedActions.contains(index)) continue;
      actionFp++;
      actionFpBy.update(
        prediction.action,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      caseActionFp++;
      falseActions.add(prediction.toJson());
      if (qualityCase.labels.any(
        (label) =>
            label.action == 'none' &&
            label.chapterId == prediction.chapterId &&
            label.blockId == prediction.blockId &&
            label.startUtf16 < prediction.end &&
            prediction.start < label.endUtf16,
      )) {
        protectedFp++;
        caseProtectedFp++;
      }
    }
    final usedFindings = <int>{};
    final missedFindings = <String>[];
    final falseFindings = <Map<String, Object?>>[];
    if (classificationApplies) {
      for (final label in qualityCase.labels) {
        final match = evaluation.findings.indexed
            .where(
              (entry) =>
                  !usedFindings.contains(entry.$1) &&
                  _sameLocation(entry.$2, label) &&
                  label.acceptableAssessments.contains(entry.$2.assessment),
            )
            .firstOrNull;
        if (match == null) {
          classificationFn++;
          missedFindings.add(label.id);
        } else {
          classificationTp++;
          usedFindings.add(match.$1);
        }
      }
      for (final (index, finding) in evaluation.findings.indexed) {
        if (usedFindings.contains(index)) continue;
        classificationFp++;
        falseFindings.add(finding.toJson());
      }
    }
    final actual = evaluation.compiled == null
        ? null
        : QualityEvaluator.normalizeChapters(evaluation.compiled!);
    final matchesExpected =
        actual != null &&
        jsonEncode(actual) == jsonEncode(qualityCase.expectedAfter);
    if (matchesExpected) {
      effectiveCases++;
      if (actionable.isNotEmpty) effectiveChangeCases++;
    } else {
      mismatchCases++;
    }
    cases.add({
      'id': qualityCase.id,
      'tags': qualityCase.tags,
      'expected_action_labels': actionable.length,
      'expected_classification_labels': classificationApplies
          ? qualityCase.labels.length
          : null,
      'action_tp': actionable.length - missedActions.length,
      'action_fp': caseActionFp,
      'action_fn': missedActions.length,
      'classification_tp': classificationApplies
          ? qualityCase.labels.length - missedFindings.length
          : null,
      'classification_fp': classificationApplies ? falseFindings.length : null,
      'classification_fn': classificationApplies ? missedFindings.length : null,
      'protected_false_positives': caseProtectedFp,
      'false_positive_spans': falseActions,
      'false_positive_findings': classificationApplies ? falseFindings : null,
      'false_negative_label_ids': missedActions,
      'classification_false_negative_label_ids': classificationApplies
          ? missedFindings
          : null,
      'invalid_result': evaluation.invalid,
      'compile_blocked': evaluation.blocked,
      'expected_after_equal': matchesExpected,
      ...evaluation.details,
    });
  }
  final summary = <String, Object?>{
    'case_count': corpus.cases.length,
    'action_tp': actionTp,
    'action_fp': actionFp,
    'action_fn': actionFn,
    'action_precision': _ratio(actionTp, actionTp + actionFp),
    'action_recall': _ratio(actionTp, actionTp + actionFn),
    'action_f1': _f1(actionTp, actionFp, actionFn),
    'classification_status': classificationApplies
        ? 'applicable'
        : 'not_applicable',
    'classification_tp': classificationApplies ? classificationTp : null,
    'classification_fp': classificationApplies ? classificationFp : null,
    'classification_fn': classificationApplies ? classificationFn : null,
    'classification_precision': classificationApplies
        ? _ratio(classificationTp, classificationTp + classificationFp)
        : null,
    'classification_recall': classificationApplies
        ? _ratio(classificationTp, classificationTp + classificationFn)
        : null,
    'classification_f1': classificationApplies
        ? _f1(classificationTp, classificationFp, classificationFn)
        : null,
    'protected_false_positives': protectedFp,
    'invalid_cases': invalidCases,
    'compile_blocked_cases': blockedCases,
    'effective_cases': effectiveCases,
    'effective_change_cases': effectiveChangeCases,
    'effective_mismatch_cases': mismatchCases,
    'action_metrics': {
      for (final action in <String>[
        'delete_text',
        'remove_block',
        'split_chapter',
        'rename_chapter',
      ])
        action: {
          'tp': actionTpBy[action] ?? 0,
          'fp': actionFpBy[action] ?? 0,
          'fn': actionFnBy[action] ?? 0,
          'precision': _ratio(
            actionTpBy[action] ?? 0,
            (actionTpBy[action] ?? 0) + (actionFpBy[action] ?? 0),
          ),
          'recall': _ratio(
            actionTpBy[action] ?? 0,
            (actionTpBy[action] ?? 0) + (actionFnBy[action] ?? 0),
          ),
        },
    },
  };
  return QualityReport._(
    mode,
    corpus.provenance,
    List<Map<String, Object?>>.unmodifiable(cases),
    summary,
  );
}

List<Chapter> _compile(
  QualityCase qualityCase,
  List<AiTextProposal> texts,
  List<AiChapterSplitProposal> splits,
  Set<String> selectedIds,
) {
  final chapterIds = qualityCase.source.chapters
      .map((chapter) => chapter.id)
      .toSet();
  final blockIds = qualityCase.source.chapters
      .expand((chapter) => chapter.blocks)
      .map((block) => block.id)
      .toSet();
  final identities = <String, AiChapterSplitIdentity>{};
  for (final (index, proposal) in splits.indexed) {
    var suffix = index;
    String chapterId;
    String blockId;
    do {
      chapterId = 'quality-chapter-$suffix';
      blockId = 'quality-block-$suffix';
      suffix++;
    } while (chapterIds.contains(chapterId) || blockIds.contains(blockId));
    chapterIds.add(chapterId);
    blockIds.add(blockId);
    String? volumeId;
    if (proposal.headingLevel == 1) {
      do {
        volumeId = 'quality-volume-$suffix';
        suffix++;
      } while (chapterIds.contains(volumeId));
      chapterIds.add(volumeId);
    }
    identities[proposal.id] = AiChapterSplitIdentity(
      chapterId: chapterId,
      blockId: blockId,
      volumeId: volumeId,
    );
  }
  return AiChangeApplication.compile(
    book: qualityCase.source,
    sessionId: 'quality-session',
    saveSeq: 0,
    textProposals: texts,
    splitProposals: splits,
    selectedIds: selectedIds,
    splitIdentities: identities,
    byteBudget: 8 * 1024 * 1024,
  );
}

bool _matchesIntent(AiProofreadingIntent intent, AiAnalysisResult result) {
  for (final finding in result.findings) {
    if (intent == AiProofreadingIntent.advertisement &&
            finding.kind != FindingKind.advertisement ||
        intent == AiProofreadingIntent.missingChapter &&
            finding.kind != FindingKind.missingChapter) {
      return false;
    }
  }
  return intent == AiProofreadingIntent.advertisement
      ? result.chapterSplits.isEmpty &&
            result.textChanges.proposals.every(
              (proposal) =>
                  proposal.action != AiTextProposalAction.renameChapter,
            )
      : result.textChanges.proposals.every(
          (proposal) => proposal.action == AiTextProposalAction.renameChapter,
        );
}

bool _sameLocation(_Prediction prediction, QualityLabel label) =>
    prediction.chapterId == label.chapterId &&
    prediction.blockId == label.blockId &&
    prediction.start == label.startUtf16 &&
    prediction.end == label.endUtf16;

bool _sameAction(_Prediction prediction, QualityLabel label) =>
    prediction.action == label.action &&
    _sameLocation(prediction, label) &&
    (label.action != 'rename_chapter' ||
        prediction.title == label.title && !prediction.removeTitleLine) &&
    (label.action != 'split_chapter' ||
        prediction.title == label.title &&
            prediction.removeTitleLine == label.removeTitleLine &&
            prediction.headingLevel == label.headingLevel);

String _assessmentWire(FindingAssessment assessment) => switch (assessment) {
  FindingAssessment.undetermined => 'undetermined',
  FindingAssessment.suspectedMissing => 'suspected_missing',
  FindingAssessment.missedHeading => 'missed_heading',
  FindingAssessment.mergedContent => 'merged_content',
  FindingAssessment.numberingSuspect => 'numbering_suspect',
  FindingAssessment.advertisement => 'advertisement',
  FindingAssessment.authorNote => 'author_note',
  FindingAssessment.storyQuote => 'story_quote',
  FindingAssessment.notAdvertisement => 'not_advertisement',
  FindingAssessment.observed => 'observed',
};

Set<String> _assessmentsFor(AiProofreadingIntent intent) =>
    intent == AiProofreadingIntent.advertisement
    ? {
        'undetermined',
        'advertisement',
        'author_note',
        'story_quote',
        'not_advertisement',
      }
    : {
        'undetermined',
        'suspected_missing',
        'missed_heading',
        'merged_content',
        'numbering_suspect',
      };

String _text(Book book, String chapterId, String blockId) =>
    (book.chapters
                .singleWhere((chapter) => chapter.id == chapterId)
                .blocks
                .singleWhere((block) => block.id == blockId)
            as TextBlock)
        .text;

Map<String, Object?> _normalizedBlock(Block block) => switch (block) {
  TextBlock(:final text) => {'kind': 'paragraph', 'text': text},
  ImageBlock(:final id, :final assetId, :final caption, :final alt) => {
    'id': id,
    'kind': 'image',
    'asset_id': assetId,
    'caption': caption,
    'alt': alt,
  },
  FootnoteBlock(:final id, :final text, :final marker) => {
    'id': id,
    'kind': 'footnote',
    'text': text,
    'marker': marker,
  },
  DividerBlock(:final id) => {'id': id, 'kind': 'divider'},
};

Map<String, Object?> _normalizedChapter(Object? value) {
  final chapter = _object(value, {
    'title',
    'level',
    'parent_index',
    'front_matter',
    'blocks',
  });
  final blocks = <Map<String, Object?>>[];
  for (final value in _list(chapter['blocks'], 10000)) {
    final block = _objectAny(value);
    switch (block['kind']) {
      case 'paragraph':
        _keys(block, {'kind', 'text'});
        blocks.add({
          'kind': 'paragraph',
          'text': _string(block, 'text', 32768, empty: true),
        });
      case 'image':
        _keys(block, {'id', 'kind', 'asset_id', 'caption', 'alt'});
        blocks.add({
          'id': _string(block, 'id', 128),
          'kind': 'image',
          'asset_id': _string(block, 'asset_id', 128),
          'caption': _nullableString(block, 'caption', 32768),
          'alt': _string(block, 'alt', 32768, empty: true),
        });
      case 'footnote':
        _keys(block, {'id', 'kind', 'text', 'marker'});
        blocks.add({
          'id': _string(block, 'id', 128),
          'kind': 'footnote',
          'text': _string(block, 'text', 32768, empty: true),
          'marker': _nullableString(block, 'marker', 128),
        });
      case 'divider':
        _keys(block, {'id', 'kind'});
        blocks.add({'id': _string(block, 'id', 128), 'kind': 'divider'});
      default:
        _bad('unknown normalized block kind');
    }
  }
  final parentIndex = chapter['parent_index'];
  if (parentIndex != null && (parentIndex is! int || parentIndex < 0)) {
    _bad('invalid parent_index');
  }
  return {
    'title': _string(chapter, 'title', 512, empty: true),
    'level': _integer(chapter, 'level', 1, 2),
    'parent_index': parentIndex,
    'front_matter': _boolean(chapter, 'front_matter'),
    'blocks': blocks,
  };
}

Map<String, Object?> _object(Object? value, Set<String> keys) {
  final result = _objectAny(value);
  _keys(result, keys);
  return result;
}

Map<String, Object?> _objectWithOptional(
  Object? value,
  Set<String> required,
  Set<String> optional,
) {
  final result = _objectAny(value);
  if (!required.every(result.containsKey) ||
      result.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    _bad('unexpected object fields');
  }
  return result;
}

ProposalTextRange? _evidenceRange(
  Map<String, Object?> label,
  String key,
  String original,
) {
  if (!label.containsKey(key)) return null;
  final value = _object(label[key], {'start_utf16', 'end_utf16'});
  final start = _integer(value, 'start_utf16', 0, original.length);
  final end = _integer(value, 'end_utf16', 1, original.length);
  if (start >= end ||
      !_boundary(original, start) ||
      !_boundary(original, end)) {
    _bad('invalid $key');
  }
  return ProposalTextRange(start, end);
}

Map<String, Object?> _objectAny(Object? value) {
  if (value is! Map<String, dynamic>) _bad('expected object');
  return value;
}

void _keys(Map<String, Object?> value, Set<String> keys) {
  if (value.length != keys.length || !keys.every(value.containsKey)) {
    _bad('unexpected object fields');
  }
}

List<Object?> _list(Object? value, int limit) {
  if (value is! List || value.length > limit) {
    _bad('invalid list or budget exceeded');
  }
  return value;
}

String _string(
  Map<String, Object?> value,
  String key,
  int limit, {
  bool empty = false,
}) {
  final result = value[key];
  if (result is! String ||
      result.length > limit ||
      (!empty && result.trim().isEmpty) ||
      !_validUtf16(result)) {
    _bad('invalid $key');
  }
  return result;
}

String? _nullableString(Map<String, Object?> value, String key, int limit) =>
    value[key] == null ? null : _string(value, key, limit, empty: true);

List<String> _strings(Object? value, int limit, int itemLimit) => [
  for (final item in _list(value, limit))
    _string({'value': item}, 'value', itemLimit),
];

int _integer(Map<String, Object?> value, String key, int min, int max) {
  final result = value[key];
  if (result is! int || result < min || result > max) _bad('invalid $key');
  return result;
}

bool _boolean(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! bool) _bad('invalid $key');
  return result;
}

bool _validUtf16(String value) {
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (++index >= value.length) return false;
      final next = value.codeUnitAt(index);
      if (next < 0xdc00 || next > 0xdfff) return false;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool _boundary(String value, int offset) {
  if (offset == 0 || offset == value.length) return true;
  final previous = value.codeUnitAt(offset - 1);
  final next = value.codeUnitAt(offset);
  return !(previous >= 0xd800 &&
      previous <= 0xdbff &&
      next >= 0xdc00 &&
      next <= 0xdfff);
}

double? _ratio(int numerator, int denominator) =>
    denominator == 0 ? null : numerator / denominator;

double? _f1(int tp, int fp, int fn) =>
    2 * tp + fp + fn == 0 ? null : 2 * tp / (2 * tp + fp + fn);

Object? _strictJson(String raw, int maxLength) {
  if (raw.length > maxLength) _bad('JSON input exceeds budget');
  try {
    final stack = <_QualityJsonFrame>[];
    var cursor = 0;
    while (cursor < raw.length) {
      final code = raw.codeUnitAt(cursor);
      if (code == 0x22) {
        final start = cursor++;
        var closed = false;
        while (cursor < raw.length) {
          final current = raw.codeUnitAt(cursor++);
          if (current == 0x5c) {
            cursor++;
          } else if (current == 0x22) {
            closed = true;
            break;
          }
        }
        if (!closed) _bad('invalid JSON string');
        if (stack.isNotEmpty && stack.last.expectsKey) {
          final frame = stack.last;
          final key = jsonDecode(raw.substring(start, cursor)) as String;
          if (!frame.keys.add(key)) _bad('duplicate JSON key: $key');
          frame.expectsKey = false;
        }
        continue;
      }
      if (code == 0x7b || code == 0x5b) {
        if (stack.length >= 32) _bad('JSON nesting exceeds budget');
        stack.add(_QualityJsonFrame(code == 0x7b));
      } else if (code == 0x7d || code == 0x5d) {
        if (stack.isEmpty || stack.last.isObject != (code == 0x7d)) {
          _bad('invalid JSON nesting');
        }
        stack.removeLast();
      } else if (code == 0x2c && stack.isNotEmpty && stack.last.isObject) {
        stack.last.expectsKey = true;
      }
      cursor++;
    }
    if (stack.isNotEmpty) _bad('incomplete JSON');
    return jsonDecode(raw);
  } on FormatException {
    _bad('invalid JSON');
  }
}

class _QualityJsonFrame {
  _QualityJsonFrame(this.isObject) : expectsKey = isObject;

  final bool isObject;
  bool expectsKey;
  final Set<String> keys = <String>{};
}

Never _bad(String message) => throw FormatException(message);
