import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../errors/app_failure.dart';
import 'file_names.dart';

/// A selected source. Its provider may be a content URI, not a local path.
final class PickedInput {
  PickedInput({
    required this.name,
    required this.size,
    required this.openRead,
    this.onRelease,
  });

  final String name;
  final int? size;
  final Stream<List<int>> Function() openRead;
  final Future<void> Function()? onRelease;
  Future<void>? _releaseFuture;

  /// Once the caller no longer needs to retry or read this selection, release
  /// its picker-owned temporary copy. Manual inputs without a callback are a
  /// no-op; concurrent and repeated calls invoke the callback only once.
  Future<void> release() => _releaseFuture ??= Future<void>.sync(() async {
    await onRelease?.call();
  });
}

sealed class SaveOutcome {
  const SaveOutcome();
}

final class SaveCancelled extends SaveOutcome {
  const SaveCancelled();
}

final class SaveSaved extends SaveOutcome {
  const SaveSaved(this.uri);

  final Uri uri;
}

/// Native input and output boundary. Exporters prepare an app-owned file first.
abstract interface class FileService {
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const ['txt', 'epub', 'docx'],
  });

  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  });

  /// Request global picker-cache cleanup. It runs once every selected input
  /// has been released and no picker is active; a deferred request returns
  /// immediately and the final release starts cleanup.
  Future<void> clearTemporaryFiles();
}

final class NativeFileService implements FileService {
  NativeFileService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('bookloom/file_service');

  final MethodChannel _channel;

  // FilePicker clears a global plugin cache, not one selection. Keep these
  // counts shared by all NativeFileService instances in this isolate.
  static int _activeLeases = 0;
  static int _activePicks = 0;
  static bool _clearRequested = false;
  static Future<void>? _clearInFlight;

  static void _startClearIfReady() {
    if (!_clearRequested ||
        _activeLeases != 0 ||
        _activePicks != 0 ||
        _clearInFlight != null) {
      return;
    }
    _clearRequested = false;
    late final Future<void> clearing;
    clearing = () async {
      var failed = false;
      try {
        await FilePicker.clearTemporaryFiles();
      } on Object catch (error, stack) {
        failed = true;
        _clearRequested = true;
        developer.log(
          'Picker cache cleanup failed; will retry after a later request.',
          name: 'bookloom.file_picker',
          error: error,
          stackTrace: stack,
        );
        rethrow;
      } finally {
        if (identical(_clearInFlight, clearing)) {
          _clearInFlight = null;
        }
        if (!failed) _startClearIfReady();
      }
    }();
    _clearInFlight = clearing;
    // A deferred request has no waiter; still consume any plugin error. An
    // immediate caller may separately await and handle this same future.
    unawaited(clearing.catchError((Object _, StackTrace _) {}));
  }

  static Future<void> _releaseLease() {
    assert(_activeLeases > 0);
    _activeLeases--;
    _startClearIfReady();
    return Future<void>.value();
  }

  @override
  Future<void> clearTemporaryFiles() {
    final clearing = _clearInFlight;
    if (clearing != null) return clearing;
    _clearRequested = true;
    _startClearIfReady();
    // If another queue still owns a selection this is only a request. The
    // final release starts the clear without making this caller wait on it.
    return _clearInFlight ?? Future<void>.value();
  }

  /// The extension filter is also used by rules, fonts, covers and backups.
  @override
  Future<List<PickedInput>> pickImports({
    bool multiple = true,
    List<String> extensions = const ['txt', 'epub', 'docx'],
  }) async {
    final List<String> allowed = extensions
        .map(
          (String extension) =>
              extension.replaceFirst(RegExp(r'^\.'), '').toLowerCase(),
        )
        .toList(growable: false);
    if (allowed.isEmpty ||
        allowed.any((String extension) => extension.isEmpty)) {
      throw const ValidationFailure('请选择至少一种文件格式。');
    }

    // Complete an in-flight clear before reserving the next picker. After the
    // await, reservation is synchronous and happens before opening the picker.
    _startClearIfReady();
    final clearing = _clearInFlight;
    if (clearing != null) {
      try {
        await clearing;
      } on Object {
        // A failed cleanup does not prevent the user from selecting again.
      }
    }
    _activePicks++;
    try {
      final List<PlatformFile> files;
      if (multiple) {
        files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: allowed,
        );
      } else {
        final PlatformFile? file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: allowed,
        );
        files = file == null ? const [] : [file];
      }

      final List<(PlatformFile, int?)> selected = [];
      for (final PlatformFile file in files) {
        final String extension = p
            .extension(file.name)
            .replaceFirst('.', '')
            .toLowerCase();
        if (!allowed.contains(extension)) {
          throw ImportFailure(
            '“${file.name}”的格式不受支持。',
            hint:
                '请选择 ${allowed.map((String value) => value.toUpperCase()).join('、')} 文件。',
          );
        }
        final int? size = file.lengthSync() ?? await file.length();
        selected.add((file, size));
      }
      _activeLeases += selected.length;
      return [
        for (final (file, size) in selected)
          PickedInput(
            name: file.name,
            size: size,
            onRelease: _releaseLease,
            openRead: () async* {
              try {
                yield* file.readAsByteStream();
              } on Object catch (error, stack) {
                throw ImportFailure(
                  '无法读取“${file.name}”。',
                  cause: error,
                  stackTrace: stack,
                  hint: '检查文件是否仍可访问，然后重新选择。',
                );
              }
            },
          ),
      ];
    } on AppFailure {
      rethrow;
    } on Object catch (error, stack) {
      throw ImportFailure(
        '无法选择文件。',
        cause: error,
        stackTrace: stack,
        hint: '检查文件权限，然后重试。',
      );
    } finally {
      _activePicks--;
      _startClearIfReady();
    }
  }

  /// Streams [prepared] to the native destination; cancellation is quiet.
  @override
  Future<SaveOutcome> savePreparedFile(
    File prepared, {
    required String suggestedName,
    String mimeType = 'application/octet-stream',
  }) async {
    final String safeName = FileNames.sanitize(suggestedName);
    try {
      if (!await prepared.exists()) {
        throw const ExportFailure('待导出的文件已不存在。', hint: '重新生成文件后再试。');
      }

      if (Platform.isAndroid) {
        final String? rawUri = await _channel.invokeMethod<String>(
          'savePreparedFile',
          <String, String>{
            'path': prepared.absolute.path,
            'fileName': safeName,
            'mimeType': mimeType,
          },
        );
        return rawUri == null
            ? const SaveCancelled()
            : SaveSaved(Uri.parse(rawUri));
      }
      if (!Platform.isLinux && !Platform.isWindows) {
        throw const ExportFailure('当前平台尚不支持原生文件导出。');
      }

      final String? targetPath = await _channel.invokeMethod<String>(
        'chooseSavePath',
        <String, String>{'fileName': safeName},
      );
      if (targetPath == null) return const SaveCancelled();
      if (targetPath.isEmpty || !p.isAbsolute(targetPath)) {
        throw const ExportFailure('系统未返回有效的保存位置。');
      }

      final File destination = File(targetPath);
      if (p.normalize(destination.absolute.path) ==
          p.normalize(prepared.absolute.path)) {
        throw const ExportFailure('保存位置与待导出文件相同，请选择其他位置。');
      }

      // A same-directory staging file keeps a previous export intact if copying
      // fails. Commit happens only after the full stream has been written.
      final File staged = File(
        p.join(destination.parent.path, '.bookloom-${const Uuid().v4()}.tmp'),
      );
      try {
        await staged.create(exclusive: true);
        final IOSink sink = staged.openWrite();
        try {
          await sink.addStream(prepared.openRead());
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (Platform.isWindows) {
          // MoveFileExW reports a locked target without deleting the old file.
          await _channel.invokeMethod<void>(
            'commitStagedFile',
            <String, String>{
              'stagedPath': staged.path,
              'targetPath': destination.path,
            },
          );
        } else {
          await staged.rename(destination.path);
        }
      } finally {
        if (await staged.exists()) await staged.delete();
      }
      return SaveSaved(Uri.file(destination.path, windows: Platform.isWindows));
    } on AppFailure {
      rethrow;
    } on PlatformException catch (error, stack) {
      throw ExportFailure(
        '无法保存文件。',
        cause: error,
        stackTrace: stack,
        hint: '检查保存位置的权限和剩余空间，然后重试。',
      );
    } on Object catch (error, stack) {
      throw ExportFailure(
        '无法保存文件。',
        cause: error,
        stackTrace: stack,
        hint: '检查保存位置的权限和剩余空间，然后重试。',
      );
    }
  }
}
