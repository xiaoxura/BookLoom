import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';

final class AiAdvertisementRequest {
  AiAdvertisementRequest._({
    required this.bookId,
    required this.sessionId,
    required this.sessionRevision,
    required this.chapterId,
    required this.blockId,
    required this.startUtf16,
    required this.endUtf16,
    required this.original,
    required this.ruleName,
  });

  factory AiAdvertisementRequest.fromSelection({
    required Book book,
    required String sessionId,
    required int sessionRevision,
    required String chapterId,
    required String blockId,
    required int startUtf16,
    required int endUtf16,
    required String original,
    String? ruleName,
  }) {
    final request = AiAdvertisementRequest._(
      bookId: book.id,
      sessionId: sessionId,
      sessionRevision: sessionRevision,
      chapterId: chapterId,
      blockId: blockId,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      original: original,
      ruleName: ruleName,
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
  final String chapterId;
  final String blockId;
  final int startUtf16;
  final int endUtf16;
  final String original;
  final String? ruleName;

  void validate({
    required Book book,
    required String sessionId,
    required int sessionRevision,
  }) {
    if (!_validId(bookId) ||
        !_validId(this.sessionId) ||
        !_validId(chapterId) ||
        !_validId(blockId) ||
        this.sessionRevision < 0 ||
        book.id != bookId ||
        this.sessionId != sessionId ||
        this.sessionRevision != sessionRevision ||
        ruleName != null &&
            (ruleName!.trim().isEmpty ||
                ruleName!.length > 256 ||
                !_validUtf16(ruleName!)) ||
        original.trim().isEmpty ||
        original.length > 8192 ||
        !_validUtf16(original)) {
      _invalid();
    }
    final chapters = book.chapters.where((chapter) => chapter.id == chapterId);
    if (chapters.length != 1) _invalid();
    final chapter = chapters.single;
    if (chapter.bookId != book.id || chapter.isVolume) _invalid();
    final blocks = chapter.blocks.where((block) => block.id == blockId);
    if (blocks.length != 1 || blocks.single is! TextBlock) _invalid();
    final source = (blocks.single as TextBlock).text;
    if (startUtf16 < 0 ||
        endUtf16 <= startUtf16 ||
        endUtf16 > source.length ||
        !_boundary(source, startUtf16) ||
        !_boundary(source, endUtf16) ||
        source.substring(startUtf16, endUtf16) != original) {
      _invalid();
    }
  }

  AiContextPlan buildPlan({required Book book}) {
    validate(
      book: book,
      sessionId: sessionId,
      sessionRevision: sessionRevision,
    );
    final chapter = book.chapters.singleWhere((item) => item.id == chapterId);
    final blocks = chapter.blocks;
    final index = blocks.indexWhere((block) => block.id == blockId);
    final source = (blocks[index] as TextBlock).text;
    var titleEnd = chapter.title.length.clamp(0, 512);
    if (!_boundary(chapter.title, titleEnd)) titleEnd--;
    final title = chapter.title.substring(0, titleEnd);
    if (!_validUtf16(title)) _invalid();

    AiContextBlock contextBlock(TextBlock block) => AiContextBlock(
      chapterId: chapterId,
      chapterTitle: title,
      blockId: block.id,
      text: block.text,
    );

    final slices = <AiContextSlice>[];
    if (index > 0 && blocks[index - 1] is TextBlock) {
      final previous = blocks[index - 1] as TextBlock;
      var start = (previous.text.length - 512).clamp(0, previous.text.length);
      if (!_boundary(previous.text, start)) start++;
      if (start < previous.text.length) {
        slices.add(
          AiContextSlice(
            block: contextBlock(previous),
            startUtf16: start,
            endUtf16: previous.text.length,
            before: '',
            text: previous.text.substring(start),
            after: '',
          ),
        );
      }
    }
    var beforeStart = (startUtf16 - 128).clamp(0, source.length);
    if (!_boundary(source, beforeStart)) beforeStart++;
    var afterEnd = (endUtf16 + 128).clamp(0, source.length);
    if (!_boundary(source, afterEnd)) afterEnd--;
    slices.add(
      AiContextSlice(
        block: contextBlock(blocks[index] as TextBlock),
        startUtf16: startUtf16,
        endUtf16: endUtf16,
        before: source.substring(beforeStart, startUtf16),
        text: original,
        after: source.substring(endUtf16, afterEnd),
      ),
    );
    if (index + 1 < blocks.length && blocks[index + 1] is TextBlock) {
      final next = blocks[index + 1] as TextBlock;
      var end = next.text.length.clamp(0, 512);
      if (!_boundary(next.text, end)) end--;
      if (end > 0) {
        slices.add(
          AiContextSlice(
            block: contextBlock(next),
            startUtf16: 0,
            endUtf16: end,
            before: '',
            text: next.text.substring(0, end),
            after: '',
          ),
        );
      }
    }
    if (slices.any(
          (slice) =>
              !_validId(slice.block.blockId) ||
              !_validUtf16(slice.text) ||
              !_validUtf16(slice.before) ||
              !_validUtf16(slice.after),
        ) ||
        slices.map((slice) => slice.block.blockId).toSet().length !=
            slices.length) {
      _invalid();
    }
    final chunk = AiContextChunk(
      bookId: bookId,
      sessionId: sessionId,
      sessionRevision: sessionRevision,
      index: 0,
      slices: slices,
    );
    if (chunk.encode().length > AiProtocol.maxUserCharacters) {
      throw const ValidationFailure('广告选区上下文超出请求预算，请缩小选区。');
    }
    return AiContextPlan(
      chunks: [chunk],
      inputCharacters: slices.fold(
        0,
        (total, slice) => total + slice.text.length,
      ),
      blockCount: slices.length,
    );
  }

  Map<String, Object?> toJson() => {
    'source': 'advertisement_selection',
    'book_id': bookId,
    'session_id': sessionId,
    'session_revision': sessionRevision,
    'chapter_id': chapterId,
    'block_id': blockId,
    'start_utf16': startUtf16,
    'end_utf16': endUtf16,
    if (ruleName != null) 'rule_name': ruleName,
  };

  static bool _validId(String value) =>
      value.trim().isNotEmpty && value.length <= 128 && _validUtf16(value);

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
    final before = text.codeUnitAt(offset - 1);
    final after = text.codeUnitAt(offset);
    return !(before >= 0xd800 &&
        before <= 0xdbff &&
        after >= 0xdc00 &&
        after <= 0xdfff);
  }

  static Never _invalid() =>
      throw const ValidationFailure('广告选区已失效，请重新选择正文后分析。');
}
