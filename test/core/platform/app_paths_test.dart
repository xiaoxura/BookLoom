import 'dart:io';

import 'package:bookloom/core/platform/app_paths.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'OS directory aliases open an empty shelf without weakening book paths',
    () async {
      final root = await Directory.systemTemp.createTemp('bookloom-paths-');
      final actual = await Directory(p.join(root.path, 'actual')).create();
      final alias = Link(p.join(root.path, 'android-user-zero'));
      await alias.create(actual.path);
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'getApplicationSupportDirectory' => p.join(alias.path, 'files'),
          'getApplicationCacheDirectory' => p.join(alias.path, 'cache'),
          _ => throw MissingPluginException(call.method),
        };
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await root.delete(recursive: true);
      });

      final paths = await AppPaths.resolve();
      expect(paths.support.path, p.join(actual.path, 'files'));
      expect(paths.cache.path, p.join(actual.path, 'cache'));
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repository = BookRepository(db, paths.support);
      expect(await repository.listSummaries(), isEmpty);
      expect(await repository.watchSummaries().first, isEmpty);

      // User-controlled book links remain forbidden after the trusted OS root
      // has been canonicalized.
      final book = await Directory(p.join(paths.books.path, 'safe')).create();
      await Link(p.join(book.path, 'source.txt'))
          .create(p.join(root.path, 'outside.txt'));
      await expectLater(
        repository.files.resolveStoredPath('safe', 'books/safe/source.txt'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
