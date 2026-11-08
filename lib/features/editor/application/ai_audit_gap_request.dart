import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';

final class AiAuditGapRequest {
  AiAuditGapRequest._({
    required this.bookId,
    required this.sessionId,
    required this.sessionRevision,
    required this.gap,
    required this.beforeTitle,
    required this.afterTitle,
    required List<String> chapterIds,
  }) : chapterIds = List<String>.unmodifiable(chapterIds);

  factory AiAuditGapRequest.fromIssue({
    required AuditIssue issue,
    required Book book,
    required String sessionId,
    required int sessionRevision,
  }) {
    final gap = issue.numberGap;
    if (issue.kind != AuditIssueKind.missingNumber ||
        gap == null ||
        issue.chapterId != gap.afterChapterId ||
        issue.chapterIndex < 0 ||
        issue.chapterIndex >= book.chapters.length ||
        book.chapters[issue.chapterIndex].id != issue.chapterId ||
        book.chapters[issue.chapterIndex].title != issue.chapterTitle) {
      _invalid();
    }
    final chapters = _chapters(book);
    final before = gap.beforeChapterId == null
        ? null
        : chapters[gap.beforeChapterId];
    final after = chapters[gap.afterChapterId];
    if (after == null ||
        after.isVolume ||
        gap.beforeChapterId != null && (before == null || before.isVolume)) {
      _invalid();
    }
    final request = AiAuditGapRequest._(
      bookId: book.id,
      sessionId: sessionId,
      sessionRevision: sessionRevision,
      gap: gap,
      beforeTitle: before?.title,
      afterTitle: after.title,
      chapterIds: [
        for (final chapter in book.chapters)
          if (chapter.id == gap.beforeChapterId ||
              chapter.id == gap.afterChapterId)
            chapter.id,
      ],
    );
    request.validate(
      book: book,
      sessionId: sessionId,
      sessionRevision: sessionRevision,
    );
    return request;
  }

  final String bookId;
  final String sessionId;
  final int sessionRevision;
  final AuditNumberGap gap;
  final String? beforeTitle;
  final String afterTitle;
  final List<String> chapterIds;

  void validate({
    required Book book,
    required String sessionId,
    required int sessionRevision,
  }) {
    if (this.sessionId.isEmpty ||
        this.sessionRevision < 0 ||
        book.id != bookId ||
        this.sessionId != sessionId ||
        this.sessionRevision != sessionRevision) {
      _invalid();
    }
    final chapters = _chapters(book);
    if (chapters[gap.afterChapterId]?.title != afterTitle ||
        (gap.beforeChapterId != null &&
            chapters[gap.beforeChapterId]?.title != beforeTitle) ||
        !Proofreading.numberGaps(book.chapters).any(
          (candidate) =>
              candidate.beforeChapterId == gap.beforeChapterId &&
              candidate.afterChapterId == gap.afterChapterId &&
              candidate.firstMissing == gap.firstMissing &&
              candidate.lastMissing == gap.lastMissing,
        )) {
      _invalid();
    }
  }

  Map<String, Object?> toJson() => {
    'source': 'built_in_missing_number',
    'first_missing': gap.firstMissing,
    'last_missing': gap.lastMissing,
    'before_chapter_id': gap.beforeChapterId,
    'before_title': beforeTitle,
    'after_chapter_id': gap.afterChapterId,
    'after_title': afterTitle,
  };

  static Map<String, Chapter> _chapters(Book book) {
    final chapters = {for (final chapter in book.chapters) chapter.id: chapter};
    if (chapters.length != book.chapters.length ||
        chapters.values.any((chapter) => chapter.bookId != book.id)) {
      _invalid();
    }
    return chapters;
  }

  static Never _invalid() =>
      throw const ValidationFailure('体检断档发现已失效，请重新体检后再分析。');
}
