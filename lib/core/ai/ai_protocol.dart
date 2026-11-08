import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_json.dart';

enum AiProtocolFailure {
  invalidRequest,
  httpError,
  authentication,
  rateLimited,
  malformedResponse,
  refused,
  incomplete,
  emptyResponse,
  responseTooLarge,
}

class AiProtocolException implements Exception {
  const AiProtocolException(this.failure);

  final AiProtocolFailure failure;

  @override
  String toString() => 'AiProtocolException: ${failure.name}';
}

class AiProtocolRequest {
  AiProtocolRequest({
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) : headers = Map<String, String>.unmodifiable(headers),
       body = Map<String, Object?>.unmodifiable(body);

  final Map<String, String> headers;
  final Map<String, Object?> body;
}

abstract final class AiProtocol {
  static const anthropicVersion = '2023-06-01';
  static const maxSystemCharacters = 8192;
  static const maxUserCharacters = 65536;
  static const maxResponseCharacters = 524288;
  static const maxTextCharacters = 32768;
  static const maxOutputTokens = 8192;

  static AiProtocolRequest buildRequest({
    required AiEndpointFormat format,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
  }) {
    if (apiKey.isEmpty ||
        apiKey.length > 4096 ||
        apiKey.trim() != apiKey ||
        _hasControl(apiKey) ||
        model.trim().isEmpty ||
        model.length > 200 ||
        model.trim() != model ||
        _hasControl(model) ||
        systemPrompt.trim().isEmpty ||
        systemPrompt.length > maxSystemCharacters ||
        userContext.trim().isEmpty ||
        userContext.length > maxUserCharacters ||
        outputTokens < 16 ||
        outputTokens > maxOutputTokens) {
      throw const AiProtocolException(AiProtocolFailure.invalidRequest);
    }

    final headers = <String, String>{'content-type': 'application/json'};
    final Map<String, Object?> body;
    switch (format) {
      case AiEndpointFormat.openAiChatCompletions:
        headers['authorization'] = 'Bearer $apiKey';
        body = <String, Object?>{
          'model': model,
          'messages': List<Map<String, String>>.unmodifiable(
            <Map<String, String>>[
              _message('system', systemPrompt),
              _message('user', userContext),
            ],
          ),
          'max_completion_tokens': outputTokens,
          'stream': false,
          'store': false,
        };
      case AiEndpointFormat.openAiResponses:
        headers['authorization'] = 'Bearer $apiKey';
        body = <String, Object?>{
          'model': model,
          'instructions': systemPrompt,
          'input': List<Map<String, String>>.unmodifiable(<Map<String, String>>[
            _message('user', userContext),
          ]),
          'max_output_tokens': outputTokens,
          'stream': false,
          'store': false,
        };
      case AiEndpointFormat.claudeMessages:
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = anthropicVersion;
        body = <String, Object?>{
          'model': model,
          'system': systemPrompt,
          'messages': List<Map<String, String>>.unmodifiable(
            <Map<String, String>>[_message('user', userContext)],
          ),
          'max_tokens': outputTokens,
          'stream': false,
        };
    }
    return AiProtocolRequest(headers: headers, body: body);
  }

  /// Returns untrusted protocol text only; callers must validate proposals locally.
  static String extractText({
    required AiEndpointFormat format,
    required int statusCode,
    required String responseBody,
  }) {
    if (responseBody.length > maxResponseCharacters) {
      throw const AiProtocolException(AiProtocolFailure.responseTooLarge);
    }
    if (statusCode == 401 || statusCode == 403) {
      throw const AiProtocolException(AiProtocolFailure.authentication);
    }
    if (statusCode == 429) {
      throw const AiProtocolException(AiProtocolFailure.rateLimited);
    }
    if (statusCode != 200) {
      throw const AiProtocolException(AiProtocolFailure.httpError);
    }

    final Object? decoded;
    try {
      decoded = decodeStrictAiJson(responseBody);
    } on FormatException {
      throw const AiProtocolException(AiProtocolFailure.malformedResponse);
    }
    final root = _object(decoded);
    if (root['error'] != null) {
      throw const AiProtocolException(AiProtocolFailure.httpError);
    }

    final text = switch (format) {
      AiEndpointFormat.openAiChatCompletions => _extractChat(root),
      AiEndpointFormat.openAiResponses => _extractResponses(root),
      AiEndpointFormat.claudeMessages => _extractClaude(root),
    };
    if (text.trim().isEmpty) {
      throw const AiProtocolException(AiProtocolFailure.emptyResponse);
    }
    return text;
  }

  static String _extractChat(Map<String, dynamic> root) {
    if (root['object'] != 'chat.completion') _malformed();
    final choices = _list(root['choices']);
    if (choices.length != 1) _malformed();
    final choice = _object(choices.single);
    if (choice['finish_reason'] == 'content_filter') _refused();
    if (choice['finish_reason'] != 'stop') _incomplete();
    final message = _object(choice['message']);
    if (message['role'] != 'assistant') _malformed();
    if (message['refusal'] != null) _refused();
    final content = message['content'];
    if (content is! String) _malformed();
    _checkTextLength(content);
    return content;
  }

  static String _extractResponses(Map<String, dynamic> root) {
    if (root['object'] != 'response') _malformed();
    if (root['status'] != 'completed' || root['incomplete_details'] != null) {
      _incomplete();
    }
    final output = _list(root['output']);
    final text = StringBuffer();
    for (final itemValue in output) {
      final item = _object(itemValue);
      if (item['type'] == 'reasoning') continue;
      if (item['type'] != 'message') _malformed();
      if (item['role'] != 'assistant' || item['status'] != 'completed') {
        _incomplete();
      }
      for (final partValue in _list(item['content'])) {
        final part = _object(partValue);
        if (part['type'] == 'refusal') _refused();
        if (part['type'] != 'output_text' || part['text'] is! String) {
          _malformed();
        }
        _appendText(text, part['text'] as String);
      }
    }
    return text.toString();
  }

  static String _extractClaude(Map<String, dynamic> root) {
    if (root['type'] != 'message' || root['role'] != 'assistant') {
      _malformed();
    }
    if (root['stop_reason'] == 'refusal' ||
        _optionalObject(root['stop_details'])?['type'] == 'refusal') {
      _refused();
    }
    if (root['stop_reason'] != 'end_turn') _incomplete();
    final text = StringBuffer();
    for (final partValue in _list(root['content'])) {
      final part = _object(partValue);
      if (part['type'] == 'tool_use') _incomplete();
      if (part['type'] != 'text') continue;
      final value = part['text'];
      if (value is! String) _malformed();
      _appendText(text, value);
    }
    return text.toString();
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is Map<String, dynamic>) return value;
    _malformed();
  }

  static Map<String, dynamic>? _optionalObject(Object? value) =>
      value == null ? null : _object(value);

  static List<dynamic> _list(Object? value) {
    if (value is List<dynamic>) return value;
    _malformed();
  }

  static void _appendText(StringBuffer buffer, String value) {
    if (buffer.length + value.length > maxTextCharacters) {
      throw const AiProtocolException(AiProtocolFailure.responseTooLarge);
    }
    buffer.write(value);
  }

  static void _checkTextLength(String value) {
    if (value.length > maxTextCharacters) {
      throw const AiProtocolException(AiProtocolFailure.responseTooLarge);
    }
  }

  static bool _hasControl(String value) {
    for (final code in value.codeUnits) {
      if (code < 32 || code == 127) return true;
    }
    return false;
  }

  static Map<String, String> _message(String role, String content) =>
      Map<String, String>.unmodifiable(<String, String>{
        'role': role,
        'content': content,
      });

  static Never _malformed() =>
      throw const AiProtocolException(AiProtocolFailure.malformedResponse);
  static Never _refused() =>
      throw const AiProtocolException(AiProtocolFailure.refused);
  static Never _incomplete() =>
      throw const AiProtocolException(AiProtocolFailure.incomplete);
}
