import 'dart:async';
import 'dart:convert';

import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_proofreading_prompt.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/core/errors/app_failure.dart';

import 'proofreading_quality.dart';

const int liveMaxApiKeyCharacters = 4096;
const int liveMaxModelCharacters = 200;
const int liveMaxCasesCeiling = 64;
const Duration liveMinTimeout = Duration(seconds: 5);
const Duration liveMaxTimeout = Duration(minutes: 5);
const int liveOutputTokens = 4096;

/// An invalid response placeholder keeps skipped or failed cases out of the
/// false-negative count: the evaluator marks them invalid instead of pretending
/// the provider returned an empty answer.
const String liveInvalidResponse = '{';

final class LiveProviderOptions {
  LiveProviderOptions._({
    required this.endpoint,
    required this.model,
    required this.apiKey,
    required this.keyEnvironment,
    required this.maxCases,
    required this.timeout,
  });

  final AiEndpoint endpoint;
  final String model;
  final String apiKey;
  final String keyEnvironment;
  final int maxCases;
  final Duration timeout;

  String get formatName => switch (endpoint.format) {
    AiEndpointFormat.openAiChatCompletions => 'chat',
    AiEndpointFormat.openAiResponses => 'responses',
    AiEndpointFormat.claudeMessages => 'claude',
  };
}

final class QualityCliOptions {
  QualityCliOptions._({
    required this.strict,
    required this.responsesPath,
    required this.outputPath,
    required this.markdownPath,
    required this.corpusPath,
    required this.allowExternal,
    required this.sendExternal,
    required this.live,
  });

  final bool strict;
  final String? responsesPath;
  final String? outputPath;
  final String? markdownPath;
  final String? corpusPath;
  final bool allowExternal;
  final bool sendExternal;
  final LiveProviderOptions? live;

  /// Parses the developer CLI. Configuration errors never include the key.
  static QualityCliOptions parse(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    var strict = false;
    var live = false;
    var allowExternal = false;
    var sendExternal = false;
    String? responsesPath;
    String? outputPath;
    String? markdownPath;
    String? corpusPath;
    String? format;
    String? baseUrl;
    String? model;
    String? keyEnvironment;
    String? maxCases;
    String? timeout;
    for (final argument in arguments) {
      if (argument == '--strict' && !strict) {
        strict = true;
      } else if (argument == '--live' && !live) {
        live = true;
      } else if (argument.startsWith('--responses=') && responsesPath == null) {
        responsesPath = argument.substring('--responses='.length);
      } else if (argument.startsWith('--output=') && outputPath == null) {
        outputPath = argument.substring('--output='.length);
      } else if (argument.startsWith('--markdown=') && markdownPath == null) {
        markdownPath = argument.substring('--markdown='.length);
      } else if (argument.startsWith('--corpus=') && corpusPath == null) {
        corpusPath = argument.substring('--corpus='.length);
      } else if (argument == '--allow-external' && !allowExternal) {
        allowExternal = true;
      } else if (argument == '--send-external' && !sendExternal) {
        sendExternal = true;
      } else if (argument.startsWith('--format=') && format == null) {
        format = argument.substring('--format='.length);
      } else if (argument.startsWith('--base-url=') && baseUrl == null) {
        baseUrl = argument.substring('--base-url='.length);
      } else if (argument.startsWith('--model=') && model == null) {
        model = argument.substring('--model='.length);
      } else if (argument.startsWith('--key-env=') && keyEnvironment == null) {
        keyEnvironment = argument.substring('--key-env='.length);
      } else if (argument.startsWith('--max-cases=') && maxCases == null) {
        maxCases = argument.substring('--max-cases='.length);
      } else if (argument.startsWith('--timeout=') && timeout == null) {
        timeout = argument.substring('--timeout='.length);
      } else {
        throw const FormatException(
          'usage: dart run tool/proofreading_quality.dart '
          '[--corpus=FILE] [--responses=FILE] [--output=FILE] [--markdown=FILE] '
          '[--strict] '
          'or --live --format=chat|responses|claude --base-url=URL '
          '--model=MODEL --key-env=ENV [--max-cases=N] [--timeout=SECONDS] '
          '[--allow-external] [--send-external]',
        );
      }
    }
    if (responsesPath == '' ||
        outputPath == '' ||
        markdownPath == '' ||
        corpusPath == '') {
      throw const FormatException('file path cannot be empty');
    }
    if (allowExternal && corpusPath == null) {
      throw const FormatException('--allow-external requires --corpus');
    }
    if (sendExternal && (corpusPath == null || !live)) {
      throw const FormatException(
        '--send-external requires --live and --corpus',
      );
    }
    if (!live) {
      if ([
        format,
        baseUrl,
        model,
        keyEnvironment,
        maxCases,
        timeout,
      ].any((value) => value != null)) {
        throw const FormatException('live options require --live');
      }
      return QualityCliOptions._(
        strict: strict,
        responsesPath: responsesPath,
        outputPath: outputPath,
        markdownPath: markdownPath,
        corpusPath: corpusPath,
        allowExternal: allowExternal,
        sendExternal: sendExternal,
        live: null,
      );
    }
    if (responsesPath != null) {
      throw const FormatException('--live cannot be combined with --responses');
    }
    if (format == null ||
        baseUrl == null ||
        model == null ||
        keyEnvironment == null) {
      throw const FormatException(
        '--live requires --format, --base-url, --model and --key-env',
      );
    }
    final endpointFormat = switch (format) {
      'chat' => AiEndpointFormat.openAiChatCompletions,
      'responses' => AiEndpointFormat.openAiResponses,
      'claude' => AiEndpointFormat.claudeMessages,
      _ => throw const FormatException(
        '--format must be chat, responses or claude',
      ),
    };
    if (!RegExp(r'^[A-Z_][A-Z0-9_]{0,63}$').hasMatch(keyEnvironment)) {
      throw const FormatException(
        '--key-env must name an uppercase environment variable',
      );
    }
    final rawKey = environment[keyEnvironment];
    final apiKey = rawKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw FormatException(
        'environment variable $keyEnvironment is missing or empty',
      );
    }
    if (apiKey.length > liveMaxApiKeyCharacters || apiKey.contains('\n')) {
      throw const FormatException('live API key is out of bounds');
    }
    final trimmedModel = model.trim();
    if (trimmedModel.isEmpty ||
        trimmedModel.length > liveMaxModelCharacters ||
        trimmedModel.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('--model is out of bounds');
    }
    final AiEndpoint endpoint;
    try {
      endpoint = AiEndpoint.normalize(baseUrl, endpointFormat);
    } on FormatException catch (error) {
      throw FormatException('invalid --base-url: ${error.message}');
    }
    if (endpoint.isInsecureRemoteHttp) {
      throw const FormatException(
        'live runs require HTTPS except for loopback addresses',
      );
    }
    final int? parsedMaxCases = maxCases == null
        ? liveMaxCasesCeiling
        : int.tryParse(maxCases);
    if (parsedMaxCases == null ||
        parsedMaxCases < 1 ||
        parsedMaxCases > liveMaxCasesCeiling) {
      throw FormatException('--max-cases must be 1..$liveMaxCasesCeiling');
    }
    final int? parsedTimeout = timeout == null ? 60 : int.tryParse(timeout);
    if (parsedTimeout == null ||
        parsedTimeout < liveMinTimeout.inSeconds ||
        parsedTimeout > liveMaxTimeout.inSeconds) {
      throw const FormatException('--timeout must be 5..300 seconds');
    }
    return QualityCliOptions._(
      strict: strict,
      responsesPath: null,
      outputPath: outputPath,
      markdownPath: markdownPath,
      corpusPath: corpusPath,
      allowExternal: allowExternal,
      sendExternal: sendExternal,
      live: LiveProviderOptions._(
        endpoint: endpoint,
        model: trimmedModel,
        apiKey: apiKey,
        keyEnvironment: keyEnvironment,
        maxCases: parsedMaxCases,
        timeout: Duration(seconds: parsedTimeout),
      ),
    );
  }
}

final class LiveCollectionResult {
  LiveCollectionResult._({
    required this.responsesByCase,
    required this.requests,
    required this.requestedCaseIds,
    required this.failedCaseIds,
    required this.skippedCaseIds,
    required this.failureKinds,
    required this.cancelled,
  });

  final Map<String, List<String>> responsesByCase;
  final int requests;
  final List<String> requestedCaseIds;
  final List<String> failedCaseIds;
  final List<String> skippedCaseIds;
  final List<String> failureKinds;
  final bool cancelled;

  /// Empty value used by metadata and configuration tests.
  factory LiveCollectionResult.empty() => LiveCollectionResult._(
    responsesByCase: const {},
    requests: 0,
    requestedCaseIds: const [],
    failedCaseIds: const [],
    skippedCaseIds: const [],
    failureKinds: const [],
    cancelled: false,
  );
}

/// Sends the fixed synthetic corpus through the production prompt builder and
/// transport. Book text never leaves this process except for these synthetic
/// cases, and the API key is never copied into results or error strings.
Future<LiveCollectionResult> collectLiveResponses(
  QualityCorpus corpus, {
  required LiveProviderOptions options,
  required AiTextClient client,
  bool Function()? isCancelled,
}) async {
  final responses = <String, List<String>>{
    for (final qualityCase in corpus.cases)
      qualityCase.id: List<String>.filled(
        qualityCase.plan.chunks.length,
        liveInvalidResponse,
      ),
  };
  final requested = <String>[];
  final failed = <String>[];
  final skipped = <String>[];
  final failureKinds = <String>[];
  var requests = 0;
  var cancelled = false;
  var casesStarted = 0;
  for (final qualityCase in corpus.cases) {
    if (cancelled || (isCancelled?.call() ?? false)) {
      cancelled = true;
      skipped.add(qualityCase.id);
      continue;
    }
    if (casesStarted >= options.maxCases) {
      skipped.add(qualityCase.id);
      continue;
    }
    casesStarted++;
    requested.add(qualityCase.id);
    final responsesForCase = <String>[];
    var caseFailed = false;
    for (final chunk in qualityCase.plan.chunks) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      requests++;
      try {
        final response = await client.generate(
          endpoint: options.endpoint,
          apiKey: options.apiKey,
          model: options.model,
          systemPrompt: AiProofreadingPrompt.system(qualityCase.intent),
          userContext: AiProofreadingPrompt.userContext(
            qualityCase.intent,
            chunk,
          ),
          outputTokens: liveOutputTokens,
          cancellation: AiCancellation(),
        );
        if (response.length > 65536) {
          throw const FormatException(
            'live response exceeds the corpus budget',
          );
        }
        jsonDecode(response);
        responsesForCase.add(response);
      } on Object catch (error) {
        failureKinds.add(_failureKind(error));
        caseFailed = true;
        break;
      }
    }
    if (cancelled) {
      skipped.add(qualityCase.id);
      continue;
    }
    if (caseFailed ||
        responsesForCase.length != qualityCase.plan.chunks.length) {
      failed.add(qualityCase.id);
      continue;
    }
    responses[qualityCase.id] = responsesForCase;
  }
  return LiveCollectionResult._(
    responsesByCase: Map<String, List<String>>.unmodifiable(responses),
    requests: requests,
    requestedCaseIds: List<String>.unmodifiable(requested),
    failedCaseIds: List<String>.unmodifiable(failed),
    skippedCaseIds: List<String>.unmodifiable(skipped),
    failureKinds: List<String>.unmodifiable(failureKinds),
    cancelled: cancelled,
  );
}

/// Refuses to send an external corpus unless the caller explicitly opted in.
void validateLiveCorpusConsent(
  QualityCorpus corpus, {
  required bool sendExternal,
}) {
  if (!corpus.isExternal) {
    if (sendExternal) {
      throw const FormatException(
        '--send-external is only valid for an external corpus',
      );
    }
    return;
  }
  if (!sendExternal) {
    throw const FormatException(
      'external corpus requires --send-external before sending to a provider',
    );
  }
}

/// Report metadata for one live run. It intentionally omits the key value,
/// prompts and response bodies.
Map<String, Object?> liveProviderMetadata(
  LiveProviderOptions options,
  LiveCollectionResult collection,
) => <String, Object?>{
  'format': options.formatName,
  'endpoint_host': options.endpoint.requestUri.host,
  'model': options.model,
  'key_env': options.keyEnvironment,
  'max_cases': options.maxCases,
  'requested_cases': collection.requestedCaseIds,
  'requests': collection.requests,
  'failed_cases': collection.failedCaseIds,
  'skipped_cases': collection.skippedCaseIds,
  'failure_kinds': collection.failureKinds,
  'cancelled': collection.cancelled,
};

/// Sanitized failure category: never includes prompts, responses or key values.
String _failureKind(Object error) => switch (error) {
  AiTransportException() => 'transport:${error.failure.name}',
  AiProtocolException() => 'protocol:${error.failure.name}',
  AppFailure() => 'app:${error.runtimeType}',
  FormatException() => 'format',
  _ => 'other:${error.runtimeType}',
};
