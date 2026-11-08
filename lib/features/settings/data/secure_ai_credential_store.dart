import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/ai/ai_configuration.dart';
import '../../../core/errors/app_failure.dart';

final class SecureAiCredentialStore implements AiCredentialStore {
  SecureAiCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              migrateWithBackup: false,
              storageNamespace: 'bookloom_ai',
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String reference) async {
    final key = _key(reference);
    try {
      final value = await _storage.read(key: key);
      if (value != null) _validateValue(value);
      return value;
    } on Object catch (error) {
      _failed(error);
    }
  }

  @override
  Future<void> write(String reference, String value) async {
    final key = _key(reference);
    _validateValue(value);
    try {
      await _storage.write(key: key, value: value);
    } on Object catch (error) {
      _failed(error);
    }
  }

  @override
  Future<void> delete(String reference) async {
    final key = _key(reference);
    try {
      await _storage.delete(key: key);
    } on Object catch (error) {
      _failed(error);
    }
  }

  static String _key(String reference) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(reference)) {
      throw const ValidationFailure('AI 密钥引用无效，请重新配置。');
    }
    return 'bookloom_ai_credential_$reference';
  }

  static void _validateValue(String value) {
    if (value.isEmpty ||
        value.length > 4096 ||
        value.trim() != value ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const ValidationFailure('API 密钥格式无效，请检查空白和长度。');
    }
  }

  static Never _failed(Object error) {
    if (error is PlatformException && error.code == 'KeyringLocked') {
      throw const StorageFailure('系统密钥环已锁定，请解锁后重试；密钥未降级为明文保存。');
    }
    throw const StorageFailure('无法访问系统安全存储，请检查系统密钥环后重试。');
  }
}
