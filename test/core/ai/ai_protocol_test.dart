import 'dart:convert';

import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

AiProtocolRequest request(AiEndpointFormat format) => AiProtocol.buildRequest(
  format: format,
  apiKey: 'test-secret',
  model: 'test-model',
  systemPrompt: 'Follow the task.',
  userContext: 'Chapter context.',
  outputTokens: 512,
);

String extract(AiEndpointFormat format, Object body, {int statusCode = 200}) =>
    AiProtocol.extractText(
      format: format,
      statusCode: statusCode,
      responseBody: jsonEncode(body),
    );

void expectFailure(
  AiEndpointFormat format,
  Object body,
  AiProtocolFailure failure, {
  int statusCode = 200,
}) {
  expect(
    () => extract(format, body, statusCode: statusCode),
    throwsA(
      isA<AiProtocolException>().having(
        (error) => error.failure,
        'failure',
        failure,
      ),
    ),
  );
}

Map<String, Object?> chatResponse({
  Object? content = 'Answer',
  Object? refusal,
  String? finishReason = 'stop',
}) => <String, Object?>{
  'object': 'chat.completion',
  'choices': <Object?>[
    <String, Object?>{
      'finish_reason': finishReason,
      'message': <String, Object?>{
        'role': 'assistant',
        'content': content,
        'refusal': refusal,
      },
    },
  ],
};

Map<String, Object?> responsesResponse({
  String status = 'completed',
  Object? incompleteDetails,
  List<Object?>? output,
}) => <String, Object?>{
  'object': 'response',
  'status': status,
  'error': null,
  'incomplete_details': incompleteDetails,
  'output':
      output ??
      <Object?>[
        <String, Object?>{
          'type': 'message',
          'role': 'assistant',
          'status': 'completed',
          'content': <Object?>[
            <String, Object?>{'type': 'output_text', 'text': 'Answer'},
          ],
        },
      ],
};

Map<String, Object?> claudeResponse({
  String? stopReason = 'end_turn',
  Object? stopDetails,
  List<Object?>? content,
}) => <String, Object?>{
  'type': 'message',
  'role': 'assistant',
  'stop_reason': stopReason,
  'stop_details': stopDetails,
  'content':
      content ??
      <Object?>[
        <String, Object?>{'type': 'text', 'text': 'Answer'},
      ],
};

void main() {
  test('Chat request keeps system and user separate with Bearer only', () {
    final built = request(AiEndpointFormat.openAiChatCompletions);
    expect(built.headers, <String, String>{
      'content-type': 'application/json',
      'authorization': 'Bearer test-secret',
    });
    expect(built.body, <String, Object?>{
      'model': 'test-model',
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': 'Follow the task.'},
        <String, String>{'role': 'user', 'content': 'Chapter context.'},
      ],
      'max_completion_tokens': 512,
      'stream': false,
      'store': false,
    });
  });

  test('Responses request uses instructions, input and Bearer only', () {
    final built = request(AiEndpointFormat.openAiResponses);
    expect(
      built.headers.keys,
      containsAll(<String>['content-type', 'authorization']),
    );
    expect(built.headers, isNot(contains('x-api-key')));
    expect(built.body, <String, Object?>{
      'model': 'test-model',
      'instructions': 'Follow the task.',
      'input': <Map<String, String>>[
        <String, String>{'role': 'user', 'content': 'Chapter context.'},
      ],
      'max_output_tokens': 512,
      'stream': false,
      'store': false,
    });
  });

  test('Claude request fixes version and uses x-api-key only', () {
    final built = request(AiEndpointFormat.claudeMessages);
    expect(AiProtocol.anthropicVersion, '2023-06-01');
    expect(built.headers, <String, String>{
      'content-type': 'application/json',
      'x-api-key': 'test-secret',
      'anthropic-version': '2023-06-01',
    });
    expect(built.headers, isNot(contains('authorization')));
    expect(built.body, <String, Object?>{
      'model': 'test-model',
      'system': 'Follow the task.',
      'messages': <Map<String, String>>[
        <String, String>{'role': 'user', 'content': 'Chapter context.'},
      ],
      'max_tokens': 512,
      'stream': false,
    });
  });

  test('request headers and nested messages are immutable snapshots', () {
    for (final format in AiEndpointFormat.values) {
      final built = request(format);
      expect(() => built.headers['x-extra'] = 'value', throwsUnsupportedError);
      expect(() => built.body['model'] = 'changed', throwsUnsupportedError);
      final key = format == AiEndpointFormat.openAiResponses
          ? 'input'
          : 'messages';
      final messages = built.body[key] as List<Map<String, String>>;
      expect(() => messages.add(<String, String>{}), throwsUnsupportedError);
      expect(
        () => messages.first['content'] = 'changed',
        throwsUnsupportedError,
      );
    }
  });

  test('request rejects unbounded and header-unsafe inputs without echo', () {
    for (final context in <String>[
      '',
      'x' * (AiProtocol.maxUserCharacters + 1),
    ]) {
      expect(
        () => AiProtocol.buildRequest(
          format: AiEndpointFormat.openAiChatCompletions,
          apiKey: 'test-secret',
          model: 'model',
          systemPrompt: 'Task',
          userContext: context,
          outputTokens: 512,
        ),
        throwsA(isA<AiProtocolException>()),
      );
    }
    for (final outputTokens in <int>[0, 15, AiProtocol.maxOutputTokens + 1]) {
      expect(
        () => AiProtocol.buildRequest(
          format: AiEndpointFormat.claudeMessages,
          apiKey: 'test-secret',
          model: 'model',
          systemPrompt: 'Task',
          userContext: 'Context',
          outputTokens: outputTokens,
        ),
        throwsA(isA<AiProtocolException>()),
      );
    }
    try {
      AiProtocol.buildRequest(
        format: AiEndpointFormat.openAiResponses,
        apiKey: 'test-secret\r\nx-extra: leaked',
        model: 'model',
        systemPrompt: 'Task',
        userContext: 'Context',
        outputTokens: 512,
      );
      fail('Expected an invalid request');
    } on AiProtocolException catch (error) {
      expect(error.failure, AiProtocolFailure.invalidRequest);
      expect(error.toString(), isNot(contains('test-secret')));
    }
  });

  test('Chat extracts completed assistant text only', () {
    const format = AiEndpointFormat.openAiChatCompletions;
    expect(extract(format, chatResponse()), 'Answer');
    expectFailure(
      format,
      chatResponse(content: ''),
      AiProtocolFailure.emptyResponse,
    );
    expectFailure(
      format,
      chatResponse(content: null),
      AiProtocolFailure.malformedResponse,
    );
    expectFailure(
      format,
      chatResponse(refusal: 'Private refusal text'),
      AiProtocolFailure.refused,
    );
    expectFailure(
      format,
      chatResponse(finishReason: 'length'),
      AiProtocolFailure.incomplete,
    );
    expectFailure(
      format,
      chatResponse(finishReason: 'content_filter'),
      AiProtocolFailure.refused,
    );
    expectFailure(
      format,
      chatResponse(finishReason: 'tool_calls'),
      AiProtocolFailure.incomplete,
    );
    expectFailure(format, <String, Object?>{
      'object': 'chat.completion.chunk',
      'choices': [],
    }, AiProtocolFailure.malformedResponse);
    expectFailure(format, <String, Object?>{
      'object': 'chat.completion',
      'choices': [],
    }, AiProtocolFailure.malformedResponse);
    expectFailure(
      format,
      chatResponse(
        content: <Object?>[
          <String, String>{'type': 'text', 'text': 'X'},
        ],
      ),
      AiProtocolFailure.malformedResponse,
    );
  });

  test('Responses joins completed text blocks and ignores reasoning', () {
    const format = AiEndpointFormat.openAiResponses;
    final body = responsesResponse(
      output: <Object?>[
        <String, Object?>{'type': 'reasoning', 'summary': []},
        <String, Object?>{
          'type': 'message',
          'role': 'assistant',
          'status': 'completed',
          'content': <Object?>[
            <String, Object?>{'type': 'output_text', 'text': 'First '},
            <String, Object?>{'type': 'output_text', 'text': 'second'},
          ],
        },
      ],
    );
    expect(extract(format, body), 'First second');
    expectFailure(
      format,
      responsesResponse(status: 'incomplete'),
      AiProtocolFailure.incomplete,
    );
    expectFailure(
      format,
      responsesResponse(
        incompleteDetails: <String, String>{'reason': 'max_output_tokens'},
      ),
      AiProtocolFailure.incomplete,
    );
    expectFailure(
      format,
      responsesResponse(output: <Object?>[]),
      AiProtocolFailure.emptyResponse,
    );
    expectFailure(
      format,
      responsesResponse(
        output: <Object?>[
          <String, Object?>{
            'type': 'message',
            'role': 'assistant',
            'status': 'completed',
            'content': <Object?>[
              <String, Object?>{
                'type': 'refusal',
                'refusal': 'Private refusal',
              },
            ],
          },
        ],
      ),
      AiProtocolFailure.refused,
    );
    expectFailure(
      format,
      responsesResponse(
        output: <Object?>[
          <String, Object?>{
            'type': 'message',
            'role': 'assistant',
            'status': 'in_progress',
            'content': <Object?>[
              <String, Object?>{'type': 'output_text', 'text': 'Partial'},
            ],
          },
        ],
      ),
      AiProtocolFailure.incomplete,
    );
    expectFailure(
      format,
      responsesResponse(
        output: <Object?>[
          <String, String>{'type': 'function_call'},
        ],
      ),
      AiProtocolFailure.malformedResponse,
    );
    expectFailure(
      format,
      responsesResponse(
        output: <Object?>[
          <String, Object?>{
            'type': 'message',
            'role': 'assistant',
            'status': 'completed',
            'content': <Object?>[
              <String, Object?>{'type': 'output_audio', 'data': 'Private'},
            ],
          },
        ],
      ),
      AiProtocolFailure.malformedResponse,
    );
    expectFailure(format, <String, Object?>{
      'output_text': 'SDK helper is not a raw HTTP contract',
    }, AiProtocolFailure.malformedResponse);
  });

  test('Claude joins text blocks without non-text content', () {
    const format = AiEndpointFormat.claudeMessages;
    expect(
      extract(
        format,
        claudeResponse(
          content: <Object?>[
            <String, Object?>{'type': 'thinking', 'thinking': 'Private'},
            <String, Object?>{'type': 'text', 'text': 'First '},
            <String, Object?>{'type': 'text', 'text': 'second'},
          ],
        ),
      ),
      'First second',
    );
    expectFailure(
      format,
      claudeResponse(
        content: <Object?>[
          <String, String>{'type': 'thinking'},
        ],
      ),
      AiProtocolFailure.emptyResponse,
    );
    expectFailure(
      format,
      claudeResponse(stopReason: 'max_tokens'),
      AiProtocolFailure.incomplete,
    );
    expectFailure(
      format,
      claudeResponse(stopReason: 'pause_turn'),
      AiProtocolFailure.incomplete,
    );
    expectFailure(
      format,
      claudeResponse(stopReason: 'model_context_window_exceeded'),
      AiProtocolFailure.incomplete,
    );
    expectFailure(
      format,
      claudeResponse(stopReason: 'refusal'),
      AiProtocolFailure.refused,
    );
    expectFailure(
      format,
      claudeResponse(stopDetails: <String, String>{'type': 'refusal'}),
      AiProtocolFailure.refused,
    );
    expectFailure(
      format,
      claudeResponse(
        content: <Object?>[
          <String, Object?>{'type': 'text', 'text': 'Partial'},
          <String, Object?>{'type': 'tool_use'},
        ],
      ),
      AiProtocolFailure.incomplete,
    );
    expectFailure(
      format,
      claudeResponse(
        content: <Object?>[
          <String, Object?>{'type': 'text'},
        ],
      ),
      AiProtocolFailure.malformedResponse,
    );
  });

  test(
    'all formats reject HTTP failures, error bodies and oversized output',
    () {
      for (final format in AiEndpointFormat.values) {
        expectFailure(
          format,
          <String, Object?>{
            'error': <String, String>{'message': 'Private text'},
          },
          AiProtocolFailure.authentication,
          statusCode: 401,
        );
        expectFailure(
          format,
          <String, Object?>{
            'error': <String, String>{'message': 'Private text'},
          },
          AiProtocolFailure.rateLimited,
          statusCode: 429,
        );
        expectFailure(format, <String, Object?>{
          'error': <String, String>{'message': 'Private text'},
        }, AiProtocolFailure.httpError);
        expectFailure(
          format,
          <String, Object?>{},
          AiProtocolFailure.httpError,
          statusCode: 500,
        );
        expect(
          () => AiProtocol.extractText(
            format: format,
            statusCode: 200,
            responseBody: '{"secret":"Private text"',
          ),
          throwsA(isA<AiProtocolException>()),
        );
        expect(
          () => AiProtocol.extractText(
            format: format,
            statusCode: 200,
            responseBody: 'x' * (AiProtocol.maxResponseCharacters + 1),
          ),
          throwsA(
            isA<AiProtocolException>().having(
              (error) => error.failure,
              'failure',
              AiProtocolFailure.responseTooLarge,
            ),
          ),
        );
      }
      expectFailure(
        AiEndpointFormat.openAiChatCompletions,
        chatResponse(content: 'x' * (AiProtocol.maxTextCharacters + 1)),
        AiProtocolFailure.responseTooLarge,
      );
    },
  );

  test('exceptions never echo request or response secrets', () {
    const secret = 'PRIVATE_BOOK_AND_KEY_CONTENT';
    for (final format in AiEndpointFormat.values) {
      try {
        extract(format, <String, Object?>{
          'error': <String, String>{'message': secret},
        });
        fail('Expected a protocol failure');
      } on AiProtocolException catch (error) {
        expect(error.toString(), isNot(contains(secret)));
      }
    }
  });

  test('a response from another protocol is rejected', () {
    expectFailure(
      AiEndpointFormat.openAiChatCompletions,
      responsesResponse(),
      AiProtocolFailure.malformedResponse,
    );
    expectFailure(
      AiEndpointFormat.openAiResponses,
      claudeResponse(),
      AiProtocolFailure.malformedResponse,
    );
    expectFailure(
      AiEndpointFormat.claudeMessages,
      chatResponse(),
      AiProtocolFailure.malformedResponse,
    );
  });
}
