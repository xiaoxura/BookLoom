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
}
