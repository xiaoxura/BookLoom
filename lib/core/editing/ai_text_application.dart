import 'dart:convert';

import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';

abstract final class AiTextApplication {
  static ToolPreview compile({
    required Book book,
    required String sessionId,
    required int saveSeq,
    required List<AiTextProposal> proposals,
    required Set<String> selectedIds,
    required int byteBudget,
  }) {
    if (sessionId.isEmpty ||
        saveSeq < 0 ||
        byteBudget <= 0 ||
        proposals.length > 100 ||
        selectedIds.length > 100) {
      _invalid();
    }
    final byId = <String, AiTextProposal>{};
    for (final proposal in proposals) {
      if (!_validString(proposal.id, 128) || byId.containsKey(proposal.id)) {
        _invalid();
      }
      byId[proposal.id] = proposal;
    }
    if (!selectedIds.every(byId.containsKey)) _invalid();

    final groups = <(String, String), List<AiTextProposal>>{};
    final sourceTexts = <(String, String), String>{};
    for (final proposal in proposals) {
      if (!selectedIds.contains(proposal.id)) continue;
      if (proposal.action == AiTextProposalAction.removeBlock ||
          proposal.action == AiTextProposalAction.renameChapter ||
          proposal.originalTitle != null) {
        _invalid();
      }
      final target = proposal.target;
      if (!_validString(target.bookId, 128) ||
          !_validString(target.sessionId, 128) ||
          !_validString(target.chapterId, 128) ||
          !_validString(target.blockId, 128) ||
          !_validString(target.originalText, 32768) ||
          !_validString(target.before, 1024, allowEmpty: true) ||
          !_validString(target.after, 1024, allowEmpty: true) ||
          !_validString(proposal.reason, 1024) ||
          !_validString(
            proposal.replacement,
            32768,
            allowEmpty: proposal.action == AiTextProposalAction.deleteText,
          ) ||
          proposal.replacement == target.originalText ||
          (proposal.action == AiTextProposalAction.deleteText &&
              proposal.replacement.isNotEmpty)) {
        _invalid();
      }
      final matches = book.chapters.where(
        (chapter) =>
            chapter.id == target.chapterId &&
            chapter.bookId == book.id &&
            !chapter.isVolume,
      );
      if (matches.length != 1) _invalid();
      final blocks = matches.single.blocks.where(
        (block) => block.id == target.blockId,
      );
      if (blocks.length != 1 || blocks.single is! TextBlock) _invalid();
      final text = (blocks.single as TextBlock).text;
      if (!_validUtf16(text)) _invalid();
      final located = target.locate(
        currentBookId: book.id,
        currentSessionId: sessionId,
        currentSessionRevision: saveSeq,
        currentChapterId: matches.single.id,
        currentBlockId: blocks.single.id,
        currentText: text,
      );
      if (proposal.range.start != located.start ||
          proposal.range.end != located.end) {
        _invalid();
      }
      final key = (target.chapterId, target.blockId);
      sourceTexts[key] = text;
      groups.putIfAbsent(key, () => <AiTextProposal>[]).add(proposal);
    }

    final patches = <TextPatch>[];
    var bytes = 0;
    for (final entry in groups.entries) {
      final key = entry.key;
      final ordered = entry.value
        ..sort((left, right) => right.range.start.compareTo(left.range.start));
      var text = sourceTexts[key]!;
      var previousStart = text.length;
      for (final proposal in ordered) {
        if (proposal.range.end > previousStart) _invalid();
        text = text.replaceRange(
          proposal.range.start,
          proposal.range.end,
          proposal.replacement,
        );
        previousStart = proposal.range.start;
      }
      final before = sourceTexts[key]!;
      patches.add(
        TextPatch(
          chapterId: key.$1,
          blockId: key.$2,
          before: before,
          after: text,
        ),
      );
      bytes +=
          utf8.encode(before).length +
          utf8.encode(text).length +
          utf8.encode(key.$1).length +
          utf8.encode(key.$2).length;
      if (bytes > byteBudget) {
        throw const ValidationFailure('本次修改超过撤销内存预算，请缩小处理范围。');
      }
    }
    return ToolPreview(
      baseRevision: saveSeq,
      hits: selectedIds.length,
      patches: patches,
      samples: const <ReplaceSample>[],
    );
  }

  static bool _validString(
    String value,
    int limit, {
    bool allowEmpty = false,
  }) =>
      value.length <= limit &&
      (allowEmpty || value.trim().isNotEmpty) &&
      _validUtf16(value);

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

  static Never _invalid() =>
      throw const ValidationFailure('AI 文本提案验证失败，未修改书稿；请重新分析或缩小范围。');
}
