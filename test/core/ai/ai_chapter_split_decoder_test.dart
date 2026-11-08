import 'dart:convert';

import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_chapter_split_decoder.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

AiContextChunk _context(String text, {int start = 0, int? end}) {
  final block = AiContextBlock(
    chapterId: 'chapter',
    chapterTitle: '第十二章',
    blockId: 'block',
    text: text,
  );
  final coreEnd = end ?? text.length;
  return AiContextChunk(
    bookId: 'book',
    sessionId: 'session',
    sessionRevision: 7,
    index: 0,
    slices: [
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

Map<String, Object?> _split({
  String id = 'split-1',
  String original = '第十三章 风雨',
  String before = '',
  String after = '',
  String title = '第十三章 风雨',
  bool removeTitleLine = true,
}) => {
  'id': id,
  'action': 'split_chapter',
  'chapter_id': 'chapter',
  'block_id': 'block',
  'original': original,
  'before': before,
  'after': after,
  'title': title,
  'remove_title_line': removeTitleLine,
  'reason': '已有独立标题行，建议拆章。',
};

Map<String, Object?> _finding({
  String id = 'heading-1',
  String category = 'missing_chapter',
  String assessment = 'missed_heading',
  String original = '第十三章 风雨',
  String before = '',
  String after = '',
}) => {
  'id': id,
  'category': category,
  'assessment': assessment,
  'chapter_id': 'chapter',
  'block_id': 'block',
  'original': original,
  'before': before,
  'after': after,
  'reason': '原文存在独立标题行。',
};

String _standalone(List<Object?> proposals) =>
    jsonEncode({'schema_version': 1, 'proposals': proposals});

String _envelope({
  List<Object?> findings = const [],
  List<Object?> proposals = const [],
}) => jsonEncode({
  'schema_version': 1,
  'findings': findings,
  'proposals': proposals,
  'rule_proposals': <Object>[],
});

AiAnalysisResult _decode(
  AiContextChunk context, {
  List<Object?> findings = const [],
  List<Object?> proposals = const [],
}) => AiAnalysisResultDecoder.decode(
  _envelope(findings: findings, proposals: proposals),
  context: context,
  responseId: 'local',
);

void main() {
  test('ordinary AI split output cannot request a volume container', () {
    for (final field in [
      'heading_level',
      'volume_id',
      'heading_number',
      'number_evidence_range',
    ]) {
      final proposal = _split()..[field] = 1;
      expect(
        () => AiChapterSplitDecoder.decode(
          _standalone([proposal]),
          context: _context('第十三章 风雨\n正文'),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('AI split output cannot opt into local rule title mappings', () {
    const source = '【第十三章 风雨】\n正文';
    for (final field in <String?>[
      null,
      'title_source_range',
      'title_evidence_range',
    ]) {
      final proposal = _split(original: '【第十三章 风雨】');
      if (field != null) proposal[field] = <int>[1, 8];
      expect(
        () => AiChapterSplitDecoder.decode(
          _standalone([proposal]),
          context: _context(source),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test(
    'mixed envelope keeps text and split products separate and immutable',
    () {
      const source = '😀前章正文\r\n  第十三章 风雨  \r\n正文广告正文';
      final heading = _split(before: '  ', after: '  \r\n')
        ..['finding_id'] = 'heading-1';
      final deletion = <String, Object?>{
        'id': 'text-1',
        'finding_id': 'ad-1',
        'action': 'delete_text',
        'chapter_id': 'chapter',
        'block_id': 'block',
        'original': '广告',
        'before': '正文',
        'after': '正文',
        'replacement': '',
        'reason': '明确的广告片段。',
      };
      final result = _decode(
        _context(source),
        findings: [
          _finding(before: '  ', after: '  \r\n'),
          _finding(
            id: 'ad-1',
            category: 'advertisement',
            assessment: 'advertisement',
            original: '广告',
            before: '正文',
            after: '正文',
          ),
        ],
        proposals: [deletion, heading],
      );
      final split = result.chapterSplits.single;
      expect(split.range.start, source.indexOf('第十三章'));
      expect(split.range.end, split.range.start + '第十三章 风雨'.length);
      expect(split.target.bookId, 'book');
      expect(split.target.sessionId, 'session');
      expect(split.target.sessionRevision, 7);
      expect(split.title, '第十三章 风雨');
      expect(split.removeTitleLine, isTrue);
      final line = split.titleLineIn(source, split.range);
      expect(source.substring(line.start, line.end), '  第十三章 风雨  \r\n');
      expect(result.textChanges.proposals.single.id, 'text-1');
      expect(result.findingIdByTextProposalId, {'text-1': 'ad-1'});
      expect(result.findingIdBySplitProposalId, {'split-1': 'heading-1'});
      expect(result.chapterSplits.clear, throwsUnsupportedError);
      expect(result.findingIdBySplitProposalId.clear, throwsUnsupportedError);
    },
  );

  test('locates repeated headings uniquely with UTF-16 context', () {
    const source = '😀\n第十三章 风雨\n中段\n第十三章 风雨\n正文';
    final context = _context(source);
    expect(
      () => AiChapterSplitDecoder.decode(
        _standalone([_split()]),
        context: context,
      ),
      throwsA(isA<ValidationFailure>()),
    );
    final result = AiChapterSplitDecoder.decode(
      _standalone([_split(before: '😀\n', after: '\n中段')]),
      context: context,
    );
    expect(result.single.range.start, 3);
    expect(result.single.range.end, 3 + '第十三章 风雨'.length);
    expect(result.clear, throwsUnsupportedError);
  });

  test('requires a complete independent heading without invented title', () {
    for (final (source, proposal) in [
      ('正文第十三章 风雨\n后文', _split()),
      ('第十三章 风雨 后接正文\n', _split()),
      ('第十三章 风雨\n', _split(title: '第十四章 风雨')),
      ('第十三章 风雨\n', _split(title: '第十三章 风雨\n正文')),
      ('第十三章 风雨\n', _split(original: '第十三章 风雨\n')),
      ('第十三章 风雨\n', _split(title: '题' * 257)),
    ]) {
      expect(
        () => AiChapterSplitDecoder.decode(
          _standalone([proposal]),
          context: _context(source),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('enforces the core boundary for original and the affected line', () {
    const source = '前文\n  第十三章 风雨  \r\n正文';
    final lineStart = source.indexOf('  第十三章');
    final originalStart = source.indexOf('第十三章');
    final originalEnd = originalStart + '第十三章 风雨'.length;
    final lineEnd = source.indexOf('\n', originalEnd) + 1;
    expect(
      () => AiChapterSplitDecoder.decode(
        _standalone([_split()]),
        context: _context(source, start: originalStart),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => AiChapterSplitDecoder.decode(
        _standalone([_split(removeTitleLine: false)]),
        context: _context(source, start: originalStart),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => AiChapterSplitDecoder.decode(
        _standalone([_split()]),
        context: _context(source, start: lineStart, end: originalEnd),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => AiChapterSplitDecoder.decode(
        _standalone([_split()]),
        context: _context(source, start: lineStart, end: lineEnd - 1),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    final preserved = AiChapterSplitDecoder.decode(
      _standalone([_split(removeTitleLine: false)]),
      context: _context(source, start: lineStart, end: originalEnd),
    );
    expect(preserved.single.removeTitleLine, isFalse);
    expect(
      AiChapterSplitDecoder.decode(
        _standalone([_split()]),
        context: _context(source, start: lineStart, end: lineEnd),
      ),
      hasLength(1),
    );
    expect(
      () => AiChapterSplitDecoder.decode(
        _standalone([_split()]),
        context: _context(source, end: originalStart),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('rejects uncertain and protected evidence overlapping a split', () {
    for (final (category, assessment) in [
      ('missing_chapter', 'undetermined'),
      ('missing_chapter', 'suspected_missing'),
      ('missing_chapter', 'numbering_suspect'),
      ('advertisement', 'author_note'),
      ('advertisement', 'story_quote'),
      ('advertisement', 'not_advertisement'),
    ]) {
      expect(
        () => _decode(
          _context('第十三章 风雨\n正文'),
          findings: [
            _finding(),
            _finding(
              id: 'protected',
              category: category,
              assessment: assessment,
            ),
          ],
          proposals: [_split()..['finding_id'] = 'heading-1'],
        ),
        throwsA(isA<ValidationFailure>()),
        reason: assessment,
      );
    }
    expect(
      () => _decode(
        _context('第十三章 风雨  \n正文'),
        findings: [
          _finding(),
          _finding(
            id: 'protected-line-end',
            category: 'advertisement',
            assessment: 'author_note',
            original: '  \n正文',
            before: '第十三章 风雨',
          ),
        ],
        proposals: [_split()..['finding_id'] = 'heading-1'],
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('requires a matching determinate finding covering the full split', () {
    final context = _context('第十三章 风雨\n正文');
    for (final proposal in [
      _split(),
      _split()..['finding_id'] = 'missing',
      _split()..['finding_id'] = 'other',
      _split()
        ..['finding_id'] = 'heading-1'
        ..['block_id'] = 'asset',
    ]) {
      expect(
        () => _decode(context, findings: [_finding()], proposals: [proposal]),
        throwsA(isA<ValidationFailure>()),
      );
    }
    expect(
      () => _decode(
        context,
        findings: [_finding(assessment: 'undetermined')],
        proposals: [_split()..['finding_id'] = 'heading-1'],
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => _decode(
        context,
        findings: [_finding(original: '十三章', before: '第', after: ' 风雨')],
        proposals: [_split()..['finding_id'] = 'heading-1'],
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'keeps competing splits and intersecting deletion for conflict review',
    () {
      final context = _context('第十三章 风雨\n正文');
      final result = _decode(
        context,
        findings: [
          _finding(),
          _finding(
            id: 'ad',
            category: 'advertisement',
            assessment: 'advertisement',
          ),
        ],
        proposals: [
          _split()..['finding_id'] = 'heading-1',
          _split(id: 'split-2', removeTitleLine: false)
            ..['finding_id'] = 'heading-1',
          {
            'id': 'delete',
            'finding_id': 'ad',
            'action': 'delete_text',
            'chapter_id': 'chapter',
            'block_id': 'block',
            'original': '第十三章 风雨',
            'before': '',
            'after': '',
            'replacement': '',
            'reason': '冲突候选，留待用户判断。',
          },
        ],
      );
      expect(result.chapterSplits, hasLength(2));
      expect(result.textChanges.proposals, hasLength(1));
    },
  );

  test('rejects malformed schema, scripts, forged targets and bad UTF-16', () {
    final context = _context('第十三章 风雨\n正文');
    final surrogate = String.fromCharCode(0xd800);
    for (final proposal in [
      _split()..remove('title'),
      _split()..['replacement'] = '',
      _split()..['resource_id'] = 'asset',
      _split()..['new_chapter_id'] = 'chosen-by-model',
      _split()..['script'] = 'run()',
      _split()..['action'] = 'run_script',
      _split()..['remove_title_line'] = 'true',
      _split()..['block_id'] = 'asset',
      _split()..['chapter_id'] = 'other',
      _split()..['title'] = surrogate,
      _split()..['original'] = surrogate,
      _split()..['reason'] = surrogate,
    ]) {
      expect(
        () => AiChapterSplitDecoder.decode(
          _standalone([proposal]),
          context: context,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
    for (final response in [
      _standalone([_split(), _split()]),
      '{"schema_version":1,"proposals":[],"script":"run()"}',
      '{"schema_version":1.0,"proposals":[]}',
      '{"schema_version":1,"proposals":[],"proposals":[]}',
      _standalone([_split()]).replaceFirst(
        '"action":"split_chapter"',
        '"action":"run_script","action":"split_chapter"',
      ),
    ]) {
      expect(
        () => AiChapterSplitDecoder.decode(response, context: context),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('one invalid split rejects an otherwise valid mixed envelope', () {
    final context = _context('第十三章 风雨\n正文');
    expect(
      () => _decode(
        context,
        findings: [_finding()],
        proposals: [
          _split()..['finding_id'] = 'heading-1',
          _split(id: 'unsafe')
            ..['finding_id'] = 'heading-1'
            ..['resource_id'] = 'asset',
        ],
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => _decode(
        context,
        findings: [_finding()],
        proposals: [_split(id: 'heading-1')..['finding_id'] = 'heading-1'],
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => _decode(
        context,
        findings: List.generate(100, (index) => _finding(id: 'finding-$index')),
        proposals: [_split()..['finding_id'] = 'finding-0'],
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
