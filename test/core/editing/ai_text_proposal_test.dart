import 'dart:convert';

import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

AiContextChunk context(String text) => AiContextPlanner.plan(
  bookId: 'book',
  sessionId: 'session',
  sessionRevision: 4,
  blocks: <AiContextBlock>[
    AiContextBlock(
      chapterId: 'chapter',
      chapterTitle: '第一章',
      blockId: 'block',
      text: text,
    ),
  ],
).chunks.single;

Map<String, Object> proposal({
  String id = 'p1',
  String action = 'delete_text',
  String original = '广告',
  String before = '',
  String after = '',
  String replacement = '',
}) => <String, Object>{
  'id': id,
  'action': action,
  'chapter_id': 'chapter',
  'block_id': 'block',
  'original': original,
  'before': before,
  'after': after,
  'replacement': replacement,
  'reason': '疑似站点推广，等待用户确认。',
};

String response(List<Map<String, Object>> proposals) =>
    jsonEncode(<String, Object>{'schema_version': 1, 'proposals': proposals});

void main() {
  test('validates deletion locally with UTF-16 and task-owned session', () {
    final source = context('😀前广告后');
    final result = AiTextProposalDecoder.decode(
      response([proposal()]),
      context: source,
    );
    final item = result.proposals.single;
    expect(item.target.bookId, 'book');
    expect(item.target.sessionId, 'session');
    expect(item.target.sessionRevision, 4);
    expect(item.range.start, 3);
    expect(item.range.end, 5);
    expect(item.action, AiTextProposalAction.deleteText);
    expect(item.replacement, '');
    expect(source.slices.single.block.text, '😀前广告后');
    expect(result.conflicts, isEmpty);
  });

  test('allows a pending result with no safe proposals', () {
    final result = AiTextProposalDecoder.decode(
      response([]),
      context: context('无可靠依据'),
    );
    expect(result.proposals, isEmpty);
    expect(result.conflicts, isEmpty);
  });

  test('rejects ambiguous repeated text and accepts exact context', () {
    final source = context('广告和广告。');
    expect(
      () =>
          AiTextProposalDecoder.decode(response([proposal()]), context: source),
      throwsA(isA<ValidationFailure>()),
    );
    final result = AiTextProposalDecoder.decode(
      response([proposal(before: '和', after: '。')]),
      context: source,
    );
    expect(result.proposals.single.range.start, 3);
  });

  test(
    'reports overlapping proposals instead of choosing a destructive winner',
    () {
      final result = AiTextProposalDecoder.decode(
        response([
          proposal(original: '推广广告'),
          proposal(id: 'p2', action: 'replace_text', replacement: '宣传'),
        ]),
        context: context('这是推广广告。'),
      );
      expect(result.proposals, hasLength(2));
      expect(result.conflicts.single.firstId, 'p1');
      expect(result.conflicts.single.secondId, 'p2');
      expect(result.proposals.clear, throwsUnsupportedError);
      expect(result.conflicts.clear, throwsUnsupportedError);
    },
  );

  test(
    'allows compatible adjacent replacements without reporting conflict',
    () {
      final result = AiTextProposalDecoder.decode(
        response([proposal(original: '推广'), proposal(id: 'p2')]),
        context: context('推广广告'),
      );
      expect(result.conflicts, isEmpty);
    },
  );

  test('rejects unknown fields, actions, forged identities and invalid edits', () {
    final invalid = <Map<String, Object>>[
      {...proposal(), 'session_revision': 0},
      {...proposal(), 'action': 'run_script'},
      {...proposal(), 'action': 'split_chapter'},
      {...proposal(), 'block_id': 'other'},
      {...proposal(), 'chapter_id': 'other'},
      {...proposal(), 'original': '原文没有的句子'},
      {...proposal(), 'replacement': '删除不能携带替换内容'},
      proposal(action: 'replace_text', replacement: ''),
      proposal(action: 'replace_text', replacement: '广告'),
      {...proposal(), 'reason': 12},
      {...proposal(), 'reason': ''},
      {...proposal(), 'replacement': String.fromCharCode(0xd800)},
    ];
    for (final item in invalid) {
      expect(
        () => AiTextProposalDecoder.decode(
          response([item]),
          context: context('广告'),
        ),
        throwsA(isA<ValidationFailure>()),
        reason:
            'Reject action/identity/schema mismatch without returning a batch',
      );
    }
  });

  test('rejects partial batches, duplicate IDs and unbounded results', () {
    for (final body in <String>[
      response([proposal(), proposal()]),
      response([
        proposal(),
        {...proposal(id: 'p2'), 'block_id': 'missing'},
      ]),
      response(List<Map<String, Object>>.generate(101, (_) => proposal())),
      '{"schema_version":1,"proposals":[],"extra":true}',
      '{"schema_version":1.0,"proposals":[]}',
      '{"schema_version":2,"schema_version":1,"proposals":[]}',
      response([proposal()]).replaceFirst(
        '"action":"delete_text"',
        r'"action":"run_script","\u0061ction":"delete_text"',
      ),
      '```json\n${response([])}\n```',
      '正文' * 20000,
      'not JSON',
    ]) {
      expect(
        () => AiTextProposalDecoder.decode(body, context: context('广告')),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('does not allow editing unseen text', () {
    final text = '前文' * 900;
    final plan = AiContextPlanner.plan(
      bookId: 'book',
      sessionId: 'session',
      sessionRevision: 4,
      maxChunkCharacters: 1024,
      blocks: <AiContextBlock>[
        AiContextBlock(
          chapterId: 'chapter',
          chapterTitle: '第一章',
          blockId: 'block',
          text: '$text广告结尾',
        ),
      ],
    );
    expect(
      () => AiTextProposalDecoder.decode(
        response([proposal()]),
        context: plan.chunks.first,
      ),
      throwsA(isA<ValidationFailure>()),
    );
    final result = AiTextProposalDecoder.decode(
      response([proposal()]),
      context: plan.chunks.last,
    );
    expect(result.proposals.single.range.start, text.length);
  });

  test('does not allow editing a neighbor shown only as overlap context', () {
    AiContextPlan split(String text) => AiContextPlanner.plan(
      bookId: 'book',
      sessionId: 'session',
      sessionRevision: 4,
      maxChunkCharacters: 1024,
      blocks: <AiContextBlock>[
        AiContextBlock(
          chapterId: 'chapter',
          chapterTitle: '第一章',
          blockId: 'block',
          text: text,
        ),
      ],
    );
    final plain = '文' * 1600;
    final boundary = split(plain).chunks.first.slices.single.endUtf16;
    final modified = plain.replaceRange(boundary + 1, boundary + 3, '广告');
    final result = split(modified);
    expect(result.chunks.first.slices.single.after, contains('广告'));
    expect(
      () => AiTextProposalDecoder.decode(
        response([proposal()]),
        context: result.chunks.first,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'a block above one Mi UTF-16 units can plan and validate consistently',
    () {
      final text = '广告${'文' * 1048576}';
      final plan = AiContextPlanner.plan(
        bookId: 'book',
        sessionId: 'session',
        sessionRevision: 4,
        maxChunkCharacters: 65536,
        blocks: <AiContextBlock>[
          AiContextBlock(
            chapterId: 'chapter',
            chapterTitle: '第一章',
            blockId: 'block',
            text: text,
          ),
        ],
      );
      final result = AiTextProposalDecoder.decode(
        response([proposal()]),
        context: plan.chunks.first,
      );
      expect(result.proposals.single.range.start, 0);
      expect(result.proposals.single.range.end, 2);
    },
  );

  test('failure diagnostics do not echo untrusted source or response', () {
    try {
      AiTextProposalDecoder.decode('秘密书稿和密钥', context: context('私有正文'));
      fail('Expected validation failure');
    } on ValidationFailure catch (error) {
      expect(error.toString(), isNot(contains('秘密')));
      expect(error.toString(), isNot(contains('私有正文')));
    }
  });
}
