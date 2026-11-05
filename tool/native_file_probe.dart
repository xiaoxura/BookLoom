import 'dart:convert';
import 'dart:io';

import 'package:bookloom/app/app.dart';
import 'package:bookloom/app/bootstrap.dart';
import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/router.dart';
import 'package:bookloom/app/window/window_controls.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/features/editor/presentation/editor_page.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// A real desktop Portal probe outside Flutter's integration-test binding.
/// Only use with a task-owned XDG root and its self-authored probe-input.txt.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final rawRoot = Platform.environment['BOOKLOOM_NATIVE_TEST_ROOT'];
  if (!Platform.isLinux || rawRoot == null) {
    throw StateError('An isolated Linux validation root is required.');
  }
  final root = Directory(rawRoot);
  if (!await File(p.join(root.path, '.bookloom-owned')).exists() ||
      Platform.environment['XDG_DATA_HOME'] != p.join(root.path, 'data') ||
      Platform.environment['XDG_CACHE_HOME'] != p.join(root.path, 'cache')) {
    throw StateError('Refusing to use non-test application data.');
  }
  WindowControls.configure();
  final boot = await bootstrap();
  if (!p.isWithin(root.path, boot.paths.support.path)) {
    throw StateError('Application support is outside the test root.');
  }
  final container = ProviderContainer(
    overrides: [
      appPathsProvider.overrideWithValue(boot.paths),
      databaseProvider.overrideWithValue(boot.database),
      initialAppearanceProvider.overrideWithValue(boot.appearance),
    ],
  );
  var firstShelfFrame = false;
  container.listen(libraryBooksProvider, (_, next) {
    if (!next.hasValue || firstShelfFrame) return;
    firstShelfFrame = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await File(p.join(root.path, 'native-shelf-frame.json')).writeAsString(
        jsonEncode({
          'firstShelfFrameUtc': DateTime.now().toUtc().toIso8601String(),
          'bookCount': next.value?.length,
          'peakRssBytes': ProcessInfo.maxRss,
          'devicePixelRatio': WidgetsBinding
              .instance
              .platformDispatcher
              .views
              .first
              .devicePixelRatio,
        }),
      );
    });
  });
  runApp(
    UncontrolledProviderScope(container: container, child: const BookloomApp()),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (Platform.environment['BOOKLOOM_NATIVE_PROBE_MODE'] == 'ime') {
      await _probeRealIme(container, root);
      return;
    }
    final result = <String, Object?>{'usesIntegrationTestBinding': false};
    final files = NativeFileService();
    final expected = File(p.join(root.path, 'probe-input.txt'));
    try {
      await File(p.join(root.path, 'probe-pick-ready'))
          .writeAsString(expected.path);
      final inputs = await files
          .pickImports(multiple: false)
          .timeout(const Duration(seconds: 45));
      result['pickedCount'] = inputs.length;
      for (final input in inputs) {
        try {
          if (input.name != p.basename(expected.path)) {
            throw StateError(
              'A file other than the owned fixture was selected.',
            );
          }
          final actualHash = (await sha256.bind(input.openRead()).first)
              .toString();
          final expectedHash = (await sha256.bind(expected.openRead()).first)
              .toString();
          if (actualHash != expectedHash) {
            throw StateError('Picker bytes differ.');
          }
          result['fixtureHashMatches'] = true;
        } finally {
          await input.release();
        }
      }
    } on Object catch (error) {
      result['error'] = '$error';
      if (error is AppFailure) result['cause'] = '${error.cause}';
    } finally {
      await File(p.join(root.path, 'native-picker-probe.json'))
          .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      container.dispose();
      await boot.database.close();
      WindowControls.close();
    }
  });
}

/// Observe the production editor's platform input connection. No test input
/// client is registered; edits must arrive through the operating system.
Future<void> _probeRealIme(ProviderContainer container, Directory root) async {
  final result = <String, Object?>{
    'usesIntegrationTestBinding': false,
    'usesTestTextInput': false,
    'events': <Map<String, Object?>>[],
  };
  final events = result['events']! as List<Map<String, Object?>>;
  EditableText? target;
  Element? targetElement;
  VoidCallback? listener;
  VoidCallback? focusListener;
  final keys = <Map<String, Object?>>[];
  final focusEvents = <bool>[];
  result['keys'] = keys;
  result['focusEvents'] = focusEvents;
  void persist() =>
      File(p.join(root.path, 'native-ime-events.json'))
          .writeAsStringSync(jsonEncode(result));
  KeyEventResult observeKey(KeyEvent event) {
    if (keys.length < 120) {
      keys.add({
        'event': event.runtimeType.toString(),
        'label': event.logicalKey.keyLabel,
      });
      persist();
    }
    return KeyEventResult.ignored;
  }

  FocusManager.instance.addEarlyKeyEventHandler(observeKey);
  try {
    final repository = container.read(bookRepositoryProvider);
    var summaries = await repository.listSummaries();
    if (summaries.isEmpty) {
      // A small self-authored fixture keeps the pointer target on screen. It
      // exercises the real importer/DB; it is unrelated to the large benchmark.
      final text = utf8.encode(
        '第一章 原生输入\n海风吹过窗边，灯光照着桌上的书页。这里是输入法验证使用的自编正文。\n第二章 后续\n这段文字只存在于隔离测试目录。',
      );
      final service = container.read(importServiceProvider);
      final prepared = await service.prepare(
        PickedInput(
          name: '原生输入法验证.txt',
          size: text.length,
          openRead: () => Stream<List<int>>.value(text),
        ),
      );
      await service.commit(prepared);
      summaries = await repository.listSummaries();
    }
    final summary = summaries.firstWhere((book) => book.chapterCount > 0);
    final book = (await repository.loadBook(summary.id))!;
    final chapter = book.chapters.firstWhere((chapter) => !chapter.isVolume);
    container.read(routerProvider).go('/books/${book.id}');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    for (var attempt = 0; attempt < 100 && target == null; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      void visit(Element element) {
        if (element.widget case final EditableText field
            when !field.readOnly &&
                field.maxLines == null &&
                field.controller.text.isNotEmpty &&
                element.findAncestorWidgetOfExactType<EditorPage>() != null) {
          target ??= field;
          targetElement ??= element;
        }
        element.visitChildElements(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    }
    final field = target ?? (throw StateError('No production paragraph field'));
    final before = field.controller.text;
    listener = () {
      final value = field.controller.value;
      if (events.length < 120) {
        events.add({
          'textSuffix': value.text.substring(
            value.text.length > 40 ? value.text.length - 40 : 0,
          ),
          'length': value.text.length,
          'composingStart': value.composing.start,
          'composingEnd': value.composing.end,
        });
      }
      // The controller writes only to the owned fixture, never an editor value.
      persist();
    };
    field.controller.addListener(listener);
    field.controller.selection = TextSelection.collapsed(offset: before.length);
    focusListener = () {
      focusEvents.add(field.focusNode.hasFocus);
      persist();
    };
    field.focusNode.addListener(focusListener);
    field.focusNode.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final box = targetElement!.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final dpr =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    await File(p.join(root.path, 'ime-input-ready')).writeAsString(
      jsonEncode({
        'bookId': book.id,
        'dpr': dpr,
        'pointerX': (origin.dx + box.size.width / 2) * dpr,
        'pointerY': (origin.dy + box.size.height / 2) * dpr,
        'hasFocus': field.focusNode.hasFocus,
      }),
    );
    await Future<void>.delayed(const Duration(seconds: 25));
    result['compositionObserved'] = events.any(
      (event) =>
          (event['composingStart']! as int) >= 0 &&
          (event['composingEnd']! as int) > (event['composingStart']! as int),
    );
    result['textChanged'] = field.controller.text != before;
    result['compositionCleared'] =
        field.controller.value.composing.isCollapsed ||
        !field.controller.value.composing.isValid;
    final after = field.controller.text;
    var commonPrefix = 0;
    while (commonPrefix < before.length &&
        commonPrefix < after.length &&
        before.codeUnitAt(commonPrefix) == after.codeUnitAt(commonPrefix)) {
      commonPrefix++;
    }
    var commonSuffix = 0;
    while (commonSuffix < before.length - commonPrefix &&
        commonSuffix < after.length - commonPrefix &&
        before.codeUnitAt(before.length - commonSuffix - 1) ==
            after.codeUnitAt(after.length - commonSuffix - 1)) {
      commonSuffix++;
    }
    final added = after.substring(commonPrefix, after.length - commonSuffix);
    result['insertedText'] = added;
    result['committedChineseChange'] = RegExp(r'[\u3400-\u9fff]')
        .hasMatch(added);
    field.focusNode.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    final saved = await repository.loadChapter(book.id, chapter.id);
    result['savedControllerText'] = saved?.blocks.whereType<TextBlock>().any(
      (block) => block.text == after,
    );
  } on Object catch (error, stack) {
    result['error'] = '$error';
    result['stack'] = '$stack';
  } finally {
    FocusManager.instance.removeEarlyKeyEventHandler(observeKey);
    if (target != null && listener != null) {
      target!.controller.removeListener(listener);
      if (focusListener != null) {
        target!.focusNode.removeListener(focusListener);
      }
    }
    await File(p.join(root.path, 'native-ime-result.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    WindowControls.close();
  }
}
