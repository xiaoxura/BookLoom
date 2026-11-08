import 'dart:async';
import 'dart:convert';

import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_proofreading_prompt.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/editing/proofreading_finding.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:bookloom/features/editor/application/ai_audit_gap_request.dart';
import 'package:bookloom/features/editor/application/ai_proofreading_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter_test/flutter_test.dart';

const _apiKey = 'local-test-key';
const _initialText = '😀广告和广告。尾文';
const _validConfiguration = AiConfiguration(
  enabled: true,
  address: 'https://api.example.com/v1',
  model: 'test-model',
  credentialReference: 'credential-1',
);

void main() {
  late _Fixture fixture;

  setUp(() async {
    fixture = await _Fixture.open();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test(
    'joint consent is explicit and prepares without credentials or HTTP',
    () async {
      final request = _jointRequest();
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        ruleRequest: request,
      );
      expect(fixture.task.phase, AiProofreadingPhase.awaitingConsent);
      expect(fixture.task.consent!.ruleRequest, same(request));
      expect(fixture.task.consent!.ruleChunkIndex, 0);
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
      expect(fixture.task.ruleProposals, isEmpty);
      expect(fixture.task.canUseRuleProposals, isFalse);
    },
  );

  test('joint text and rules publish independently without saving or running rules', () async {
    final request = _jointRequest();
    fixture.responder = (call) async {
      final target = _targetFor(call, '广告');
      return _analysisResponse(
        findings: [_finding(target)],
        proposals: [_proposal(target)],
        rules: [_jointRule(request)],
      );
    };
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
      ruleRequest: request,
    );
    final revision = fixture.session.saveSeq;
    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.phase, AiProofreadingPhase.completed);
    expect(fixture.task.changes, hasLength(1));
    final rule = fixture.task.ruleProposals.single;
    expect(fixture.task.canUseRuleProposals, isTrue);
    expect(rule.rule.source, ProofreadingRuleSource.ai);
    expect(rule.rule.scope, ProofreadingRuleScope.book);
    expect(rule.rule.bookId, 'book');
    expect(rule.rule.enabled, isTrue);
    expect(fixture.session.saveSeq, revision);
    expect(fixture.session.canUndo, isFalse);
    expect(fixture.store.savedDirtyIds, isEmpty);
    expect(() => fixture.task.ruleProposals.clear(), throwsUnsupportedError);
    await fixture.task.applySelected({rule.proposalId});
    expect(fixture.session.saveSeq, revision);
    expect(fixture.task.ruleProposals, hasLength(1));
    await fixture.task.applySelected({fixture.task.changes.single.id});
    expect(fixture.task.phase, AiProofreadingPhase.applied);
    expect(_text(fixture.session.activeChapter!, 'p1'), '😀和广告。尾文');
    expect(fixture.task.ruleProposals, isEmpty);
  });

  test('rule-only joint results support both generic chapter and advertisement analysis', () async {
    for (final kind in ProofreadingRuleKind.values) {
      await fixture.dispose();
      fixture = await _Fixture.open(initialText: '第十三章 风雨\n广告');
      final request = _jointRequest(
        kind: kind,
        positive: [kind == ProofreadingRuleKind.chapter ? '第十三章 风雨' : '广告'],
      );
      fixture.responder = (call) async =>
          _analysisResponse(rules: [_jointRule(request)]);
      await fixture.task.prepare(
        intent: kind == ProofreadingRuleKind.chapter
            ? AiProofreadingIntent.missingChapter
            : AiProofreadingIntent.advertisement,
        chapterIds: kind == ProofreadingRuleKind.chapter ? ['a', 'b'] : ['a'],
        ruleRequest: request,
      );
      expect(fixture.task.phase, AiProofreadingPhase.awaitingConsent);
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(fixture.task.changes, isEmpty);
      expect(fixture.task.splitChanges, isEmpty);
      expect(fixture.task.ruleProposals.single.rule.kind, kind);
      expect(fixture.task.canUseRuleProposals, isTrue);
      expect(fixture.store.savedDirtyIds, isEmpty);
      expect(fixture.session.canUndo, isFalse);
    }
  });

  test(
    'advertisement focus can opt into rules while keeping bounded context',
    () async {
      final request = _jointRequest();
      fixture.responder = (call) async =>
          _analysisResponse(rules: [_jointRule(request)]);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        advertisementSelection: _advertisementSelection(
          fixture,
          start: 2,
          end: 4,
        ),
        ruleRequest: request,
      );
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(fixture.task.ruleProposals, hasLength(1));
      final payload =
          jsonDecode(fixture.clients.single.calls.single.userContext) as Map;
      expect(payload['rule_request'], request.toJson());
      expect(payload.containsKey('advertisement_selection'), isTrue);
    },
  );

  test(
    'invalid or wrong-kind joint requests fail before credentials and HTTP',
    () async {
      for (final request in [
        _jointRequest(kind: ProofreadingRuleKind.chapter),
        _jointRequest(positive: []),
        _jointRequest(positive: List.generate(13, (index) => '广告$index')),
        _jointRequest(positive: ['广告', '广告']),
        _jointRequest(negative: ['普通', '普通']),
        _jointRequest(negative: ['广告']),
        _jointRequest(positive: ['广告\n正文']),
        _jointRequest(positive: ['\ud800']),
        _jointRequest(positive: [' ']),
        _jointRequest(positive: ['字' * 2049]),
        _jointRequest(
          positive: List.generate(5, (index) => '$index${'字' * 1800}'),
        ),
        _jointRequest(positive: ['不在正文的正例']),
      ]) {
        await fixture.task.prepare(
          intent: AiProofreadingIntent.advertisement,
          chapterIds: const ['a'],
          ruleRequest: request,
        );
        expect(fixture.task.phase, AiProofreadingPhase.failed);
        expect(fixture.task.consent, isNull);
        expect(fixture.task.ruleProposals, isEmpty);
      }
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test('joint positives split across chunks cannot expand or silently skip authorization', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(initialText: '头正例\n${'文' * 20000}\n尾正例');
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
      ruleRequest: _jointRequest(positive: ['头正例', '尾正例']),
    );
    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.credentials.readReferences, isEmpty);
    expect(fixture.clients, isEmpty);
  });

  test(
    'only the first fully covering chunk receives joint rule authorization',
    () async {
      await fixture.dispose();
      fixture = await _Fixture.open(initialText: '头正例\n${'文' * 20000}\n尾正例');
      final request = _jointRequest(positive: ['尾正例']);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        ruleRequest: request,
      );
      final consent = fixture.task.consent!;
      expect(consent.ruleChunkIndex, greaterThan(0));
      fixture.responder = (call) async {
        final payload = jsonDecode(call.userContext) as Map;
        final index = (payload['context'] as Map)['chunk_index'];
        if (index == consent.ruleChunkIndex) {
          expect(payload['rule_request'], request.toJson());
          expect(
            call.systemPrompt,
            isNot(contains('No rule creation was requested')),
          );
          return _analysisResponse(rules: [_jointRule(request)]);
        }
        expect(payload.containsKey('rule_request'), isFalse);
        expect(call.systemPrompt, contains('No rule creation was requested'));
        return _analysisResponse();
      };
      await fixture.task.run(consent);
      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(fixture.task.ruleProposals, hasLength(1));
      expect(
        fixture.clients.single.calls,
        hasLength(consent.plan.chunks.length),
      );
    },
  );

  test(
    'unsolicited rules on generic or unauthorized chunks reject all products',
    () async {
      final request = _jointRequest();
      fixture.responder = (call) async =>
          _analysisResponse(rules: [_jointRule(request)]);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: ['a'],
      );
      expect(fixture.task.consent!.ruleRequest, isNull);
      expect(fixture.task.consent!.ruleChunkIndex, isNull);
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.ruleProposals, isEmpty);
      await fixture.dispose();
      fixture = await _Fixture.open(initialText: '${'文' * 20000}\n广告');
      fixture.responder = (call) async =>
          _analysisResponse(rules: [_jointRule(request)]);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: ['a'],
        ruleRequest: request,
      );
      expect(fixture.task.consent!.ruleChunkIndex, greaterThan(0));
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.changes, isEmpty);
      expect(fixture.task.ruleProposals, isEmpty);
    },
  );

  test(
    'wrong kind and unsafe rule alongside a valid edit reject the batch',
    () async {
      final request = _jointRequest();
      for (final invalid in [
        _jointRule(_jointRequest(kind: ProofreadingRuleKind.chapter)),
        _jointRule(request)
          ..['match'] = {
            'mode': 'safe_regex',
            'pattern': r'(广+)+告',
            'case_sensitive': true,
          },
      ]) {
        fixture.responder = (call) async {
          final target = _targetFor(call, '广告');
          return _analysisResponse(
            findings: [_finding(target)],
            proposals: [_proposal(target)],
            rules: [invalid],
          );
        };
        await fixture.task.prepare(
          intent: AiProofreadingIntent.advertisement,
          chapterIds: ['a'],
          ruleRequest: request,
        );
        await fixture.task.run(fixture.task.consent!);
        expect(fixture.task.phase, AiProofreadingPhase.failed);
        expect(fixture.task.changes, isEmpty);
        expect(fixture.task.ruleProposals, isEmpty);
        expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);
      }
    },
  );

  test(
    'joint rule identities are unique across tasks and preparations',
    () async {
      final request = _jointRequest();
      fixture.responder = (call) async =>
          _analysisResponse(rules: [_jointRule(request)]);
      final identities = <String>{};
      for (final task in [fixture.task, fixture.createTask(), fixture.task]) {
        await task.prepare(
          intent: AiProofreadingIntent.advertisement,
          chapterIds: ['a'],
          ruleRequest: request,
        );
        await task.run(task.consent!);
        expect(task.phase, AiProofreadingPhase.completed);
        final proposal = task.ruleProposals.single;
        expect(identities.add(proposal.proposalId), isTrue);
        expect(identities.add(proposal.rule.id), isTrue);
      }
      expect(fixture.store.savedDirtyIds, isEmpty);
    },
  );

  test('cancel, editing and changed range clear joint rule results and late replies', () async {
    final request = _jointRequest();
    for (final cancel in [true, false]) {
      final started = Completer<void>();
      final gate = Completer<String>();
      fixture.responder = (call) {
        started.complete();
        return gate.future;
      };
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: ['a'],
        ruleRequest: request,
      );
      final run = fixture.task.run(fixture.task.consent!);
      await started.future;
      if (cancel) {
        fixture.task.cancel();
      } else {
        fixture.session.editBlockText('p1', '广告与人工编辑');
      }
      gate.complete(_analysisResponse(rules: [_jointRule(request)]));
      await run;
      expect(
        fixture.task.phase,
        cancel ? AiProofreadingPhase.cancelled : AiProofreadingPhase.stale,
      );
      expect(fixture.task.ruleProposals, isEmpty);
      expect(fixture.task.canUseRuleProposals, isFalse);
    }
    fixture.responder = (call) async =>
        _analysisResponse(rules: [_jointRule(request)]);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: ['a'],
      ruleRequest: request,
    );
    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.ruleProposals, hasLength(1));
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: ['b'],
    );
    expect(fixture.task.ruleProposals, isEmpty);
  });

  test('joint configuration changes during credential and reply waits reject results', () async {
    final request = _jointRequest();
    final keyStarted = Completer<void>();
    final keyGate = Completer<String?>();
    fixture.credentials.readStarted = keyStarted;
    fixture.credentials.gate = keyGate;
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: ['a'],
      ruleRequest: request,
    );
    final running = fixture.task.run(fixture.task.consent!);
    await keyStarted.future;
    fixture.configuration = _configurationAt('https://changed.example.com/v1');
    keyGate.complete(_apiKey);
    await running;
    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.clients.expand((client) => client.calls), isEmpty);
    expect(fixture.task.ruleProposals, isEmpty);

    fixture.credentials.gate = null;
    fixture.credentials.readStarted = null;
    final replyStarted = Completer<void>();
    final replyGate = Completer<String>();
    fixture.responder = (call) {
      replyStarted.complete();
      return replyGate.future;
    };
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: ['a'],
      ruleRequest: request,
    );
    final waiting = fixture.task.run(fixture.task.consent!);
    await replyStarted.future;
    fixture.configuration = _validConfiguration;
    replyGate.complete(_analysisResponse(rules: [_jointRule(request)]));
    await waiting;
    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.task.canUseRuleProposals, isFalse);
    expect(fixture.task.ruleProposals, isEmpty);
  });

  test(
    'advertisement selection prepares one bounded payload without sending',
    () async {
      await fixture.dispose();
      fixture = await _Fixture.open(
        initialText: '😀广告和正文',
        extraBlocks: [
          TextBlock(id: 'neighbor', text: '邻' * 700),
          TextBlock(id: 'unrelated', text: '秘密' * 9000),
        ],
      );
      final selection = _advertisementSelection(fixture, start: 2, end: 4);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        advertisementSelection: selection,
      );
      expect(fixture.task.phase, AiProofreadingPhase.awaitingConsent);
      expect(fixture.task.consent!.advertisementSelection, same(selection));
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
      expect(fixture.store.loadedChapterIds, ['book/a']);
      final context = AiProofreadingPrompt.userContext(
        AiProofreadingIntent.advertisement,
        fixture.task.consent!.plan.chunks.single,
        advertisementSelection: selection.toJson(),
      );
      expect(context, isNot(contains('秘密')));
      expect(context, isNot(contains('后文广告')));
      final envelope = jsonDecode(context) as Map<String, dynamic>;
      final slices =
          (envelope['context'] as Map<String, dynamic>)['blocks'] as List;
      expect(slices, hasLength(2));
      expect((slices.first as Map)['text'], '广告');
      expect((slices.last as Map)['text'], '邻' * 512);
      expect(
        (envelope['advertisement_selection'] as Map).containsKey('original'),
        isFalse,
      );
    },
  );

  test(
    'selection only permits advertisement intent and its exact chapter',
    () async {
      final selection = _advertisementSelection(fixture, start: 2, end: 4);
      for (final (intent, chapters) in [
        (AiProofreadingIntent.missingChapter, ['a', 'b']),
        (AiProofreadingIntent.advertisement, ['a', 'b']),
        (AiProofreadingIntent.advertisement, ['b']),
      ]) {
        await fixture.task.prepare(
          intent: intent,
          chapterIds: chapters,
          advertisementSelection: selection,
        );
        expect(fixture.task.phase, AiProofreadingPhase.failed);
        expect(fixture.task.consent, isNull);
      }
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test(
    'selection applies only precise text and preserves other content',
    () async {
      final selection = _advertisementSelection(fixture, start: 2, end: 4);
      fixture.responder = (call) async {
        expect(call.userContext, isNot(contains('后文广告')));
        expect(call.systemPrompt, contains('only editable focus'));
        return _singleAdResponse(call);
      };
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        advertisementSelection: selection,
      );
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.completed);
      await fixture.task.applySelected({fixture.task.changes.single.id});
      expect(fixture.task.phase, AiProofreadingPhase.applied);
      expect(_text(fixture.session.activeChapter!, 'p1'), '😀和广告。尾文');
      expect(
        fixture.session.book!.chapters
            .singleWhere((chapter) => chapter.id == 'b')
            .blocks,
        isEmpty,
      );
    },
  );

  test(
    'a valid neighboring proposal rejects the whole response batch',
    () async {
      await fixture.dispose();
      fixture = await _Fixture.open(
        initialText: '😀广告正文',
        extraBlocks: const [TextBlock(id: 'neighbor', text: '邻块广告')],
      );
      fixture.responder = (call) async {
        final focus = _targetFor(call, '广告', blockId: 'p1');
        final neighbor = _targetFor(call, '广告', blockId: 'neighbor');
        return _analysisResponse(
          findings: [
            _finding(focus, id: 'focus-finding'),
            _finding(neighbor, id: 'neighbor-finding'),
          ],
          proposals: [
            _proposal(focus, id: 'focus-edit', findingId: 'focus-finding'),
            _proposal(
              neighbor,
              id: 'neighbor-edit',
              findingId: 'neighbor-finding',
            ),
          ],
        );
      };
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        advertisementSelection: _advertisementSelection(
          fixture,
          start: 2,
          end: 4,
        ),
      );
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.findings, isEmpty);
      expect(fixture.task.changes, isEmpty);
      expect(_text(fixture.session.activeChapter!, 'p1'), '😀广告正文');
    },
  );

  test('a visible neighboring finding remains diagnostic only', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(
      initialText: '😀广告正文',
      extraBlocks: const [TextBlock(id: 'neighbor', text: '邻块广告')],
    );
    fixture.responder = (call) async => _analysisResponse(
      findings: [_finding(_targetFor(call, '广告', blockId: 'neighbor'))],
    );
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
      advertisementSelection: _advertisementSelection(
        fixture,
        start: 2,
        end: 4,
      ),
    );
    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.phase, AiProofreadingPhase.completed);
    expect(fixture.task.findings.single.blockId, 'neighbor');
    expect(fixture.task.changes, isEmpty);
  });

  test('whole block removal needs the complete selected TextBlock', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(initialText: '广告');
    fixture.responder = (call) async => _wholeBlockAdResponse(call);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
      advertisementSelection: _advertisementSelection(
        fixture,
        start: 0,
        end: 2,
        original: '广告',
      ),
    );
    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.phase, AiProofreadingPhase.completed);
    await fixture.task.applySelected({fixture.task.changes.single.id});
    expect(fixture.task.phase, AiProofreadingPhase.applied);
    expect(fixture.session.activeChapter!.blocks, isEmpty);
  });

  test(
    'partial advertisement selection cannot remove its whole block',
    () async {
      fixture.responder = (call) async {
        final target = _targetFor(call, '广告', blockId: 'p1');
        return _analysisResponse(
          findings: [_finding(target)],
          proposals: [
            _proposal(target, action: 'remove_block', before: '', after: ''),
          ],
        );
      };
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        advertisementSelection: _advertisementSelection(
          fixture,
          start: 2,
          end: 4,
        ),
      );
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.changes, isEmpty);
      expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);
    },
  );

  test(
    'selection cancellation and stale revision discard late results',
    () async {
      final selection = _advertisementSelection(fixture, start: 2, end: 4);
      final started = Completer<void>();
      final gate = Completer<String>();
      fixture.responder = (call) {
        if (!started.isCompleted) started.complete();
        return gate.future;
      };
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        advertisementSelection: selection,
      );
      final running = fixture.task.run(fixture.task.consent!);
      await started.future;
      fixture.task.cancel();
      gate.complete(_analysisResponse());
      await running;
      expect(fixture.task.phase, AiProofreadingPhase.cancelled);
      expect(fixture.task.changes, isEmpty);

      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        advertisementSelection: selection,
      );
      final consent = fixture.task.consent!;
      fixture.session.editBlockText('p1', '人工改写');
      await fixture.task.run(consent);
      expect(fixture.task.phase, AiProofreadingPhase.stale);
      expect(fixture.clients.single.calls, hasLength(1));
    },
  );

  test('ignored findings hide linked edits and cannot be applied', () async {
    fixture.responder = (call) async => _singleAdResponse(call);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );
    await fixture.task.run(fixture.task.consent!);
    final change = fixture.task.changes.single;
    final revision = fixture.session.saveSeq;
    final calls = fixture.clients.single.calls.length;
    fixture.task.ignoreFinding('unknown');
    expect(fixture.task.ignoredFindingCount, 0);
    fixture.task.ignoreFinding(change.finding.id);
    fixture.task.ignoreFinding(change.finding.id);
    expect(fixture.task.ignoredFindingCount, 1);
    expect(fixture.task.visibleFindings, isEmpty);
    expect(fixture.task.visibleChanges, isEmpty);
    expect(fixture.task.findings, hasLength(1));
    expect(fixture.task.changes, hasLength(1));
    expect(fixture.session.saveSeq, revision);
    expect(fixture.session.canUndo, isFalse);
    expect(fixture.store.savedDirtyIds, isEmpty);

    await fixture.task.applySelected({change.id});
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.task.phase, AiProofreadingPhase.completed);
    expect(fixture.session.saveSeq, revision);
    expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);

    fixture.task.restoreIgnoredFindings();
    expect(fixture.task.ignoredFindingCount, 0);
    expect(fixture.task.visibleChanges.single, same(change));
    expect(fixture.task.visibleFindings.single, same(change.finding));
    expect(() => fixture.task.visibleChanges.clear(), throwsUnsupportedError);
    expect(fixture.clients.single.calls, hasLength(calls));
    await fixture.task.applySelected({change.id});
    expect(fixture.task.phase, AiProofreadingPhase.applied);
    expect(fixture.task.ignoredFindingCount, 0);
    await fixture.session.undo();
    expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);
  });

  test(
    'diagnostic-only findings can be ignored and restored without edits',
    () async {
      fixture.responder = (call) async =>
          _singleFindingResponse(call, assessment: 'undetermined');
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(fixture.task.consent!);
      final finding = fixture.task.findings.single;
      fixture.task.ignoreFinding(finding.id);
      expect(fixture.task.visibleFindings, isEmpty);
      expect(fixture.task.ignoredFindingCount, 1);
      fixture.task.restoreIgnoredFindings();
      expect(fixture.task.visibleFindings.single, same(finding));
      expect(fixture.task.visibleChanges, isEmpty);
      expect(fixture.session.canUndo, isFalse);
      expect(fixture.store.savedDirtyIds, isEmpty);
    },
  );

  test('ignoring a finding hides every linked split alternative', () async {
    await fixture.dispose();
    const source = '😀前章正文\r\n第三章 风雨\r\n后续正文';
    fixture = await _Fixture.open(initialText: source);
    fixture.responder = (call) async =>
        _splitResponse(call, proposalIds: ['split-first', 'split-second']);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: const ['a', 'b'],
    );
    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.splitChanges, hasLength(2));
    final finding = fixture.task.findings.single;
    fixture.task.ignoreFinding(finding.id);
    expect(fixture.task.visibleSplitChanges, isEmpty);
    for (final split in fixture.task.splitChanges) {
      await fixture.task.applySelected({split.id});
      expect(fixture.task.failure, isA<ValidationFailure>());
    }
    expect(fixture.session.book!.chapters, hasLength(2));
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
    fixture.task.restoreIgnoredFindings();
    expect(fixture.task.visibleSplitChanges, hasLength(2));
    await fixture.task.applySelected({
      fixture.task.visibleSplitChanges.first.id,
    });
    expect(fixture.task.phase, AiProofreadingPhase.applied);
    expect(fixture.session.book!.chapters, hasLength(3));
    await fixture.session.undo();
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
  });

  test(
    'a new analysis and cancellation clear task-local ignored state',
    () async {
      fixture.responder = (call) async => _singleAdResponse(call);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(fixture.task.consent!);
      final oldId = fixture.task.findings.single.id;
      fixture.task.ignoreFinding(oldId);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      expect(fixture.task.ignoredFindingCount, 0);
      await fixture.task.run(fixture.task.consent!);
      fixture.task.ignoreFinding(oldId);
      expect(fixture.task.visibleFindings, hasLength(1));
      fixture.task.ignoreFinding(fixture.task.findings.single.id);
      expect(fixture.task.ignoredFindingCount, 1);
      fixture.task.cancel();
      fixture.task.restoreIgnoredFindings();
      expect(fixture.task.ignoredFindingCount, 0);
      expect(fixture.task.visibleFindings, isEmpty);
      expect(fixture.task.visibleChanges, isEmpty);
    },
  );

  test(
    'editing invalidates ignored results and stale actions do nothing',
    () async {
      fixture.responder = (call) async => _singleAdResponse(call);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(fixture.task.consent!);
      final findingId = fixture.task.findings.single.id;
      fixture.task.ignoreFinding(findingId);
      fixture.session.editBlockText('p1', '用户的新正文');
      expect(fixture.task.phase, AiProofreadingPhase.stale);
      fixture.task.restoreIgnoredFindings();
      fixture.task.ignoreFinding(findingId);
      expect(fixture.task.ignoredFindingCount, 0);
      expect(fixture.task.visibleFindings, isEmpty);
      expect(_text(fixture.session.activeChapter!, 'p1'), '用户的新正文');
    },
  );

  test('prepare saves the full draft before selecting AI context', () async {
    fixture.session.editBlockText('p1', '完整未保存草稿：$_initialText');
    final revision = fixture.session.saveSeq;

    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );

    expect(fixture.task.phase, AiProofreadingPhase.awaitingConsent);
    expect(fixture.session.dirty, isFalse);
    expect(fixture.session.saveSeq, revision);
    expect(fixture.store.loadedChapterIds, ['book/a']);
    expect(fixture.store.savedDirtyIds, [
      <String>{'a'},
    ]);
    expect(
      _text(fixture.store.body('book', 'a')!, 'p1'),
      '完整未保存草稿：$_initialText',
    );
    expect(fixture.credentials.readReferences, isEmpty);
    expect(fixture.clients, isEmpty);

    final consent = fixture.task.consent!;
    expect(consent.chapterTitles, {'a': '第一章'});
    final envelope = jsonDecode(
      AiProofreadingPrompt.userContext(
        AiProofreadingIntent.advertisement,
        consent.plan.chunks.single,
      ),
    ) as Map<String, dynamic>;
    expect(envelope.keys.toSet(), {'task', 'context'});
    expect(envelope['task'], 'advertisement');
    final context = envelope['context'] as Map<String, dynamic>;
    final blocks = context['blocks'] as List<dynamic>;
    expect(blocks, hasLength(1));
    expect(
      (blocks.single as Map<String, dynamic>)['text'],
      '完整未保存草稿：$_initialText',
    );
  });

  test('selected chapters enter context in book order', () async {
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['b', 'a'],
    );

    expect(fixture.task.phase, AiProofreadingPhase.awaitingConsent);
    expect(fixture.store.loadedChapterIds, ['book/a', 'book/b']);
    expect(
      fixture.task.consent!.plan.chunks
          .expand((chunk) => chunk.slices)
          .map((slice) => slice.block.chapterId),
      ['a', 'b'],
    );
    expect(fixture.credentials.readReferences, isEmpty);
    expect(fixture.clients, isEmpty);
  });

  test('initial number gap permits only its single chapter', () async {
    fixture.session.editChapterTitle('a', '第3章');
    fixture.session.editChapterTitle('b', '后记');
    final request = _auditGapRequest(fixture);
    expect(request.gap.beforeChapterId, isNull);
    expect(request.chapterIds, ['a']);

    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: const ['a'],
    );
    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.task.consent, isNull);

    fixture.responder = (call) async => _singleFindingResponse(
      call,
      category: 'missing_chapter',
      assessment: 'suspected_missing',
    );
    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: request.chapterIds,
      auditGap: request,
    );
    expect(fixture.task.phase, AiProofreadingPhase.awaitingConsent);
    expect(fixture.task.consent!.auditGap, same(request));
    expect(fixture.credentials.readReferences, isEmpty);
    expect(fixture.clients, isEmpty);

    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.phase, AiProofreadingPhase.completed);
    expect(fixture.task.findings.single.kind, FindingKind.missingChapter);
    expect(fixture.task.changes, isEmpty);
    expect(fixture.clients.single.calls, hasLength(1));
    final call = fixture.clients.single.calls.single;
    final payload = jsonDecode(call.userContext) as Map<String, dynamic>;
    expect(payload['audit_gap'], request.toJson());
    expect((payload['audit_gap'] as Map)['before_chapter_id'], isNull);
    expect((payload['audit_gap'] as Map)['first_missing'], 1);
    expect((payload['audit_gap'] as Map)['last_missing'], 2);
    expect(
      (payload['context']['blocks'] as List)
          .map((block) => (block as Map)['chapter_id'])
          .toSet(),
      {'a'},
    );
    expect(
      call.systemPrompt,
      contains('not proof that any original text is missing'),
    );
    expect(fixture.store.savedDirtyIds, [<String>{}]);
  });

  test(
    'audit metadata over budget fails during prepare without credentials',
    () async {
      fixture.session.editChapterTitle('a', '第1章');
      fixture.session.editChapterTitle(
        'b',
        '第3章${'x' * AiProtocol.maxUserCharacters}',
      );
      fixture.store.bodies[('book', 'b')] = fixture.store
          .body('book', 'b')!
          .copyWith(blocks: const <Block>[]);
      final request = _auditGapRequest(fixture);

      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: request.chapterIds,
        auditGap: request,
      );

      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.failure!.message, contains('请求预算'));
      expect(fixture.task.consent, isNull);
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test(
    'audit gap rejects different scope or intent before credentials',
    () async {
      fixture.session.editChapterTitle('a', '第1章');
      fixture.session.editChapterTitle('b', '第3章');
      final request = _auditGapRequest(fixture);
      expect(request.chapterIds, ['a', 'b']);
      expect(request.gap.beforeChapterId, 'a');

      for (final selection in [
        (AiProofreadingIntent.missingChapter, <String>['a']),
        (AiProofreadingIntent.missingChapter, <String>['b', 'a']),
        (AiProofreadingIntent.missingChapter, <String>['a', 'b', 'a']),
        (AiProofreadingIntent.advertisement, <String>['a', 'b']),
      ]) {
        await fixture.task.prepare(
          intent: selection.$1,
          chapterIds: selection.$2,
          auditGap: request,
        );
        expect(fixture.task.phase, AiProofreadingPhase.failed);
        expect(fixture.task.consent, isNull);
      }
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);

      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: request.chapterIds,
        auditGap: request,
      );
      await fixture.task.run(fixture.task.consent!);
      final payload = jsonDecode(
        fixture.clients.single.calls.single.userContext,
      ) as Map<String, dynamic>;
      expect(payload['audit_gap'], request.toJson());
      expect((payload['audit_gap'] as Map)['before_title'], '第1章');
      expect((payload['audit_gap'] as Map)['after_title'], '第3章');
      expect(
        (payload['context']['blocks'] as List)
            .map((block) => (block as Map)['chapter_id'])
            .toSet(),
        {'a', 'b'},
      );
    },
  );

  test(
    'expired audit gap is rejected before configuration or key read',
    () async {
      fixture.session.editChapterTitle('a', '第1章');
      fixture.session.editChapterTitle('b', '第3章');
      final request = _auditGapRequest(fixture);
      fixture.session.editChapterTitle('b', '第4章');

      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: request.chapterIds,
        auditGap: request,
      );
      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.consent, isNull);
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test(
    'editing during audit context loading invalidates the handoff',
    () async {
      fixture.session.editChapterTitle('a', '第1章');
      fixture.session.editChapterTitle('b', '第3章');
      final request = _auditGapRequest(fixture);
      fixture.store
        ..gatedChapterId = 'b'
        ..chapterReadStarted = Completer<void>()
        ..chapterReadGate = Completer<void>();
      final preparing = fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: request.chapterIds,
        auditGap: request,
      );
      await fixture.store.chapterReadStarted!.future;
      fixture.session.editBlockText('p1', '人工修订');
      fixture.store.chapterReadGate!.complete();
      await preparing;

      expect(fixture.task.phase, AiProofreadingPhase.stale);
      expect(fixture.task.consent, isNull);
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test(
    'editing after audit consent blocks credential access and HTTP',
    () async {
      fixture.session.editChapterTitle('a', '第1章');
      fixture.session.editChapterTitle('b', '第3章');
      final request = _auditGapRequest(fixture);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: request.chapterIds,
        auditGap: request,
      );
      final consent = fixture.task.consent!;
      fixture.session.editBlockText('p1', '人工修订');

      await fixture.task.run(consent);
      expect(fixture.task.phase, AiProofreadingPhase.stale);
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test('editing while audit credential is pending prevents HTTP', () async {
    fixture.session.editChapterTitle('a', '第1章');
    fixture.session.editChapterTitle('b', '第3章');
    final request = _auditGapRequest(fixture);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: request.chapterIds,
      auditGap: request,
    );
    final keyGate = Completer<String?>();
    fixture.credentials
      ..readStarted = Completer<void>()
      ..gate = keyGate;

    final running = fixture.task.run(fixture.task.consent!);
    await fixture.credentials.readStarted!.future;
    fixture.session.editBlockText('p1', '凭据读取期间的人工修订');
    keyGate.complete(_apiKey);
    await running;

    expect(fixture.task.phase, AiProofreadingPhase.stale);
    expect(fixture.clients, isEmpty);
    expect(fixture.store.savedDirtyIds, [<String>{}]);
  });

  test(
    'disabled configuration and missing key reference make no request',
    () async {
      for (final configuration in [
        const AiConfiguration(
          address: 'https://api.example.com/v1',
          model: 'test-model',
          credentialReference: 'credential-1',
        ),
        const AiConfiguration(
          enabled: true,
          address: 'https://api.example.com/v1',
          model: 'test-model',
        ),
      ]) {
        fixture.configuration = configuration;
        await fixture.task.prepare(
          intent: AiProofreadingIntent.advertisement,
          chapterIds: const ['a'],
        );

        expect(fixture.task.phase, AiProofreadingPhase.failed);
        expect(fixture.task.failure, isA<ValidationFailure>());
        expect(fixture.task.consent, isNull);
        expect(fixture.credentials.readReferences, isEmpty);
        expect(fixture.clients, isEmpty);
      }
    },
  );

  test(
    'consent cannot cross task instances or survive a new preparation',
    () async {
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      final oldConsent = fixture.task.consent!;

      final otherTask = fixture.createTask();
      await otherTask.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      final otherConsent = otherTask.consent!;
      await otherTask.run(oldConsent);
      expect(otherTask.failure, isA<ValidationFailure>());
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);

      await otherTask.run(otherConsent);
      expect(otherTask.phase, AiProofreadingPhase.completed);
      expect(fixture.credentials.readReferences, ['credential-1']);

      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      final currentConsent = fixture.task.consent!;
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(currentConsent);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.credentials.readReferences, ['credential-1']);
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.completed);
    },
  );

  test(
    'configuration changed after consent is rejected before key read',
    () async {
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      final consent = fixture.task.consent!;
      fixture.configuration = _configurationAt('https://new.example.com/v1');

      await fixture.task.run(consent);

      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test('configuration changed while key is pending is never sent', () async {
    final keyGate = Completer<String?>();
    fixture.credentials
      ..readStarted = Completer<void>()
      ..gate = keyGate;
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );

    final running = fixture.task.run(fixture.task.consent!);
    await fixture.credentials.readStarted!.future;
    fixture.configuration = _configurationAt('https://new.example.com/v1');
    keyGate.complete(_apiKey);
    await running;

    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.clients, hasLength(1));
    expect(fixture.clients.single.calls, isEmpty);
    expect(fixture.clients.single.disposed, isTrue);
  });

  test(
    'cancel or book switch while reading key prevents all requests',
    () async {
      final keyGate = Completer<String?>();
      fixture.credentials
        ..readStarted = Completer<void>()
        ..gate = keyGate;
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      final cancelledRun = fixture.task.run(fixture.task.consent!);
      await fixture.credentials.readStarted!.future;
      fixture.task.cancel();
      keyGate.complete(_apiKey);
      await cancelledRun;

      expect(fixture.task.phase, AiProofreadingPhase.cancelled);
      expect(fixture.clients, isEmpty);

      fixture.credentials
        ..gate = Completer<String?>()
        ..readStarted = Completer<void>();
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      final switchedRun = fixture.task.run(fixture.task.consent!);
      await fixture.credentials.readStarted!.future;
      await fixture.session.open('other');
      fixture.credentials.gate!.complete(_apiKey);
      await switchedRun;

      expect(fixture.session.book!.id, 'other');
      expect(fixture.task.phase, AiProofreadingPhase.stale);
      expect(fixture.clients, isEmpty);
    },
  );

  test(
    'a valid finding and linked proposal require explicit selection',
    () async {
      fixture.responder = (call) async => _singleAdResponse(call);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );

      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(fixture.task.findings, hasLength(1));
      expect(fixture.task.changes, hasLength(1));
      final change = fixture.task.changes.single;
      expect(change.finding.id, isNot('model-finding'));
      expect(change.finding, same(fixture.task.findings.single));
      expect(change.proposal.id, change.id);
      expect(fixture.task.canApply, isTrue);
      expect(fixture.store.savedDirtyIds, isEmpty);
      expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);

      await fixture.task.applySelected(const {});
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);
      expect(fixture.session.canUndo, isFalse);

      await fixture.task.applySelected({change.id});
      expect(fixture.task.phase, AiProofreadingPhase.applied);
      expect(fixture.task.lastAppliedCount, 1);
      expect(_text(fixture.session.activeChapter!, 'p1'), '😀和广告。尾文');
      expect(fixture.session.canUndo, isTrue);

      await fixture.session.undo();
      expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);
      expect(fixture.session.canUndo, isFalse);
      await fixture.session.redo();
      expect(_text(fixture.session.activeChapter!, 'p1'), '😀和广告。尾文');
      await fixture.session.flush();
      expect(_text(fixture.store.body('book', 'a')!, 'p1'), '😀和广告。尾文');
      expect(fixture.store.savedDirtyIds, [
        <String>{'a'},
      ]);
    },
  );

  test(
    'remove_block removes only the selected block and supports undo and save',
    () async {
      await fixture.dispose();
      const source = '整块广告😀';
      fixture = await _Fixture.open(initialText: source);
      fixture.responder = (call) async => _wholeBlockAdResponse(call);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.completed);
      final change = fixture.task.changes.single;
      expect(change.proposal.action, AiTextProposalAction.removeBlock);
      expect(change.proposal.range.start, 0);
      expect(change.proposal.range.end, source.length);
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.store.savedDirtyIds, isEmpty);
      expect(fixture.session.canUndo, isFalse);

      await fixture.task.applySelected(const {});
      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      await fixture.task.applySelected({change.id});
      expect(fixture.task.phase, AiProofreadingPhase.applied);
      expect(fixture.session.book!.chapters, hasLength(2));
      expect(fixture.session.activeChapter!.blocks, isEmpty);
      expect(fixture.session.canUndo, isTrue);

      await fixture.session.undo();
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      await fixture.session.redo();
      expect(fixture.session.activeChapter!.blocks, isEmpty);
      await fixture.session.flush();
      expect(fixture.store.body('book', 'a')!.blocks, isEmpty);
      expect(fixture.store.body('book', 'b')!.blocks, hasLength(1));
      expect(fixture.store.savedDirtyIds, [
        <String>{'a'},
      ]);
    },
  );

  test('ignored remove_block stays unapplied after restoration', () async {
    await fixture.dispose();
    const source = '整块广告😀';
    fixture = await _Fixture.open(initialText: source);
    fixture.responder = (call) async => _wholeBlockAdResponse(call);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );
    await fixture.task.run(fixture.task.consent!);

    final change = fixture.task.changes.single;
    fixture.task.ignoreFinding(change.finding.id);
    expect(fixture.task.visibleChanges, isEmpty);
    await fixture.task.applySelected({change.id});
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
    fixture.task.restoreIgnoredFindings();
    expect(fixture.task.visibleChanges.single, same(change));
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
    expect(fixture.session.canUndo, isFalse);
    await fixture.task.applySelected({change.id});
    expect(fixture.session.activeChapter!.blocks, isEmpty);
  });

  test('stale remove_block cannot be applied after a manual edit', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(initialText: '整块广告😀');
    fixture.responder = (call) async => _wholeBlockAdResponse(call);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );
    await fixture.task.run(fixture.task.consent!);
    final changeId = fixture.task.changes.single.id;

    fixture.session.editBlockText('p1', '人工新正文');
    expect(fixture.task.phase, AiProofreadingPhase.stale);
    await fixture.task.applySelected({changeId});
    expect(_text(fixture.session.activeChapter!, 'p1'), '人工新正文');
    expect(fixture.task.changes, isEmpty);
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test('provider products from another intent are rejected locally', () async {
    final List<
      ({
        AiProofreadingIntent intent,
        List<String> chapterIds,
        String Function(_AiCall) response,
      })
    >
    cases = [
      (
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
        response: (call) => _singleFindingResponse(
          call,
          category: 'missing_chapter',
          assessment: 'suspected_missing',
        ),
      ),
      (
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: const ['a', 'b'],
        response: _singleFindingResponse,
      ),
      (
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: const ['a', 'b'],
        response: _singleAdResponse,
      ),
    ];

    for (final testCase in cases) {
      fixture.responder = (call) async => testCase.response(call);
      await fixture.task.prepare(
        intent: testCase.intent,
        chapterIds: testCase.chapterIds,
      );
      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.findings, isEmpty);
      expect(fixture.task.changes, isEmpty);
      expect(fixture.task.canApply, isFalse);
      expect(fixture.store.savedDirtyIds, isEmpty);
    }
  });

  test('missing-chapter intent rejects remove_block text changes', () async {
    await fixture.dispose();
    const source = '整块广告😀';
    fixture = await _Fixture.open(initialText: source);
    fixture.responder = (call) async => _wholeBlockAdResponse(call);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: const ['a', 'b'],
    );
    await fixture.task.run(fixture.task.consent!);

    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.task.changes, isEmpty);
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
    expect(fixture.session.canUndo, isFalse);
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test(
    'missing-chapter split stays unselected until explicitly applied',
    () async {
      await fixture.dispose();
      const source = '😀前章正文\r\n第三章 风雨\r\n后续正文';
      fixture = await _Fixture.open(initialText: source);
      fixture.responder = (call) async => _splitResponse(call);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: const ['a', 'b'],
      );
      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(fixture.task.changes, isEmpty);
      expect(fixture.task.splitChanges, hasLength(1));
      expect(fixture.task.canApply, isTrue);
      expect(fixture.session.book!.chapters, hasLength(2));
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.session.canUndo, isFalse);
      final change = fixture.task.splitChanges.single;
      expect(change.proposal.title, '第三章 风雨');
      expect(change.proposal.removeTitleLine, isTrue);
      final initialSeq = fixture.session.saveSeq;

      await fixture.task.applySelected({change.id});

      expect(fixture.task.phase, AiProofreadingPhase.applied);
      expect(fixture.task.lastAppliedCount, 1);
      expect(fixture.session.saveSeq, initialSeq + 1);
      final chapters = fixture.session.book!.chapters;
      expect(chapters, hasLength(3));
      expect(chapters[1].title, '第三章 风雨');
      expect((chapters.first.blocks.single as TextBlock).text, '😀前章正文\r\n');
      expect(
        chapters[1].blocks.whereType<TextBlock>().map((block) => block.text),
        ['后续正文'],
      );
      expect(fixture.session.canUndo, isTrue);

      await fixture.session.undo();
      expect(fixture.session.saveSeq, initialSeq + 2);
      expect(fixture.session.book!.chapters.map((chapter) => chapter.id), [
        'a',
        'b',
      ]);
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.session.canUndo, isFalse);
      await fixture.session.redo();
      expect(fixture.session.saveSeq, initialSeq + 3);
      expect(fixture.session.book!.chapters[1].title, '第三章 风雨');
    },
  );

  test(
    'split preview retains complete local blocks after source eviction',
    () async {
      await fixture.dispose();
      fixture = await _Fixture.open(
        initialText: '卷前正文',
        withVolume: true,
        withUnselectedChapter: true,
        extraBlocks: const [
          ImageBlock(
            id: 'before-image',
            assetId: 'private-before-asset',
            caption: '私有前图说明',
          ),
          FootnoteBlock(id: 'before-note', text: '私有前脚注'),
          DividerBlock(id: 'before-divider'),
          TextBlock(id: 'heading', text: '第三章 风雨\n本章正文'),
          ImageBlock(
            id: 'after-image',
            assetId: 'private-after-asset',
            caption: '私有后图说明',
          ),
          FootnoteBlock(id: 'after-note', text: '私有后脚注'),
          DividerBlock(id: 'after-divider'),
          TextBlock(id: 'tail', text: '章末正文'),
        ],
      );
      fixture.responder = (call) async => _splitResponse(
        call,
        blockId: 'heading',
        proposalIds: const ['split-first', 'split-second'],
      );
      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: const ['a', 'b'],
      );
      expect(fixture.task.phase, AiProofreadingPhase.awaitingConsent);
      await fixture.session.selectChapter('b');
      expect(
        fixture.session.book!.chapters
            .singleWhere((chapter) => chapter.id == 'a')
            .blocks,
        isEmpty,
      );

      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(fixture.task.splitChanges, hasLength(2));
      final first = fixture.task.splitChanges.first;
      final second = fixture.task.splitChanges.last;
      expect(first.sourceBlockIndex, 4);
      expect(first.sourceBlock.blockId, 'heading');
      expect(first.sourceBlock.text, '第三章 风雨\n本章正文');
      expect(first.parentTitle, '本地卷名不外发');
      expect(first.sourceChapter.parentId, 'volume');
      expect(identical(first.sourceChapter, second.sourceChapter), isTrue);
      expect(first.precedingBlockCount, 4);
      expect(first.precedingBlocks.map((block) => block.id), [
        'p1',
        'before-image',
        'before-note',
        'before-divider',
      ]);
      expect(first.followingBlockCount, 4);
      expect(first.followingBlocks.map((block) => block.id), [
        'after-image',
        'after-note',
        'after-divider',
        'tail',
      ]);
      expect(first.followingBlocks.elementAt(0), isA<ImageBlock>());
      expect(first.followingBlocks.elementAt(1), isA<FootnoteBlock>());
      expect(first.followingBlocks.elementAt(2), isA<DividerBlock>());
      expect(
        () =>
            first.sourceChapter.blocks.add(const DividerBlock(id: 'mutation')),
        throwsUnsupportedError,
      );
      expect(fixture.session.canUndo, isFalse);
      expect(fixture.store.savedDirtyIds, isEmpty);

      final wire = fixture.clients.single.calls
          .map((call) => '${call.systemPrompt}${call.userContext}')
          .join();
      for (final privateValue in [
        'private-before-asset',
        'private-after-asset',
        '私有前图说明',
        '私有后图说明',
        '私有前脚注',
        '私有后脚注',
        '本地卷名不外发',
        '未选章机密标题',
        '未选章机密正文',
      ]) {
        expect(wire, isNot(contains(privateValue)));
      }
      expect(fixture.store.loadedChapterIds, isNot(contains('book/c')));
    },
  );

  test(
    'late split replies after cancellation or revision change stay unpublished',
    () async {
      for (final cancel in [true, false]) {
        await fixture.dispose();
        fixture = await _Fixture.open(initialText: '前文\n第三章 风雨\n后文');
        final started = Completer<void>();
        final responseGate = Completer<String>();
        fixture.responder = (call) {
          if (!started.isCompleted) started.complete();
          return responseGate.future;
        };
        await fixture.task.prepare(
          intent: AiProofreadingIntent.missingChapter,
          chapterIds: const ['a', 'b'],
        );
        final running = fixture.task.run(fixture.task.consent!);
        await started.future;
        final response = _splitResponse(fixture.clients.single.calls.single);
        if (cancel) {
          fixture.task.cancel();
        } else {
          fixture.session.editBlockText('p1', '人工改写');
        }
        responseGate.complete(response);
        await running;
        expect(
          fixture.task.phase,
          cancel ? AiProofreadingPhase.cancelled : AiProofreadingPhase.stale,
        );
        expect(fixture.task.splitChanges, isEmpty);
        expect(fixture.task.canApply, isFalse);
        expect(fixture.session.canUndo, cancel ? isFalse : isTrue);
      }
    },
  );

  test(
    'opening heading rename remains selected, undoable, and preserves body',
    () async {
      await fixture.dispose();
      const source = '第三章 风雨\r\n正文仍保留标题行';
      fixture = await _Fixture.open(initialText: source);
      fixture.responder = (call) async => _renameResponse(call);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: const ['a', 'b'],
      );
      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.completed);
      final change = fixture.task.changes.single;
      expect(change.proposal.action, AiTextProposalAction.renameChapter);
      expect(change.proposal.originalTitle, '第一章');
      expect(change.proposal.replacement, '第三章 风雨');
      expect(fixture.task.splitChanges, isEmpty);
      expect(fixture.session.book!.chapters.first.title, '第一章');
      expect(_text(fixture.session.activeChapter!, 'p1'), source);

      fixture.task.ignoreFinding(change.finding.id);
      expect(fixture.task.visibleChanges, isEmpty);
      await fixture.task.applySelected({change.id});
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.session.book!.chapters.first.title, '第一章');
      fixture.task.restoreIgnoredFindings();
      expect(fixture.task.visibleChanges.single, same(change));

      await fixture.task.applySelected({change.id});
      expect(fixture.task.phase, AiProofreadingPhase.applied);
      expect(fixture.task.lastAppliedCount, 1);
      expect(fixture.session.book!.chapters.first.title, '第三章 风雨');
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      await fixture.session.undo();
      expect(fixture.session.book!.chapters.first.title, '第一章');
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      await fixture.session.redo();
      expect(fixture.session.book!.chapters.first.title, '第三章 风雨');
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
    },
  );

  test('duplicate opening-block renames conflict', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(initialText: '第三章 风雨\n正文');
    fixture.responder = (call) async {
      final first = _targetFor(call, '第三章 风雨');
      return _analysisResponse(
        findings: [
          _finding(
            first,
            category: 'missing_chapter',
            assessment: 'missed_heading',
          ),
        ],
        proposals: [
          _renameProposal(
            first,
            id: 'rename-first',
            findingId: 'model-finding',
          ),
          _renameProposal(
            first,
            id: 'rename-second',
            findingId: 'model-finding',
          ),
        ],
      );
    };
    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: const ['a', 'b'],
    );
    await fixture.task.run(fixture.task.consent!);

    expect(fixture.task.phase, AiProofreadingPhase.completed);
    expect(fixture.task.changes, hasLength(2));
    expect(fixture.task.conflicts, hasLength(1));
    final ids = fixture.task.changes.map((change) => change.id).toSet();
    final conflict = fixture.task.conflicts.single;
    expect({conflict.firstId, conflict.secondId}, ids);
    await fixture.task.applySelected(ids);
    expect(fixture.task.phase, AiProofreadingPhase.completed);
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.session.book!.chapters.first.title, '第一章');
  });

  test('rename in later block and chunk is rejected before preview', () async {
    await fixture.dispose();
    final source = _repeat('正文', 8050);
    const laterText = '第四章 清明\n后文';
    fixture = await _Fixture.open(
      initialText: source,
      extraBlocks: const [TextBlock(id: 'p3', text: laterText)],
    );
    fixture.responder = (call) async {
      final slices = _context(call)['blocks'] as List<dynamic>;
      if (!slices.any(
        (slice) => (slice as Map<String, dynamic>)['block_id'] == 'p3',
      )) {
        return _analysisResponse();
      }
      final target = _targetFor(call, '第四章 清明', blockId: 'p3');
      return _analysisResponse(
        findings: [
          _finding(
            target,
            category: 'missing_chapter',
            assessment: 'missed_heading',
          ),
        ],
        proposals: [
          _renameProposal(
            target,
            id: 'rename-later',
            findingId: 'model-finding',
          ),
        ],
      );
    };
    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: const ['a', 'b'],
    );
    final chunks = fixture.task.consent!.plan.chunks;
    final laterChunk = chunks.singleWhere(
      (chunk) => chunk.slices.any((slice) => slice.block.blockId == 'p3'),
    );
    expect(laterChunk.index, greaterThan(0));
    expect(
      laterChunk.slices
          .where((slice) => slice.block.chapterId == 'a')
          .map((slice) => slice.block.blockId),
      ['p3'],
    );
    final revision = fixture.session.saveSeq;

    await fixture.task.run(fixture.task.consent!);

    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.task.findings, isEmpty);
    expect(fixture.task.changes, isEmpty);
    expect(fixture.task.conflicts, isEmpty);
    expect(fixture.session.saveSeq, revision);
    expect(fixture.session.book!.chapters.first.title, '第一章');
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
    expect(_text(fixture.session.activeChapter!, 'p3'), laterText);
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test('rename and split in the same chapter conflict', () async {
    await fixture.dispose();
    const source = '第三章 风雨\n正文\n第四章 清明\n后文';
    fixture = await _Fixture.open(initialText: source);
    fixture.responder = (call) async {
      final rename = _targetFor(call, '第三章 风雨');
      final split = _targetFor(call, '第四章 清明');
      return _analysisResponse(
        findings: [
          _finding(
            rename,
            id: 'rename-finding',
            category: 'missing_chapter',
            assessment: 'missed_heading',
          ),
          _finding(
            split,
            id: 'split-finding',
            category: 'missing_chapter',
            assessment: 'missed_heading',
          ),
        ],
        proposals: [
          _renameProposal(rename, id: 'rename', findingId: 'rename-finding'),
          _splitProposal(split, id: 'split', findingId: 'split-finding'),
        ],
      );
    };
    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: const ['a', 'b'],
    );
    await fixture.task.run(fixture.task.consent!);

    expect(fixture.task.phase, AiProofreadingPhase.completed);
    final rename = fixture.task.changes.single;
    final split = fixture.task.splitChanges.single;
    expect(fixture.task.conflicts, hasLength(1));
    final conflict = fixture.task.conflicts.single;
    expect({conflict.firstId, conflict.secondId}, {rename.id, split.id});
    await fixture.task.applySelected({rename.id, split.id});
    expect(fixture.task.phase, AiProofreadingPhase.completed);
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.session.book!.chapters, hasLength(2));
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
  });

  test('advertisement intent rejects chapter rename', () async {
    await fixture.dispose();
    const source = '第三章 风雨\n正文';
    fixture = await _Fixture.open(initialText: source);
    fixture.responder = (call) async => _renameResponse(call);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );
    await fixture.task.run(fixture.task.consent!);

    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.task.changes, isEmpty);
    expect(fixture.session.book!.chapters.first.title, '第一章');
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
  });

  test(
    'duplicate split proposals conflict as one pair and apply individually',
    () async {
      await fixture.dispose();
      const source = '开篇\r\n第三章 风雨\r\n后文';
      fixture = await _Fixture.open(initialText: source);
      fixture.responder = (call) async =>
          _splitResponse(call, proposalIds: const ['split-a', 'split-b']);
      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: const ['a', 'b'],
      );
      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(fixture.task.splitChanges, hasLength(2));
      expect(fixture.task.conflicts, hasLength(1));
      final ids = fixture.task.splitChanges.map((change) => change.id).toSet();
      final conflict = fixture.task.conflicts.single;
      expect({conflict.firstId, conflict.secondId}, ids);
      final initialSeq = fixture.session.saveSeq;

      await fixture.task.applySelected(ids);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(fixture.session.saveSeq, initialSeq);
      expect(fixture.session.book!.chapters, hasLength(2));
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.session.canUndo, isFalse);

      await fixture.task.applySelected({fixture.task.splitChanges.first.id});
      expect(fixture.task.phase, AiProofreadingPhase.applied);
      expect(fixture.task.lastAppliedCount, 1);
      expect(fixture.session.saveSeq, initialSeq + 1);
      expect(fixture.session.book!.chapters, hasLength(3));
    },
  );

  test(
    'missing-chapter intent rejects advertisement text results atomically',
    () async {
      await fixture.dispose();
      const source = '前文\r\n第三章 风雨\r\n内容广告\r\n第四章 清明\r\n末尾尾部广告';
      fixture = await _Fixture.open(initialText: source);
      fixture.responder = (call) async => _mixedSplitTextResponse(call);
      final initialSeq = fixture.session.saveSeq;
      await fixture.task.prepare(
        intent: AiProofreadingIntent.missingChapter,
        chapterIds: const ['a', 'b'],
      );
      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.findings, isEmpty);
      expect(fixture.task.splitChanges, isEmpty);
      expect(fixture.task.changes, isEmpty);
      expect(fixture.task.conflicts, isEmpty);
      expect(fixture.task.canApply, isFalse);
      expect(fixture.session.saveSeq, initialSeq);
      expect(fixture.session.book!.chapters, hasLength(2));
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.session.canUndo, isFalse);
      expect(fixture.session.dirty, isFalse);
      expect(fixture.store.savedDirtyIds, isEmpty);
    },
  );

  test(
    'advertisement intent rejects split proposals without changing text',
    () async {
      await fixture.dispose();
      const source = '推广段落\r\n正文';
      fixture = await _Fixture.open(initialText: source);
      fixture.responder = (call) async => _splitResponse(call, needle: '推广段落');
      final initialSeq = fixture.session.saveSeq;
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.findings, isEmpty);
      expect(fixture.task.changes, isEmpty);
      expect(fixture.task.splitChanges, isEmpty);
      expect(fixture.session.saveSeq, initialSeq);
      expect(fixture.session.book!.chapters, hasLength(2));
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.session.canUndo, isFalse);
    },
  );

  test('cancelling completed split results clears split proposals', () async {
    await fixture.dispose();
    const source = '开篇\r\n第三章 风雨\r\n后文';
    fixture = await _Fixture.open(initialText: source);
    fixture.responder = (call) async => _splitResponse(call);
    await fixture.task.prepare(
      intent: AiProofreadingIntent.missingChapter,
      chapterIds: const ['a', 'b'],
    );
    await fixture.task.run(fixture.task.consent!);
    expect(fixture.task.splitChanges, hasLength(1));

    fixture.task.cancel();

    expect(fixture.task.phase, AiProofreadingPhase.cancelled);
    expect(fixture.task.splitChanges, isEmpty);
    expect(fixture.task.changes, isEmpty);
    expect(fixture.task.findings, isEmpty);
    expect(fixture.task.canApply, isFalse);
    expect(fixture.session.book!.chapters, hasLength(2));
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
    expect(fixture.session.canUndo, isFalse);
  });

  test('late response after manual edit is stale and cannot publish', () async {
    final held = await _startHeldRun(fixture);

    fixture.session.editBlockText('p1', '人工新正文');
    expect(fixture.task.phase, AiProofreadingPhase.stale);
    held.gate.complete(held.response);
    await held.running;

    expect(fixture.task.findings, isEmpty);
    expect(fixture.task.changes, isEmpty);
    expect(fixture.task.canApply, isFalse);
    expect(_text(fixture.session.activeChapter!, 'p1'), '人工新正文');
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test(
    'late response after switching books cannot publish or edit new book',
    () async {
      final held = await _startHeldRun(fixture);

      await fixture.session.open('other');
      held.gate.complete(held.response);
      await held.running;

      expect(fixture.task.phase, AiProofreadingPhase.stale);
      expect(fixture.task.findings, isEmpty);
      expect(fixture.task.changes, isEmpty);
      expect(fixture.task.canApply, isFalse);
      expect(fixture.session.book!.id, 'other');
      expect(_text(fixture.session.activeChapter!, 'other-p1'), '另一本文字');
    },
  );

  test('late response after closing session cannot publish', () async {
    final held = await _startHeldRun(fixture);

    await fixture.closeSession();
    held.gate.complete(held.response);
    await held.running;

    expect(fixture.task.phase, AiProofreadingPhase.stale);
    expect(fixture.task.findings, isEmpty);
    expect(fixture.task.changes, isEmpty);
    expect(fixture.task.canApply, isFalse);
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test('late response after task disposal cannot publish or apply', () async {
    final held = await _startHeldRun(fixture);

    fixture.task.dispose();
    held.gate.complete(held.response);
    await held.running;

    expect(fixture.task.findings, isEmpty);
    expect(fixture.task.changes, isEmpty);
    expect(fixture.task.canApply, isFalse);
    expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test('large context runs two ordered chunks with accurate progress', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(
      initialText:
          '${_repeat('A', 8200)}广告一${_repeat('A', 8000)}广告二${_repeat('B', 1000)}',
    );
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final firstGate = Completer<String>();
    final secondGate = Completer<String>();
    late _MemoryClient client;
    fixture.responder = (call) {
      final chunkIndex = _context(call)['chunk_index'] as int;
      if (chunkIndex == 0) {
        if (!firstStarted.isCompleted) firstStarted.complete();
        return firstGate.future;
      }
      if (!secondStarted.isCompleted) secondStarted.complete();
      return secondGate.future;
    };
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );
    expect(fixture.task.totalChunks, 2);
    final running = fixture.task.run(fixture.task.consent!);
    await firstStarted.future;
    client = fixture.clients.single;
    expect(fixture.task.completedChunks, 0);
    expect(client.calls, hasLength(1));
    firstGate.complete(
      _singleAdResponse(
        client.calls.single,
        needle: '广告一',
        findingId: _repeat('x', 128),
        proposalId: _repeat('y', 128),
      ),
    );
    await secondStarted.future;
    expect(fixture.task.completedChunks, 1);
    expect(client.calls, hasLength(2));
    expect(client.calls.map((call) => _context(call)['chunk_index']), [0, 1]);
    expect(client.maxConcurrent, 1);
    secondGate.complete(
      _singleFindingResponse(
        client.calls.last,
        needle: '广告二',
        id: _repeat('x', 128),
      ),
    );
    await running;

    expect(fixture.task.phase, AiProofreadingPhase.completed);
    expect(fixture.task.completedChunks, 2);
    expect(fixture.task.findings, hasLength(2));
    expect(
      fixture.task.findings.map((finding) => finding.id).toSet(),
      hasLength(2),
    );
    expect(
      fixture.task.findings.every((finding) => finding.id.length < 128),
      isTrue,
    );
    expect(
      fixture.task.findings.every((finding) => finding.id != _repeat('x', 128)),
      isTrue,
    );
    expect(fixture.task.findings.map((finding) => finding.evidence), [
      '广告一',
      '广告二',
    ]);
    expect(fixture.task.changes, hasLength(1));
    final change = fixture.task.changes.single;
    expect(change.id.length, lessThan(128));
    expect(change.id, isNot(_repeat('y', 128)));
    expect(change.proposal.id, change.id);
    expect(change.finding, same(fixture.task.findings.first));
    expect(change.finding.evidence, '广告一');
    expect(fixture.task.conflicts, isEmpty);
  });

  test('configuration change during the last response drops all results', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(
      initialText:
          '${_repeat('A', 8200)}广告一${_repeat('A', 8000)}广告二${_repeat('B', 1000)}',
    );
    final lastRequestStarted = Completer<void>();
    final lastResponseGate = Completer<String>();
    fixture.responder = (call) {
      final chunkIndex = _context(call)['chunk_index'] as int;
      if (chunkIndex == 0) {
        return Future<String>.value(_singleAdResponse(call, needle: '广告一'));
      }
      if (!lastRequestStarted.isCompleted) lastRequestStarted.complete();
      return lastResponseGate.future;
    };
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );
    expect(fixture.task.totalChunks, 2);
    final running = fixture.task.run(fixture.task.consent!);
    await lastRequestStarted.future;
    expect(fixture.task.completedChunks, 1);
    fixture.configuration = _configurationAt('https://new.example.com/v1');
    lastResponseGate.complete(_analysisResponse());
    await running;

    expect(fixture.task.phase, AiProofreadingPhase.failed);
    expect(fixture.task.completedChunks, 2);
    expect(fixture.task.findings, isEmpty);
    expect(fixture.task.changes, isEmpty);
    expect(fixture.task.canApply, isFalse);
    expect(fixture.clients.single.calls, hasLength(2));
    expect(
      fixture.clients.single.calls.every(
        (call) => call.endpoint.baseUri.host == 'api.example.com',
      ),
      isTrue,
    );
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test('cancelling after one chunk stops later sends and discards partial data', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(
      initialText:
          '${_repeat('A', 8200)}广告一${_repeat('A', 8000)}广告二${_repeat('B', 1000)}',
    );
    fixture.responder = (call) async => _singleAdResponse(call, needle: '广告一');
    await fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['a'],
    );
    expect(fixture.task.totalChunks, 2);
    var cancellationRequested = false;
    fixture.task.addListener(() {
      if (!cancellationRequested && fixture.task.completedChunks == 1) {
        cancellationRequested = true;
        fixture.task.cancel();
      }
    });

    await fixture.task.run(fixture.task.consent!);

    expect(cancellationRequested, isTrue);
    expect(fixture.clients.single.calls, hasLength(1));
    expect(fixture.task.completedChunks, 1);
    expect(fixture.task.phase, AiProofreadingPhase.cancelled);
    expect(fixture.task.findings, isEmpty);
    expect(fixture.task.changes, isEmpty);
    expect(fixture.task.canApply, isFalse);
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test(
    'overlapping changes reject a combined selection but allow one item',
    () async {
      fixture.responder = (call) async => _overlappingResponse();
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(fixture.task.consent!);

      expect(fixture.task.changes, hasLength(2));
      expect(fixture.task.conflicts, hasLength(1));
      final changeIds = fixture.task.changes.map((change) => change.id).toSet();
      final conflict = fixture.task.conflicts.single;
      expect({conflict.firstId, conflict.secondId}, changeIds);

      await fixture.task.applySelected(changeIds);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.phase, AiProofreadingPhase.completed);
      expect(_text(fixture.session.activeChapter!, 'p1'), _initialText);
      expect(fixture.session.canUndo, isFalse);
      expect(fixture.store.savedDirtyIds, isEmpty);

      await fixture.task.applySelected({fixture.task.changes.first.id});
      expect(fixture.task.phase, AiProofreadingPhase.applied);
      expect(fixture.task.lastAppliedCount, 1);
      expect(_text(fixture.session.activeChapter!, 'p1'), '😀和广告。尾文');
    },
  );

  test(
    'credential and provider errors do not expose key or response text',
    () async {
      fixture.credentials.readError = StateError('credential-secret-raw');
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(
        fixture.task.failure!.message,
        isNot(contains('credential-secret-raw')),
      );
      expect(fixture.clients, isEmpty);

      fixture.credentials.readError = null;
      fixture.responder = (call) async =>
          throw StateError('$_apiKey provider-private-error-body');
      await fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['a'],
      );
      await fixture.task.run(fixture.task.consent!);
      expect(fixture.task.phase, AiProofreadingPhase.failed);
      expect(fixture.task.failure!.message, isNot(contains(_apiKey)));
      expect(
        fixture.task.failure!.message,
        isNot(contains('provider-private-error-body')),
      );
      expect(fixture.task.findings, isEmpty);
      expect(fixture.task.changes, isEmpty);
    },
  );

  test('cancellation during context loading stops preparation', () async {
    fixture.store
      ..gatedChapterId = 'b'
      ..chapterReadStarted = Completer<void>()
      ..chapterReadGate = Completer<void>();
    final preparing = fixture.task.prepare(
      intent: AiProofreadingIntent.advertisement,
      chapterIds: const ['b'],
    );
    await fixture.store.chapterReadStarted!.future;
    fixture.task.cancel();
    fixture.store.chapterReadGate!.complete();
    await preparing;

    expect(fixture.task.phase, AiProofreadingPhase.cancelled);
    expect(fixture.task.consent, isNull);
    expect(fixture.credentials.readReferences, isEmpty);
    expect(fixture.clients, isEmpty);
  });

  test(
    'revision change during context loading invalidates preparation',
    () async {
      fixture.store
        ..gatedChapterId = 'b'
        ..chapterReadStarted = Completer<void>()
        ..chapterReadGate = Completer<void>();
      final preparing = fixture.task.prepare(
        intent: AiProofreadingIntent.advertisement,
        chapterIds: const ['b'],
      );
      await fixture.store.chapterReadStarted!.future;
      fixture.session.editBlockText('p1', '修订后的当前章节');
      fixture.store.chapterReadGate!.complete();
      await preparing;

      expect(fixture.task.phase, AiProofreadingPhase.stale);
      expect(fixture.task.consent, isNull);
      expect(fixture.credentials.readReferences, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );
}

AiConfiguration _configurationAt(String address) => AiConfiguration(
  enabled: true,
  address: address,
  model: 'test-model',
  credentialReference: 'credential-1',
);

AiAuditGapRequest _auditGapRequest(_Fixture fixture) {
  final book = fixture.session.book!;
  final issue = Proofreading.audit(book).issues
      .singleWhere((issue) => issue.kind == AuditIssueKind.missingNumber);
  return AiAuditGapRequest.fromIssue(
    issue: issue,
    book: book,
    sessionId: fixture.session.sessionId!,
    sessionRevision: fixture.session.saveSeq,
  );
}

AiAdvertisementRequest _advertisementSelection(
  _Fixture fixture, {
  required int start,
  required int end,
  String original = '广告',
}) => AiAdvertisementRequest.fromSelection(
  book: fixture.session.book!,
  sessionId: fixture.session.sessionId!,
  sessionRevision: fixture.session.saveSeq,
  chapterId: 'a',
  blockId: 'p1',
  startUtf16: start,
  endUtf16: end,
  original: original,
);

String _text(Chapter chapter, String blockId) => (chapter.blocks.singleWhere(
  (block) => block.id == blockId,
) as TextBlock).text;

Map<String, dynamic> _context(_AiCall call) {
  final envelope = jsonDecode(call.userContext) as Map<String, dynamic>;
  return envelope['context'] as Map<String, dynamic>;
}

Map<String, dynamic> _firstSlice(_AiCall call) =>
    (_context(call)['blocks'] as List<dynamic>).first as Map<String, dynamic>;

Map<String, String> _targetFor(_AiCall call, String needle, {String? blockId}) {
  final slice = blockId == null
      ? _firstSlice(call)
      : (_context(call)['blocks'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .singleWhere((slice) => slice['block_id'] == blockId);
  final sliceText = slice['text'] as String;
  final foundAt = sliceText.indexOf(needle);
  if (foundAt < 0) throw StateError('Expected target not found in this chunk.');
  final surroundingText =
      '${slice['before'] as String}$sliceText${slice['after'] as String}';
  final start = (slice['before'] as String).length + foundAt;
  final end = start + needle.length;
  var contextStart = start > 8 ? start - 8 : 0;
  var contextEnd = end + 8 < surroundingText.length
      ? end + 8
      : surroundingText.length;
  while (contextStart > 0 &&
      _isLowSurrogate(surroundingText.codeUnitAt(contextStart))) {
    contextStart--;
  }
  while (contextEnd < surroundingText.length &&
      _isLowSurrogate(surroundingText.codeUnitAt(contextEnd))) {
    contextEnd++;
  }
  return {
    'chapter_id': slice['chapter_id'] as String,
    'block_id': slice['block_id'] as String,
    'original': needle,
    'before': surroundingText.substring(contextStart, start),
    'after': surroundingText.substring(end, contextEnd),
  };
}

bool _isLowSurrogate(int value) => value >= 0xdc00 && value <= 0xdfff;

String _repeat(String value, int count) =>
    List<String>.filled(count, value).join();

Map<String, Object?> _finding(
  Map<String, String> target, {
  String id = 'model-finding',
  String category = 'advertisement',
  String assessment = 'advertisement',
}) => {
  'id': id,
  'category': category,
  'assessment': assessment,
  'chapter_id': target['chapter_id']!,
  'block_id': target['block_id']!,
  'original': target['original']!,
  'before': target['before']!,
  'after': target['after']!,
  'reason': '上下文中出现了精确候选。',
};

Map<String, Object?> _proposal(
  Map<String, String> target, {
  String id = 'model-change',
  String findingId = 'model-finding',
  String action = 'delete_text',
  String replacement = '',
  String? original,
  String? before,
  String? after,
}) => {
  'id': id,
  'finding_id': findingId,
  'action': action,
  'chapter_id': target['chapter_id']!,
  'block_id': target['block_id']!,
  'original': original ?? target['original']!,
  'before': before ?? target['before']!,
  'after': after ?? target['after']!,
  'replacement': replacement,
  'reason': '仅提出精确局部修改，等待人工选择。',
};

Map<String, Object?> _splitProposal(
  Map<String, String> target, {
  required String id,
  required String findingId,
  bool removeTitleLine = true,
}) => {
  'id': id,
  'finding_id': findingId,
  'action': 'split_chapter',
  'chapter_id': target['chapter_id']!,
  'block_id': target['block_id']!,
  'original': target['original']!,
  'before': target['before']!,
  'after': target['after']!,
  'title': target['original']!.trim(),
  'remove_title_line': removeTitleLine,
  'reason': '原文存在可独立定位的标题行。',
};

Map<String, Object?> _renameProposal(
  Map<String, String> target, {
  required String id,
  required String findingId,
  String originalTitle = '第一章',
}) => _proposal(
  target,
  id: id,
  findingId: findingId,
  action: 'rename_chapter',
  replacement: target['original']!.trim(),
)..['original_title'] = originalTitle;

AiRuleRequest _jointRequest({
  ProofreadingRuleKind kind = ProofreadingRuleKind.advertisement,
  List<String> positive = const ['广告'],
  List<String> negative = const ['普通正文'],
}) => AiRuleRequest(
  kind: kind,
  positiveExamples: positive,
  negativeExamples: negative,
);

Map<String, Object?> _jointRule(AiRuleRequest request) => {
  'schema_version': 1,
  'name': '本书候选',
  'kind': request.kind.name,
  'target': request.kind == ProofreadingRuleKind.chapter
      ? 'heading_line'
      : 'paragraph',
  'match': {
    'mode': 'literal',
    'pattern': request.positiveExamples.first,
    'case_sensitive': true,
  },
  'action': request.kind == ProofreadingRuleKind.chapter
      ? 'chapter_candidate'
      : 'advertisement_candidate',
  'positive_examples': request.positiveExamples,
  'negative_examples': request.negativeExamples,
  'reason': '只针对显式请求的样例提供本书规则候选。',
};

String _analysisResponse({
  List<Map<String, Object?>> findings = const [],
  List<Map<String, Object?>> proposals = const [],
  List<Map<String, Object?>> rules = const [],
}) => jsonEncode({
  'schema_version': 1,
  'findings': findings,
  'proposals': proposals,
  'rule_proposals': rules,
});

String _singleFindingResponse(
  _AiCall call, {
  String needle = '广告',
  String id = 'model-finding',
  String category = 'advertisement',
  String assessment = 'advertisement',
}) {
  final target = _targetFor(call, needle);
  return _analysisResponse(
    findings: [
      _finding(target, id: id, category: category, assessment: assessment),
    ],
  );
}

String _singleAdResponse(
  _AiCall call, {
  String needle = '广告',
  String findingId = 'model-finding',
  String proposalId = 'model-change',
}) {
  final target = _targetFor(call, needle);
  return _analysisResponse(
    findings: [_finding(target, id: findingId)],
    proposals: [_proposal(target, id: proposalId, findingId: findingId)],
  );
}

String _wholeBlockAdResponse(_AiCall call) {
  final slice = _firstSlice(call);
  final text = slice['text'] as String;
  final target = <String, String>{
    'chapter_id': slice['chapter_id'] as String,
    'block_id': slice['block_id'] as String,
    'original': text,
    'before': '',
    'after': '',
  };
  return _analysisResponse(
    findings: [_finding(target)],
    proposals: [_proposal(target, action: 'remove_block')],
  );
}

String _splitResponse(
  _AiCall call, {
  String needle = '第三章 风雨',
  String? blockId,
  List<String> proposalIds = const ['split-proposal'],
}) {
  final target = _targetFor(call, needle, blockId: blockId);
  const findingId = 'split-finding';
  return _analysisResponse(
    findings: [
      _finding(
        target,
        id: findingId,
        category: 'missing_chapter',
        assessment: 'missed_heading',
      ),
    ],
    proposals: [
      for (final id in proposalIds)
        _splitProposal(target, id: id, findingId: findingId),
    ],
  );
}

String _renameResponse(_AiCall call, {String needle = '第三章 风雨'}) {
  final target = _targetFor(call, needle);
  return _analysisResponse(
    findings: [
      _finding(
        target,
        category: 'missing_chapter',
        assessment: 'missed_heading',
      ),
    ],
    proposals: [
      _renameProposal(target, id: 'rename', findingId: 'model-finding'),
    ],
  );
}

String _mixedSplitTextResponse(_AiCall call) {
  final firstHeading = _targetFor(call, '第三章 风雨');
  final secondHeading = _targetFor(call, '第四章 清明');
  final titleText = _targetFor(call, '第三章');
  final tailText = _targetFor(call, '尾部广告');
  return _analysisResponse(
    findings: [
      _finding(
        firstHeading,
        id: 'split-finding-a',
        category: 'missing_chapter',
        assessment: 'missed_heading',
      ),
      _finding(
        secondHeading,
        id: 'split-finding-b',
        category: 'missing_chapter',
        assessment: 'missed_heading',
      ),
      _finding(
        titleText,
        id: 'text-finding-title',
        category: 'advertisement',
        assessment: 'advertisement',
      ),
      _finding(
        tailText,
        id: 'text-finding-tail',
        category: 'advertisement',
        assessment: 'advertisement',
      ),
    ],
    proposals: [
      _splitProposal(firstHeading, id: 'split-a', findingId: 'split-finding-a'),
      _splitProposal(
        secondHeading,
        id: 'split-b',
        findingId: 'split-finding-b',
      ),
      _proposal(
        titleText,
        id: 'delete-title-text',
        findingId: 'text-finding-title',
      ),
      _proposal(
        tailText,
        id: 'delete-tail-text',
        findingId: 'text-finding-tail',
      ),
    ],
  );
}

String _overlappingResponse() {
  const target = {
    'chapter_id': 'a',
    'block_id': 'p1',
    'original': '广告和',
    'before': '😀',
    'after': '',
  };
  return _analysisResponse(
    findings: [_finding(target)],
    proposals: [
      _proposal(
        target,
        id: 'overlap-short',
        original: '广告',
        before: '😀',
        after: '和',
      ),
      _proposal(
        target,
        id: 'overlap-long',
        original: '广告和',
        before: '😀',
        after: '',
      ),
    ],
  );
}

Future<({Future<void> running, Completer<String> gate, String response})>
_startHeldRun(_Fixture fixture) async {
  final requestStarted = Completer<void>();
  final responseGate = Completer<String>();
  late String response;
  fixture.responder = (call) {
    response = _singleAdResponse(call);
    if (!requestStarted.isCompleted) requestStarted.complete();
    return responseGate.future;
  };
  await fixture.task.prepare(
    intent: AiProofreadingIntent.advertisement,
    chapterIds: const ['a'],
  );
  final running = fixture.task.run(fixture.task.consent!);
  await requestStarted.future;
  return (running: running, gate: responseGate, response: response);
}

class _Fixture {
  _Fixture._({
    required this.store,
    required this.session,
    required this.jobs,
    required this.credentials,
  });

  static Future<_Fixture> open({
    String initialText = _initialText,
    List<Block> extraBlocks = const [],
    bool withVolume = false,
    bool withUnselectedChapter = false,
  }) async {
    final store = _MemoryStore(
      initialText: initialText,
      extraBlocks: extraBlocks,
      withVolume: withVolume,
      withUnselectedChapter: withUnselectedChapter,
    );
    final jobs = _InlineJobs();
    final session = EditorSession.withStore(
      store: store,
      jobs: jobs,
      debounce: const Duration(milliseconds: 800),
    );
    await session.open('book');
    final fixture = _Fixture._(
      store: store,
      session: session,
      jobs: jobs,
      credentials: _MemoryCredentials(),
    );
    fixture.task = fixture.createTask();
    return fixture;
  }

  final _MemoryStore store;
  final EditorSession session;
  final _InlineJobs jobs;
  final _MemoryCredentials credentials;
  final List<AiProofreadingTask> tasks = [];
  final List<_MemoryClient> clients = [];
  AiConfiguration configuration = _validConfiguration;
  Future<String> Function(_AiCall call) responder = (call) async =>
      _analysisResponse();
  late AiProofreadingTask task;
  bool sessionClosed = false;

  AiProofreadingTask createTask() {
    final task = AiProofreadingTask(
      session: session,
      loadConfiguration: () async => configuration,
      credentials: credentials,
      createClient: () {
        final client = _MemoryClient((call) => responder(call));
        clients.add(client);
        return client;
      },
      jobs: jobs,
    );
    tasks.add(task);
    return task;
  }

  Future<void> closeSession() async {
    await session.close();
    sessionClosed = true;
  }

  Future<void> dispose() async {
    for (final task in tasks) {
      task.dispose();
    }
    if (!sessionClosed) session.dispose();
  }
}

class _MemoryStore implements EditorBookStore {
  _MemoryStore({
    required String initialText,
    List<Block> extraBlocks = const [],
    bool withVolume = false,
    bool withUnselectedChapter = false,
  }) {
    final now = DateTime.utc(2026, 11, 6);
    books['book'] = Book(
      id: 'book',
      meta: BookMeta(title: '测试书', author: '作者'),
      chapters: [
        if (withVolume)
          const Chapter(
            id: 'volume',
            bookId: 'book',
            title: '本地卷名不外发',
            level: 1,
            order: 0,
          ),
        Chapter(
          id: 'a',
          bookId: 'book',
          title: '第一章',
          parentId: withVolume ? 'volume' : null,
          order: withVolume ? 1 : 0,
        ),
        Chapter(
          id: 'b',
          bookId: 'book',
          title: '第二章',
          parentId: withVolume ? 'volume' : null,
          order: withVolume ? 2 : 1,
        ),
        if (withUnselectedChapter)
          Chapter(
            id: 'c',
            bookId: 'book',
            title: '未选章机密标题',
            parentId: withVolume ? 'volume' : null,
            order: withVolume ? 3 : 2,
          ),
      ],
      createdAt: now,
      updatedAt: now,
      wordCount: WordCount.ofText(initialText) + WordCount.ofText('后文广告'),
    );
    bodies[('book', 'a')] = Chapter(
      id: 'a',
      bookId: 'book',
      title: '第一章',
      parentId: withVolume ? 'volume' : null,
      order: 0,
      blocks: [
        TextBlock(id: 'p1', text: initialText),
        ...extraBlocks,
      ],
    );
    bodies[('book', 'b')] = Chapter(
      id: 'b',
      bookId: 'book',
      title: '第二章',
      parentId: withVolume ? 'volume' : null,
      order: 1,
      blocks: const [TextBlock(id: 'p2', text: '后文广告')],
    );
    if (withUnselectedChapter) {
      bodies[('book', 'c')] = const Chapter(
        id: 'c',
        bookId: 'book',
        title: '未选章机密标题',
        blocks: [TextBlock(id: 'unselected', text: '未选章机密正文')],
      );
    }
    books['other'] = Book(
      id: 'other',
      meta: BookMeta(title: '另一本书'),
      chapters: const [
        Chapter(id: 'other-a', bookId: 'other', title: '正文', order: 0),
      ],
      createdAt: now,
      updatedAt: now,
    );
    bodies[('other', 'other-a')] = const Chapter(
      id: 'other-a',
      bookId: 'other',
      title: '正文',
      order: 0,
      blocks: [TextBlock(id: 'other-p1', text: '另一本文字')],
    );
  }

  final Map<String, Book> books = {};
  final Map<(String, String), Chapter> bodies = {};
  final List<String> loadedChapterIds = [];
  final List<Set<String>> savedDirtyIds = [];
  Completer<void>? chapterReadStarted;
  Completer<void>? chapterReadGate;
  String? gatedChapterId;

  Chapter? body(String bookId, String chapterId) => bodies[(bookId, chapterId)];

  @override
  Future<Book?> loadBook(String bookId) async => books[bookId];

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async {
    loadedChapterIds.add('$bookId/$chapterId');
    if (chapterId == gatedChapterId && chapterReadGate != null) {
      final started = chapterReadStarted;
      if (started != null && !started.isCompleted) started.complete();
      await chapterReadGate!.future;
    }
    return bodies[(bookId, chapterId)];
  }

  @override
  Future<Book> saveBook(
    Book source, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    final current = books[source.id];
    if (current == null || current.revision != expectedRevision) {
      throw const StorageFailure('测试书稿修订冲突');
    }
    savedDirtyIds.add(Set<String>.of(dirtyChapterIds));
    for (final chapter in source.chapters) {
      if (dirtyChapterIds.contains(chapter.id)) {
        bodies[(source.id, chapter.id)] = chapter;
      }
    }
    final saved = source.copyWith(
      chapters: [
        for (final chapter in source.chapters)
          chapter.copyWith(blocks: const <Block>[]),
      ],
      revision: expectedRevision + 1,
    );
    books[source.id] = saved;
    return saved;
  }
}

class _MemoryCredentials implements AiCredentialStore {
  String? value = _apiKey;
  Object? readError;
  Completer<void>? readStarted;
  Completer<String?>? gate;
  final List<String> readReferences = [];

  @override
  Future<String?> read(String reference) async {
    readReferences.add(reference);
    final started = readStarted;
    if (started != null && !started.isCompleted) started.complete();
    if (readError case final error?) throw error;
    final pending = gate;
    if (pending != null) return pending.future;
    return value;
  }

  @override
  Future<void> write(String reference, String value) async {}

  @override
  Future<void> delete(String reference) async {}
}

class _AiCall {
  const _AiCall({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    required this.userContext,
  });

  final AiEndpoint endpoint;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final String userContext;
}

class _MemoryClient implements AiTextClient {
  _MemoryClient(this.responder);

  final Future<String> Function(_AiCall call) responder;
  final List<_AiCall> calls = [];
  int activeRequests = 0;
  int maxConcurrent = 0;
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
  }) async {
    final call = _AiCall(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      userContext: userContext,
    );
    calls.add(call);
    activeRequests++;
    if (activeRequests > maxConcurrent) maxConcurrent = activeRequests;
    try {
      return await responder(call);
    } finally {
      activeRequests--;
    }
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class _InlineJobs extends BackgroundJobs {
  @override
  bool get isBusy => false;

  @override
  Future<R> run<T, R>(
    T input,
    FutureOr<R> Function(T, void Function(double, String)) compute, {
    required int revision,
    Duration timeout = const Duration(minutes: 2),
    void Function(JobProgress)? onProgress,
  }) async => compute(input, (fraction, stage) {
    onProgress?.call(JobProgress(1, revision, fraction, stage));
  });

  @override
  void cancelActive() {}
}
