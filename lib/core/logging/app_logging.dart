import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Local logging. Never logs manuscript text: log file names, sizes, formats,
/// ids and error kinds only (see docs/01-architecture.md §10).
abstract final class AppLogging {
  static const int maxBytes = 1024 * 1024;

  /// Wires the `logging` package to a rotating file in [directory].
  ///
  /// Returns a [Future] that completes once the sink is attached; writes are
  /// queued and never block the caller.
  static Future<void> init({
    required Directory directory,
    Level level = Level.INFO,
  }) async {
    await directory.create(recursive: true);
    final _RotatingFileSink sink = _RotatingFileSink(
      File(p.join(directory.path, 'bookloom.log')),
    );
    Logger.root.level = level;
    Logger.root.onRecord.listen(sink.add);
  }
}

class _RotatingFileSink {
  _RotatingFileSink(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  void add(LogRecord record) {
    _tail = _tail.then((_) => _write(record)).catchError((Object _) {});
  }

  Future<void> _write(LogRecord record) async {
    try {
      if (await file.exists() && await file.length() > AppLogging.maxBytes) {
        final File previous = File('${file.path}.1');
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      final String level = record.level.name.padRight(7);
      final String line =
          '${record.time.toUtc().toIso8601String()} $level ${record.loggerName} '
          '${record.message}'
          '${record.error == null ? '' : ' | ${record.error}'}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: false);
    } on FileSystemException {
      // Logging must never take the app down.
    }
  }
}
