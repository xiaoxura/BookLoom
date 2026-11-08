import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/features/settings/data/secure_ai_credential_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late List<MethodCall> calls;
  late Map<String, String> values;
  late SecureAiCredentialStore store;

  setUp(() {
    calls = <MethodCall>[];
    values = <String, String>{};
    store = SecureAiCredentialStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final arguments = call.arguments as Map;
          final key = arguments['key'] as String;
          switch (call.method) {
            case 'write':
              values[key] = arguments['value'] as String;
              return null;
            case 'read':
              return values[key];
            case 'delete':
              values.remove(key);
              return null;
            default:
              throw StateError('Unexpected bulk storage operation');
          }
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'only reads and deletes the exact app-owned credential reference',
    () async {
      values['unrelated-key'] = 'unrelated-synthetic-value';
      expect(await store.read('new-id'), isNull);
      await store.write('new-id', 'synthetic-key');
      expect(await store.read('new-id'), 'synthetic-key');
      await store.delete('new-id');
      expect(values, {'unrelated-key': 'unrelated-synthetic-value'});
      expect(calls.map((call) => call.method), [
        'read',
        'write',
        'read',
        'delete',
      ]);
      for (final call in calls) {
        expect((call.arguments as Map)['key'], 'bookloom_ai_credential_new-id');
      }
    },
  );

  test(
    'invalid references and keys never reach the platform channel',
    () async {
      for (final reference in ['', '../other', 'other/key', 'a' * 129]) {
        await expectLater(
          store.read(reference),
          throwsA(isA<ValidationFailure>()),
        );
        await expectLater(
          store.delete(reference),
          throwsA(isA<ValidationFailure>()),
        );
      }
      for (final key in ['', ' synthetic-key', 'key\nvalue', 'a' * 4097]) {
        await expectLater(
          store.write('owned', key),
          throwsA(isA<ValidationFailure>()),
        );
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'Android uses an isolated namespace without resetting data on error',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await store.write('owned', 'synthetic-key');
      final options = (calls.single.arguments as Map)['options'] as Map;
      expect(options['storageNamespace'], 'bookloom_ai');
      expect(options['resetOnError'], 'false');
      expect(options['migrateWithBackup'], 'false');
    },
  );

  test(
    'platform failures are sanitized and never fall back to plaintext',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            throw PlatformException(
              code: 'KeyringLocked',
              message: 'synthetic-private-value',
            );
          });
      for (final operation in <Future<void> Function()>[
        () async {
          await store.read('owned');
        },
        () => store.write('owned', 'synthetic-key'),
        () => store.delete('owned'),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<StorageFailure>()
                .having((error) => error.message, 'message', contains('已锁定'))
                .having(
                  (error) => error.toString(),
                  'private value',
                  isNot(contains('synthetic-private-value')),
                )
                .having((error) => error.cause, 'cause', isNull),
          ),
        );
      }
      expect(calls, hasLength(3));
    },
  );
}
