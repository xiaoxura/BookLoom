import 'dart:convert';

import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/editing/ai_change_application.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_application.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decoder reads standalone rename proposals without finding ids', () {
    const source = ' \r\n  新目录标题  \r\n正文广告';
    final context = _context(source, chapterTitle: '旧目录标题');

    final renamed = AiTextProposalDecoder.decode(
      _response([
        _wire(
          action: 'rename_chapter',
          originalTitle: '旧目录标题',
          original: '  新目录标题  ',
          before: ' \r\n',
          after: '\r\n',
          replacement: '新目录标题',
        ),
      ]),
      context: context,
    ).proposals.single;

    expect(renamed.action, AiTextProposalAction.renameChapter);
    expect(renamed.originalTitle, '旧目录标题');
    expect(renamed.target.originalText, '  新目录标题  ');
    expect(renamed.replacement, '新目录标题');
    expect(renamed.range.start, source.indexOf('  新目录标题  '));

    final ordinary = AiTextProposalDecoder.decode(
      _response([
        _wire(
          action: 'replace_text',
          original: '广告',
          before: '正文',
          replacement: '正文内容',
        ),
      ]),
      context: _context('正文广告', chapterTitle: '旧目录标题'),
    ).proposals.single;
    expect(ordinary.action, AiTextProposalAction.replaceText);
    expect(ordinary.originalTitle, isNull);

    for (final originalTitle in <String?>[null, '旧目录标题']) {
      expect(
        () => AiTextProposalDecoder.decode(
          _response([
            _wire(
              action: 'replace_text',
              original: '广告',
              before: '正文',
              replacement: '正文内容',
            )..['original_title'] = originalTitle,
          ]),
          context: _context('正文广告', chapterTitle: '旧目录标题'),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }

    expect(
      () => AiTextProposalDecoder.decode(
        _response([
          _wire(
            action: 'rename_chapter',
            originalTitle: '旧目录标题',
            original: '  新目录标题  ',
            before: ' \r\n',
            after: '\r\n',
            replacement: '新目录标题',
          )..['finding_id'] = 'not-part-of-this-decoder',
        ]),
        context: context,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('decoder rejects title evidence in a later same-chapter block', () {
    const firstBody = '前置正文\n内容';
    const laterHeading = '新目录标题\n正文';
    final context = AiContextChunk(
      bookId: 'book',
      sessionId: 'session',
      sessionRevision: 7,
      index: 0,
      slices: <AiContextSlice>[
        AiContextSlice(
          block: const AiContextBlock(
            chapterId: 'chapter',
            chapterTitle: '旧目录标题',
            blockId: 'first-body',
            text: firstBody,
          ),
          startUtf16: 0,
          endUtf16: firstBody.length,
          before: '',
          text: firstBody,
          after: '',
        ),
        AiContextSlice(
          block: const AiContextBlock(
            chapterId: 'chapter',
            chapterTitle: '旧目录标题',
            blockId: 'later-heading',
            text: laterHeading,
          ),
          startUtf16: 0,
          endUtf16: laterHeading.length,
          before: '',
          text: laterHeading,
          after: '',
        ),
      ],
    );

    expect(
      () => AiTextProposalDecoder.decode(
        _response([
          _wire(
            action: 'rename_chapter',
            blockId: 'later-heading',
            originalTitle: '旧目录标题',
            original: '新目录标题',
            after: '\n',
            replacement: '新目录标题',
          ),
        ]),
        context: context,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'decoder requires first-line evidence and a title visible in the core',
    () {
      const repeated = '新目录标题\n正文\n新目录标题\n尾声';
      final disambiguated = AiTextProposalDecoder.decode(
        _response([
          _wire(
            action: 'rename_chapter',
            originalTitle: '旧目录标题',
            original: '新目录标题',
            after: '\n正文',
            replacement: '新目录标题',
          ),
        ]),
        context: _context(repeated, chapterTitle: '旧目录标题'),
      ).proposals.single;
      expect(disambiguated.range.start, 0);

      final partial = '新目录标题\n正文';
      final visibleHeadingOnly = _context(
        partial,
        chapterTitle: '旧目录标题',
        end: '新目录标题\n'.length,
      );
      expect(
        AiTextProposalDecoder.decode(
          _response([
            _wire(
              action: 'rename_chapter',
              originalTitle: '旧目录标题',
              original: '新目录标题',
              after: '\n',
              replacement: '新目录标题',
            ),
          ]),
          context: visibleHeadingOnly,
        ).proposals,
        hasLength(1),
      );

      final hiddenHeading = _context(
        partial,
        chapterTitle: '旧目录标题',
        start: '新目录标题\n'.length,
      );
      final invalid = <(AiContextChunk, Map<String, Object?>)>[
        (
          _context('前言\n中间段落\n正文', chapterTitle: '旧目录标题'),
          _wire(
            action: 'rename_chapter',
            originalTitle: '旧目录标题',
            original: '中间段落',
            before: '前言\n',
            after: '\n',
            replacement: '中间段落',
          ),
        ),
        (
          _context('正文与新目录标题相连', chapterTitle: '旧目录标题'),
          _wire(
            action: 'rename_chapter',
            originalTitle: '旧目录标题',
            original: '新目录标题',
            before: '正文与',
            after: '相连',
            replacement: '新目录标题',
          ),
        ),
        (
          _context('新目录标题\n正文', chapterTitle: '另一目录标题'),
          _wire(
            action: 'rename_chapter',
            originalTitle: '旧目录标题',
            original: '新目录标题',
            after: '\n',
            replacement: '新目录标题',
          ),
        ),
        (
          hiddenHeading,
          _wire(
            action: 'rename_chapter',
            originalTitle: '旧目录标题',
            original: '新目录标题',
            after: '\n',
            replacement: '新目录标题',
          ),
        ),
      ];
      for (final (context, proposal) in invalid) {
        expect(
          () => AiTextProposalDecoder.decode(
            _response([proposal]),
            context: context,
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );

  test('decoder enforces title shape and the 512 code-unit limit', () {
    final maximumTitle = List<String>.filled(512, '新').join();
    final tooLongTitle = List<String>.filled(513, '新').join();
    final accepted = AiTextProposalDecoder.decode(
      _response([
        _wire(
          action: 'rename_chapter',
          originalTitle: '旧目录标题',
          original: maximumTitle,
          replacement: maximumTitle,
        ),
      ]),
      context: _context(maximumTitle, chapterTitle: '旧目录标题'),
    );
    expect(accepted.proposals.single.replacement.length, 512);

    final invalid = <Map<String, Object?>>[
      _wire(
        action: 'rename_chapter',
        originalTitle: '伪造目录标题',
        original: '新目录标题',
        replacement: '新目录标题',
      ),
      _wire(
        action: 'rename_chapter',
        originalTitle: '旧目录标题',
        original: '新目录标题',
        replacement: '另一个标题',
      ),
      _wire(
        action: 'rename_chapter',
        originalTitle: '旧目录标题',
        original: '新\n目录标题',
        replacement: '新\n目录标题',
      ),
      _wire(
        action: 'rename_chapter',
        originalTitle: '旧目录标题',
        original: '新目录标题',
        replacement: tooLongTitle,
      ),
    ];
    for (final proposal in invalid) {
      final text = proposal['original']! as String;
      expect(
        () => AiTextProposalDecoder.decode(
          _response([proposal]),
          context: _context(text, chapterTitle: '旧目录标题'),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('change application updates only the directory title and preserves evidence', () {
    const heading = TextBlock(id: 'heading', text: '\n  新目录标题  \n正文');
    const emptyPrefix = TextBlock(id: 'empty-prefix', text: '  \n');
    const image = ImageBlock(id: 'image', assetId: 'cover-art', caption: '插图');
    const footnote = FootnoteBlock(id: 'footnote', text: '来源', marker: '1');
    const tail = TextBlock(id: 'tail', text: '尾段');
    const volume = Chapter(
      id: 'volume',
      bookId: 'book',
      title: '第一卷',
      level: 1,
      order: 3,
    );
    const chapter = Chapter(
      id: 'chapter',
      bookId: 'book',
      title: '旧目录标题',
      parentId: 'volume',
      level: 2,
      order: 9,
      frontMatter: true,
      blocks: <Block>[emptyPrefix, heading, image, footnote, tail],
    );
    const untouched = Chapter(
      id: 'untouched',
      bookId: 'book',
      title: '后续章节',
      parentId: 'volume',
      order: 15,
      frontMatter: true,
      blocks: <Block>[TextBlock(id: 'untouched-body', text: '未选正文')],
    );
    final book = _book(const <Chapter>[volume, chapter, untouched]);
    final rename = _rename(
      id: 'rename',
      blockId: 'heading',
      source: heading.text,
      original: '新目录标题',
      before: '\n  ',
      after: '  \n',
      replacement: '新目录标题',
    );

    final result = _compile(
      book,
      textProposals: <AiTextProposal>[rename],
      selectedIds: const <String>{'rename'},
    );

    expect(result.map((item) => item.id), ['volume', 'chapter', 'untouched']);
    expect(result[0].order, 3);
    expect(result[1].title, '新目录标题');
    expect(result[1].bookId, chapter.bookId);
    expect(result[1].parentId, chapter.parentId);
    expect(result[1].level, chapter.level);
    expect(result[1].order, chapter.order);
    expect(result[1].frontMatter, chapter.frontMatter);
    expect(result[1].blocks, const <Block>[
      emptyPrefix,
      heading,
      image,
      footnote,
      tail,
    ]);
    expect(result[1].blocks.first, same(emptyPrefix));
    expect(result[1].blocks[1], same(heading));
    expect(result[1].blocks[2], same(image));
    expect(result[1].blocks[3], same(footnote));
    expect(result[1].blocks[4], same(tail));
    expect(result[2], same(untouched));
    expect(result[2].order, 15);
    expect(result[2].frontMatter, isTrue);
    expect(
      result[2].blocks.single,
      const TextBlock(id: 'untouched-body', text: '未选正文'),
    );
    expect(book.chapters[1].title, '旧目录标题');
    expect(book.chapters[1].blocks.first, same(emptyPrefix));
  });

  test('an empty current directory title can be replaced', () {
    const source = '新目录标题\n正文';
    final book = _book([
      const Chapter(
        id: 'chapter',
        bookId: 'book',
        title: '',
        blocks: <Block>[TextBlock(id: 'body', text: source)],
      ),
    ]);
    final proposal = _rename(
      id: 'rename-empty-title',
      source: source,
      original: '新目录标题',
      after: '\n',
      replacement: '新目录标题',
      originalTitle: '',
    );

    final result = _compile(
      book,
      textProposals: <AiTextProposal>[proposal],
      selectedIds: const <String>{'rename-empty-title'},
    );

    expect(result.single.title, '新目录标题');
    expect(
      result.single.blocks.single,
      const TextBlock(id: 'body', text: source),
    );
  });

  test(
    'plain text application rejects a rename without editing its evidence',
    () {
      const source = '新目录标题\n正文广告';
      final book = _book([
        const Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '旧目录标题',
          blocks: <Block>[TextBlock(id: 'body', text: source)],
        ),
      ]);
      final rename = _rename(
        id: 'rename',
        source: source,
        original: '新目录标题',
        after: '\n',
        replacement: '新目录标题',
      );

      expect(
        () => AiTextApplication.compile(
          book: book,
          sessionId: 'session',
          saveSeq: 7,
          proposals: <AiTextProposal>[rename],
          selectedIds: const <String>{'rename'},
          byteBudget: 1024,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(book.chapters.single.title, '旧目录标题');
      expect((book.chapters.single.blocks.single as TextBlock).text, source);
    },
  );

  test(
    'stale, malformed, or over-budget renames fail without changing the book',
    () {
      const source = '新目录标题\n正文';
      final book = _book([
        const Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '旧目录标题',
          blocks: <Block>[TextBlock(id: 'body', text: source)],
        ),
      ]);
      final valid = _rename(
        id: 'valid',
        source: source,
        original: '新目录标题',
        after: '\n',
        replacement: '新目录标题',
      );
      final staleRevision = _rename(
        id: 'stale-revision',
        source: source,
        original: '新目录标题',
        after: '\n',
        replacement: '新目录标题',
        sessionRevision: 6,
      );
      final multiline = _rename(
        id: 'multiline',
        source: '新\n目录标题\n正文',
        original: '新\n目录标题',
        after: '\n',
        replacement: '新\n目录标题',
      );
      final badUtf16Text = '新目录标题${String.fromCharCode(0xd800)}';
      final invalidUtf16 = _rename(
        id: 'invalid-utf16',
        source: badUtf16Text,
        original: badUtf16Text,
        replacement: badUtf16Text,
      );
      final wrongTitle = _rename(
        id: 'stale-title',
        source: source,
        original: '新目录标题',
        after: '\n',
        replacement: '新目录标题',
        originalTitle: '已过期目录标题',
      );
      final invalid = <AiTextProposal>[
        staleRevision,
        multiline,
        invalidUtf16,
        wrongTitle,
      ];

      final staleHeadingBook = _book([
        const Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '旧目录标题',
          blocks: <Block>[TextBlock(id: 'body', text: '已更改标题\n正文')],
        ),
      ]);
      expect(
        () => _compile(
          staleHeadingBook,
          textProposals: <AiTextProposal>[valid],
          selectedIds: const <String>{'valid'},
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(staleHeadingBook.chapters.single.title, '旧目录标题');
      expect(
        staleHeadingBook.chapters.single.blocks.single,
        const TextBlock(id: 'body', text: '已更改标题\n正文'),
      );

      for (final proposal in invalid) {
        expect(
          () => _compile(
            book,
            textProposals: <AiTextProposal>[proposal],
            selectedIds: <String>{proposal.id},
          ),
          throwsA(isA<ValidationFailure>()),
          reason:
              'Invalid proposal ${proposal.id} must be rejected atomically.',
        );
        expect(book.chapters.single.title, '旧目录标题');
        expect(
          book.chapters.single.blocks.single,
          const TextBlock(id: 'body', text: source),
        );
      }

      expect(
        () => _compile(
          book,
          textProposals: <AiTextProposal>[valid],
          selectedIds: const <String>{'valid'},
          byteBudget: 1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(book.chapters.single.title, '旧目录标题');
      expect(
        book.chapters.single.blocks.single,
        const TextBlock(id: 'body', text: source),
      );
    },
  );

  test('renames are exclusive per chapter, across blocks and splits', () {
    const firstBlock = '新目录标题\n正文';
    const secondBlock = '另一个目录候选\n正文';
    final book = _book([
      const Chapter(
        id: 'chapter',
        bookId: 'book',
        title: '旧目录标题',
        blocks: <Block>[
          TextBlock(id: 'first', text: firstBlock),
          TextBlock(id: 'second', text: secondBlock),
        ],
      ),
    ]);
    final firstRename = _rename(
      id: 'rename-first',
      blockId: 'first',
      source: firstBlock,
      original: '新目录标题',
      after: '\n',
      replacement: '新目录标题',
    );
    final secondRename = _rename(
      id: 'rename-second',
      blockId: 'second',
      source: secondBlock,
      original: '另一个目录候选',
      after: '\n',
      replacement: '另一个目录候选',
    );
    final split = _split(
      id: 'split',
      blockId: 'second',
      source: secondBlock,
      original: '另一个目录候选',
      after: '\n',
    );

    expect(
      () => _compile(
        book,
        textProposals: <AiTextProposal>[firstRename, secondRename],
        selectedIds: const <String>{'rename-first', 'rename-second'},
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => _compile(
        book,
        textProposals: <AiTextProposal>[firstRename],
        splitProposals: <AiChapterSplitProposal>[split],
        selectedIds: const <String>{'rename-first', 'split'},
        splitIdentities: const <String, AiChapterSplitIdentity>{
          'split': AiChapterSplitIdentity(
            chapterId: 'new-chapter',
            blockId: 'new-body',
          ),
        },
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(book.chapters.single.title, '旧目录标题');
    expect(book.chapters.single.blocks, const <Block>[
      TextBlock(id: 'first', text: firstBlock),
      TextBlock(id: 'second', text: secondBlock),
    ]);
  });

  test(
    'overlapping text edits and whole-block removal conflict with rename',
    () {
      const source = '新目录标题\n正文广告';
      final book = _book([
        const Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '旧目录标题',
          blocks: <Block>[TextBlock(id: 'body', text: source)],
        ),
      ]);
      final rename = _rename(
        id: 'rename',
        source: source,
        original: '新目录标题',
        after: '\n',
        replacement: '新目录标题',
      );
      final overlappingEdit = _text(
        id: 'edit-heading',
        source: source,
        original: '新目录标题',
        replacement: '错误标题',
      );
      final removeBlock = _text(
        id: 'remove-block',
        action: AiTextProposalAction.removeBlock,
        source: source,
        original: source,
      );

      for (final other in <AiTextProposal>[overlappingEdit, removeBlock]) {
        expect(
          () => _compile(
            book,
            textProposals: <AiTextProposal>[rename, other],
            selectedIds: <String>{'rename', other.id},
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
      expect(book.chapters.single.title, '旧目录标题');
      expect(
        book.chapters.single.blocks.single,
        const TextBlock(id: 'body', text: source),
      );
    },
  );

  test(
    'different-chapter rename, split, and non-overlapping edits compose',
    () {
      const renamedSource = '新目录标题\n正文广告';
      const splitSource = '序言\n第二章\n正文广告';
      const volume = Chapter(
        id: 'volume',
        bookId: 'book',
        title: '第一卷',
        level: 1,
      );
      const bookChapter = Chapter(
        id: 'chapter-a',
        bookId: 'book',
        title: '旧目录标题',
        parentId: 'volume',
        order: 1,
        blocks: <Block>[TextBlock(id: 'body-a', text: renamedSource)],
      );
      const splitChapter = Chapter(
        id: 'chapter-b',
        bookId: 'book',
        title: '拼接章节',
        parentId: 'volume',
        order: 2,
        blocks: <Block>[TextBlock(id: 'body-b', text: splitSource)],
      );
      final book = _book(const <Chapter>[volume, bookChapter, splitChapter]);
      final rename = _rename(
        id: 'rename-a',
        chapterId: 'chapter-a',
        blockId: 'body-a',
        source: renamedSource,
        original: '新目录标题',
        after: '\n',
        replacement: '新目录标题',
      );
      final editRenamedChapter = _text(
        id: 'edit-a-body',
        chapterId: 'chapter-a',
        blockId: 'body-a',
        source: renamedSource,
        original: '广告',
        before: '正文',
        replacement: '推广',
      );
      final split = _split(
        id: 'split-b',
        chapterId: 'chapter-b',
        blockId: 'body-b',
        source: splitSource,
        original: '第二章',
        before: '序言\n',
        after: '\n',
      );
      final editSplitBody = _text(
        id: 'edit-b-body',
        chapterId: 'chapter-b',
        blockId: 'body-b',
        source: splitSource,
        original: '广告',
        before: '正文',
        replacement: '推广',
      );

      final result = _compile(
        book,
        textProposals: <AiTextProposal>[
          rename,
          editRenamedChapter,
          editSplitBody,
        ],
        splitProposals: <AiChapterSplitProposal>[split],
        selectedIds: const <String>{
          'rename-a',
          'edit-a-body',
          'edit-b-body',
          'split-b',
        },
        splitIdentities: const <String, AiChapterSplitIdentity>{
          'split-b': AiChapterSplitIdentity(
            chapterId: 'chapter-c',
            blockId: 'body-c',
          ),
        },
      );

      expect(result.map((chapter) => chapter.id), [
        'volume',
        'chapter-a',
        'chapter-b',
        'chapter-c',
      ]);
      expect(result[1].title, '新目录标题');
      expect(
        result[1].blocks.single,
        const TextBlock(id: 'body-a', text: '新目录标题\n正文推广'),
      );
      expect(result[2].title, '拼接章节');
      expect(
        result[2].blocks.single,
        const TextBlock(id: 'body-b', text: '序言\n'),
      );
      expect(result[3].title, '第二章');
      expect(result[3].parentId, 'volume');
      expect(
        result[3].blocks.single,
        const TextBlock(id: 'body-c', text: '正文推广'),
      );
      expect(bookChapter.title, '旧目录标题');
      expect(
        bookChapter.blocks.single,
        const TextBlock(id: 'body-a', text: renamedSource),
      );
      expect(
        splitChapter.blocks.single,
        const TextBlock(id: 'body-b', text: splitSource),
      );
    },
  );
}

AiContextChunk _context(
  String text, {
  required String chapterTitle,
  String chapterId = 'chapter',
  String blockId = 'body',
  int start = 0,
  int? end,
}) {
  final block = AiContextBlock(
    chapterId: chapterId,
    chapterTitle: chapterTitle,
    blockId: blockId,
    text: text,
  );
  final coreEnd = end ?? text.length;
  return AiContextChunk(
    bookId: 'book',
    sessionId: 'session',
    sessionRevision: 7,
    index: 0,
    slices: <AiContextSlice>[
      AiContextSlice(
        block: block,
        startUtf16: start,
        endUtf16: coreEnd,
        before: text.substring(0, start),
        text: text.substring(start, coreEnd),
        after: text.substring(coreEnd),
      ),
    ],
  );
}

Map<String, Object?> _wire({
  String id = 'p1',
  String action = 'replace_text',
  String? originalTitle,
  String chapterId = 'chapter',
  String blockId = 'body',
  String original = '广告',
  String before = '',
  String after = '',
  String replacement = '清理',
}) => <String, Object?>{
  'id': id,
  'action': action,
  'chapter_id': chapterId,
  'block_id': blockId,
  if (action == 'rename_chapter') 'original_title': originalTitle,
  'original': original,
  'before': before,
  'after': after,
  'replacement': replacement,
  'reason': '基于当前可见原文提出修改。',
};

String _response(List<Map<String, Object?>> proposals) =>
    jsonEncode(<String, Object>{'schema_version': 1, 'proposals': proposals});

AiTextProposal _rename({
  required String id,
  String chapterId = 'chapter',
  String blockId = 'body',
  required String source,
  required String original,
  String before = '',
  String after = '',
  required String replacement,
  String originalTitle = '旧目录标题',
  int sessionRevision = 7,
}) {
  final target = ProposalTextTarget(
    bookId: 'book',
    sessionId: 'session',
    sessionRevision: sessionRevision,
    chapterId: chapterId,
    blockId: blockId,
    originalText: original,
    before: before,
    after: after,
  );
  final range = target.locate(
    currentBookId: 'book',
    currentSessionId: 'session',
    currentSessionRevision: sessionRevision,
    currentChapterId: chapterId,
    currentBlockId: blockId,
    currentText: source,
  );
  return AiTextProposal(
    id: id,
    action: AiTextProposalAction.renameChapter,
    target: target,
    range: range,
    replacement: replacement,
    reason: '正文中存在独立的新目录标题。',
    originalTitle: originalTitle,
  );
}

AiTextProposal _text({
  required String id,
  AiTextProposalAction action = AiTextProposalAction.replaceText,
  String chapterId = 'chapter',
  String blockId = 'body',
  required String source,
  required String original,
  String before = '',
  String after = '',
  String replacement = '清理',
  int sessionRevision = 7,
}) {
  final target = ProposalTextTarget(
    bookId: 'book',
    sessionId: 'session',
    sessionRevision: sessionRevision,
    chapterId: chapterId,
    blockId: blockId,
    originalText: original,
    before: before,
    after: after,
  );
  final range = target.locate(
    currentBookId: 'book',
    currentSessionId: 'session',
    currentSessionRevision: sessionRevision,
    currentChapterId: chapterId,
    currentBlockId: blockId,
    currentText: source,
  );
  return AiTextProposal(
    id: id,
    action: action,
    target: target,
    range: range,
    replacement: action == AiTextProposalAction.removeBlock ? '' : replacement,
    reason: '基于原文定位的独立正文建议。',
    originalTitle: null,
  );
}

AiChapterSplitProposal _split({
  required String id,
  String chapterId = 'chapter',
  String blockId = 'body',
  required String source,
  required String original,
  String before = '',
  String after = '',
}) {
  final target = ProposalTextTarget(
    bookId: 'book',
    sessionId: 'session',
    sessionRevision: 7,
    chapterId: chapterId,
    blockId: blockId,
    originalText: original,
    before: before,
    after: after,
  );
  final range = target.locate(
    currentBookId: 'book',
    currentSessionId: 'session',
    currentSessionRevision: 7,
    currentChapterId: chapterId,
    currentBlockId: blockId,
    currentText: source,
  );
  return AiChapterSplitProposal(
    id: id,
    target: target,
    range: range,
    title: original.trim(),
    removeTitleLine: true,
    reason: '原文中已有可独立定位的章节标题。',
  );
}

Book _book(List<Chapter> chapters) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return Book(
    id: 'book',
    meta: BookMeta(title: '测试书稿'),
    chapters: chapters,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

List<Chapter> _compile(
  Book book, {
  List<AiTextProposal> textProposals = const <AiTextProposal>[],
  List<AiChapterSplitProposal> splitProposals =
      const <AiChapterSplitProposal>[],
  Set<String>? selectedIds,
  Map<String, AiChapterSplitIdentity> splitIdentities =
      const <String, AiChapterSplitIdentity>{},
  int byteBudget = 1024 * 1024,
}) => AiChangeApplication.compile(
  book: book,
  sessionId: 'session',
  saveSeq: 7,
  textProposals: textProposals,
  splitProposals: splitProposals,
  selectedIds:
      selectedIds ??
      <String>{
        ...textProposals.map((proposal) => proposal.id),
        ...splitProposals.map((proposal) => proposal.id),
      },
  splitIdentities: splitIdentities,
  byteBudget: byteBudget,
);
