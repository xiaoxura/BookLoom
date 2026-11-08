import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/platform/file_names.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile(this.name, this.uri, this.content);

  @override
  final String name;
  @override
  final Uri uri;
  final Uint8List content;

  @override
  Never get xFile => throw StateError('No local file path exists');

  @override
  int? lengthSync() => content.length;

  @override
  Future<int?> length() async => content.length;

  @override
  Future<Uint8List> readAsBytes() => throw StateError('Must use stream');

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield Uint8List.sublistView(content, 0, 2);
    yield Uint8List.sublistView(content, 2);
  }
}

final class _TestPicker extends FilePickerPlatform {
  _TestPicker(this.files);
  final List<PlatformFile> files;
  bool? selectedMultiple;
  Completer<List<PlatformFile>>? pendingPick;
  Completer<void>? pendingClear;
  int pickCount = 0;
  int clearCount = 0;
  bool clearInProgress = false;
  bool pickOverlappedClear = false;

  @override
  Future<void> clearTemporaryFiles() async {
    clearCount++;
    clearInProgress = true;
    try {
      await pendingClear?.future;
    } finally {
      clearInProgress = false;
    }
  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    selectedMultiple = true;
    pickCount++;
    pickOverlappedClear |= clearInProgress;
    return pendingPick?.future ?? files;
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    selectedMultiple = false;
    pickCount++;
    pickOverlappedClear |= clearInProgress;
    return (await (pendingPick?.future ?? Future.value(files))).firstOrNull;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('file names drop paths and reserved Windows names', () {
    expect(FileNames.sanitize(r'C:\source\CON.txt'), 'CON_.txt');
    expect(FileNames.sanitize('../NUL.epub'), 'NUL_.epub');
    expect(FileNames.sanitize('CON .txt'), 'CON_.txt');
    expect(FileNames.sanitize('COM¹.txt'), 'COM¹_.txt');
    expect(FileNames.sanitize('  a:b?.txt.  '), 'a_b_.txt');
    expect(FileNames.sanitize('...'), 'bookloom');
    expect(FileNames.sanitize('${'书' * 100}.epub').endsWith('.epub'), isTrue);
    expect(FileNames.sanitize('${'书' * 100}.epub').length, lessThan(100));
  });

  test('case-insensitive collision gets a deterministic suffix', () {
    expect(FileNames.unique('Book.EPUB', ['book.epub']), 'Book (2).EPUB');
    expect(
      FileNames.unique('Book.EPUB', ['book.epub', 'BOOK (2).epub']),
      'Book (3).EPUB',
    );
  });

  test(
    'selection opens a byte stream without treating a URI as a path',
    () async {
      final FilePickerPlatform previous = FilePickerPlatform.instance;
      final _TestPicker picker = _TestPicker([
        _TestPlatformFile(
          '稿件.TXT',
          Uri.parse('content://provider/document/42'),
          Uint8List.fromList([1, 2, 3, 4]),
        ),
      ]);
      FilePickerPlatform.instance = picker;
      final List<PickedInput> leased = [];
      try {
        final List<PickedInput> inputs = await NativeFileService()
            .pickImports();
        leased.addAll(inputs);
        expect(picker.selectedMultiple, isTrue);
        expect(inputs.single.size, 4);
        expect(
          await inputs.single.openRead().expand((chunk) => chunk).toList(),
          [1, 2, 3, 4],
        );
        leased.addAll(await NativeFileService().pickImports(multiple: false));
        expect(picker.selectedMultiple, isFalse);
      } finally {
        for (final input in leased) {
          await input.release();
        }
        FilePickerPlatform.instance = previous;
      }
    },
  );

  test('unsupported provider result raises actionable failure', () async {
    final FilePickerPlatform previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _TestPicker([
      _TestPlatformFile(
        'wrong.zip',
        Uri.parse('content://provider/1'),
        Uint8List(0),
      ),
    ]);
    try {
      expect(NativeFileService().pickImports(), throwsA(isA<ImportFailure>()));
    } finally {
      FilePickerPlatform.instance = previous;
    }
  });

  test(
    'cache clear waits for the last lease across service instances',
    () async {
      final previous = FilePickerPlatform.instance;
      final picker = _TestPicker([
        _TestPlatformFile('a.txt', Uri.parse('content://a'), Uint8List(1)),
        _TestPlatformFile('b.txt', Uri.parse('content://b'), Uint8List(1)),
      ]);
      FilePickerPlatform.instance = picker;
      final service = NativeFileService();
      final leased = <PickedInput>[];
      try {
        leased.addAll(await service.pickImports());
        leased.addAll(await NativeFileService().pickImports(multiple: false));
        await service.clearTemporaryFiles();
        expect(picker.clearCount, 0);
        await leased[0].release();
        await leased[1].release();
        expect(picker.clearCount, 0);
        await leased[2].release();
        await Future<void>.delayed(Duration.zero);
        expect(picker.clearCount, 1);
        await leased[2].release();
        expect(picker.clearCount, 1);
      } finally {
        for (final input in leased) {
          await input.release();
        }
        await service.clearTemporaryFiles();
        FilePickerPlatform.instance = previous;
      }
    },
  );

  test('a picker waits for clear and cancellation creates no lease', () async {
    final previous = FilePickerPlatform.instance;
    final picker = _TestPicker([]);
    FilePickerPlatform.instance = picker;
    final service = NativeFileService();
    try {
      final clearGate = Completer<void>();
      picker.pendingClear = clearGate;
      final clearing = service.clearTemporaryFiles();
      final selecting = NativeFileService().pickImports();
      await Future<void>.delayed(Duration.zero);
      expect(picker.pickCount, 0);
      clearGate.complete();
      await clearing;
      expect(await selecting, isEmpty);
      expect(picker.pickOverlappedClear, isFalse);

      picker.pendingPick = Completer<List<PlatformFile>>();
      final cancelled = service.pickImports();
      await Future<void>.delayed(Duration.zero);
      await service.clearTemporaryFiles();
      expect(picker.clearCount, 1);
      picker.pendingPick!.complete([]);
      expect(await cancelled, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(picker.clearCount, 2);
    } finally {
      if (picker.pendingClear case final gate? when !gate.isCompleted) {
        gate.complete();
      }
      await service.clearTemporaryFiles();
      FilePickerPlatform.instance = previous;
    }
  });

  test(
    'deferred clear failure does not fail release and retries later',
    () async {
      final previous = FilePickerPlatform.instance;
      final picker = _TestPicker([
        _TestPlatformFile('a.txt', Uri.parse('content://a'), Uint8List(1)),
      ]);
      FilePickerPlatform.instance = picker;
      final service = NativeFileService();
      final leased = <PickedInput>[];
      try {
        leased.addAll(await service.pickImports());
        final clearGate = Completer<void>();
        picker.pendingClear = clearGate;
        await service.clearTemporaryFiles();
        await leased.single.release();
        expect(picker.clearCount, 1);
        clearGate.completeError(StateError('temporary cleanup failed'));
        await Future<void>.delayed(Duration.zero);

        picker.pendingClear = null;
        leased.addAll(await NativeFileService().pickImports());
        expect(picker.clearCount, 2);
        await leased.last.release();
      } finally {
        for (final input in leased) {
          await input.release();
        }
        await service.clearTemporaryFiles();
        FilePickerPlatform.instance = previous;
      }
    },
  );

  test('manual selection release callback is idempotent', () async {
    var releases = 0;
    final input = PickedInput(
      name: 'manual.txt',
      size: 0,
      openRead: () => const Stream<List<int>>.empty(),
      onRelease: () async {
        releases++;
      },
    );
    await Future.wait([input.release(), input.release()]);
    await input.release();
    expect(releases, 1);
  });

  test('save copies by stream and preserves prepared file', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'bookloom-file-service-',
    );
    const MethodChannel channel = MethodChannel('bookloom/file-service-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final File prepared = File(p.join(directory.path, 'prepared.epub'));
    final File target = File(p.join(directory.path, 'export.epub'));
    try {
      final Uint8List bytes = Uint8List.fromList(
        List<int>.generate(1024 * 1024, (i) => i % 251),
      );
      await prepared.writeAsBytes(bytes);
      await target.writeAsString('previous');
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        expect(call.method, 'chooseSavePath');
        expect(
          (call.arguments as Map<Object?, Object?>)['fileName'],
          'export.epub',
        );
        return target.path;
      });

      final SaveOutcome outcome = await NativeFileService(channel: channel)
          .savePreparedFile(prepared, suggestedName: 'export.epub');
      expect((outcome as SaveSaved).uri, Uri.file(target.path));
      expect(await target.readAsBytes(), bytes);
      expect(await prepared.readAsBytes(), bytes);
      expect(directory.listSync().length, 2);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);

  test('save cancellation leaves no destination', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'bookloom-file-cancel-',
    );
    const MethodChannel channel = MethodChannel('bookloom/file-cancel-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final File prepared = File(p.join(directory.path, 'prepared.txt'));
    try {
      await prepared.writeAsString('ready');
      messenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async => null,
      );
      final SaveOutcome outcome = await NativeFileService(channel: channel)
          .savePreparedFile(prepared, suggestedName: 'cancel.txt');
      expect(outcome, isA<SaveCancelled>());
      expect(directory.listSync().length, 1);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);

  test('missing prepared file has a useful error', () async {
    expect(
      NativeFileService().savePreparedFile(
        File('/nonexistent/bookloom-output.zip'),
        suggestedName: 'backup.bookloom',
      ),
      throwsA(isA<ExportFailure>()),
    );
  });
  test(
    'Linux runner dialog returns real paths with requested filters',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('bookloom-picker-');
      addTearDown(() => root.delete(recursive: true));
      final file = File(p.join(root.path, 'sample.txt'));
      await file.writeAsString('hello');
      const channel = MethodChannel('bookloom/file_service');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return <String>[file.path];
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final picked = await NativeFileService().pickImports(
        multiple: false,
        extensions: const <String>['.txt'],
      );
      expect(seen?.method, 'chooseOpenFiles');
      expect(seen?.arguments, {
        'extensions': <String>['txt'],
        'multiple': false,
      });
      expect(picked.single.name, 'sample.txt');
      expect(picked.single.size, 5);
      final bytes = await picked.single
          .openRead()
          .expand((chunk) => chunk)
          .toList();
      expect(bytes, utf8.encode('hello'));
    },
  );

  test(
    'Linux runner dialog handles cancel and unsupported extensions',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('bookloom/file_service');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      List<String>? response;
      messenger.setMockMethodCallHandler(channel, (call) async => response);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      expect(
        await NativeFileService().pickImports(
          extensions: const <String>['txt'],
        ),
        isEmpty,
      );

      final root = await Directory.systemTemp.createTemp('bookloom-picker-');
      addTearDown(() => root.delete(recursive: true));
      final pdf = File(p.join(root.path, 'sample.pdf'));
      await pdf.writeAsString('pdf');
      response = <String>[pdf.path];
      await expectLater(
        NativeFileService().pickImports(extensions: const <String>['txt']),
        throwsA(isA<ImportFailure>()),
      );
    },
  );
}
