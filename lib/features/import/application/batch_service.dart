import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/formatting/export_snapshot.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/parsing/rules.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/file_names.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/platform/job_cache.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'import_service.dart';

enum BatchMode { addToLibrary, convertFiles }

enum BatchItemStatus { waiting, processing, success, failed, cancelled }

class BatchItem {
  BatchItem._(this.input, this.index);

  final PickedInput input;
  final int index;
  BatchItemStatus status = BatchItemStatus.waiting;
  String? error;
  String? outputName;
  String? bookId;
  String? stage;
  double? progress;
  int? _observedBytes;
  ParseOptions? _retryOptions;
}

/// Runs one fixed batch through the shared import/export worker and owns only
/// its private scratch files. Converted books never enter the repository.
class BatchService extends ChangeNotifier {
  BatchService({
    required this.repository,
    required this.files,
    required this.jobs,
    required this.importService,
    required this.temporaryDirectory,
    this.renderTemplateCover,
  });

  final BookRepository repository;
  final FileService files;
  final BackgroundJobs jobs;
  final ImportService importService;
  final Directory temporaryDirectory;
  final Future<Uint8List> Function(Book)? renderTemplateCover;
  late final JobCache _cache = JobCache(temporaryDirectory);
  CachedJob? _outputJob;
  final List<BatchItem> _items = [];
  BatchMode _mode = BatchMode.addToLibrary;
  ExportFormat _format = ExportFormat.epub3;
  ParseOptions _options = const ParseOptions();
  LayoutOptions _layout = LayoutOptions();
  bool _running = false;
  bool _committing = false;
  bool _cancelRequested = false;
  bool _writing = false;
  bool _saving = false;
  bool _closing = false;
  Completer<void>? _idle;
  Future<void>? _shutdownFuture;
  SaveOutcome? _saveOutcome;

  List<BatchItem> get items => List<BatchItem>.unmodifiable(_items);
  BatchMode get mode => _mode;
  ExportFormat get format => _format;
  bool get isRunning => _running || _saving;
  bool get isCommitting => _committing;
  SaveOutcome? get saveOutcome => _saveOutcome;
  bool get canSaveZip =>
      !_running &&
      !_saving &&
      _mode == BatchMode.convertFiles &&
      _items.any((item) => item.status == BatchItemStatus.success);

  Future<List<PickedInput>> selectFiles() => files.pickImports();

  /// Replacing a queue releases its input leases and generated output only
  /// after any active consumer has finished.
  Future<void> enqueue(
    List<PickedInput> inputs, {
    required BatchMode mode,
    ExportFormat format = ExportFormat.epub3,
    ParseOptions options = const ParseOptions(),
    LayoutOptions? layout,
  }) async {
    if (_closing || isRunning) {
      throw const ValidationFailure('批量任务仍在运行或正在关闭。');
    }
    if (inputs.isEmpty) throw const ValidationFailure('请先选择文件。');
    if (inputs.length > ImportLimits.maxBatchInputs) {
      throw const ValidationFailure('一次最多处理 40 个文件。');
    }
    var announcedBytes = 0;
    for (final input in inputs) {
      if (!const {
        '.txt',
        '.epub',
        '.docx',
      }.contains(p.extension(input.name).toLowerCase())) {
        throw ImportFailure('“${input.name}”的格式不受支持。');
      }
      final size = input.size;
      if (size != null) {
        if (size < 0 || size > ImportLimits.maxSingleInputBytes) {
          throw ImportFailure('“${input.name}”超过单文件 80 MiB 上限。');
        }
        announcedBytes += size;
      }
    }
    if (announcedBytes > ImportLimits.maxBatchInputBytes) {
      throw const ValidationFailure('文件合计超过 200 MiB 上限。');
    }
    final fixedOptions = _freezeOptions(options);
    await _disposeOutput();
    if (_items.isNotEmpty) {
      await _releaseInputs(retaining: inputs);
      await files.clearTemporaryFiles();
    }
    _items
      ..clear()
      ..addAll([
        for (var i = 0; i < inputs.length; i++) BatchItem._(inputs[i], i),
      ]);
    _mode = mode;
    _format = format;
    _options = fixedOptions;
    _layout = layout ?? LayoutOptions();
    _cancelRequested = false;
    _saveOutcome = null;
    notifyListeners();
  }

  Future<void> start() => _run(retryOnly: false);

  Future<void> retryFailed() => _run(retryOnly: true);

  /// A failed TXT item may use a different encoding on its next attempt.
  void setRetryOptions(int index, ParseOptions options) {
    if (isRunning || index < 0 || index >= _items.length) {
      throw const ValidationFailure('当前无法修改重试选项。');
    }
    final item = _items[index];
    if (item.status != BatchItemStatus.failed ||
        p.extension(item.input.name).toLowerCase() != '.txt') {
      throw const ValidationFailure('只有失败的 TXT 文件可以修改编码。');
    }
    item._retryOptions = options;
    notifyListeners();
  }

  ParseOptions retryOptionsFor(int index) =>
      _items[index]._retryOptions ?? _options;

  Future<void> _run({required bool retryOnly}) async {
    if (_closing) throw const ValidationFailure('批量任务正在关闭。');
    if (isRunning) throw const ValidationFailure('另一项批量任务正在运行。');
    if (_items.isEmpty) throw const ValidationFailure('请先选择文件。');
    final pending = retryOnly
        ? _items.where((item) => item.status == BatchItemStatus.failed).toList()
        : _items
              .where((item) => item.status == BatchItemStatus.waiting)
              .toList();
    if (pending.isEmpty) return;
    if (jobs.isBusy) throw const ValidationFailure('另一项后台任务正在运行，请稍候。');
    _running = true;
    _idle = Completer<void>();
    _cancelRequested = false;
    _saveOutcome = null;
    notifyListeners();
    try {
      if (_mode == BatchMode.convertFiles && _outputJob == null) {
        _outputJob = await _cache.create('export');
      }
      for (final item in pending) {
        if (_cancelRequested) {
          _setStatus(item, BatchItemStatus.cancelled);
          continue;
        }
        _setStatus(item, BatchItemStatus.processing);
        PreparedImport? prepared;
        try {
          final measuredInput = PickedInput(
            name: item.input.name,
            size: item.input.size,
            openRead: () => _boundedRead(item),
          );
          prepared = await importService.prepare(
            measuredInput,
            options: p.extension(item.input.name).toLowerCase() == '.txt'
                ? (item._retryOptions ?? _options)
                : _options.copyWith(
                    encoding: 'auto',
                    rulePreset: 'auto',
                    clearRuleSpec: true,
                  ),
            onProgress: (progress) => _progress(item, progress),
          );
          if (_cancelRequested) throw const TaskCancelled();
          if (_mode == BatchMode.addToLibrary) {
            _committing = true;
            notifyListeners();
            final book = await importService.commit(prepared);
            prepared = null;
            item.bookId = book.id;
          } else {
            await _convert(item, prepared);
          }
          _setStatus(item, BatchItemStatus.success);
        } on TaskCancelled {
          _setStatus(item, BatchItemStatus.cancelled);
        } on AppFailure catch (error) {
          item.error = error.message;
          _setStatus(item, BatchItemStatus.failed);
        } on Object {
          item.error = '处理失败，请检查文件后重试。';
          _setStatus(item, BatchItemStatus.failed);
        } finally {
          _committing = false;
          if (prepared != null) {
            try {
              await importService.discard(prepared);
            } on Object {
              // The item result is still authoritative; stale cache is
              // recovered on the next service use.
            }
          }
          notifyListeners();
        }
      }
    } finally {
      _running = false;
      _committing = false;
      notifyListeners();
      _idle?.complete();
      _idle = null;
    }
  }

  Stream<List<int>> _boundedRead(BatchItem item) async* {
    var bytes = 0;
    await for (final chunk in item.input.openRead()) {
      // End the borrowed stream normally. ImportService owns the active
      // preparation and will surface its own TaskCancelled after closing the
      // file sink; throwing through IOSink.addStream can instead be wrapped
      // as a file read failure while the sink is closing.
      if (_cancelRequested) return;
      bytes += chunk.length;
      if (bytes > ImportLimits.maxSingleInputBytes) {
        throw ImportFailure('“${item.input.name}”实际大小超过 80 MiB。');
      }
      final observed = item._observedBytes ?? 0;
      if (bytes > observed) {
        final otherBytes = _items.fold<int>(0, (sum, current) {
          if (identical(current, item)) return sum;
          final declared = current.input.size ?? 0;
          final actual = current._observedBytes ?? 0;
          return sum + (actual > declared ? actual : declared);
        });
        final currentBudget = bytes > (item.input.size ?? 0)
            ? bytes
            : (item.input.size ?? 0);
        if (otherBytes + currentBudget > ImportLimits.maxBatchInputBytes) {
          throw const ImportFailure('实际输入总量超过 200 MiB，已停止读取。');
        }
        item._observedBytes = bytes;
      }
      yield chunk;
    }
  }

  Future<void> _convert(BatchItem item, PreparedImport prepared) async {
    final now = DateTime.now().toUtc();
    final cover = prepared.cover;
    final book = Book(
      id: prepared.bookId,
      meta: prepared.result.suggestedMeta,
      chapters: prepared.result.chapters,
      parseOptions: prepared.options,
      layout: _layout,
      coverMode: cover == null ? CoverMode.template : CoverMode.image,
      coverAssetId: cover == null ? null : 'staged-cover',
      wordCount: prepared.wordCount,
      createdAt: now,
      updatedAt: now,
    );
    final names = _items.map((entry) => entry.outputName).whereType<String>();
    final name = FileNames.unique(
      '${book.meta.title.trim().isEmpty ? p.basenameWithoutExtension(item.input.name) : book.meta.title}.${_format.extension}',
      names,
    );
    final output = File(p.join(_outputJob!.directory.path, name));
    Uint8List? generatedCover;
    if (_format == ExportFormat.epub3 || _format == ExportFormat.epub2) {
      if (cover == null) generatedCover = await renderTemplateCover?.call(book);
    }
    if (_cancelRequested) throw const TaskCancelled();
    try {
      _writing = true;
      try {
        await jobs.run(
          _BatchWriteInput(
            book: book,
            outputPath: output.path,
            format: _format,
            coverPath: cover?.file.path,
            coverMime: cover?.mime ?? 'image/jpeg',
            generatedCover: generatedCover,
          ),
          _writeBatchDocument,
          revision: 0,
          onProgress: (progress) => _progress(item, progress),
        );
      } finally {
        _writing = false;
      }
      if (_cancelRequested) throw const TaskCancelled();
      item.outputName = name;
    } on Object {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  /// Packages only successful outputs and a status manifest. Native save
  /// cancellation is returned distinctly and leaves the batch results intact.
  Future<SaveOutcome> saveZip() async {
    if (_closing) throw const ValidationFailure('批量任务正在关闭。');
    if (!canSaveZip) throw const ValidationFailure('当前没有可保存的转换结果。');
    if (jobs.isBusy) throw const ValidationFailure('另一项后台任务正在运行，请稍候。');
    _saving = true;
    _idle = Completer<void>();
    _cancelRequested = false;
    _saveOutcome = null;
    notifyListeners();
    final zip = File(p.join(_outputJob!.directory.path, 'batch-results.zip'));
    try {
      if (await zip.exists()) await zip.delete();
      await jobs.run(
        _BatchZipInput(
          zip.path,
          _outputJob!.directory.path,
          [
            for (final item in _items)
              if (item.status == BatchItemStatus.success) item.outputName!,
          ],
          jsonEncode({
            'version': 1,
            'mode': _mode.name,
            'format': _format.name,
            'results': [
              for (final item in _items)
                {
                  'input': item.input.name,
                  'status': item.status.name,
                  'output': item.outputName,
                  'error': item.error,
                },
            ],
          }),
        ),
        _writeBatchZip,
        revision: 0,
      );
      _committing = true;
      notifyListeners();
      final outcome = await files.savePreparedFile(
        zip,
        suggestedName: 'bookloom-batch.zip',
        mimeType: 'application/zip',
      );
      _saveOutcome = outcome;
      return outcome;
    } on Object {
      if (await zip.exists()) await zip.delete();
      rethrow;
    } finally {
      _committing = false;
      _saving = false;
      notifyListeners();
      _idle?.complete();
      _idle = null;
    }
  }

  void cancel() {
    if (!isRunning || _cancelRequested) return;
    if (_saving && _committing) return;
    _cancelRequested = true;
    if (!_committing) {
      importService.cancel();
      if (_writing || _saving) jobs.cancelActive();
    }
    notifyListeners();
  }

  void _progress(BatchItem item, JobProgress progress) {
    if (item.status != BatchItemStatus.processing) return;
    item.progress = progress.fraction;
    item.stage = progress.stage;
    notifyListeners();
  }

  void _setStatus(BatchItem item, BatchItemStatus status) {
    item.status = status;
    item.progress = null;
    item.stage = null;
    if (status == BatchItemStatus.processing) item.error = null;
    notifyListeners();
  }

  Future<void> _disposeOutput() async {
    final job = _outputJob;
    _outputJob = null;
    if (job != null) await job.dispose();
  }

  Future<void> _releaseInputs({
    Iterable<PickedInput> retaining = const [],
  }) async {
    final retained = Set<PickedInput>.identity()..addAll(retaining);
    final released = Set<PickedInput>.identity();
    for (final item in _items) {
      final input = item.input;
      if (!retained.contains(input) && released.add(input)) {
        await input.release();
      }
    }
  }

  /// Cancels interruptible work, waits for any native commit to finish, then
  /// reclaims this service's output and picker copies exactly once.
  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _closing = true;
    cancel();
    await _idle?.future;
    try {
      await _disposeOutput();
      await _releaseInputs();
      await files.clearTemporaryFiles();
    } finally {
      dispose();
    }
  }

  Future<void> close() => shutdown();
}

ParseOptions _freezeOptions(ParseOptions options) {
  try {
    final spec = options.ruleSpec == null
        ? null
        : RuleSpec.fromMap(options.ruleSpec);
    spec?.toJsonString();
    final canonical = spec?.toMap();
    final ruleSpec = canonical == null
        ? null
        : Map<String, Object?>.unmodifiable({
            for (final entry in canonical.entries)
              entry.key: entry.value is List<String>
                  ? List<String>.unmodifiable(entry.value as List<String>)
                  : entry.value,
          });
    final frozen = options.copyWith(ruleSpec: ruleSpec);
    resolveTxtRules(frozen);
    return frozen;
  } on RuleValidationException catch (error) {
    throw ValidationFailure('解析规则无效：${error.message}');
  }
}

class _BatchWriteInput {
  const _BatchWriteInput({
    required this.book,
    required this.outputPath,
    required this.format,
    required this.coverPath,
    required this.coverMime,
    required this.generatedCover,
  });
  final Book book;
  final String outputPath;
  final ExportFormat format;
  final String? coverPath;
  final String coverMime;
  final Uint8List? generatedCover;
}

bool _writeBatchDocument(
  _BatchWriteInput input,
  void Function(double, String) progress,
) {
  progress(0.1, 'generate');
  final cover = input.coverPath == null
      ? input.generatedCover
      : File(input.coverPath!).readAsBytesSync();
  writeDocument(
    ExportSnapshot(
      book: input.book,
      coverBytes: cover,
      coverMime: input.coverMime,
    ),
    input.outputPath,
    format: input.format,
  );
  progress(1, 'ready');
  return true;
}

class _BatchZipInput {
  const _BatchZipInput(this.path, this.directory, this.names, this.manifest);
  final String path;
  final String directory;
  final List<String> names;
  final String manifest;
}

bool _writeBatchZip(
  _BatchZipInput input,
  void Function(double, String) progress,
) {
  final output = OutputFileStream(input.path);
  final encoder = ZipEncoder(streamed: true)..startEncode(output, level: 6);
  try {
    for (var i = 0; i < input.names.length; i++) {
      final name = input.names[i];
      encoder.add(
        ArchiveFile.stream(
          name,
          InputFileStream(p.join(input.directory, name)),
        ),
      );
      progress((i + 1) / (input.names.length + 1), 'zip');
    }
    encoder.add(ArchiveFile.string('result-manifest.json', input.manifest));
    encoder.endEncode();
    progress(1, 'ready');
    return true;
  } finally {
    output.closeSync();
  }
}
