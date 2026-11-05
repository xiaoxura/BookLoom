import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../io/input_limits.dart';

/// An input stream may originate from a picker URI; it need not be a File.
typedef OpenInputStream = Stream<List<int>> Function();

class SourceImport {
  const SourceImport({
    required this.format,
    required this.originalName,
    required this.openRead,
    this.maxBytes = ImportLimits.maxSingleInputBytes,
    this.id,
  });

  final String format;
  final String originalName;
  final OpenInputStream openRead;
  final int maxBytes;
  final String? id;
}

class AssetImport {
  const AssetImport({
    required this.kind,
    required this.mime,
    required this.openRead,
    this.id,
    this.extension = 'bin',
    this.maxBytes = ImportLimits.maxFontBytes,
    this.width,
    this.height,
  });

  final String kind;
  final String mime;
  final OpenInputStream openRead;
  final String? id;
  final String extension;
  final int maxBytes;
  final int? width;
  final int? height;
}

class StoredFile {
  const StoredFile({
    required this.id,
    required this.storedPath,
    required this.byteSize,
    required this.sha256,
  });

  final String id;
  final String storedPath;
  final int byteSize;
  final String sha256;
}

/// Owns only paths under the application's support directory. Operation
/// markers survive a crash between a file move and its SQLite transaction.
class BookFiles {
  BookFiles(this.supportDirectory);

  final Directory supportDirectory;
  static const Uuid _uuid = Uuid();
  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');

  String get _root => p.normalize(p.absolute(supportDirectory.path));
  String newId() => _uuid.v4();

  void checkId(String id) {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'unsafe path component');
    }
  }

  String bookRelativePath(String bookId) {
    checkId(bookId);
    return p.join('books', bookId);
  }

  String _inside(String relative) {
    if (p.isAbsolute(relative)) throw ArgumentError.value(relative, 'path');
    final normalized = p.normalize(relative);
    if (normalized == '.' ||
        normalized == '..' ||
        p.split(normalized).contains('..')) {
      throw ArgumentError.value(relative, 'path', 'path traversal');
    }
    final absolute = p.normalize(p.join(_root, normalized));
    if (!p.isWithin(_root, absolute)) {
      throw ArgumentError.value(relative, 'path', 'outside app support');
    }
    return absolute;
  }

  Future<void> _rejectLinks(String absolute) async {
    var ancestor = _root;
    while (true) {
      if (await FileSystemEntity.type(ancestor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException('Symlinked support directory', ancestor);
      }
      final parent = p.dirname(ancestor);
      if (parent == ancestor) break;
      ancestor = parent;
    }
    var cursor = _root;
    for (final segment in p.split(p.relative(absolute, from: _root))) {
      cursor = p.join(cursor, segment);
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException('Symlinked book path', cursor);
      }
    }
  }

  Future<void> ensureRoot() async {
    await _rejectLinks(_root);
    await supportDirectory.create(recursive: true);
    for (final relative in <String>['books', 'staging', 'operations']) {
      final path = _inside(relative);
      await _rejectLinks(path);
      await Directory(path).create();
    }
  }

  Future<File> resolveStoredPath(String bookId, String relative) async {
    final bookPath = bookRelativePath(bookId);
    if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
      throw ArgumentError.value(relative, 'storedPath', 'path traversal');
    }
    final normalized = p.normalize(relative);
    if (!p.isWithin(bookPath, normalized)) {
      throw ArgumentError.value(relative, 'storedPath', 'wrong book');
    }
    final path = _inside(normalized);
    await _rejectLinks(path);
    return File(path);
  }

  Future<Directory> createStaging(String operationId) async {
    checkId(operationId);
    await ensureRoot();
    final path = _inside(p.join('staging', operationId));
    await _rejectLinks(path);
    return Directory(path).create();
  }

  Future<StoredFile> stageStream({
    required Directory staging,
    required String id,
    required String relative,
    required OpenInputStream openRead,
    required int maxBytes,
  }) async {
    checkId(id);
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    final stagingPath = p.normalize(p.absolute(staging.path));
    final operationId = p.basename(stagingPath);
    if (p.dirname(stagingPath) != _inside('staging')) {
      throw ArgumentError.value(
        staging.path,
        'staging',
        'outside staging root',
      );
    }
    checkId(operationId);
    if (p.isAbsolute(relative) ||
        p.normalize(relative) == '.' ||
        p.split(relative).contains('..')) {
      throw ArgumentError.value(relative, 'relative', 'path traversal');
    }
    final path = _inside(p.join('staging', operationId, relative));
    await _rejectLinks(path);
    await Directory(p.dirname(path)).create(recursive: true);
    final file = File(path);
    final writer = await file.open(mode: FileMode.write);
    final digestSink = _DigestSink();
    final hashSink = sha256.startChunkedConversion(digestSink);
    var size = 0;
    var complete = false;
    try {
      await for (final chunk in openRead()) {
        size += chunk.length;
        if (size > maxBytes) {
          throw FileSystemException('Input exceeds byte budget', path);
        }
        hashSink.add(chunk);
        // Await each write so a fast picker stream cannot queue the entire
        // input in memory while the destination is slow.
        await writer.writeFrom(chunk);
      }
      hashSink.close();
      await writer.flush();
      complete = true;
      return StoredFile(
        id: id,
        storedPath: relative,
        byteSize: size,
        sha256: digestSink.digest!.toString(),
      );
    } finally {
      await writer.close();
      if (!complete && await file.exists()) await file.delete();
    }
  }

  Future<void> writeMarker(
    String operationId, {
    required String kind,
    required String bookId,
    String? assetId,
    String? relativePath,
    String? sha256,
  }) async {
    checkId(operationId);
    checkId(bookId);
    if (assetId != null) checkId(assetId);
    final path = _inside(p.join('operations', '$operationId.json'));
    final temporary = _inside(p.join('operations', '$operationId.tmp'));
    await _rejectLinks(path);
    await _rejectLinks(temporary);
    final marker = <String, String>{'kind': kind, 'bookId': bookId};
    if (assetId != null) marker['assetId'] = assetId;
    if (relativePath != null) marker['relativePath'] = relativePath;
    if (sha256 != null) marker['sha256'] = sha256;
    if (await File(path).exists()) {
      throw StateError('Operation marker already exists');
    }
    await File(temporary).writeAsString(jsonEncode(marker), flush: true);
    await File(temporary).rename(path);
  }

  Future<void> removeMarker(String operationId) async {
    checkId(operationId);
    final file = File(_inside(p.join('operations', '$operationId.json')));
    await _rejectLinks(file.path);
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteStaging(String operationId) async {
    checkId(operationId);
    final directory = Directory(_inside(p.join('staging', operationId)));
    await _rejectLinks(directory.path);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> deleteBookDirectory(String bookId) async {
    final directory = Directory(_inside(bookRelativePath(bookId)));
    await _rejectLinks(directory.path);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> moveStagedBook(String operationId, String bookId) async {
    final from = Directory(_inside(p.join('staging', operationId)));
    final to = Directory(_inside(bookRelativePath(bookId)));
    await _rejectLinks(from.path);
    await _rejectLinks(to.path);
    if (await to.exists()) throw StateError('Book directory already exists');
    await from.rename(to.path);
  }

  Future<void> moveStagedAsset(
    String operationId,
    String bookId,
    String relative,
  ) async {
    final from = File(_inside(p.join('staging', operationId, relative)));
    final to = File(_inside(p.join(bookRelativePath(bookId), relative)));
    await _rejectLinks(from.path);
    await _rejectLinks(to.path);
    await to.parent.create(recursive: true);
    if (await to.exists()) throw StateError('Asset file already exists');
    await from.rename(to.path);
  }

  Future<void> deleteAssetFile(String bookId, String relative) async {
    final file = await resolveStoredPath(
      bookId,
      p.join(bookRelativePath(bookId), relative),
    );
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteUncommittedAsset(String bookId, String assetId) async {
    checkId(assetId);
    final directory = Directory(
      _inside(p.join(bookRelativePath(bookId), 'assets')),
    );
    await _rejectLinks(directory.path);
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && p.basename(entity.path).startsWith('$assetId.')) {
        await deleteAssetFile(
          bookId,
          p.join('assets', p.basename(entity.path)),
        );
      }
    }
  }

  Future<List<(String, Map<String, Object?>)>> readMarkers() async {
    await ensureRoot();
    final operations = Directory(_inside('operations'));
    final result = <(String, Map<String, Object?>)>[];
    await for (final entity in operations.list(followLinks: false)) {
      if (entity is! File) continue;
      final extension = p.extension(entity.path);
      if (extension != '.json' && extension != '.tmp') continue;
      await _rejectLinks(entity.path);
      final id = p.basenameWithoutExtension(entity.path);
      try {
        checkId(id);
      } on ArgumentError {
        continue;
      }
      if (extension == '.tmp') {
        // The final marker was never published, so no file move started.
        await entity.delete();
        continue;
      }
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is Map<String, dynamic>) {
          result.add((id, json.cast<String, Object?>()));
        }
      } on FormatException {
        // A damaged old marker does not make every book inaccessible. Leave
        // it untouched because its target cannot be proven from partial JSON.
      }
    }
    return result;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
