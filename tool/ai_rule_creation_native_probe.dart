import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/app/ai_rule_providers.dart';
import 'package:bookloom/app/rule_providers.dart';
import 'package:bookloom/app/window/window_controls.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Book, Chapter, Block;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/application/ai_rule_creation_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/application/rule_workbench_task.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:bookloom/features/editor/presentation/ai_rule_creation_panel.dart';
import 'package:bookloom/features/editor/presentation/rule_workbench_panel.dart';
import 'package:bookloom/features/settings/data/ai_http_client.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

const _sample = '第二章 合成标题';
const _original = '😀前文。\n$_sample\r\n后续正文。';
final _viewports = <String, Map<String, num>>{};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = Platform.environment;
  final path = environment['BOOKLOOM_NATIVE_TEST_ROOT'];
  if (!Platform.isLinux ||
      path == null ||
      !await File('$path/.bookloom-owned').exists() ||
      environment['XDG_DATA_HOME'] != '$path/data' ||
      environment['XDG_CONFIG_HOME'] != '$path/config' ||
      environment['XDG_CACHE_HOME'] != '$path/cache' ||
      environment['XDG_RUNTIME_DIR'] != '$path/runtime' ||
      environment['BOOKLOOM_EXPECTED_TEST_BUS'] == null ||
      environment['DBUS_SESSION_BUS_ADDRESS'] !=
          environment['BOOKLOOM_EXPECTED_TEST_BUS']) {
    throw StateError('Owned root, private XDG and bus are required.');
  }
  final root = Directory(path);
  final errors = <String>[];
  FlutterError.onError = (details) =>
      errors.add('${details.exceptionAsString()}\n${details.stack}');
  WindowControls.configure();
  final database = AppDatabase.memory();
  final repository = BookRepository(database, Directory('$path/data'));
  final now = DateTime.utc(2026, 11, 7);
  await repository.createBook(
    Book(
      id: 'synthetic-book',
      meta: BookMeta(title: 'AI 规则隔离合成书'),
      createdAt: now,
      updatedAt: now,
      chapters: const [
        Chapter(
          id: 'chapter',
          bookId: 'synthetic-book',
          title: '第一章 合成原章',
          blocks: [
            TextBlock(id: 'text', text: '已保存原文。'),
            TextBlock(id: 'unsent', text: 'private-never-send-marker'),
          ],
        ),
      ],
    ),
  );
  final session = EditorSession(
    repository: repository,
    debounce: const Duration(hours: 1),
  );
  await session.open('synthetic-book');
  session.editBlockText('text', _original);
  final selection = AiRuleSelection(
    chapterId: 'chapter',
    blockId: 'text',
    startUtf16: _original.indexOf(_sample),
    endUtf16: _original.indexOf(_sample) + _sample.length,
    original: _sample,
  );
  final credentials = _Credentials();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  var boundedRequest = false;
  final subscription = server.listen((request) async {
    requests++;
    final payload = jsonDecode(
      await utf8.decoder.bind(request).join(),
    ) as Map<String, dynamic>;
    final messages = payload['messages'] as List;
    final sent = messages.last['content'] as String;
    boundedRequest =
        sent.contains(_sample) &&
        sent.contains('😀前文。') &&
        !sent.contains('已保存原文。') &&
        !sent.contains('private-never-send-marker');
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'object': 'chat.completion',
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'role': 'assistant',
              'content': jsonEncode({
                'schema_version': 1,
                'findings': <Object>[],
                'proposals': <Object>[],
                'rule_proposals': [
                  {
                    'schema_version': 1,
                    'name': '合成样例章节规则',
                    'kind': 'chapter',
                    'target': 'heading_line',
                    'match': {
                      'mode': 'safe_regex',
                      'pattern': '^$_sample\$',
                      'case_sensitive': true,
                    },
                    'action': 'chapter_candidate',
                    'positive_examples': [_sample],
                    'negative_examples': ['他提到第二章 合成标题'],
                    'reason': '仅对选中标题生成保守候选，保存前检查全书命中。',
                  },
                ],
              }),
            },
          },
        ],
      }),
    );
    await request.response.close();
  });
  final configuration = AiConfiguration(
    enabled: true,
    address: 'http://127.0.0.1:${server.port}/v1',
    model: 'synthetic-rule-model',
    credentialReference: 'synthetic-rule-reference',
  );
  final store = SettingsProofreadingRuleStore(database);
  final container = ProviderContainer(
    overrides: [
      aiRuleCreationTaskProvider.overrideWith(
        (ref, target) => AiRuleCreationTask(
          session: target,
          loadConfiguration: () async => configuration,
          credentials: credentials,
          createClient: AiHttpClient.new,
        ),
      ),
      ruleWorkbenchTaskProvider.overrideWith(
        (ref, target) => RuleWorkbenchTask(session: target, store: store),
      ),
    ],
  );
  final aiSubscription = container.listen(
    aiRuleCreationTaskProvider(session),
    (previous, next) {},
  );
  final ai = aiSubscription.read();
  final ruleSubscription = container.listen(
    ruleWorkbenchTaskProvider(session),
    (previous, next) {},
  );
  final rules = ruleSubscription.read();
  final appearance = ValueNotifier<(bool, double)>((false, 1));
  final candidate = ValueNotifier<ProofreadingRule?>(null);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<(bool, double)>(
        valueListenable: appearance,
        builder: (context, value, child) => MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: value.$1 ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(value.$2)),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: (value.$1 ? AppTheme.dark() : AppTheme.light())
                .colorScheme
                .surface,
            body: ValueListenableBuilder<ProofreadingRule?>(
              valueListenable: candidate,
              builder: (context, rule, child) => rule == null
                  ? AiRuleCreationPanel(
                      session: session,
                      selection: selection,
                      initialKind: ProofreadingRuleKind.chapter,
                      onUseRule: (rule) => candidate.value = rule,
                    )
                  : RuleWorkbenchPanel(
                      session: session,
                      initialRule: rule,
                      initialSessionId: session.sessionId,
                      initialSaveSeq: session.saveSeq,
                      onLocate: (chapterId, blockId) async {},
                    ),
            ),
          ),
        ),
      ),
    ),
  );
  final result = <String, Object?>{
    'usesDailyDatabase': false,
    'usesDailyKeyring': false,
    'usesDailyBrowser': false,
    'usesRealCloudService': false,
    'usesNativePointerClicks': false,
    'usesWidgetCallbackAutomation': true,
    'usesTaskControllerAutomation': true,
    'nativeInputUnverified': true,
  };
  try {
    await _settle();
    final window = WindowManager.instance.getCurrent();
    if (window == null) throw StateError('Owned GTK window missing.');
    window.title = 'Bookloom AI rules isolated probe';
    window.setSize(const Size(1280, 900).toNative(), false);
    window.show();
    _setText('ai-rule-intent', '只识别这个样式的章节标题，不修改正文。');
    _setText('ai-rule-negative', '他提到第二章 合成标题');
    await _activate('ai-rule-prepare');
    await _until(() => !ai.isBusy);
    _require(
      ai.phase == AiRuleCreationPhase.awaitingConsent,
      'Could not prepare rule consent.',
    );
    _require(
      requests == 0 && credentials.reads == 0,
      'Preparation accessed service or key.',
    );
    await _phase(root, 'ai-rules-consent-light-1280');
    await _activate('ai-rule-send');
    await _until(() => !ai.isBusy);
    _require(
      ai.canUseProposals && ai.proposals.length == 1,
      'Generated rule was not validated.',
    );
    _require(
      requests == 1 && credentials.reads == 1 && boundedRequest,
      'Unbounded or unexpected request.',
    );
    _require(
      (await store.loadForBook('synthetic-book')).isEmpty &&
          session.book!.chapters.length == 1,
      'Generation saved or applied a rule.',
    );
    final useKey = 'ai-rule-use-${ai.proposals.single.proposalId}';
    await _expand('ai-rule-proposal-${ai.proposals.single.proposalId}');
    await Scrollable.ensureVisible(await _findControl(useKey), alignment: 1);
    await _phase(root, 'ai-rules-candidate-light-1280');
    appearance.value = (true, 1.6);
    window.setSize(const Size(820, 900).toNative(), false);
    await _settle();
    await Scrollable.ensureVisible(await _findControl(useKey), alignment: 1);
    await _phase(root, 'ai-rules-candidate-dark-820-scaled');
    await _activate(useKey);
    await _until(() => rules.isLoaded && rules.rules.length == 1);
    _require(
      !rules.hasCurrentTrial &&
          (await store.loadForBook('synthetic-book')).isEmpty,
      'Handoff persisted or scanned automatically.',
    );
    await _activate('rule-scan');
    await _until(() => !rules.isBusy);
    _require(
      rules.hasCurrentTrial &&
          rules.matches.length == 1 &&
          rules.trial!.coverage.textBlocks == 2,
      'Handoff rule full-book trial failed.',
    );
    appearance.value = (false, 1);
    window.setSize(const Size(1280, 900).toNative(), false);
    await _phase(root, 'ai-rules-workbench-trial-light-1280');
    final revision = session.saveSeq;
    await rules.saveRule(candidate.value!.id);
    _require(
      session.saveSeq == revision &&
          (await store.loadForBook('synthetic-book')).length == 1,
      'Independent rule save changed manuscript.',
    );
    await _activate('rule-check-${rules.matches.single.id}');
    await _activate('rule-apply-selected');
    await _until(() => !rules.isBusy);
    _require(
      rules.phase == RuleWorkbenchPhase.applied &&
          session.book!.chapters.length == 2 &&
          session.book!.chapters[1].title == _sample &&
          session.book!.chapters[1].blocks.last.plainText ==
              'private-never-send-marker',
      'Explicit application failed.',
    );
    await session.undo();
    _require(
      session.book!.chapters.length == 1 &&
          session.book!.chapters.single.blocks.first.plainText == _original &&
          session.book!.chapters.single.blocks.last.plainText ==
              'private-never-send-marker',
      'Single undo did not restore exact source.',
    );
    _require(!ai.canUseProposals, 'Old candidate survived editing.');
    _require(errors.isEmpty, 'Framework errors occurred.');
    result.addAll({
      'passed': true,
      'requests': requests,
      'credentialReads': credentials.reads,
      'boundedRequest': boundedRequest,
      'frameworkErrors': errors,
      'renderedViewports': _viewports,
      'verified': [
        'prepare-without-network-or-key',
        'explicit-confirmed-loopback-http',
        'validated-book-scoped-rule',
        'generation-and-handoff-do-not-save-or-apply',
        'full-book-trial',
        'independent-rule-save',
        'explicit-split-and-single-undo',
        'stale-generation-refused',
      ],
    });
  } catch (error, stack) {
    result.addAll({
      'passed': false,
      'error': error.toString(),
      'stack': stack.toString(),
      'frameworkErrors': errors,
      'aiPhase': ai.phase.name,
      'aiFailure': ai.failure?.message,
      'rulePhase': rules.phase.name,
    });
  } finally {
    runApp(const SizedBox.shrink());
    await _settle();
    aiSubscription.close();
    ruleSubscription.close();
    container.dispose();
    await subscription.cancel();
    await server.close(force: true);
    await session.close();
    await database.close();
    if (errors.isNotEmpty) {
      result['passed'] = false;
      result['frameworkErrors'] = errors;
    }
    await File('$path/native-ai-rule-result.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    exit(result['passed'] == true ? 0 : 1);
  }
}

class _Credentials implements AiCredentialStore {
  int reads = 0;

  @override
  Future<String?> read(String reference) async {
    reads++;
    return 'synthetic-key-only';
  }

  @override
  Future<void> write(String reference, String value) async =>
      throw StateError('Probe does not write credentials.');

  @override
  Future<void> delete(String reference) async =>
      throw StateError('Probe does not delete credentials.');
}

void _setText(String key, String text) {
  final widget = _element(key)?.widget;
  if (widget is! TextField || widget.controller == null) {
    throw StateError('Text control unavailable: $key.');
  }
  widget.controller!.text = text;
  widget.onChanged?.call(text);
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await WidgetsBinding.instance.endOfFrame;
}

Element? _element(String key) {
  Element? found;
  void visit(Element element) {
    if (element.widget.key == ValueKey(key)) found = element;
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<Element> _findControl(String key) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    final element = _element(key);
    if (element != null) return element;
    ScrollableState? scroll;
    void findScroll(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        scroll ??= element.state as ScrollableState;
      }
      element.visitChildren(findScroll);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(findScroll);
    if (scroll == null) break;
    final position = scroll!.position;
    final offset = attempt == 0
        ? 0.0
        : (position.pixels + 400).clamp(0.0, position.maxScrollExtent);
    position.jumpTo(offset);
    await _settle();
  }
  throw StateError('Control missing: $key.');
}

Future<void> _activate(String key) async {
  await _settle();
  final element = await _findControl(key);
  await Scrollable.ensureVisible(element, alignment: .5);
  await _settle();
  final widget = element.widget;
  if (widget is Checkbox && widget.onChanged != null) {
    widget.onChanged!(!(widget.value ?? false));
  } else if (widget is ButtonStyleButton && widget.onPressed != null) {
    widget.onPressed!();
  } else {
    throw StateError('Control unavailable: $key.');
  }
  await _settle();
}

Future<void> _expand(String key) async {
  final tile = await _findControl(key);
  ExpansibleController? controller;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Expansible) controller = widget.controller;
    element.visitChildren(visit);
  }

  tile.visitChildren(visit);
  _require(controller != null, 'Expansion control missing: $key.');
  controller!.expand();
  await _settle();
}

Future<void> _until(bool Function() predicate) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Owned rule probe did not reach expected state.');
}

Future<void> _phase(Directory root, String phase) async {
  var themeFrames = 0;
  if (phase.contains('dark') || phase.contains('light')) {
    final expectedTheme = phase.contains('dark')
        ? AppTheme.dark()
        : AppTheme.light();
    final expected = expectedTheme.textTheme.bodyMedium!.color;
    var settled = false;
    for (; themeFrames < 150; themeFrames++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      Element? panel;
      void findPanel(Element element) {
        if (element.widget is AiRuleCreationPanel ||
            element.widget is RuleWorkbenchPanel) {
          panel = element;
        }
        element.visitChildren(findPanel);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(findPanel);
      if (panel != null &&
          Theme.of(panel!).textTheme.bodyMedium?.color == expected &&
          Theme.of(panel!).colorScheme.surface ==
              expectedTheme.colorScheme.surface) {
        settled = true;
        break;
      }
    }
    _require(settled, 'Native theme did not reach its target text colors.');
    for (var frame = 0; frame < 4; frame++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  await _settle();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  _viewports[phase] = {
    'physicalWidth': view.physicalSize.width,
    'physicalHeight': view.physicalSize.height,
    'devicePixelRatio': view.devicePixelRatio,
    'themeSettleFrames': themeFrames,
  };
  final styles = <Map<String, Object?>>[];
  void inspect(Element element) {
    final widget = element.widget;
    if (widget is RichText && styles.length < 40) {
      styles.add({
        'text': widget.text.toPlainText(),
        'renderedColor': widget.text.style?.color?.toARGB32(),
        'themeBodyColor': Theme.of(element).textTheme.bodyMedium?.color
            ?.toARGB32(),
        'surfaceColor': Theme.of(element).colorScheme.surface.toARGB32(),
      });
    }
    element.visitChildren(inspect);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(inspect);
  await File('${root.path}/styles-$phase.json')
      .writeAsString(jsonEncode(styles));
  await File('${root.path}/phase-$phase.ready').writeAsString('ready');
  await _until(() => File('${root.path}/phase-$phase.ack').existsSync());
}
