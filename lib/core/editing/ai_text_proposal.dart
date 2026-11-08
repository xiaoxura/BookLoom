import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_json.dart';
import 'package:bookloom/core/ai/ai_limits.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';

enum AiTextProposalAction {
  replaceText,
  deleteText,
  removeBlock,
  renameChapter,
}

class AiTextProposal {
  const AiTextProposal({
    required this.id,
    required this.action,
    required this.target,
    required this.range,
    required this.replacement,
    required this.reason,
    this.originalTitle,
  });

  final String id;
  final AiTextProposalAction action;
  final ProposalTextTarget target;
  final ProposalTextRange range;
  final String replacement;
  final String reason;
  final String? originalTitle;

  ProposalTextRange chapterTitleConflictRangeIn(
    String currentTitle,
    String text,
  ) {
    if (action != AiTextProposalAction.renameChapter ||
        originalTitle == null ||
        originalTitle != currentTitle ||
        replacement == currentTitle ||
        replacement != target.originalText.trim() ||
        RegExp(r'[\x00-\x1f\x7f\u2028\u2029]').hasMatch(replacement) ||
        target.originalText.contains('\n') ||
        target.originalText.contains('\r') ||
        range.start < 0 ||
        range.end > text.length ||
        range.start >= range.end ||
        text.substring(range.start, range.end) != target.originalText ||
        text.substring(0, range.start).trim().isNotEmpty) {
      AiTextProposalDecoder._invalid();
    }
    for (final value in [
      id,
      target.bookId,
      target.sessionId,
      target.chapterId,
      target.blockId,
    ]) {
      AiTextProposalDecoder._string({'value': value}, 'value', 128);
    }
    AiTextProposalDecoder._string(
      {'value': originalTitle},
      'value',
      512,
      allowEmpty: true,
    );
    AiTextProposalDecoder._string({'value': replacement}, 'value', 512);
    AiTextProposalDecoder._string({'value': target.originalText}, 'value', 512);
    AiTextProposalDecoder._string(
      {'value': target.before},
      'value',
      1024,
      allowEmpty: true,
    );
    AiTextProposalDecoder._string(
      {'value': target.after},
      'value',
      1024,
      allowEmpty: true,
    );
    AiTextProposalDecoder._string({'value': reason}, 'value', 1024);
    AiTextProposalDecoder._string(
      {'value': text},
      'value',
      aiMaxContextCharacters,
    );
    final nextBreak = text.indexOf(RegExp(r'[\r\n]'), range.end);
    final lineEnd = nextBreak < 0 ? text.length : nextBreak;
    if (text.substring(range.end, lineEnd).trim().isNotEmpty) {
      AiTextProposalDecoder._invalid();
    }
    var conflictEnd = lineEnd;
    if (conflictEnd < text.length && text.codeUnitAt(conflictEnd) == 13) {
      conflictEnd++;
    }
    if (conflictEnd < text.length && text.codeUnitAt(conflictEnd) == 10) {
      conflictEnd++;
    }
    return ProposalTextRange(0, conflictEnd);
  }
}

class AiTextProposalConflict {
  const AiTextProposalConflict(this.firstId, this.secondId);

  final String firstId;
  final String secondId;
}

class AiTextProposalResult {
  AiTextProposalResult({
    required List<AiTextProposal> proposals,
    required List<AiTextProposalConflict> conflicts,
  }) : proposals = List<AiTextProposal>.unmodifiable(proposals),
       conflicts = List<AiTextProposalConflict>.unmodifiable(conflicts);

  final List<AiTextProposal> proposals;
  final List<AiTextProposalConflict> conflicts;
}

abstract final class AiTextProposalDecoder {
  static AiTextProposalResult decode(
    String response, {
    required AiContextChunk context,
  }) {
    if (response.length > 32768) _invalid();
    final Object? decoded;
    try {
      decoded = decodeStrictAiJson(response);
    } on FormatException {
      _invalid();
    }
    final root = _object(decoded);
    _keys(root, const {'schema_version', 'proposals'});
    if (root['schema_version'] is! int || root['schema_version'] != 1) {
      _invalid();
    }
    final values = root['proposals'];
    if (values is! List || values.length > 100) _invalid();
    final slices = <String, AiContextSlice>{};
    for (final slice in context.slices) {
      if (slices.containsKey(slice.block.blockId)) _invalid();
      slices[slice.block.blockId] = slice;
    }
    final ids = <String>{};
    final proposals = <AiTextProposal>[];
    for (final value in values) {
      final item = _object(value);
      final actionValue = _string(item, 'action', 32);
      _keys(item, {
        'id',
        'action',
        'chapter_id',
        'block_id',
        'original',
        'before',
        'after',
        'replacement',
        'reason',
        if (actionValue == 'rename_chapter') 'original_title',
      });
      final id = _string(item, 'id', 128);
      if (!ids.add(id)) _invalid();
      final action = switch (actionValue) {
        'replace_text' => AiTextProposalAction.replaceText,
        'delete_text' => AiTextProposalAction.deleteText,
        'remove_block' => AiTextProposalAction.removeBlock,
        'rename_chapter' => AiTextProposalAction.renameChapter,
        _ => _invalid(),
      };
      final chapterId = _string(item, 'chapter_id', 128);
      final blockId = _string(item, 'block_id', 128);
      final original = _string(item, 'original', 32768);
      final before = _string(item, 'before', 1024, allowEmpty: true);
      final after = _string(item, 'after', 1024, allowEmpty: true);
      final replacement = _string(
        item,
        'replacement',
        32768,
        allowEmpty: action != AiTextProposalAction.replaceText,
      );
      final reason = _string(item, 'reason', 1024);
      if ((action != AiTextProposalAction.renameChapter &&
              replacement == original) ||
          ((action == AiTextProposalAction.deleteText ||
                  action == AiTextProposalAction.removeBlock) &&
              replacement.isNotEmpty)) {
        _invalid();
      }
      final slice = slices[blockId];
      if (slice == null || slice.block.chapterId != chapterId) _invalid();
      final target = ProposalTextTarget(
        bookId: context.bookId,
        sessionId: context.sessionId,
        sessionRevision: context.sessionRevision,
        chapterId: chapterId,
        blockId: blockId,
        originalText: original,
        before: before,
        after: after,
      );
      final range = target.locate(
        currentBookId: context.bookId,
        currentSessionId: context.sessionId,
        currentSessionRevision: context.sessionRevision,
        currentChapterId: slice.block.chapterId,
        currentBlockId: slice.block.blockId,
        currentText: slice.block.text,
      );
      if (range.start < slice.startUtf16 ||
          range.end > slice.endUtf16 ||
          range.start - before.length <
              slice.startUtf16 - slice.before.length ||
          range.end + after.length > slice.endUtf16 + slice.after.length) {
        _invalid();
      }
      if (action == AiTextProposalAction.removeBlock &&
          (range.start != 0 ||
              range.end != slice.block.text.length ||
              slice.startUtf16 != 0 ||
              slice.endUtf16 != slice.block.text.length ||
              original != slice.block.text ||
              before.isNotEmpty ||
              after.isNotEmpty)) {
        _invalid();
      }
      final proposal = AiTextProposal(
        id: id,
        action: action,
        target: target,
        range: range,
        replacement: replacement,
        reason: reason,
        originalTitle: action == AiTextProposalAction.renameChapter
            ? _string(item, 'original_title', 512, allowEmpty: true)
            : null,
      );
      if (action == AiTextProposalAction.renameChapter) {
        final leadingBlocks = context.slices.where(
          (candidate) =>
              candidate.block.chapterId == chapterId &&
              candidate.block.text.trim().isNotEmpty,
        );
        if (leadingBlocks.isEmpty ||
            leadingBlocks.first.block.blockId != blockId) {
          _invalid();
        }
        proposal.chapterTitleConflictRangeIn(
          slice.block.chapterTitle,
          slice.block.text,
        );
      }
      proposals.add(proposal);
    }
    final conflicts = <AiTextProposalConflict>[];
    for (var first = 0; first < proposals.length; first++) {
      for (var second = first + 1; second < proposals.length; second++) {
        final left = proposals[first];
        final right = proposals[second];
        if (left.target.chapterId == right.target.chapterId &&
            ((left.action == AiTextProposalAction.renameChapter &&
                    right.action == AiTextProposalAction.renameChapter) ||
                left.target.blockId == right.target.blockId &&
                    (left.action == AiTextProposalAction.renameChapter
                            ? left.chapterTitleConflictRangeIn(
                                left.originalTitle!,
                                slices[left.target.blockId]!.block.text,
                              )
                            : left.range)
                        .overlaps(
                          right.action == AiTextProposalAction.renameChapter
                              ? right.chapterTitleConflictRangeIn(
                                  right.originalTitle!,
                                  slices[right.target.blockId]!.block.text,
                                )
                              : right.range,
                        ))) {
          conflicts.add(AiTextProposalConflict(left.id, right.id));
        }
      }
    }
    return AiTextProposalResult(proposals: proposals, conflicts: conflicts);
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is Map<String, dynamic>) return value;
    _invalid();
  }

  static void _keys(Map<String, dynamic> value, Set<String> expected) {
    if (value.length != expected.length || !expected.every(value.containsKey)) {
      _invalid();
    }
  }

  static String _string(
    Map<String, dynamic> item,
    String key,
    int limit, {
    bool allowEmpty = false,
  }) {
    final value = item[key];
    if (value is! String ||
        value.length > limit ||
        (!allowEmpty && value.trim().isEmpty)) {
      _invalid();
    }
    for (var index = 0; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (code >= 0xd800 && code <= 0xdbff) {
        if (++index >= value.length) _invalid();
        final next = value.codeUnitAt(index);
        if (next < 0xdc00 || next > 0xdfff) _invalid();
      } else if (code >= 0xdc00 && code <= 0xdfff) {
        _invalid();
      }
    }
    return value;
  }

  static Never _invalid() =>
      throw const ValidationFailure('AI 文本提案验证失败，未修改书稿；请重新分析或缩小范围。');
}
