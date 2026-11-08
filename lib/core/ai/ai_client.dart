import 'package:bookloom/core/ai/ai_endpoint.dart';

enum AiTransportFailure {
  cancelled,
  timedOut,
  connection,
  redirect,
  invalidUtf8,
  requestTooLarge,
  responseTooLarge,
  concurrentRequest,
  disposed,
}

final class AiTransportException implements Exception {
  const AiTransportException(this.failure);

  final AiTransportFailure failure;

  @override
  String toString() => 'AiTransportException: ${failure.name}';
}

/// A one-way, reusable cancellation signal for an AI task.
final class AiCancellation {
  bool _isCancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {}
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const AiTransportException(AiTransportFailure.cancelled);
    }
  }

  /// Returns a remover so a completed request does not retain its resources.
  void Function() onCancel(void Function() listener) {
    if (_isCancelled) {
      try {
        listener();
      } catch (_) {}
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

abstract interface class AiTextClient {
  /// Returns untrusted protocol text; this interface never applies proposals.
  Future<String> generate({
    required AiEndpoint endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
    required AiCancellation cancellation,
  });

  void dispose();
}
