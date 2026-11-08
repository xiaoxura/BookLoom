import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chat = AiEndpointFormat.openAiChatCompletions;
  const responses = AiEndpointFormat.openAiResponses;
  const claude = AiEndpointFormat.claudeMessages;

  test('normalizes each format, full endpoints, prefixes, and ports', () {
    final cases =
        <
          ({AiEndpointFormat format, String input, String base, String request})
        >[
          (
            format: chat,
            input: 'https://api.example.com',
            base: 'https://api.example.com/v1',
            request: 'https://api.example.com/v1/chat/completions',
          ),
          (
            format: chat,
            input: ' https://api.example.com/v1/ ',
            base: 'https://api.example.com/v1',
            request: 'https://api.example.com/v1/chat/completions',
          ),
          (
            format: chat,
            input: 'https://api.example.com/v1/v1//',
            base: 'https://api.example.com/v1',
            request: 'https://api.example.com/v1/chat/completions',
          ),
          (
            format: chat,
            input: 'https://api.example.com/proxy/v1/chat/completions',
            base: 'https://api.example.com/proxy/v1',
            request: 'https://api.example.com/proxy/v1/chat/completions',
          ),
          (
            format: chat,
            input: 'https://api.example.com:8443/proxy/chat/completions/',
            base: 'https://api.example.com:8443/proxy/v1',
            request: 'https://api.example.com:8443/proxy/v1/chat/completions',
          ),
          (
            format: responses,
            input: 'https://api.example.com/v1/v1/',
            base: 'https://api.example.com/v1',
            request: 'https://api.example.com/v1/responses',
          ),
          (
            format: responses,
            input: 'https://api.example.com/proxy/responses',
            base: 'https://api.example.com/proxy/v1',
            request: 'https://api.example.com/proxy/v1/responses',
          ),
          (
            format: responses,
            input: 'https://api.example.com:9443/proxy/v1/responses',
            base: 'https://api.example.com:9443/proxy/v1',
            request: 'https://api.example.com:9443/proxy/v1/responses',
          ),
          (
            format: claude,
            input: 'https://api.example.com',
            base: 'https://api.example.com',
            request: 'https://api.example.com/v1/messages',
          ),
          (
            format: claude,
            input: 'https://api.example.com/proxy/v1/v1/',
            base: 'https://api.example.com/proxy',
            request: 'https://api.example.com/proxy/v1/messages',
          ),
          (
            format: claude,
            input: 'https://api.example.com:7443/proxy/v1/messages',
            base: 'https://api.example.com:7443/proxy',
            request: 'https://api.example.com:7443/proxy/v1/messages',
          ),
          (
            format: claude,
            input: 'https://api.example.com/proxy/messages',
            base: 'https://api.example.com/proxy',
            request: 'https://api.example.com/proxy/v1/messages',
          ),
          (
            format: chat,
            input: 'https://api.example.com/myv1proxy',
            base: 'https://api.example.com/myv1proxy/v1',
            request: 'https://api.example.com/myv1proxy/v1/chat/completions',
          ),
          (
            format: responses,
            input: 'https://api.example.com/proxy%20name/v1',
            base: 'https://api.example.com/proxy%20name/v1',
            request: 'https://api.example.com/proxy%20name/v1/responses',
          ),
          (
            format: claude,
            input: 'https://api.example.com/%E4%B8%AD%E6%96%87%3Aproxy/v1',
            base: 'https://api.example.com/%E4%B8%AD%E6%96%87%3Aproxy',
            request: 'https://api.example.com/%E4%B8%AD%E6%96%87%3Aproxy/v1/messages',
          ),
        ];
    for (final entry in cases) {
      final result = AiEndpoint.normalize(entry.input, entry.format);
      expect(result.baseUri.toString(), entry.base, reason: entry.input);
      expect(result.requestUri.toString(), entry.request, reason: entry.input);
      expect(result.isInsecureRemoteHttp, isFalse, reason: entry.input);
      final repeated = AiEndpoint.normalize(
        result.baseUri.toString(),
        entry.format,
      );
      expect(repeated.baseUri, result.baseUri, reason: entry.input);
      expect(repeated.requestUri, result.requestUri, reason: entry.input);
      expect(
        AiEndpoint.normalize(
          result.requestUri.toString(),
          entry.format,
        ).requestUri,
        result.requestUri,
        reason: entry.input,
      );
    }
  });

  test(
    'permits only loopback HTTP without explicit remote acknowledgement',
    () {
      for (final address in [
        'http://localhost:8080/proxy',
        'http://127.0.0.1:8080',
        'http://[::1]:8080',
      ]) {
        final result = AiEndpoint.normalize(address, chat);
        expect(result.requestUri.scheme, 'http');
        expect(result.isInsecureRemoteHttp, isFalse);
      }
      const remote = 'http://api.example.com:8080/proxy';
      expect(
        () => AiEndpoint.normalize(remote, responses),
        throwsFormatException,
      );
      final acknowledged = AiEndpoint.normalize(
        remote,
        responses,
        acknowledgeRemoteHttp: true,
      );
      expect(acknowledged.isInsecureRemoteHttp, isTrue);
      expect(
        acknowledged.requestUri.toString(),
        'http://api.example.com:8080/proxy/v1/responses',
      );
    },
  );

  test('rejects endpoints belonging to a different selected format', () {
    final cases = <({AiEndpointFormat format, String input})>[
      (format: chat, input: 'https://api.example.com/v1/responses'),
      (format: chat, input: 'https://api.example.com/messages'),
      (format: responses, input: 'https://api.example.com/v1/chat/completions'),
      (format: responses, input: 'https://api.example.com/v1/messages'),
      (format: claude, input: 'https://api.example.com/chat/completions'),
      (format: claude, input: 'https://api.example.com/v1/responses'),
    ];
    for (final entry in cases) {
      expect(
        () => AiEndpoint.normalize(entry.input, entry.format),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('格式不一致'),
          ),
        ),
        reason: entry.input,
      );
    }
  });

  test('rejects unsafe syntax before URI normalization can hide it', () {
    for (final address in [
      'api.example.com/v1',
      'ftp://api.example.com/v1',
      'https:///v1',
      'https://user:secret@api.example.com/v1',
      'https://@api.example.com/v1',
      'https://api.example.com/v1?key=secret',
      'https://api.example.com/v1?',
      'https://api.example.com/v1#fragment',
      'https://api.example.com/v1#',
      'https://api.example.com:0/v1',
      'https://api.example.com:65536/v1',
      'https://api.example.com:/v1',
      'https://api.example.com/proxy/../v1',
      'https://api.example.com/proxy/./v1',
      'https://api.example.com/proxy//v1',
      'https://api.example.com/proxy/%2e%2e/v1',
      'https://api.example.com/proxy/%2F/v1',
      r'https://api.example.com/proxy\v1',
      'https://api.example.com/proxy/%5c/v1',
      'https://api.example.com/proxy/%2576%2531',
      'https://api.example.com/proxy%00/v1',
      'https://api.example.com/proxy%0A/v1',
      'https://api.example.com/proxy%7f/v1',
      'https://api.example.com/proxy%C2%80/v1',
      'https://api.example.com/proxy/%76%31',
      'https://api.example.com/v%31',
      'https://api.example.com/proxy/%',
      'https://api.example.com/v10',
      'https://api.example.com/v1beta',
      'https://api.example.com/V1',
      'https://api.example.com/v2/proxy',
    ]) {
      expect(
        () => AiEndpoint.normalize(address, chat),
        throwsFormatException,
        reason: address,
      );
    }
  });
}
