import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/editing/rule_heading_mapping.dart';
import 'package:bookloom/core/errors/app_failure.dart';

class AiChapterSplitProposal {
  const AiChapterSplitProposal({
    required this.id,
    required this.target,
    required this.range,
    required this.title,
    required this.removeTitleLine,
    required this.reason,
    this.titleEvidenceRange,
    this.headingLevel = 2,
    this.headingNumber,
    this.numberEvidenceRange,
  });

  final String id;
  final ProposalTextTarget target;
  final ProposalTextRange range;
  final String title;
  final bool removeTitleLine;
  final String reason;
  final ProposalTextRange? titleEvidenceRange;
  final int headingLevel;
  final int? headingNumber;
  final ProposalTextRange? numberEvidenceRange;

  ProposalTextRange titleLineIn(String text, ProposalTextRange located) {
    if (located.start < 0 ||
        (headingLevel != 1 && headingLevel != 2) ||
        located.end > text.length ||
        located.start >= located.end ||
        text.substring(located.start, located.end) != target.originalText ||
        title.trim().isEmpty ||
        title.length > 256 ||
        title != title.trim() ||
        !_titleMatchesSource() ||
        title.contains('\n') ||
        title.contains('\r') ||
        target.originalText.contains('\n') ||
        target.originalText.contains('\r') ||
        !_validUtf16(target.originalText) ||
        !_validUtf16(title) ||
        !_validUtf16(reason)) {
      _invalid();
    }
    final lineStart = located.start == 0
        ? 0
        : text.lastIndexOf('\n', located.start - 1) + 1;
    final nextBreak = text.indexOf('\n', located.end);
    final lineEnd = nextBreak < 0 ? text.length : nextBreak;
    if (text.substring(lineStart, located.start).trim().isNotEmpty ||
        text.substring(located.end, lineEnd).trim().isNotEmpty) {
      _invalid();
    }
    return ProposalTextRange(
      lineStart,
      nextBreak < 0 ? lineEnd : nextBreak + 1,
    );
  }

  bool _titleMatchesSource() {
    final source = titleEvidenceRange;
    final number = headingNumber;
    final numberSource = numberEvidenceRange;
    if (source == null) {
      return number == null &&
          numberSource == null &&
          title == target.originalText.trim();
    }
    if (source.start < 0 ||
        source.end <= source.start ||
        source.end > target.originalText.length) {
      return false;
    }
    final baseTitle = target.originalText.substring(source.start, source.end);
    if (number == null) return numberSource == null && title == baseTitle;
    if (numberSource == null ||
        numberSource.start < 0 ||
        numberSource.end <= numberSource.start ||
        numberSource.end > target.originalText.length ||
        RuleHeadingMapping.parseNumber(
              target.originalText.substring(
                numberSource.start,
                numberSource.end,
              ),
            ) !=
            number) {
      return false;
    }
    return title ==
        RuleHeadingMapping.composeTitle(
          title: baseTitle,
          number: number,
          headingLevel: headingLevel,
        );
  }

  ProposalTextRange textConflictRangeIn(String text) {
    final line = titleLineIn(text, range);
    var start = line.start;
    if (start > 0) {
      start--;
      if (start > 0 && text.codeUnitAt(start - 1) == 13) start--;
    }
    return ProposalTextRange(start, line.end);
  }

  static Never _invalid() =>
      throw const ValidationFailure('拆章提案必须精确定位独立标题行，未修改书稿。');

  static bool _validUtf16(String value) {
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
}

class AiChapterSplitIdentity {
  const AiChapterSplitIdentity({
    required this.chapterId,
    required this.blockId,
    this.volumeId,
  });

  final String chapterId;
  final String blockId;
  final String? volumeId;
}
