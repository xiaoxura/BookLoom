import 'package:bookloom/core/editing/ai_change_application.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splits same-block headings in reverse order with UTF-16 and CRLF', () {
    const source = '😀序言\r\n 第一章 \r\n甲😀\r\n第二章\r\n乙';
    final book = _book(<Chapter>[
      const Chapter(
        id: 'source',
        bookId: 'book',
        title: '合并稿',
        blocks: <Block>[TextBlock(id: 'body', text: source)],
      ),
    ]);
    final first = _split(
      id: 'first',
      chapterId: 'source',
      blockId: 'body',
      source: source,
      original: ' 第一章 ',
      before: '😀序言\r\n',
      after: '\r\n',
      removeTitleLine: true,
    );
    final second = _split(
      id: 'second',
      chapterId: 'source',
      blockId: 'body',
      source: source,
      original: '第二章',
      before: '甲😀\r\n',
      after: '\r\n',
      removeTitleLine: false,
    );

    expect(first.range.start, source.indexOf(' 第一章 '));
    final result = _compile(
      book,
      splitProposals: <AiChapterSplitProposal>[first, second],
      selectedIds: const <String>{'first', 'second'},
      identities: const <String, AiChapterSplitIdentity>{
        'first': AiChapterSplitIdentity(
          chapterId: 'first-chapter',
          blockId: 'first-body',
        ),
        'second': AiChapterSplitIdentity(
          chapterId: 'second-chapter',
          blockId: 'second-body',
        ),
      },
    );

    expect(result.map((chapter) => chapter.title), ['合并稿', '第一章', '第二章']);
    expect((result[0].blocks.single as TextBlock).text, '😀序言\r\n');
    expect((result[1].blocks.single as TextBlock).text, '甲😀\r\n');
    expect((result[2].blocks.single as TextBlock).text, '第二章\r\n乙');
    expect(() => result.add(result.first), throwsUnsupportedError);
  });

  test('moves split boundary after earlier and later text edits', () {
    const source = '😀前缀\r\n第二章\r\n后缀🙂';
    final book = _book(<Chapter>[
      const Chapter(
        id: 'source',
        bookId: 'book',
        title: '合并稿',
        blocks: <Block>[TextBlock(id: 'body', text: source)],
      ),
    ]);
    final before = _replace(
      id: 'before',
      chapterId: 'source',
      blockId: 'body',
      source: source,
      original: '前缀',
      before: '😀',
      after: '\r\n',
      replacement: '前',
    );
    final after = _replace(
      id: 'after',
      chapterId: 'source',
      blockId: 'body',
      source: source,
      original: '后缀',
      before: '\r\n',
      after: '🙂',
      replacement: '补充🙂',
    );
    final split = _split(
      id: 'split',
      chapterId: 'source',
      blockId: 'body',
      source: source,
      original: '第二章',
      before: '😀前缀\r\n',
      after: '\r\n',
      removeTitleLine: true,
    );

    final result = _compile(
      book,
      textProposals: <AiTextProposal>[before, after],
      splitProposals: <AiChapterSplitProposal>[split],
      selectedIds: const <String>{'before', 'after', 'split'},
      identities: const <String, AiChapterSplitIdentity>{
        'split': AiChapterSplitIdentity(
          chapterId: 'split-chapter',
          blockId: 'split-body',
        ),
      },
    );

    expect((result[0].blocks.single as TextBlock).text, '😀前\r\n');
    expect((result[1].blocks.single as TextBlock).text, '补充🙂🙂');
  });

  test(
    'rejects a title line deleted by a selected text proposal atomically',
    () {
      const source = '开篇\r\n第二章\r\n结尾';
      final book = _book(<Chapter>[
        const Chapter(
          id: 'source',
          bookId: 'book',
          title: '合并稿',
          blocks: <Block>[TextBlock(id: 'body', text: source)],
        ),
      ]);
      final split = _split(
        id: 'split',
        chapterId: 'source',
        blockId: 'body',
        source: source,
        original: '第二章',
        before: '开篇\r\n',
        after: '\r\n',
      );
      final deletion = AiTextProposal(
        id: 'delete-title',
        action: AiTextProposalAction.deleteText,
        target: split.target,
        range: split.range,
        replacement: '',
        reason: '删除标题行',
      );

      expect(
        () => _compile(
          book,
          textProposals: <AiTextProposal>[deletion],
          splitProposals: <AiChapterSplitProposal>[split],
          selectedIds: const <String>{'delete-title', 'split'},
          identities: const <String, AiChapterSplitIdentity>{
            'split': AiChapterSplitIdentity(
              chapterId: 'split-chapter',
              blockId: 'split-body',
            ),
          },
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect((book.chapters.single.blocks.single as TextBlock).text, source);
      expect(book.chapters, hasLength(1));
    },
  );

  test('rejects deletion of the CRLF before a split heading atomically', () {
    const source = '前章正文\r\n第二章\r\n后续正文';
    final book = _book(<Chapter>[
      const Chapter(
        id: 'source',
        bookId: 'book',
        title: '合并稿',
        blocks: <Block>[TextBlock(id: 'body', text: source)],
      ),
    ]);
    final split = _split(
      id: 'split',
      chapterId: 'source',
      blockId: 'body',
      source: source,
      original: '第二章',
      before: '前章正文\r\n',
      after: '\r\n',
    );
    final target = _target(
      chapterId: 'source',
      blockId: 'body',
      source: source,
      original: '\r\n',
      before: '前章正文',
      after: '第二章',
    );
    final joinParagraphs = AiTextProposal(
      id: 'delete-preceding-crlf',
      action: AiTextProposalAction.deleteText,
      target: target,
      range: _range(target, 'source', 'body', source),
      replacement: '',
      reason: '删除标题前换行会连接两章正文',
    );

    expect(
      () => _compile(
        book,
        textProposals: <AiTextProposal>[joinParagraphs],
        splitProposals: <AiChapterSplitProposal>[split],
        selectedIds: const <String>{'delete-preceding-crlf', 'split'},
        identities: const <String, AiChapterSplitIdentity>{
          'split': AiChapterSplitIdentity(
            chapterId: 'split-chapter',
            blockId: 'split-body',
          ),
        },
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(book.chapters, hasLength(1));
    expect((book.chapters.single.blocks.single as TextBlock).text, source);
  });

  test('preserves volume, resource order and unselected chapters', () {
    const unselected = Chapter(
      id: 'unselected',
      bookId: 'book',
      title: '未选章节',
      parentId: 'volume',
      blocks: <Block>[TextBlock(id: 'other-body', text: '原样保留')],
    );
    const bookChapters = <Chapter>[
      Chapter(id: 'volume', bookId: 'book', title: '第一卷', level: 1),
      Chapter(
        id: 'source',
        bookId: 'book',
        title: '合并稿',
        parentId: 'volume',
        blocks: <Block>[
          TextBlock(id: 'body', text: '引子\r\n第二章\r\n正文'),
          ImageBlock(id: 'image', assetId: 'asset'),
          FootnoteBlock(id: 'footnote', text: '脚注', marker: '1'),
          DividerBlock(id: 'divider'),
          TextBlock(id: 'tail', text: '尾段'),
        ],
      ),
      unselected,
    ];
    final book = _book(bookChapters);
    final split = _split(
      id: 'split',
      chapterId: 'source',
      blockId: 'body',
      source: '引子\r\n第二章\r\n正文',
      original: '第二章',
      before: '引子\r\n',
      after: '\r\n',
    );

    final result = _compile(
      book,
      splitProposals: <AiChapterSplitProposal>[split],
      selectedIds: const <String>{'split'},
      identities: const <String, AiChapterSplitIdentity>{
        'split': AiChapterSplitIdentity(
          chapterId: 'new-chapter',
          blockId: 'new-body',
        ),
      },
    );

    expect(result.map((chapter) => chapter.id), [
      'volume',
      'source',
      'new-chapter',
      'unselected',
    ]);
    expect(result.first.isVolume, isTrue);
    expect(result[1].parentId, 'volume');
    expect(result[2].parentId, 'volume');
    expect(result[1].blocks, const <Block>[
      TextBlock(id: 'body', text: '引子\r\n'),
    ]);
    expect(result[2].blocks, const <Block>[
      TextBlock(id: 'new-body', text: '正文'),
      ImageBlock(id: 'image', assetId: 'asset'),
      FootnoteBlock(id: 'footnote', text: '脚注', marker: '1'),
      DividerBlock(id: 'divider'),
      TextBlock(id: 'tail', text: '尾段'),
    ]);
    expect(result.last.title, unselected.title);
    expect(result.last.parentId, unselected.parentId);
    expect(result.last.blocks, unselected.blocks);
  });

  test('rejects fabricated, inline, forged and unknown split proposals', () {
    const source = '开篇\r\n第二章\r\n结尾';
    final book = _book(<Chapter>[
      const Chapter(
        id: 'source',
        bookId: 'book',
        title: '合并稿',
        blocks: <Block>[TextBlock(id: 'body', text: source)],
      ),
    ]);
    final split = _split(
      id: 'split',
      chapterId: 'source',
      blockId: 'body',
      source: source,
      original: '第二章',
      before: '开篇\r\n',
      after: '\r\n',
    );
    const identities = <String, AiChapterSplitIdentity>{
      'split': AiChapterSplitIdentity(
        chapterId: 'split-chapter',
        blockId: 'split-body',
      ),
    };

    expect(
      () => _compile(
        book,
        splitProposals: <AiChapterSplitProposal>[split],
        selectedIds: const <String>{'unknown'},
        identities: identities,
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => _compile(
        book,
        splitProposals: <AiChapterSplitProposal>[
          AiChapterSplitProposal(
            id: split.id,
            target: split.target,
            range: ProposalTextRange(
              split.range.start + 1,
              split.range.end + 1,
            ),
            title: split.title,
            removeTitleLine: split.removeTitleLine,
            reason: split.reason,
          ),
        ],
        selectedIds: const <String>{'split'},
        identities: identities,
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => _compile(
        book,
        splitProposals: <AiChapterSplitProposal>[
          AiChapterSplitProposal(
            id: split.id,
            target: split.target,
            range: split.range,
            title: '第二章正文',
            removeTitleLine: split.removeTitleLine,
            reason: split.reason,
          ),
        ],
        selectedIds: const <String>{'split'},
        identities: identities,
      ),
      throwsA(isA<ValidationFailure>()),
    );

    const inlineText = '正文 第二章 后文';
    final inlineBook = _book(<Chapter>[
      const Chapter(
        id: 'source',
        bookId: 'book',
        title: '合并稿',
        blocks: <Block>[TextBlock(id: 'body', text: inlineText)],
      ),
    ]);
    final inline = _split(
      id: 'inline',
      chapterId: 'source',
      blockId: 'body',
      source: inlineText,
      original: '第二章',
      before: '正文 ',
      after: ' 后文',
    );
    expect(
      () => _compile(
        inlineBook,
        splitProposals: <AiChapterSplitProposal>[inline],
        selectedIds: const <String>{'inline'},
        identities: const <String, AiChapterSplitIdentity>{
          'inline': AiChapterSplitIdentity(
            chapterId: 'inline-chapter',
            blockId: 'inline-body',
          ),
        },
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
  test(
    'partitions same-block volumes and chapter independent of input order',
    () {
      const source = '序🙂\r\n第二卷\r\n卷二序\r\n第三章\r\n章正文\r\n第三卷\r\n卷三序';
      final book = _book(const [
        Chapter(id: 'old-volume', bookId: 'book', title: '第一卷', level: 1),
        Chapter(
          id: 'source',
          bookId: 'book',
          title: '合并稿',
          parentId: 'old-volume',
          blocks: [TextBlock(id: 'body', text: source)],
        ),
        Chapter(
          id: 'following',
          bookId: 'book',
          title: '后续章',
          parentId: 'old-volume',
          blocks: [TextBlock(id: 'following-body', text: '后续正文')],
        ),
        Chapter(id: 'next-volume', bookId: 'book', title: '已有下一卷', level: 1),
        Chapter(
          id: 'untouched',
          bookId: 'book',
          title: '不跨卷',
          parentId: 'next-volume',
        ),
      ]);
      final proposals = [
        _split(
          id: 'v2',
          chapterId: 'source',
          blockId: 'body',
          source: source,
          original: '第二卷',
          before: '',
          after: '',
          headingLevel: 1,
        ),
        _split(
          id: 'chapter',
          chapterId: 'source',
          blockId: 'body',
          source: source,
          original: '第三章',
          before: '',
          after: '',
        ),
        _split(
          id: 'v3',
          chapterId: 'source',
          blockId: 'body',
          source: source,
          original: '第三卷',
          before: '',
          after: '',
          headingLevel: 1,
        ),
      ];
      expect(proposals[1].headingLevel, 2);
      for (final ordered in [proposals, proposals.reversed.toList()]) {
        final result = _compile(
          book,
          splitProposals: ordered,
          selectedIds: {'v2', 'chapter', 'v3'},
          identities: const {
            'v2': AiChapterSplitIdentity(
              chapterId: 'intro2',
              blockId: 'intro2-body',
              volumeId: 'volume2',
            ),
            'chapter': AiChapterSplitIdentity(
              chapterId: 'chapter3',
              blockId: 'chapter3-body',
            ),
            'v3': AiChapterSplitIdentity(
              chapterId: 'intro3',
              blockId: 'intro3-body',
              volumeId: 'volume3',
            ),
          },
        );
        expect(result.map((chapter) => chapter.id), [
          'old-volume',
          'source',
          'volume2',
          'intro2',
          'chapter3',
          'volume3',
          'intro3',
          'following',
          'next-volume',
          'untouched',
        ]);
        expect(result.map((chapter) => chapter.parentId), [
          null,
          'old-volume',
          null,
          'volume2',
          'volume2',
          null,
          'volume3',
          'volume3',
          null,
          'next-volume',
        ]);
        expect(
          result
              .where((chapter) => chapter.isVolume)
              .every((chapter) => chapter.blocks.isEmpty),
          isTrue,
        );
        expect(
          result
              .where((chapter) => chapter.frontMatter)
              .map((chapter) => chapter.id),
          ['intro2', 'intro3'],
        );
        expect(
          result
              .where((chapter) => chapter.frontMatter)
              .every((chapter) => chapter.title.isEmpty),
          isTrue,
        );
        expect(
          result
              .expand((chapter) => chapter.blocks)
              .whereType<TextBlock>()
              .map((block) => block.text),
          ['序🙂\r\n', '卷二序\r\n', '章正文\r\n', '卷三序', '后续正文'],
        );
      }
      expect(book.chapters, hasLength(5));
      expect(book.chapters[1].blocks, const [
        TextBlock(id: 'body', text: source),
      ]);
    },
  );

  test(
    'omits only truly empty volume intro and retains whitespace or resources',
    () {
      const resources = <Block>[
        ImageBlock(id: 'image', assetId: 'asset'),
        FootnoteBlock(id: 'footnote', text: '脚注', marker: '①'),
      ];
      for (final scenario in [
        (source: '前文\n第二卷', resources: const <Block>[], suffix: ''),
        (
          source: '前文\n第二卷\r\n \t\r\n',
          resources: const <Block>[],
          suffix: ' \t\r\n',
        ),
        (source: '前文\n第二卷', resources: resources, suffix: ''),
      ]) {
        final originalBlocks = <Block>[
          TextBlock(id: 'body', text: scenario.source),
          ...scenario.resources,
        ];
        final book = _book([
          Chapter(
            id: 'source',
            bookId: 'book',
            title: '合并稿',
            blocks: originalBlocks,
          ),
        ]);
        final proposal = _split(
          id: 'volume',
          chapterId: 'source',
          blockId: 'body',
          source: scenario.source,
          original: '第二卷',
          before: '',
          after: '',
          headingLevel: 1,
        );
        final result = _compile(
          book,
          splitProposals: [proposal],
          selectedIds: {'volume'},
          identities: const {
            'volume': AiChapterSplitIdentity(
              chapterId: 'intro',
              blockId: 'intro-body',
              volumeId: 'volume2',
            ),
          },
        );
        expect(result.first.blocks, const [
          TextBlock(id: 'body', text: '前文\n'),
        ]);
        expect(result[1].isVolume, isTrue);
        expect(result[1].blocks, isEmpty);
        if (scenario.suffix.isEmpty && scenario.resources.isEmpty) {
          expect(result, hasLength(2));
        } else {
          expect(result, hasLength(3));
          expect(result.last.id, 'intro');
          expect(result.last.frontMatter, isTrue);
          expect(result.last.title, '');
          expect(result.last.parentId, 'volume2');
          expect(result.last.blocks, [
            if (scenario.suffix.isNotEmpty)
              TextBlock(id: 'intro-body', text: scenario.suffix),
            ...scenario.resources,
          ]);
        }
        expect(book.chapters.single.blocks, originalBlocks);
      }
    },
  );

  test(
    'rejects invalid volume identities atomically including chapter misuse',
    () {
      const source = '前文\n第二卷\n正文\n第三卷\n尾文';
      final book = _book(const [
        Chapter(
          id: 'source',
          bookId: 'book',
          title: '合并稿',
          blocks: [TextBlock(id: 'body', text: source)],
        ),
      ]);
      final first = _split(
        id: 'first',
        chapterId: 'source',
        blockId: 'body',
        source: source,
        original: '第二卷',
        before: '',
        after: '',
        headingLevel: 1,
      );
      final second = _split(
        id: 'second',
        chapterId: 'source',
        blockId: 'body',
        source: source,
        original: '第三卷',
        before: '',
        after: '',
        headingLevel: 1,
      );
      const validSecond = AiChapterSplitIdentity(
        chapterId: 'intro3',
        blockId: 'intro3-body',
        volumeId: 'volume3',
      );
      final originalChapters = List<Chapter>.of(book.chapters);
      for (final badFirst in const <AiChapterSplitIdentity?>[
        null,
        AiChapterSplitIdentity(chapterId: 'intro2', blockId: 'intro2-body'),
        AiChapterSplitIdentity(
          chapterId: 'intro2',
          blockId: 'intro2-body',
          volumeId: 'volume3',
        ),
        AiChapterSplitIdentity(
          chapterId: 'intro2',
          blockId: 'intro2-body',
          volumeId: 'source',
        ),
        AiChapterSplitIdentity(
          chapterId: 'intro2',
          blockId: 'intro2-body',
          volumeId: 'intro2',
        ),
      ]) {
        expect(
          () => _compile(
            book,
            splitProposals: [first, second],
            selectedIds: {'first', 'second'},
            identities: {'first': ?badFirst, 'second': validSecond},
          ),
          throwsA(isA<ValidationFailure>()),
        );
        expect(book.chapters, originalChapters);
        expect(book.chapters.single.blocks, const [
          TextBlock(id: 'body', text: source),
        ]);
      }
      final ordinary = _split(
        id: 'ordinary',
        chapterId: 'source',
        blockId: 'body',
        source: source,
        original: '第二卷',
        before: '',
        after: '',
      );
      expect(ordinary.headingLevel, 2);
      expect(
        () => _compile(
          book,
          splitProposals: [ordinary],
          selectedIds: {'ordinary'},
          identities: const {
            'ordinary': AiChapterSplitIdentity(
              chapterId: 'chapter2',
              blockId: 'chapter2-body',
              volumeId: 'unexpected-volume',
            ),
          },
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(book.chapters, originalChapters);
      expect(book.chapters.single.blocks, const [
        TextBlock(id: 'body', text: source),
      ]);
    },
  );
  test('number evidence compiles without duplicating an existing number or breaking legacy titles', () {
    for (final scenario in [
      (
        original: '【１３ 😀归来】',
        base: '😀归来',
        numberText: '１３',
        number: 13,
        title: '第13章 😀归来',
      ),
      (
        original: '【13 第十三回 😀归来】',
        base: '第十三回 😀归来',
        numberText: '13',
        number: 13,
        title: '第十三回 😀归来',
      ),
      (
        original: '【😀归来】',
        base: '😀归来',
        numberText: '',
        number: null,
        title: '😀归来',
      ),
    ]) {
      final source = '前文\n${scenario.original}\n后文';
      final book = _book([
        Chapter(
          id: 'source',
          bookId: 'book',
          title: '合并稿',
          blocks: [TextBlock(id: 'body', text: source)],
        ),
      ]);
      final baseOffset = scenario.original.indexOf(scenario.base);
      final numberOffset = scenario.original.indexOf(scenario.numberText);
      final proposal = _split(
        id: 'split',
        chapterId: 'source',
        blockId: 'body',
        source: source,
        original: scenario.original,
        before: '',
        after: '',
        title: scenario.title,
        titleEvidenceRange: ProposalTextRange(
          baseOffset,
          baseOffset + scenario.base.length,
        ),
        headingNumber: scenario.number,
        numberEvidenceRange: scenario.number == null
            ? null
            : ProposalTextRange(
                numberOffset,
                numberOffset + scenario.numberText.length,
              ),
      );
      final result = _compile(
        book,
        splitProposals: [proposal],
        selectedIds: {'split'},
        identities: const {
          'split': AiChapterSplitIdentity(
            chapterId: 'new-chapter',
            blockId: 'new-body',
          ),
        },
      );
      expect(result.map((chapter) => chapter.title), ['合并稿', scenario.title]);
      expect(result.last.level, 2);
      expect(result.last.blocks, const [TextBlock(id: 'new-body', text: '后文')]);
      expect(result.first.blocks, const [TextBlock(id: 'body', text: '前文\n')]);
      expect(book.chapters.single.blocks, [
        TextBlock(id: 'body', text: source),
      ]);
    }
  });

  test(
    'forged or incomplete number evidence rejects a whole selected batch',
    () {
      const original = '【１３ 😀归来】';
      const source = '前文\n$original\n正文\n第二章\n尾文';
      final book = _book(const [
        Chapter(
          id: 'source',
          bookId: 'book',
          title: '合并稿',
          blocks: [TextBlock(id: 'body', text: source)],
        ),
      ]);
      final chaptersBefore = List<Chapter>.of(book.chapters);
      final valid = _split(
        id: 'valid',
        chapterId: 'source',
        blockId: 'body',
        source: source,
        original: '第二章',
        before: '',
        after: '',
      );
      for (final evidence
          in <
            ({
              int? number,
              ProposalTextRange? base,
              ProposalTextRange? numberRange,
              String title,
            })
          >[
            (
              number: 14,
              base: const ProposalTextRange(4, 8),
              numberRange: const ProposalTextRange(1, 3),
              title: '第14章 😀归来',
            ),
            (
              number: 13,
              base: const ProposalTextRange(4, 8),
              numberRange: null,
              title: '第13章 😀归来',
            ),
            (
              number: 13,
              base: null,
              numberRange: const ProposalTextRange(1, 3),
              title: '第13章 😀归来',
            ),
            (
              number: null,
              base: const ProposalTextRange(4, 8),
              numberRange: const ProposalTextRange(1, 3),
              title: '😀归来',
            ),
            (
              number: 13,
              base: const ProposalTextRange(4, 8),
              numberRange: const ProposalTextRange(-1, 3),
              title: '第13章 😀归来',
            ),
            (
              number: 13,
              base: const ProposalTextRange(4, 8),
              numberRange: const ProposalTextRange(1, 99),
              title: '第13章 😀归来',
            ),
            (
              number: 13,
              base: const ProposalTextRange(4, 99),
              numberRange: const ProposalTextRange(1, 3),
              title: '第13章 😀归来',
            ),
            (
              number: 13,
              base: const ProposalTextRange(5, 8),
              numberRange: const ProposalTextRange(1, 3),
              title: '第13章 \uDE00归来',
            ),
            (
              number: 13,
              base: const ProposalTextRange(4, 8),
              numberRange: const ProposalTextRange(4, 5),
              title: '第13章 😀归来',
            ),
            (
              number: 13,
              base: const ProposalTextRange(4, 8),
              numberRange: const ProposalTextRange(1, 3),
              title: '第13章 伪造标题',
            ),
          ]) {
        final forged = _split(
          id: 'forged',
          chapterId: 'source',
          blockId: 'body',
          source: source,
          original: original,
          before: '',
          after: '',
          title: evidence.title,
          headingNumber: evidence.number,
          titleEvidenceRange: evidence.base,
          numberEvidenceRange: evidence.numberRange,
        );
        expect(
          () => _compile(
            book,
            splitProposals: [valid, forged],
            selectedIds: {'valid', 'forged'},
            identities: const {
              'valid': AiChapterSplitIdentity(
                chapterId: 'valid-chapter',
                blockId: 'valid-body',
              ),
              'forged': AiChapterSplitIdentity(
                chapterId: 'forged-chapter',
                blockId: 'forged-body',
              ),
            },
          ),
          throwsA(isA<ValidationFailure>()),
        );
        expect(book.chapters, chaptersBefore);
        expect(book.chapters.single.blocks, const [
          TextBlock(id: 'body', text: source),
        ]);
      }
    },
  );
}

Book _book(List<Chapter> chapters) => Book(
  id: 'book',
  meta: BookMeta(title: '合成书稿', author: '测试作者'),
  chapters: chapters,
  createdAt: DateTime.utc(2026, 11, 7),
  updatedAt: DateTime.utc(2026, 11, 7),
);

AiChapterSplitProposal _split({
  required String id,
  required String chapterId,
  required String blockId,
  required String source,
  required String original,
  required String before,
  required String after,
  bool removeTitleLine = true,
  int headingLevel = 2,
  String? title,
  ProposalTextRange? titleEvidenceRange,
  int? headingNumber,
  ProposalTextRange? numberEvidenceRange,
}) {
  final target = _target(
    chapterId: chapterId,
    blockId: blockId,
    source: source,
    original: original,
    before: before,
    after: after,
  );
  return AiChapterSplitProposal(
    id: id,
    target: target,
    range: _range(target, chapterId, blockId, source),
    title: title ?? original.trim(),
    titleEvidenceRange: titleEvidenceRange,
    headingNumber: headingNumber,
    numberEvidenceRange: numberEvidenceRange,
    removeTitleLine: removeTitleLine,
    headingLevel: headingLevel,
    reason: '精确标题行后开始新章',
  );
}

AiTextProposal _replace({
  required String id,
  required String chapterId,
  required String blockId,
  required String source,
  required String original,
  required String before,
  required String after,
  required String replacement,
}) {
  final target = _target(
    chapterId: chapterId,
    blockId: blockId,
    source: source,
    original: original,
    before: before,
    after: after,
  );
  return AiTextProposal(
    id: id,
    action: AiTextProposalAction.replaceText,
    target: target,
    range: _range(target, chapterId, blockId, source),
    replacement: replacement,
    reason: '合成回归建议',
  );
}

ProposalTextTarget _target({
  required String chapterId,
  required String blockId,
  required String source,
  required String original,
  required String before,
  required String after,
}) => ProposalTextTarget(
  bookId: 'book',
  sessionId: 'session',
  sessionRevision: 7,
  chapterId: chapterId,
  blockId: blockId,
  originalText: original,
  before: before,
  after: after,
);

ProposalTextRange _range(
  ProposalTextTarget target,
  String chapterId,
  String blockId,
  String source,
) => target.locate(
  currentBookId: 'book',
  currentSessionId: 'session',
  currentSessionRevision: 7,
  currentChapterId: chapterId,
  currentBlockId: blockId,
  currentText: source,
);

List<Chapter> _compile(
  Book book, {
  List<AiTextProposal> textProposals = const <AiTextProposal>[],
  List<AiChapterSplitProposal> splitProposals =
      const <AiChapterSplitProposal>[],
  required Set<String> selectedIds,
  Map<String, AiChapterSplitIdentity> identities =
      const <String, AiChapterSplitIdentity>{},
}) => AiChangeApplication.compile(
  book: book,
  sessionId: 'session',
  saveSeq: 7,
  textProposals: textProposals,
  splitProposals: splitProposals,
  selectedIds: selectedIds,
  splitIdentities: identities,
  byteBudget: 1024 * 1024,
);
