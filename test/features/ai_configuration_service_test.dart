import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/settings_store.dart';
import 'package:bookloom/features/settings/application/ai_configuration_service.dart';
import 'package:bookloom/features/settings/data/ai_configuration_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _Configurations implements AiConfigurationStore {
  AiConfiguration current = const AiConfiguration();
  final Set<String> pending = {};
  int reads = 0;
  int writes = 0;
  bool failRead = false;
  bool failAddPending = false;
  Future<bool> Function(AiConfiguration expected, AiConfiguration next)?
  onWrite;
  Future<void> _mutationTail = Future<void>.value();

  @override
  Future<T> withCredentialMutation<T>(Future<T> Function() action) async {
    final predecessor = _mutationTail;
    final release = Completer<void>();
    _mutationTail = release.future;
    await predecessor;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  @override
  Future<AiConfiguration> read() async {
    reads++;
    if (failRead) throw StateError('unavailable');
    return current;
  }

  @override
  Future<List<String>> readPendingCleanup() async => pending.toList()..sort();

  @override
  Future<void> addPendingCleanup(String reference) async {
    if (failAddPending) throw StateError('queue unavailable');
    pending.add(reference);
  }

  @override
  Future<void> removePendingCleanup(String reference) async {
    pending.remove(reference);
  }

  void commit(AiConfiguration configuration) {
    final oldReference = current.credentialReference;
    final newReference = configuration.credentialReference;
    if (oldReference != null && oldReference != newReference) {
      pending.add(oldReference);
    }
    if (newReference != null) pending.remove(newReference);
    current = configuration;
  }

  @override
  Future<bool> writeIfCurrent({
    required AiConfiguration expected,
    required AiConfiguration configuration,
  }) async {
    writes++;
    if (onWrite != null) return onWrite!(expected, configuration);
    if (current != expected) return false;
    commit(configuration);
    return true;
  }
}

class _Credentials implements AiCredentialStore {
  final Map<String, String> values = {};
  int reads = 0;
  int writes = 0;
  int deletes = 0;
  bool failWriteAfterStorage = false;
  bool failDelete = false;
  Future<void> Function(String reference)? afterWrite;

  @override
  Future<String?> read(String reference) async {
    reads++;
    return values[reference];
  }

  @override
  Future<void> write(String reference, String value) async {
    writes++;
    values[reference] = value;
    if (afterWrite != null) await afterWrite!(reference);
    if (failWriteAfterStorage) throw StateError('secret $value');
  }

  @override
  Future<void> delete(String reference) async {
    deletes++;
    if (failDelete) throw StateError('secret ${values[reference]}');
    values.remove(reference);
  }
}

class _Client implements AiTextClient {
  _Client(this.respond);

  final Future<String> Function(
    AiEndpoint endpoint,
    String key,
    String model,
    String context,
    AiCancellation cancellation,
  )
  respond;
  bool disposed = false;

  @override
  Future<String> generate({
    required AiEndpoint endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContext,
    required int outputTokens,
    required AiCancellation cancellation,
  }) => respond(endpoint, apiKey, model, userContext, cancellation);

  @override
  void dispose() => disposed = true;
}

AiConfiguration _candidate({
  AiEndpointFormat format = AiEndpointFormat.openAiChatCompletions,
  String address = 'https://api.example.com/v1',
  String model = 'small-model',
  String? reference,
  bool enabled = true,
}) => AiConfiguration(
  enabled: enabled,
  format: format,
  address: address,
  model: model,
  credentialReference: reference,
);

Matcher _failure(AiConfigurationFailure failure) => throwsA(
  isA<AiConfigurationException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  late _Configurations configurations;
  late _Credentials credentials;
  late List<_Client> clients;
  late AiConfigurationService service;

  setUp(() {
    configurations = _Configurations();
    credentials = _Credentials();
    clients = [];
    service = AiConfigurationService(
      cfgStore: configurations,
      credentials: credentials,
      createClient: () {
        final client = _Client(
          (endpoint, key, model, context, signal) async =>
              AiConfigurationService.connectionMarker,
        );
        clients.add(client);
        return client;
      },
    );
  });

  test('load is offline and does not read a credential', () async {
    expect(await service.load(), const AiConfiguration());
    expect(credentials.reads, 0);
    expect(clients, isEmpty);
  });

  test(
    'connection failures retain only protocol and transport enums',
    () async {
      final candidate = _candidate();
      for (final failure in AiProtocolFailure.values) {
        service = AiConfigurationService(
          cfgStore: configurations,
          credentials: credentials,
          createClient: () => _Client(
            (endpoint, key, model, context, signal) =>
                throw AiProtocolException(failure),
          ),
        );
        await expectLater(
          service.testConnection(
            configuration: candidate,
            expected: configurations.current,
            apiKey: 'test-key',
          ),
          throwsA(
            isA<AiConfigurationException>()
                .having(
                  (error) => error.failure,
                  'failure',
                  AiConfigurationFailure.connectionFailed,
                )
                .having((error) => error.protocolFailure, 'protocol', failure)
                .having((error) => error.transportFailure, 'transport', isNull),
          ),
        );
      }
      for (final failure in AiTransportFailure.values) {
        service = AiConfigurationService(
          cfgStore: configurations,
          credentials: credentials,
          createClient: () => _Client(
            (endpoint, key, model, context, signal) =>
                throw AiTransportException(failure),
          ),
        );
        await expectLater(
          service.testConnection(
            configuration: candidate,
            expected: configurations.current,
            apiKey: 'test-key',
          ),
          throwsA(
            isA<AiConfigurationException>()
                .having(
                  (error) => error.failure,
                  'failure',
                  failure == AiTransportFailure.cancelled
                      ? AiConfigurationFailure.cancelled
                      : AiConfigurationFailure.connectionFailed,
                )
                .having((error) => error.transportFailure, 'transport', failure)
                .having((error) => error.protocolFailure, 'protocol', isNull),
          ),
        );
      }
      expect(credentials.writes, 0);
      expect(configurations.writes, 0);
    },
  );

  test(
    'three formats use only the fixed connection fixture and dispose',
    () async {
      for (final format in AiEndpointFormat.values) {
        final contexts = <String>[];
        service = AiConfigurationService(
          cfgStore: configurations,
          credentials: credentials,
          createClient: () {
            final client = _Client((
              endpoint,
              key,
              model,
              context,
              signal,
            ) async {
              expect(endpoint.format, format);
              expect(key, 'test-key');
              expect(model, 'small-model');
              contexts.add(context);
              return AiConfigurationService.connectionMarker;
            });
            clients.add(client);
            return client;
          },
        );
        final candidate = _candidate(format: format);
        final proof = await service.testConnection(
          configuration: candidate,
          expected: configurations.current,
          apiKey: 'test-key',
        );
        expect(contexts, <String>[
          'Reply with exactly BOOKLOOM_CONNECTION_OK. No other text.',
        ]);
        expect(clients.last.disposed, isTrue);
        final result = await service.save(
          configuration: candidate,
          expected: configurations.current,
          apiKey: 'test-key',
          proof: proof,
        );
        expect(result.configuration.format, format);
        expect(result.configuration.credentialReference, isNotNull);
        expect(result.cleanupWarning, isNull);
        expect(credentials.values.length, 1);
        configurations.current = const AiConfiguration();
        credentials.values.clear();
      }
    },
  );

  test(
    'changed address, format, model or key rejects an earlier proof',
    () async {
      final candidate = _candidate();
      final proof = await service.testConnection(
        configuration: candidate,
        expected: configurations.current,
        apiKey: 'key-a',
      );
      for (final edited in <AiConfiguration>[
        _candidate(address: 'https://other.example.com'),
        _candidate(format: AiEndpointFormat.openAiResponses),
        _candidate(model: 'other-model'),
      ]) {
        await expectLater(
          service.save(
            configuration: edited,
            expected: configurations.current,
            apiKey: 'key-a',
            proof: proof,
          ),
          _failure(AiConfigurationFailure.proofRequired),
        );
      }
      await expectLater(
        service.save(
          configuration: candidate,
          expected: configurations.current,
          apiKey: 'key-b',
          proof: proof,
        ),
        _failure(AiConfigurationFailure.proofRequired),
      );
      expect(credentials.writes, 0);
      expect(configurations.writes, 0);
    },
  );

  test(
    'existing key can be reused on same host but never on another host',
    () async {
      configurations.current = _candidate(reference: 'old');
      credentials.values['old'] = 'old-key';
      final proof = await service.testConnection(
        configuration: configurations.current,
        expected: configurations.current,
        apiKey: '',
      );
      final result = await service.save(
        configuration: configurations.current,
        expected: configurations.current,
        proof: proof,
      );
      expect(result.configuration.credentialReference, 'old');
      expect(credentials.writes, 0);
      await expectLater(
        service.testConnection(
          configuration: _candidate(
            address: 'https://other.example.com',
            reference: 'old',
          ),
          expected: configurations.current,
        ),
        _failure(AiConfigurationFailure.invalidConfiguration),
      );
      expect(credentials.reads, 2);
    },
  );

  test('rotating the stored key after testing invalidates the proof', () async {
    configurations.current = _candidate(reference: 'old');
    credentials.values['old'] = 'old-key';
    final proof = await service.testConnection(
      configuration: configurations.current,
      expected: configurations.current,
    );
    credentials.values['old'] = 'different-key';
    await expectLater(
      service.save(
        configuration: configurations.current,
        expected: configurations.current,
        proof: proof,
      ),
      _failure(AiConfigurationFailure.proofRequired),
    );
    expect(configurations.writes, 0);
  });

  test(
    'editing and restoring the same values still invalidates proof',
    () async {
      final candidate = _candidate();
      final proof = await service.testConnection(
        configuration: candidate,
        expected: configurations.current,
        apiKey: 'test-key',
      );
      service.invalidateProof();
      await expectLater(
        service.save(
          configuration: candidate,
          expected: configurations.current,
          apiKey: 'test-key',
          proof: proof,
        ),
        _failure(AiConfigurationFailure.proofRequired),
      );
      expect(credentials.writes, 0);
    },
  );

  test('disabled configuration saves without test or network', () async {
    final result = await service.save(
      configuration: _candidate(enabled: false, model: ''),
      expected: configurations.current,
    );
    expect(result.configuration.enabled, isFalse);
    expect(clients, isEmpty);
    expect(credentials.reads, 0);
    await expectLater(
      service.testConnection(
        configuration: result.configuration,
        expected: result.configuration,
      ),
      _failure(AiConfigurationFailure.invalidConfiguration),
    );
  });

  test(
    'invalid parameters stop before credential reads and client creation',
    () async {
      configurations.current = _candidate(reference: 'old');
      await expectLater(
        service.testConnection(
          configuration: _candidate(
            address: 'https://other.example.com',
            reference: 'old',
          ),
          expected: configurations.current,
        ),
        _failure(AiConfigurationFailure.invalidConfiguration),
      );
      expect(credentials.reads, 0);
      expect(clients, isEmpty);
    },
  );

  test(
    'partial key write failure removes only the temporary reference',
    () async {
      credentials.failWriteAfterStorage = true;
      configurations.current = _candidate(reference: 'old', enabled: false);
      credentials.values['old'] = 'old-key';
      await expectLater(
        service.save(
          configuration: configurations.current,
          expected: configurations.current,
          apiKey: 'new-key',
        ),
        _failure(AiConfigurationFailure.credentialUnavailable),
      );
      expect(credentials.values, <String, String>{'old': 'old-key'});
      expect(configurations.pending, isEmpty);
      expect(configurations.current.credentialReference, 'old');
    },
  );

  test('cleanup queue failure prevents writing a new credential', () async {
    configurations.failAddPending = true;
    await expectLater(
      service.save(
        configuration: _candidate(enabled: false),
        expected: configurations.current,
        apiKey: 'new-key',
      ),
      _failure(AiConfigurationFailure.saveFailed),
    );
    expect(credentials.writes, 0);
    expect(configurations.writes, 0);
    expect(configurations.current, const AiConfiguration());
  });

  test(
    'metadata failure keeps old address and key, and removes new key',
    () async {
      configurations.current = _candidate(reference: 'old', enabled: false);
      credentials.values['old'] = 'old-key';
      configurations.onWrite = (expected, next) async =>
          throw StateError('sqlite failure');
      await expectLater(
        service.save(
          configuration: _candidate(
            address: 'https://other.example.com',
            reference: 'old',
            enabled: false,
          ),
          expected: configurations.current,
          apiKey: 'new-key',
        ),
        _failure(AiConfigurationFailure.saveFailed),
      );
      expect(configurations.current.address, 'https://api.example.com/v1');
      expect(credentials.values, <String, String>{'old': 'old-key'});
      expect(configurations.pending, isEmpty);
    },
  );

  test(
    'ambiguous commit readback preserves the committed new reference',
    () async {
      configurations.current = _candidate(reference: 'old', enabled: false);
      credentials.values['old'] = 'old-key';
      configurations.onWrite = (expected, next) async {
        configurations.commit(next);
        throw StateError('response lost');
      };
      final result = await service.save(
        configuration: _candidate(reference: 'old', enabled: false),
        expected: configurations.current,
        apiKey: 'new-key',
      );
      expect(result.configuration.credentialReference, isNot('old'));
      expect(credentials.values.values, <String>['new-key']);
    },
  );

  test('unreadable commit state retains the new key for safe retry', () async {
    configurations.current = _candidate(reference: 'old', enabled: false);
    credentials.values['old'] = 'old-key';
    configurations.onWrite = (expected, next) async {
      configurations.commit(next);
      configurations.failRead = true;
      throw StateError('commit response lost');
    };
    AiConfigurationException? failure;
    try {
      await service.save(
        configuration: configurations.current,
        expected: configurations.current,
        apiKey: 'new-key',
      );
    } on AiConfigurationException catch (error) {
      failure = error;
    }
    expect(failure?.failure, AiConfigurationFailure.commitUnknown);
    final newReference = failure?.cleanupWarning?.reference;
    expect(newReference, isNotNull);
    expect(configurations.current.credentialReference, newReference);
    expect(credentials.values[newReference], 'new-key');
    expect(credentials.values['old'], 'old-key');
    configurations.failRead = false;
    await expectLater(
      service.retryCleanup(failure!.cleanupWarning!),
      _failure(AiConfigurationFailure.cleanupFailed),
    );
    expect(credentials.values[newReference], 'new-key');
  });

  test('old credential cleanup failure is explicit and retryable', () async {
    configurations.current = _candidate(reference: 'old', enabled: false);
    credentials.values['old'] = 'old-key';
    credentials.failDelete = true;
    final result = await service.save(
      configuration: configurations.current,
      expected: configurations.current,
      apiKey: 'new-key',
    );
    final warning = result.cleanupWarning!;
    expect(warning.reference, 'old');
    expect(configurations.pending, <String>{'old'});
    expect(configurations.current.credentialReference, isNot('old'));
    expect(credentials.values.length, 2);
    credentials.failDelete = false;
    await service.retryCleanup(warning);
    expect(credentials.values.values, <String>['new-key']);
    expect(configurations.pending, isEmpty);
  });

  test('stale baseline and conditional write reject outdated pages', () async {
    final baseline = configurations.current;
    configurations.current = _candidate(enabled: false);
    await expectLater(
      service.save(configuration: baseline, expected: baseline),
      _failure(AiConfigurationFailure.staleConfiguration),
    );
    configurations.onWrite = (expected, next) async {
      configurations.current = _candidate(model: 'other', enabled: false);
      return false;
    };
    await expectLater(
      service.save(
        configuration: configurations.current,
        expected: configurations.current,
      ),
      _failure(AiConfigurationFailure.staleConfiguration),
    );
    expect(credentials.writes, 0);
  });

  test(
    'busy lock and cancellation suppress a late successful response',
    () async {
      final pending = Completer<String>();
      final started = Completer<void>();
      service = AiConfigurationService(
        cfgStore: configurations,
        credentials: credentials,
        createClient: () {
          final client = _Client((endpoint, key, model, context, signal) {
            started.complete();
            return pending.future;
          });
          clients.add(client);
          return client;
        },
      );
      final signal = AiCancellation();
      final candidate = _candidate();
      final testFuture = service.testConnection(
        configuration: candidate,
        expected: configurations.current,
        apiKey: 'test-key',
        cancellation: signal,
      );
      await started.future;
      await expectLater(service.load(), _failure(AiConfigurationFailure.busy));
      signal.cancel();
      pending.complete(AiConfigurationService.connectionMarker);
      await expectLater(testFuture, _failure(AiConfigurationFailure.cancelled));
      expect(clients.single.disposed, isTrue);
      await expectLater(
        service.save(
          configuration: candidate,
          expected: configurations.current,
          apiKey: 'test-key',
        ),
        _failure(AiConfigurationFailure.proofRequired),
      );
      expect(configurations.writes, 0);
    },
  );

  test('field edit suppresses a late connection result', () async {
    final pending = Completer<String>();
    final started = Completer<void>();
    service = AiConfigurationService(
      cfgStore: configurations,
      credentials: credentials,
      createClient: () => _Client((endpoint, key, model, context, signal) {
        started.complete();
        return pending.future;
      }),
    );
    final candidate = _candidate();
    final testFuture = service.testConnection(
      configuration: candidate,
      expected: configurations.current,
      apiKey: 'test-key',
    );
    await started.future;
    service.invalidateProof();
    pending.complete(AiConfigurationService.connectionMarker);
    await expectLater(testFuture, _failure(AiConfigurationFailure.cancelled));
    expect(configurations.writes, 0);
  });

  test('clear removes the current metadata and then its credential', () async {
    configurations.current = _candidate(reference: 'old');
    credentials.values['old'] = 'old-key';
    final result = await service.clear(expected: configurations.current);
    expect(result.configuration, const AiConfiguration());
    expect(configurations.current, const AiConfiguration());
    expect(credentials.values, isEmpty);
    expect(clients, isEmpty);
  });

  test('SettingsStore bridge writes one current JSON value with CAS', () async {
    final database = AppDatabase.memory();
    addTearDown(database.close);
    final store = AiSettingsConfigurationStore(database);
    const baseline = AiConfiguration();
    expect(await store.read(), baseline);
    final next = _candidate(enabled: false);
    expect(
      await store.writeIfCurrent(expected: baseline, configuration: next),
      isTrue,
    );
    expect(
      await store.writeIfCurrent(expected: baseline, configuration: next),
      isFalse,
    );
    expect(await store.read(), next);
  });

  test('SQLite queue survives service and database recreation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bookloom-ai-config-',
    );
    final file = File('${directory.path}/settings.sqlite');
    var database = AppDatabase.openAt(file);
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    var store = AiSettingsConfigurationStore(database);
    final old = _candidate(reference: 'old', enabled: false);
    expect(
      await store.writeIfCurrent(
        expected: const AiConfiguration(),
        configuration: old,
      ),
      isTrue,
    );
    credentials.values['old'] = 'old-key';
    credentials.failDelete = true;
    service = AiConfigurationService(
      cfgStore: store,
      credentials: credentials,
      createClient: () => throw StateError('network forbidden'),
    );
    final saved = await service.save(
      configuration: old,
      expected: old,
      apiKey: 'new-key',
    );
    expect(saved.cleanupWarning?.reference, 'old');
    final settings = SettingsStore(database);
    final queue = jsonDecode(
      (await settings.read(AiSettingsConfigurationStore.pendingCleanupKey))!,
    );
    expect(queue, <String>['old']);
    expect(queue.toString(), isNot(contains('old-key')));
    expect(queue.toString(), isNot(contains('new-key')));
    await database.close();

    database = AppDatabase.openAt(file);
    store = AiSettingsConfigurationStore(database);
    service = AiConfigurationService(
      cfgStore: store,
      credentials: credentials,
      createClient: () => throw StateError('network forbidden'),
    );
    final readCount = credentials.reads;
    expect(
      (await service.load()).credentialReference,
      saved.configuration.credentialReference,
    );
    final warnings = await service.pendingCleanupWarnings;
    expect(warnings.map((warning) => warning.reference), <String>['old']);
    expect(credentials.reads, readCount);
    credentials.failDelete = false;
    await service.retryCleanup(warnings.single);
    expect(await service.pendingCleanupWarnings, isEmpty);
    expect(credentials.values.values, <String>['new-key']);
  });

  test('pre-commit orphan is recoverable without secret enumeration', () async {
    final database = AppDatabase.memory();
    addTearDown(database.close);
    final store = AiSettingsConfigurationStore(database);
    await store.addPendingCleanup('ai_orphan');
    await credentials.write('ai_orphan', 'new-key');
    final recreated = AiConfigurationService(
      cfgStore: store,
      credentials: credentials,
      createClient: () => throw StateError('network forbidden'),
    );
    final warnings = await recreated.pendingCleanupWarnings;
    expect(warnings.map((warning) => warning.reference), <String>['ai_orphan']);
    expect(credentials.reads, 0);
    await recreated.retryCleanup(warnings.single);
    expect(credentials.values, isEmpty);
    expect(await store.readPendingCleanup(), isEmpty);
  });

  test(
    'CAS atomically queues old reference and protects new current one',
    () async {
      final database = AppDatabase.memory();
      addTearDown(database.close);
      final store = AiSettingsConfigurationStore(database);
      final old = _candidate(reference: 'old', enabled: false);
      final next = _candidate(reference: 'new', enabled: false);
      await store.writeIfCurrent(
        expected: const AiConfiguration(),
        configuration: old,
      );
      await store.addPendingCleanup('new');
      final warningForNew = (await AiConfigurationService(
        cfgStore: store,
        credentials: credentials,
        createClient: () => throw StateError('network forbidden'),
      ).pendingCleanupWarnings).single;
      expect(
        await store.writeIfCurrent(expected: old, configuration: next),
        isTrue,
      );
      expect(await store.readPendingCleanup(), <String>['old']);
      final recreated = AiConfigurationService(
        cfgStore: store,
        credentials: credentials,
        createClient: () => throw StateError('network forbidden'),
      );
      await expectLater(
        recreated.retryCleanup(warningForNew),
        _failure(AiConfigurationFailure.cleanupFailed),
      );
      expect((await recreated.pendingCleanupWarnings).single.reference, 'old');
    },
  );

  test(
    'two stores on one database hide in-flight references until commit',
    () async {
      final database = AppDatabase.memory();
      addTearDown(database.close);
      final storeA = AiSettingsConfigurationStore(database);
      final storeB = AiSettingsConfigurationStore(database);
      final entered = Completer<String>();
      final release = Completer<void>();
      credentials.afterWrite = (reference) async {
        entered.complete(reference);
        await release.future;
      };
      final serviceA = AiConfigurationService(
        cfgStore: storeA,
        credentials: credentials,
        createClient: () => throw StateError('network forbidden'),
      );
      final serviceB = AiConfigurationService(
        cfgStore: storeB,
        credentials: credentials,
        createClient: () => throw StateError('network forbidden'),
      );
      final serviceC = AiConfigurationService(
        cfgStore: AiSettingsConfigurationStore(database),
        credentials: credentials,
        createClient: () => throw StateError('network forbidden'),
      );

      final saveFuture = serviceA.save(
        configuration: _candidate(enabled: false),
        expected: const AiConfiguration(),
        apiKey: 'new-key',
      );
      final newReference = await entered.future;
      expect(await storeB.readPendingCleanup(), <String>[newReference]);
      expect(await storeB.read(), const AiConfiguration());

      var warningsCompleted = false;
      final warningsFuture = serviceB.pendingCleanupWarnings.then((warnings) {
        warningsCompleted = true;
        return warnings;
      });
      final staleClearExpectation = expectLater(
        serviceC.clear(expected: const AiConfiguration()),
        _failure(AiConfigurationFailure.staleConfiguration),
      );
      await Future<void>.delayed(Duration.zero);
      expect(warningsCompleted, isFalse);
      expect(credentials.values[newReference], 'new-key');

      release.complete();
      final saved = await saveFuture;
      expect(saved.configuration.credentialReference, newReference);
      expect(await warningsFuture, isEmpty);
      await staleClearExpectation;
      expect((await storeB.read()).credentialReference, newReference);
      expect(credentials.values[newReference], 'new-key');
    },
  );

  test(
    'retry waits behind another service mutation on the same database',
    () async {
      final database = AppDatabase.memory();
      addTearDown(database.close);
      final storeA = AiSettingsConfigurationStore(database);
      final storeB = AiSettingsConfigurationStore(database);
      await storeA.addPendingCleanup('orphan');
      credentials.values['orphan'] = 'orphan-key';
      final entered = Completer<void>();
      final release = Completer<void>();
      credentials.afterWrite = (reference) async {
        entered.complete();
        await release.future;
      };
      final serviceA = AiConfigurationService(
        cfgStore: storeA,
        credentials: credentials,
        createClient: () => throw StateError('network forbidden'),
      );
      final serviceB = AiConfigurationService(
        cfgStore: storeB,
        credentials: credentials,
        createClient: () => throw StateError('network forbidden'),
      );
      final warning = (await serviceB.pendingCleanupWarnings).single;
      final saveFuture = serviceA.save(
        configuration: _candidate(enabled: false),
        expected: const AiConfiguration(),
        apiKey: 'new-key',
      );
      await entered.future;
      final retryFuture = serviceB.retryCleanup(warning);
      await Future<void>.delayed(Duration.zero);
      expect(credentials.values['orphan'], 'orphan-key');
      expect(credentials.deletes, 0);

      release.complete();
      await saveFuture;
      await retryFuture;
      expect(credentials.values.containsKey('orphan'), isFalse);
      expect(await storeB.readPendingCleanup(), isEmpty);
    },
  );

  test('failed credential write releases the shared mutation gate', () async {
    final database = AppDatabase.memory();
    addTearDown(database.close);
    final storeA = AiSettingsConfigurationStore(database);
    final storeB = AiSettingsConfigurationStore(database);
    final entered = Completer<void>();
    final release = Completer<void>();
    credentials.failWriteAfterStorage = true;
    credentials.afterWrite = (reference) async {
      entered.complete();
      await release.future;
    };
    final serviceA = AiConfigurationService(
      cfgStore: storeA,
      credentials: credentials,
      createClient: () => throw StateError('network forbidden'),
    );
    final serviceB = AiConfigurationService(
      cfgStore: storeB,
      credentials: credentials,
      createClient: () => throw StateError('network forbidden'),
    );
    final failedSave = expectLater(
      serviceA.save(
        configuration: _candidate(enabled: false),
        expected: const AiConfiguration(),
        apiKey: 'new-key',
      ),
      _failure(AiConfigurationFailure.credentialUnavailable),
    );
    await entered.future;
    final warnings = serviceB.pendingCleanupWarnings;
    release.complete();
    await failedSave;
    expect(await warnings, isEmpty);
    expect(await storeB.readPendingCleanup(), isEmpty);
    expect(credentials.values, isEmpty);
  });
}
