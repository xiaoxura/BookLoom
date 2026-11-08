import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';

final class AiHttpClient implements AiTextClient {
  AiHttpClient({
    this.timeout = const Duration(seconds: 60),
    this.maxRequestBytes = 512 * 1024,
    this.maxResponseBytes = 512 * 1024,
  }) {
    if (timeout <= Duration.zero ||
        maxRequestBytes < 1 ||
        maxResponseBytes < 1) {
      throw ArgumentError('AI transport budgets must be positive.');
    }
  }

  final Duration timeout;
  final int maxRequestBytes;
  final int maxResponseBytes;

  bool _disposed = false;
  bool _active = false;
  void Function()? _stopActive;

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
    if (_disposed) {
      throw const AiTransportException(AiTransportFailure.disposed);
    }
    if (_active) {
      throw const AiTransportException(AiTransportFailure.concurrentRequest);
    }
    _active = true;

    HttpClient? client;
    HttpClientRequest? request;
    StreamSubscription<List<int>>? subscription;
    AiTransportFailure? stopped;
    final interrupted = Completer<void>();

    void stop(AiTransportFailure reason) {
      if (stopped != null) return;
      stopped = reason;
      interrupted.complete();
      final currentSubscription = subscription;
      if (currentSubscription != null) {
        unawaited(currentSubscription.cancel().catchError((Object _) {}));
      }
      try {
        request?.abort();
      } catch (_) {}
      try {
        client?.close(force: true);
      } catch (_) {}
    }

    Future<T> waitFor<T>(Future<T> operation) => Future.any(<Future<T>>[
      operation,
      interrupted.future.then<T>(
        (_) =>
            throw AiTransportException(stopped ?? AiTransportFailure.cancelled),
      ),
    ]);

    final removeCancellation = cancellation.onCancel(
      () => stop(AiTransportFailure.cancelled),
    );
    _stopActive = () => stop(AiTransportFailure.disposed);
    final timer = Timer(timeout, () => stop(AiTransportFailure.timedOut));

    try {
      cancellation.throwIfCancelled();
      final protocolRequest = AiProtocol.buildRequest(
        format: endpoint.format,
        apiKey: apiKey,
        model: model,
        systemPrompt: systemPrompt,
        userContext: userContext,
        outputTokens: outputTokens,
      );
      final body = utf8.encode(jsonEncode(protocolRequest.body));
      if (body.length > maxRequestBytes) {
        throw const AiTransportException(AiTransportFailure.requestTooLarge);
      }
      if (stopped != null) throw AiTransportException(stopped!);

      final activeClient = HttpClient()..autoUncompress = true;
      client = activeClient;
      final activeRequest = await waitFor(
        activeClient.postUrl(endpoint.requestUri),
      );
      request = activeRequest;
      if (stopped != null) throw AiTransportException(stopped!);
      activeRequest.followRedirects = false;
      activeRequest.contentLength = body.length;
      for (final entry in protocolRequest.headers.entries) {
        activeRequest.headers.set(entry.key, entry.value);
      }
      activeRequest.add(body);
      final response = await waitFor(activeRequest.close());
      if (stopped != null) throw AiTransportException(stopped!);

      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const AiTransportException(AiTransportFailure.redirect);
      }
      if (response.statusCode != HttpStatus.ok) {
        AiProtocol.extractText(
          format: endpoint.format,
          statusCode: response.statusCode,
          responseBody: '',
        );
      }
      if (response.contentLength > maxResponseBytes) {
        throw const AiTransportException(AiTransportFailure.responseTooLarge);
      }

      final bytes = <int>[];
      final completed = Completer<void>();
      subscription = response.listen(
        (chunk) {
          if (stopped != null || completed.isCompleted) return;
          if (chunk.length > maxResponseBytes - bytes.length) {
            completed.completeError(
              const AiTransportException(AiTransportFailure.responseTooLarge),
            );
            return;
          }
          bytes.addAll(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completed.isCompleted) {
            completed.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completed.isCompleted) {
            completed.complete();
          }
        },
        cancelOnError: true,
      );
      await waitFor(completed.future);
      if (stopped != null) throw AiTransportException(stopped!);

      late final String responseBody;
      try {
        responseBody = utf8.decode(bytes, allowMalformed: false);
      } on FormatException {
        throw const AiTransportException(AiTransportFailure.invalidUtf8);
      }
      final text = AiProtocol.extractText(
        format: endpoint.format,
        statusCode: response.statusCode,
        responseBody: responseBody,
      );
      if (stopped != null) throw AiTransportException(stopped!);
      return text;
    } on AiTransportException {
      rethrow;
    } on AiProtocolException {
      rethrow;
    } catch (_) {
      if (stopped != null) throw AiTransportException(stopped!);
      throw const AiTransportException(AiTransportFailure.connection);
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
      try {
        await subscription?.cancel();
      } catch (_) {}
      if (cancellation.isCancelled && stopped == null) {
        stopped = AiTransportFailure.cancelled;
      }
      timer.cancel();
      removeCancellation();
      _stopActive = null;
      _active = false;
      if (stopped != null) throw AiTransportException(stopped!);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopActive?.call();
  }
}
