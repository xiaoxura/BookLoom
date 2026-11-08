import 'dart:convert';

import 'package:bookloom/core/ai/ai_limits.dart';
import 'package:bookloom/core/errors/app_failure.dart';

class AiContextBlock {
  const AiContextBlock({
    required this.chapterId,
    required this.chapterTitle,
    required this.blockId,
    required this.text,
  });

  final String chapterId;
  final String chapterTitle;
  final String blockId;
  final String text;
}

class AiContextSlice {
  const AiContextSlice({
    required this.block,
    required this.startUtf16,
    required this.endUtf16,
    required this.before,
    required this.text,
    required this.after,
  });

  final AiContextBlock block;
  final int startUtf16;
  final int endUtf16;
  final String before;
  final String text;
  final String after;

  Map<String, Object> toJson() => <String, Object>{
    'chapter_id': block.chapterId,
    'chapter_title': block.chapterTitle,
    'block_id': block.blockId,
    'block_length_utf16': block.text.length,
    'start_utf16': startUtf16,
    'end_utf16': endUtf16,
    'before': before,
    'text': text,
    'after': after,
  };
}

class AiContextChunk {
  AiContextChunk({
    required this.bookId,
    required this.sessionId,
    required this.sessionRevision,
    required this.index,
    required List<AiContextSlice> slices,
  }) : slices = List<AiContextSlice>.unmodifiable(slices);

  final String bookId;
  final String sessionId;
  final int sessionRevision;
  final int index;
  final List<AiContextSlice> slices;

  String encode() => jsonEncode(<String, Object>{
    'book_id': bookId,
    'session_id': sessionId,
    'session_revision': sessionRevision,
    'chunk_index': index,
    'blocks': slices.map((slice) => slice.toJson()).toList(),
  });
}

class AiContextPlan {
  AiContextPlan({
    required List<AiContextChunk> chunks,
    required this.inputCharacters,
    required this.blockCount,
  }) : chunks = List<AiContextChunk>.unmodifiable(chunks);

  final List<AiContextChunk> chunks;
  final int inputCharacters;
  final int blockCount;
}

abstract final class AiContextPlanner {
  static AiContextPlan plan({
    required String bookId,
    required String sessionId,
    required int sessionRevision,
    required List<AiContextBlock> blocks,
    int maxChunkCharacters = 16384,
    int maxChunks = 32,
    int maxInputCharacters = aiMaxContextCharacters,
    int overlapCharacters = 32,
  }) {
    if (!_validId(bookId) ||
        !_validId(sessionId) ||
        sessionRevision < 0 ||
        maxChunkCharacters < 512 ||
        maxChunkCharacters > 65536 ||
        maxChunks < 1 ||
        maxChunks > 128 ||
        maxInputCharacters < 1 ||
        maxInputCharacters > aiMaxContextCharacters ||
        overlapCharacters < 0 ||
        overlapCharacters > 128 ||
        blocks.isEmpty ||
        blocks.length > 10000) {
      throw const ValidationFailure('AI 上下文参数无效，请缩小或重新选择分析范围。');
    }
    var inputCharacters = 0;
    final blockIds = <String>{};
    for (final block in blocks) {
      inputCharacters += block.text.length;
      if (!_validId(block.chapterId) ||
          !_validId(block.blockId) ||
          block.chapterTitle.length > 512 ||
          !blockIds.add(block.blockId) ||
          inputCharacters > maxInputCharacters ||
          !_validUtf16(block.text) ||
          !_validUtf16(block.chapterTitle)) {
        throw const ValidationFailure('AI 上下文超出预算或包含无效定位，请缩小分析范围。');
      }
    }

    final chunks = <AiContextChunk>[];
    var pending = <AiContextSlice>[];

    AiContextChunk chunk(List<AiContextSlice> slices) => AiContextChunk(
      bookId: bookId,
      sessionId: sessionId,
      sessionRevision: sessionRevision,
      index: chunks.length,
      slices: slices,
    );

    void flush() {
      if (pending.isEmpty) return;
      if (chunks.length >= maxChunks) {
        throw const ValidationFailure('AI 分块数量超出预算，请缩小分析范围；尚未发送内容。');
      }
      chunks.add(chunk(pending));
      pending = <AiContextSlice>[];
    }

    for (final block in blocks) {
      var start = 0;
      while (true) {
        final remaining = block.text.length - start;
        var low = remaining == 0 ? 0 : 1;
        var high = remaining < maxChunkCharacters
            ? remaining
            : maxChunkCharacters;
        AiContextSlice? best;
        while (low <= high) {
          final count = (low + high) ~/ 2;
          var end = start + count;
          if (!_boundary(block.text, end)) end--;
          if (end == start && remaining > 0) {
            low = count + 1;
            continue;
          }
          final slice = _slice(block, start, end, overlapCharacters);
          if (chunk(<AiContextSlice>[...pending, slice]).encode().length <=
              maxChunkCharacters) {
            best = slice;
            low = count + 1;
          } else {
            high = count - 1;
          }
        }
        if (best == null) {
          if (pending.isEmpty) {
            throw const ValidationFailure('单块定位信息超过请求预算，请缩小标题或分析范围。');
          }
          flush();
          continue;
        }
        pending.add(best);
        start = best.endUtf16;
        if (start == block.text.length) break;
        flush();
      }
    }
    flush();
    return AiContextPlan(
      chunks: chunks,
      inputCharacters: inputCharacters,
      blockCount: blocks.length,
    );
  }

  static AiContextSlice _slice(
    AiContextBlock block,
    int start,
    int end,
    int overlap,
  ) {
    var contextStart = start - overlap;
    if (contextStart < 0) contextStart = 0;
    if (!_boundary(block.text, contextStart)) contextStart++;
    var contextEnd = end + overlap;
    if (contextEnd > block.text.length) contextEnd = block.text.length;
    if (!_boundary(block.text, contextEnd)) contextEnd--;
    return AiContextSlice(
      block: block,
      startUtf16: start,
      endUtf16: end,
      before: block.text.substring(contextStart, start),
      text: block.text.substring(start, end),
      after: block.text.substring(end, contextEnd),
    );
  }

  static bool _validId(String value) =>
      value.isNotEmpty && value.length <= 128 && _validUtf16(value);

  static bool _validUtf16(String text) {
    for (var index = 0; index < text.length; index++) {
      final code = text.codeUnitAt(index);
      if (code >= 0xd800 && code <= 0xdbff) {
        if (++index >= text.length) return false;
        final next = text.codeUnitAt(index);
        if (next < 0xdc00 || next > 0xdfff) return false;
      } else if (code >= 0xdc00 && code <= 0xdfff) {
        return false;
      }
    }
    return true;
  }

  static bool _boundary(String text, int offset) {
    if (offset == 0 || offset == text.length) return true;
    final previous = text.codeUnitAt(offset - 1);
    final next = text.codeUnitAt(offset);
    return !(previous >= 0xd800 &&
        previous <= 0xdbff &&
        next >= 0xdc00 &&
        next <= 0xdfff);
  }
}
