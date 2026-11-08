import 'package:bookloom/core/editing/chapter_edits.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Chapter chapter(
    String id, {
    String? parentId,
    int level = 2,
    List<Block> blocks = const <Block>[],
  }) => Chapter(
    id: id,
    bookId: 'book',
    title: id,
    parentId: parentId,
    level: level,
    blocks: blocks,
  );

  test('split then merge preserves content in reading order', () {
    final original = chapter(
      'a',
      blocks: const <Block>[
        TextBlock(id: 'p1', text: '前文'),
        TextBlock(id: 'p2', text: '新章标题'),
        ImageBlock(id: 'img', assetId: 'asset'),
        TextBlock(id: 'p3', text: '后文'),
      ],
    );
    final split = ChapterEdits.splitAtParagraph(
      <Chapter>[original],
      'a',
      'p2',
      'b',
    );
    expect(split.map((chapter) => chapter.title), <String>['a', '新章标题']);
    expect(split[0].blocks.map((block) => block.id), <String>['p1']);
    expect(split[1].blocks.map((block) => block.id), <String>['img', 'p3']);
    expect(split.map((chapter) => chapter.order), <int>[0, 1]);

    final merged = ChapterEdits.mergeWithPrevious(split, 'b');
    expect(merged, hasLength(1));
    expect(merged.single.blocks.map((block) => block.id), <String>[
      'p1',
      'img',
      'p3',
    ]);
    expect(
      () => ChapterEdits.mergeWithPrevious(<Chapter>[original], 'a'),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('deleting a volume promotes children without deleting their blocks', () {
    final chapters = <Chapter>[
      chapter('v', level: 1),
      chapter(
        'a',
        parentId: 'v',
        blocks: const <Block>[TextBlock(id: 'p1', text: '正文')],
      ),
      chapter('b', parentId: 'v'),
      chapter('c'),
    ];
    final result = ChapterEdits.delete(chapters, 'v');
    expect(result.map((item) => item.id), <String>['a', 'b', 'c']);
    expect(result.every((item) => item.parentId == null), isTrue);
    expect(result.map((item) => item.order), <int>[0, 1, 2]);
    expect(result.first.blocks.single.plainText, '正文');
  });

  test('promotion and demotion keep only two valid levels', () {
    final chapters = <Chapter>[
      chapter('v', level: 1),
      chapter('a', parentId: 'v'),
      chapter('b', parentId: 'v'),
      chapter('c', parentId: 'v'),
    ];
    final promoted = ChapterEdits.promoteToVolume(chapters, 'b');
    expect(promoted[1].parentId, 'v');
    expect(promoted[2].level, 1);
    expect(promoted[2].parentId, isNull);
    expect(promoted[3].parentId, 'b');
    final demoted = ChapterEdits.demoteToChapter(promoted, 'b');
    expect(demoted[2].level, 2);
    expect(demoted[2].parentId, 'v');
    expect(demoted[3].parentId, 'v');
    expect(ChapterEdits.normalize(demoted), hasLength(4));
  });

  test('paragraph as title consumes exactly that paragraph', () {
    final source = chapter(
      'a',
      blocks: const <Block>[
        TextBlock(id: 'one', text: '正文'),
        TextBlock(id: 'two', text: '标题'),
        TextBlock(id: 'three', text: '尾段'),
      ],
    );
    final result = ChapterEdits.setParagraphAsTitle(
      <Chapter>[source],
      'a',
      'two',
    );
    expect(result.single.title, '标题');
    expect(result.single.blocks.map((block) => block.id), <String>[
      'one',
      'three',
    ]);
  });

  test('new volume and chapters normalize contiguous reading order', () {
    final source = <Chapter>[chapter('a'), chapter('b')];
    final withVolume = ChapterEdits.createVolume(
      source,
      chapter('v', level: 1),
    );
    expect(withVolume.map((item) => item.id), <String>['a', 'b', 'v']);
    expect(withVolume.last.blocks, isEmpty);

    final first = ChapterEdits.createChapter(
      withVolume,
      chapter(
        'c',
        parentId: 'v',
        blocks: const <Block>[TextBlock(id: 'p3', text: '')],
      ),
    );
    final before = ChapterEdits.createChapter(
      first,
      chapter(
        'd',
        parentId: 'v',
        blocks: const <Block>[TextBlock(id: 'p4', text: '')],
      ),
      beforeChapterId: 'c',
    );
    final after = ChapterEdits.createChapter(
      before,
      chapter(
        'e',
        blocks: const <Block>[TextBlock(id: 'p5', text: '')],
      ),
      afterChapterId: 'a',
    );
    expect(after.map((item) => item.id), <String>[
      'a',
      'e',
      'b',
      'v',
      'd',
      'c',
    ]);
    expect(after.map((item) => item.order), <int>[0, 1, 2, 3, 0, 1]);
    expect(after.last.parentId, 'v');
  });

  test('top-level chapters can be placed around whole volumes', () {
    final source = <Chapter>[
      chapter('v1', level: 1),
      chapter('a', parentId: 'v1'),
      chapter('b', parentId: 'v1'),
      chapter('v2', level: 1),
      chapter('c', parentId: 'v2'),
      chapter('v3', level: 1),
    ];
    Chapter fresh(String id) => chapter(
      id,
      blocks: <Block>[TextBlock(id: 'block-$id', text: '')],
    );

    final beforeFirst = ChapterEdits.createChapter(
      source,
      fresh('before'),
      beforeChapterId: 'v1',
    );
    expect(beforeFirst.map((item) => item.id), <String>[
      'before',
      'v1',
      'a',
      'b',
      'v2',
      'c',
      'v3',
    ]);

    final between = ChapterEdits.createChapter(
      source,
      fresh('between'),
      afterChapterId: 'v1',
    );
    expect(between.map((item) => item.id), <String>[
      'v1',
      'a',
      'b',
      'between',
      'v2',
      'c',
      'v3',
    ]);
    expect(between[3].parentId, isNull);
    expect(between[1].parentId, 'v1');
    expect(between[2].parentId, 'v1');

    final beforeSecond = ChapterEdits.createChapter(
      source,
      fresh('before'),
      beforeChapterId: 'v2',
    );
    expect(beforeSecond.map((item) => item.id), <String>[
      'v1',
      'a',
      'b',
      'before',
      'v2',
      'c',
      'v3',
    ]);

    final afterEmpty = ChapterEdits.createChapter(
      source,
      fresh('after'),
      afterChapterId: 'v3',
    );
    expect(afterEmpty.map((item) => item.id), <String>[
      'v1',
      'a',
      'b',
      'v2',
      'c',
      'v3',
      'after',
    ]);
  });

  test('batch move appends in source order and preserves blocks and IDs', () {
    final source = <Chapter>[
      chapter(
        'a',
        blocks: const <Block>[ImageBlock(id: 'img', assetId: 'asset')],
      ),
      chapter('v1', level: 1),
      chapter('b', parentId: 'v1'),
      chapter('c', parentId: 'v1'),
      chapter('v2', level: 1),
      chapter('d', parentId: 'v2'),
      chapter('e'),
    ];
    final moved = ChapterEdits.moveChaptersToVolume(source, <String>{
      'c',
      'a',
      'e',
    }, volumeId: 'v2');
    expect(moved.map((item) => item.id), <String>[
      'v1',
      'b',
      'v2',
      'd',
      'a',
      'c',
      'e',
    ]);
    expect(moved.skip(4).every((item) => item.parentId == 'v2'), isTrue);
    expect(moved[4].blocks.single, same(source.first.blocks.single));
    final root = ChapterEdits.moveChaptersToVolume(moved, <String>{
      'b',
      'd',
    }, volumeId: null);
    expect(root.map((item) => item.id), <String>[
      'v1',
      'v2',
      'a',
      'c',
      'e',
      'b',
      'd',
    ]);
    expect(root.last.parentId, isNull);
    expect(ChapterEdits.normalize(root), hasLength(7));
  });

  test('invalid creation and move arguments fail before changing input', () {
    final source = <Chapter>[
      chapter('v', level: 1),
      chapter('a', parentId: 'v'),
      chapter('b'),
    ];
    Chapter fresh(String id, {String? parentId, String title = 'new'}) =>
        Chapter(
          id: id,
          bookId: 'book',
          title: title,
          parentId: parentId,
          blocks: const <Block>[TextBlock(id: 'new-block', text: '')],
        );

    expect(
      () => ChapterEdits.createVolume(source, chapter('v', level: 1)),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createVolume(
        source,
        const Chapter(id: '../bad', bookId: 'book', title: '卷', level: 1),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createChapter(source, fresh('c', title: '  ')),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createChapter(source, fresh('c', parentId: 'missing')),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createChapter(
        source,
        fresh('c', parentId: 'v'),
        beforeChapterId: 'b',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createChapter(
        source,
        fresh('c', parentId: 'v'),
        beforeChapterId: 'v',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createChapter(
        source,
        fresh('c', parentId: 'v'),
        afterChapterId: 'v',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createChapter(
        source,
        fresh('c'),
        beforeChapterId: 'a',
        afterChapterId: 'b',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.moveChaptersToVolume(source, <String>{
        'v',
      }, volumeId: null),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.moveChaptersToVolume(source, <String>{
        'a',
        'missing',
      }, volumeId: 'v'),
      throwsA(isA<ValidationFailure>()),
    );
    expect(source.map((item) => item.id), <String>['v', 'a', 'b']);
    expect(source[1].parentId, 'v');
  });

  test('anchored volume before a chapter adopts its unmanaged run', () {
    final source = <Chapter>[chapter('x'), chapter('y')];
    final result = ChapterEdits.createVolume(
      source,
      chapter('v', level: 1),
      beforeChapterId: 'x',
    );
    expect(result.map((item) => item.id), <String>['v', 'x', 'y']);
    expect(result.first.level, 1);
    expect(result[1].parentId, 'v');
    expect(result[2].parentId, 'v');
  });

  test('anchored volume after a chapter keeps the anchor unassigned', () {
    final source = <Chapter>[chapter('x'), chapter('y')];
    final result = ChapterEdits.createVolume(
      source,
      chapter('v', level: 1),
      afterChapterId: 'x',
    );
    expect(result.map((item) => item.id), <String>['x', 'v', 'y']);
    expect(result.first.parentId, isNull);
    expect(result[2].parentId, 'v');
  });

  test('anchored volume spans the whole anchor volume block', () {
    final source = <Chapter>[
      chapter('v', level: 1),
      chapter('a', parentId: 'v'),
      chapter('b', parentId: 'v'),
      chapter('c'),
    ];
    final before = ChapterEdits.createVolume(
      source,
      chapter('n', level: 1),
      beforeChapterId: 'v',
    );
    expect(before.map((item) => item.id), <String>['n', 'v', 'a', 'b', 'c']);
    expect(before[1].parentId, isNull);
    expect(before[2].parentId, 'v');
    expect(before[3].parentId, 'v');
    expect(before.last.parentId, isNull);

    final after = ChapterEdits.createVolume(
      source,
      chapter('n', level: 1),
      afterChapterId: 'v',
    );
    expect(after.map((item) => item.id), <String>['v', 'a', 'b', 'n', 'c']);
    expect(after[4].parentId, 'n');
  });

  test('anchored volume rejects conflicting and nested anchors', () {
    final source = <Chapter>[chapter('x')];
    final inside = <Chapter>[
      chapter('v', level: 1),
      chapter('a', parentId: 'v'),
    ];
    expect(
      () => ChapterEdits.createVolume(
        source,
        chapter('v', level: 1),
        beforeChapterId: 'x',
        afterChapterId: 'x',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createVolume(
        inside,
        chapter('n', level: 1),
        beforeChapterId: 'a',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => ChapterEdits.createVolume(
        source,
        chapter('n', level: 1),
        afterChapterId: 'missing',
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
