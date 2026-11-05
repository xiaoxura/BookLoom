import 'dart:io';

import 'package:bookloom/core/platform/app_paths.dart';
import 'package:bookloom/core/platform/permission_access.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'checks only app directories and removes each successful probe',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bookloom-permissions-',
      );
      addTearDown(() => root.delete(recursive: true));
      final paths = await _pathsIn(root);
      await paths.support.create();
      await paths.books.create();
      await paths.cache.create();
      final existing = File(p.join(paths.books.path, 'existing.txt'));
      await existing.writeAsString('keep this file');

      final checks = await PermissionAccess(isAndroid: () => false)
          .checkDirectories(paths);

      expect(checks.map((check) => check.target), AccessDirectory.values);
      for (final check in checks) {
        expect(check.readable, isTrue);
        expect(check.writable, isTrue);
        expect(check.failureKind, isNull);
      }
      expect(await existing.readAsString(), 'keep this file');
      for (final directory in [paths.support, paths.books, paths.cache]) {
        final entries = await directory.list(followLinks: false).toList();
        expect(
          entries.where(
            (entry) => p.basename(entry.path).startsWith('.bookloom-access-'),
          ),
          isEmpty,
        );
      }
    },
  );

  test('missing, file, and link targets cannot report access', () async {
    final root = await Directory.systemTemp.createTemp('bookloom-permissions-');
    addTearDown(() => root.delete(recursive: true));
    final actual = await Directory(p.join(root.path, 'actual')).create();
    final supportLink = Link(p.join(root.path, 'support'));
    await supportLink.create(actual.path);
    final cacheFile = File(p.join(root.path, 'cache'));
    await cacheFile.writeAsString('not a directory');
    final paths = AppPaths(
      support: Directory(supportLink.path),
      books: Directory(p.join(root.path, 'missing-books')),
      logs: Directory(p.join(root.path, 'logs')),
      cache: Directory(cacheFile.path),
    );

    final checks = await PermissionAccess(isAndroid: () => false)
        .checkDirectories(paths);

    expect(checks.map((check) => check.failureKind), [
      'not_directory',
      'missing',
      'not_directory',
    ]);
    for (final check in checks) {
      expect(check.readable, isFalse);
      expect(check.writable, isFalse);
    }
    expect(await actual.list().toList(), isEmpty);
    expect(await cacheFile.readAsString(), 'not a directory');
  });

  test('Android inspection preserves granted and denied permissions', () async {
    const channel = MethodChannel('bookloom-permissions-inspection-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'inspectPermissions');
      return {
        'runtimePermissions': [
          {
            'name': 'android.permission.CAMERA',
            'label': 'Camera',
            'granted': true,
          },
          {
            'name': 'android.permission.RECORD_AUDIO',
            'label': 'Microphone',
            'granted': false,
          },
        ],
        'declaresInternet': false,
        'declaresBroadStorage': false,
      };
    });

    final report = await PermissionAccess(
      channel: channel,
      isAndroid: () => true,
    ).inspectSystemPermissions();

    expect(report.android, isTrue);
    expect(report.systemCheckAvailable, isTrue);
    expect(report.runtimePermissions.map((permission) => permission.name), [
      'android.permission.CAMERA',
      'android.permission.RECORD_AUDIO',
    ]);
    expect(report.runtimePermissions.map((permission) => permission.label), [
      'Camera',
      'Microphone',
    ]);
    expect(report.runtimePermissions.map((permission) => permission.granted), [
      true,
      false,
    ]);
    expect(report.declaresInternet, isFalse);
    expect(report.declaresBroadStorage, isFalse);
  });

  test(
    'unknown Android inspection and failed Settings launch stay unavailable',
    () async {
      const channel = MethodChannel('bookloom-permissions-failure-test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'inspectPermissions') {
          return {
            'runtimePermissions': [
              {'name': 'android.permission.CAMERA', 'label': 'Camera'},
            ],
            'declaresInternet': false,
            'declaresBroadStorage': false,
          };
        }
        if (call.method == 'openSystemSettings') {
          throw PlatformException(code: 'no_settings');
        }
        throw MissingPluginException(call.method);
      });
      final access = PermissionAccess(channel: channel, isAndroid: () => true);

      final report = await access.inspectSystemPermissions();
      expect(report.android, isTrue);
      expect(report.systemCheckAvailable, isFalse);
      expect(report.runtimePermissions, isEmpty);
      expect(await access.openSystemSettings(), isFalse);

      messenger.setMockMethodCallHandler(channel, null);
      expect(
        (await access.inspectSystemPermissions()).systemCheckAvailable,
        isFalse,
      );
    },
  );

  test('desktop never calls the Android bridge', () async {
    const channel = MethodChannel('bookloom-permissions-desktop-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      fail('Desktop called native method ${call.method}');
    });
    final access = PermissionAccess(channel: channel, isAndroid: () => false);

    final report = await access.inspectSystemPermissions();
    expect(report.android, isFalse);
    expect(report.systemCheckAvailable, isFalse);
    expect(report.runtimePermissions, isEmpty);
    expect(await access.openSystemSettings(), isFalse);
  });
}

Future<AppPaths> _pathsIn(Directory root) async {
  return AppPaths(
    support: Directory(p.join(root.path, 'support')),
    books: Directory(p.join(root.path, 'books')),
    logs: Directory(p.join(root.path, 'logs')),
    cache: Directory(p.join(root.path, 'cache')),
  );
}
