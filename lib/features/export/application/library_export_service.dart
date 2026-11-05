import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/file_names.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/platform/job_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'export_service.dart';

enum LibraryExportStatus { waiting, processing, success, failed, cancelled }

class LibraryExportItem {
  LibraryExportItem._(this.bookId);

  final String bookId;
  LibraryExportStatus status = LibraryExportStatus.waiting;
  String? title;
  String? outputName;
  String? error;
  String? stage;
  double? progress;
}

/// Serializes exports of current library content. Each book is rendered by
/// ExportService, so its own cover, font and layout stay attached to its text.
class LibraryExportService extends ChangeNotifier {
  LibraryExportService({
    required this.exportService,
    required this.files,
    required this.jobs,
    required this.temporaryDirectory,
  });

  final ExportService exportService;
  final FileService files;
  final BackgroundJobs jobs;
  final Directory temporaryDirectory;
  late final JobCache _cache = JobCache(temporaryDirectory);
  CachedJob? _outputJob;
  final List<LibraryExportItem> _items = [];
  ExportFormat _format = ExportFormat.epub3;
  bool _running = false;
  bool _saving = false;
  bool _committing = false;
  bool _cancelRequested = false;
  bool _closing = false;
  Completer<void>? _idle;
  Future<void>? _shutdownFuture;
  SaveOutcome? _saveOutcome;

  List<LibraryExportItem> get items => List.unmodifiable(_items);
  ExportFormat get format => _format;
  bool get isRunning => _running || _saving;
  bool get isCommitting => _committing;
  SaveOutcome? get saveOutcome => _saveOutcome;
  bool get canSaveZip =>
      !_closing &&
      !isRunning &&
      _items.any((item) => item.status == LibraryExportStatus.success);

  Future<void> enqueue(
    List<String> bookIds, {
    ExportFormat format = ExportFormat.epub3,
  }) async {
    if (_closing || isRunning) {
      throw const ValidationFailure('书架导出仍在运行或正在关闭。');
    }
    final ids = bookIds.toSet().toList(growable: false);
    if (ids.isEmpty) throw const ValidationFailure('请先选择要导出的书籍。');
    if (ids.length > ImportLimits.maxBatchInputs) {
      throw const ValidationFailure('一次最多导出 40 本书，请分批选择。');
    }
    await _disposeOutput();
    _items
      ..clear()
      ..addAll([for (final id in ids) LibraryExportItem._(id)]);
    _format = format;
    _cancelRequested = false;
    _saveOutcome = null;
    notifyListeners();
  }

  Future<void> start() => _run(retryOnly: false);

  Future<void> retryFailed() => _run(retryOnly: true);

  Future<void> _run({required bool retryOnly}) async {
    if (_closing || isRunning) {
      throw const ValidationFailure('另一项书架导出正在运行或正在关闭。');
    }
    if (_items.isEmpty) throw const ValidationFailure('请先选择书籍。');
    final pending = retryOnly
        ? _items
              .where((item) => item.status == LibraryExportStatus.failed)
              .toList()
        : _items
              .where((item) => item.status == LibraryExportStatus.waiting)
              .toList();
    if (pending.isEmpty) return;
    if (jobs.isBusy) throw const ValidationFailure('另一项后台任务正在运行，请稍候。');
    _running = true;
    _idle = Completer<void>();
    _cancelRequested = false;
    _saveOutcome = null;
    notifyListeners();
    try {
      _outputJob ??= await _cache.create('export');
      for (final item in pending) {
        if (_cancelRequested) {
          _setStatus(item, LibraryExportStatus.cancelled);
          continue;
        }
        _setStatus(item, LibraryExportStatus.processing);
        try {
          final name = await exportService.withPreparedExport<String>(
            item.bookId,
            format: _format,
            onProgress: (progress) => _progress(item, progress),
            submit: (file, {required suggestedName, required mimeType}) async {
              item.title = p.basenameWithoutExtension(suggestedName);
              notifyListeners();
              return _copyPrepared(file, suggestedName);
            },
          );
          if (_cancelRequested) {
            final output = File(p.join(_outputJob!.directory.path, name));
            if (await output.exists()) await output.delete();
            throw const TaskCancelled();
          }
          item.outputName = name;
          _setStatus(item, LibraryExportStatus.success);
        } on TaskCancelled {
          _setStatus(item, LibraryExportStatus.cancelled);
        } on AppFailure catch (error) {
          item.error = error.message;
          _setStatus(item, LibraryExportStatus.failed);
        } on Object {
          item.error = '导出失败，请检查书籍与磁盘空间后重试。';
          _setStatus(item, LibraryExportStatus.failed);
        }
      }
    } finally {
      _running = false;
      notifyListeners();
      _idle?.complete();
      _idle = null;
    }
  }

  Future<String> _copyPrepared(File source, String suggestedName) async {
    if (_cancelRequested) throw const TaskCancelled();
    final used = _items.map((item) => item.outputName).whereType<String>();
    final name = FileNames.unique(suggestedName, used);
    final target = File(p.join(_outputJob!.directory.path, name));
    final staged = File('${target.path}.partial');
    if (await target.exists() || await staged.exists()) {
      throw const ExportFailure('私有导出文件名冲突，请重试。');
    }
    try {
      await staged.create(exclusive: true);
      final sink = staged.openWrite();
      try {
        await for (final chunk in source.openRead()) {
          // Let the stream and file sink close normally, then report the
          // cancellation. Throwing through IOSink can mask TaskCancelled.
          if (_cancelRequested) break;
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (_cancelRequested) throw const TaskCancelled();
      await staged.rename(target.path);
      return name;
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<SaveOutcome> saveZip() async {
    if (!canSaveZip) throw const ValidationFailure('当前没有可保存的导出结果。');
    if (jobs.isBusy) throw const ValidationFailure('另一项后台任务正在运行，请稍候。');
    _saving = true;
    _idle = Completer<void>();
    _cancelRequested = false;
    _saveOutcome = null;
    notifyListeners();
    final zip = File(p.join(_outputJob!.directory.path, 'library-exports.zip'));
    try {
      if (await zip.exists()) await zip.delete();
      await jobs.run(
        _LibraryZipInput(
          zip.path,
          _outputJob!.directory.path,
          [
            for (final item in _items)
              if (item.status == LibraryExportStatus.success) item.outputName!,
          ],
          jsonEncode({
            'version': 1,
            'kind': 'libraryExport',
            'format': _format.name,
            'results': [
              for (final item in _items)
                {
                  'bookId': item.bookId,
                  'title': item.title,
                  'status': item.status.name,
                  'output': item.outputName,
                  'error': item.error,
                },
            ],
          }),
        ),
        _writeLibraryZip,
        revision: 0,
        timeout: const Duration(minutes: 10),
      );
      if (_cancelRequested) throw const TaskCancelled();
      _committing = true;
      notifyListeners();
      final outcome = await files.savePreparedFile(
        zip,
        suggestedName: 'bookloom-library-export.zip',
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
    if (_running) exportService.cancel();
    if (_saving) jobs.cancelActive();
    notifyListeners();
  }

  void _progress(LibraryExportItem item, JobProgress progress) {
    if (item.status != LibraryExportStatus.processing) return;
    item.progress = progress.fraction;
    item.stage = progress.stage;
    notifyListeners();
  }

  void _setStatus(LibraryExportItem item, LibraryExportStatus status) {
    item.status = status;
    item.progress = null;
    item.stage = null;
    if (status == LibraryExportStatus.processing) item.error = null;
    notifyListeners();
  }

  Future<void> _disposeOutput() async {
    final job = _outputJob;
    _outputJob = null;
    if (job != null) await job.dispose();
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _closing = true;
    cancel();
    await _idle?.future;
    try {
      await _disposeOutput();
    } finally {
      dispose();
    }
  }
}

class _LibraryZipInput {
  const _LibraryZipInput(this.path, this.directory, this.names, this.manifest);
  final String path;
  final String directory;
  final List<String> names;
  final String manifest;
}

bool _writeLibraryZip(
  _LibraryZipInput input,
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
