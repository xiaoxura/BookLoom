import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(List<Block> blocks) => Book(
  id: 'book',
  meta: BookMeta(title: '书'),
  chapters: [
    Chapter(id: 'chapter', bookId: 'book', title: '第一章', blocks: blocks),
    const Chapter(
      id: 'other-chapter',
      bookId: 'book',
      title: '第二章',
      blocks: [TextBlock(id: 'remote', text: '不得外发的另一章')],
    ),
  ],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

AiAdvertisementRequest _request(
  Book book, {
  String blockId = 'focus',
  int start = 2,
  int end = 4,
  String original = '广告',
}) => AiAdvertisementRequest.fromSelection(
  book: book,
  sessionId: 'session',
  sessionRevision: 3,
  chapterId: 'chapter',
  blockId: blockId,
  startUtf16: start,
  endUtf16: end,
  original: original,
);

void main() {
  test('one chunk keeps true offsets and only bounded adjacent text', () {
    final book = _book([
      TextBlock(id: 'before', text: '甲' * 700),
      const TextBlock(id: 'focus', text: '😀广告正文'),
      TextBlock(id: 'after', text: '乙' * 700),
    ]);
    final request = _request(book);
    final plan = request.buildPlan(book: book);
    expect(plan.chunks, hasLength(1));
    final slices = plan.chunks.single.slices;
    expect(slices.map((slice) => slice.block.blockId), [
      'before',
      'focus',
      'after',
    ]);
    expect((slices.first.startUtf16, slices.first.endUtf16), (188, 700));
    expect(slices.first.text, '甲' * 512);
    expect((slices[1].startUtf16, slices[1].endUtf16), (2, 4));
    expect(slices[1].text, '广告');
    expect(slices[1].before, '😀');
    expect(slices[1].after, '正文');
    expect((slices.last.startUtf16, slices.last.endUtf16), (0, 512));
    expect(plan.chunks.single.encode(), isNot(contains('不得外发')));
    expect(request.toJson().values, isNot(contains('广告')));
  });

  test('non-text resources stop neighboring context', () {
    final book = _book([
      const TextBlock(id: 'before', text: '前文'),
      const DividerBlock(id: 'barrier'),
      const TextBlock(id: 'focus', text: '😀广告正文'),
      const ImageBlock(id: 'image', assetId: 'asset', alt: '秘密图片'),
      const TextBlock(id: 'after', text: '后文'),
    ]);
    final slices = _request(book).buildPlan(book: book).chunks.single.slices;
    expect(slices.map((slice) => slice.block.blockId), ['focus']);
  });

  test(
    'rejects partial surrogate, stale original, empty and long selection',
    () {
      final book = _book([const TextBlock(id: 'focus', text: '😀广告正文')]);
      for (final selection in [
        (start: 1, end: 4, original: '\ude00广告'),
        (start: 2, end: 4, original: '文案'),
        (start: 2, end: 2, original: ''),
        (start: 0, end: 1, original: ' '),
      ]) {
        expect(
          () => _request(
            book,
            start: selection.start,
            end: selection.end,
            original: selection.original,
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
      final longBook = _book([TextBlock(id: 'focus', text: '广' * 8193)]);
      expect(
        () => _request(longBook, start: 0, end: 8193, original: '广' * 8193),
        throwsA(isA<ValidationFailure>()),
      );
      final blankBook = _book([const TextBlock(id: 'focus', text: '  广告')]);
      expect(
        () => _request(blankBook, start: 0, end: 2, original: '  '),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('session, revision, block text and ownership remain current', () {
    final book = _book([const TextBlock(id: 'focus', text: '😀广告正文')]);
    final request = _request(book);
    request.validate(book: book, sessionId: 'session', sessionRevision: 3);
    for (final changed in [
      _book([const TextBlock(id: 'focus', text: '😀文案正文')]),
      _book([const TextBlock(id: 'other', text: '😀广告正文')]),
    ]) {
      expect(
        () => request.buildPlan(book: changed),
        throwsA(isA<ValidationFailure>()),
      );
    }
    expect(
      () =>
          request.validate(book: book, sessionId: 'other', sessionRevision: 3),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => request.validate(
        book: book,
        sessionId: 'session',
        sessionRevision: 4,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
