import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolved, platform-correct app directories.
///
/// `core/platform` is the only place allowed to know where files live; the rest
/// of the app asks for [AppPaths].
class AppPaths {
  const AppPaths({
    required this.support,
    required this.books,
    required this.logs,
    required this.cache,
  });

  /// Root for app-owned data that must survive restarts.
  final Directory support;

  /// One subdirectory per book: `<books>/<bookId>/source.txt` etc.
  final Directory books;

  final Directory logs;
  final Directory cache;

  File get databaseFile => File(p.join(support.path, 'bookloom.sqlite'));

  /// Resolves and creates the directories. Safe to call once at startup.
  static Future<AppPaths> resolve() async {
    // The OS may return an alias (Android's /data/user/0 is a symlink inside
    // the app's mount namespace). Establish trusted, canonical roots before
    // the storage layer rejects links in book-controlled paths.
    final Directory platformSupport = await getApplicationSupportDirectory();
    final Directory platformCache = await getApplicationCacheDirectory();
    await platformSupport.create(recursive: true);
    await platformCache.create(recursive: true);
    final support = Directory(await platformSupport.resolveSymbolicLinks());
    final cache = Directory(await platformCache.resolveSymbolicLinks());
    final AppPaths paths = AppPaths(
      support: support,
      books: Directory(p.join(support.path, 'books')),
      logs: Directory(p.join(support.path, 'logs')),
      cache: cache,
    );
    await paths.books.create(recursive: true);
    await paths.logs.create(recursive: true);
    return paths;
  }

  Directory bookDir(String bookId) => Directory(p.join(books.path, bookId));
}
