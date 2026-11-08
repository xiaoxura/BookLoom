import 'dart:async';
import 'dart:convert';

import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/features/editor/application/ai_rule_creation_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter_test/flutter_test.dart';

const _configuration = AiConfiguration(
  enabled: true,
  address: 'https://api.example.com/v1',
  model: 'test-model',
  credentialReference: 'local-credential',
);
const _source = '前文\n  【卷二】夜雨  \n后文';
const _heading = '  【卷二】夜雨  ';
const _ad = ' 访问测试站点领取奖励。 ';

void main() {
  late _Fixture fixture;

  setUp(() async {
    fixture = await _Fixture.open();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test(
    'prepare preserves exact bounded selection and reads no credentials',
    () async {
      final draft = '未保存$_source';
      fixture.session.editBlockText('p1', draft);
      final revision = fixture.session.saveSeq;
      await fixture.prepare();

      expect(fixture.task.phase, AiRuleCreationPhase.awaitingConsent);
      expect(fixture.task.isBusy, isFalse);
      expect(fixture.session.saveSeq, revision);
      expect(fixture.session.dirty, isTrue);
      expect(fixture.store.loads, ['book/a']);
      expect(fixture.store.saves, 0);
      expect(fixture.credentials.reads, 0);
      expect(fixture.clients, isEmpty);
      final consent = fixture.task.consent!;
      expect(consent.configuration, _configuration.canonicalized());
      expect(consent.request.positiveExamples, [_heading]);
      expect(consent.request.negativeExamples, ['【卷二】风雨']);
      expect(consent.chunk.slices, hasLength(1));
      final slice = consent.chunk.slices.single;
      expect(slice.text, _heading);
      expect(slice.block.text, draft);
      expect(slice.before, '未保存前文\n');
      expect(slice.after, '\n后文');
      expect(slice.startUtf16, draft.indexOf(_heading));
      expect(slice.endUtf16, draft.indexOf(_heading) + _heading.length);
    },
  );

  test('context clips adjacent UTF-16 without splitting emoji', () async {
    final source = '😀${'x' * 511}$_heading${'z' * 511}😀';
    fixture.session.editBlockText('p1', source);
    await fixture.prepare(selection: _selection(source, _heading));

    expect(fixture.task.phase, AiRuleCreationPhase.awaitingConsent);
    final slice = fixture.task.consent!.chunk.slices.single;
    expect(slice.before, 'x' * 511);
    expect(slice.after, 'z' * 511);
    expect(slice.before.length, lessThanOrEqualTo(512));
    expect(slice.after.length, lessThanOrEqualTo(512));
    expect(slice.block.text, source);
    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.phase, AiRuleCreationPhase.completed);
    final userContext = fixture.clients.single.calls.single.userContext;
    final request =
        (jsonDecode(userContext) as Map<String, dynamic>)['context']
            as Map<String, dynamic>;
    final encodedSlice =
        (request['blocks'] as List<dynamic>).single as Map<String, dynamic>;
    expect(encodedSlice['start_utf16'], source.indexOf(_heading));
    expect(
      encodedSlice['end_utf16'],
      source.indexOf(_heading) + _heading.length,
    );
    expect(encodedSlice['block_length_utf16'], source.length);
    expect(encodedSlice['text'], _heading);
    expect(userContext, isNot(contains(source)));
    expect(userContext, isNot(contains('后章正文')));
  });

  test(
    'invalid selection and samples stop before configuration access',
    () async {
      fixture.session.editBlockText('p1', '😀$_heading\n尾文');
      final source =
          (fixture.session.activeChapter!.blocks.single as TextBlock).text;
      final valid = _selection(source, _heading);
      final invalid =
          <
            ({AiRuleSelection selection, List<String> negatives, String intent})
          >[
            (
              selection: AiRuleSelection(
                chapterId: 'b',
                blockId: 'p1',
                startUtf16: valid.startUtf16,
                endUtf16: valid.endUtf16,
                original: _heading,
              ),
              negatives: const [],
              intent: '识别',
            ),
            (
              selection: AiRuleSelection(
                chapterId: 'a',
                blockId: 'missing',
                startUtf16: valid.startUtf16,
                endUtf16: valid.endUtf16,
                original: _heading,
              ),
              negatives: const [],
              intent: '识别',
            ),
            (
              selection: AiRuleSelection(
                chapterId: 'a',
                blockId: 'p1',
                startUtf16: 1,
                endUtf16: 3,
                original: '\uDE00',
              ),
              negatives: const [],
              intent: '识别',
            ),
            (
              selection: AiRuleSelection(
                chapterId: 'a',
                blockId: 'p1',
                startUtf16: valid.startUtf16,
                endUtf16: valid.endUtf16,
                original: '不匹配',
              ),
              negatives: const [],
              intent: '识别',
            ),
            (
              selection: AiRuleSelection(
                chapterId: 'a',
                blockId: 'p1',
                startUtf16: 0,
                endUtf16: source.length,
                original: source,
              ),
              negatives: const [],
              intent: '识别',
            ),
            (selection: valid, negatives: const ['非法\n反例'], intent: '识别'),
            (selection: valid, negatives: const ['\uD800'], intent: '识别'),
            (selection: valid, negatives: ['x' * 2049], intent: '识别'),
            (
              selection: valid,
              negatives: List<String>.filled(9, '反例'),
              intent: '识别',
            ),
            (selection: valid, negatives: const [], intent: ' '),
            (selection: valid, negatives: const [], intent: 'x' * 1025),
          ];
      for (final input in invalid) {
        await fixture.task.prepare(
          selection: input.selection,
          kind: ProofreadingRuleKind.chapter,
          intent: input.intent,
          negativeExamples: input.negatives,
        );
        expect(fixture.task.phase, AiRuleCreationPhase.failed);
        expect(fixture.task.failure, isA<ValidationFailure>());
        expect(fixture.task.consent, isNull);
      }
      expect(fixture.configurationLoads, 0);
      expect(fixture.credentials.reads, 0);
      expect(fixture.clients, isEmpty);
      final otherBookRule = ProofreadingRule.create(
        id: 'other-rule',
        name: '其他书规则',
        kind: ProofreadingRuleKind.chapter,
        source: ProofreadingRuleSource.user,
        bookId: 'other',
        target: ProofreadingRuleTarget.headingLine,
        mode: ProofreadingMatchMode.literal,
        pattern: '其他',
        caseSensitive: true,
        action: ProofreadingRuleAction.chapterCandidate,
        positiveExamples: const ['其他'],
        negativeExamples: const [],
      );
      await fixture.task.prepare(
        selection: valid,
        kind: ProofreadingRuleKind.chapter,
        intent: '识别',
        negativeExamples: const [],
        relatedRules: [otherBookRule],
      );
      expect(fixture.task.phase, AiRuleCreationPhase.failed);
      expect(fixture.configurationLoads, 0);
    },
  );

  test(
    'disabled default and missing credential reject without network',
    () async {
      for (final configuration in [
        const AiConfiguration(),
        const AiConfiguration(
          enabled: true,
          address: 'https://api.example.com/v1',
          model: 'model',
        ),
      ]) {
        fixture.configuration = configuration;
        await fixture.prepare();
        expect(fixture.task.phase, AiRuleCreationPhase.failed);
        expect(fixture.task.consent, isNull);
        expect(fixture.credentials.reads, 0);
        expect(fixture.clients, isEmpty);
      }
    },
  );

  test(
    'configuration changes before run or during key read prevent request',
    () async {
      await fixture.prepare();
      final firstConsent = fixture.task.consent!;
      fixture.configuration = _configurationAt(
        'https://changed.example.com/v1',
      );
      await fixture.task.run(firstConsent);
      expect(fixture.task.phase, AiRuleCreationPhase.failed);
      expect(fixture.credentials.reads, 0);

      fixture.configuration = _configuration;
      await fixture.prepare();
      fixture.credentials.gate = Completer<String?>();
      fixture.credentials.started = Completer<void>();
      final running = fixture.task.run(fixture.task.consent!);
      await fixture.credentials.started!.future;
      fixture.configuration = _configurationAt(
        'https://changed.example.com/v1',
      );
      fixture.credentials.gate!.complete('test-key');
      await running;
      expect(fixture.task.phase, AiRuleCreationPhase.failed);
      expect(fixture.task.proposals, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test(
    'configuration changes after response discard decoded proposals',
    () async {
      fixture.responder = (call) async {
        fixture.configuration = _configurationAt(
          'https://changed.example.com/v1',
        );
        return _ruleResponse(kind: 'chapter', pattern: '【卷二】夜雨');
      };
      await fixture.prepare();
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiRuleCreationPhase.failed);
      expect(fixture.task.proposals, isEmpty);
      expect(fixture.task.canUseProposals, isFalse);
    },
  );

  test(
    'manual edit, book switch, close and cancellation reject late response',
    () async {
      final changes = <(AiRuleCreationPhase, Future<void> Function())>[
        (
          AiRuleCreationPhase.stale,
          () async => fixture.session.editBlockText('p1', '人工改稿'),
        ),
        (AiRuleCreationPhase.stale, () => fixture.session.open('other')),
        (
          AiRuleCreationPhase.stale,
          () async {
            await fixture.session.close();
            fixture.sessionClosed = true;
          },
        ),
        (AiRuleCreationPhase.cancelled, () async => fixture.task.cancel()),
      ];
      for (final (index, change) in changes.indexed) {
        if (index != 0) {
          await fixture.dispose();
          fixture = await _Fixture.open();
        }
        final gate = Completer<String>();
        final started = Completer<void>();
        fixture.responder = (call) {
          started.complete();
          return gate.future;
        };
        await fixture.prepare();
        final running = fixture.task.run(fixture.task.consent!);
        await started.future;
        await change.$2();
        gate.complete(_ruleResponse(kind: 'chapter', pattern: '【卷二】夜雨'));
        await running;
        expect(fixture.task.proposals, isEmpty);
        expect(fixture.task.canUseProposals, isFalse);
        expect(fixture.task.phase, change.$1);
      }
    },
  );

  test('invalid model rules and non-rule products fail atomically', () async {
    final invalid = [
      _ruleResponse(kind: 'chapter', pattern: '.*'),
      _ruleResponse(kind: 'advertisement', pattern: '【卷二】夜雨'),
      _ruleResponse(
        kind: 'chapter',
        pattern: '【卷二】夜雨',
        extra: {'script': 'run'},
      ),
      _ruleResponse(
        kind: 'chapter',
        pattern: '【卷二】夜雨',
        findings: [
          {'id': 'bad'},
        ],
      ),
      jsonEncode({
        'schema_version': 1,
        'findings': <Object>[],
        'proposals': [
          {'action': 'run_script'},
        ],
        'rule_proposals': <Object>[],
      }),
    ];
    for (final response in invalid) {
      fixture.responder = (call) async => response;
      await fixture.prepare();
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiRuleCreationPhase.failed);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.proposals, isEmpty);
      expect(fixture.store.saves, 0);
    }
  });

  test('a valid finding in a rule response is rejected', () async {
    fixture.responder = (call) async => jsonEncode({
      'schema_version': 1,
      'findings': [
        {
          'id': 'model-finding',
          'category': 'other',
          'assessment': 'observed',
          'chapter_id': 'a',
          'block_id': 'p1',
          'original': '【卷二】夜雨',
          'before': '  ',
          'after': '  ',
          'reason': '模型擅自生成发现项',
        },
      ],
      'proposals': <Object>[],
      'rule_proposals': [
        (jsonDecode(_ruleResponse(kind: 'chapter', pattern: '【卷二】夜雨'))
            as Map<String, dynamic>)['rule_proposals'][0],
      ],
    });
    await fixture.prepare();
    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.phase, AiRuleCreationPhase.failed);
    expect(fixture.task.proposals, isEmpty);
  });

  test(
    'valid chapter and ad candidates retain supplied examples without writes',
    () async {
      fixture.session.editBlockText('p1', _source);
      fixture.responder = (call) async =>
          _ruleResponse(kind: 'chapter', pattern: '【卷二】夜雨');
      await fixture.prepare();
      final revision = fixture.session.saveSeq;
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiRuleCreationPhase.completed);
      expect(fixture.task.canUseProposals, isTrue);
      final chapter = fixture.task.proposals.single;
      expect(chapter.reason, '保守匹配');
      expect(chapter.rule.positiveExamples, containsAll([_heading, '【卷二】夜雨']));
      expect(chapter.rule.negativeExamples, containsAll(['【卷二】风雨', '普通正文']));
      expect(chapter.rule.kind, ProofreadingRuleKind.chapter);
      expect(chapter.rule.source, ProofreadingRuleSource.ai);
      expect(chapter.rule.scope, ProofreadingRuleScope.book);
      expect(chapter.rule.bookId, 'book');
      expect(chapter.rule.enabled, isTrue);
      expect(chapter.rule.id, isNot('model-rule-id'));
      expect(fixture.session.saveSeq, revision);
      expect(fixture.store.saves, 0);

      fixture.session.editBlockText('p1', '正文\n$_ad\n尾文');
      fixture.responder = (call) async =>
          _ruleResponse(kind: 'advertisement', pattern: '访问测试站点领取奖励。');
      await fixture.prepare(
        kind: ProofreadingRuleKind.advertisement,
        selection: _selection('正文\n$_ad\n尾文', _ad),
        negatives: ['剧情中提到测试站点'],
      );
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiRuleCreationPhase.completed);
      final ad = fixture.task.proposals.single;
      expect(ad.rule.positiveExamples, containsAll([_ad, '访问测试站点领取奖励。']));
      expect(ad.rule.negativeExamples, containsAll(['剧情中提到测试站点', '普通正文']));
      expect(ad.rule.action, ProofreadingRuleAction.advertisementCandidate);
      expect(ad.rule.source, ProofreadingRuleSource.ai);
      expect(ad.rule.bookId, 'book');
      expect(ad.proposalId, isNot(chapter.proposalId));
      expect(ad.rule.id, isNot(chapter.rule.id));
      expect(fixture.store.saves, 0);
      expect(
        (fixture.session.activeChapter!.blocks.single as TextBlock).text,
        '正文\n$_ad\n尾文',
      );
    },
  );

  test(
    'AI candidate retains title capture after required example merge',
    () async {
      fixture.responder = (call) async => _ruleResponse(
        kind: 'chapter',
        pattern: r'【卷(二)】(夜雨)',
        extra: {
          'heading_level': 1,
          'match': {
            'mode': 'safe_regex',
            'pattern': r'【卷(二)】(夜雨)',
            'case_sensitive': true,
            'title_capture_group': 2,
            'number_capture_group': 1,
          },
          'positive_examples': ['【卷二】夜雨'],
        },
      );
      await fixture.prepare();
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiRuleCreationPhase.completed);
      final rule = fixture.task.proposals.single.rule;
      expect(rule.titleCaptureGroup, 2);
      expect(rule.numberCaptureGroup, 1);
      expect(rule.headingLevel, 1);
      expect(rule.matchSample(_heading).single.mappedTitle, '夜雨');
      expect(rule.matchSample(_heading).single.mappedNumber, 2);
      expect(rule.matchSample(_heading).single.numberText, '二');
    },
  );

  test('consent cannot cross tasks or survive a second prepare', () async {
    await fixture.prepare();
    final first = fixture.task.consent!;
    final other = fixture.createTask();
    await fixture.prepare(task: other);
    await other.run(first);
    expect(other.failure, isA<ValidationFailure>());
    expect(fixture.credentials.reads, 0);
    await fixture.prepare();
    await fixture.task.run(first);
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.credentials.reads, 0);
  });

  test('real background worker decodes and returns a bounded rule', () async {
    final jobs = BackgroundJobs();
    try {
      final task = fixture.createTask(jobs: jobs);
      await fixture.prepare(task: task);
      await task.run(task.consent!);
      expect(task.phase, AiRuleCreationPhase.completed);
      expect(task.proposals.single.rule.positiveExamples, contains(_heading));
    } finally {
      jobs.dispose();
    }
  });

  test('prepare loads only relevant current rule summaries', () async {
    final rules = <ProofreadingRule>[
      for (var index = 17; index >= 0; index--)
        _relatedRule('r$index', priority: 18 - index),
      _relatedRule('b', priority: 100),
      _relatedRule('a', priority: 100),
      _relatedRule('disabled', priority: 200, enabled: false),
      _relatedRule(
        'ad',
        priority: 200,
        kind: ProofreadingRuleKind.advertisement,
      ),
      _relatedRule('foreign', priority: 200, bookId: 'other'),
    ];
    final loadedBookIds = <String>[];
    final task = fixture.createTask(
      loadRelatedRules: (bookId) async {
        loadedBookIds.add(bookId);
        return rules;
      },
    );
    expect(loadedBookIds, isEmpty);

    await fixture.prepare(task: task);

    final expectedIds = [
      'a',
      'b',
      for (var index = 0; index < 14; index++) 'r$index',
    ];
    expect(loadedBookIds, ['book']);
    expect(task.phase, AiRuleCreationPhase.awaitingConsent);
    expect(task.consent!.relatedRules.map((rule) => rule.id), expectedIds);
    expect(fixture.credentials.reads, 0);
    expect(fixture.clients, isEmpty);

    await task.run(task.consent!);
    expect(task.phase, AiRuleCreationPhase.completed);
    final context = jsonDecode(
      fixture.clients.single.calls.single.userContext,
    ) as Map<String, dynamic>;
    final summaries = context['related_rules'] as List<dynamic>;
    expect(summaries, hasLength(16));
    expect(summaries.map((item) => (item as Map)['name']), expectedIds);
    expect(jsonEncode(summaries), isNot(contains('私有样例')));
    expect(jsonEncode(summaries), isNot(contains('disabled')));
    expect(jsonEncode(summaries), isNot(contains('foreign')));
  });

  test('cancelling while related rules load never publishes consent', () async {
    final gate = Completer<List<ProofreadingRule>>();
    final started = Completer<void>();
    final task = fixture.createTask(
      loadRelatedRules: (bookId) {
        started.complete();
        return gate.future;
      },
    );
    final preparing = fixture.prepare(task: task);
    await started.future;
    expect(task.isBusy, isTrue);
    task.cancel();
    gate.complete([_relatedRule('late')]);
    await preparing;

    expect(task.phase, AiRuleCreationPhase.cancelled);
    expect(task.consent, isNull);
    expect(task.proposals, isEmpty);
    expect(fixture.configurationLoads, 0);
    expect(fixture.credentials.reads, 0);
  });

  test(
    'book switch while related rules load never publishes consent',
    () async {
      final gate = Completer<List<ProofreadingRule>>();
      final started = Completer<void>();
      final task = fixture.createTask(
        loadRelatedRules: (bookId) {
          started.complete();
          return gate.future;
        },
      );
      final preparing = fixture.prepare(task: task);
      await started.future;
      await fixture.session.open('other');
      gate.complete([_relatedRule('late')]);
      await preparing;

      expect(task.phase, AiRuleCreationPhase.stale);
      expect(task.consent, isNull);
      expect(task.proposals, isEmpty);
      expect(fixture.configurationLoads, 0);
      expect(fixture.credentials.reads, 0);
    },
  );
}

AiConfiguration _configurationAt(String address) => AiConfiguration(
  enabled: true,
  address: address,
  model: 'test-model',
  credentialReference: 'local-credential',
);

AiRuleSelection _selection(String source, String original) {
  final start = source.indexOf(original);
  return AiRuleSelection(
    chapterId: 'a',
    blockId: 'p1',
    startUtf16: start,
    endUtf16: start + original.length,
    original: original,
  );
}

ProofreadingRule _relatedRule(
  String id, {
  int priority = 0,
  bool enabled = true,
  String bookId = 'book',
  ProofreadingRuleKind kind = ProofreadingRuleKind.chapter,
}) {
  final pattern = '章节标记$id';
  return ProofreadingRule.create(
    id: id,
    name: id,
    kind: kind,
    source: ProofreadingRuleSource.user,
    bookId: bookId,
    target: kind == ProofreadingRuleKind.chapter
        ? ProofreadingRuleTarget.headingLine
        : ProofreadingRuleTarget.bodyLine,
    mode: ProofreadingMatchMode.literal,
    pattern: pattern,
    caseSensitive: true,
    action: kind == ProofreadingRuleKind.chapter
        ? ProofreadingRuleAction.chapterCandidate
        : ProofreadingRuleAction.advertisementCandidate,
    positiveExamples: ['$pattern私有样例'],
    negativeExamples: const [],
    enabled: enabled,
    priority: priority,
  );
}

String _ruleResponse({
  required String kind,
  required String pattern,
  Map<String, Object>? extra,
  List<Map<String, Object>> findings = const [],
}) => jsonEncode({
  'schema_version': 1,
  'findings': findings,
  'proposals': <Object>[],
  'rule_proposals': [
    {
      'schema_version': 1,
      'name': '候选规则',
      'kind': kind,
      'target': kind == 'chapter' ? 'heading_line' : 'body_line',
      'match': {'mode': 'literal', 'pattern': pattern, 'case_sensitive': true},
      'action': kind == 'chapter'
          ? 'chapter_candidate'
          : 'advertisement_candidate',
      'positive_examples': [pattern],
      'negative_examples': ['普通正文'],
      'reason': '保守匹配',
      ...?extra,
    },
  ],
});

class _Fixture {
  _Fixture(this.store, this.session, this.credentials);

  static Future<_Fixture> open() async {
    final store = _MemoryStore();
    final session = EditorSession.withStore(
      store: store,
      jobs: _InlineJobs(),
      debounce: const Duration(milliseconds: 800),
    );
    await session.open('book');
    final fixture = _Fixture(store, session, _Credentials());
    fixture.task = fixture.createTask();
    return fixture;
  }

  final _MemoryStore store;
  final EditorSession session;
  final _Credentials credentials;
  final List<AiRuleCreationTask> tasks = [];
  final List<_Client> clients = [];
  AiConfiguration configuration = _configuration;
  Future<String> Function(_Call) responder = (call) async =>
      _ruleResponse(kind: 'chapter', pattern: '【卷二】夜雨');
  late AiRuleCreationTask task;
  int configurationLoads = 0;
  bool sessionClosed = false;

  AiRuleCreationTask createTask({
    BackgroundJobs? jobs,
    Future<List<ProofreadingRule>> Function(String bookId)? loadRelatedRules,
  }) {
    final task = AiRuleCreationTask(
      session: session,
      loadConfiguration: () async {
        configurationLoads++;
        return configuration;
      },
      credentials: credentials,
      loadRelatedRules: loadRelatedRules,
      createClient: () {
        final client = _Client((call) => responder(call));
        clients.add(client);
        return client;
      },
      jobs: jobs ?? _InlineJobs(),
    );
    tasks.add(task);
    return task;
  }

  Future<void> prepare({
    AiRuleCreationTask? task,
    ProofreadingRuleKind kind = ProofreadingRuleKind.chapter,
    AiRuleSelection? selection,
    List<String> negatives = const ['【卷二】风雨'],
  }) => (task ?? this.task).prepare(
    selection:
        selection ??
        _selection(
          (session.activeChapter!.blocks.single as TextBlock).text,
          _heading,
        ),
    kind: kind,
    intent: '识别该类文字',
    negativeExamples: negatives,
  );

  Future<void> dispose() async {
    for (final task in tasks) {
      task.dispose();
    }
    if (!sessionClosed) session.dispose();
  }
}

class _MemoryStore implements EditorBookStore {
  _MemoryStore() {
    final now = DateTime.utc(2026);
    books['book'] = Book(
      id: 'book',
      meta: BookMeta(title: '测试书'),
      chapters: const [
        Chapter(id: 'a', bookId: 'book', title: '第一章', order: 0),
        Chapter(id: 'b', bookId: 'book', title: '第二章', order: 1),
      ],
      createdAt: now,
      updatedAt: now,
    );
    bodies[('book', 'a')] = const Chapter(
      id: 'a',
      bookId: 'book',
      title: '第一章',
      blocks: [TextBlock(id: 'p1', text: _source)],
    );
    bodies[('book', 'b')] = const Chapter(
      id: 'b',
      bookId: 'book',
      title: '第二章',
      blocks: [TextBlock(id: 'p2', text: '后章正文')],
    );
    books['other'] = Book(
      id: 'other',
      meta: BookMeta(title: '另一本'),
      chapters: const [Chapter(id: 'other-a', bookId: 'other', title: '正文')],
      createdAt: now,
      updatedAt: now,
    );
    bodies[('other', 'other-a')] = const Chapter(
      id: 'other-a',
      bookId: 'other',
      title: '正文',
      blocks: [TextBlock(id: 'other-p', text: '另一本文字')],
    );
  }

  final Map<String, Book> books = {};
  final Map<(String, String), Chapter> bodies = {};
  final List<String> loads = [];
  int saves = 0;

  @override
  Future<Book?> loadBook(String bookId) async => books[bookId];

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async {
    loads.add('$bookId/$chapterId');
    return bodies[(bookId, chapterId)];
  }

  @override
  Future<Book> saveBook(
    Book source, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    saves++;
    for (final chapter in source.chapters) {
      if (dirtyChapterIds.contains(chapter.id)) {
        bodies[(source.id, chapter.id)] = chapter;
      }
    }
    final saved = source.copyWith(revision: expectedRevision + 1);
    books[source.id] = saved;
    return saved;
  }
}

class _Credentials implements AiCredentialStore {
  int reads = 0;
  Completer<String?>? gate;
  Completer<void>? started;

  @override
  Future<String?> read(String reference) async {
    reads++;
    if (started != null && !started!.isCompleted) started!.complete();
    return gate?.future ?? 'test-key';
  }

  @override
  Future<void> write(String reference, String value) async {}

  @override
  Future<void> delete(String reference) async {}
}

class _Call {
  const _Call(this.userContext);
  final String userContext;
}

class _Client implements AiTextClient {
  _Client(this.responder);
  final Future<String> Function(_Call) responder;
  final List<_Call> calls = [];
  bool disposed = false;

  @override
  Future<String> generate({
    required AiEndpoint endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
    required AiCancellation cancellation,
  }) {
    final call = _Call(userContext);
    calls.add(call);
    return responder(call);
  }

  @override
  void dispose() => disposed = true;
}

class _InlineJobs extends BackgroundJobs {
  @override
  Future<R> run<T, R>(
    T input,
    FutureOr<R> Function(T, void Function(double, String)) compute, {
    required int revision,
    Duration timeout = const Duration(minutes: 2),
    void Function(JobProgress)? onProgress,
  }) async => compute(input, (fraction, stage) {});

  @override
  void cancelActive() {}
}
