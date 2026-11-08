import 'dart:async';

import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/settings/application/ai_configuration_service.dart';
import 'package:bookloom/features/settings/presentation/ai_settings_page.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _zh = lookupAppLocalizations(const Locale('zh'));

class _Configurations implements AiConfigurationStore {
  AiConfiguration current = const AiConfiguration();
  final pendingCleanup = <String>{};
  Future<void> _mutationTail = Future<void>.value();
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<T> withCredentialMutation<T>(Future<T> Function() action) async {
    final previous = _mutationTail;
    final release = Completer<void>();
    _mutationTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  @override
  Future<AiConfiguration> read() async {
    if (failRead) throw StateError('unavailable');
    return current;
  }

  @override
  Future<List<String>> readPendingCleanup() async =>
      pendingCleanup.toList()..sort();

  @override
  Future<void> addPendingCleanup(String reference) async {
    pendingCleanup.add(reference);
  }

  @override
  Future<void> removePendingCleanup(String reference) async {
    pendingCleanup.remove(reference);
  }

  @override
  Future<bool> writeIfCurrent({
    required AiConfiguration expected,
    required AiConfiguration configuration,
  }) async {
    if (failWrite) throw StateError('write failed');
    if (expected != current) return false;
    final oldReference = current.credentialReference;
    final newReference = configuration.credentialReference;
    if (oldReference != null && oldReference != newReference) {
      pendingCleanup.add(oldReference);
    }
    if (newReference != null) pendingCleanup.remove(newReference);
    current = configuration;
    return true;
  }
}

class _Credentials implements AiCredentialStore {
  final values = <String, String>{};
  int reads = 0;
  int deletes = 0;
  bool failDelete = false;

  @override
  Future<String?> read(String reference) async {
    reads++;
    return values[reference];
  }

  @override
  Future<void> write(String reference, String value) async {
    values[reference] = value;
  }

  @override
  Future<void> delete(String reference) async {
    deletes++;
    if (failDelete) throw StateError('delete failed');
    values.remove(reference);
  }
}

class _Client implements AiTextClient {
  _Client(this.respond);

  final Future<String> Function(AiEndpoint, AiCancellation) respond;
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
  }) => respond(endpoint, cancellation);

  @override
  void dispose() => disposed = true;
}

class _Fixture {
  final configurations = _Configurations();
  final credentials = _Credentials();
  final endpoints = <AiEndpoint>[];
  final clients = <_Client>[];
  Future<String> Function(AiEndpoint, AiCancellation)? respond;

  late final service = createService();

  AiConfigurationService createService() => AiConfigurationService(
    cfgStore: configurations,
    credentials: credentials,
    createClient: () {
      final client = _Client((endpoint, cancellation) {
        endpoints.add(endpoint);
        return respond?.call(endpoint, cancellation) ??
            Future.value(AiConfigurationService.connectionMarker);
      });
      clients.add(client);
      return client;
    },
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  _Fixture fixture, {
  Size size = const Size(900, 800),
  bool dark = false,
  double textScale = 1,
  double keyboardInset = 0,
  AiConfigurationService? service,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: dark
            ? AppTheme.dark(glass: GlassQuality.off)
            : AppTheme.light(glass: GlassQuality.off),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              viewInsets: EdgeInsets.only(bottom: keyboardInset),
            ),
            child: Scaffold(
              body: AiSettingsPage(service: service ?? fixture.service),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillEnabled(WidgetTester tester) async {
  await tester.tap(find.byType(Switch));
  await tester.pump();
  await tester.enterText(
    find.byType(TextField).at(0),
    'https://api.example.com',
  );
  await tester.enterText(find.byType(TextField).at(1), 'test-key');
  await tester.enterText(find.byType(TextField).at(2), 'test-model');
  await tester.pump();
}

Future<void> _tapText(
  WidgetTester tester,
  String text, {
  bool settle = true,
}) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('initial load reads metadata only and AI stays disabled', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _pumpPage(tester, fixture);
    expect(fixture.credentials.reads, 0);
    expect(fixture.clients, isEmpty);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text(_zh.aiOfflineNotice), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, _zh.aiTestConnection),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('three formats show local base and request previews', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _pumpPage(tester, fixture);
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://api.example.com/proxy/v1/v1',
    );
    await tester.pump();
    expect(
      find.text('https://api.example.com/proxy/v1/chat/completions'),
      findsOneWidget,
    );

    await tester.tap(find.byType(DropdownButtonFormField<AiEndpointFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI Responses').last);
    await tester.pumpAndSettle();
    expect(
      find.text('https://api.example.com/proxy/v1/responses'),
      findsOneWidget,
    );

    await tester.tap(find.byType(DropdownButtonFormField<AiEndpointFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Messages').last);
    await tester.pumpAndSettle();
    expect(find.text('https://api.example.com/proxy'), findsOneWidget);
    expect(
      find.text('https://api.example.com/proxy/v1/messages'),
      findsOneWidget,
    );
    expect(fixture.clients, isEmpty);
  });

  testWidgets('test and save use one proof and never refill the key', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _pumpPage(tester, fixture);
    await _fillEnabled(tester);
    await _tapText(tester, _zh.aiTestConnection);
    expect(
      fixture.endpoints.single.requestUri.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(find.text(_zh.aiTestPassed), findsOneWidget);
    await _tapText(tester, _zh.aiSave);
    expect(fixture.configurations.current.enabled, isTrue);
    expect(fixture.configurations.current.credentialReference, isNotNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      isEmpty,
    );
    expect(find.text(_zh.aiSaved), findsOneWidget);
    expect(fixture.clients.single.disposed, isTrue);
  });

  testWidgets('saved key can be reused only with the same service address', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.configurations.current = const AiConfiguration(
      enabled: true,
      address: 'https://api.example.com/v1',
      model: 'model',
      credentialReference: 'old-ref',
    );
    fixture.credentials.values['old-ref'] = 'old-key';
    await _pumpPage(tester, fixture);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('ai-api-key')))
          .controller!
          .text,
      isEmpty,
    );
    await _tapText(tester, _zh.aiTestConnection);
    expect(fixture.credentials.reads, 1);
    await tester.enterText(
      find.byKey(const ValueKey('ai-address')),
      'https://new.example.com',
    );
    await tester.pump();
    expect(find.text(_zh.aiKeyChangedAddressHint), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('ai-test-connection')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'connection error uses localized category without raw service text',
    (tester) async {
      final fixture = _Fixture();
      fixture.respond = (_, _) =>
          throw const AiProtocolException(AiProtocolFailure.authentication);
      await _pumpPage(tester, fixture);
      await _fillEnabled(tester);
      await _tapText(tester, _zh.aiTestConnection);
      expect(find.text(_zh.aiAuthenticationFailed), findsOneWidget);
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .every((text) => !(text.data ?? '').contains('test-key')),
        isTrue,
      );
      expect(fixture.configurations.current, const AiConfiguration());
    },
  );

  testWidgets('editing invalidates proof and suppresses a late success', (
    tester,
  ) async {
    final fixture = _Fixture();
    final reply = Completer<String>();
    fixture.respond = (_, _) => reply.future;
    await _pumpPage(tester, fixture);
    await _fillEnabled(tester);
    await _tapText(tester, _zh.aiTestConnection, settle: false);
    expect(find.text(_zh.aiTesting), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), 'changed-model');
    reply.complete(AiConfigurationService.connectionMarker);
    await tester.pumpAndSettle();
    expect(find.text(_zh.aiTestPassed), findsNothing);
    expect(find.text(_zh.aiNotTested), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, _zh.aiSave))
          .onPressed,
      isNull,
    );
  });

  testWidgets('cancel waits for cleanup and ignores late reply', (
    tester,
  ) async {
    final fixture = _Fixture();
    final reply = Completer<String>();
    fixture.respond = (_, _) => reply.future;
    await _pumpPage(tester, fixture);
    await _fillEnabled(tester);
    await _tapText(tester, _zh.aiTestConnection, settle: false);
    await _tapText(tester, _zh.aiCancelTest, settle: false);
    expect(find.text(_zh.aiTesting), findsOneWidget);
    reply.complete(AiConfigurationService.connectionMarker);
    await tester.pumpAndSettle();
    expect(find.text(_zh.aiTestPassed), findsNothing);
    expect(find.text(_zh.aiCancelled), findsOneWidget);
    expect(fixture.clients.single.disposed, isTrue);
  });

  testWidgets('remote HTTP consent resets on address and format edits', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _pumpPage(tester, fixture);
    await _fillEnabled(tester);
    await tester.enterText(
      find.byType(TextField).at(0),
      'http://remote.example.com/v1',
    );
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, _zh.aiTestConnection),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'http://other.example.com/v1',
    );
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<AiEndpointFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI Responses').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(fixture.clients, isEmpty);
  });

  testWidgets('save failure retains form and previous configuration', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.configurations.failWrite = true;
    await _pumpPage(tester, fixture);
    await _fillEnabled(tester);
    await _tapText(tester, _zh.aiTestConnection);
    await _tapText(tester, _zh.aiSave);
    expect(find.text(_zh.aiSaveFailed), findsOneWidget);
    expect(fixture.configurations.current, const AiConfiguration());
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'test-key',
    );
  });

  testWidgets(
    'clear confirms, removes linked key and keeps manuscripts untouched',
    (tester) async {
      final fixture = _Fixture();
      fixture.configurations.current = const AiConfiguration(
        enabled: true,
        address: 'https://api.example.com/v1',
        model: 'model',
        credentialReference: 'old-ref',
      );
      fixture.credentials.values['old-ref'] = 'old-key';
      await _pumpPage(tester, fixture);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        isEmpty,
      );
      await _tapText(tester, _zh.aiClear);
      expect(find.text(_zh.aiClearDescription), findsOneWidget);
      await tester.tap(find.text(_zh.aiClearConfirm));
      await tester.pumpAndSettle();
      expect(fixture.configurations.current, const AiConfiguration());
      expect(fixture.credentials.values, isEmpty);
      expect(find.text(_zh.aiCleared), findsOneWidget);
    },
  );

  testWidgets('cleanup warning stays visible until retry succeeds', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.configurations.current = const AiConfiguration(
      address: 'https://api.example.com/v1',
      credentialReference: 'old-ref',
    );
    fixture.credentials.values['old-ref'] = 'old-key';
    fixture.credentials.failDelete = true;
    await _pumpPage(tester, fixture);
    await _tapText(tester, _zh.aiClear);
    await tester.tap(find.text(_zh.aiClearConfirm));
    await tester.pumpAndSettle();
    expect(find.text(_zh.aiCleanupWarning), findsOneWidget);
    fixture.credentials.failDelete = false;
    await _tapText(tester, _zh.aiRetryCleanup);
    expect(find.text(_zh.aiCleanupWarning), findsNothing);
    expect(find.text(_zh.aiCleanupDone), findsOneWidget);
  });

  testWidgets('cleanup warning survives reopening and service recreation', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.configurations.current = const AiConfiguration(
      address: 'https://api.example.com/v1',
      credentialReference: 'old-ref',
    );
    fixture.credentials.values['old-ref'] = 'old-key';
    fixture.credentials.failDelete = true;
    await _pumpPage(tester, fixture);
    await _tapText(tester, _zh.aiClear);
    await tester.tap(find.text(_zh.aiClearConfirm));
    await tester.pumpAndSettle();
    expect(find.text(_zh.aiCleanupWarning), findsOneWidget);
    final readsBeforeReopening = fixture.credentials.reads;
    final deletesBeforeReopening = fixture.credentials.deletes;

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpPage(tester, fixture);
    expect(find.text(_zh.aiCleanupWarning), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpPage(tester, fixture, service: fixture.createService());
    expect(find.text(_zh.aiCleanupWarning), findsOneWidget);
    expect(fixture.credentials.reads, readsBeforeReopening);
    expect(fixture.credentials.deletes, deletesBeforeReopening);
    expect(fixture.clients, isEmpty);

    fixture.credentials.failDelete = false;
    await _tapText(tester, _zh.aiRetryCleanup);
    expect(find.text(_zh.aiCleanupWarning), findsNothing);
    expect(find.text(_zh.aiCleanupDone), findsOneWidget);
    expect(fixture.credentials.values, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpPage(tester, fixture, service: fixture.createService());
    expect(find.text(_zh.aiCleanupWarning), findsNothing);
    expect(find.text(_zh.aiRetryCleanup), findsNothing);
  });

  testWidgets(
    'failed load offers reload without presenting empty configuration',
    (tester) async {
      final fixture = _Fixture();
      fixture.configurations.failRead = true;
      await _pumpPage(tester, fixture);
      expect(find.text(_zh.aiLoadFailed), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      fixture.configurations.failRead = false;
      await _tapText(tester, _zh.aiReload);
      expect(find.byType(Switch), findsOneWidget);
    },
  );

  testWidgets(
    'dark narrow page with large text and keyboard stays scrollable',
    (tester) async {
      final fixture = _Fixture();
      await _pumpPage(
        tester,
        fixture,
        size: const Size(320, 720),
        dark: true,
        textScale: 2,
        keyboardInset: 270,
      );
      expect(tester.takeException(), isNull);
      for (final field in find.byType(TextField).evaluate().toList()) {
        await tester.ensureVisible(find.byWidget(field.widget));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.text(_zh.aiSave));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
