import 'dart:async';
import 'dart:io';

import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/platform/app_paths.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/platform/permission_access.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/settings/presentation/permissions_page.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_bookloom.dart';

void main() {
  testBookloomWidgets(
    'unknown Android permission state stays unknown and the read action is reachable on a narrow screen',
    (tester) async {
      _setViewport(tester, const Size(320, 640), devicePixelRatio: 2);
      final fixture = await _createPaths(tester);
      _cleanUpPaths(tester, fixture.root);
      final files = _FakeFileService()..pickResults.add(<PickedInput>[]);
      final access = _FakePermissionAccess(
        report: PlatformPermissionReport(
          android: true,
          systemCheckAvailable: false,
          runtimePermissions: const <RuntimePermissionCheck>[],
          declaresInternet: false,
          declaresBroadStorage: false,
        ),
      );
      await _pumpPermissionsPage(
        tester,
        paths: fixture.paths,
        files: files,
        access: access,
        textScale: 2,
      );

      final l10n = lookupAppLocalizations(const Locale('zh'));
      await _pumpUntil(
        tester,
        () =>
            find.text(l10n.permissionsSystemUnavailable).evaluate().isNotEmpty,
      );
      expect(find.text(l10n.permissionsSystemUnavailable), findsOneWidget);
      expect(find.text(l10n.permissionsNoRuntime), findsNothing);
      expect(find.textContaining(l10n.permissionsGranted), findsNothing);
      expect(tester.takeException(), isNull);

      final readAction = find.text(l10n.permissionsReadAction);
      await tester.ensureVisible(readAction);
      await tester.pump();
      final buttonBounds = tester.getRect(readAction);
      expect(buttonBounds.top, greaterThanOrEqualTo(0));
      expect(buttonBounds.bottom, lessThanOrEqualTo(640));
      await tester.tap(readAction);
      await _pumpUntil(
        tester,
        () => find.text(l10n.permissionsCancelled).evaluate().isNotEmpty,
      );
      expect(find.text(l10n.permissionsCancelled), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'file access check distinguishes picker cancellation from read failure and releases selected inputs',
    (tester) async {
      _setViewport(tester, const Size(900, 800));
      final fixture = await _createPaths(tester);
      _cleanUpPaths(tester, fixture.root);
      final files = _FakeFileService();
      final input = PickedInput(
        name: 'unreadable.txt',
        size: 1,
        openRead: () =>
            Stream<List<int>>.error(StateError('provider denied read')),
        onRelease: () async {
          files.releaseCount++;
        },
      );
      files.pickResults.addAll(<List<PickedInput>>[
        <PickedInput>[],
        <PickedInput>[input],
      ]);
      await _pumpPermissionsPage(
        tester,
        paths: fixture.paths,
        files: files,
        access: _desktopAccess(),
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      final readAction = find.text(l10n.permissionsReadAction);

      await tester.ensureVisible(readAction);
      await tester.pump();
      await tester.tap(readAction);
      await _pumpUntil(
        tester,
        () => find.text(l10n.permissionsCancelled).evaluate().isNotEmpty,
      );
      expect(find.text(l10n.permissionsCancelled), findsOneWidget);
      expect(files.releaseCount, 0);

      await tester.ensureVisible(readAction);
      await tester.pump();
      await tester.tap(readAction);
      await _pumpUntil(
        tester,
        () => find.text(l10n.permissionsReadFailure).evaluate().isNotEmpty,
      );
      expect(find.text(l10n.permissionsReadFailure), findsOneWidget);
      expect(find.text(l10n.permissionsCancelled), findsNothing);
      expect(files.releaseCount, 1);
      expect(files.clearTemporaryFilesCount, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'an OEM-reported app-list permission is shown as optional and not granted',
    (tester) async {
      _setViewport(tester, const Size(900, 800));
      final fixture = await _createPaths(tester);
      _cleanUpPaths(tester, fixture.root);
      final files = _FakeFileService();
      await _pumpPermissionsPage(
        tester,
        paths: fixture.paths,
        files: files,
        access: _FakePermissionAccess(
          report: PlatformPermissionReport(
            android: true,
            systemCheckAvailable: true,
            runtimePermissions: const <RuntimePermissionCheck>[
              RuntimePermissionCheck(
                'com.android.permission.GET_INSTALLED_APPS',
                '读取设备应用列表',
                false,
              ),
            ],
            declaresInternet: false,
            declaresBroadStorage: false,
          ),
        ),
      );

      final l10n = lookupAppLocalizations(const Locale('zh'));
      await _pumpUntil(
        tester,
        () => find
            .text('读取设备应用列表 · ${l10n.permissionsNotGranted}')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.text('读取设备应用列表 · ${l10n.permissionsNotGranted}'),
        findsOneWidget,
      );
      expect(find.text(l10n.permissionsRuntimePolicy), findsOneWidget);
      expect(find.text(l10n.permissionsRuntimeNotRequired), findsOneWidget);
      expect(find.text(l10n.permissionsNoRuntime), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'save check keeps its cache file until the native result and cleans only its own file on cancel and success',
    (tester) async {
      _setViewport(tester, const Size(900, 800));
      final fixture = await _createPaths(tester);
      _cleanUpPaths(tester, fixture.root);
      final keptFile = File('${fixture.paths.cache.path}/user-kept.txt');
      await tester.runAsync(() async {
        await keptFile.writeAsString('keep this file');
      });
      final files = _FakeFileService();
      await _pumpPermissionsPage(
        tester,
        paths: fixture.paths,
        files: files,
        access: _desktopAccess(),
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      final saveAction = find.text(l10n.permissionsSaveAction);

      await tester.ensureVisible(saveAction);
      await tester.pump();
      await tester.tap(saveAction);
      await _pumpUntil(tester, () => files.preparedFiles.length == 1);
      final cancelledFile = files.preparedFiles[0];
      expect(await _runIo(tester, cancelledFile.exists), isTrue);
      files.pendingSaves[0].complete(const SaveCancelled());
      await _pumpUntil(
        tester,
        () => find.text(l10n.permissionsCancelled).evaluate().isNotEmpty,
      );
      expect(find.text(l10n.permissionsCancelled), findsOneWidget);
      expect(await _runIo(tester, cancelledFile.exists), isFalse);
      expect(await _runIo(tester, cancelledFile.parent.exists), isFalse);
      expect(await _runIo(tester, keptFile.readAsString), 'keep this file');

      await tester.ensureVisible(saveAction);
      await tester.pump();
      await tester.tap(saveAction);
      await _pumpUntil(tester, () => files.preparedFiles.length == 2);
      final savedFile = files.preparedFiles[1];
      expect(await _runIo(tester, savedFile.exists), isTrue);
      files.pendingSaves[1].complete(
        SaveSaved(Uri.parse('content://saved/test-file')),
      );
      await _pumpUntil(
        tester,
        () => find.text(l10n.permissionsSaveSuccess).evaluate().isNotEmpty,
      );
      expect(find.text(l10n.permissionsSaveSuccess), findsOneWidget);
      expect(await _runIo(tester, savedFile.exists), isFalse);
      expect(await _runIo(tester, savedFile.parent.exists), isFalse);
      expect(await _runIo(tester, keptFile.readAsString), 'keep this file');
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakePermissionAccess extends PermissionAccess {
  _FakePermissionAccess({required this.report})
    : super(isAndroid: () => report.android);

  final PlatformPermissionReport report;

  @override
  Future<List<DirectoryAccessCheck>> checkDirectories(AppPaths paths) async =>
      const <DirectoryAccessCheck>[];

  @override
  Future<PlatformPermissionReport> inspectSystemPermissions() async => report;
}

class _FakeFileService implements FileService {
  final List<List<PickedInput>> pickResults = <List<PickedInput>>[];
  final List<File> preparedFiles = <File>[];
  final List<Completer<SaveOutcome>> pendingSaves = <Completer<SaveOutcome>>[];
  int _pickIndex = 0;
  int clearTemporaryFilesCount = 0;
  int releaseCount = 0;

  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const <String>['txt', 'epub', 'docx'],
  }) async {
    if (_pickIndex >= pickResults.length) return <PickedInput>[];
    return pickResults[_pickIndex++];
  }

  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) {
    preparedFiles.add(prepared);
    final completer = Completer<SaveOutcome>();
    pendingSaves.add(completer);
    return completer.future;
  }

  @override
  Future<void> clearTemporaryFiles() async {
    clearTemporaryFilesCount++;
  }
}

_FakePermissionAccess _desktopAccess() => _FakePermissionAccess(
  report: PlatformPermissionReport(
    android: false,
    systemCheckAvailable: false,
    runtimePermissions: const <RuntimePermissionCheck>[],
    declaresInternet: false,
    declaresBroadStorage: false,
  ),
);

Future<void> _pumpPermissionsPage(
  WidgetTester tester, {
  required AppPaths paths,
  required _FakeFileService files,
  required _FakePermissionAccess access,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPathsProvider.overrideWithValue(paths),
        fileServiceProvider.overrideWithValue(files),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(glass: GlassQuality.off),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: PermissionsPage(access: access),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<({AppPaths paths, Directory root})> _createPaths(
  WidgetTester tester,
) async {
  final fixture = await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('permissions-page-');
    final support = Directory('${root.path}/support');
    final books = Directory('${root.path}/books');
    final logs = Directory('${root.path}/logs');
    final cache = Directory('${root.path}/cache');
    await Future.wait(<Future<void>>[
      support.create(),
      books.create(),
      logs.create(),
      cache.create(),
    ]);
    return (
      root: root,
      paths: AppPaths(support: support, books: books, logs: logs, cache: cache),
    );
  });
  if (fixture == null) throw StateError('Could not create permissions fixture');
  return fixture;
}

void _cleanUpPaths(WidgetTester tester, Directory root) {
  addTearDown(() async {
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });
}

void _setViewport(
  WidgetTester tester,
  Size logicalSize, {
  double devicePixelRatio = 1,
}) {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = Size(
    logicalSize.width * devicePixelRatio,
    logicalSize.height * devicePixelRatio,
  );
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = const <Locale>[Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.pump(Duration.zero);
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(condition(), isTrue, reason: 'Permissions page did not reach state');
}

Future<T> _runIo<T>(WidgetTester tester, Future<T> Function() operation) async {
  final result = await tester.runAsync(operation);
  if (result == null) throw StateError('Real I/O operation did not complete');
  return result;
}
