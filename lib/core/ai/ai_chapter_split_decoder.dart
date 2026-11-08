import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_json.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';

abstract final class AiChapterSplitDecoder {
  static List<AiChapterSplitProposal> decode(
    String response, {
    required AiContextChunk context,
  }) {
    if (response.length > 65536) _invalid();
    final Object? decoded;
    try {
      decoded = decodeStrictAiJson(response);
    } on FormatException {
      _invalid();
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['schema_version'] is! int ||
        decoded['schema_version'] != 1 ||
        decoded['proposals'] is! List) {
      _invalid();
    }
    final values = decoded['proposals'] as List;
    if (values.length > 100) _invalid();
    final slices = <String, AiContextSlice>{};
    for (final slice in context.slices) {
      if (slices.containsKey(slice.block.blockId)) _invalid();
      slices[slice.block.blockId] = slice;
    }
    final ids = <String>{};
    final proposals = <AiChapterSplitProposal>[];
    for (final value in values) {
      const keys = {
        'id',
        'action',
        'chapter_id',
        'block_id',
        'original',
        'before',
        'after',
        'title',
        'remove_title_line',
        'reason',
      };
      if (value is! Map<String, dynamic> ||
          value.length != keys.length ||
          !keys.every(value.containsKey) ||
          value['remove_title_line'] is! bool) {
        _invalid();
      }
      final id = _field(value, 'id', 128);
      if (!ids.add(id) || _field(value, 'action', 32) != 'split_chapter') {
        _invalid();
      }
      final chapterId = _field(value, 'chapter_id', 128);
      final blockId = _field(value, 'block_id', 128);
      final original = _field(value, 'original', 32768);
      final before = _field(value, 'before', 1024, allowEmpty: true);
      final after = _field(value, 'after', 1024, allowEmpty: true);
      final title = _field(value, 'title', 256);
      final reason = _field(value, 'reason', 1024);
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
        currentChapterId: chapterId,
        currentBlockId: blockId,
        currentText: slice.block.text,
      );
      final proposal = AiChapterSplitProposal(
        id: id,
        target: target,
        range: range,
        title: title,
        removeTitleLine: value['remove_title_line'] as bool,
        reason: reason,
      );
      final line = proposal.titleLineIn(slice.block.text, range);
      if (range.start < slice.startUtf16 ||
          range.end > slice.endUtf16 ||
          line.start < slice.startUtf16 ||
          proposal.removeTitleLine && line.end > slice.endUtf16 ||
          range.start - before.length <
              slice.startUtf16 - slice.before.length ||
          range.end + after.length > slice.endUtf16 + slice.after.length) {
        _invalid();
      }
      proposals.add(proposal);
    }
    return List<AiChapterSplitProposal>.unmodifiable(proposals);
  }

  static String _field(
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
      throw const ValidationFailure('AI 拆章提案验证失败，未修改书稿；请重新分析或缩小范围。');
}
