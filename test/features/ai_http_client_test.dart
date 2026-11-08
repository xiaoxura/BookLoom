import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/features/settings/data/ai_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _secret = 'local-test-secret';
const _context = 'Only local test context.';

String _responseFor(AiEndpointFormat format, [String text = 'Answer']) =>
    jsonEncode(switch (format) {
      AiEndpointFormat.openAiChatCompletions => <String, Object?>{
        'object': 'chat.completion',
        'choices': <Object?>[
          <String, Object?>{
            'finish_reason': 'stop',
            'message': <String, Object?>{'role': 'assistant', 'content': text},
          },
        ],
      },
      AiEndpointFormat.openAiResponses => <String, Object?>{
        'object': 'response',
        'status': 'completed',
        'output': <Object?>[
          <String, Object?>{
            'type': 'message',
            'role': 'assistant',
            'status': 'completed',
            'content': <Object?>[
              <String, Object?>{'type': 'output_text', 'text': text},
            ],
          },
        ],
      },
      AiEndpointFormat.claudeMessages => <String, Object?>{
        'type': 'message',
        'role': 'assistant',
        'stop_reason': 'end_turn',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
      },
    });

AiEndpoint _endpoint(HttpServer server, AiEndpointFormat format) =>
    AiEndpoint.normalize('http://127.0.0.1:${server.port}', format);

Future<String> _generate(
  AiHttpClient client,
  AiEndpoint endpoint, {
  AiCancellation? cancellation,
  String userContext = _context,
}) => client.generate(
  endpoint: endpoint,
  apiKey: _secret,
  model: 'local-test-model',
  systemPrompt: 'Return test text.',
  userContext: userContext,
  outputTokens: 64,
  cancellation: cancellation ?? AiCancellation(),
);

Future<void> _expectTransport(
  Future<String> operation,
  AiTransportFailure failure,
) => expectLater(
  operation,
  throwsA(
    isA<AiTransportException>().having(
      (error) => error.failure,
      'failure',
      failure,
    ),
  ),
);

Future<void> _awaitSignal(Future<void> signal) =>
    signal.timeout(const Duration(seconds: 2));

Future<HttpServer> _server(FutureOr<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    unawaited(
      Future<void>.sync(() => handler(request)).catchError((Object _) {}),
    );
  });
  addTearDown(() => server.close(force: true));
  return server;
}

AiHttpClient _client({
  Duration timeout = const Duration(seconds: 2),
  int maxRequestBytes = 512 * 1024,
  int maxResponseBytes = 512 * 1024,
}) {
  final client = AiHttpClient(
    timeout: timeout,
    maxRequestBytes: maxRequestBytes,
    maxResponseBytes: maxResponseBytes,
  );
  addTearDown(client.dispose);
  return client;
}

class _DelayedCancelClient implements HttpClient {
  _DelayedCancelClient(this.delegate, this.entered, this.release);

  final HttpClient delegate;
  final Completer<void> entered;
  final Completer<void> release;

  @override
  set autoUncompress(bool value) => delegate.autoUncompress = value;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _DelayedCancelRequest(await delegate.postUrl(url), entered, release);

  @override
  void close({bool force = false}) => delegate.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedCancelRequest implements HttpClientRequest {
  _DelayedCancelRequest(this.delegate, this.entered, this.release);

  final HttpClientRequest delegate;
  final Completer<void> entered;
  final Completer<void> release;

  @override
  set followRedirects(bool value) => delegate.followRedirects = value;

  @override
  set contentLength(int value) => delegate.contentLength = value;

  @override
  HttpHeaders get headers => delegate.headers;

  @override
  void add(List<int> data) => delegate.add(data);

  @override
  Future<HttpClientResponse> close() async =>
      _DelayedCancelResponse(await delegate.close(), entered, release);

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      delegate.abort(exception, stackTrace);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedCancelResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _DelayedCancelResponse(this.delegate, this.entered, this.release);

  final HttpClientResponse delegate;
  final Completer<void> entered;
  final Completer<void> release;

  @override
  int get statusCode => delegate.statusCode;

  @override
  int get contentLength => delegate.contentLength;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _DelayedCancelSubscription(
    delegate.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
    entered,
    release,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedCancelSubscription implements StreamSubscription<List<int>> {
  _DelayedCancelSubscription(this.delegate, this.entered, this.release);

  final StreamSubscription<List<int>> delegate;
  final Completer<void> entered;
  final Completer<void> release;

  @override
  Future<void> cancel() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await delegate.cancel();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpOverrides? priorOverrides;
  setUpAll(() {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = priorOverrides);

  test('cancellation notifies every listener without exposing errors', () {
    final cancellation = AiCancellation();
    var notifications = 0;
    cancellation.onCancel(() => throw StateError('private task text'));
    cancellation.onCancel(() => notifications++);
    expect(cancellation.cancel, returnsNormally);
    expect(notifications, 1);
    expect(cancellation.isCancelled, isTrue);
    expect(cancellation.cancel, returnsNormally);
    expect(notifications, 1);
    expect(
      () => cancellation.onCancel(() => throw StateError('private task text')),
      returnsNormally,
    );
  });

  test(
    'three formats send distinct headers and bodies and extract text',
    () async {
      final seen =
          <({String path, Map<String, String?> headers, Object? body})>[];
      final server = await _server((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        seen.add((
          path: request.uri.path,
          headers: <String, String?>{
            'authorization': request.headers.value('authorization'),
            'x-api-key': request.headers.value('x-api-key'),
            'anthropic-version': request.headers.value('anthropic-version'),
            'content-type': request.headers.value('content-type'),
          },
          body: body,
        ));
        final format = switch (request.uri.path) {
          '/v1/chat/completions' => AiEndpointFormat.openAiChatCompletions,
          '/v1/responses' => AiEndpointFormat.openAiResponses,
          _ => AiEndpointFormat.claudeMessages,
        };
        request.response.write(_responseFor(format));
        await request.response.close();
      });
      final client = _client();
      for (final format in AiEndpointFormat.values) {
        expect(await _generate(client, _endpoint(server, format)), 'Answer');
      }
      expect(seen.map((item) => item.path), <String>[
        '/v1/chat/completions',
        '/v1/responses',
        '/v1/messages',
      ]);
      for (final item in seen) {
        expect(item.headers['content-type'], startsWith('application/json'));
        final body = item.body as Map<String, dynamic>;
        expect(body['model'], 'local-test-model');
        expect(body['stream'], false);
        if (item.path == '/v1/messages') {
          expect(item.headers['authorization'], isNull);
          expect(item.headers['x-api-key'], _secret);
          expect(
            item.headers['anthropic-version'],
            AiProtocol.anthropicVersion,
          );
          expect(body['system'], 'Return test text.');
          expect(body['messages'][0]['content'], _context);
          expect(body['max_tokens'], 64);
        } else {
          expect(item.headers['authorization'], 'Bearer $_secret');
          expect(item.headers['x-api-key'], isNull);
          expect(item.headers['anthropic-version'], isNull);
          if (item.path == '/v1/responses') {
            expect(body['instructions'], 'Return test text.');
            expect(body['input'][0]['content'], _context);
            expect(body['max_output_tokens'], 64);
          } else {
            expect(body['messages'][0]['role'], 'system');
            expect(body['messages'][1]['content'], _context);
            expect(body['max_completion_tokens'], 64);
          }
        }
      }
    },
  );

  test('redirects never reach another server with credentials', () async {
    var destinationRequests = 0;
    var redirectStatus = HttpStatus.seeOther;
    final destination = await _server((request) async {
      destinationRequests++;
      await request.response.close();
    });
    final source = await _server((request) async {
      await request.drain<void>();
      request.response.statusCode = redirectStatus;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://127.0.0.1:${destination.port}/collect',
      );
      await request.response.close();
    });
    final client = _client();
    for (final entry in <(int, AiEndpointFormat)>[
      (HttpStatus.seeOther, AiEndpointFormat.openAiChatCompletions),
      (HttpStatus.temporaryRedirect, AiEndpointFormat.claudeMessages),
    ]) {
      redirectStatus = entry.$1;
      await _expectTransport(
        _generate(client, _endpoint(source, entry.$2)),
        AiTransportFailure.redirect,
      );
    }
    expect(destinationRequests, 0);
  });

  test('pre-cancel and request bytes reject before network', () async {
    var requests = 0;
    final server = await _server((request) async {
      requests++;
      await request.response.close();
    });
    final client = _client(maxRequestBytes: 128);
    final endpoint = _endpoint(server, AiEndpointFormat.openAiResponses);
    final cancellation = AiCancellation()..cancel();
    await _expectTransport(
      _generate(client, endpoint, cancellation: cancellation),
      AiTransportFailure.cancelled,
    );
    await _expectTransport(
      _generate(client, endpoint, userContext: '书' * 100),
      AiTransportFailure.requestTooLarge,
    );
    expect(requests, 0);
  });

  test('cancellation while waiting for headers drops late result', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final server = await _server((request) async {
      await request.drain<void>();
      received.complete();
      await release.future;
      request.response.write(_responseFor(AiEndpointFormat.openAiResponses));
      await request.response.close();
    });
    final client = _client();
    final cancellation = AiCancellation();
    cancellation.onCancel(() => throw StateError('private task text'));
    final operation = _generate(
      client,
      _endpoint(server, AiEndpointFormat.openAiResponses),
      cancellation: cancellation,
    );
    await _awaitSignal(received.future);
    cancellation.cancel();
    await _expectTransport(operation, AiTransportFailure.cancelled);
    release.complete();
  });

  test(
    'cancel and dispose during stream cleanup discard completed text',
    () async {
      final server = await _server((request) async {
        await request.drain<void>();
        request.response.write(_responseFor(AiEndpointFormat.openAiResponses));
        await request.response.close();
      });
      for (final disposeDuringCleanup in <bool>[false, true]) {
        final realClient = HttpClient();
        final entered = Completer<void>();
        final release = Completer<void>();
        final client = _client();
        final cancellation = AiCancellation();
        try {
          await HttpOverrides.runZoned(
            () async {
              final operation = _generate(
                client,
                _endpoint(server, AiEndpointFormat.openAiResponses),
                cancellation: cancellation,
              );
              await _awaitSignal(entered.future);
              if (disposeDuringCleanup) {
                client.dispose();
              } else {
                cancellation.cancel();
              }
              release.complete();
              await _expectTransport(
                operation,
                disposeDuringCleanup
                    ? AiTransportFailure.disposed
                    : AiTransportFailure.cancelled,
              );
            },
            createHttpClient: (_) =>
                _DelayedCancelClient(realClient, entered, release),
          );
        } finally {
          if (!release.isCompleted) release.complete();
          realClient.close(force: true);
        }
      }
    },
  );

  test('immediate cancellation interrupts connection setup', () async {
    final server = await _server((request) async {
      await request.response.close();
    });
    final client = _client();
    final cancellation = AiCancellation();
    final operation = _generate(
      client,
      _endpoint(server, AiEndpointFormat.openAiResponses),
      cancellation: cancellation,
    );
    cancellation.cancel();
    await _expectTransport(operation, AiTransportFailure.cancelled);
  });

  test('timeout while waiting for headers is classified', () async {
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final server = await _server((request) async {
      await request.drain<void>();
      await release.future;
      await request.response.close();
    });
    final client = _client(timeout: const Duration(milliseconds: 150));
    await _expectTransport(
      _generate(client, _endpoint(server, AiEndpointFormat.openAiResponses)),
      AiTransportFailure.timedOut,
    );
    release.complete();
  });

  test('whole-task timeout applies after response chunks arrive', () async {
    final firstChunk = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final server = await _server((request) async {
      await request.drain<void>();
      request.response.write('{"object":"response",');
      await request.response.flush();
      firstChunk.complete();
      await release.future;
      request.response.write('"status":"completed","output":[]}');
      await request.response.close();
    });
    final client = _client(timeout: const Duration(milliseconds: 150));
    final operation = _generate(
      client,
      _endpoint(server, AiEndpointFormat.openAiResponses),
    );
    await _awaitSignal(firstChunk.future);
    await _expectTransport(operation, AiTransportFailure.timedOut);
    release.complete();
  });

  test(
    'cancellation during stream read stops without returning text',
    () async {
      final firstChunk = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final server = await _server((request) async {
        await request.drain<void>();
        request.response.write('{"object":"chat.completion",');
        await request.response.flush();
        firstChunk.complete();
        await release.future;
        request.response.write(
          _responseFor(AiEndpointFormat.openAiChatCompletions),
        );
        await request.response.close();
      });
      final client = _client();
      final cancellation = AiCancellation();
      final operation = _generate(
        client,
        _endpoint(server, AiEndpointFormat.openAiChatCompletions),
        cancellation: cancellation,
      );
      await _awaitSignal(firstChunk.future);
      cancellation.cancel();
      await _expectTransport(operation, AiTransportFailure.cancelled);
      release.complete();
    },
  );

  test('chunked and gzip decoded bytes have the same response cap', () async {
    for (final gzipResponse in <bool>[false, true]) {
      final server = await _server((request) async {
        await request.drain<void>();
        final bytes = utf8.encode(
          _responseFor(AiEndpointFormat.openAiChatCompletions, 'x' * 2000),
        );
        if (gzipResponse) {
          request.response.headers.set(
            HttpHeaders.contentEncodingHeader,
            'gzip',
          );
          request.response.add(gzip.encode(bytes));
        } else {
          request.response.add(bytes);
        }
        await request.response.close();
      });
      final client = _client(maxResponseBytes: 256);
      await _expectTransport(
        _generate(
          client,
          _endpoint(server, AiEndpointFormat.openAiChatCompletions),
        ),
        AiTransportFailure.responseTooLarge,
      );
    }
  });

  test(
    'Content-Length rejects oversized response and UTF-8 is strict',
    () async {
      final server = await _server((request) async {
        await request.drain<void>();
        if (request.uri.path == '/v1/responses') {
          request.response.contentLength = 1024;
          request.response.write('x');
          await request.response.flush();
        } else {
          request.response.add(<int>[0xc3, 0x28]);
          await request.response.close();
        }
      });
      final client = _client(maxResponseBytes: 256);
      await _expectTransport(
        _generate(client, _endpoint(server, AiEndpointFormat.openAiResponses)),
        AiTransportFailure.responseTooLarge,
      );
      await _expectTransport(
        _generate(client, _endpoint(server, AiEndpointFormat.claudeMessages)),
        AiTransportFailure.invalidUtf8,
      );
    },
  );

  test('HTTP errors are classified without reading or echoing body', () async {
    var status = HttpStatus.unauthorized;
    final server = await _server((request) async {
      await request.drain<void>();
      request.response.statusCode = status;
      request.response.contentLength = 4096;
      request.response.write(_secret);
      await request.response.flush();
    });
    final client = _client(maxResponseBytes: 256);
    for (final entry in <(int, AiProtocolFailure)>[
      (HttpStatus.unauthorized, AiProtocolFailure.authentication),
      (HttpStatus.tooManyRequests, AiProtocolFailure.rateLimited),
      (HttpStatus.badRequest, AiProtocolFailure.httpError),
    ]) {
      status = entry.$1;
      await expectLater(
        _generate(client, _endpoint(server, AiEndpointFormat.openAiResponses)),
        throwsA(
          isA<AiProtocolException>()
              .having((error) => error.failure, 'failure', entry.$2)
              .having(
                (error) => error.toString(),
                'redacted',
                isNot(contains(_secret)),
              ),
        ),
      );
    }
  });

  test(
    'closed loopback endpoint reports a redacted connection failure',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(force: true);
      final endpoint = AiEndpoint.normalize(
        'http://127.0.0.1:$port',
        AiEndpointFormat.openAiResponses,
      );
      await _expectTransport(
        _generate(_client(), endpoint),
        AiTransportFailure.connection,
      );
    },
  );

  test('concurrent call rejects; dispose cancels and forbids reuse', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final server = await _server((request) async {
      await request.drain<void>();
      received.complete();
      await release.future;
      request.response.write(_responseFor(AiEndpointFormat.openAiResponses));
      await request.response.close();
    });
    final client = _client();
    final endpoint = _endpoint(server, AiEndpointFormat.openAiResponses);
    final first = _generate(client, endpoint);
    await _awaitSignal(received.future);
    await _expectTransport(
      _generate(client, endpoint),
      AiTransportFailure.concurrentRequest,
    );
    client.dispose();
    await _expectTransport(first, AiTransportFailure.disposed);
    await _expectTransport(
      _generate(client, endpoint),
      AiTransportFailure.disposed,
    );
    release.complete();
  });
}
