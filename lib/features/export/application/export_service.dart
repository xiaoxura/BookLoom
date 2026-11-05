import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/platform/job_cache.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

class ExportService {
  ExportService({
    required this.repository,
    required this.files,
    required this.jobs,
    required this.temporaryDirectory,
    this.renderTemplateCover,
  });

  final BookRepository repository;
  final FileService files;
  final BackgroundJobs jobs;
  final Directory temporaryDirectory;
  final Future<Uint8List> Function(Book)? renderTemplateCover;
  late final JobCache _cache = JobCache(temporaryDirectory);
  Future<void>? _cacheReady;
  final Logger _logger = Logger('export');
  bool _busy = false;
  bool _computing = false;
  bool _cancelled = false;
  bool _committing = false;
  bool get isCommitting => _committing;

  /// The editor must flush first. Snapshot reads share one DB transaction;
  /// generation and the native save dialog never mutate the current book.
  Future<SaveOutcome> exportBook(
    String bookId, {
    ExportFormat format = ExportFormat.epub3,
    void Function(JobProgress)? onProgress,
  }) => withPreparedExport(
    bookId,
    format: format,
    onProgress: onProgress,
    submit: files.savePreparedFile,
  );

  /// Keeps the task-private output alive until saving or sharing has copied it.
  Future<T> withPreparedExport<T>(
    String bookId, {
    ExportFormat format = ExportFormat.epub3,
    void Function(JobProgress)? onProgress,
    required Future<T> Function(
      File file, {
      required String suggestedName,
      required String mimeType,
    })
    submit,
  }) async {
    if (_busy || jobs.isBusy) {
      throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
    }
    _busy = true;
    _cancelled = false;
    CachedJob? cacheJob;
    try {
      await _ensureCacheReady();
      final includeResources =
          format == ExportFormat.epub3 || format == ExportFormat.epub2;
      final snapshot = await _snapshot(
        bookId,
        includeResources: includeResources,
      );
      if (_cancelled) throw const TaskCancelled();
      cacheJob = await _cache.create('export');
      final output = File(
        p.join(cacheJob.directory.path, 'book.${format.extension}'),
      );
      final generatedCover =
          includeResources && snapshot.book.coverMode == CoverMode.template
          ? await renderTemplateCover?.call(snapshot.book)
          : null;
      if (_cancelled) throw const TaskCancelled();
      _computing = true;
      try {
        await jobs.run(
          _ExportInput(snapshot, output.path, format, generatedCover),
          _write,
          revision: snapshot.book.revision,
          onProgress: onProgress,
        );
      } finally {
        _computing = false;
      }
      if (_cancelled) throw const TaskCancelled();
      onProgress?.call(JobProgress(0, snapshot.book.revision, 1, 'save'));
      _committing = true;
      return await submit(
        output,
        suggestedName: '${snapshot.book.meta.title}.${format.extension}',
        mimeType: format.mimeType,
      );
    } on AppFailure {
      rethrow;
    } on Object catch (error, stack) {
      throw ExportFailure(
        '导出失败，当前书稿仍已保留。请检查保存位置后重试。',
        cause: error,
        stackTrace: stack,
      );
    } finally {
      if (cacheJob != null) {
        try {
          await cacheJob.dispose();
        } on Object {
          _logger.warning('export cache cleanup deferred');
        }
      }
      _busy = false;
      _committing = false;
    }
  }

  Future<void> _recoverCache() async {
    await _cache.recover();
  }

  Future<void> _ensureCacheReady() async {
    try {
      await (_cacheReady ??= _recoverCache());
    } on Object {
      _cacheReady = null;
      rethrow;
    }
  }

  Future<_ExportPlan> _snapshot(
    String bookId, {
    required bool includeResources,
  }) async {
    // Ensure repository crash recovery has completed before entering the read
    // transaction (its first-use recovery itself may need a transaction).
    if (await repository.loadBook(bookId) == null) {
      throw const ExportFailure('找不到这本书，请返回书架后重试。');
    }
    return repository.db.transaction(() async {
      final Book? book = await repository.loadBook(bookId);
      if (book == null) throw const ExportFailure('书籍已被删除。');
      final chapters = <Chapter>[];
      for (final chapter in book.chapters) {
        if (_cancelled) throw const TaskCancelled();
        final body = await repository.loadChapter(bookId, chapter.id);
        if (body == null) throw const ExportFailure('章节无法读取，请重新打开书稿。');
        chapters.add(body);
      }
      final assets = await repository.loadAssets(bookId);
      final resources = <_AssetInput>[];
      for (final asset in assets) {
        if (!includeResources) break;
        final isCover =
            book.coverMode == CoverMode.image && book.coverAssetId == asset.id;
        final isFont = book.layout.embeddedFontAssetId == asset.id;
        if (!isCover && !isFont) continue;
        final maxBytes = isCover
            ? ImportLimits.maxEncodedCoverBytes
            : ImportLimits.maxFontBytes;
        if (asset.byteSize > maxBytes) {
          throw const ExportFailure('资源超过导出预算，请移除过大的封面或字体。');
        }
        final resource = await repository.resolveAsset(asset);
        if (!await resource.exists()) {
          throw const ExportFailure('封面或字体文件缺失，请重新选择资源后导出。');
        }
        resources.add(
          _AssetInput(
            asset.id,
            resource.path,
            p.basename(asset.storedPath),
            asset.mime,
            asset.byteSize,
            asset.sha256,
            isCover,
            isFont,
          ),
        );
      }
      if (includeResources &&
          book.layout.embeddedFontAssetId != null &&
          !resources.any((item) => item.isFont)) {
        throw const ExportFailure('嵌入字体引用失效，请移除或重新选择字体。');
      }
      if (includeResources &&
          book.coverMode == CoverMode.image &&
          !resources.any((item) => item.isCover)) {
        throw const ExportFailure('当前封面引用失效，请重新选择封面。');
      }
      return _ExportPlan(book.copyWith(chapters: chapters), resources);
    });
  }

  void cancel() {
    if (!_busy || _committing) return;
    _cancelled = true;
    if (_computing) jobs.cancelActive();
  }
}

class _ExportInput {
  const _ExportInput(
    this.snapshot,
    this.path,
    this.format,
    this.generatedCover,
  );
  final _ExportPlan snapshot;
  final String path;
  final ExportFormat format;
  final Uint8List? generatedCover;
}

bool _write(_ExportInput input, void Function(double, String) progress) {
  try {
    return _writeSnapshot(input, progress);
  } on FileSystemException {
    throw const ExportFailure('临时文件无法生成，请检查应用数据目录的权限与剩余空间。');
  } on FormatException {
    throw const ExportFailure('导出结构检查未通过，请检查章节和资源后重试。');
  }
}

bool _writeSnapshot(
  _ExportInput input,
  void Function(double, String) progress,
) {
  progress(0.1, 'generate');
  Uint8List? cover = input.generatedCover;
  var coverMime = 'image/jpeg';
  final fonts = <ExportFont>[];
  for (final resource in input.snapshot.resources) {
    final bytes = _readResource(resource);
    if (resource.isCover) {
      cover = bytes;
      coverMime = resource.mime;
    }
    if (resource.isFont) {
      fonts.add(
        ExportFont(
          assetId: resource.id,
          fileName: resource.fileName,
          bytes: bytes,
        ),
      );
    }
  }
  writeDocument(
    ExportSnapshot(
      book: input.snapshot.book,
      coverBytes: cover,
      coverMime: coverMime,
      fonts: fonts,
    ),
    input.path,
    format: input.format,
  );
  progress(1, 'ready');
  return true;
}

class _ExportPlan {
  const _ExportPlan(this.book, this.resources);
  final Book book;
  final List<_AssetInput> resources;
}

class _AssetInput {
  const _AssetInput(
    this.id,
    this.path,
    this.fileName,
    this.mime,
    this.expectedBytes,
    this.expectedHash,
    this.isCover,
    this.isFont,
  );
  final String id;
  final String path;
  final String fileName;
  final String mime;
  final int expectedBytes;
  final String expectedHash;
  final bool isCover;
  final bool isFont;
}

// Runs in the export isolate. A stale DB size must never allow an unbounded
// read on the UI isolate, and changing files must not enter the output.
Uint8List _readResource(_AssetInput input) {
  final file = File(input.path).openSync();
  final maxBytes = input.isCover
      ? ImportLimits.maxEncodedCoverBytes
      : ImportLimits.maxFontBytes;
  try {
    if (file.lengthSync() > maxBytes ||
        file.lengthSync() != input.expectedBytes) {
      throw const ExportFailure('资源大小已变化或超过预算，请重新选择封面或字体。');
    }
    final bytes = BytesBuilder(copy: false);
    while (true) {
      final chunk = file.readSync(64 * 1024);
      if (chunk.isEmpty) break;
      if (bytes.length + chunk.length > maxBytes) {
        throw const ExportFailure('资源实际大小超过预算，已停止导出。');
      }
      bytes.add(chunk);
    }
    final result = bytes.takeBytes();
    if (result.length != input.expectedBytes ||
        sha256.convert(result).toString() != input.expectedHash) {
      throw const ExportFailure('资源内容已变化，请重新选择封面或字体后导出。');
    }
    return result;
  } finally {
    file.closeSync();
  }
}
