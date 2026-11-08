import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/app/rule_providers.dart';
import 'package:bookloom/app/window/window_controls.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Book, Chapter, Block;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/application/rule_workbench_task.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:bookloom/features/editor/presentation/rule_workbench_panel.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

const _original = '😀正文。\n第二章 合成标题\r\n本站推广后文。';
const _mappedHeading = '【第二章 😀映射标题】';
const _mappedOriginal = '😀前文。\r\n$_mappedHeading\r\n映射后文。';
const _volumeHeading = '【第二卷 😀新卷】';
const _volumeOriginal = '😀卷前的原章。\r\n$_volumeHeading\r\n新卷的卷前内容。';
const _numberHeading = '【卷貳·归来😀】';
bool get _numberMapping =>
    Platform.environment['BOOKLOOM_NATIVE_NUMBER_MAPPING'] == '1';
bool get _volumeMapping =>
    _numberMapping ||
    Platform.environment['BOOKLOOM_NATIVE_VOLUME_MAPPING'] == '1';
bool get _titleMapping =>
    Platform.environment['BOOKLOOM_NATIVE_TITLE_MAPPING'] == '1';
bool get _mapping => _titleMapping || _volumeMapping;
String get _mappingTitle => _numberMapping
    ? '第2卷 归来😀'
    : _volumeMapping
    ? '第二卷 😀新卷'
    : '第二章 😀映射标题';
String get _mappingBaseTitle => _numberMapping ? '归来😀' : _mappingTitle;
String get _mappingOriginal => _numberMapping
    ? '😀卷前的原章。\r\n$_numberHeading\r\n新卷的卷前内容。'
    : _volumeMapping
    ? _volumeOriginal
    : _mappedOriginal;
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
    throw StateError(
      'Owned root, private XDG and private session bus required.',
    );
  }
  final root = Directory(path);
  final errors = <String>[];
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  WindowControls.configure();
  final database = AppDatabase.memory();
  final repository = BookRepository(database, Directory('$path/data'));
  final now = DateTime.utc(2026, 11, 7);
  await repository.createBook(
    Book(
      id: 'synthetic-book',
      meta: BookMeta(title: '隔离合成书稿'),
      createdAt: now,
      updatedAt: now,
      parseOptions: const ParseOptions(rulePreset: 'numbered'),
      chapters: [
        const Chapter(
          id: 'synthetic-first',
          bookId: 'synthetic-book',
          title: '第一章 合成原章',
          blocks: [TextBlock(id: 'synthetic-text', text: '已保存的旧正文。')],
        ),
        const Chapter(
          id: 'synthetic-last',
          bookId: 'synthetic-book',
          title: '第三章 后续章',
          order: 1,
          blocks: [TextBlock(id: 'synthetic-last-text', text: '未参与变更的后续章节。')],
        ),
        if (_volumeMapping) ...const [
          Chapter(
            id: 'synthetic-existing-volume',
            bookId: 'synthetic-book',
            title: '已有下一卷',
            level: 1,
            order: 2,
          ),
          Chapter(
            id: 'synthetic-existing-child',
            bookId: 'synthetic-book',
            title: '下一卷原章节',
            parentId: 'synthetic-existing-volume',
            order: 3,
            blocks: [
              TextBlock(id: 'synthetic-existing-text', text: '下一卷正文不变。'),
            ],
          ),
        ],
      ],
    ),
  );
  final session = EditorSession(
    repository: repository,
    debounce: const Duration(hours: 1),
  );
  await session.open('synthetic-book');
  session.editBlockText(
    'synthetic-text',
    _mapping ? _mappingOriginal : _original,
  );
  final store = SettingsProofreadingRuleStore(database);
  for (final rule in [
    if (_mapping)
      _rule(
        'chapter',
        ProofreadingRuleKind.chapter,
        _numberMapping
            ? r'【卷(貳)·(归来😀)】'
            : _volumeMapping
            ? r'【(第二卷 😀新卷)】'
            : r'【(第二章 😀映射标题)】',
        titleCaptureGroup: _numberMapping ? 2 : 1,
        numberCaptureGroup: _numberMapping ? 1 : null,
        headingLevel: _volumeMapping ? 1 : 2,
        positiveExamples: [
          _numberMapping
              ? _numberHeading
              : _volumeMapping
              ? _volumeHeading
              : _mappedHeading,
        ],
      )
    else ...[
      _rule('ad', ProofreadingRuleKind.advertisement, '推广'),
      _rule('chapter', ProofreadingRuleKind.chapter, '第二章'),
      _rule('global', ProofreadingRuleKind.advertisement, '本站', global: true),
      _rule(
        'exclude',
        ProofreadingRuleKind.advertisement,
        '推广',
        excludePattern: '后文',
        wholeLineOnly: true,
      ),
    ],
  ]) {
    await store.save(rule);
  }
  late RuleWorkbenchTask task;
  final container = ProviderContainer(
    overrides: [
      ruleWorkbenchTaskProvider.overrideWith((ref, target) {
        task = RuleWorkbenchTask(session: target, store: store);
        return task;
      }),
    ],
  );
  final appearance = ValueNotifier<(bool, double)>((false, 1));
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<(bool, double)>(
        valueListenable: appearance,
        builder: (context, value, child) => MaterialApp(
          title: 'Bookloom rules isolated probe',
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
            body: SafeArea(
              child: RuleWorkbenchPanel(
                session: session,
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
    if (window == null) throw StateError('Owned native window missing.');
    window.title = 'Bookloom rules isolated probe';
    window.setSize(const Size(1280, 900).toNative(), false);
    window.show();
    await _until(() => task.rules.length == (_mapping ? 1 : 4) && !task.isBusy);
    _require(
      task.selectedRuleIds.isEmpty,
      'Rules were selected automatically.',
    );
    if (_mapping) {
      await _activate('rule-select-chapter');
      await _activate('rule-scan');
      await _until(() => !task.isBusy);
      _require(
        task.hasCurrentTrial &&
            task.matches.length == 1 &&
            task.matches.single.match.mappedTitle == _mappingBaseTitle &&
            task.matches.single.match.mappedNumber ==
                (_numberMapping ? 2 : null) &&
            task.matches.single.match.numberText ==
                (_numberMapping ? '貳' : null) &&
            task.matches.single.match.headingLevel ==
                (_volumeMapping ? 1 : 2) &&
            task.matches.single.splitTitle == _mappingTitle,
        'Mapped trial lost the selected capture.',
      );
      final split = task.matches.single;
      final phase = _numberMapping
          ? 'rules-number'
          : _volumeMapping
          ? 'rules-volume'
          : 'rules-mapping';
      await _expand('rule-hit-${split.id}');
      await _activate('rule-check-${split.id}');
      if (_volumeMapping) {
        await Scrollable.ensureVisible(
          await _findControl('rule-hit-${split.id}'),
          alignment: 0,
        );
        await _phase(root, '$phase-origin-light-1280');
        await _expand('rule-following-chapters-${split.id}');
      }
      await Scrollable.ensureVisible(
        await _findControl('rule-locate-${split.id}'),
        alignment: 1,
      );
      await _phase(root, '$phase-impact-light-1280');
      appearance.value = (true, 1.6);
      window.setSize(const Size(820, 900).toNative(), false);
      await _settle();
      await Scrollable.ensureVisible(
        await _findControl('rule-locate-${split.id}'),
        alignment: 1,
      );
      await _phase(root, '$phase-impact-dark-scaled-820');
      final revision = session.saveSeq;
      await task.saveRule('chapter');
      _require(
        (await store.loadForBook('synthetic-book')).single.titleCaptureGroup ==
                (_numberMapping ? 2 : 1) &&
            (await store.loadForBook('synthetic-book'))
                    .single
                    .numberCaptureGroup ==
                (_numberMapping ? 1 : null) &&
            (await store.loadForBook('synthetic-book')).single.headingLevel ==
                (_volumeMapping ? 1 : 2) &&
            session.saveSeq == revision &&
            _body(session) == _mappingOriginal,
        'Saving a mapped rule lost its field or modified the book.',
      );
      await _activate('rule-apply-selected');
      await _until(() => !task.isBusy);
      _require(
        task.phase == RuleWorkbenchPhase.applied &&
            session.book!.chapters.length == (_volumeMapping ? 6 : 3) &&
            session.book!.chapters[1].title == _mappingTitle &&
            (session.book!.chapters[_volumeMapping ? 2 : 1].blocks.single
                        as TextBlock)
                    .text ==
                (_volumeMapping ? '新卷的卷前内容。' : '映射后文。') &&
            _body(session) == (_volumeMapping ? '😀卷前的原章。\r\n' : '😀前文。\r\n'),
        'Mapped title or full heading removal was not applied exactly.',
      );
      if (_volumeMapping) {
        final chapters = session.book!.chapters;
        _require(
          chapters[1].isVolume &&
              chapters[1].blocks.isEmpty &&
              chapters[2].frontMatter &&
              chapters[2].title.isEmpty &&
              chapters[2].parentId == chapters[1].id &&
              chapters[3].id == 'synthetic-last' &&
              chapters[3].parentId == chapters[1].id &&
              chapters[4].id == 'synthetic-existing-volume' &&
              chapters[5].parentId == 'synthetic-existing-volume',
          'Volume intro or contiguous following chapter ownership was lost.',
        );
      }
      await session.undo();
      _require(
        session.book!.chapters.length == (_volumeMapping ? 4 : 2) &&
            session.book!.chapters[1].parentId == null &&
            _body(session) == _mappingOriginal,
        'Mapped split undo lost the original heading.',
      );
      await session.redo();
      await session.flush();
      final reloaded = (await repository.loadBook('synthetic-book'))!;
      _require(
        reloaded.chapters.length == (_volumeMapping ? 6 : 3) &&
            reloaded.chapters[1].title == _mappingTitle &&
            (!_volumeMapping ||
                reloaded.chapters[3].parentId == reloaded.chapters[1].id),
        'Mapped catalog title did not survive persistence.',
      );
      _require(errors.isEmpty, 'Flutter framework errors.');
      result.addAll({
        'passed': true,
        'frameworkErrors': errors,
        'renderedViewports': _viewports,
        'verified': [
          'offline-capture-title-mapping',
          if (_numberMapping)
            'exact-source-number-and-title-mapping-without-renumbering',
          if (_volumeMapping) 'volume-intro-and-contiguous-chapter-ownership',
          'mapped-title-and-complete-heading-impact-preview',
          'save-preserves-mapping-without-editing-manuscript',
          'explicit-apply-removes-complete-source-heading',
          'single-undo-redo-and-persistence',
          'light-dark-scaled-rendering',
        ],
      });
      return;
    }
    _require(
      task.importRules?.presetId == 'numbered' &&
          task.importRules!.presetName == '数字标题' &&
          task.importRules!.entries.length == 1 &&
          task.importRules!.entries.single.pattern.contains(r'\d{1,4}'),
      'Read-only import rules were not loaded from the book options.',
    );
    _require(
      task.rules.length == 4 && task.selectedRuleIds.isEmpty,
      'Read-only import rules joined the workbench rule set.',
    );
    await _expand('rule-import-rules');
    await Scrollable.ensureVisible(
      await _findControl('rule-import-entry-0'),
      alignment: .2,
    );
    await _phase(root, 'rules-import-light-1280');
    appearance.value = (true, 1.6);
    window.setSize(const Size(820, 900).toNative(), false);
    await _settle();
    await Scrollable.ensureVisible(
      await _findControl('rule-import-entry-0'),
      alignment: .2,
    );
    await _phase(root, 'rules-import-dark-scaled-820');
    appearance.value = (false, 1);
    window.setSize(const Size(1280, 900).toNative(), false);
    await _settle();
    await _collapse('rule-import-rules');
    await _phase(root, 'rules-initial-light-1280');
    await _activate('rule-select-exclude');
    await _expand('rule-definition');
    await _findControl('rule-definition-exclude');
    await _findControl('rule-definition-whole-line');
    final example = _exactTextElement('推广');
    _require(example != null, 'Definition example text is missing.');
    final exampleBox = example!.renderObject;
    final exampleLeft = exampleBox is RenderBox
        ? exampleBox.localToGlobal(Offset.zero).dx
        : null;
    _require(
      exampleLeft != null && exampleLeft >= 0 && exampleLeft < 120,
      'Definition examples are not left-aligned.',
    );
    await Scrollable.ensureVisible(
      await _findControl('rule-definition-whole-line'),
      alignment: .4,
    );
    await _phase(root, 'rules-exclude-light-1280');
    appearance.value = (true, 1.6);
    window.setSize(const Size(820, 900).toNative(), false);
    await _settle();
    await Scrollable.ensureVisible(
      await _findControl('rule-definition-whole-line'),
      alignment: .4,
    );
    await _phase(root, 'rules-exclude-dark-scaled-820');
    appearance.value = (false, 1);
    window.setSize(const Size(1280, 900).toNative(), false);
    await _settle();
    await _activate('rule-select-ad');
    await _activate('rule-select-chapter');
    await _activate('rule-scan');
    await _until(() => !task.isBusy);
    _require(
      task.hasCurrentTrial && task.trial!.distinctMatches == 2,
      'Full unsaved scan failed.',
    );
    _require(
      task.trial!.coverage.chapters == 2 &&
          task.trial!.coverage.textBlocks == 2,
      'Incomplete coverage.',
    );
    await _phase(root, 'rules-trial-light-1280');
    final split = task.matches.firstWhere(
      (item) => item.match.action == ProofreadingRuleAction.chapterCandidate,
    );
    await _expand('rule-hit-${split.id}');
    await _activate('rule-check-${split.id}');
    await _settle();
    await Scrollable.ensureVisible(
      await _findControl('rule-locate-${split.id}'),
      alignment: 1,
    );
    await _phase(root, 'rules-split-preview-light-1280');
    final deletion = task.matches.firstWhere(
      (item) => item.match.action == ProofreadingRuleAction.exactDeletion,
    );
    await _activate('rule-check-${deletion.id}');
    final beforeSave = session.saveSeq;
    await task.saveRule('ad');
    _require(
      task.hasCurrentTrial &&
          session.saveSeq == beforeSave &&
          _body(session) == _original,
      'Save modified manuscript.',
    );
    final selectedIds = task.matches.map((item) => item.id).toSet();
    await _activate('rule-apply-selected');
    await _until(() => !task.isBusy);
    _require(
      task.phase == RuleWorkbenchPhase.applied &&
          session.saveSeq == beforeSave + 1,
      'Mixed application failed.',
    );
    _require(
      session.book!.chapters.length == 3 &&
          session.book!.chapters[1].title == '第二章 合成标题',
      'Split structure failed.',
    );
    _require(
      (session.book!.chapters[1].blocks.single as TextBlock).text == '本站后文。',
      'Exact deletion failed.',
    );
    await session.undo();
    _require(
      session.book!.chapters.length == 2 && _body(session) == _original,
      'One undo failed.',
    );
    await session.redo();
    _require(session.book!.chapters.length == 3, 'Redo failed.');
    await session.undo();
    await task.scan();
    session.editBlockText('synthetic-text', '$_original 新输入');
    _require(
      task.phase == RuleWorkbenchPhase.stale && !task.hasCurrentTrial,
      'Stale scan remained valid.',
    );
    final staleRevision = session.saveSeq;
    await task.applySelected(selectedIds);
    _require(session.saveSeq == staleRevision, 'Stale changes applied.');
    final pending = task.scan();
    task.cancel();
    await pending;
    _require(
      !task.hasCurrentTrial && task.matches.isEmpty,
      'Cancelled scan published.',
    );
    appearance.value = (true, 1.6);
    window.setSize(const Size(820, 900).toNative(), false);
    await _phase(root, 'rules-cancelled-dark-820-scaled');
    _require(errors.isEmpty, 'Flutter framework errors.');
    result.addAll({
      'passed': true,
      'frameworkErrors': errors,
      'renderedViewports': _viewports,
      'verified': [
        'offline-without-ai-config',
        'read-only-import-rules-without-trial',
        'exclude-definition-and-filtering',
        'whole-line-condition',
        'definition-examples-left-aligned',
        'no-default-rule-selection',
        'complete-unsaved-scan',
        'save-does-not-edit-manuscript',
        'mixed-exact-delete-and-split',
        'single-undo-redo',
        'stale-refusal',
        'cancelled-result-cleared',
      ],
    });
  } catch (error, stack) {
    result.addAll({
      'passed': false,
      'error': error.toString(),
      'stack': stack.toString(),
      'frameworkErrors': errors,
      'phase': task.phase.name,
      'failure': task.failure?.message,
    });
  } finally {
    container.dispose();
    await session.close();
    await database.close();
    await File('$path/native-rule-workbench-result.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    exit(result['passed'] == true ? 0 : 1);
  }
}

ProofreadingRule _rule(
  String id,
  ProofreadingRuleKind kind,
  String pattern, {
  bool global = false,
  int? titleCaptureGroup,
  int? numberCaptureGroup,
  int headingLevel = 2,
  List<String>? positiveExamples,
  String? excludePattern,
  bool wholeLineOnly = false,
}) => ProofreadingRule.create(
  id: id,
  name: kind == ProofreadingRuleKind.chapter ? '合成章节识别' : '合成广告规则 $id',
  kind: kind,
  source: ProofreadingRuleSource.user,
  bookId: 'synthetic-book',
  scope: global ? ProofreadingRuleScope.global : ProofreadingRuleScope.book,
  globalScopeConfirmed: global,
  target: kind == ProofreadingRuleKind.chapter
      ? ProofreadingRuleTarget.headingLine
      : ProofreadingRuleTarget.bodyLine,
  mode: titleCaptureGroup == null
      ? ProofreadingMatchMode.literal
      : ProofreadingMatchMode.safeRegex,
  titleCaptureGroup: titleCaptureGroup,
  numberCaptureGroup: numberCaptureGroup,
  headingLevel: headingLevel,
  pattern: pattern,
  excludePattern: excludePattern,
  wholeLineOnly: wholeLineOnly,
  caseSensitive: true,
  action: kind == ProofreadingRuleKind.chapter
      ? ProofreadingRuleAction.chapterCandidate
      : global
      ? ProofreadingRuleAction.advertisementCandidate
      : ProofreadingRuleAction.exactDeletion,
  positiveExamples: positiveExamples ?? [pattern],
  negativeExamples: const ['纯剧情正文'],
);

String _body(EditorSession session) =>
    (session.book!.chapters.first.blocks.single as TextBlock).text;
void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await _nextFrame('settle');
}

Future<void> _nextFrame(String stage) async {
  final binding = WidgetsBinding.instance;
  binding.scheduleFrame();
  await binding.endOfFrame.timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw StateError(
      'Native frame wait timed out at $stage: '
      'enabled=${binding.framesEnabled}, scheduled=${binding.hasScheduledFrame}, '
      'phase=${binding.schedulerPhase}.',
    ),
  );
}

Element? _exactTextElement(String text) {
  Element? found;
  void visit(Element element) {
    final widget = element.widget;
    if (found == null &&
        (widget is Text && widget.data == text ||
            widget is SelectableText && widget.data == text)) {
      found = element;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
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

Future<void> _collapse(String key) async {
  final tile = await _findControl(key);
  ExpansibleController? expansion;
  void findExpansion(Element element) {
    final widget = element.widget;
    if (widget is Expansible) {
      expansion = widget.controller;
      return;
    }
    element.visitChildren(findExpansion);
  }

  tile.visitChildren(findExpansion);
  _require(expansion != null, 'Import rule expansion controller missing.');
  expansion!.collapse();
  await _settle();
}

Future<void> _expand(String key) async {
  final tile = await _findControl(key);
  ExpansibleController? expansion;
  void findExpansion(Element element) {
    final widget = element.widget;
    if (widget is Expansible) {
      expansion = widget.controller;
      return;
    }
    element.visitChildren(findExpansion);
  }

  tile.visitChildren(findExpansion);
  _require(expansion != null, 'Chapter preview controller missing.');
  expansion!.expand();
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
  stdout.writeln('Native phase starting: $phase');
  var themeFrames = 0;
  if (phase.contains('dark')) {
    final expected = AppTheme.dark().textTheme.bodyMedium!.color!;
    final clock = Stopwatch()..start();
    final targetLabel = _mapping
        ? '${_volumeMapping ? '新卷标题' : '新目录标题'}: $_mappingTitle'
        : null;
    var settled = false;
    for (
      ;
      themeFrames < 150 && clock.elapsed < const Duration(seconds: 10);
      themeFrames++
    ) {
      await _nextFrame('$phase/$themeFrames');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      Element? firstText;
      Element? targetText;
      void findText(Element element) {
        final widget = element.widget;
        if (widget is RichText) {
          firstText ??= element;
          if (widget.text.toPlainText() == targetLabel) targetText ??= element;
        }
        element.visitChildren(findText);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(findText);
      final probe = targetLabel == null ? firstText : targetText;
      if (themeFrames == 0 || themeFrames == 10) {
        stdout.writeln(
          'Native theme frame $themeFrames: expected=${expected.toARGB32()}, '
          'firstText=${firstText == null ? null : (firstText!.widget as RichText).text.toPlainText()}, '
          'firstRendered=${firstText == null ? null : (firstText!.widget as RichText).text.style?.color?.toARGB32()}, '
          'firstExactEquality=${firstText == null ? null : (firstText!.widget as RichText).text.style?.color == expected}, '
          'probeText=${probe == null ? null : (probe.widget as RichText).text.toPlainText()}, '
          'probeTheme=${probe == null ? null : Theme.of(probe).textTheme.bodyMedium?.color?.toARGB32()}, '
          'probeRendered=${probe == null ? null : (probe.widget as RichText).text.style?.color?.toARGB32()}.',
        );
      }
      if (probe != null &&
          Theme.of(probe).brightness == Brightness.dark &&
          Theme.of(probe).textTheme.bodyMedium?.color?.toARGB32() ==
              expected.toARGB32() &&
          (probe.widget as RichText).text.style?.color?.toARGB32() ==
              expected.toARGB32()) {
        settled = true;
        break;
      }
    }
    _require(
      settled,
      'Native dark theme did not reach its target text colors.',
    );
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
