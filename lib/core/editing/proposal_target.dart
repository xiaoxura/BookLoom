import 'package:bookloom/core/ai/ai_limits.dart';
import 'package:bookloom/core/errors/app_failure.dart';

class ProposalTextTarget {
  const ProposalTextTarget({
    required this.bookId,
    required this.sessionId,
    required this.sessionRevision,
    required this.chapterId,
    required this.blockId,
    required this.originalText,
    this.before = '',
    this.after = '',
  });

  final String bookId;
  final String sessionId;
  final int sessionRevision;
  final String chapterId;
  final String blockId;
  final String originalText;
  final String before;
  final String after;

  ProposalTextRange locate({
    required String currentBookId,
    required String currentSessionId,
    required int currentSessionRevision,
    required String currentChapterId,
    required String currentBlockId,
    required String currentText,
  }) {
    if (bookId.isEmpty ||
        sessionId.isEmpty ||
        chapterId.isEmpty ||
        blockId.isEmpty ||
        sessionRevision < 0 ||
        bookId != currentBookId ||
        sessionId != currentSessionId ||
        sessionRevision != currentSessionRevision ||
        chapterId != currentChapterId ||
        blockId != currentBlockId) {
      throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
    }
    if (originalText.isEmpty ||
        originalText.length > 65536 ||
        before.length > 1024 ||
        after.length > 1024 ||
        currentText.length > aiMaxContextCharacters) {
      throw const ValidationFailure('提案定位超出单块验证范围，请缩小分析范围。');
    }

    int? matchedStart;
    var cursor = 0;
    while (cursor <= currentText.length - originalText.length) {
      final start = currentText.indexOf(originalText, cursor);
      if (start < 0) break;
      final end = start + originalText.length;
      final contextStart = start - before.length;
      final contextEnd = end + after.length;
      if (_isBoundary(currentText, start) &&
          _isBoundary(currentText, end) &&
          contextStart >= 0 &&
          contextEnd <= currentText.length &&
          _isBoundary(currentText, contextStart) &&
          _isBoundary(currentText, contextEnd) &&
          currentText.substring(contextStart, start) == before &&
          currentText.substring(end, contextEnd) == after) {
        if (matchedStart != null) {
          throw const ValidationFailure('提案原文存在多处匹配，请补充定位上下文。');
        }
        matchedStart = start;
      }
      cursor = start + 1;
    }
    if (matchedStart == null) {
      throw const ValidationFailure('提案原文与当前书稿不符，请重新分析。');
    }
    return ProposalTextRange(matchedStart, matchedStart + originalText.length);
  }
}

class ProposalTextRange {
  const ProposalTextRange(this.start, this.end);

  final int start;
  final int end;

  bool overlaps(ProposalTextRange other) =>
      start < other.end && other.start < end;
}

bool _isBoundary(String text, int offset) {
  if (offset == 0 || offset == text.length) return true;
  final previous = text.codeUnitAt(offset - 1);
  final next = text.codeUnitAt(offset);
  return !(previous >= 0xd800 &&
      previous <= 0xdbff &&
      next >= 0xdc00 &&
      next <= 0xdfff);
}
