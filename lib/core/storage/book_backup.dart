import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:archive/archive_io.dart' as archive_io;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../errors/app_failure.dart';
import '../io/input_limits.dart';
import '../model/layout_options.dart';
import '../platform/background_jobs.dart';
import '../text/word_count.dart';
import 'app_database.dart';
import 'book_repository.dart';

/// Backup format 2 keeps the index small and streams data records separately.
/// Every ordinary record is at most 2 MiB; large text blocks use chunks.
const int _recordLimit = 2 * 1024 * 1024;
// JSON can expand a control character to six ASCII bytes ("\\u0001").
const int _textChunkLimit = 256 * 1024;
const int _libraryLimit = 8 * 1024 * 1024;

enum RestoreConflictPolicy { copy, skip, overwrite }

class RestoreBookPreview {
  const RestoreBookPreview({
    required this.id,
    required this.title,
    required this.author,
    required this.chapterCount,
    required this.wordCount,
    required this.hasSource,
    required this.assetCount,
  });

  final String id;
  final String title;
  final String author;
  final int chapterCount;
  final int wordCount;
  final bool hasSource;
  final int assetCount;
}

class RestoreApplyResult {
  const RestoreApplyResult({
    required this.restoredIds,
    required this.skippedIds,
    required this.cancelledIds,
    required this.failures,
    this.cleanupWarning,
  });

  /// A multi-book restore commits one book at a time; previous successes remain
  /// if a later book fails. The UI must show [failures] explicitly.
  final List<String> restoredIds;
  final List<String> skippedIds;

  /// Books left untouched when cancellation stops a multi-book restore.
  final List<String> cancelledIds;
  final Map<String, String> failures;

  /// A committed restore remains successful if its scratch sweep needs a
  /// later retry; surface this warning rather than reporting a false rollback.
  final String? cleanupWarning;
}

class RestorePreview {
  RestorePreview._(
    this._owner,
    this._directory,
    this._database, {
    required this.books,
    required this.formatVersion,
    required this.includesSources,
    required this.declaredBytes,
    required this.actualBytes,
    required this.estimatedRequiredBytes,
  });

  final BookBackup _owner;
  final Directory _directory;
  final AppDatabase _database;
  final List<RestoreBookPreview> books;
  final int formatVersion;
  final bool includesSources;
  final int declaredBytes;
  final int actualBytes;

  /// Approximate peak footprint including the input ZIP, extracted entries,
  /// staged SQLite, target DB growth, and restored resource copies. SQLite
  /// WAL and filesystem overhead can make actual free-space needs higher.
  final int estimatedRequiredBytes;
  bool _disposed = false;

  /// Discard a preview when the user cancels before applying it.
  Future<void> dispose() => _owner._dispose(this);
}

/// Exports the current library state without copying an active SQLite file.
/// [scratchDirectory] is an application-owned cache or leased JobCache folder.
/// The caller pauses affected editing sessions before export or restore.
class BookBackup {
  BookBackup(
    this.repository, {
    required this.scratchDirectory,
    required this.appVersion,
    BackgroundJobs? jobs,
  }) : jobs = jobs ?? BackgroundJobs();

  final BookRepository repository;
  final Directory scratchDirectory;
  final String appVersion;
  final BackgroundJobs jobs;
  final Set<RestorePreview> _previews = <RestorePreview>{};
  static const Uuid _uuid = Uuid();
  bool _activeOperation = false;
  bool _cancelRequested = false;
  bool _workerActive = false;
  bool _isCommitting = false;
  int _jobRevision = 0;

  /// True only while one book's database transaction is being committed.
  bool get isCommitting => _isCommitting;

  /// Stops ZIP work immediately. Restore finishes its current DB transaction
  /// before reporting remaining books as [RestoreApplyResult.cancelledIds].
  void cancel() {
    if (!_activeOperation) return;
    _cancelRequested = true;
    if (_workerActive) jobs.cancelActive();
  }

  void _beginOperation() {
    if (_activeOperation) {
      throw StateError('Another backup operation is active');
    }
    _activeOperation = true;
    _cancelRequested = false;
  }

  void _checkCancelled() {
    if (_cancelRequested) throw const TaskCancelled();
  }

  Future<R> _runWorker<T, R>(
    T input,
    FutureOr<R> Function(T, void Function(double, String)) worker,
  ) async {
    _checkCancelled();
    if (jobs.isBusy) {
      throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
    }
    _workerActive = true;
    try {
      return await jobs.run<T, R>(
        input,
        worker,
        revision: ++_jobRevision,
        timeout: const Duration(hours: 2),
      );
    } finally {
      _workerActive = false;
    }
  }

  Future<File> exportBooks(
    List<String> ids,
    String outputPath, {
    bool includeSources = true,
  }) async {
    _beginOperation();
    try {
      return await _exportBooks(
        ids,
        outputPath,
        includeSources: includeSources,
      );
    } finally {
      _activeOperation = false;
    }
  }

  Future<File> _exportBooks(
    List<String> ids,
    String outputPath, {
    required bool includeSources,
  }) async {
    // The repository completes pending-operation recovery before its public
    // queries. Direct page reads below must not race that startup sweep.
    await repository.listSummaries();
    _checkCancelled();
    if (ids.isEmpty || ids.toSet().length != ids.length) {
      throw ArgumentError.value(ids, 'ids', 'Expected distinct book IDs');
    }
    if (appVersion.trim().isEmpty) {
      throw ArgumentError.value(appVersion, 'appVersion');
    }
    for (final id in ids) {
      repository.files.checkId(id);
    }
    final output = File(p.normalize(p.absolute(outputPath)));
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('Backup target already exists');
    }
    final operation = await _createScratch('backup-export');
    final temporaryOutput = File('${output.path}.partial-${_uuid.v4()}');
    try {
      final records = File(p.join(operation.path, 'records.ndjson'));
      final writer = await records.open(mode: FileMode.write);
      final resources = <_ZipInput>[];
      final index = <Map<String, Object?>>[];
      try {
        for (final id in ids) {
          _checkCancelled();
          await _exportBook(id, writer, resources, index, includeSources);
        }
        await writer.flush();
      } finally {
        await writer.close();
      }
      final library = File(p.join(operation.path, 'library.json'));
      final libraryBytes = utf8.encode(
        jsonEncode(<String, Object?>{'books': index}),
      );
      if (libraryBytes.length > _libraryLimit) {
        throw const FormatException('Backup book index exceeds 8 MiB');
      }
      await library.writeAsBytes(libraryBytes, flush: true);
      final payloadBytes =
          await records.length() +
          libraryBytes.length +
          resources.fold<int>(0, (total, item) => total + item.byteSize);
      final manifest = File(p.join(operation.path, 'manifest.json'));
      await manifest.writeAsString(
        jsonEncode(<String, Object?>{
          'format': 'bookloom-backup',
          'formatVersion': 2,
          'appVersion': appVersion,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'bookCount': ids.length,
          'includesSources': includeSources,
          'payloadBytes': payloadBytes,
        }),
        flush: true,
      );
      final inputs = <_ZipInput>[
        _ZipInput('manifest.json', manifest.path, await manifest.length()),
        _ZipInput('library.json', library.path, libraryBytes.length),
        _ZipInput('records.ndjson', records.path, await records.length()),
        ...resources,
      ];
      await _runWorker<_ZipPlan, bool>(
        _ZipPlan(temporaryOutput.path, inputs),
        _zipWorker,
      );
      _checkCancelled();
      if (await FileSystemEntity.type(output.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('Backup target appeared during export');
      }
      return await temporaryOutput.rename(output.path);
    } finally {
      if (await temporaryOutput.exists()) await temporaryOutput.delete();
      await _deleteScratch(operation);
    }
  }

  Future<void> _exportBook(
    String id,
    RandomAccessFile writer,
    List<_ZipInput> resources,
    List<Map<String, Object?>> index,
    bool includeSources,
  ) async {
    _checkCancelled();
    final db = repository.db;
    final book = await (db.select(
      db.books,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (book == null) throw StateError('Book $id does not exist');
    final structural = await repository.loadBook(id);
    if (structural == null) throw StateError('Book $id disappeared');
    final chapters = await (db.select(
      db.chapters,
    )..where((table) => table.bookId.equals(id))).get();
    final chapterById = <String, Chapter>{
      for (final chapter in chapters) chapter.id: chapter,
    };
    final source = includeSources ? await repository.loadSource(id) : null;
    final referencedAssets = <String>{
      if (structural.coverAssetId != null) structural.coverAssetId!,
      if (structural.layout.embeddedFontAssetId != null)
        structural.layout.embeddedFontAssetId!,
    };
    final imageRefs = await db
        .customSelect(
          '''
      SELECT DISTINCT b.asset_id FROM blocks b
      JOIN chapters c ON c.id = b.chapter_id
      WHERE c.book_id = ? AND b.kind = 'image' AND b.asset_id IS NOT NULL
      ''',
          variables: <drift.Variable<Object>>[drift.Variable<String>(id)],
        )
        .get();
    for (final row in imageRefs) {
      referencedAssets.add(row.read<String>('asset_id'));
    }
    final assets = <Asset>[];
    final assetIds = referencedAssets.toList();
    for (var offset = 0; offset < assetIds.length; offset += 400) {
      _checkCancelled();
      final end = offset + 400 < assetIds.length
          ? offset + 400
          : assetIds.length;
      assets.addAll(
        await (db.select(db.assets)..where(
              (table) =>
                  table.bookId.equals(id) &
                  table.id.isIn(assetIds.sublist(offset, end)),
            ))
            .get(),
      );
    }
    if (assets.length != referencedAssets.length) {
      throw FormatException('Book $id references a missing or foreign asset');
    }
    index.add(<String, Object?>{
      'id': id,
      'title': book.title,
      'author': book.author,
      'chapterCount': chapters.length,
      'wordCount': book.wordCount,
      'hasSource': source != null,
      'assetCount': assets.length,
    });
    await _writeRecord(writer, 'book', book.toJson());
    if (source != null) {
      _checkCancelled();
      final file = await repository.resolveSource(source);
      final extension = p.extension(file.path).replaceFirst('.', '');
      if (!const <String>{'txt', 'epub', 'docx'}.contains(extension)) {
        throw const FormatException('Unsupported source extension');
      }
      final entry = 'sources/$id/${source.id}.$extension';
      await _verifyResource(
        file,
        source.byteSize,
        source.sha256,
        checkCancelled: _checkCancelled,
      );
      resources.add(_ZipInput(entry, file.path, source.byteSize));
      await _writeRecord(writer, 'source', source.toJson(), entry: entry);
    }
    for (final asset in assets) {
      _checkCancelled();
      final file = await repository.resolveAsset(asset);
      final extension = p.extension(file.path).replaceFirst('.', '');
      if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)) {
        throw const FormatException('Unsupported asset extension');
      }
      final entry = 'assets/$id/${asset.id}.$extension';
      await _verifyResource(
        file,
        asset.byteSize,
        asset.sha256,
        checkCancelled: _checkCancelled,
      );
      resources.add(_ZipInput(entry, file.path, asset.byteSize));
      await _writeRecord(writer, 'asset', asset.toJson(), entry: entry);
    }
    for (final structure in structural.chapters) {
      _checkCancelled();
      final chapter = chapterById[structure.id]!;
      await _writeRecord(writer, 'chapter', chapter.toJson());
      var offset = 0;
      while (true) {
        final page =
            await (db.select(db.blocks)
                  ..where((table) => table.chapterId.equals(chapter.id))
                  ..orderBy(<drift.OrderingTerm Function($BlocksTable)>[
                    (table) => drift.OrderingTerm.asc(table.sortOrder),
                    (table) => drift.OrderingTerm.asc(table.id),
                  ])
                  ..limit(128, offset: offset))
                .get();
        if (page.isEmpty) break;
        for (final block in page) {
          _checkCancelled();
          await _writeBlock(writer, block, _checkCancelled);
        }
        offset += page.length;
      }
    }
  }

  static Future<void> _writeBlock(
    RandomAccessFile writer,
    Block block,
    void Function() checkCancelled,
  ) async {
    final content = block.content;
    if (content == null || content.length < 200000) {
      await _writeRecord(writer, 'block', block.toJson());
      return;
    }
    final chunkCount = _textChunks(content).length;
    final data = block.copyWith(content: const drift.Value(null)).toJson();
    await _writeRecord(writer, 'block', data, chunkCount: chunkCount);
    var index = 0;
    for (final chunk in _textChunks(content)) {
      checkCancelled();
      await _writeRecord(writer, 'blockText', <String, Object?>{
        'id': block.id,
        'index': index++,
        'text': chunk,
      });
    }
  }

  static Iterable<String> _textChunks(String text) sync* {
    final buffer = StringBuffer();
    var bytes = 0;
    for (final rune in text.runes) {
      final width = rune <= 0x7f
          ? 1
          : rune <= 0x7ff
          ? 2
          : rune <= 0xffff
          ? 3
          : 4;
      if (bytes + width > _textChunkLimit) {
        yield buffer.toString();
        buffer.clear();
        bytes = 0;
      }
      buffer.writeCharCode(rune);
      bytes += width;
    }
    if (bytes > 0) yield buffer.toString();
  }

  static Future<void> _writeRecord(
    RandomAccessFile writer,
    String type,
    Map<String, Object?> data, {
    String? entry,
    int? chunkCount,
  }) async {
    final bytes = utf8.encode(
      '${jsonEncode(<String, Object?>{'type': type, 'data': data, 'entry': ?entry, 'chunkCount': ?chunkCount})}\n',
    );
    if (bytes.length > _recordLimit) {
      throw const FormatException('Backup record exceeds 2 MiB');
    }
    await writer.writeFrom(bytes);
  }

  static Future<void> _verifyResource(
    File file,
    int declaredSize,
    String expectedHash, {
    void Function()? checkCancelled,
  }) async {
    if (await file.length() != declaredSize) {
      throw FormatException('Resource size changed: ${file.path}');
    }
    final sink = _DigestSink();
    final converter = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      checkCancelled?.call();
      converter.add(chunk);
    }
    converter.close();
    final digest = sink.digest;
    if (digest.toString() != expectedHash) {
      throw FormatException('Resource hash changed: ${file.path}');
    }
  }

  static void _writeZip(String path, List<_ZipInput> inputs) {
    _rejectLinksSync(path);
    final encoder = archive_io.ZipFileEncoder();
    encoder.create(path, level: archive_io.ZipFileEncoder.gzip);
    try {
      for (final input in inputs) {
        _rejectLinksSync(input.path);
        if (FileSystemEntity.typeSync(input.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw FileSystemException(
            'Backup input is not a regular file',
            input.path,
          );
        }
        encoder.addFileSync(File(input.path), input.entry);
      }
    } finally {
      encoder.closeSync();
    }
  }

  Future<RestorePreview> prepareRestore(
    String path, {
    required int maxOutputBytes,
  }) async {
    _beginOperation();
    try {
      return await _prepareRestore(path, maxOutputBytes: maxOutputBytes);
    } finally {
      _activeOperation = false;
    }
  }

  Future<RestorePreview> _prepareRestore(
    String path, {
    required int maxOutputBytes,
  }) async {
    if (maxOutputBytes <= 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    final input = File(p.normalize(p.absolute(path)));
    final operation = await _createScratch('backup-restore');
    AppDatabase? staged;
    try {
      final extracted = await _runWorker<_UnzipPlan, _Extracted>(
        _UnzipPlan(input.path, operation.path, maxOutputBytes),
        _unzipWorker,
      );
      _checkCancelled();
      final entries = Directory(p.join(operation.path, 'entries'));
      final manifest = _decodeSmallJson(
        File(p.join(entries.path, 'manifest.json')),
        BackupLimits.maxManifestBytes,
      );
      final format = _string(manifest['format'], 'manifest.format');
      if (format != 'bookloom-backup') {
        throw const FormatException('Not a Bookloom backup');
      }
      final version = manifest['formatVersion'] ?? manifest['schemaVersion'];
      if (version is! int || version < 1 || version > 2) {
        throw FormatException('Unsupported backup format version: $version');
      }
      final declaredBooks = _nonnegative(manifest['bookCount'], 'bookCount');
      final includesSources = manifest['includesSources'];
      if (includesSources is! bool) {
        throw const FormatException('Invalid includesSources flag');
      }
      final library = _decodeSmallJson(
        File(p.join(entries.path, 'library.json')),
        _libraryLimit,
      );
      final indexRows = library['books'];
      if (indexRows is! List || indexRows.length != declaredBooks) {
        throw const FormatException('Book index/count mismatch');
      }
      staged = AppDatabase.openAt(File(p.join(operation.path, 'staged.db')));
      if (version == 2) {
        final records = File(p.join(entries.path, 'records.ndjson'));
        if (!await records.exists()) {
          throw const FormatException('Missing records.ndjson');
        }
        await _readRecords(staged, records, _checkCancelled);
      } else {
        if (extracted.names.contains('records.ndjson')) {
          throw const FormatException('Unexpected v2 records in legacy backup');
        }
        await _readLegacyLibrary(staged, library, _checkCancelled);
      }
      final previews = await _validateStaged(
        staged,
        entries,
        indexRows,
        includesSources,
        extracted.names,
        _checkCancelled,
      );
      _checkCancelled();
      final declaredBytes = version == 2
          ? _nonnegative(manifest['payloadBytes'], 'payloadBytes')
          : extracted.actualBytes;
      if (version == 2 &&
          declaredBytes !=
              extracted.actualBytes -
                  await File(p.join(entries.path, 'manifest.json')).length()) {
        throw const FormatException('Backup payload size mismatch');
      }
      final stagedDbFile = File(p.join(operation.path, 'staged.db'));
      final stagedWalFile = File('${stagedDbFile.path}-wal');
      final stagedBytes =
          (await stagedDbFile.exists() ? await stagedDbFile.length() : 0) +
          (await stagedWalFile.exists() ? await stagedWalFile.length() : 0);
      final resourcesBytes =
          (await staged.select(staged.sources).get()).fold<int>(
            0,
            (sum, row) => sum + row.byteSize,
          ) +
          (await staged.select(staged.assets).get()).fold<int>(
            0,
            (sum, row) => sum + row.byteSize,
          );
      final preview = RestorePreview._(
        this,
        operation,
        staged,
        books: previews,
        formatVersion: version,
        includesSources: includesSources,
        declaredBytes: declaredBytes,
        actualBytes: extracted.actualBytes,
        estimatedRequiredBytes:
            await input.length() +
            extracted.actualBytes +
            stagedBytes * 2 +
            resourcesBytes,
      );
      _previews.add(preview);
      return preview;
    } catch (_) {
      await staged?.close();
      await _deleteScratch(operation);
      rethrow;
    }
  }

  static _Extracted _extractZip(
    String inputPath,
    String stagePath,
    int maxBytes,
  ) {
    _rejectLinksSync(inputPath);
    _rejectLinksSync(stagePath);
    final input = archive.InputFileStream(inputPath);
    final entries = Directory(p.join(stagePath, 'entries'));
    entries.createSync(recursive: true);
    final limits = BackupLimits(maxOutputBytes: maxBytes);
    final names = <String>{};
    var claimedBytes = 0;
    var count = 0;
    try {
      final directory = archive.ZipDirectory();
      for (final header in directory.headers(
        input,
        verify: true,
        files: false,
      )) {
        final name = header.filename;
        _checkEntryName(name);
        if (!names.add(name)) {
          throw FormatException('Duplicate ZIP entry: $name');
        }
        if (++count > limits.maxEntries) {
          throw const FormatException('Too many backup entries');
        }
        final mode = (header.externalFileAttributes >> 16) & 0xf000;
        if (mode == 0xa000 || mode == 0x4000 || name.endsWith('/')) {
          throw FormatException(
            'Links and directories are not backup entries: $name',
          );
        }
        final size = header.uncompressedSize;
        final limit = name == 'library.json'
            ? _libraryLimit
            : limits.entryLimit(name);
        if (size < 0 || size > maxBytes || (limit != null && size > limit)) {
          throw FormatException('Entry exceeds backup budget: $name');
        }
        claimedBytes += size;
        if (claimedBytes > maxBytes) {
          throw const FormatException('Backup exceeds declared write budget');
        }
      }
      if (directory.filePosition < 0 ||
          !names.contains('manifest.json') ||
          !names.contains('library.json')) {
        throw const FormatException('Incomplete backup ZIP');
      }
      final budget = _WriteBudget(maxBytes);
      final second = archive.ZipDirectory();
      final extractedNames = <String>{};
      for (final header in second.headers(input, verify: true)) {
        final name = header.filename;
        _checkEntryName(name);
        final mode = (header.externalFileAttributes >> 16) & 0xf000;
        if (!names.contains(name) ||
            !extractedNames.add(name) ||
            mode == 0xa000 ||
            mode == 0x4000 ||
            name.endsWith('/')) {
          throw const FormatException('Backup ZIP changed during extraction');
        }
        final target = File(
          p.joinAll(<String>[entries.path, ...p.posix.split(name)]),
        );
        target.parent.createSync(recursive: true);
        final perEntry = name == 'library.json'
            ? _libraryLimit
            : limits.entryLimit(name) ?? maxBytes;
        final output = _BoundedOutputFileStream(target.path, budget, perEntry);
        try {
          final content = header.file;
          if (content == null) throw FormatException('Missing ZIP data: $name');
          content.verify = true;
          content.throwOnError = true;
          content.decompress(output);
          output.flush();
          if (output.length != header.uncompressedSize) {
            throw FormatException('Entry size mismatch: $name');
          }
        } finally {
          output.closeSync();
        }
      }
      if (extractedNames.length != names.length) {
        throw const FormatException('Backup ZIP changed during extraction');
      }
      return _Extracted(names, budget.used);
    } finally {
      input.closeSync();
    }
  }

  static void _checkEntryName(String name) {
    if (name.isEmpty ||
        name.contains('\\') ||
        name.contains('\u0000') ||
        p.posix.isAbsolute(name) ||
        p.posix.normalize(name) != name ||
        p.posix.split(name).contains('..')) {
      throw FormatException('Unsafe backup path: $name');
    }
    if (const <String>{
      'manifest.json',
      'library.json',
      'records.ndjson',
    }.contains(name)) {
      return;
    }
    final parts = p.posix.split(name);
    if (parts.length == 3 &&
        (parts.first == 'assets' || parts.first == 'sources') &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(parts[1]) &&
        RegExp(r'^[A-Za-z0-9_-]+\.[a-z0-9]{1,8}$').hasMatch(parts[2])) {
      return;
    }
    if (parts.length == 2 &&
        parts.first == 'assets' &&
        RegExp(r'^[A-Za-z0-9_-]+\.[a-z0-9]{1,8}$').hasMatch(parts[1])) {
      return; // bounded legacy v1 convention
    }
    throw FormatException('Unexpected backup path: $name');
  }

  static Map<String, Object?> _decodeSmallJson(File file, int limit) {
    if (!file.existsSync() || file.lengthSync() > limit) {
      throw FormatException('Missing or oversized ${p.basename(file.path)}');
    }
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }
    return value.cast<String, Object?>();
  }

  static Future<void> _readRecords(
    AppDatabase db,
    File file,
    void Function() checkCancelled,
  ) async {
    final chapterBooks = <String, String>{};
    final chapterCounts = <String, int>{};
    _ChunkState? chunkState;
    await for (final line in _boundedLines(file)) {
      checkCancelled();
      final decoded = jsonDecode(utf8.decode(line));
      final record = _map(decoded, 'record');
      final type = _string(record['type'], 'record.type');
      final data = _map(record['data'], 'record.data');
      if (chunkState != null &&
          chunkState.remaining > 0 &&
          type != 'blockText') {
        throw const FormatException('Missing text block chunks');
      }
      switch (type) {
        case 'book':
          final row = Book.fromJson(data);
          _checkId(row.id);
          if (row.chapterCount < 0 || row.wordCount < 0) {
            throw const FormatException('Invalid book counts');
          }
          await db.into(db.books).insert(row);
        case 'source':
          final row = Source.fromJson(data);
          _checkId(row.id);
          _checkId(row.bookId);
          final entry = _string(record['entry'], 'source.entry');
          _checkEntryName(entry);
          if (!entry.startsWith('sources/${row.bookId}/${row.id}.') ||
              p.extension(entry) != '.${row.format}' ||
              row.byteSize < 0 ||
              !const <String>{'txt', 'epub', 'docx'}.contains(row.format)) {
            throw const FormatException('Invalid source record');
          }
          await db.into(db.sources).insert(row.copyWith(storedPath: entry));
        case 'asset':
          final row = Asset.fromJson(data);
          _checkId(row.id);
          _checkId(row.bookId);
          final entry = _string(record['entry'], 'asset.entry');
          _checkEntryName(entry);
          if (!entry.startsWith('assets/${row.bookId}/${row.id}.') ||
              row.byteSize < 0 ||
              !const <String>{'image', 'cover', 'font'}.contains(row.kind)) {
            throw const FormatException('Invalid asset record');
          }
          await db.into(db.assets).insert(row.copyWith(storedPath: entry));
        case 'chapter':
          final row = Chapter.fromJson(data);
          _checkId(row.id);
          _checkId(row.bookId);
          if (row.parentId != null) _checkId(row.parentId!);
          if (row.level != 1 && row.level != 2 || row.wordCount < 0) {
            throw const FormatException('Invalid chapter record');
          }
          await db.into(db.chapters).insert(row);
          chapterBooks[row.id] = row.bookId;
          chapterCounts[row.id] = 0;
        case 'block':
          final row = Block.fromJson(data);
          _checkId(row.id);
          _checkId(row.chapterId);
          if (!chapterBooks.containsKey(row.chapterId) ||
              !const <String>{
                'paragraph',
                'image',
                'footnote',
                'divider',
              }.contains(row.kind)) {
            throw const FormatException('Invalid block record');
          }
          final count = record['chunkCount'] ?? 0;
          if (count is! int ||
              count < 0 ||
              count > 100000 ||
              (count > 0 &&
                  (row.content != null ||
                      !const <String>{
                        'paragraph',
                        'footnote',
                      }.contains(row.kind)))) {
            throw const FormatException('Invalid text chunk count');
          }
          if (row.kind == 'image' && row.assetId == null) {
            throw const FormatException('Image has no asset');
          }
          await db.into(db.blocks).insert(row);
          if (row.kind == 'paragraph') {
            chapterCounts[row.chapterId] =
                chapterCounts[row.chapterId]! +
                WordCount.ofText(row.content ?? '');
          }
          chunkState = count > 0
              ? _ChunkState(row.id, row.chapterId, row.kind, count)
              : null;
        case 'blockText':
          final state = chunkState;
          if (state == null ||
              state.remaining <= 0 ||
              data['id'] != state.blockId ||
              data['index'] != state.nextIndex) {
            throw const FormatException('Out-of-order text chunk');
          }
          final text = _string(data['text'], 'blockText.text');
          if (utf8.encode(text).length > _textChunkLimit) {
            throw const FormatException('Oversized text chunk');
          }
          await db.customUpdate(
            "UPDATE blocks SET text = COALESCE(text, '') || ? WHERE id = ?",
            variables: <drift.Variable<Object>>[
              drift.Variable<String>(text),
              drift.Variable<String>(state.blockId),
            ],
          );
          if (state.kind == 'paragraph') {
            chapterCounts[state.chapterId] =
                chapterCounts[state.chapterId]! + WordCount.ofText(text);
          }
          state.nextIndex++;
          state.remaining--;
          if (state.remaining == 0) chunkState = null;
        default:
          throw FormatException('Unknown backup record type: $type');
      }
    }
    if (chunkState != null) {
      throw const FormatException('Truncated text block chunks');
    }
    await _checkCounts(db, chapterBooks, chapterCounts);
  }

  static Future<void> _checkCounts(
    AppDatabase db,
    Map<String, String> chapterBooks,
    Map<String, int> chapterCounts,
  ) async {
    final bookCounts = <String, int>{};
    final bookChapters = <String, int>{};
    for (final chapter in await db.select(db.chapters).get()) {
      if (chapterCounts[chapter.id] != chapter.wordCount) {
        throw FormatException('Chapter count mismatch: ${chapter.id}');
      }
      bookCounts.update(
        chapter.bookId,
        (value) => value + chapter.wordCount,
        ifAbsent: () => chapter.wordCount,
      );
      bookChapters.update(
        chapter.bookId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    for (final book in await db.select(db.books).get()) {
      if (book.wordCount != (bookCounts[book.id] ?? 0) ||
          book.chapterCount != (bookChapters[book.id] ?? 0)) {
        throw FormatException('Book count mismatch: ${book.id}');
      }
    }
  }

  static Stream<Uint8List> _boundedLines(File file) async* {
    var pending = BytesBuilder(copy: false);
    await for (final raw in file.openRead()) {
      final chunk = raw is Uint8List ? raw : Uint8List.fromList(raw);
      var start = 0;
      while (start < chunk.length) {
        final end = chunk.indexOf(0x0a, start);
        final stop = end < 0 ? chunk.length : end;
        if (pending.length + stop - start > _recordLimit) {
          throw const FormatException('Backup record exceeds 2 MiB');
        }
        pending.add(Uint8List.sublistView(chunk, start, stop));
        if (end < 0) break;
        final line = pending.takeBytes();
        if (line.isEmpty) throw const FormatException('Empty backup record');
        yield line;
        pending = BytesBuilder(copy: false);
        start = end + 1;
      }
    }
    if (pending.length != 0) {
      throw const FormatException('Unterminated backup record');
    }
  }

  static Future<void> _readLegacyLibrary(
    AppDatabase db,
    Map<String, Object?> library,
    void Function() checkCancelled,
  ) async {
    // Version 1's single JSON tree is accepted only behind the 8 MiB cap.
    // Normalize the v1 missing fields and preserve its current content.
    final books = _list(library['books'], 'books');
    final sources = _list(library['sources'] ?? <Object?>[], 'sources');
    final assets = _list(library['assets'] ?? <Object?>[], 'assets');
    final chapters = _list(library['chapters'] ?? <Object?>[], 'chapters');
    final blocks = _list(library['blocks'] ?? <Object?>[], 'blocks');
    final chapterBooks = <String, String>{};
    final chapterCounts = <String, int>{};
    for (final raw in books) {
      checkCancelled();
      final data = _legacyFields(_map(raw, 'legacy.book'));
      data.putIfAbsent(
        'coverMode',
        () => data['coverAssetId'] == null ? 'template' : 'image',
      );
      data.putIfAbsent('parseOptionsJson', () => '{}');
      data.putIfAbsent('revision', () => 0);
      data.putIfAbsent('chapterCount', () => 0);
      data.putIfAbsent('wordCount', () => 0);
      data.putIfAbsent('layoutJson', () => '{}');
      data.putIfAbsent('coverOptionsJson', () => '{}');
      data.putIfAbsent('tagsJson', () => '[]');
      data.putIfAbsent('author', () => '');
      data.putIfAbsent('language', () => 'zh-CN');
      data.putIfAbsent('description', () => '');
      data.putIfAbsent('progress', () => 0.0);
      _normalizeLegacyDates(data, <String>[
        'createdAt',
        'updatedAt',
        'lastOpenedAt',
      ]);
      final row = Book.fromJson(data);
      _checkId(row.id);
      await db.into(db.books).insert(row);
    }
    for (final raw in sources) {
      checkCancelled();
      final data = _legacyFields(_map(raw, 'legacy.source'));
      _normalizeLegacyDates(data, <String>['createdAt']);
      final row = Source.fromJson(data);
      final ext = p.extension(row.storedPath).replaceFirst('.', '');
      final entry = 'sources/${row.bookId}/source.$ext';
      _checkEntryName(entry);
      await db.into(db.sources).insert(row.copyWith(storedPath: entry));
    }
    for (final raw in assets) {
      checkCancelled();
      final data = _legacyFields(_map(raw, 'legacy.asset'));
      _normalizeLegacyDates(data, <String>['createdAt']);
      final row = Asset.fromJson(data);
      final ext = p.extension(row.storedPath).replaceFirst('.', '');
      final entry = 'assets/${row.id}.$ext';
      _checkEntryName(entry);
      await db.into(db.assets).insert(row.copyWith(storedPath: entry));
    }
    for (final raw in chapters) {
      checkCancelled();
      final data = _legacyFields(_map(raw, 'legacy.chapter'));
      data.putIfAbsent('frontMatter', () => false);
      data.putIfAbsent('wordCount', () => 0);
      data.putIfAbsent('level', () => 2);
      _normalizeLegacyDates(data, <String>['createdAt', 'updatedAt']);
      final row = Chapter.fromJson(data);
      await db.into(db.chapters).insert(row);
      chapterBooks[row.id] = row.bookId;
      chapterCounts[row.id] = 0;
    }
    for (final raw in blocks) {
      checkCancelled();
      final data = _legacyFields(_map(raw, 'legacy.block'));
      if (!data.containsKey('content') && data.containsKey('text')) {
        data['content'] = data.remove('text');
      }
      data.putIfAbsent('metaJson', () => '{}');
      _normalizeLegacyDates(data, <String>['createdAt']);
      final row = Block.fromJson(data);
      await db.into(db.blocks).insert(row);
      if (row.kind == 'paragraph') {
        chapterCounts[row.chapterId] =
            (chapterCounts[row.chapterId] ?? 0) +
            WordCount.ofText(row.content ?? '');
      }
    }
    await _checkCounts(db, chapterBooks, chapterCounts);
  }

  static Map<String, dynamic> _legacyFields(Map<String, Object?> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      result[entry.key.replaceAllMapped(
            RegExp(r'_([a-z])'),
            (match) => match.group(1)!.toUpperCase(),
          )] =
          entry.value;
    }
    return result;
  }

  static void _normalizeLegacyDates(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is int && value.abs() < 100000000000) {
        data[key] = value * 1000; // Drift v1 SQLite stored seconds.
      }
    }
  }

  static Future<List<RestoreBookPreview>> _validateStaged(
    AppDatabase db,
    Directory entries,
    List<dynamic> indexRows,
    bool includesSources,
    Set<String> entryNames,
    void Function() checkCancelled,
  ) async {
    final books = await db.select(db.books).get();
    if (books.length != indexRows.length) {
      throw const FormatException('Book index does not match records');
    }
    final byId = <String, Book>{for (final book in books) book.id: book};
    final used = <String>{'manifest.json', 'library.json'};
    if (entryNames.contains('records.ndjson')) used.add('records.ndjson');
    final sourceByBook = <String, Source>{};
    for (final source in await db.select(db.sources).get()) {
      checkCancelled();
      if (!includesSources || !byId.containsKey(source.bookId)) {
        throw const FormatException('Source does not belong to this backup');
      }
      _checkEntryName(source.storedPath);
      if (!entryNames.contains(source.storedPath) ||
          !used.add(source.storedPath)) {
        throw const FormatException('Missing or duplicate source entry');
      }
      await _verifyResource(
        File(
          p.joinAll(<String>[
            entries.path,
            ...p.posix.split(source.storedPath),
          ]),
        ),
        source.byteSize,
        source.sha256,
        checkCancelled: checkCancelled,
      );
      sourceByBook[source.bookId] = source;
    }
    final assets = await db.select(db.assets).get();
    final assetById = <String, Asset>{};
    final assetCount = <String, int>{};
    for (final asset in assets) {
      checkCancelled();
      if (!byId.containsKey(asset.bookId)) {
        throw const FormatException('Asset does not belong to this backup');
      }
      _checkEntryName(asset.storedPath);
      if (!entryNames.contains(asset.storedPath) ||
          !used.add(asset.storedPath)) {
        throw const FormatException('Missing or duplicate asset entry');
      }
      await _verifyResource(
        File(
          p.joinAll(<String>[entries.path, ...p.posix.split(asset.storedPath)]),
        ),
        asset.byteSize,
        asset.sha256,
        checkCancelled: checkCancelled,
      );
      assetById[asset.id] = asset;
      assetCount.update(asset.bookId, (count) => count + 1, ifAbsent: () => 1);
    }
    if (used.length != entryNames.length) {
      throw const FormatException('Unreferenced backup entry');
    }
    final chapterById = <String, Chapter>{};
    for (final chapter in await db.select(db.chapters).get()) {
      if (!byId.containsKey(chapter.bookId)) {
        throw const FormatException('Chapter has no book');
      }
      chapterById[chapter.id] = chapter;
    }
    for (final chapter in chapterById.values) {
      final parent = chapter.parentId == null
          ? null
          : chapterById[chapter.parentId];
      if (chapter.level == 1 && chapter.parentId != null ||
          chapter.parentId != null &&
              (chapter.level != 2 ||
                  parent == null ||
                  parent.level != 1 ||
                  parent.bookId != chapter.bookId)) {
        throw const FormatException('Invalid chapter parent');
      }
    }
    final invalidBlocks = await db.customSelect('''
      SELECT b.id FROM blocks b JOIN chapters c ON c.id = b.chapter_id
      WHERE b.kind NOT IN ('paragraph', 'image', 'footnote', 'divider')
         OR (b.kind = 'image' AND b.asset_id IS NULL)
         OR (b.asset_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM assets a
           WHERE a.id = b.asset_id AND a.book_id = c.book_id
         ))
      LIMIT 1
    ''').get();
    if (invalidBlocks.isNotEmpty) {
      throw const FormatException(
        'Invalid block or cross-book asset reference',
      );
    }
    final preview = <RestoreBookPreview>[];
    final seen = <String>{};
    for (final raw in indexRows) {
      checkCancelled();
      final index = _map(raw, 'library.book');
      final id = _string(index['id'], 'library.book.id');
      final book = byId[id];
      if (book == null || !seen.add(id) || index['title'] != book.title) {
        throw const FormatException('Book index differs from records');
      }
      if (entryNames.contains('records.ndjson') &&
          (index['author'] != book.author ||
              index['chapterCount'] != book.chapterCount ||
              index['wordCount'] != book.wordCount ||
              index['hasSource'] != sourceByBook.containsKey(id) ||
              index['assetCount'] != (assetCount[id] ?? 0))) {
        throw const FormatException('Book summary differs from records');
      }
      if (!const <String>{'template', 'image'}.contains(book.coverMode) ||
          (book.coverMode == 'image' && book.coverAssetId == null)) {
        throw const FormatException('Invalid cover mode or image reference');
      }
      final tags = jsonDecode(book.tagsJson);
      if (tags is! List || tags.any((tag) => tag is! String)) {
        throw const FormatException('Invalid book tags');
      }
      if (book.coverAssetId != null &&
          assetById[book.coverAssetId]?.bookId != book.id) {
        throw const FormatException('Invalid cover asset');
      }
      final layout = LayoutOptions.fromJson(
        _map(jsonDecode(book.layoutJson), 'layoutJson'),
      );
      final fontId = layout.embeddedFontAssetId;
      if (fontId != null && assetById[fontId]?.bookId != book.id) {
        throw const FormatException('Invalid embedded font asset');
      }
      _map(jsonDecode(book.parseOptionsJson), 'parseOptionsJson');
      _map(jsonDecode(book.coverOptionsJson), 'coverOptionsJson');
      preview.add(
        RestoreBookPreview(
          id: id,
          title: book.title,
          author: book.author,
          chapterCount: book.chapterCount,
          wordCount: book.wordCount,
          hasSource: sourceByBook.containsKey(id),
          assetCount: assetCount[id] ?? 0,
        ),
      );
    }
    return preview;
  }

  Future<RestoreApplyResult> applyRestore(
    RestorePreview preview, {
    RestoreConflictPolicy policy = RestoreConflictPolicy.copy,
  }) async {
    _beginOperation();
    final restored = <String>[];
    final skipped = <String>[];
    final cancelled = <String>[];
    final failures = <String, String>{};
    String? cleanupWarning;
    try {
      if (!_previews.contains(preview) || preview._disposed) {
        throw StateError('Restore preview is no longer active');
      }
      await repository.listSummaries();
      for (var index = 0; index < preview.books.length; index++) {
        final book = preview.books[index];
        if (_cancelRequested) {
          cancelled.addAll(preview.books.skip(index).map((row) => row.id));
          break;
        }
        final existing = await (repository.db.select(
          repository.db.books,
        )..where((table) => table.id.equals(book.id))).getSingleOrNull();
        if (existing != null && policy == RestoreConflictPolicy.skip) {
          skipped.add(book.id);
          continue;
        }
        final targetId =
            existing != null && policy == RestoreConflictPolicy.copy
            ? _uuid.v4()
            : book.id;
        try {
          await _applyOne(
            preview,
            book.id,
            targetId,
            targetId == book.id ? existing : null,
          );
          restored.add(targetId);
        } on TaskCancelled {
          cancelled.addAll(preview.books.skip(index).map((row) => row.id));
          break;
        } on Object catch (error) {
          failures[book.id] = error.toString();
        }
      }
    } finally {
      try {
        if (_previews.contains(preview)) await preview.dispose();
      } on FileSystemException catch (error) {
        cleanupWarning = '恢复已提交，但暂存目录清理失败：$error';
      } finally {
        _activeOperation = false;
      }
    }
    return RestoreApplyResult(
      restoredIds: List<String>.unmodifiable(restored),
      skippedIds: List<String>.unmodifiable(skipped),
      cancelledIds: List<String>.unmodifiable(cancelled),
      failures: Map<String, String>.unmodifiable(failures),
      cleanupWarning: cleanupWarning,
    );
  }

  Future<void> _applyOne(
    RestorePreview preview,
    String sourceBookId,
    String targetBookId,
    Book? existing,
  ) async {
    _checkCancelled();
    final stage = preview._database;
    final target = repository.db;
    final files = repository.files;
    final stagedBook = await (stage.select(
      stage.books,
    )..where((table) => table.id.equals(sourceBookId))).getSingle();
    final source = await (stage.select(
      stage.sources,
    )..where((table) => table.bookId.equals(sourceBookId))).getSingleOrNull();
    final assets = await (stage.select(
      stage.assets,
    )..where((table) => table.bookId.equals(sourceBookId))).get();
    final chapters = await (stage.select(
      stage.chapters,
    )..where((table) => table.bookId.equals(sourceBookId))).get();
    final salt = _uuid.v4();
    String mapId(String kind, String id) =>
        'r${sha256.convert(utf8.encode('$salt:$sourceBookId:$kind:$id')).toString().substring(0, 32)}';
    final assetIds = <String, String>{
      for (final asset in assets) asset.id: mapId('asset', asset.id),
    };
    final chapterIds = <String, String>{
      for (final chapter in chapters) chapter.id: mapId('chapter', chapter.id),
    };
    final operationId = _uuid.v4();
    final bookRelative = files.bookRelativePath(targetBookId);
    final bookDirectory = Directory(
      p.join(files.supportDirectory.path, bookRelative),
    );
    await files.ensureRoot();
    await files.resolveStoredPath(targetBookId, p.join(bookRelative, 'assets'));
    if (existing == null && await bookDirectory.exists()) {
      throw StateError('An unindexed book directory already exists');
    }
    final oldPaths = <String>[];
    Source? oldSourceSnapshot;
    var oldAssetsSnapshot = <Asset>[];
    if (existing != null) {
      oldSourceSnapshot = await (target.select(
        target.sources,
      )..where((table) => table.bookId.equals(targetBookId))).getSingleOrNull();
      if (oldSourceSnapshot != null) {
        final relative = p.relative(
          oldSourceSnapshot.storedPath,
          from: bookRelative,
        );
        if (_managedRelative(relative)) oldPaths.add(relative);
      }
      oldAssetsSnapshot = await (target.select(
        target.assets,
      )..where((table) => table.bookId.equals(targetBookId))).get();
      for (final asset in oldAssetsSnapshot) {
        final relative = p.relative(asset.storedPath, from: bookRelative);
        if (_managedRelative(relative)) oldPaths.add(relative);
      }
    }
    final copies = <(File, String, int, String)>[];
    if (source != null) {
      final extension = p.extension(source.storedPath).replaceFirst('.', '');
      final relative = 'source-${mapId('source', source.id)}.$extension';
      copies.add((
        File(p.join(preview._directory.path, 'entries', source.storedPath)),
        relative,
        source.byteSize,
        source.sha256,
      ));
    }
    for (final asset in assets) {
      final extension = p.extension(asset.storedPath).replaceFirst('.', '');
      final relative = p.join('assets', '${assetIds[asset.id]}.$extension');
      copies.add((
        File(p.join(preview._directory.path, 'entries', asset.storedPath)),
        relative,
        asset.byteSize,
        asset.sha256,
      ));
    }
    final newPaths = <String>[for (final copy in copies) copy.$2];
    await _writeRestoreMarker(
      operationId,
      targetBookId,
      <String>{...oldPaths, ...newPaths}.toList(),
    );
    var committed = false;
    try {
      _checkCancelled();
      await bookDirectory.create(recursive: true);
      for (final (stagedFile, relative, size, digest) in copies) {
        _checkCancelled();
        await _rejectLinks(stagedFile.path);
        final destination = await files.resolveStoredPath(
          targetBookId,
          p.join(bookRelative, relative),
        );
        if (await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw StateError('Restore target file already exists');
        }
        await destination.parent.create(recursive: true);
        await _copyResource(stagedFile, destination, size, digest);
      }
      _checkCancelled();
      _isCommitting = true;
      try {
        await target.transaction(() async {
          final current = await (target.select(
            target.books,
          )..where((table) => table.id.equals(targetBookId))).getSingleOrNull();
          if (current?.revision != existing?.revision) {
            throw StateError('Book changed during restore');
          }
          if (current != null) {
            final currentSource =
                await (target.select(target.sources)
                      ..where((table) => table.bookId.equals(targetBookId)))
                    .getSingleOrNull();
            final currentAssets = await (target.select(
              target.assets,
            )..where((table) => table.bookId.equals(targetBookId))).get();
            if (jsonEncode(currentSource?.toJson()) !=
                    jsonEncode(oldSourceSnapshot?.toJson()) ||
                _assetSnapshot(currentAssets) !=
                    _assetSnapshot(oldAssetsSnapshot)) {
              throw StateError('Book resources changed during restore');
            }
          }
          if (current != null) {
            await (target.delete(
              target.books,
            )..where((table) => table.id.equals(targetBookId))).go();
          }
          final layout = _map(jsonDecode(stagedBook.layoutJson), 'layoutJson');
          final fontId = layout['embeddedFontAssetId'];
          if (fontId is String) {
            layout['embeddedFontAssetId'] = assetIds[fontId];
          }
          await target
              .into(target.books)
              .insert(
                stagedBook.copyWith(
                  id: targetBookId,
                  coverAssetId: drift.Value(
                    stagedBook.coverAssetId == null
                        ? null
                        : assetIds[stagedBook.coverAssetId],
                  ),
                  layoutJson: jsonEncode(layout),
                  revision: current == null ? 0 : current.revision + 1,
                ),
              );
          for (final asset in assets) {
            final extension = p
                .extension(asset.storedPath)
                .replaceFirst('.', '');
            final relative = p.join(
              'assets',
              '${assetIds[asset.id]}.$extension',
            );
            await target
                .into(target.assets)
                .insert(
                  asset.copyWith(
                    id: assetIds[asset.id],
                    bookId: targetBookId,
                    storedPath: files.storedPathFor(targetBookId, relative),
                  ),
                );
          }
          if (source != null) {
            final extension = p
                .extension(source.storedPath)
                .replaceFirst('.', '');
            await target
                .into(target.sources)
                .insert(
                  source.copyWith(
                    id: mapId('source', source.id),
                    bookId: targetBookId,
                    storedPath: files.storedPathFor(
                      targetBookId,
                      'source-${mapId('source', source.id)}.$extension',
                    ),
                  ),
                );
          }
          final ordered = [...chapters]
            ..sort((a, b) => a.level.compareTo(b.level));
          for (final chapter in ordered) {
            await target
                .into(target.chapters)
                .insert(
                  chapter.copyWith(
                    id: chapterIds[chapter.id],
                    bookId: targetBookId,
                    parentId: drift.Value(
                      chapter.parentId == null
                          ? null
                          : chapterIds[chapter.parentId],
                    ),
                  ),
                );
            var offset = 0;
            while (true) {
              final page =
                  await (stage.select(stage.blocks)
                        ..where((table) => table.chapterId.equals(chapter.id))
                        ..orderBy(<drift.OrderingTerm Function($BlocksTable)>[
                          (table) => drift.OrderingTerm.asc(table.sortOrder),
                          (table) => drift.OrderingTerm.asc(table.id),
                        ])
                        ..limit(128, offset: offset))
                      .get();
              if (page.isEmpty) break;
              for (final block in page) {
                await target
                    .into(target.blocks)
                    .insert(
                      block.copyWith(
                        id: mapId('block', block.id),
                        chapterId: chapterIds[chapter.id],
                        assetId: drift.Value(
                          block.assetId == null
                              ? null
                              : assetIds[block.assetId],
                        ),
                      ),
                    );
              }
              offset += page.length;
            }
          }
        });
      } finally {
        _isCommitting = false;
      }
      committed = true;
    } finally {
      if (!committed) {
        for (final relative in newPaths) {
          try {
            await files.deleteAssetFile(targetBookId, relative);
          } on FileSystemException {
            // The marker makes startup cleanup retryable.
          }
        }
        if (existing == null && await bookDirectory.exists()) {
          try {
            await bookDirectory.delete(recursive: true);
          } on FileSystemException {
            // The marker remains for recovery.
          }
        }
      }
    }
    // Deletion follows the committed reference change. An interrupted sweep
    // leaves the marker for BookRepository startup recovery.
    try {
      await _cleanupRestorePaths(targetBookId, oldPaths);
      await files.removeMarker(operationId);
    } on FileSystemException {
      // Committed replacement is usable; startup recovery finishes cleanup.
    }
  }

  Future<void> _writeRestoreMarker(
    String operationId,
    String bookId,
    List<String> paths,
  ) async {
    final root = p.join(repository.files.supportDirectory.path, 'operations');
    final temporary = File(p.join(root, '$operationId.tmp'));
    final marker = File(p.join(root, '$operationId.json'));
    await _rejectLinks(temporary.path);
    await _rejectLinks(marker.path);
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'kind': 'restore',
        'bookId': bookId,
        'paths': paths,
      }),
      flush: true,
    );
    await temporary.rename(marker.path);
  }

  Future<void> _copyResource(
    File staged,
    File destination,
    int expectedSize,
    String expectedHash,
  ) async {
    _checkCancelled();
    await _rejectLinks(destination.path);
    await destination.create(exclusive: true);
    final writer = await destination.open(mode: FileMode.writeOnly);
    final sink = _DigestSink();
    final converter = sha256.startChunkedConversion(sink);
    var bytes = 0;
    try {
      await for (final chunk in staged.openRead()) {
        _checkCancelled();
        bytes += chunk.length;
        if (bytes > expectedSize) {
          throw const FormatException('Restore resource exceeds declared size');
        }
        converter.add(chunk);
        await writer.writeFrom(chunk);
      }
      _checkCancelled();
      converter.close();
      if (bytes != expectedSize || sink.digest.toString() != expectedHash) {
        throw const FormatException('Restore resource changed after preview');
      }
      await writer.flush();
    } finally {
      await writer.close();
    }
  }

  Future<void> _cleanupRestorePaths(String bookId, List<String> paths) async {
    for (final relative in paths) {
      if (!_managedRelative(relative)) continue;
      final storedPath = repository.files.storedPathFor(bookId, relative);
      final source =
          await (repository.db.select(repository.db.sources)
                ..where((table) => table.storedPath.equals(storedPath))
                ..limit(1))
              .getSingleOrNull();
      final asset =
          await (repository.db.select(repository.db.assets)
                ..where((table) => table.storedPath.equals(storedPath))
                ..limit(1))
              .getSingleOrNull();
      if (source == null && asset == null) {
        await repository.files.deleteAssetFile(bookId, relative);
      }
    }
  }

  static bool _managedRelative(String relative) {
    if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
      return false;
    }
    final name = p.basename(relative);
    if (p.dirname(relative) == 'assets' &&
        RegExp(r'^[A-Za-z0-9_-]+\.[a-z0-9]{1,8}$').hasMatch(name)) {
      return true;
    }
    return p.dirname(relative) == '.' &&
        RegExp(r'^source(?:-[A-Za-z0-9_-]+)?\.(?:txt|epub|docx)$')
            .hasMatch(name);
  }

  static String _assetSnapshot(List<Asset> assets) {
    final ordered = [...assets]..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode(ordered.map((asset) => asset.toJson()).toList());
  }

  Future<Directory> _createScratch(String prefix) async {
    final root = p.normalize(p.absolute(scratchDirectory.path));
    await _rejectLinks(root);
    await Directory(root).create(recursive: true);
    final path = p.join(root, '$prefix-${_uuid.v4()}');
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('Backup task directory already exists');
    }
    return Directory(path).create();
  }

  Future<void> _deleteScratch(Directory directory) async {
    final root = p.normalize(p.absolute(scratchDirectory.path));
    final path = p.normalize(p.absolute(directory.path));
    if (p.dirname(path) != root || !p.basename(path).startsWith('backup-')) {
      throw StateError('Refusing to remove a non-backup directory');
    }
    await _rejectLinks(path);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> _dispose(RestorePreview preview) async {
    if (preview._disposed) return;
    if (!_previews.remove(preview)) {
      throw StateError('Restore preview belongs to another service');
    }
    preview._disposed = true;
    await preview._database.close();
    await _deleteScratch(preview._directory);
  }

  static Future<void> _rejectLinks(String path) async {
    var current = path;
    while (true) {
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException('Symlinked backup path', current);
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  static void _rejectLinksSync(String path) {
    var current = path;
    while (true) {
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException('Symlinked backup path', current);
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  static Map<String, dynamic> _map(Object? value, String field) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected object: $field');
    }
    return value;
  }

  static List<dynamic> _list(Object? value, String field) {
    if (value is! List) throw FormatException('Expected list: $field');
    return value;
  }

  static String _string(Object? value, String field) {
    if (value is! String) throw FormatException('Expected string: $field');
    return value;
  }

  static int _nonnegative(Object? value, String field) {
    if (value is! int || value < 0) {
      throw FormatException('Expected nonnegative integer: $field');
    }
    return value;
  }

  static void _checkId(String id) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(id)) {
      throw FormatException('Unsafe backup ID: $id');
    }
  }
}

class _ZipInput {
  const _ZipInput(this.entry, this.path, this.byteSize);
  final String entry;
  final String path;
  final int byteSize;
}

class _ZipPlan {
  const _ZipPlan(this.outputPath, this.inputs);
  final String outputPath;
  final List<_ZipInput> inputs;
}

class _UnzipPlan {
  const _UnzipPlan(this.inputPath, this.stagePath, this.maxBytes);
  final String inputPath;
  final String stagePath;
  final int maxBytes;
}

bool _zipWorker(_ZipPlan plan, void Function(double, String) progress) {
  try {
    BookBackup._writeZip(plan.outputPath, plan.inputs);
    return true;
  } on FileSystemException {
    throw const StorageFailure('备份写入失败，请检查目标位置与磁盘空间。');
  } on Object {
    throw const ExportFailure('备份压缩失败，请重试。');
  }
}

_Extracted _unzipWorker(
  _UnzipPlan plan,
  void Function(double, String) progress,
) {
  try {
    return BookBackup._extractZip(
      plan.inputPath,
      plan.stagePath,
      plan.maxBytes,
    );
  } on FileSystemException {
    throw const StorageFailure('无法读取备份文件或写入暂存目录。');
  } on Object {
    throw const ValidationFailure('备份文件无效，或超过所选的恢复空间预算。');
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get digest =>
      _digest ?? (throw StateError('Resource hash was not completed'));

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}

class _Extracted {
  const _Extracted(this.names, this.actualBytes);
  final Set<String> names;
  final int actualBytes;
}

class _ChunkState {
  _ChunkState(this.blockId, this.chapterId, this.kind, this.remaining);
  final String blockId;
  final String chapterId;
  final String kind;
  int remaining;
  int nextIndex = 0;
}

class _WriteBudget {
  _WriteBudget(this.limit);
  final int limit;
  int used = 0;
}

class _BoundedOutputFileStream extends archive.OutputFileStream {
  _BoundedOutputFileStream(String path, this.budget, this.entryLimit)
    : super.withFileHandle(
        archive.FileHandle(path, mode: archive.FileAccess.write),
      );

  final _WriteBudget budget;
  final int entryLimit;

  void _charge(int amount) {
    if (amount < 0 ||
        length + amount > entryLimit ||
        budget.used + amount > budget.limit) {
      throw const FormatException('Backup decompression budget exceeded');
    }
    budget.used += amount;
  }

  @override
  void writeByte(int value) {
    _charge(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _charge(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeRange(Uint8List bytes, int start, int end) {
    _charge(end - start);
    super.writeRange(bytes, start, end);
  }

  @override
  void writeZeros(int count) {
    if (count <= 0) return;
    final zeros = Uint8List(count < 64 * 1024 ? count : 64 * 1024);
    while (count > 0) {
      final length = count < zeros.length ? count : zeros.length;
      writeBytes(zeros, length: length);
      count -= length;
    }
  }
}
