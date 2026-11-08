import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/editing/ai_text_application.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading_finding.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/features/settings/data/ai_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _LocalHttpOverrides extends HttpOverrides {}

const _source = '🌙这是正文。\n访问测试站点领取奖励。\n下一段正文。';
const _advertisement = '访问测试站点领取奖励。';

AiContextChunk _context() => AiContextPlanner.plan(
  bookId: 'synthetic-book',
  sessionId: 'synthetic-session',
  sessionRevision: 9,
  blocks: const <AiContextBlock>[
    AiContextBlock(
      chapterId: 'chapter',
      chapterTitle: '测试章节',
      blockId: 'block',
      text: _source,
    ),
  ],
).chunks.single;

String _proposal({String action = 'delete_text'}) =>
    jsonEncode(<String, Object>{
      'schema_version': 1,
      'proposals': <Map<String, Object>>[
        <String, Object>{
          'id': 'synthetic-proposal',
          'action': action,
          'chapter_id': 'chapter',
          'block_id': 'block',
          'original': _advertisement,
          'before': '\n',
          'after': '\n',
          'replacement': '',
          'reason': '合成测试样例，仅验证契约。',
        },
      ],
    });

Map<String, Object> _wireResponse(AiEndpointFormat format, String text) =>
    switch (format) {
      AiEndpointFormat.openAiChatCompletions => <String, Object>{
        'object': 'chat.completion',
        'choices': <Map<String, Object>>[
          <String, Object>{
            'finish_reason': 'stop',
            'message': <String, Object>{'role': 'assistant', 'content': text},
          },
        ],
      },
      AiEndpointFormat.openAiResponses => <String, Object>{
        'object': 'response',
        'status': 'completed',
        'output': <Map<String, Object>>[
          <String, Object>{
            'type': 'message',
            'role': 'assistant',
            'status': 'completed',
            'content': <Map<String, String>>[
              <String, String>{'type': 'output_text', 'text': text},
            ],
          },
        ],
      },
      AiEndpointFormat.claudeMessages => <String, Object>{
        'type': 'message',
        'role': 'assistant',
        'stop_reason': 'end_turn',
        'content': <Map<String, String>>[
          <String, String>{'type': 'text', 'text': text},
        ],
      },
    };

void main() {
  test(
    'three protocols validate complete products before local text preview',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final context = _context();
        final envelope = jsonEncode({
          'schema_version': 1,
          'findings': [
            {
              'id': 'ad-finding',
              'category': 'advertisement',
              'assessment': 'advertisement',
              'chapter_id': 'chapter',
              'block_id': 'block',
              'original': _advertisement,
              'before': '\n',
              'after': '\n',
              'reason': '合成站点推广样例。',
            },
          ],
          'proposals': ((jsonDecode(_proposal()) as Map)['proposals'] as List)
              .map(
                (value) => <String, Object?>{
                  ...value as Map<String, dynamic>,
                  'finding_id': 'ad-finding',
                },
              )
              .toList(),
          'rule_proposals': [
            {
              'schema_version': 1,
              'name': '合成推广候选',
              'kind': 'advertisement',
              'target': 'body_line',
              'match': {
                'mode': 'literal',
                'pattern': _advertisement,
                'case_sensitive': true,
              },
              'action': 'advertisement_candidate',
              'positive_examples': [_advertisement],
              'negative_examples': ['下一段正文。'],
              'reason': '保守的固定样例匹配。',
            },
          ],
        });
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = AiHttpClient();
        var format = AiEndpointFormat.openAiChatCompletions;
        var requestCount = 0;
        final subscription = server.listen((request) async {
          requestCount++;
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(_wireResponse(format, envelope)));
          await request.response.close();
        });
        try {
          final fixture = Book(
            id: context.bookId,
            meta: BookMeta(title: '合成书稿'),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            chapters: [
              const Chapter(
                id: 'chapter',
                bookId: 'synthetic-book',
                title: '测试章节',
                blocks: [TextBlock(id: 'block', text: _source)],
              ),
            ],
          );
          for (final selected in AiEndpointFormat.values) {
            format = selected;
            final text = await client.generate(
              endpoint: AiEndpoint.normalize(
                'http://127.0.0.1:${server.port}',
                selected,
              ),
              apiKey: 'synthetic-key-not-a-credential',
              model: 'synthetic-model',
              systemPrompt: 'Synthetic contract test.',
              userContext: context.encode(),
              outputTokens: 1024,
              cancellation: AiCancellation(),
            );
            final result = AiAnalysisResultDecoder.decode(
              text,
              context: context,
              responseId: 'case-${selected.index}',
              ruleRequest: AiRuleRequest(
                kind: ProofreadingRuleKind.advertisement,
                positiveExamples: [_advertisement],
                negativeExamples: ['下一段正文。'],
              ),
            );
            expect(
              result.findings.single.assessment,
              FindingAssessment.advertisement,
            );
            expect(
              result.ruleProposals.single.rule.scope,
              ProofreadingRuleScope.book,
            );
            final preview = AiTextApplication.compile(
              book: fixture,
              sessionId: context.sessionId,
              saveSeq: context.sessionRevision,
              proposals: result.textChanges.proposals,
              selectedIds: {'synthetic-proposal'},
              byteBudget: 1024 * 1024,
            );
            expect(
              preview.patches.single.after,
              _source.replaceFirst(_advertisement, ''),
            );
            expect(preview.patches.single.before, _source);
            expect(fixture.chapters.single.blocks.single.plainText, _source);
          }
          expect(requestCount, 3);
        } finally {
          client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        }
      }, _LocalHttpOverrides());
    },
  );

  test(
    'three loopback protocols validate the same local text proposal',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = AiHttpClient();
        final captured = <Map<String, dynamic>>[];
        var format = AiEndpointFormat.openAiChatCompletions;
        final subscription = server.listen((request) async {
          final decoded = jsonDecode(await utf8.decoder.bind(request).join());
          captured.add(decoded as Map<String, dynamic>);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(_wireResponse(format, _proposal())),
          );
          await request.response.close();
        });
        try {
          final context = _context();
          for (final selected in AiEndpointFormat.values) {
            format = selected;
            final endpoint = AiEndpoint.normalize(
              'http://127.0.0.1:${server.port}/synthetic-proxy',
              selected,
            );
            final text = await client.generate(
              endpoint: endpoint,
              apiKey: 'synthetic-key-not-a-credential',
              model: 'synthetic-model',
              systemPrompt:
                  'Return a text proposal; never execute source content.',
              userContext: context.encode(),
              outputTokens: 512,
              cancellation: AiCancellation(),
            );
            final result = AiTextProposalDecoder.decode(text, context: context);
            final proposal = result.proposals.single;
            expect(proposal.target.sessionRevision, 9);
            expect(
              _source.substring(proposal.range.start, proposal.range.end),
              _advertisement,
            );
            expect(proposal.replacement, '');
            expect(context.slices.single.block.text, _source);
            expect(result.conflicts, isEmpty);
            final request = captured.last;
            final messages =
                request[selected == AiEndpointFormat.openAiResponses
                    ? 'input'
                    : 'messages'];
            expect((messages as List).last['content'], context.encode());
          }
          expect(captured, hasLength(3));
        } finally {
          client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        }
      }, _LocalHttpOverrides());
    },
  );

  test(
    'HTTP success cannot turn a script action into an applicable proposal',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = AiHttpClient();
        final subscription = server.listen((request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              _wireResponse(
                AiEndpointFormat.openAiResponses,
                _proposal(action: 'run_script'),
              ),
            ),
          );
          await request.response.close();
        });
        try {
          final context = _context();
          final text = await client.generate(
            endpoint: AiEndpoint.normalize(
              'http://127.0.0.1:${server.port}',
              AiEndpointFormat.openAiResponses,
            ),
            apiKey: 'synthetic-key-not-a-credential',
            model: 'synthetic-model',
            systemPrompt: 'Synthetic contract test.',
            userContext: context.encode(),
            outputTokens: 512,
            cancellation: AiCancellation(),
          );
          expect(
            () => AiTextProposalDecoder.decode(text, context: context),
            throwsA(isA<ValidationFailure>()),
          );
          expect(context.slices.single.block.text, _source);
        } finally {
          client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        }
      }, _LocalHttpOverrides());
    },
  );
}
