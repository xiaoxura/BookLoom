import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to disabled without an endpoint or credential', () {
    const configuration = AiConfiguration();
    expect(configuration.enabled, isFalse);
    expect(configuration.address, isEmpty);
    expect(configuration.credentialReference, isNull);
    expect(configuration.canonicalized(), configuration);
  });

  test('canonicalizes the three protocol bases and keeps only metadata', () {
    final cases = <(AiEndpointFormat, String, String)>[
      (
        AiEndpointFormat.openAiChatCompletions,
        ' https://api.example.com/v1/chat/completions ',
        'https://api.example.com/v1',
      ),
      (
        AiEndpointFormat.openAiResponses,
        'https://api.example.com/v1/v1/responses',
        'https://api.example.com/v1',
      ),
      (
        AiEndpointFormat.claudeMessages,
        'https://api.example.com/v1/messages',
        'https://api.example.com',
      ),
    ];
    for (final (format, input, base) in cases) {
      final configuration = AiConfiguration(
        enabled: true,
        format: format,
        address: input,
        model: '  small-model  ',
        credentialReference: 'ai_reference',
      ).canonicalized();
      expect(configuration.address, base);
      expect(configuration.model, 'small-model');
      expect(AiConfiguration.fromJson(configuration.toJson()), configuration);
      expect(configuration.toJson().keys, isNot(contains('apiKey')));
      expect(configuration.toJson().keys, isNot(contains('hash')));
    }
  });

  test('validates fields without revealing their values', () {
    expect(
      () => const AiConfiguration(enabled: true).canonicalized(),
      throwsFormatException,
    );
    expect(
      () =>
          const AiConfiguration(address: 'https://user:secret@api.example.com')
              .canonicalized(),
      throwsFormatException,
    );
    expect(
      () => AiConfiguration(model: 'x' * 201).canonicalized(),
      throwsFormatException,
    );
    expect(
      () =>
          AiConfiguration(address: 'https://api.example.com/${'a' * 2048}')
              .canonicalized(),
      throwsFormatException,
    );
    expect(
      () => AiConfiguration.fromJson(<String, Object?>{
        'enabled': 'yes',
        'format': 'invalid',
      }),
      throwsFormatException,
    );
  });
}
