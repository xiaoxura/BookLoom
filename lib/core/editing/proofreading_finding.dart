import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_json.dart';
import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';

enum FindingSource { builtIn, customRule, ai }

enum FindingKind {
  missingChapter,
  advertisement,
  missedHeading,
  duplicateNumber,
  emptyChapter,
  duplicateTitle,
  longChapter,
  shortChapter,
  emptyVolume,
  other,
}

enum FindingAssessment {
  undetermined,
  suspectedMissing,
  missedHeading,
  mergedContent,
  numberingSuspect,
  advertisement,
  authorNote,
  storyQuote,
  notAdvertisement,
  observed,
}

final class Finding {
  Finding.chapter({
    required this.id,
    required this.bookId,
    required this.sessionId,
    required this.sessionRevision,
    required this.chapterId,
    required this.kind,
    required this.assessment,
    required this.source,
    required this.evidence,
    required this.reason,
    this.blockId,
    this.sourceId,
  }) : target = null,
       range = null {
    _validate();
    if (source == FindingSource.ai) _invalidFinding();
  }

  factory Finding.text({
    required String id,
    required FindingKind kind,
    required FindingAssessment assessment,
    required FindingSource source,
    String? sourceId,
    required ProposalTextTarget target,
    required String currentText,
    required String reason,
  }) {
    final range = target.locate(
      currentBookId: target.bookId,
      currentSessionId: target.sessionId,
      currentSessionRevision: target.sessionRevision,
      currentChapterId: target.chapterId,
      currentBlockId: target.blockId,
      currentText: currentText,
    );
    return Finding._text(
      id,
      kind,
      assessment,
      source,
      sourceId,
      target,
      range,
      reason,
    );
  }

  Finding._text(
    this.id,
    this.kind,
    this.assessment,
    this.source,
    this.sourceId,
    ProposalTextTarget textTarget,
    ProposalTextRange textRange,
    this.reason,
  ) : bookId = textTarget.bookId,
      sessionId = textTarget.sessionId,
      sessionRevision = textTarget.sessionRevision,
      chapterId = textTarget.chapterId,
      blockId = textTarget.blockId,
      evidence = textTarget.originalText,
      target = textTarget,
      range = textRange {
    _validate();
  }

  final String id;
  final String bookId;
  final String sessionId;
  final int sessionRevision;
  final String chapterId;
  final String? blockId;
  final FindingKind kind;
  final FindingAssessment assessment;
  final FindingSource source;
  final String? sourceId;
  final String evidence;
  final String reason;
  final ProposalTextTarget? target;
  final ProposalTextRange? range;

  Finding withId(String newId) => target == null
      ? Finding.chapter(
          id: newId,
          bookId: bookId,
          sessionId: sessionId,
          sessionRevision: sessionRevision,
          chapterId: chapterId,
          kind: kind,
          assessment: assessment,
          source: source,
          evidence: evidence,
          reason: reason,
          blockId: blockId,
          sourceId: sourceId,
        )
      : Finding._text(
          newId,
          kind,
          assessment,
          source,
          sourceId,
          target!,
          range!,
          reason,
        );

  void _validate() {
    if (!_validFindingText(id, 128) ||
        !_validFindingText(bookId, 128) ||
        !_validFindingText(sessionId, 128) ||
        !_validFindingText(chapterId, 128) ||
        sessionRevision < 0 ||
        (blockId != null && !_validFindingText(blockId!, 128)) ||
        (sourceId != null && !_validFindingText(sourceId!, 128)) ||
        (source == FindingSource.customRule && sourceId == null) ||
        !_validFindingText(evidence, 32768, allowEmpty: true) ||
        !_validFindingText(reason, 1024) ||
        !_allowedAssessment(kind, assessment)) {
      _invalidFinding();
    }
  }
}

final class FindingReport {
  FindingReport({required List<Finding> findings, required this.totalCount})
    : findings = List<Finding>.unmodifiable(findings) {
    if (totalCount < findings.length ||
        findings.length > 1000 ||
        findings.map((finding) => finding.id).toSet().length !=
            findings.length) {
      _invalidFinding();
    }
    if (findings.isNotEmpty) {
      final first = findings.first;
      if (findings.any(
        (finding) =>
            finding.bookId != first.bookId ||
            finding.sessionId != first.sessionId ||
            finding.sessionRevision != first.sessionRevision,
      )) {
        _invalidFinding();
      }
    }
  }

  final List<Finding> findings;
  final int totalCount;
  bool get hasMore => totalCount > findings.length;
}

abstract final class AuditFindingAdapter {
  static FindingReport convert({
    required AuditReport report,
    required Book book,
    required String sessionId,
    required int sessionRevision,
  }) {
    final chapters = {for (final chapter in book.chapters) chapter.id: chapter};
    if (chapters.length != book.chapters.length ||
        report.counts.values.any((count) => count < 0) ||
        report.issues.length > 1000) {
      _invalidFinding();
    }
    final findings = <Finding>[];
    final represented = <AuditIssueKind, int>{};
    for (final (index, issue) in report.issues.indexed) {
      final chapter = chapters[issue.chapterId];
      if (chapter == null ||
          chapter.bookId != book.id ||
          issue.chapterIndex < 0 ||
          issue.chapterIndex >= book.chapters.length ||
          book.chapters[issue.chapterIndex].id != chapter.id ||
          issue.chapterTitle != chapter.title) {
        _invalidFinding();
      }
      represented.update(issue.kind, (count) => count + 1, ifAbsent: () => 1);
      if (represented[issue.kind]! > (report.counts[issue.kind] ?? 0)) {
        _invalidFinding();
      }
      var evidence = chapter.title;
      if (issue.blockId != null) {
        final blocks = chapter.blocks.where(
          (block) => block.id == issue.blockId,
        );
        if (blocks.length != 1 || blocks.single is! TextBlock) {
          _invalidFinding();
        }
        evidence = (blocks.single as TextBlock).text;
      }
      final kind = switch (issue.kind) {
        AuditIssueKind.missingNumber => FindingKind.missingChapter,
        AuditIssueKind.duplicateNumber => FindingKind.duplicateNumber,
        AuditIssueKind.emptyChapter => FindingKind.emptyChapter,
        AuditIssueKind.duplicateTitle => FindingKind.duplicateTitle,
        AuditIssueKind.tooLong => FindingKind.longChapter,
        AuditIssueKind.tooShort => FindingKind.shortChapter,
        AuditIssueKind.emptyVolume => FindingKind.emptyVolume,
        AuditIssueKind.adLeftover => FindingKind.advertisement,
        AuditIssueKind.titleFormat => FindingKind.other,
        AuditIssueKind.duplicateContent => FindingKind.other,
      };
      findings.add(
        Finding.chapter(
          id: 'audit-${issue.kind.name}-$index',
          bookId: book.id,
          sessionId: sessionId,
          sessionRevision: sessionRevision,
          chapterId: chapter.id,
          blockId: issue.blockId,
          kind: kind,
          assessment:
              kind == FindingKind.missingChapter ||
                  kind == FindingKind.advertisement
              ? FindingAssessment.undetermined
              : FindingAssessment.observed,
          source: FindingSource.builtIn,
          sourceId: 'audit.${issue.kind.name}',
          evidence: _findingExcerpt(evidence),
          reason: issue.message,
        ),
      );
    }
    return FindingReport(findings: findings, totalCount: report.total);
  }
}

abstract final class AiFindingDecoder {
  static List<Finding> decode(
    String response, {
    required AiContextChunk context,
  }) {
    if (response.length > 65536) _invalidFinding();
    final Object? decoded;
    try {
      decoded = decodeStrictAiJson(response);
    } on FormatException {
      _invalidFinding();
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['schema_version'] is! int ||
        decoded['schema_version'] != 1 ||
        decoded['findings'] is! List) {
      _invalidFinding();
    }
    final values = decoded['findings'] as List;
    if (values.length > 100) _invalidFinding();
    final slices = {
      for (final slice in context.slices) slice.block.blockId: slice,
    };
    if (slices.length != context.slices.length) _invalidFinding();
    final ids = <String>{};
    final findings = <Finding>[];
    for (final value in values) {
      const keys = {
        'id',
        'category',
        'assessment',
        'chapter_id',
        'block_id',
        'original',
        'before',
        'after',
        'reason',
      };
      if (value is! Map<String, dynamic> ||
          value.length != keys.length ||
          !keys.every(value.containsKey)) {
        _invalidFinding();
      }
      String field(String key, int limit, {bool allowEmpty = false}) {
        final text = value[key];
        if (text is! String ||
            !_validFindingText(text, limit, allowEmpty: allowEmpty)) {
          _invalidFinding();
        }
        return text;
      }

      final id = field('id', 128);
      if (!ids.add(id)) _invalidFinding();
      final kind = switch (field('category', 32)) {
        'missing_chapter' => FindingKind.missingChapter,
        'advertisement' => FindingKind.advertisement,
        'other' => FindingKind.other,
        _ => _invalidFinding(),
      };
      final assessment = switch (field('assessment', 32)) {
        'undetermined' => FindingAssessment.undetermined,
        'suspected_missing' => FindingAssessment.suspectedMissing,
        'missed_heading' => FindingAssessment.missedHeading,
        'merged_content' => FindingAssessment.mergedContent,
        'numbering_suspect' => FindingAssessment.numberingSuspect,
        'advertisement' => FindingAssessment.advertisement,
        'author_note' => FindingAssessment.authorNote,
        'story_quote' => FindingAssessment.storyQuote,
        'not_advertisement' => FindingAssessment.notAdvertisement,
        'observed' => FindingAssessment.observed,
        _ => _invalidFinding(),
      };
      final chapterId = field('chapter_id', 128);
      final blockId = field('block_id', 128);
      final slice = slices[blockId];
      if (slice == null || slice.block.chapterId != chapterId) {
        _invalidFinding();
      }
      final target = ProposalTextTarget(
        bookId: context.bookId,
        sessionId: context.sessionId,
        sessionRevision: context.sessionRevision,
        chapterId: chapterId,
        blockId: blockId,
        originalText: field('original', 32768),
        before: field('before', 1024, allowEmpty: true),
        after: field('after', 1024, allowEmpty: true),
      );
      final finding = Finding.text(
        id: id,
        kind: kind,
        assessment: assessment,
        source: FindingSource.ai,
        target: target,
        currentText: slice.block.text,
        reason: field('reason', 1024),
      );
      final range = finding.range!;
      if (range.start < slice.startUtf16 ||
          range.end > slice.endUtf16 ||
          range.start - target.before.length <
              slice.startUtf16 - slice.before.length ||
          range.end + target.after.length >
              slice.endUtf16 + slice.after.length) {
        _invalidFinding();
      }
      findings.add(finding);
    }
    return List<Finding>.unmodifiable(findings);
  }
}

bool _allowedAssessment(FindingKind kind, FindingAssessment assessment) {
  if (assessment == FindingAssessment.undetermined) return true;
  return switch (kind) {
    FindingKind.missingChapter => const {
      FindingAssessment.suspectedMissing,
      FindingAssessment.missedHeading,
      FindingAssessment.mergedContent,
      FindingAssessment.numberingSuspect,
    }.contains(assessment),
    FindingKind.advertisement => const {
      FindingAssessment.advertisement,
      FindingAssessment.authorNote,
      FindingAssessment.storyQuote,
      FindingAssessment.notAdvertisement,
    }.contains(assessment),
    _ => assessment == FindingAssessment.observed,
  };
}

bool _validFindingText(String value, int limit, {bool allowEmpty = false}) {
  if (value.length > limit || (!allowEmpty && value.trim().isEmpty)) {
    return false;
  }
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= value.length) return false;
      final next = value.codeUnitAt(index);
      if (next < 0xdc00 || next > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

String _findingExcerpt(String text) {
  var end = text.length > 1024 ? 1024 : text.length;
  if (end > 0 &&
      end < text.length &&
      text.codeUnitAt(end - 1) >= 0xd800 &&
      text.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  return text.substring(0, end);
}

Never _invalidFinding() =>
    throw const ValidationFailure('校对发现项验证失败，未修改书稿；请重新扫描或缩小范围。');
