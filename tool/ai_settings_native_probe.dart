import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/app/ai_providers.dart';
import 'package:bookloom/app/app.dart';
import 'package:bookloom/app/bootstrap.dart';
import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/router.dart';
import 'package:bookloom/app/window/window_controls.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/core/storage/settings_store.dart';
import 'package:bookloom/features/settings/data/ai_configuration_store.dart';
import 'package:bookloom/features/settings/data/secure_ai_credential_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as paths;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = Platform.environment;
  final rootPath = environment['BOOKLOOM_NATIVE_TEST_ROOT'];
  if (!Platform.isLinux ||
      rootPath == null ||
      environment['BOOKLOOM_PRIVATE_KEYRING_ROOT'] != rootPath ||
      environment['BOOKLOOM_EXPECTED_TEST_BUS'] == null ||
      environment['DBUS_SESSION_BUS_ADDRESS'] !=
          environment['BOOKLOOM_EXPECTED_TEST_BUS'] ||
      !await File(paths.join(rootPath, '.bookloom-owned')).exists()) {
    throw StateError(
      'An owned Linux root and private session bus are required.',
    );
  }
  for (final entry in <String, String>{
    'XDG_DATA_HOME': 'data',
    'XDG_CACHE_HOME': 'cache',
    'XDG_CONFIG_HOME': 'config',
    'XDG_RUNTIME_DIR': 'runtime',
  }.entries) {
    if (environment[entry.key] != paths.join(rootPath, entry.value)) {
      throw StateError('Refusing non-test application directories.');
    }
  }
  final root = Directory(rootPath);
  WindowControls.configure();
  final boot = await bootstrap();
  if (!paths.isWithin(root.path, boot.paths.support.path)) {
    throw StateError('Application support escaped the owned root.');
  }
  final container = ProviderContainer(
    overrides: [
      appPathsProvider.overrideWithValue(boot.paths),
      databaseProvider.overrideWithValue(boot.database),
      initialAppearanceProvider.overrideWithValue(
        const Appearance(themeMode: AppThemeMode.light),
      ),
    ],
  );
  runApp(
    UncontrolledProviderScope(container: container, child: const BookloomApp()),
  );
  final result = <String, Object?>{
    'usesIntegrationTestBinding': false,
    'usesTestTextInput': false,
    'usesDailyDatabase': false,
    'usesDailyKeyring': false,
    'usesRealCloudService': false,
  };
  HttpServer? server;
  try {
    final window = WindowManager.instance.getCurrent();
    if (window == null) throw StateError('No owned native window.');
    window.title = 'Bookloom AI isolated probe';
    window.minimumSize = const Size(820, 600).toNative();
    window.setSize(const Size(1280, 900).toNative(), false);
    window.show();
    window.focus();
    await _settle();
    final service = container.read(aiConfigurationServiceProvider);
    final initial = await service.load();
    _require(initial == const AiConfiguration(), 'Default must be disabled.');
    container.read(routerProvider).go('/settings/ai');
    await _waitForField();
    await _phase(root, 'initial');
    var requests = 0;
    var fixtureOnly = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      fixtureOnly =
          fixtureOnly &&
          request.method == 'POST' &&
          request.uri.path == '/v1/chat/completions' &&
          request.headers.value('authorization') ==
              'Bearer bookloom-owned-synthetic-key' &&
          body['messages'].length == 2 &&
          body['messages'][1]['content'] ==
              'Reply with exactly BOOKLOOM_CONNECTION_OK. No other text.';
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'object': 'chat.completion',
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {
                'role': 'assistant',
                'content': 'BOOKLOOM_CONNECTION_OK',
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    final candidate = AiConfiguration(
      enabled: true,
      address: 'http://127.0.0.1:${server.port}',
      model: 'owned-loopback-fixture',
    );
    const syntheticKey = 'bookloom-owned-synthetic-key';
    final proof = await service.testConnection(
      configuration: candidate,
      expected: initial,
      apiKey: syntheticKey,
    );
    final saved = await service.save(
      configuration: candidate,
      expected: initial,
      apiKey: syntheticKey,
      proof: proof,
    );
    final reference = saved.configuration.credentialReference;
    _require(reference != null && saved.cleanupWarning == null, 'Save failed.');
    final credentials = SecureAiCredentialStore();
    _require(
      await credentials.read(reference!) == syntheticKey,
      'Private keyring round-trip failed.',
    );
    final metadata = await SettingsStore(boot.database)
        .read(AiSettingsConfigurationStore.key);
    _require(
      metadata != null && !metadata.contains(syntheticKey),
      'Metadata contains a credential.',
    );
    result['secureStoreRoundTrip'] = true;
    result['metadataContainsNoKey'] = true;
    _require(
      (await service.pendingCleanupWarnings).isEmpty,
      'Committed credential must not be queued for deletion.',
    );
    container.read(routerProvider).go('/settings');
    await _settle();
    container.read(routerProvider).go('/settings/ai');
    await _waitForField();
    _require(
      _passwordField().controller.text.isEmpty,
      'Saved credentials must never prefill the form.',
    );
    _require(requests == 1 && fixtureOnly, 'Unexpected network request.');
    result['reopenDoesNotRequest'] = true;
    result['keyNotPrefilled'] = true;
    result['connectionFixtureOnly'] = true;
    await _phase(root, 'saved');
    await container
        .read(appearanceProvider.notifier)
        .setThemeMode(AppThemeMode.dark);
    await _settle();
    await _phase(root, 'dark');
    window.setSize(const Size(820, 900).toNative(), false);
    await _settle();
    result['narrowLogicalWidth'] =
        WidgetsBinding
            .instance
            .platformDispatcher
            .views
            .first
            .physicalSize
            .width /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    await _phase(root, 'narrow');
    final cleared = await service.clear(expected: saved.configuration);
    _require(
      cleared.configuration == const AiConfiguration() &&
          cleared.cleanupWarning == null &&
          await credentials.read(reference) == null,
      'Clear failed.',
    );
    result['secureStoreCleared'] = true;
    _require(
      (await service.pendingCleanupWarnings).isEmpty,
      'Successful cleanup must remove its technical reference.',
    );
    result['cleanupQueueEmpty'] = true;
    result['passed'] = true;
  } on Object catch (error) {
    result['passed'] = false;
    result['errorType'] = error.runtimeType.toString();
  } finally {
    await server?.close(force: true);
    await File(paths.join(root.path, 'native-ai-result.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    container.dispose();
    await boot.database.close();
    WindowControls.close();
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

EditableText _passwordField() {
  EditableText? field;
  void visit(Element element, [bool inside = false]) {
    final matching =
        inside || element.widget.key == const ValueKey('ai-api-key');
    if (matching && element.widget is EditableText) {
      field = element.widget as EditableText;
    }
    element.visitChildren((child) => visit(child, matching));
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  if (field == null) throw StateError('AI credential field is not rendered.');
  return field!;
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 650));
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _waitForField() async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await _settle();
    try {
      _passwordField();
      return;
    } on StateError {
      continue;
    }
  }
  throw StateError('AI settings did not load.');
}

Future<void> _phase(Directory root, String phase) async {
  await _settle();
  await File(paths.join(root.path, 'phase-$phase.ready'))
      .writeAsString('ready');
  final acknowledgement = File(paths.join(root.path, 'phase-$phase.ack'));
  for (var attempt = 0; attempt < 300; attempt++) {
    if (await acknowledgement.exists()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Owned screenshot acknowledgement timed out.');
}
