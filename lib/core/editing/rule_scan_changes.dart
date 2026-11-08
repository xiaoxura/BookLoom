import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_scan.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/editing/rule_heading_mapping.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';

final class RuleScanChangeSet {
  RuleScanChangeSet({
    required List<AiTextProposal> textProposals,
    required List<AiChapterSplitProposal> splitProposals,
    required Set<String> selectedIds,
  }) : textProposals = List<AiTextProposal>.unmodifiable(textProposals),
       splitProposals = List<AiChapterSplitProposal>.unmodifiable(
         splitProposals,
       ),
       selectedIds = Set<String>.unmodifiable(selectedIds);

  final List<AiTextProposal> textProposals;
  final List<AiChapterSplitProposal> splitProposals;
  final Set<String> selectedIds;
}

final class RuleScanChangeDescription {
  const RuleScanChangeDescription({
    required this.headingTitle,
    required this.titleLine,
    required this.sourceTextBefore,
    required this.sourceTextAfter,
    this.headingLevel = 2,
    this.headingNumber,
  });

  final String? headingTitle;
  final String? titleLine;
  final String sourceTextBefore;
  final String sourceTextAfter;
  final int headingLevel;
  final int? headingNumber;
}

abstract final class RuleScanChanges {
  static bool supportsHeadingLineEnding(String text, int lineEnd) =>
      lineEnd >= 0 &&
      lineEnd <= text.length &&
      (lineEnd == text.length ||
          text.codeUnitAt(lineEnd) != 13 ||
          lineEnd + 1 < text.length && text.codeUnitAt(lineEnd + 1) == 10);

  static RuleScanChangeSet build({
    required Book snapshot,
    required String sessionId,
    required int saveSeq,
    required List<RuleScanMatch> selectedMatches,
  }) {
    if (snapshot.id.isEmpty ||
        sessionId.isEmpty ||
        sessionId.length > 128 ||
        saveSeq < 0 ||
        selectedMatches.isEmpty ||
        selectedMatches.length > 100) {
      throw const ValidationFailure('请选择 1 至 100 条有效规则命中。');
    }
    final textProposals = <AiTextProposal>[];
    final splitProposals = <AiChapterSplitProposal>[];
    final selectedIds = <String>{};
    final splitLines = <String, ProposalTextRange>{};

    for (final (index, match) in selectedMatches.indexed) {
      if (match.action == ProofreadingRuleAction.advertisementCandidate) {
        throw const ValidationFailure('广告候选仅供核对，不能作为删除操作执行。');
      }
      final resolved = _resolve(snapshot, match);
      final text = resolved.text;
      final id = 'rule-change-$index';
      final originalRange = ProposalTextRange(match.startUtf16, match.endUtf16);
      final range = match.action == ProofreadingRuleAction.chapterCandidate
          ? _headingRange(
              text,
              resolved.line,
              originalRange,
              mapped: match.mappedTitle != null,
            )
          : originalRange;
      final target = ProposalTextTarget(
        bookId: snapshot.id,
        sessionId: sessionId,
        sessionRevision: saveSeq,
        chapterId: match.chapterId,
        blockId: match.blockId,
        originalText: text.substring(range.start, range.end),
        before: text.substring(_contextStart(text, range.start), range.start),
        after: text.substring(range.end, _contextEnd(text, range.end)),
      );
      final located = target.locate(
        currentBookId: snapshot.id,
        currentSessionId: sessionId,
        currentSessionRevision: saveSeq,
        currentChapterId: match.chapterId,
        currentBlockId: match.blockId,
        currentText: text,
      );
      if (located.start != range.start || located.end != range.end) {
        throw const ValidationFailure('规则命中定位不唯一或已失效，请重新试跑。');
      }
      if (match.action == ProofreadingRuleAction.exactDeletion) {
        for (final previous in textProposals) {
          if (previous.target.blockId == match.blockId &&
              previous.range.overlaps(range)) {
            _conflict();
          }
        }
        for (final previous in splitProposals) {
          if (previous.target.blockId == match.blockId &&
              range.overlaps(previous.textConflictRangeIn(text))) {
            _conflict();
          }
        }
        textProposals.add(
          AiTextProposal(
            id: id,
            action: AiTextProposalAction.deleteText,
            target: target,
            range: range,
            replacement: '',
            reason: '规则精确删除',
          ),
        );
      } else {
        final title = _headingTitle(text, match, range);
        final titleOffset = match.mappedTitle == null
            ? null
            : text.indexOf(match.mappedTitle!, match.startUtf16) - range.start;
        final numberText = match.numberText;
        final numberOffset = numberText == null
            ? null
            : text.indexOf(numberText, match.startUtf16) - range.start;
        final proposal = AiChapterSplitProposal(
          id: id,
          target: target,
          range: range,
          title: title,
          removeTitleLine: true,
          reason: match.headingLevel == 1 ? '规则识别独立卷标题行' : '规则识别独立标题行',
          headingLevel: match.headingLevel,
          headingNumber: match.mappedNumber,
          numberEvidenceRange: numberOffset == null
              ? null
              : ProposalTextRange(
                  numberOffset,
                  numberOffset + numberText!.length,
                ),
          titleEvidenceRange: titleOffset == null
              ? null
              : ProposalTextRange(
                  titleOffset,
                  titleOffset + match.mappedTitle!.length,
                ),
        );
        final fullLine = proposal.titleLineIn(text, range);
        for (final previous in splitProposals) {
          if (previous.target.blockId == match.blockId &&
              splitLines[previous.id]!.overlaps(fullLine)) {
            _conflict();
          }
        }
        for (final previous in textProposals) {
          if (previous.target.blockId == match.blockId &&
              previous.range.overlaps(proposal.textConflictRangeIn(text))) {
            _conflict();
          }
        }
        splitLines[id] = fullLine;
        splitProposals.add(proposal);
      }
      selectedIds.add(id);
    }
    return RuleScanChangeSet(
      textProposals: textProposals,
      splitProposals: splitProposals,
      selectedIds: selectedIds,
    );
  }

  static RuleScanChangeDescription describe(
    Book snapshot,
    RuleScanMatch match,
  ) {
    final resolved = _resolve(snapshot, match);
    final text = resolved.text;
    if (match.action == ProofreadingRuleAction.chapterCandidate) {
      final range = _headingRange(
        text,
        resolved.line,
        ProposalTextRange(match.startUtf16, match.endUtf16),
        mapped: match.mappedTitle != null,
      );
      return RuleScanChangeDescription(
        headingTitle: _headingTitle(text, match, range),
        titleLine: text.substring(resolved.line.start, resolved.line.end),
        sourceTextBefore: text,
        sourceTextAfter: text.replaceRange(
          resolved.line.start,
          resolved.line.terminatedEnd,
          '',
        ),
        headingLevel: match.headingLevel,
        headingNumber: match.mappedNumber,
      );
    }
    return RuleScanChangeDescription(
      headingTitle: null,
      titleLine: null,
      sourceTextBefore: text,
      sourceTextAfter: match.action == ProofreadingRuleAction.exactDeletion
          ? text.replaceRange(match.startUtf16, match.endUtf16, '')
          : text,
    );
  }

  static Never _conflict() =>
      throw const ValidationFailure('所选规则命中范围冲突，请取消冲突项后重试。');
}

String _headingTitle(
  String text,
  RuleScanMatch match,
  ProposalTextRange headingRange,
) {
  final baseTitle = _headingBaseTitle(text, match, headingRange);
  final number = match.mappedNumber;
  return number == null
      ? baseTitle
      : RuleHeadingMapping.composeTitle(
          title: baseTitle,
          number: number,
          headingLevel: match.headingLevel,
        );
}

String _headingBaseTitle(
  String text,
  RuleScanMatch match,
  ProposalTextRange headingRange,
) {
  final title = match.mappedTitle;
  if (title == null) {
    return text.substring(headingRange.start, headingRange.end);
  }
  final offset = text.indexOf(title, match.startUtf16);
  if (title.isEmpty ||
      title.length > 256 ||
      title != title.trim() ||
      title.contains('\n') ||
      title.contains('\r') ||
      offset < match.startUtf16 ||
      offset + title.length > match.endUtf16 ||
      !_isBoundary(text, offset) ||
      !_isBoundary(text, offset + title.length)) {
    _stale();
  }
  return title;
}

_ResolvedMatch _resolve(Book snapshot, RuleScanMatch match) {
  if ((match.headingLevel != 1 && match.headingLevel != 2) ||
      (match.mappedTitle != null ||
              match.headingLevel != 2 ||
              match.mappedNumber != null ||
              match.numberText != null) &&
          match.action != ProofreadingRuleAction.chapterCandidate) {
    _stale();
  }
  final chapters = snapshot.chapters.where(
    (chapter) =>
        chapter.id == match.chapterId &&
        chapter.bookId == snapshot.id &&
        !chapter.isVolume,
  );
  if (chapters.length != 1 || chapters.single.title != match.chapterTitle) {
    _stale();
  }
  final blocks = chapters.single.blocks.where(
    (block) => block.id == match.blockId,
  );
  if (blocks.length != 1 || blocks.single is! TextBlock) _stale();
  final text = (blocks.single as TextBlock).text;
  final numberText = match.numberText;
  final number = match.mappedNumber;
  if ((number == null) != (numberText == null)) _stale();
  if (numberText != null) {
    if (match.mappedTitle == null ||
        numberText != numberText.trim() ||
        RuleHeadingMapping.parseNumber(numberText) != number) {
      _stale();
    }
  }
  final start = match.startUtf16;
  final end = match.endUtf16;
  if (start < 0 ||
      end <= start ||
      end > text.length ||
      !_isBoundary(text, start) ||
      !_isBoundary(text, end)) {
    _stale();
  }
  if (numberText != null) {
    final numberOffset = text.indexOf(numberText, start);
    if (numberOffset < start ||
        numberOffset + numberText.length > end ||
        !_isBoundary(text, numberOffset) ||
        !_isBoundary(text, numberOffset + numberText.length)) {
      _stale();
    }
  }
  final line = _lineAt(text, start);
  var excerptEnd = end < start + 160 ? end : start + 160;
  if (excerptEnd < end && !_isBoundary(text, excerptEnd)) excerptEnd--;
  if (match.lineNumber != line.number ||
      match.excerpt != text.substring(start, excerptEnd) ||
      match.before != text.substring(_contextStart(text, start, 80), start) ||
      match.after != text.substring(end, _contextEnd(text, end, 80))) {
    _stale();
  }
  return _ResolvedMatch(text, line);
}

ProposalTextRange _headingRange(
  String text,
  _SourceLine line,
  ProposalTextRange matchRange, {
  bool mapped = false,
}) {
  if (matchRange.end > line.end || matchRange.start < line.start) {
    throw const ValidationFailure('章节候选跨越正文行，无法作为标题拆章。');
  }
  final raw = text.substring(line.start, line.end);
  if (!RuleScanChanges.supportsHeadingLineEnding(text, line.end)) {
    throw const ValidationFailure('孤立 CR 标题行暂不支持拆章，请调整换行格式后重试。');
  }
  final title = raw.trim();
  if (title.isEmpty ||
      title.length > (mapped ? 32768 : 256) ||
      title.contains('\r') ||
      title.contains('\n')) {
    throw const ValidationFailure('章节候选所在标题行无效或过长。');
  }
  final start = line.start + raw.length - raw.trimLeft().length;
  return ProposalTextRange(start, start + title.length);
}

_SourceLine _lineAt(String text, int offset) {
  var start = 0;
  var number = 1;
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (unit != 10 && unit != 13) continue;
    var nextStart = index + 1;
    if (unit == 13 &&
        nextStart < text.length &&
        text.codeUnitAt(nextStart) == 10) {
      nextStart++;
    }
    if (offset < nextStart) return _SourceLine(number, start, index, nextStart);
    start = nextStart;
    number++;
    index = nextStart - 1;
  }
  return _SourceLine(number, start, text.length, text.length);
}

int _contextStart(String text, int start, [int limit = 1024]) {
  var offset = start > limit ? start - limit : 0;
  if (!_isBoundary(text, offset)) offset++;
  return offset;
}

int _contextEnd(String text, int end, [int limit = 1024]) {
  var offset = end + limit < text.length ? end + limit : text.length;
  if (!_isBoundary(text, offset)) offset--;
  return offset;
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

Never _stale() => throw const ValidationFailure('规则命中与当前书稿不符，请重新试跑。');

final class _ResolvedMatch {
  const _ResolvedMatch(this.text, this.line);
  final String text;
  final _SourceLine line;
}

final class _SourceLine {
  const _SourceLine(this.number, this.start, this.end, this.terminatedEnd);
  final int number;
  final int start;
  final int end;
  final int terminatedEnd;
}
