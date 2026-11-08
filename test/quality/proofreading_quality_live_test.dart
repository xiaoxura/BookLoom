import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/features/settings/data/ai_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/proofreading_quality.dart'
    show validateReferenceCorpusCoverage;
import '../../tool/src/proofreading_quality.dart';
import '../../tool/src/proofreading_quality_live.dart';

const _emptyResult =
    '{"schema_version":1,"findings":[],"proposals":[],"rule_proposals":[]}';

void main() {
  final corpus = QualityCorpus.decode(
    File('test/fixtures/proofreading/quality-corpus.json').readAsStringSync(),
  );

  setUpAll(() => validateReferenceCorpusCoverage(corpus));

  test('non-live arguments keep the replay and rule modes working', () {
    final replay = QualityCliOptions.parse([
      '--responses=batch.json',
      '--output=report.json',
      '--strict',
    ], const {});
    expect(replay.strict, isTrue);
    expect(replay.responsesPath, 'batch.json');
    expect(replay.outputPath, 'report.json');
    expect(replay.live, isNull);

    final rules = QualityCliOptions.parse(const [], const {});
    expect(rules.responsesPath, isNull);
    expect(rules.live, isNull);
  });

  test('live arguments normalize the endpoint without exposing the key', () {
    final options = QualityCliOptions.parse(
      [
        '--live',
        '--format=chat',
        '--base-url=http://127.0.0.1:1234',
        '--model= synthetic-model ',
        '--key-env=BOOKLOOM_TEST_KEY',
        '--max-cases=3',
        '--timeout=15',
        '--output=live.json',
      ],
      const {'BOOKLOOM_TEST_KEY': 'sk-synthetic-secret'},
    ).live!;

    expect(options.endpoint.format, AiEndpointFormat.openAiChatCompletions);
    expect(
      options.endpoint.requestUri.toString(),
      'http://127.0.0.1:1234/v1/chat/completions',
    );
    expect(options.model, 'synthetic-model');
    expect(options.apiKey, 'sk-synthetic-secret');
    expect(options.maxCases, 3);
    expect(options.timeout, const Duration(seconds: 15));
    expect(
      jsonEncode(liveProviderMetadata(options, LiveCollectionResult.empty())),
      isNot(contains('sk-synthetic-secret')),
    );
  });

  test('live configuration rejects unsafe or incomplete requests', () {
    Map<String, String> env([String key = 'sk-secret']) => {'TEST_KEY': key};
    List<String> args({
      String format = 'chat',
      String url = 'http://127.0.0.1:1',
      String model = 'm',
      String keyEnv = 'TEST_KEY',
      String? extra,
    }) => [
      '--live',
      '--format=$format',
      '--base-url=$url',
      '--model=$model',
      '--key-env=$keyEnv',
      ?extra,
    ];

    final cases = <List<String>>[
      ['--live', '--format=chat', '--base-url=http://127.0.0.1:1'],
      args(keyEnv: 'MISSING_KEY'),
      args(url: 'http://api.example.com'),
      args(format: 'unknown'),
      args(model: ' '),
      args(extra: '--max-cases=0'),
      args(extra: '--timeout=1'),
      args(extra: '--responses=batch.json'),
      [...args(), '--unknown-flag'],
      ['--format=chat', '--base-url=http://127.0.0.1:1'],
    ];
    for (final arguments in cases) {
      expect(
        () => QualityCliOptions.parse(arguments, env()),
        throwsFormatException,
        reason: '$arguments',
      );
    }
    expect(
      () => QualityCliOptions.parse(args(keyEnv: 'TEST_KEY'), env('')),
      throwsFormatException,
    );
    expect(
      () => QualityCliOptions.parse(args(keyEnv: 'test_key'), env()),
      throwsFormatException,
    );
    try {
      QualityCliOptions.parse(args(url: 'http://api.example.com'), env());
      fail('remote http must be rejected');
    } on FormatException catch (error) {
      expect(error.message, isNot(contains('sk-secret')));
    }
  });

  test('collector sends exactly one prompt per corpus chunk', () async {
    final options = QualityCliOptions.parse(
      [
        '--live',
        '--format=chat',
        '--base-url=http://127.0.0.1:1',
        '--model=m',
        '--key-env=TEST_KEY',
      ],
      const {'TEST_KEY': 'sk-secret'},
    ).live!;
    final client = _FakeClient();
    final collection = await collectLiveResponses(
      corpus,
      options: options,
      client: client,
    );

    final expectedChunks = corpus.cases
        .map((qualityCase) => qualityCase.plan.chunks.length)
        .fold<int>(0, (sum, count) => sum + count);
    expect(collection.requests, expectedChunks);
    expect(collection.failedCaseIds, isEmpty);
    expect(collection.skippedCaseIds, isEmpty);
    expect(collection.failureKinds, isEmpty);
    expect(client.calls, expectedChunks);
    expect(
      collection.responsesByCase.values.every(
        (responses) => responses.every((response) => response == _emptyResult),
      ),
      isTrue,
    );
    final systems = client.captured.map((entry) => entry.system).toList();
    expect(
      systems.any((prompt) => prompt.contains('Task: advertisement')),
      isTrue,
    );
    expect(
      systems.any((prompt) => prompt.contains('Task: missingChapter')),
      isTrue,
    );
    final missingIndex = corpus.cases.indexWhere(
      (qualityCase) => qualityCase.intent.name == 'missingChapter',
    );
    expect(missingIndex, greaterThanOrEqualTo(0));
    final offset = corpus.cases
        .take(missingIndex)
        .map((qualityCase) => qualityCase.plan.chunks.length)
        .fold<int>(0, (sum, count) => sum + count);
    final captured = client.captured[offset];
    final decoded = jsonDecode(captured.user) as Map<String, dynamic>;
    expect(decoded['task'], 'missingChapter');
    expect(decoded['context'], isA<Map<String, dynamic>>());
    expect(captured.user, isNot(contains('收藏星河书屋')));
  });

  test('collector keeps failed cases invalid and continues', () async {
    final options = QualityCliOptions.parse(
      [
        '--live',
        '--format=chat',
        '--base-url=http://127.0.0.1:1',
        '--model=m',
        '--key-env=TEST_KEY',
      ],
      const {'TEST_KEY': 'sk-secret'},
    ).live!;
    final client = _FakeClient(failAt: 2);
    final collection = await collectLiveResponses(
      corpus,
      options: options,
      client: client,
    );

    expect(
      collection.requests,
      corpus.cases
          .map((qualityCase) => qualityCase.plan.chunks.length)
          .fold<int>(0, (sum, count) => sum + count),
    );
    expect(collection.failedCaseIds, hasLength(1));
    expect(collection.failedCaseIds.single, corpus.cases[1].id);
    expect(collection.failureKinds, ['transport:connection']);
    final failed = collection.failedCaseIds.single;
    expect(
      collection.responsesByCase[failed]!.every(
        (response) => response == liveInvalidResponse,
      ),
      isTrue,
    );
    final evaluation = QualityEvaluator.evaluateResponses(
      corpus,
      collection.responsesByCase,
    );
    expect(evaluation.summary['invalid_cases'], 1);
    expect(evaluation.hasStrictFailure, isTrue);
  });

  test('collector stops sending once cancelled', () async {
    final options = QualityCliOptions.parse(
      [
        '--live',
        '--format=chat',
        '--base-url=http://127.0.0.1:1',
        '--model=m',
        '--key-env=TEST_KEY',
      ],
      const {'TEST_KEY': 'sk-secret'},
    ).live!;
    final client = _FakeClient();
    final collection = await collectLiveResponses(
      corpus,
      options: options,
      client: client,
      isCancelled: () => client.calls >= 1,
    );

    expect(collection.requests, 1);
    expect(collection.cancelled, isTrue);
    expect(collection.skippedCaseIds, isNotEmpty);
    expect(collection.requestedCaseIds, hasLength(1));
    final evaluation = QualityEvaluator.evaluateResponses(
      corpus,
      collection.responsesByCase,
    );
    expect(evaluation.summary['invalid_cases'], corpus.cases.length - 1);
  });

  test(
    'max-cases bounds provider usage without shrinking the corpus',
    () async {
      final options = QualityCliOptions.parse(
        [
          '--live',
          '--format=chat',
          '--base-url=http://127.0.0.1:1',
          '--model=m',
          '--key-env=TEST_KEY',
          '--max-cases=2',
        ],
        const {'TEST_KEY': 'sk-secret'},
      ).live!;
      final client = _FakeClient();
      final collection = await collectLiveResponses(
        corpus,
        options: options,
        client: client,
      );

      expect(collection.requestedCaseIds, hasLength(2));
      expect(collection.skippedCaseIds, hasLength(corpus.cases.length - 2));
      final evaluation = QualityEvaluator.evaluateResponses(
        corpus,
        collection.responsesByCase,
      );
      expect(evaluation.summary['case_count'], corpus.cases.length);
      expect(evaluation.summary['invalid_cases'], corpus.cases.length - 2);
      expect(evaluation.hasStrictFailure, isTrue);
    },
  );

  test(
    'real transport sends protocol requests with the key only in headers',
    () async {
      final requests = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add({
          'path': request.uri.path,
          'authorization': request.headers.value('authorization'),
          'model': (jsonDecode(body) as Map<String, dynamic>)['model'],
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'object': 'chat.completion',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': _emptyResult},
                'finish_reason': 'stop',
              },
            ],
          }),
        );
        await request.response.close();
      });
      final options = QualityCliOptions.parse(
        [
          '--live',
          '--format=chat',
          '--base-url=http://127.0.0.1:${server.port}',
          '--model=loopback-model',
          '--key-env=TEST_KEY',
          '--max-cases=1',
          '--timeout=10',
        ],
        const {'TEST_KEY': 'sk-loopback-secret'},
      ).live!;
      final client = AiHttpClient(timeout: const Duration(seconds: 10));
      addTearDown(client.dispose);

      final collection = await collectLiveResponses(
        corpus,
        options: options,
        client: client,
      );
      final evaluation = QualityEvaluator.evaluateResponses(
        corpus,
        collection.responsesByCase,
      );
      final metadata = liveProviderMetadata(options, collection);
      final report = evaluation.toJson();

      expect(collection.requests, 1);
      expect(requests.single['path'], '/v1/chat/completions');
      expect(requests.single['authorization'], 'Bearer sk-loopback-secret');
      expect(requests.single['model'], 'loopback-model');
      expect(metadata['endpoint_host'], '127.0.0.1');
      expect(metadata['model'], 'loopback-model');
      expect(metadata['key_env'], 'TEST_KEY');
      expect(metadata['requests'], 1);
      expect(metadata['failed_cases'], isEmpty);
      for (final payload in [jsonEncode(metadata), jsonEncode(report)]) {
        expect(payload, isNot(contains('sk-loopback-secret')));
      }
      expect(evaluation.summary['invalid_cases'], corpus.cases.length - 1);
      expect(evaluation.summary['classification_status'], 'applicable');
      expect(report['realProviderQualityVerified'], isFalse);
    },
  );
}

class _FakeClient implements AiTextClient {
  _FakeClient({this.failAt});

  final int? failAt;
  int calls = 0;
  final List<({String system, String user})> captured = [];

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
    calls++;
    captured.add((system: systemPrompt, user: userContext));
    if (failAt == calls) {
      throw const AiTransportException(AiTransportFailure.connection);
    }
    return _emptyResult;
  }

  @override
  void dispose() {}
}
