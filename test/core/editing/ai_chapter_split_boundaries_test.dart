import 'package:bookloom/core/editing/ai_change_application.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adjacent CRLF headings split independently without inventing body', () {
    const text = '😀序言\r\n第一章\r\n第二章\r\n后文';
    final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final book = Book(
      id: 'book',
      meta: BookMeta(title: '合成稿'),
      chapters: const [
        Chapter(
          id: 'source',
          bookId: 'book',
          title: '合并稿',
          blocks: [TextBlock(id: 'body', text: text)],
        ),
      ],
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final proposals = [
      for (final title in ['第一章', '第二章'])
        AiChapterSplitProposal(
          id: title,
          target: ProposalTextTarget(
            bookId: 'book',
            sessionId: 'session',
            sessionRevision: 0,
            chapterId: 'source',
            blockId: 'body',
            originalText: title,
          ),
          range: ProposalTextRange(
            text.indexOf(title),
            text.indexOf(title) + title.length,
          ),
          title: title,
          removeTitleLine: true,
          reason: '相邻标题边界来自原文，不补写空章节。',
        ),
    ];
    final result = AiChangeApplication.compile(
      book: book,
      sessionId: 'session',
      saveSeq: 0,
      textProposals: const [],
      splitProposals: proposals,
      selectedIds: {'第一章', '第二章'},
      splitIdentities: const {
        '第一章': AiChapterSplitIdentity(
          chapterId: 'first',
          blockId: 'first-body',
        ),
        '第二章': AiChapterSplitIdentity(
          chapterId: 'second',
          blockId: 'second-body',
        ),
      },
      byteBudget: 1024 * 1024,
    );

    expect(result.map((chapter) => chapter.title), ['合并稿', '第一章', '第二章']);
    expect(result[0].blocks.single.plainText, '😀序言\r\n');
    expect(result[1].blocks, isEmpty);
    expect(result[2].blocks.single.plainText, '后文');
    expect(book.chapters.single.blocks.single.plainText, text);
  });
}
