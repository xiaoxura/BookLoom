import 'dart:io';

import 'package:bookloom/core/conversion/opencc_converter.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/model/parse_result.dart';
import 'package:bookloom/core/parsing/structured_import.dart';
import 'package:bookloom/core/parsing/txt_encoding.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/platform/job_cache.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// A validated, temporary import. It is not a second editable book or a shelf
/// entry. The original source is retained until commit or discard finishes.
class PreparedImport {
  PreparedImport._(
    this.bookId,
    this.originalName,
    this.result,
    this.options,
    this._cacheJob,
    this._source,
    this.cover,
    this.isReparse,
    this.layout,
  );

  final String bookId;
  final String originalName;
  final ParseResult result;
  final ParseOptions options;
  final CachedJob _cacheJob;
  final File _source;
  final StagedCover? cover;
  final bool isReparse;
  final LayoutOptions layout;
  bool _finished = false;
  bool _committing = false;

  int get wordCount => result.chapters.fold<int>(
    0,
    (int count, chapter) => count + WordCount.ofBlocks(chapter.blocks),
  );
}

class ImportService {
  ImportService({
    required this.repository,
    required this.jobs,
    required this.temporaryDirectory,
    this.loadDictionaries,
    this.loadDefaultLayout,
  });

  final BookRepository repository;
  final BackgroundJobs jobs;
  final Directory temporaryDirectory;
  final Future<Map<String, String>> Function()? loadDictionaries;
  final Future<LayoutOptions> Function()? loadDefaultLayout;
  Future<Map<String, String>>? _dictionaryData;
  late final JobCache _cache = JobCache(temporaryDirectory);
  Future<void>? _cacheReady;
  bool _busy = false;
  bool _reparsing = false;
  bool _cancelled = false;
  bool _computing = false;
  final Logger _logger = Logger('import');

  Future<PreparedImport> prepare(
    PickedInput input, {
    ParseOptions options = const ParseOptions(),
    void Function(JobProgress)? onProgress,
  }) => _prepare(input, options: options, onProgress: onProgress);

  /// Prepares replacement chapters without mutating the current book or metadata.
  /// A reselected source must match the saved original hash.
  Future<PreparedImport> prepareReparse(
    String bookId, {
    required ParseOptions options,
    PickedInput? replacementInput,
    void Function(JobProgress)? onProgress,
  }) async {
    if (_busy || _reparsing) throw const ValidationFailure('导入仍在进行，请等待或取消。');
    _reparsing = true;
    _cancelled = false;
    try {
      final source = await repository.loadSource(bookId);
      if (source == null || source.format != 'txt') {
        throw const ImportFailure('只有保留 TXT 原文的书稿可以重新识别。');
      }
      final file = await repository.resolveSource(source);
      final sourceMissing = !await file.exists();
      final input =
          replacementInput ??
          (!sourceMissing
              ? PickedInput(
                  name: source.originalName,
                  size: source.byteSize,
                  openRead: file.openRead,
                )
              : null);
      if (input == null) {
        throw const ImportFailure('原文已缺失。请重新选择同一个原文件；当前书稿仍可继续编辑。');
      }
      final prepared = await _prepare(
        input,
        options: options,
        onProgress: onProgress,
        targetBookId: bookId,
        expectedSourceHash: source.sha256,
        reparseReserved: true,
      );
      try {
        if (_cancelled) throw const TaskCancelled();
        if (sourceMissing) {
          await repository.reattachMissingSource(
            bookId,
            SourceImport(
              format: source.format,
              originalName: source.originalName,
              openRead: prepared._source.openRead,
            ),
          );
        }
        return prepared;
      } on Object {
        prepared._finished = true;
        await _cleanFailure(prepared._cacheJob);
        rethrow;
      }
    } finally {
      _reparsing = false;
    }
  }

  Future<PreparedImport> _prepare(
    PickedInput input, {
    required ParseOptions options,
    void Function(JobProgress)? onProgress,
    String? targetBookId,
    String? expectedSourceHash,
    bool reparseReserved = false,
  }) async {
    if (_busy || (_reparsing && !reparseReserved)) {
      throw const ValidationFailure('导入仍在进行，请等待或取消。');
    }
    final extension = p.extension(input.name).toLowerCase();
    if (!const ['.txt', '.epub', '.docx'].contains(extension)) {
      throw const ImportFailure('请选择 TXT、EPUB 或 DOCX 文件。');
    }
    if ((input.size ?? 0) > ImportLimits.maxInputBytes) {
      throw const ImportFailure('文件超过 80 MiB，请先拆分书稿再导入。');
    }
    if (reparseReserved && _cancelled) throw const TaskCancelled();
    _busy = true;
    if (!reparseReserved) _cancelled = false;
    CachedJob? cacheJob;
    try {
      await _ensureCacheReady();
      cacheJob = await _cache.create('import');
      final directory = cacheJob.directory;
      final source = File(p.join(directory.path, 'source$extension'));
      final sink = source.openWrite();
      try {
        await sink.addStream(_boundedInput(input));
        await sink.flush();
      } on Object catch (error, stack) {
        try {
          await sink.close();
        } on Object {
          _logger.fine('import sink close failed after read error');
        }
        Error.throwWithStackTrace(error, stack);
      }
      await sink.close();
      if (_cancelled) throw const TaskCancelled();
      if (expectedSourceHash != null &&
          (await sha256.bind(source.openRead()).first).toString() !=
              expectedSourceHash) {
        throw const ImportFailure('所选文件与保存的原文不一致，当前书稿未改变。');
      }
      final dictionaries = options.convertMode == ConvertMode.none
          ? const <String, String>{}
          : await (_dictionaryData ??= _loadDictionaries());
      if (_cancelled) throw const TaskCancelled();
      final bookId = targetBookId ?? const Uuid().v4();
      if (jobs.isBusy) {
        throw const ValidationFailure('另一项任务正在运行，请完成后再导入。');
      }
      late final StructuredImport parsed;
      _computing = true;
      try {
        parsed = await jobs.run(
          _ParseInput(
            source.path,
            bookId,
            input.name,
            options,
            directory.path,
            dictionaries,
          ),
          _parse,
          revision: 0,
          onProgress: onProgress,
        );
      } finally {
        _computing = false;
      }
      if (_cancelled) throw const TaskCancelled();
      final result = parsed.result;
      if (result.chapters.isEmpty) {
        throw const ImportFailure('书稿没有可导入的内容，请检查文件或编码。');
      }
      final layout = await loadDefaultLayout?.call() ?? LayoutOptions();
      if (_cancelled) throw const TaskCancelled();
      return PreparedImport._(
        bookId,
        input.name,
        result,
        options,
        cacheJob,
        source,
        parsed.cover,
        targetBookId != null,
        layout,
      );
    } on AppFailure {
      await _cleanFailure(cacheJob);
      rethrow;
    } on Object catch (error, stack) {
      await _cleanFailure(cacheJob);
      throw ImportFailure(
        '无法读取或解析书稿。请检查文件权限和编码后重试。',
        cause: error,
        stackTrace: stack,
      );
    } finally {
      _busy = false;
    }
  }

  Future<Book> commit(
    PreparedImport prepared, {
    void Function(JobProgress)? onProgress,
  }) async {
    if (prepared.isReparse) throw const ValidationFailure('重新识别结果只能在原书稿中应用。');
    if (prepared._finished || prepared._committing) {
      throw const ValidationFailure('导入已完成或正在保存，请返回书架。');
    }
    prepared._committing = true;
    final totalWatch = Stopwatch()..start();
    final chapterCount = prepared.result.chapters.length;
    final blockCount = prepared.result.chapters.fold<int>(
      0,
      (count, chapter) => count + chapter.blocks.length,
    );
    final totalSteps = chapterCount + blockCount + 3;
    void report(int completedSteps, String stage) {
      try {
        onProgress?.call(JobProgress(0, 0, completedSteps / totalSteps, stage));
      } on Object {
        return;
      }
    }

    try {
      report(0, 'save_prepare');
      final now = DateTime.now().toUtc();
      final coverId = prepared.cover == null ? null : const Uuid().v4();
      final book = Book(
        id: prepared.bookId,
        meta: prepared.result.suggestedMeta,
        chapters: prepared.result.chapters,
        parseOptions: prepared.options,
        layout: prepared.layout,
        coverMode: coverId == null ? CoverMode.template : CoverMode.image,
        coverAssetId: coverId,
        wordCount: prepared.wordCount,
        createdAt: now,
        updatedAt: now,
      );
      final storageWatch = Stopwatch()..start();
      final stored = await repository.createBook(
        book,
        assets: [
          if (prepared.cover case final cover?)
            AssetImport(
              id: coverId,
              kind: 'cover',
              mime: cover.mime,
              extension: cover.mime.split('/').last,
              openRead: cover.file.openRead,
              width: cover.width,
              height: cover.height,
            ),
        ],
        source: SourceImport(
          format: prepared.result.format.wire,
          originalName: prepared.originalName,
          openRead: prepared._source.openRead,
        ),
        onProgress: (chaptersWritten, blocksWritten, stage) {
          final completedSteps = switch (stage) {
            'save_prepare' => 1,
            'save_finalize' => totalSteps - 1,
            _ => 1 + chaptersWritten + blocksWritten,
          };
          report(completedSteps, stage);
        },
      );
      storageWatch.stop();
      prepared._finished = true;
      final cleanupWatch = Stopwatch()..start();
      try {
        await _clean(prepared);
      } on Object {
        // A committed book stays successful even if cache reclamation fails.
        _logger.warning('import cache cleanup deferred');
      }
      cleanupWatch.stop();
      report(totalSteps, 'save_finalize');
      totalWatch.stop();
      _logger.info(
        'import commit success chapters=$chapterCount blocks=$blockCount '
        'words=${book.wordCount} storage_ms=${storageWatch.elapsedMilliseconds} '
        'cleanup_ms=${cleanupWatch.elapsedMilliseconds} total_ms=${totalWatch.elapsedMilliseconds}',
      );
      return stored;
    } on AppFailure {
      rethrow;
    } on Object catch (error, stack) {
      throw StorageFailure(
        '书稿尚未保存，请检查磁盘空间后重试。',
        cause: error,
        stackTrace: stack,
      );
    } finally {
      prepared._committing = false;
    }
  }

  Future<void> discard(PreparedImport prepared) async {
    if (prepared._committing) {
      throw const ValidationFailure('正在完成保存，请稍候。');
    }
    prepared._finished = true;
    await _clean(prepared);
  }

  Future<Map<String, String>> _loadDictionaries() async {
    final loader = loadDictionaries;
    if (loader == null) throw const ImportFailure('离线转换词典尚未加载，请重试。');
    try {
      return await loader();
    } on Object {
      _dictionaryData = null;
      rethrow;
    }
  }

  Future<void> _clean(PreparedImport prepared) => prepared._cacheJob.dispose();

  Future<void> _cleanFailure(CachedJob? job) async {
    if (job == null) return;
    try {
      await job.dispose();
    } on Object {
      _logger.warning('import cache cleanup deferred');
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

  void cancel() {
    if (!_busy && !_reparsing) return;
    _cancelled = true;
    if (_computing) jobs.cancelActive();
  }

  Stream<List<int>> _boundedInput(PickedInput input) async* {
    var actualBytes = 0;
    await for (final chunk in input.openRead()) {
      if (_cancelled) throw const TaskCancelled();
      actualBytes += chunk.length;
      if (actualBytes > ImportLimits.maxInputBytes) {
        throw const ImportFailure('实际文件大小超过 80 MiB，已停止导入。');
      }
      yield chunk;
    }
  }
}

class _ParseInput {
  const _ParseInput(
    this.path,
    this.bookId,
    this.filename,
    this.options,
    this.temporaryPath,
    this.dictionaries,
  );
  final String path;
  final String bookId;
  final String filename;
  final ParseOptions options;
  final String temporaryPath;
  final Map<String, String> dictionaries;
}

StructuredImport _parse(
  _ParseInput input,
  void Function(double, String) progress,
) {
  try {
    progress(0.1, 'decode');
    final parseOptions = input.options.copyWith(convertMode: ConvertMode.none);
    final StructuredImport parsed;
    if (p.extension(input.filename).toLowerCase() == '.txt') {
      parsed = StructuredImport(
        result: parseTxtBytes(
          File(input.path).readAsBytesSync(),
          bookId: input.bookId,
          filename: input.filename,
          options: parseOptions,
        ),
      );
    } else {
      parsed = parseStructuredFileSync(
        input.path,
        bookId: input.bookId,
        filename: input.filename,
        options: parseOptions,
        temporaryDirectory: Directory(input.temporaryPath),
      );
    }
    final original = parsed.result;
    if (input.options.convertMode == ConvertMode.none) {
      progress(1, 'ready');
      return parsed;
    }
    progress(0.8, 'convert');
    final converter = OpenCcConverter.loadData(input.dictionaries);
    String convert(String text) =>
        converter.convertText(text, input.options.convertMode);
    final converted = ParseResult(
      format: original.format,
      actualEncoding: original.actualEncoding,
      encodingConfidence: original.encodingConfidence,
      suggestedMeta: original.suggestedMeta.copyWith(
        title: convert(original.suggestedMeta.title),
        author: convert(original.suggestedMeta.author),
        description: convert(original.suggestedMeta.description),
      ),
      chapters: [
        for (final chapter in original.chapters)
          chapter.copyWith(
            title: convert(chapter.title),
            blocks: [
              for (final block in chapter.blocks)
                if (block is TextBlock)
                  TextBlock(id: block.id, text: convert(block.text))
                else
                  block,
            ],
          ),
      ],
      warnings: original.warnings,
      sourceLocations: original.sourceLocations,
    );
    progress(1, 'ready');
    return StructuredImport(result: converted, cover: parsed.cover);
  } on FileSystemException {
    throw const ImportFailure('暂存原文无法读取，请检查磁盘空间并重新选择书稿。');
  } on FormatException catch (error) {
    throw ImportFailure('文件编码、容器或解析规则无效：${error.message}');
  } on ArgumentError {
    throw const ImportFailure('解析选项无效，请重新选择编码或规则后重试。');
  } on UnsupportedError catch (error) {
    throw ImportFailure('当前无法应用所选解析选项：${error.message}');
  }
}
