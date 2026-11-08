import 'dart:async';
import 'dart:convert';

import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/settings_store.dart';

final class AiSettingsConfigurationStore implements AiConfigurationStore {
  AiSettingsConfigurationStore(AppDatabase database)
    : _database = database,
      _settings = SettingsStore(database);

  static const key = 'ai.configuration';
  static const pendingCleanupKey = 'ai.configuration.pending_cleanup';
  static final RegExp _referencePattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final Expando<_CredentialMutationGate> _mutationGates = Expando();

  final AppDatabase _database;
  final SettingsStore _settings;

  @override
  Future<T> withCredentialMutation<T>(Future<T> Function() action) {
    final gate = _mutationGates[_database] ??= _CredentialMutationGate();
    return gate.run(action);
  }

  @override
  Future<AiConfiguration> read() async {
    final raw = await _settings.read(key);
    if (raw == null) return const AiConfiguration();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('AI 配置数据无效。');
      }
      return AiConfiguration.fromJson(decoded);
    } catch (_) {
      throw const FormatException('AI 配置数据无效。');
    }
  }

  @override
  Future<List<String>> readPendingCleanup() async {
    final raw = await _settings.read(pendingCleanupKey);
    if (raw == null) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.length > 1024) {
        throw const FormatException('AI 凭据清理队列无效。');
      }
      final references = <String>{};
      for (final item in decoded) {
        if (item is! String || !_referencePattern.hasMatch(item)) {
          throw const FormatException('AI 凭据清理队列无效。');
        }
        references.add(item);
      }
      return references.toList()..sort();
    } catch (_) {
      throw const FormatException('AI 凭据清理队列无效。');
    }
  }

  @override
  Future<void> addPendingCleanup(String reference) async {
    _validateReference(reference);
    await _database.transaction(() async {
      final references = (await readPendingCleanup()).toSet()..add(reference);
      await _writePendingCleanup(references);
    });
  }

  @override
  Future<void> removePendingCleanup(String reference) async {
    _validateReference(reference);
    await _database.transaction(() async {
      final references = (await readPendingCleanup()).toSet()
        ..remove(reference);
      await _writePendingCleanup(references);
    });
  }

  @override
  Future<bool> writeIfCurrent({
    required AiConfiguration expected,
    required AiConfiguration configuration,
  }) => _database.transaction(() async {
    if (await read() != expected) return false;
    final references = (await readPendingCleanup()).toSet();
    final oldReference = expected.credentialReference;
    final newReference = configuration.credentialReference;
    if (oldReference != null && oldReference != newReference) {
      references.add(oldReference);
    }
    if (newReference != null) references.remove(newReference);
    await _settings.write(key, jsonEncode(configuration.toJson()));
    await _writePendingCleanup(references);
    return true;
  });

  Future<void> _writePendingCleanup(Set<String> references) async {
    if (references.length > 1024) {
      throw const FormatException('AI 凭据清理队列已满。');
    }
    final sorted = references.toList()..sort();
    await _settings.write(pendingCleanupKey, jsonEncode(sorted));
  }

  static void _validateReference(String reference) {
    if (!_referencePattern.hasMatch(reference)) {
      throw const FormatException('AI 凭据引用无效。');
    }
  }
}

final class _CredentialMutationGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) async {
    final predecessor = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await predecessor;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }
}
