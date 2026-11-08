import 'dart:convert';
import 'dart:math';

import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

AiContextBlock block(String id, String text, {String title = '第一章'}) =>
    AiContextBlock(
      chapterId: 'chapter-$id',
      chapterTitle: title,
      blockId: id,
      text: text,
    );

AiContextPlan plan(
  List<AiContextBlock> blocks, {
  int characters = 1024,
  int chunks = 32,
  int input = 2097152,
}) => AiContextPlanner.plan(
  bookId: 'book',
  sessionId: 'session',
  sessionRevision: 7,
  blocks: blocks,
  maxChunkCharacters: characters,
  maxChunks: chunks,
  maxInputCharacters: input,
);

void main() {
  test('covers every selected block in order including empty blocks', () {
    final blocks = <AiContextBlock>[
      block('previous', '上章正文' * 300),
      block('empty', ''),
      block('next', '下章正文' * 300),
    ];
    final result = plan(blocks);
    expect(result.blockCount, 3);
    expect(result.inputCharacters, 2400);
    final slices = result.chunks.expand((chunk) => chunk.slices).toList();
    expect(slices.map((slice) => slice.block.blockId).toSet(), {
      'previous',
      'empty',
      'next',
    });
    for (final original in blocks) {
      final selected = slices.where(
        (slice) => slice.block.blockId == original.blockId,
      );
      expect(selected.map((slice) => slice.text).join(), original.text);
      var expectedStart = 0;
      for (final slice in selected) {
        expect(slice.startUtf16, expectedStart);
        expectedStart = slice.endUtf16;
      }
      expect(expectedStart, original.text.length);
    }
  });

  test('budgets serialized metadata and JSON escapes, not text alone', () {
    final result = plan([block('quoted', '\n"\\' * 1000, title: '转义"标题')]);
    expect(result.chunks.length, greaterThan(3));
    for (final chunk in result.chunks) {
      expect(chunk.encode().length, lessThanOrEqualTo(1024));
      final decoded = jsonDecode(chunk.encode()) as Map<String, dynamic>;
      expect(decoded['session_revision'], 7);
      expect(decoded['chunk_index'], chunk.index);
      expect(decoded['book_id'], 'book');
    }
  });

  test('retains empty blocks that require flushing the previous chunk', () {
    final blocks = List<AiContextBlock>.generate(
      20,
      (index) => block('empty-$index', ''),
    );
    final result = plan(blocks);
    expect(
      result.chunks
          .expand((chunk) => chunk.slices)
          .map((slice) => slice.block.blockId)
          .toList(),
      blocks.map((block) => block.blockId).toList(),
    );
  });

  test(
    'splits emoji safely and preserves neighboring context at boundaries',
    () {
      final original = '前😀后\n' * 500;
      final result = plan([block('emoji', original)]);
      final slices = result.chunks.expand((chunk) => chunk.slices).toList();
      expect(slices.map((slice) => slice.text).join(), original);
      for (final slice in slices) {
        expect(utf8.decode(utf8.encode(slice.text)), slice.text);
        expect(utf8.decode(utf8.encode(slice.before)), slice.before);
        expect(utf8.decode(utf8.encode(slice.after)), slice.after);
        expect(
          original.substring(slice.startUtf16, slice.endUtf16),
          slice.text,
        );
        if (slice.startUtf16 > 0) expect(slice.before, isNotEmpty);
        if (slice.endUtf16 < original.length) expect(slice.after, isNotEmpty);
      }
    },
  );

  test(
    'refuses excessive chunks or input without returning partial coverage',
    () {
      expect(
        () => plan([block('large', '文' * 2000)], chunks: 1),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => plan([block('large', '文' * 101)], input: 100),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('rejects invalid IDs, duplicate blocks and invalid UTF-16', () {
    for (final blocks in <List<AiContextBlock>>[
      <AiContextBlock>[],
      [block('same', '甲'), block('same', '乙')],
      [block('', '文')],
      [block('long-title', '文', title: '题' * 513)],
      [block('bad-text', String.fromCharCode(0xd800))],
    ]) {
      expect(() => plan(blocks), throwsA(isA<ValidationFailure>()));
    }
  });

  test('returns deterministic immutable chunk lists', () {
    final blocks = [block('one', '正文' * 500)];
    final first = plan(blocks);
    final second = plan(blocks);
    expect(
      first.chunks.map((chunk) => chunk.encode()).toList(),
      second.chunks.map((chunk) => chunk.encode()).toList(),
    );
    expect(first.chunks.clear, throwsUnsupportedError);
    expect(() => first.chunks.first.slices.clear(), throwsUnsupportedError);
    blocks.clear();
    expect(first.chunks.first.slices.first.text, isNotEmpty);
  });

  test('preserves complete coverage under varied escaping and Unicode', () {
    final random = Random(42);
    const atoms = ['文', '😀', '\n', '"', '\\', '𝄞', 'a', '\t'];
    for (var trial = 0; trial < 40; trial++) {
      final blocks = List<AiContextBlock>.generate(5, (index) {
        final text = List<String>.generate(
          random.nextInt(200),
          (_) => atoms[random.nextInt(atoms.length)],
        ).join();
        return block('b-$index', text);
      });
      final budget = 512 + random.nextInt(513);
      final result = plan(blocks, characters: budget, chunks: 128);
      for (final chunk in result.chunks) {
        expect(chunk.encode().length, lessThanOrEqualTo(budget));
      }
      for (final original in blocks) {
        final slices = result.chunks
            .expand((chunk) => chunk.slices)
            .where((slice) => slice.block.blockId == original.blockId);
        expect(slices, isNotEmpty);
        expect(slices.map((slice) => slice.text).join(), original.text);
        var nextStart = 0;
        for (final slice in slices) {
          expect(slice.startUtf16, nextStart);
          nextStart = slice.endUtf16;
          expect(utf8.decode(utf8.encode(slice.text)), slice.text);
          expect(utf8.decode(utf8.encode(slice.before)), slice.before);
          expect(utf8.decode(utf8.encode(slice.after)), slice.after);
        }
        expect(nextStart, original.text.length);
      }
    }
  });
}
