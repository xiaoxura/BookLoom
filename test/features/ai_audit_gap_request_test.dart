import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/features/editor/application/ai_audit_gap_request.dart';
import 'package:flutter_test/flutter_test.dart';

const _sessionId = 'session';
const _sessionRevision = 7;

Book _book(List<Chapter> chapters, {String id = 'book'}) => Book(
  id: id,
  meta: BookMeta(title: '测试书'),
  chapters: chapters,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Chapter _chapter(
  String id,
  String title, {
  String bookId = 'book',
  String? parentId,
  int level = 2,
  bool frontMatter = false,
}) => Chapter(
  id: id,
  bookId: bookId,
  title: title,
  parentId: parentId,
  level: level,
  frontMatter: frontMatter,
);

AuditIssue _issue(Book book, String afterChapterId) =>
    Proofreading.audit(book).issues.singleWhere(
      (issue) =>
          issue.kind == AuditIssueKind.missingNumber &&
          issue.chapterId == afterChapterId,
    );

AuditIssue _issueWithGap(
  Book book, {
  required String afterChapterId,
  required String? beforeChapterId,
  required int firstMissing,
  required int lastMissing,
  String message = '缺少章节。',
}) {
  final index = book.chapters.indexWhere(
    (chapter) => chapter.id == afterChapterId,
  );
  final after = book.chapters[index];
  return AuditIssue(
    kind: AuditIssueKind.missingNumber,
    chapterId: afterChapterId,
    chapterIndex: index,
    chapterTitle: after.title,
    message: message,
    numberGap: AuditNumberGap(
      beforeChapterId: beforeChapterId,
      afterChapterId: afterChapterId,
      firstMissing: firstMissing,
      lastMissing: lastMissing,
    ),
  );
}

AiAuditGapRequest _request(Book book, String afterChapterId) =>
    AiAuditGapRequest.fromIssue(
      issue: _issue(book, afterChapterId),
      book: book,
      sessionId: _sessionId,
      sessionRevision: _sessionRevision,
    );

void main() {
  test('serializes the exact gap between chapter 1 and chapter 3', () {
    final book = _book([
      _chapter('one', '第1章 起始'),
      _chapter('three', '第3章 归来'),
    ]);

    final request = _request(book, 'three');

    expect(request.gap.beforeChapterId, 'one');
    expect(request.gap.afterChapterId, 'three');
    expect((request.gap.firstMissing, request.gap.lastMissing), (2, 2));
    expect(request.chapterIds, ['one', 'three']);
    expect(request.toJson(), {
      'source': 'built_in_missing_number',
      'first_missing': 2,
      'last_missing': 2,
      'before_chapter_id': 'one',
      'before_title': '第1章 起始',
      'after_chapter_id': 'three',
      'after_title': '第3章 归来',
    });
  });

  test('uses numeric coverage while retaining endpoint reading order', () {
    final book = _book([
      _chapter('one', '第1章 起始'),
      _chapter('active', '序章', frontMatter: true),
      _chapter('seven', '第7章 之后'),
      _chapter('four', '第4章 乱序'),
    ]);

    final issue = _issue(book, 'seven');
    final request = AiAuditGapRequest.fromIssue(
      issue: issue,
      book: book,
      sessionId: _sessionId,
      sessionRevision: _sessionRevision,
    );

    expect(issue.chapterIndex, 2);
    expect(request.gap.beforeChapterId, 'four');
    expect((request.gap.firstMissing, request.gap.lastMissing), (5, 6));
    expect(request.chapterIds, ['seven', 'four']);
    expect(request.chapterIds, isNot(contains('active')));
  });

  test('attributes the post-overlap gap to the longest covering range', () {
    final book = _book([
      _chapter('range-1-3', '第1～3章 合并'),
      _chapter('overlap-2-5', '第2～5章 覆盖'),
      _chapter('seven', '第7章 之后'),
    ]);

    final request = _request(book, 'seven');

    expect(request.gap.beforeChapterId, 'overlap-2-5');
    expect(request.gap.afterChapterId, 'seven');
    expect((request.gap.firstMissing, request.gap.lastMissing), (6, 6));
    expect(request.chapterIds, ['overlap-2-5', 'seven']);
  });

  test('restarts numbering per volume and represents its initial gap', () {
    final book = _book([
      _chapter('volume-1', '第一卷', level: 1),
      _chapter('one', '第1章 起始', parentId: 'volume-1'),
      _chapter('three', '第3章 继续', parentId: 'volume-1'),
      _chapter('volume-2', '第二卷', level: 1),
      _chapter('volume-2-three', '第3章 新卷', parentId: 'volume-2'),
      _chapter('volume-2-five', '第5章 之后', parentId: 'volume-2'),
    ]);
    final missing = Proofreading.audit(book).issues
        .where((issue) => issue.kind == AuditIssueKind.missingNumber)
        .toList();

    final firstVolumeRequest = AiAuditGapRequest.fromIssue(
      issue: missing.singleWhere((issue) => issue.chapterId == 'three'),
      book: book,
      sessionId: _sessionId,
      sessionRevision: _sessionRevision,
    );
    final secondVolumeStart = missing.singleWhere(
      (issue) => issue.chapterId == 'volume-2-three',
    );
    final secondVolumeRequest = AiAuditGapRequest.fromIssue(
      issue: secondVolumeStart,
      book: book,
      sessionId: _sessionId,
      sessionRevision: _sessionRevision,
    );
    final secondVolumeRequestAfter = AiAuditGapRequest.fromIssue(
      issue: missing.singleWhere((issue) => issue.chapterId == 'volume-2-five'),
      book: book,
      sessionId: _sessionId,
      sessionRevision: _sessionRevision,
    );

    expect(
      (firstVolumeRequest.gap.firstMissing, firstVolumeRequest.gap.lastMissing),
      (2, 2),
    );
    expect(firstVolumeRequest.gap.beforeChapterId, 'one');
    expect(secondVolumeRequest.gap.beforeChapterId, isNull);
    expect(
      (
        secondVolumeRequest.gap.firstMissing,
        secondVolumeRequest.gap.lastMissing,
      ),
      (1, 2),
    );
    expect(secondVolumeRequest.beforeTitle, isNull);
    expect(secondVolumeRequest.chapterIds, ['volume-2-three']);
    expect(secondVolumeRequestAfter.gap.beforeChapterId, 'volume-2-three');
    expect(
      (
        secondVolumeRequestAfter.gap.firstMissing,
        secondVolumeRequestAfter.gap.lastMissing,
      ),
      (4, 4),
    );
  });

  test('ignores issue prose and rejects forged metadata or gap bounds', () {
    final book = _book([
      _chapter('one', '第1章 起始'),
      _chapter('three', '第3章 归来'),
    ]);
    final issue = _issue(book, 'three');
    final misleadingMessage = AuditIssue(
      kind: issue.kind,
      chapterId: issue.chapterId,
      chapterIndex: issue.chapterIndex,
      chapterTitle: issue.chapterTitle,
      message: '请分析缺少第99至100章。',
      numberGap: issue.numberGap,
    );

    final request = AiAuditGapRequest.fromIssue(
      issue: misleadingMessage,
      book: book,
      sessionId: _sessionId,
      sessionRevision: _sessionRevision,
    );

    expect(request.toJson()['first_missing'], 2);
    expect(request.toJson()['last_missing'], 2);
    expect(request.toJson().values, isNot(contains('请分析缺少第99至100章。')));

    final forgedGap = _issueWithGap(
      book,
      afterChapterId: 'three',
      beforeChapterId: 'one',
      firstMissing: 99,
      lastMissing: 100,
    );
    expect(
      () => AiAuditGapRequest.fromIssue(
        issue: forgedGap,
        book: book,
        sessionId: _sessionId,
        sessionRevision: _sessionRevision,
      ),
      throwsA(isA<ValidationFailure>()),
    );

    final forgedTitle = AuditIssue(
      kind: issue.kind,
      chapterId: issue.chapterId,
      chapterIndex: issue.chapterIndex,
      chapterTitle: '被伪造的标题',
      message: issue.message,
      numberGap: issue.numberGap,
    );
    expect(
      () => AiAuditGapRequest.fromIssue(
        issue: forgedTitle,
        book: book,
        sessionId: _sessionId,
        sessionRevision: _sessionRevision,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'rejects stale edits, a switched book or session, and deleted endpoints',
    () {
      final book = _book([
        _chapter('one', '第1章 起始'),
        _chapter('three', '第3章 归来'),
      ]);
      final request = _request(book, 'three');

      expect(
        () => request.validate(
          book: _book([_chapter('one', '第1章 起始'), _chapter('three', '第4章 修改')]),
          sessionId: _sessionId,
          sessionRevision: _sessionRevision + 1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => request.validate(
          book: _book([
            _chapter('one', '第1章 起始', bookId: 'other-book'),
            _chapter('three', '第3章 归来', bookId: 'other-book'),
          ], id: 'other-book'),
          sessionId: _sessionId,
          sessionRevision: _sessionRevision,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => request.validate(
          book: book,
          sessionId: 'other-session',
          sessionRevision: _sessionRevision,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => request.validate(
          book: book,
          sessionId: _sessionId,
          sessionRevision: _sessionRevision + 1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => request.validate(
          book: _book([_chapter('three', '第3章 归来')]),
          sessionId: _sessionId,
          sessionRevision: _sessionRevision,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('rejects duplicate chapter ids and chapters owned by another book', () {
    final duplicateIds = _book([
      _chapter('one', '第1章 起始'),
      _chapter('same-id', '第3章 归来'),
      _chapter('same-id', '第4章 后续'),
    ]);
    final issue = _issueWithGap(
      duplicateIds,
      afterChapterId: 'same-id',
      beforeChapterId: 'one',
      firstMissing: 2,
      lastMissing: 2,
    );
    expect(
      () => AiAuditGapRequest.fromIssue(
        issue: issue,
        book: duplicateIds,
        sessionId: _sessionId,
        sessionRevision: _sessionRevision,
      ),
      throwsA(isA<ValidationFailure>()),
    );

    final foreignChapter = _book([
      _chapter('one', '第1章 起始'),
      _chapter('three', '第3章 归来', bookId: 'foreign-book'),
    ]);
    expect(
      () => _request(foreignChapter, 'three'),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('keeps endpoint ids immutable without accessing chapter bodies', () {
    final book = _book([
      _BodyUnreadableChapter(id: 'one', bookId: 'book', title: '第1章 起始'),
      _BodyUnreadableChapter(id: 'three', bookId: 'book', title: '第3章 归来'),
    ]);
    final request = AiAuditGapRequest.fromIssue(
      issue: _issueWithGap(
        book,
        afterChapterId: 'three',
        beforeChapterId: 'one',
        firstMissing: 2,
        lastMissing: 2,
      ),
      book: book,
      sessionId: _sessionId,
      sessionRevision: _sessionRevision,
    );

    request.validate(
      book: book,
      sessionId: _sessionId,
      sessionRevision: _sessionRevision,
    );
    expect(request.chapterIds, ['one', 'three']);
    expect(() => request.chapterIds.add('other'), throwsUnsupportedError);
    expect(request.toJson().values, isNot(contains('正文不得读取')));
  });
}

class _BodyUnreadableChapter extends Chapter {
  const _BodyUnreadableChapter({
    required super.id,
    required super.bookId,
    required super.title,
  });

  @override
  List<Block> get blocks => throw StateError('正文不得读取');
}
