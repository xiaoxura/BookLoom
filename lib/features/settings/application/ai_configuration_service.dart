import 'dart:convert';

import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

enum AiConfigurationFailure {
  busy,
  invalidConfiguration,
  missingCredential,
  credentialUnavailable,
  staleConfiguration,
  proofRequired,
  connectionFailed,
  cancelled,
  saveFailed,
  commitUnknown,
  cleanupFailed,
}

final class AiCredentialCleanupWarning {
  const AiCredentialCleanupWarning._(this.reference);

  final String reference;
}

final class AiConfigurationException implements Exception {
  const AiConfigurationException(
    this.failure, {
    this.cleanupWarning,
    this.protocolFailure,
    this.transportFailure,
  });

  final AiConfigurationFailure failure;
  final AiCredentialCleanupWarning? cleanupWarning;
  final AiProtocolFailure? protocolFailure;
  final AiTransportFailure? transportFailure;

  @override
  String toString() => 'AiConfigurationException: ${failure.name}';
}

final class AiConnectionProof {
  const AiConnectionProof._(
    this._configuration,
    this._expected,
    this._credentialDigest,
  );

  final AiConfiguration _configuration;
  final AiConfiguration _expected;
  final Digest _credentialDigest;
}

final class AiConfigurationSaveResult {
  const AiConfigurationSaveResult(this.configuration, {this.cleanupWarning});

  final AiConfiguration configuration;
  final AiCredentialCleanupWarning? cleanupWarning;
}

final class AiConfigurationService {
  factory AiConfigurationService({
    required AiConfigurationStore cfgStore,
    required AiCredentialStore credentials,
    required AiTextClient Function() createClient,
  }) => AiConfigurationService._(cfgStore, credentials, createClient);

  AiConfigurationService._(
    this._cfgStore,
    this._credentials,
    this._createClient,
  );

  static const connectionMarker = 'BOOKLOOM_CONNECTION_OK';
  static const _systemPrompt =
      'This is a connection test. Reply with exactly BOOKLOOM_CONNECTION_OK.';
  static const _userContext =
      'Reply with exactly BOOKLOOM_CONNECTION_OK. No other text.';

  final AiConfigurationStore _cfgStore;
  final AiCredentialStore _credentials;
  final AiTextClient Function() _createClient;
  final String _proofSalt = const Uuid().v4();

  bool _busy = false;
  int _proofGeneration = 0;
  AiConnectionProof? _lastProof;

  bool get isBusy => _busy;

  void invalidateProof() {
    _proofGeneration++;
    _lastProof = null;
  }

  Future<AiConfiguration> load() => _exclusive(_read);

  Future<List<AiCredentialCleanupWarning>> get pendingCleanupWarnings =>
      _exclusive(
        () => _withCredentialMutation(() async {
          final current = await _read();
          final pending = await _readPendingCleanup();
          return List<AiCredentialCleanupWarning>.unmodifiable(
            pending
                .where((reference) => reference != current.credentialReference)
                .map(AiCredentialCleanupWarning._),
          );
        }),
      );

  Future<AiConnectionProof> testConnection({
    required AiConfiguration configuration,
    required AiConfiguration expected,
    String? apiKey,
    AiCancellation? cancellation,
  }) => _exclusive(() async {
    invalidateProof();
    final proofGeneration = _proofGeneration;
    final candidate = _validate(configuration, expected, apiKey);
    if (!candidate.enabled) {
      throw const AiConfigurationException(
        AiConfigurationFailure.invalidConfiguration,
      );
    }
    final signal = cancellation ?? AiCancellation();
    _checkTestActive(signal, proofGeneration);
    await _ensureCurrent(expected);
    _checkTestActive(signal, proofGeneration);
    final key = await _resolveKey(
      candidate: candidate,
      expected: expected,
      apiKey: apiKey,
    );
    _checkTestActive(signal, proofGeneration);
    AiTextClient? client;
    try {
      client = _createClient();
      final response = await client.generate(
        endpoint: candidate.endpoint,
        apiKey: key,
        model: candidate.model,
        systemPrompt: _systemPrompt,
        userContext: _userContext,
        outputTokens: 32,
        cancellation: signal,
      );
      _checkTestActive(signal, proofGeneration);
      if (response.trim() != connectionMarker) {
        throw const AiConfigurationException(
          AiConfigurationFailure.connectionFailed,
        );
      }
      final proof = AiConnectionProof._(candidate, expected, _digest(key));
      _lastProof = proof;
      return proof;
    } on AiConfigurationException {
      rethrow;
    } on AiTransportException catch (error) {
      throw AiConfigurationException(
        error.failure == AiTransportFailure.cancelled
            ? AiConfigurationFailure.cancelled
            : AiConfigurationFailure.connectionFailed,
        transportFailure: error.failure,
      );
    } on AiProtocolException catch (error) {
      throw AiConfigurationException(
        AiConfigurationFailure.connectionFailed,
        protocolFailure: error.failure,
      );
    } catch (_) {
      if (signal.isCancelled) {
        throw const AiConfigurationException(AiConfigurationFailure.cancelled);
      }
      throw const AiConfigurationException(
        AiConfigurationFailure.connectionFailed,
      );
    } finally {
      try {
        client?.dispose();
      } catch (_) {}
    }
  });

  Future<AiConfigurationSaveResult> save({
    required AiConfiguration configuration,
    required AiConfiguration expected,
    String? apiKey,
    AiConnectionProof? proof,
  }) => _exclusive(
    () => _withCredentialMutation(() async {
      final candidate = _validate(configuration, expected, apiKey);
      if (candidate.enabled &&
          (proof == null ||
              !identical(proof, _lastProof) ||
              proof._configuration != candidate ||
              proof._expected != expected)) {
        throw const AiConfigurationException(
          AiConfigurationFailure.proofRequired,
        );
      }
      await _ensureCurrent(expected);
      if (candidate.enabled) {
        final key = await _resolveKey(
          candidate: candidate,
          expected: expected,
          apiKey: apiKey,
        );
        if (_digest(key) != proof!._credentialDigest) {
          throw const AiConfigurationException(
            AiConfigurationFailure.proofRequired,
          );
        }
      }

      String? newReference;
      if (apiKey != null && apiKey.isNotEmpty) {
        newReference = 'ai_${const Uuid().v4().replaceAll('-', '')}';
        try {
          await _cfgStore.addPendingCleanup(newReference);
        } catch (_) {
          throw const AiConfigurationException(
            AiConfigurationFailure.saveFailed,
          );
        }
        try {
          await _credentials.write(newReference, apiKey);
        } catch (_) {
          final warning = await _cleanup(newReference);
          throw AiConfigurationException(
            AiConfigurationFailure.credentialUnavailable,
            cleanupWarning: warning,
          );
        }
      }

      final next = candidate.withCredentialReference(
        newReference ?? expected.credentialReference,
      );
      bool? wrote;
      try {
        wrote = await _cfgStore.writeIfCurrent(
          expected: expected,
          configuration: next,
        );
      } catch (_) {}

      AiConfiguration? actual;
      try {
        actual = await _cfgStore.read();
      } catch (_) {}
      if (actual != next || wrote != true) {
        if (actual == next) {
          return _finishCommitted(next, expected);
        }
        if (actual == null ||
            actual.credentialReference == newReference &&
                newReference != null) {
          final warning = newReference == null
              ? null
              : AiCredentialCleanupWarning._(newReference);
          throw AiConfigurationException(
            AiConfigurationFailure.commitUnknown,
            cleanupWarning: warning,
          );
        }
        final warning = newReference == null
            ? null
            : await _cleanup(newReference);
        throw AiConfigurationException(
          wrote == false
              ? AiConfigurationFailure.staleConfiguration
              : AiConfigurationFailure.saveFailed,
          cleanupWarning: warning,
        );
      }
      return _finishCommitted(next, expected);
    }),
  );

  Future<AiConfigurationSaveResult> clear({
    required AiConfiguration expected,
  }) => _exclusive(
    () => _withCredentialMutation(() async {
      await _ensureCurrent(expected);
      const empty = AiConfiguration();
      bool? wrote;
      try {
        wrote = await _cfgStore.writeIfCurrent(
          expected: expected,
          configuration: empty,
        );
      } catch (_) {}
      AiConfiguration? actual;
      try {
        actual = await _cfgStore.read();
      } catch (_) {}
      if (actual == empty) return _finishCommitted(empty, expected);
      if (actual == null) {
        throw const AiConfigurationException(
          AiConfigurationFailure.commitUnknown,
        );
      }
      throw AiConfigurationException(
        wrote == false
            ? AiConfigurationFailure.staleConfiguration
            : AiConfigurationFailure.saveFailed,
      );
    }),
  );

  Future<void> retryCleanup(AiCredentialCleanupWarning warning) => _exclusive(
    () => _withCredentialMutation(() async {
      if (!(await _readPendingCleanup()).contains(warning.reference)) {
        throw const AiConfigurationException(
          AiConfigurationFailure.cleanupFailed,
        );
      }
      final current = await _read();
      if (current.credentialReference == warning.reference) {
        throw const AiConfigurationException(
          AiConfigurationFailure.cleanupFailed,
        );
      }
      try {
        await _credentials.delete(warning.reference);
        await _cfgStore.removePendingCleanup(warning.reference);
      } catch (_) {
        throw AiConfigurationException(
          AiConfigurationFailure.cleanupFailed,
          cleanupWarning: warning,
        );
      }
    }),
  );

  Future<AiConfigurationSaveResult> _finishCommitted(
    AiConfiguration next,
    AiConfiguration expected,
  ) async {
    invalidateProof();
    AiCredentialCleanupWarning? warning;
    final oldReference = expected.credentialReference;
    if (oldReference != null && oldReference != next.credentialReference) {
      warning = await _cleanup(oldReference);
    }
    return AiConfigurationSaveResult(next, cleanupWarning: warning);
  }

  Future<AiCredentialCleanupWarning?> _cleanup(String reference) async {
    try {
      await _credentials.delete(reference);
      await _cfgStore.removePendingCleanup(reference);
      return null;
    } catch (_) {
      return AiCredentialCleanupWarning._(reference);
    }
  }

  Future<AiConfiguration> _read() async {
    try {
      return await _cfgStore.read();
    } catch (_) {
      throw const AiConfigurationException(AiConfigurationFailure.saveFailed);
    }
  }

  Future<List<String>> _readPendingCleanup() async {
    try {
      return await _cfgStore.readPendingCleanup();
    } catch (_) {
      throw const AiConfigurationException(AiConfigurationFailure.saveFailed);
    }
  }

  Future<void> _ensureCurrent(AiConfiguration expected) async {
    if (await _read() != expected) {
      invalidateProof();
      throw const AiConfigurationException(
        AiConfigurationFailure.staleConfiguration,
      );
    }
  }

  AiConfiguration _validate(
    AiConfiguration configuration,
    AiConfiguration expected,
    String? apiKey,
  ) {
    try {
      final candidate = configuration.canonicalized();
      if (candidate.credentialReference != expected.credentialReference ||
          apiKey != null &&
              apiKey.isNotEmpty &&
              (apiKey.length > 4096 ||
                  apiKey.trim() != apiKey ||
                  apiKey.contains(RegExp(r'[\x00-\x1f\x7f]')))) {
        throw const FormatException('AI 配置字段无效。');
      }
      if (apiKey == null || apiKey.isEmpty) {
        if (expected.credentialReference != null &&
            (candidate.format != expected.format ||
                candidate.address != expected.address)) {
          throw const FormatException('更换服务地址或格式需要重新输入密钥。');
        }
      }
      return candidate;
    } catch (_) {
      throw const AiConfigurationException(
        AiConfigurationFailure.invalidConfiguration,
      );
    }
  }

  Future<String> _resolveKey({
    required AiConfiguration candidate,
    required AiConfiguration expected,
    required String? apiKey,
  }) async {
    if (apiKey != null && apiKey.isNotEmpty) return apiKey;
    final reference = expected.credentialReference;
    if (reference == null ||
        candidate.format != expected.format ||
        candidate.address != expected.address) {
      throw const AiConfigurationException(
        AiConfigurationFailure.missingCredential,
      );
    }
    try {
      final key = await _credentials.read(reference);
      if (key == null || key.isEmpty) {
        throw const AiConfigurationException(
          AiConfigurationFailure.missingCredential,
        );
      }
      return key;
    } on AiConfigurationException {
      rethrow;
    } catch (_) {
      throw const AiConfigurationException(
        AiConfigurationFailure.credentialUnavailable,
      );
    }
  }

  Digest _digest(String key) => sha256.convert(utf8.encode('$_proofSalt:$key'));

  void _checkTestActive(AiCancellation signal, int generation) {
    signal.throwIfCancelled();
    if (generation != _proofGeneration) {
      throw const AiConfigurationException(AiConfigurationFailure.cancelled);
    }
  }

  Future<T> _withCredentialMutation<T>(Future<T> Function() action) async {
    try {
      return await _cfgStore.withCredentialMutation(action);
    } on AiConfigurationException {
      rethrow;
    } catch (_) {
      throw const AiConfigurationException(AiConfigurationFailure.saveFailed);
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const AiConfigurationException(AiConfigurationFailure.busy);
    }
    _busy = true;
    try {
      return await action();
    } on AiTransportException catch (error) {
      throw AiConfigurationException(
        error.failure == AiTransportFailure.cancelled
            ? AiConfigurationFailure.cancelled
            : AiConfigurationFailure.connectionFailed,
        transportFailure: error.failure,
      );
    } finally {
      _busy = false;
    }
  }
}
