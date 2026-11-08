import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

ProposalTextTarget target({
  String original = '广告',
  String before = '',
  String after = '',
}) => ProposalTextTarget(
  bookId: 'book',
  sessionId: 'session',
  sessionRevision: 3,
  chapterId: 'chapter',
  blockId: 'block',
  originalText: original,
  before: before,
  after: after,
);

ProposalTextRange locate(
  ProposalTextTarget proposal,
  String text, {
  String bookId = 'book',
  String sessionId = 'session',
  int revision = 3,
  String chapterId = 'chapter',
  String blockId = 'block',
}) => proposal.locate(
  currentBookId: bookId,
  currentSessionId: sessionId,
  currentSessionRevision: revision,
  currentChapterId: chapterId,
  currentBlockId: blockId,
  currentText: text,
);

void main() {
  test('locates exact text with UTF-16 offsets across emoji and newline', () {
    final range = locate(target(), '😀正文\n广告完');
    expect(range.start, 5);
    expect(range.end, 7);
    expect('😀正文\n广告完'.substring(range.start, range.end), '广告');
  });

  test('rejects ambiguous repeated and overlapping matches', () {
    expect(() => locate(target(), '广告和广告'), throwsA(isA<ValidationFailure>()));
    expect(
      () => locate(target(original: '哈哈'), '哈哈哈'),
      throwsA(isA<ValidationFailure>()),
    );
    final range = locate(target(before: '和', after: '。'), '广告和广告。');
    expect(range.start, 3);
    expect(range.end, 5);
  });

  test('does not relocate across books, sessions, revisions or block IDs', () {
    for (final attempt in <ProposalTextRange Function()>[
      () => locate(target(), '广告', bookId: 'other'),
      () => locate(target(), '广告', sessionId: 'reopened-session'),
      () => locate(target(), '广告', revision: 4),
      () => locate(target(), '广告', chapterId: 'other'),
      () => locate(target(), '广告', blockId: 'other'),
    ]) {
      expect(attempt, throwsA(isA<ValidationFailure>()));
    }
  });

  test('rejects missing or edited source rather than fuzzy matching', () {
    expect(() => locate(target(), '广 告'), throwsA(isA<ValidationFailure>()));
    expect(
      () => locate(target(before: '前'), '后广告'),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('rejects splitting UTF-16 surrogate pairs in text or context', () {
    final lowSurrogate = String.fromCharCode(0xde00);
    expect(
      () => locate(target(original: lowSurrogate), '😀'),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => locate(target(before: lowSurrogate), '😀广告'),
      throwsA(isA<ValidationFailure>()),
    );
    final range = locate(target(original: '😀'), '前😀后');
    expect(range.start, 1);
    expect(range.end, 3);
  });

  test('has bounded validation and does not echo private source in errors', () {
    for (final proposal in <ProposalTextTarget>[
      target(original: ''),
      target(original: '密' * 65537),
      target(before: '密' * 1025),
      target(after: '密' * 1025),
    ]) {
      expect(() => locate(proposal, '广告'), throwsA(isA<ValidationFailure>()));
    }
    expect(
      () => locate(target(), '密' * 2097153),
      throwsA(isA<ValidationFailure>()),
    );
    try {
      locate(target(original: '秘密正文'), '其他');
      fail('Expected validation failure');
    } on ValidationFailure catch (error) {
      expect(error.toString(), isNot(contains('秘密正文')));
    }
  });

  test('adjacent half-open ranges do not conflict', () {
    const first = ProposalTextRange(0, 2);
    expect(first.overlaps(const ProposalTextRange(1, 3)), isTrue);
    expect(first.overlaps(const ProposalTextRange(2, 4)), isFalse);
    expect(first.overlaps(const ProposalTextRange(0, 2)), isTrue);
  });
}
