import 'dart:convert';

import 'package:bookloom/core/ai/ai_context.dart';
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
  test(
    'delete_text empties a full TextBlock while remove_block removes it',
    () {
      const source = '😀站点推广\r\n完整块正文';
      final book = _book(<Chapter>[
        const Chapter(id: 'volume', bookId: 'book', title: '第一卷', level: 1),
        const Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '正文',
          parentId: 'volume',
          blocks: <Block>[TextBlock(id: 'body', text: source)],
        ),
      ]);
      final deleteText = _textProposal(
        id: 'delete-text',
        action: AiTextProposalAction.deleteText,
        source: source,
        original: source,
      );
      final removeBlock = _textProposal(
        id: 'remove-block',
        action: AiTextProposalAction.removeBlock,
        source: source,
        original: source,
      );

      final emptied = _compile(
        book,
        textProposals: <AiTextProposal>[deleteText],
        selectedIds: const <String>{'delete-text'},
      );
      final removed = _compile(
        book,
        textProposals: <AiTextProposal>[removeBlock],
        selectedIds: const <String>{'remove-block'},
      );

      expect(emptied.map((chapter) => chapter.id), ['volume', 'chapter']);
      expect(emptied[1].blocks, const <Block>[TextBlock(id: 'body', text: '')]);
      expect(emptied[1].parentId, 'volume');
      expect(removed.map((chapter) => chapter.id), ['volume', 'chapter']);
      expect(removed[1].blocks, isEmpty);
      expect(removed[1].title, '正文');
      expect(removed[1].parentId, 'volume');
    },
  );

  test('remove_block preserves resource blocks and volume ownership', () {
    const image = ImageBlock(
      id: 'image',
      assetId: 'asset-7',
      caption: '插图说明',
      alt: '风景',
    );
    const footnote = FootnoteBlock(id: 'footnote', text: '来源说明', marker: '注一');
    const divider = DividerBlock(id: 'divider');
    const keptText = TextBlock(id: 'kept', text: '保留的正文');
    const source = '😀整块广告\r\n';
    final book = _book(<Chapter>[
      const Chapter(id: 'volume', bookId: 'book', title: '第一卷', level: 1),
      const Chapter(
        id: 'chapter',
        bookId: 'book',
        title: '正文',
        parentId: 'volume',
        blocks: <Block>[
          image,
          TextBlock(id: 'ad', text: source),
          footnote,
          divider,
          keptText,
        ],
      ),
    ]);
    final removal = _textProposal(
      id: 'remove-ad',
      action: AiTextProposalAction.removeBlock,
      blockId: 'ad',
      source: source,
      original: source,
    );

    final result = _compile(
      book,
      textProposals: <AiTextProposal>[removal],
      selectedIds: const <String>{'remove-ad'},
    );

    expect(result.map((chapter) => chapter.id), ['volume', 'chapter']);
    expect(result.first.isVolume, isTrue);
    expect(result[1].parentId, 'volume');
    expect(result[1].blocks, const <Block>[image, footnote, divider, keptText]);
    expect(result[1].blocks[0], same(image));
    expect(result[1].blocks[1], same(footnote));
    expect(result[1].blocks[2], same(divider));
    expect(result[1].blocks[3], same(keptText));
  });

  test('remove_block rejects image, footnote, and divider targets', () {
    const image = ImageBlock(id: 'image', assetId: 'asset', caption: '图片说明');
    const footnote = FootnoteBlock(id: 'footnote', text: '脚注内容');
    const divider = DividerBlock(id: 'divider');
    final cases = <(Block, String)>[
      (image, image.plainText),
      (footnote, footnote.plainText),
      (divider, 'divider'),
    ];

    for (final (block, source) in cases) {
      final book = _book(<Chapter>[
        Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '正文',
          blocks: <Block>[block],
        ),
      ]);
      final target = ProposalTextTarget(
        bookId: 'book',
        sessionId: 'session',
        sessionRevision: 7,
        chapterId: 'chapter',
        blockId: block.id,
        originalText: source,
      );
      final removal = AiTextProposal(
        id: 'remove-${block.id}',
        action: AiTextProposalAction.removeBlock,
        target: target,
        range: ProposalTextRange(0, source.length),
        replacement: '',
        reason: '只允许移除完整文字块',
      );

      expect(
        () => _compile(
          book,
          textProposals: <AiTextProposal>[removal],
          selectedIds: <String>{removal.id},
        ),
        throwsA(isA<ValidationFailure>()),
        reason: 'A ${block.kind.name} block must remain intact.',
      );
      expect(book.chapters.single.blocks.single, same(block));
    }
  });

  test(
    'remove_block rejects partial ranges, replacement, and forged context',
    () {
      const source = '😀前缀广告\r\n后续正文';
      final book = _book(<Chapter>[
        const Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '正文',
          blocks: <Block>[TextBlock(id: 'body', text: source)],
        ),
      ]);
      final invalid = <AiTextProposal Function()>[
        () => _textProposal(
          id: 'partial',
          action: AiTextProposalAction.removeBlock,
          source: source,
          original: '广告',
          before: '😀前缀',
          after: '\r\n',
        ),
        () => _textProposal(
          id: 'replacement',
          action: AiTextProposalAction.removeBlock,
          source: source,
          original: source,
          replacement: '残留内容',
        ),
        () => _textProposal(
          id: 'forged-before',
          action: AiTextProposalAction.removeBlock,
          source: source,
          original: source,
          before: '伪造前文',
        ),
        () => _textProposal(
          id: 'forged-after',
          action: AiTextProposalAction.removeBlock,
          source: source,
          original: source,
          after: '伪造后文',
        ),
      ];

      for (final makeProposal in invalid) {
        expect(
          () {
            final proposal = makeProposal();
            _compile(
              book,
              textProposals: <AiTextProposal>[proposal],
              selectedIds: <String>{proposal.id},
            );
          },
          throwsA(isA<ValidationFailure>()),
          reason: 'Malformed whole-block removal must fail.',
        );
        expect(
          book.chapters.single.blocks.single,
          const TextBlock(id: 'body', text: source),
        );
      }
    },
  );

  test('same-block delete and split conflict with removal atomically', () {
    const source = '😀引子\r\n第二章\r\n正文🙂';
    final book = _book(<Chapter>[
      const Chapter(
        id: 'chapter',
        bookId: 'book',
        title: '合并稿',
        blocks: <Block>[TextBlock(id: 'body', text: source)],
      ),
    ]);
    final remove = _textProposal(
      id: 'remove-body',
      action: AiTextProposalAction.removeBlock,
      source: source,
      original: source,
    );
    final delete = _textProposal(
      id: 'delete-title',
      action: AiTextProposalAction.deleteText,
      source: source,
      original: '第二章',
      before: '😀引子\r\n',
      after: '\r\n',
    );
    final split = _splitProposal(
      id: 'split-title',
      source: source,
      original: '第二章',
      before: '😀引子\r\n',
      after: '\r\n',
    );

    expect(
      () => _compile(
        book,
        textProposals: <AiTextProposal>[remove, delete],
        selectedIds: const <String>{'remove-body', 'delete-title'},
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => _compile(
        book,
        textProposals: <AiTextProposal>[remove],
        splitProposals: <AiChapterSplitProposal>[split],
        selectedIds: const <String>{'remove-body', 'split-title'},
        identities: const <String, AiChapterSplitIdentity>{
          'split-title': AiChapterSplitIdentity(
            chapterId: 'new-chapter',
            blockId: 'new-body',
          ),
        },
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(book.chapters, hasLength(1));
    expect(book.chapters.single.blocks, const <Block>[
      TextBlock(id: 'body', text: source),
    ]);
  });

  test(
    'different-block removal composes with shifted split and text edits',
    () {
      const body = '😀序言广告\r\n第二章\r\n正文🙂';
      const tail = '😀尾部广告';
      const removable = '😀广告\r\n引导';
      const image = ImageBlock(id: 'image', assetId: 'asset');
      const footnote = FootnoteBlock(id: 'footnote', text: '脚注', marker: '1');
      const divider = DividerBlock(id: 'divider');
      const volume = Chapter(
        id: 'volume',
        bookId: 'book',
        title: '第一卷',
        level: 1,
      );
      const untouched = Chapter(
        id: 'untouched',
        bookId: 'book',
        title: '另一章',
        parentId: 'volume',
        blocks: <Block>[TextBlock(id: 'other', text: '不变')],
      );
      final book = _book(<Chapter>[
        volume,
        const Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '合并稿',
          parentId: 'volume',
          blocks: <Block>[
            TextBlock(id: 'ad', text: removable),
            TextBlock(id: 'body', text: body),
            TextBlock(id: 'tail', text: tail),
            image,
            footnote,
            divider,
          ],
        ),
        untouched,
      ]);
      final remove = _textProposal(
        id: 'remove-ad',
        action: AiTextProposalAction.removeBlock,
        blockId: 'ad',
        source: removable,
        original: removable,
      );
      final prefixEdit = _textProposal(
        id: 'edit-before-split',
        action: AiTextProposalAction.replaceText,
        blockId: 'body',
        source: body,
        original: '广告',
        before: '😀序言',
        after: '\r\n',
        replacement: '推广内容',
      );
      final tailEdit = _textProposal(
        id: 'edit-tail',
        action: AiTextProposalAction.replaceText,
        blockId: 'tail',
        source: tail,
        original: '广告',
        before: '😀尾部',
        replacement: '清理🙂',
      );
      final split = _splitProposal(
        id: 'split-title',
        blockId: 'body',
        source: body,
        original: '第二章',
        before: '😀序言广告\r\n',
        after: '\r\n',
      );

      final result = _compile(
        book,
        textProposals: <AiTextProposal>[remove, prefixEdit, tailEdit],
        splitProposals: <AiChapterSplitProposal>[split],
        selectedIds: const <String>{
          'remove-ad',
          'edit-before-split',
          'edit-tail',
          'split-title',
        },
        identities: const <String, AiChapterSplitIdentity>{
          'split-title': AiChapterSplitIdentity(
            chapterId: 'new-chapter',
            blockId: 'new-body',
          ),
        },
      );

      expect(result.map((chapter) => chapter.id), [
        'volume',
        'chapter',
        'new-chapter',
        'untouched',
      ]);
      expect(result[1].parentId, 'volume');
      expect(result[1].blocks, const <Block>[
        TextBlock(id: 'body', text: '😀序言推广内容\r\n'),
      ]);
      expect(result[2].title, '第二章');
      expect(result[2].parentId, 'volume');
      expect(result[2].blocks, const <Block>[
        TextBlock(id: 'new-body', text: '正文🙂'),
        TextBlock(id: 'tail', text: '😀尾部清理🙂'),
        image,
        footnote,
        divider,
      ]);
      expect(result[2].blocks[2], same(image));
      expect(result[2].blocks[3], same(footnote));
      expect(result[2].blocks[4], same(divider));
      expect(result[3].title, untouched.title);
      expect(result[3].parentId, untouched.parentId);
      expect(result[3].blocks, untouched.blocks);
      expect(
        book.chapters[1].blocks.first,
        const TextBlock(id: 'ad', text: removable),
      );
    },
  );

  test(
    'rejects stale revision, stale source, and insufficient patch budget',
    () {
      const source = '😀广告\r\n正文';
      final book = _book(<Chapter>[
        const Chapter(
          id: 'chapter',
          bookId: 'book',
          title: '正文',
          blocks: <Block>[TextBlock(id: 'body', text: source)],
        ),
      ]);
      final staleRevision = _textProposal(
        id: 'stale-revision',
        action: AiTextProposalAction.removeBlock,
        source: source,
        original: source,
        sessionRevision: 6,
      );
      final staleSource = _textProposal(
        id: 'stale-source',
        action: AiTextProposalAction.removeBlock,
        source: '😀广告\r\n旧正文',
        original: '😀广告\r\n旧正文',
      );
      final removal = _textProposal(
        id: 'over-budget',
        action: AiTextProposalAction.removeBlock,
        source: source,
        original: source,
      );

      for (final proposal in <AiTextProposal>[staleRevision, staleSource]) {
        expect(
          () => _compile(
            book,
            textProposals: <AiTextProposal>[proposal],
            selectedIds: <String>{proposal.id},
          ),
          throwsA(isA<ValidationFailure>()),
        );
      }
      expect(
        () => _compile(
          book,
          textProposals: <AiTextProposal>[removal],
          selectedIds: const <String>{'over-budget'},
          byteBudget: 1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(book.chapters.single.blocks, const <Block>[
        TextBlock(id: 'body', text: source),
      ]);
    },
  );

  test(
    'decoder accepts a whole core and rejects partial ranges and slices',
    () {
      const source = '😀站点广告\r\n整块正文🙂';
      final fullContext = _context(source);
      expect(fullContext.slices.single.startUtf16, 0);
      expect(fullContext.slices.single.endUtf16, source.length);
      final decoded = AiTextProposalDecoder.decode(
        _response(original: source),
        context: fullContext,
      );
      expect(decoded.proposals, hasLength(1));
      expect(decoded.proposals.single.action, AiTextProposalAction.removeBlock);
      expect(decoded.proposals.single.range.start, 0);
      expect(decoded.proposals.single.range.end, source.length);
      expect(decoded.proposals.single.target.originalText, source);
      expect(decoded.proposals.single.replacement, '');

      expect(
        () => AiTextProposalDecoder.decode(
          _response(original: '😀站点广告'),
          context: fullContext,
        ),
        throwsA(isA<ValidationFailure>()),
        reason:
            'A complete local block does not make a partial range removable.',
      );

      final longSource = '${'正文' * 400}😀广告\r\n尾声';
      final partialPlan = AiContextPlanner.plan(
        bookId: 'book',
        sessionId: 'session',
        sessionRevision: 7,
        maxChunkCharacters: 512,
        blocks: <AiContextBlock>[
          AiContextBlock(
            chapterId: 'chapter',
            chapterTitle: '正文',
            blockId: 'body',
            text: longSource,
          ),
        ],
      );
      expect(partialPlan.chunks.length, greaterThan(1));
      for (final chunk in partialPlan.chunks) {
        expect(
          () => AiTextProposalDecoder.decode(
            _response(original: longSource),
            context: chunk,
          ),
          throwsA(isA<ValidationFailure>()),
          reason:
              'A partial context chunk cannot authorize whole-block removal.',
        );
      }
    },
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

AiTextProposal _textProposal({
  required String id,
  required AiTextProposalAction action,
  String chapterId = 'chapter',
  String blockId = 'body',
  required String source,
  required String original,
  String before = '',
  String after = '',
  String replacement = '',
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
    replacement: replacement,
    reason: '基于当前文字块完整内容核验',
  );
}

AiChapterSplitProposal _splitProposal({
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
    reason: '标题行边界明确',
  );
}

List<Chapter> _compile(
  Book book, {
  List<AiTextProposal> textProposals = const <AiTextProposal>[],
  List<AiChapterSplitProposal> splitProposals =
      const <AiChapterSplitProposal>[],
  required Set<String> selectedIds,
  Map<String, AiChapterSplitIdentity> identities =
      const <String, AiChapterSplitIdentity>{},
  int byteBudget = 1024 * 1024,
  String sessionId = 'session',
  int saveSeq = 7,
}) => AiChangeApplication.compile(
  book: book,
  sessionId: sessionId,
  saveSeq: saveSeq,
  textProposals: textProposals,
  splitProposals: splitProposals,
  selectedIds: selectedIds,
  splitIdentities: identities,
  byteBudget: byteBudget,
);

AiContextChunk _context(String text) => AiContextPlanner.plan(
  bookId: 'book',
  sessionId: 'session',
  sessionRevision: 7,
  blocks: <AiContextBlock>[
    AiContextBlock(
      chapterId: 'chapter',
      chapterTitle: '正文',
      blockId: 'body',
      text: text,
    ),
  ],
).chunks.single;

String _response({required String original}) => jsonEncode(<String, Object>{
  'schema_version': 1,
  'proposals': <Object>[
    <String, Object>{
      'id': 'remove',
      'action': 'remove_block',
      'chapter_id': 'chapter',
      'block_id': 'body',
      'original': original,
      'before': '',
      'after': '',
      'replacement': '',
      'reason': '完整文字块内容均为推广信息',
    },
  ],
});
