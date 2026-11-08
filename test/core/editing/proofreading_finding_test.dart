import 'dart:convert';

import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/editing/proofreading_finding.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

AiContextChunk _context(String text) => AiContextPlanner.plan(
  bookId: 'book',
  sessionId: 'session',
  sessionRevision: 7,
  blocks: [
    AiContextBlock(
      chapterId: 'chapter',
      chapterTitle: '第一章',
      blockId: 'block',
      text: text,
    ),
  ],
).chunks.single;

Map<String, Object> _finding({
  String id = 'finding',
  String category = 'advertisement',
  String assessment = 'undetermined',
  String original = '广告',
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
  'reason': '仅供人工判断，不自动删除。',
};

String _response(List<Map<String, Object>> findings) =>
    jsonEncode({'schema_version': 1, 'findings': findings});

Book _book({String title = '第一章', String text = '正文'}) => Book(
  id: 'book',
  meta: BookMeta(title: '测试'),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  chapters: [
    Chapter(
      id: 'chapter',
      bookId: 'book',
      title: title,
      blocks: [TextBlock(id: 'block', text: text)],
    ),
  ],
);

AuditReport _audit({
  AuditIssueKind kind = AuditIssueKind.missingNumber,
  int total = 1,
  String? blockId,
  String title = '第一章',
}) => AuditReport(
  {kind: total},
  [
    AuditIssue(
      kind: kind,
      chapterId: 'chapter',
      chapterIndex: 0,
      chapterTitle: title,
      message: '需人工核对。',
      blockId: blockId,
    ),
  ],
);

void main() {
  test('local finding identity preserves verified evidence and rejects invalid ids', () {
    final original = AiFindingDecoder.decode(
      _response([_finding()]),
      context: _context('😀广告结束'),
    ).single;
    final copied = original.withId('task-1-chunk-0-finding-0');
    expect(copied.id, 'task-1-chunk-0-finding-0');
    expect(original.id, 'finding');
    expect(copied.target, same(original.target));
    expect(copied.range, same(original.range));
    expect(copied.source, original.source);
    expect(copied.assessment, original.assessment);
    expect(copied.evidence, original.evidence);
    expect(() => original.withId(''), throwsA(isA<ValidationFailure>()));
    final chapter = Finding.chapter(
      id: 'local',
      bookId: 'book',
      sessionId: 'session',
      sessionRevision: 7,
      chapterId: 'chapter',
      kind: FindingKind.other,
      assessment: FindingAssessment.observed,
      source: FindingSource.customRule,
      sourceId: 'rule',
      evidence: '章节',
      reason: '本地发现',
    );
    final localCopy = chapter.withId('local-2');
    expect(localCopy.sourceId, 'rule');
    expect(localCopy.target, isNull);
    expect(localCopy.evidence, '章节');
  });

  test('AI findings retain uncertainty and only local session identity', () {
    final findings = AiFindingDecoder.decode(
      _response([_finding()]),
      context: _context('😀广告结束'),
    );
    final finding = findings.single;
    expect(finding.source, FindingSource.ai);
    expect(finding.assessment, FindingAssessment.undetermined);
    expect(finding.bookId, 'book');
    expect(finding.sessionId, 'session');
    expect(finding.sessionRevision, 7);
    expect(finding.range!.start, 2);
    expect(finding.range!.end, 4);
    expect(finding.evidence, '广告');
    expect(findings.clear, throwsUnsupportedError);
  });

  test('ad distinctions are diagnostics, not executable replacements', () {
    for (final assessment in [
      'undetermined',
      'advertisement',
      'author_note',
      'story_quote',
      'not_advertisement',
    ]) {
      final finding = AiFindingDecoder.decode(
        _response([_finding(assessment: assessment)]),
        context: _context('广告'),
      ).single;
      expect(finding.reason, isNotEmpty);
      expect(finding.target!.originalText, '广告');
    }
  });

  test('missing chapter distinctions do not invent missing content', () {
    for (final assessment in [
      'undetermined',
      'suspected_missing',
      'missed_heading',
      'merged_content',
      'numbering_suspect',
    ]) {
      final finding = AiFindingDecoder.decode(
        _response([
          _finding(category: 'missing_chapter', assessment: assessment),
        ]),
        context: _context('广告'),
      ).single;
      expect(finding.kind, FindingKind.missingChapter);
      expect(finding.evidence, '广告');
    }
  });

  test('rejects invalid category and assessment combinations', () {
    for (final value in [
      _finding(assessment: 'suspected_missing'),
      _finding(category: 'missing_chapter', assessment: 'advertisement'),
      _finding(category: 'execute_script'),
      _finding(assessment: 'definitely_missing'),
    ]) {
      expect(
        () => AiFindingDecoder.decode(
          _response([value]),
          context: _context('广告'),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    }
  });

  test('requires exact unique evidence with adjacent disambiguation', () {
    expect(
      () => AiFindingDecoder.decode(
        _response([_finding()]),
        context: _context('前广告后，另广告尾'),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    final finding = AiFindingDecoder.decode(
      _response([_finding(before: '另', after: '尾')]),
      context: _context('前广告后，另广告尾'),
    ).single;
    expect(finding.range!.start, 6);
    expect(
      () => AiFindingDecoder.decode(
        _response([_finding(original: '不存在')]),
        context: _context('广告'),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('rejects evidence or context that was not sent in the core slice', () {
    final block = AiContextBlock(
      chapterId: 'chapter',
      chapterTitle: '第一章',
      blockId: 'block',
      text: '前广告后',
    );
    final context = AiContextChunk(
      bookId: 'book',
      sessionId: 'session',
      sessionRevision: 7,
      index: 0,
      slices: [
        AiContextSlice(
          block: block,
          startUtf16: 3,
          endUtf16: 4,
          before: '广告',
          text: '后',
          after: '',
        ),
      ],
    );
    expect(
      () => AiFindingDecoder.decode(_response([_finding()]), context: context),
      throwsA(isA<ValidationFailure>()),
    );
    final unavailable = _finding()..['block_id'] = 'another-block';
    expect(
      () => AiFindingDecoder.decode(
        _response([unavailable]),
        context: _context('广告'),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'duplicate ids, keys, unknown instructions, and spoofed identity fail',
    () {
      final context = _context('广告');
      final invalid = <String>[
        _response([_finding(), _finding()]),
        '{"schema_version":1,"schema_version":1,"findings":[]}',
        _response([_finding()..['script'] = 'erase()']),
        _response([_finding()..['session_revision'] = 7]),
        jsonEncode({
          'schema_version': 1,
          'findings': <Object>[],
          'execute': true,
        }),
      ];
      for (final response in invalid) {
        expect(
          () => AiFindingDecoder.decode(response, context: context),
          throwsA(isA<ValidationFailure>()),
        );
      }
    },
  );

  test(
    'enforces response, count, string and Unicode budgets without echoing',
    () {
      final context = _context('广告');
      final invalid = <String>[
        'x' * 65537,
        _response(List.generate(101, (index) => _finding(id: '$index'))),
        _response([_finding()..['reason'] = 'private-marker' * 100]),
        _response([_finding()..['reason'] = '\ud800']),
        _response([_finding(original: '')]),
        _response([_finding(id: ' ')]),
      ];
      for (final response in invalid) {
        try {
          AiFindingDecoder.decode(response, context: context);
          fail('Invalid findings accepted');
        } on ValidationFailure catch (error) {
          expect(error.toString(), isNot(contains('private-marker')));
        }
      }
    },
  );

  test(
    'all built-in audit types keep total coverage separate from samples',
    () {
      for (final kind in AuditIssueKind.values) {
        final report = AuditFindingAdapter.convert(
          report: _audit(
            kind: kind,
            total: 23,
            blockId: kind == AuditIssueKind.adLeftover ? 'block' : null,
          ),
          book: _book(),
          sessionId: 'session',
          sessionRevision: 7,
        );
        expect(report.totalCount, 23);
        expect(report.findings.length, 1);
        expect(report.hasMore, isTrue);
        expect(report.findings.single.source, FindingSource.builtIn);
        expect(report.findings.single.target, isNull);
        expect(report.findings.clear, throwsUnsupportedError);
        if (kind == AuditIssueKind.adLeftover ||
            kind == AuditIssueKind.missingNumber) {
          expect(
            report.findings.single.assessment,
            FindingAssessment.undetermined,
          );
        }
      }
    },
  );

  test('duplicate content audit maps to a neutral observed finding', () {
    final report = AuditFindingAdapter.convert(
      report: _audit(kind: AuditIssueKind.duplicateContent),
      book: _book(),
      sessionId: 'session',
      sessionRevision: 7,
    );
    final finding = report.findings.single;
    expect(finding.kind, FindingKind.other);
    expect(finding.assessment, FindingAssessment.observed);
    expect(finding.sourceId, 'audit.duplicateContent');
  });

  test('title format audit maps to a neutral observed finding', () {
    final report = AuditFindingAdapter.convert(
      report: _audit(kind: AuditIssueKind.titleFormat),
      book: _book(),
      sessionId: 'session',
      sessionRevision: 7,
    );
    final finding = report.findings.single;
    expect(finding.kind, FindingKind.other);
    expect(finding.assessment, FindingAssessment.observed);
    expect(finding.sourceId, 'audit.titleFormat');
  });

  test('built-in findings refer to current book data and safe excerpts', () {
    final text = '${'甲' * 1023}😀尾';
    final report = AuditFindingAdapter.convert(
      report: _audit(kind: AuditIssueKind.adLeftover, blockId: 'block'),
      book: _book(text: text),
      sessionId: 'session',
      sessionRevision: 7,
    );
    expect(report.findings.single.evidence, '甲' * 1023);
    expect(
      () => AuditFindingAdapter.convert(
        report: _audit(title: '旧标题'),
        book: _book(),
        sessionId: 'session',
        sessionRevision: 7,
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => AuditFindingAdapter.convert(
        report: _audit(blockId: 'missing'),
        book: _book(),
        sessionId: 'session',
        sessionRevision: 7,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'real audit advertisement excerpts do not split an emoji surrogate pair',
    () {
      final text = '爱下电子书${'甲' * 26}😀尾';
      final book = _book(text: text);
      final audit = Proofreading.audit(book);
      final report = AuditFindingAdapter.convert(
        report: audit,
        book: book,
        sessionId: 'session',
        sessionRevision: 7,
      );
      final advertisement = report.findings.singleWhere(
        (finding) => finding.kind == FindingKind.advertisement,
      );
      expect(advertisement.reason, contains('爱下电子书${'甲' * 26}…'));
      expect(advertisement.evidence, text);
      expect(report.totalCount, audit.total);
    },
  );

  test('reports reject inconsistent counts and mixed editing sessions', () {
    expect(
      () => AuditFindingAdapter.convert(
        report: _audit(total: 0),
        book: _book(),
        sessionId: 'session',
        sessionRevision: 7,
      ),
      throwsA(isA<ValidationFailure>()),
    );
    final first = AiFindingDecoder.decode(
      _response([_finding()]),
      context: _context('广告'),
    ).single;
    final second = Finding.chapter(
      id: 'another',
      bookId: 'book',
      sessionId: 'another-session',
      sessionRevision: 7,
      chapterId: 'chapter',
      kind: FindingKind.other,
      assessment: FindingAssessment.observed,
      source: FindingSource.builtIn,
      evidence: '',
      reason: '需核对。',
    );
    expect(
      () => FindingReport(findings: [first, second], totalCount: 2),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('untrusted AI cannot create an unlocated chapter finding', () {
    expect(
      () => Finding.chapter(
        id: 'finding',
        bookId: 'book',
        sessionId: 'session',
        sessionRevision: 7,
        chapterId: 'chapter',
        kind: FindingKind.other,
        assessment: FindingAssessment.observed,
        source: FindingSource.ai,
        evidence: '',
        reason: '无定位。',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => Finding.chapter(
        id: 'finding',
        bookId: 'book',
        sessionId: 'session',
        sessionRevision: 7,
        chapterId: 'chapter',
        kind: FindingKind.other,
        assessment: FindingAssessment.observed,
        source: FindingSource.customRule,
        evidence: '',
        reason: '未给规则标识。',
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
