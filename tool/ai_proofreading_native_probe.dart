import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/app/ai_providers.dart';
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
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:bookloom/features/editor/application/ai_proofreading_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:bookloom/features/editor/presentation/ai_proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/rule_workbench_panel.dart';
import 'package:bookloom/features/settings/data/ai_http_client.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

const _original = '正文开始。\n本站推广请访问example.invalid\n正文结束。';
const _advertisement = '本站推广请访问example.invalid';
const _splitTitle = '第二章 合成边界';
const _splitOriginal = '😀前段。\n$_splitTitle\r\n恢复后的正文。';
const _renameTitle = '第一章 😀原文标题';
const _renameOriginal = '$_renameTitle\r\n原文正文保持不变。';
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
    throw StateError('Owned native root and private session bus are required.');
  }
  final root = Directory(path);
  final errors = <String>[];
  final pointerEvents = <Map<String, double>>[];
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  WindowControls.configure();
  final database = AppDatabase.memory();
  final repository = BookRepository(database, Directory('$path/data'));
  final fixture = _fixture();
  await repository.createBook(
    _auditHandoff
        ? fixture.copyWith(
            chapters: [
              ...fixture.chapters,
              const Chapter(
                id: 'synthetic-distant',
                bookId: 'synthetic-book',
                title: '第四章 无关活动章',
                order: 2,
                blocks: [
                  TextBlock(id: 'synthetic-distant-body', text: '不应发送的无关合成章节。'),
                ],
              ),
            ],
          )
        : fixture,
    source: _splitImpact
        ? SourceImport(
            format: 'txt',
            originalName: 'synthetic-split.txt',
            openRead: () => Stream.value(utf8.encode(_splitOriginal)),
          )
        : null,
    assets: [
      if (_splitImpact)
        AssetImport(
          id: 'synthetic-image-asset',
          kind: 'image',
          mime: 'image/png',
          extension: 'png',
          openRead: () => Stream.value(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN1sAAAAASUVORK5CYII=',
            ),
          ),
        ),
    ],
  );
  final session = EditorSession(
    repository: repository,
    debounce: const Duration(hours: 1),
  );
  await session.open('synthetic-book');
  if (_auditHandoff) await session.selectChapter('synthetic-distant');
  final credentials = _Credentials();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  var disconnectedResponses = 0;
  var returnSplit = _splitImpact;
  var returnRemove = false;
  var returnRename = false;
  final requestBodies = <Map<String, dynamic>>[];
  Completer<void>? responseGate;
  final subscription = server.listen((request) async {
    requests++;
    try {
      final body = await utf8.decoder.bind(request).join();
      if (_auditHandoff || _advertisementSelection || _splitImpact) {
        requestBodies.add(jsonDecode(body) as Map<String, dynamic>);
      }
      final gate = responseGate;
      if (gate != null) await gate.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'object': 'chat.completion',
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {
                'role': 'assistant',
                'content': jsonEncode(
                  _auditHandoff
                      ? {
                          'schema_version': 1,
                          'findings': <Object?>[],
                          'proposals': <Object?>[],
                          'rule_proposals': <Object?>[],
                        }
                      : returnRename
                      ? _renameResponse()
                      : returnRemove
                      ? _removeResponse()
                      : returnSplit
                      ? _splitResponse()
                      : _response(),
                ),
              },
            },
          ],
        }),
      );
      await request.response.close();
    } on Object {
      try {
        await request.response.close();
      } on Object {
        disconnectedResponses++;
      }
    }
  });
  final configuration = AiConfiguration(
    enabled: true,
    address: 'http://127.0.0.1:${server.port}/v1',
    model: 'synthetic-model',
    credentialReference: 'synthetic-reference',
  );
  late AiProofreadingTask task;
  var taskCreated = false;
  final ruleStore = SettingsProofreadingRuleStore(database);
  final container = ProviderContainer(
    overrides: [
      proofreadingRuleStoreProvider.overrideWithValue(ruleStore),
      aiProofreadingTaskProvider.overrideWith((ref, target) {
        task = AiProofreadingTask(
          session: target,
          loadConfiguration: () async => configuration,
          credentials: credentials,
          createClient: AiHttpClient.new,
        );
        taskCreated = true;
        task.addListener(
          () => File('${root.path}/live-state.json').writeAsStringSync(
            jsonEncode({
              'phase': task.phase.name,
              'failure': task.failure?.message,
              'requests': requests,
              'busy': task.isBusy,
            }),
          ),
        );
        return task;
      }),
    ],
  );
  final advertisementSelection = _advertisementSelection
      ? AiAdvertisementRequest.fromSelection(
          book: session.book!,
          sessionId: session.sessionId!,
          sessionRevision: session.saveSeq,
          chapterId: 'synthetic-chapter',
          blockId: 'synthetic-block',
          startUtf16: _original.indexOf(_advertisement),
          endUtf16: _original.indexOf(_advertisement) + _advertisement.length,
          original: _advertisement,
          ruleName: '合成广告候选规则',
        )
      : null;
  final appearance = ValueNotifier<(bool, double)>((false, 1));
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<(bool, double)>(
        valueListenable: appearance,
        builder: (context, value, child) => MaterialApp(
          title: 'Bookloom AI proofreading isolated probe',
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: value.$1 ? AppTheme.dark() : AppTheme.light(),
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
              child: Listener(
                onPointerDown: (event) => pointerEvents.add({
                  'x': event.position.dx,
                  'y': event.position.dy,
                }),
                child: _auditHandoff
                    ? ProofreadingPanel(
                        key: const ValueKey('native-workbench-panel'),
                        session: session,
                        onLocate: (chapterId, blockId) async {},
                      )
                    : AiProofreadingPanel(
                        key: const ValueKey('native-ai-panel'),
                        session: session,
                        initialAdvertisementSelection: advertisementSelection,
                        onLocate: (chapterId, blockId) async {},
                        onUseRule: _jointRules
                            ? (rule) {
                                final sessionId = session.sessionId;
                                final revision = session.saveSeq;
                                unawaited(
                                  showDialog<void>(
                                    context: _element('native-ai-panel')!,
                                    builder: (dialog) => Dialog(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth:
                                              AppLayout.workbenchDialogMaxWidth,
                                        ),
                                        child: SizedBox(
                                          height:
                                              MediaQuery.sizeOf(dialog).height *
                                              AppLayout
                                                  .workbenchDialogHeightFraction,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Align(
                                                alignment: AlignmentDirectional
                                                    .centerEnd,
                                                child: IconButton(
                                                  key: const ValueKey(
                                                    'native-close-rule-dialog',
                                                  ),
                                                  onPressed: () =>
                                                      Navigator.of(dialog)
                                                          .pop(),
                                                  icon: const Icon(Icons.close),
                                                ),
                                              ),
                                              Expanded(
                                                child: RuleWorkbenchPanel(
                                                  key: const ValueKey(
                                                    'native-joint-workbench-panel',
                                                  ),
                                                  session: session,
                                                  initialRule: rule,
                                                  initialSessionId: sessionId,
                                                  initialSaveSeq: revision,
                                                  onLocate: (
                                                    chapterId,
                                                    blockId,
                                                  ) async {},
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            : null,
                      ),
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
    'usesRealCloudService': false,
    'usesIntegrationTestBinding': false,
    'usesNativePointerClicks': !_callbackAutomation,
    'usesWidgetCallbackAutomation': _callbackAutomation,
    'nativeInputUnverified': _callbackAutomation,
  };
  try {
    await _settle();
    final window = WindowManager.instance.getCurrent();
    if (window == null) throw StateError('Owned native window missing.');
    window.title = 'Bookloom AI proofreading isolated probe';
    window.minimumSize = const Size(320, 480).toNative();
    window.setSize(const Size(1280, 900).toNative(), false);
    window.show();
    await _settle();
    if (_splitImpact) {
      final source = (await repository.loadSource('synthetic-book'))!;
      final asset = (await repository.loadAssets('synthetic-book')).single;
      final sourceBytes = await (await repository.resolveSource(source))
          .readAsBytes();
      final assetBytes = await (await repository.resolveAsset(asset))
          .readAsBytes();
      await _click(root, 'ai-intent-missingChapter');
      await _click(root, 'ai-prepare');
      await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
      _require(
        requests == 0 && credentials.reads == 0,
        'Split preparation sent data.',
      );
      await _click(root, 'ai-run');
      await _until(() => task.phase == AiProofreadingPhase.completed);
      final split = task.splitChanges.single;
      _require(
        requests == 1 &&
            credentials.reads == 1 &&
            split.precedingBlockCount == 3 &&
            split.followingBlockCount == 4 &&
            split.parentTitle == '第一卷 合成卷' &&
            !session.canUndo &&
            session.book!.chapters.length == 3,
        'Complete split impact missing or automatically applied.',
      );
      final wire = jsonEncode(requestBodies.single);
      _require(
        !wire.contains('synthetic-image-asset') &&
            !wire.contains('仅本地图注') &&
            !wire.contains('仅本地脚注'),
        'Local resource metadata leaked into AI context.',
      );
      await _click(root, 'ai-change-${split.id}');
      await _expandTile('ai-split-before-${split.id}');
      await _phase(root, 'split-impact-before-light-1280');
      await _expandTile('ai-split-after-${split.id}');
      window.setSize(const Size(820, 900).toNative(), false);
      appearance.value = (true, 1.6);
      final afterRow = _textElement('synthetic-after-image');
      _require(
        afterRow != null,
        'Split following resource rows are missing from the native preview.',
      );
      final beforeScroll = _scrollState();
      for (var attempt = 0; attempt < 3; attempt++) {
        await Scrollable.ensureVisible(afterRow!, alignment: .05);
        await _settle();
      }
      final afterScroll = _scrollState();
      final rowBox = afterRow!.renderObject;
      final rowTop = rowBox is RenderBox
          ? rowBox.localToGlobal(Offset.zero).dy
          : null;
      final rowBottom = rowBox is RenderBox
          ? rowBox.localToGlobal(Offset(0, rowBox.size.height)).dy
          : null;
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      _require(
        rowTop != null &&
            rowBottom != null &&
            rowTop >= 0 &&
            rowBottom <= view.physicalSize.height,
        'Split following resource rows were not visible in the native window.',
      );
      await File('${root.path}/split-scroll-diagnostic.json').writeAsString(
        jsonEncode({
          'before': beforeScroll,
          'after': afterScroll,
          'rowTop': rowTop,
          'rowBottom': rowBottom,
          'viewportHeight': view.physicalSize.height,
        }),
      );
      await _phase(root, 'split-impact-after-dark-scaled-820');
      appearance.value = (false, 1);
      window.setSize(const Size(1280, 900).toNative(), false);
      await _click(root, 'ai-apply-selected');
      await _until(() => task.phase == AiProofreadingPhase.applied);
      final chapters = session.book!.chapters;
      final original = chapters.singleWhere(
        (chapter) => chapter.id == 'synthetic-chapter',
      );
      final created = chapters.singleWhere(
        (chapter) => chapter.title == _splitTitle,
      );
      _require(
        chapters.length == 4 &&
            original.parentId == 'synthetic-volume' &&
            created.parentId == 'synthetic-volume' &&
            original.blocks.take(3).map((block) => block.id).join(',') ==
                'synthetic-before-image,synthetic-before-note,synthetic-before-divider' &&
            original.blocks.last.plainText == '😀前段。\n' &&
            created.blocks.first.plainText == '恢复后的正文。' &&
            created.blocks.skip(1).map((block) => block.id).join(',') == 'synthetic-after-image,synthetic-after-note,synthetic-after-divider,synthetic-after-text',
        'Applied split differs from resource ownership preview.',
      );
      await session.undo();
      _require(
        session.book!.chapters.length == 3 &&
            session.activeChapter!.blocks.length == 8 &&
            session.activeChapter!.blocks[3].plainText == _splitOriginal,
        'Split impact undo lost resources.',
      );
      await session.redo();
      await session.flush();
      final persisted = (await repository.loadChapter(
        'synthetic-book',
        created.id,
      ))!;
      _require(
        persisted.blocks.length == 5 &&
            persisted.blocks.indexed.every(
              (entry) => entry.$2 == created.blocks[entry.$1],
            ) &&
            persisted.parentId == 'synthetic-volume' &&
            (await repository.loadSource('synthetic-book'))?.id == source.id &&
            (await repository.loadAssets('synthetic-book')).single.id ==
                asset.id &&
            base64Encode(
                  await (await repository.resolveAsset(asset)).readAsBytes(),
                ) ==
                base64Encode(assetBytes) &&
            base64Encode(
                  await (await repository.resolveSource(source)).readAsBytes(),
                ) ==
                base64Encode(sourceBytes) &&
            errors.isEmpty,
        'Split persistence, source or asset preservation failed.',
      );
      result.addAll({
        'passed': true,
        'requests': requests,
        'credentialReads': credentials.reads,
        'frameworkErrors': errors,
        'renderedViewports': _viewports,
        'verified': [
          'local-complete-ordered-split-impact',
          'preceding-and-following-resource-ownership',
          'parent-volume-retained',
          'no-resource-context-leak',
          'zero-send-before-confirmation',
          'no-auto-apply',
          'explicit-apply-undo-redo-sqlite-persistence',
          'source-and-image-bytes-preserved',
          'light-dark-scaled-rendering',
        ],
      });
      return;
    }
    if (_auditHandoff) {
      await _click(root, 'proofreading-audit-run');
      await _until(() => _element('audit-ai-gap-synthetic-next') != null);
      await _phase(root, 'audit-gap-finding-light-1280');
      _require(requests == 0 && credentials.reads == 0, 'Audit contacted AI.');
      await _click(root, 'audit-ai-gap-synthetic-next');
      await _until(
        () => taskCreated && _element('ai-audit-gap-source') != null,
      );
      _require(
        requests == 0 &&
            credentials.reads == 0 &&
            session.activeChapterId == 'synthetic-distant',
        'Opening the handoff sent data or selected a different editor chapter.',
      );
      await _phase(root, 'audit-gap-source-light-1280');
      await _click(root, 'ai-prepare');
      await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
      final consent = task.consent!;
      final chapterIds = consent.plan.chunks
          .expand((chunk) => chunk.slices)
          .map((slice) => slice.block.chapterId)
          .toSet();
      _require(
        chapterIds.length == 2 &&
            chapterIds.contains('synthetic-chapter') &&
            chapterIds.contains('synthetic-next') &&
            consent.auditGap?.gap.firstMissing == 2 &&
            consent.auditGap?.gap.lastMissing == 2 &&
            requests == 0 &&
            credentials.reads == 0,
        'Handoff scope does not match the selected gap.',
      );
      appearance.value = (true, 1.6);
      window.setSize(const Size(820, 900).toNative(), false);
      await _phase(root, 'audit-gap-consent-dark-scaled-820');
      await _click(root, 'ai-run');
      await _until(() => task.phase == AiProofreadingPhase.completed);
      _require(
        requests == 1 &&
            credentials.reads == 1 &&
            requestBodies.length == 1 &&
            task.changes.isEmpty &&
            task.splitChanges.isEmpty,
        'Explicit handoff request failed.',
      );
      final messages = requestBodies.single['messages'] as List;
      final content =
          jsonDecode((messages.last as Map)['content'] as String) as Map;
      final gap = content['audit_gap'] as Map;
      _require(
        gap['first_missing'] == 2 &&
            gap['last_missing'] == 2 &&
            gap['before_chapter_id'] == 'synthetic-chapter' &&
            gap['after_chapter_id'] == 'synthetic-next' &&
            !(messages.last as Map)['content'].toString().contains(
              '不应发送的无关合成章节。',
            ),
        'Wire data lost the gap or included the active unrelated chapter.',
      );
      _require(
        session.book!.chapters.length == 3 &&
            session.book!.chapters.first.title == '第一章 合成数据',
        'A diagnosis modified the manuscript.',
      );
      await _click(root, 'ai-prepare');
      await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
      session.editChapterTitle('synthetic-next', '第三章 人工修改');
      await _until(
        () =>
            task.phase == AiProofreadingPhase.stale ||
            task.phase == AiProofreadingPhase.cancelled,
      );
      await _phase(root, 'audit-gap-stale-dark-scaled-820');
      _require(
        requests == 1 && errors.isEmpty,
        'Stale gap sent data or raised framework errors.',
      );
      result.addAll({
        'passed': true,
        'requests': requests,
        'credentialReads': credentials.reads,
        'frameworkErrors': errors,
        'renderedViewports': _viewports,
        'verified': [
          'audit-to-ai-gap-handoff',
          'unrelated-active-chapter-excluded',
          'no-send-or-credential-read-before-confirmation',
          'exact-gap-wire-metadata',
          'diagnosis-does-not-modify-book',
          'stale-gap-refuses-send',
          'light-dark-scaled-rendering',
        ],
      });
      return;
    }
    if (_advertisementSelection) {
      if (_jointRules) {
        final checkbox = _element('ai-request-rules')?.widget;
        _require(
          checkbox is Checkbox && checkbox.value == false,
          'Joint rule request was not explicitly opt-in.',
        );
        await _click(root, 'ai-request-rules');
      }
      await _click(root, 'ai-prepare');
      await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
      _require(requests == 0 && credentials.reads == 0, 'Selection auto-sent.');
      final consent = task.consent!;
      if (_jointRules) {
        _require(
          consent.ruleRequest?.positiveExamples.single == _advertisement &&
              consent.ruleRequest?.kind == ProofreadingRuleKind.advertisement &&
              consent.ruleChunkIndex == 0,
          'Joint rule authorization differs from the explicit samples.',
        );
      }
      final slices = consent.plan.chunks.single.slices;
      final focus = slices.singleWhere(
        (slice) => slice.block.blockId == 'synthetic-block',
      );
      _require(
        focus.text == _advertisement &&
            focus.startUtf16 == _original.indexOf(_advertisement) &&
            focus.endUtf16 ==
                _original.indexOf(_advertisement) + _advertisement.length &&
            slices.length == 3,
        'Selection or neighboring scope differs.',
      );
      await _phase(root, 'ad-selection-consent-light-1280');
      window.setSize(const Size(820, 900).toNative(), false);
      appearance.value = (true, 1.6);
      await _phase(root, 'ad-selection-consent-dark-scaled-820');
      window.setSize(const Size(1280, 900).toNative(), false);
      appearance.value = (false, 1);
      await _click(root, 'ai-run');
      await _until(() => task.phase == AiProofreadingPhase.completed);
      _require(
        requests == 1 &&
            task.changes.length == 1 &&
            _text(session) == _original,
        'Validated selection result missing or automatically applied.',
      );
      final sent = jsonDecode(
        (requestBodies.single['messages'] as List).last['content'] as String,
      ) as Map<String, dynamic>;
      _require(
        sent['advertisement_selection'] != null &&
            !jsonEncode(sent).contains('未修改的后续章节。'),
        'Selection metadata missing or unrelated chapter leaked.',
      );
      await _phase(root, 'ad-selection-results-light-1280');
      if (_jointRules) {
        _require(
          task.ruleProposals.length == 1 &&
              task.canUseRuleProposals &&
              sent['rule_request'] != null &&
              (await ruleStore.loadForBook('synthetic-book')).isEmpty,
          'Joint rules missing, unsolicited or automatically persisted.',
        );
        final proposal = task.ruleProposals.single;
        await _expandTile('ai-rule-tile-${proposal.proposalId}');
        await _phase(root, 'joint-rule-result-light-1280');
        await _click(root, 'ai-use-rule-${proposal.proposalId}');
        await _until(() => _element('rule-scan') != null);
        final workbench = container.read(ruleWorkbenchTaskProvider(session));
        await _until(
          () => workbench.rules.any((rule) => rule.id == proposal.rule.id),
        );
        _require(
          workbench.trial == null &&
              !session.canUndo &&
              _text(session) == _original &&
              (await ruleStore.loadForBook('synthetic-book')).isEmpty,
          'Rule handoff automatically scanned, saved or changed the manuscript.',
        );
        await _click(root, 'rule-scan');
        await _until(() => workbench.hasCurrentTrial);
        _require(
          workbench.trial!.distinctMatches == 1,
          'Joint rule trial differs.',
        );
        window.setSize(const Size(820, 900).toNative(), false);
        appearance.value = (true, 1.6);
        await _phase(root, 'joint-rule-trial-dark-scaled-820');
        await _click(root, 'rule-save');
        await _until(() => workbench.isSaved(proposal.rule.id));
        _require(
          (await ruleStore.loadForBook('synthetic-book')).single.id ==
                  proposal.rule.id &&
              _text(session) == _original &&
              !session.canUndo,
          'Save-only did not persist the independent rule or modified the book.',
        );
        window.setSize(const Size(1280, 900).toNative(), false);
        appearance.value = (false, 1);
        await _phase(root, 'joint-rule-saved-light-1280');
        await _click(root, 'native-close-rule-dialog');
        await _until(() => _element('native-joint-workbench-panel') == null);
        _require(
          task.canApply &&
              task.changes.length == 1 &&
              task.ruleProposals.length == 1,
          'Rule handoff discarded the independent text proposals.',
        );
      }
      await _click(root, 'ai-change-${task.changes.single.id}');
      await _click(root, 'ai-apply-selected');
      await _until(() => task.phase == AiProofreadingPhase.applied);
      final edited = _original.replaceFirst(_advertisement, '');
      _require(_text(session) == edited, 'Selection precise deletion failed.');
      await session.undo();
      _require(_text(session) == _original, 'Selection undo failed.');
      await session.redo();
      await session.flush();
      final reloaded = (await repository.loadChapter(
        'synthetic-book',
        'synthetic-chapter',
      ))!;
      _require(
        reloaded.blocks
                    .whereType<TextBlock>()
                    .singleWhere((block) => block.id == 'synthetic-block')
                    .text ==
                edited &&
            reloaded.blocks.length == 3 &&
            reloaded.blocks.first.plainText == '只读相邻前段。' &&
            reloaded.blocks.last.plainText == '只读相邻后段。' &&
            errors.isEmpty,
        'Selection persistence, neighbors or rendering failed.',
      );
      if (_jointRules) {
        _require(
          (await ruleStore.loadForBook('synthetic-book')).single.name ==
              '合成联合广告规则',
          'Independent saved rule was lost after body apply and undo/redo.',
        );
      }
      result.addAll({
        'passed': true,
        'requests': requests,
        'credentialReads': credentials.reads,
        'frameworkErrors': errors,
        'renderedViewports': _viewports,
        'verified': [
          'explicit-selection-with-read-only-neighbors',
          'zero-send-before-confirmation',
          'exact-selection-wire-scope',
          'no-auto-apply',
          'precise-apply-undo-redo-persistence',
          'light-dark-scaled-rendering',
          if (_jointRules) ...[
            'joint-rule-request-explicit-opt-in',
            'separate-rule-and-text-results',
            'no-auto-rule-trial-save-or-manuscript-edit',
            'rule-save-only-persistence-and-return-to-text-proposal',
          ],
        ],
      });
      return;
    }
    await _click(root, 'ai-prepare');
    await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
    _require(
      credentials.reads == 0 && requests == 0,
      'Preparation sent data or read credentials.',
    );
    _require(
      task.consent!.plan.inputCharacters == _original.length,
      'Scope is incomplete.',
    );
    await _phase(root, 'consent-light-1280');
    appearance.value = (true, 1);
    await _phase(root, 'consent-dark-1280');
    window.setSize(const Size(420, 900).toNative(), false);
    appearance.value = (true, 1.6);
    await _phase(root, 'consent-dark-desktop-min-scaled');
    window.setSize(const Size(1280, 900).toNative(), false);
    appearance.value = (false, 1);
    await _click(root, 'ai-run');
    await _until(() => task.phase == AiProofreadingPhase.completed);
    _require(
      task.changes.length == 1 && task.completedChunks == 1 && requests == 1,
      'Expected exactly one validated synthetic change.',
    );
    _require(
      _text(session) == _original && !session.canUndo,
      'A change was applied without selection.',
    );
    await _phase(root, 'results-light-1280');
    final firstChange = task.changes.single;
    final initialSeq = session.saveSeq;
    await _click(root, 'ai-change-${task.changes.single.id}');
    await _click(root, 'ai-ignore-${firstChange.finding.id}');
    _require(
      task.ignoredFindingCount == 1 &&
          task.visibleChanges.isEmpty &&
          task.visibleFindings.isEmpty &&
          _text(session) == _original &&
          session.saveSeq == initialSeq &&
          !session.canUndo &&
          requests == 1,
      'Ignoring a result changed the manuscript or sent another request.',
    );
    await _phase(root, 'ignored-light-1280');
    window.setSize(const Size(820, 900).toNative(), false);
    appearance.value = (true, 1.6);
    await _until(() {
      final element = _element('native-ai-panel');
      return element != null &&
          Theme.of(element).colorScheme.surface ==
              AppTheme.dark().colorScheme.surface;
    });
    await _phase(root, 'ignored-dark-scaled-820');
    await _click(root, 'ai-restore-ignored');
    _require(
      task.ignoredFindingCount == 0 && task.visibleChanges.length == 1,
      'Ignored result was not restored.',
    );
    appearance.value = (false, 1);
    window.setSize(const Size(1280, 900).toNative(), false);
    await _click(root, 'ai-change-${firstChange.id}', requireUnchecked: true);
    await _click(root, 'ai-apply-selected');
    await _until(() => task.phase == AiProofreadingPhase.applied);
    _require(
      _text(session) == _original.replaceFirst(_advertisement, ''),
      'Precise application failed.',
    );
    await session.undo();
    _require(
      _text(session) == _original,
      'Undo did not restore the synthetic text.',
    );
    await session.redo();
    _require(
      _text(session) == _original.replaceFirst(_advertisement, ''),
      'Redo failed.',
    );
    await session.undo();
    await _click(root, 'ai-prepare');
    await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
    final staleConsent = task.consent!;
    session.editBlockText('synthetic-block', '手工修改后的合成正文');
    await _until(() => task.phase == AiProofreadingPhase.stale);
    await task.run(staleConsent);
    _require(requests == 1 && !task.canApply, 'Stale consent sent data.');
    session.editBlockText('synthetic-block', _original);
    await _click(root, 'ai-prepare');
    await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
    responseGate = Completer<void>();
    await _click(root, 'ai-run');
    await _until(() => requests == 2);
    await _click(root, 'ai-cancel');
    await _until(() => !task.isBusy);
    responseGate.complete();
    _require(
      task.phase == AiProofreadingPhase.cancelled &&
          task.changes.isEmpty &&
          _text(session) == _original,
      'Cancelled result could be applied.',
    );
    appearance.value = (true, 1.6);
    window.setSize(const Size(420, 900).toNative(), false);
    await _phase(root, 'cancelled-dark-desktop-min-scaled');
    window.setSize(const Size(1280, 900).toNative(), false);
    appearance.value = (false, 1);
    session.editBlockText('synthetic-block', _splitOriginal);
    returnSplit = true;
    await _click(root, 'ai-intent-missingChapter');
    await _click(root, 'ai-prepare');
    await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
    await _phase(root, 'split-consent-light-1280');
    await _click(root, 'ai-run');
    await _until(() => task.phase == AiProofreadingPhase.completed);
    _require(
      task.splitChanges.length == 1 && task.changes.isEmpty && requests == 3,
      'Expected one reliable chapter split.',
    );
    _require(
      session.book!.chapters.length == 2,
      'Split was applied automatically.',
    );
    await _click(root, 'ai-change-${task.splitChanges.single.id}');
    final split = task.splitChanges.single;
    await _click(root, 'ai-ignore-${split.finding.id}');
    _require(
      task.visibleSplitChanges.isEmpty &&
          task.ignoredFindingCount == 1 &&
          session.book!.chapters.length == 2 &&
          _text(session) == _splitOriginal,
      'Ignoring a chapter split changed the manuscript.',
    );
    await _click(root, 'ai-restore-ignored');
    await _click(root, 'ai-change-${split.id}', requireUnchecked: true);
    await _phase(root, 'split-selected-light-1280');
    final splitAction = _element('ai-locate-${task.splitChanges.single.id}');
    _require(splitAction != null, 'Expanded split preview is missing.');
    await Scrollable.ensureVisible(splitAction!, alignment: 1);
    await _phase(root, 'split-preview-end-light-1280');
    await _click(root, 'ai-apply-selected');
    await _until(() => task.phase == AiProofreadingPhase.applied);
    _require(
      session.book!.chapters.length == 3 &&
          session.book!.chapters[1].title == _splitTitle &&
          session.book!.chapters[1].blocks.single.plainText == '恢复后的正文。' &&
          _text(session) == '😀前段。\n',
      'Split did not preserve exact boundaries.',
    );
    await session.undo();
    _require(
      _text(session) == _splitOriginal && session.book!.chapters.length == 2,
      'Split undo failed.',
    );
    await session.redo();
    _require(session.book!.chapters.length == 3, 'Split redo failed.');
    await session.flush();
    await session.undo();
    session.editBlockText('synthetic-block', _advertisement);
    await session.readAiContext(['synthetic-next']);
    returnRemove = true;
    await _click(root, 'ai-intent-advertisement');
    await _click(root, 'ai-prepare');
    await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
    await _click(root, 'ai-run');
    await _until(() => task.phase == AiProofreadingPhase.completed);
    _require(
      requests == 4 &&
          task.changes.length == 1 &&
          _text(session) == _advertisement,
      'Block removal was not proposed without changing the manuscript.',
    );
    final removal = task.changes.single;
    await _click(root, 'ai-change-${removal.id}', requireUnchecked: true);
    final impact = _element('ai-remove-block-impact-${removal.id}');
    _require(impact != null, 'Whole-block removal impact is missing.');
    await Scrollable.ensureVisible(impact!, alignment: .5);
    await _phase(root, 'remove-block-impact-light-1280');
    await _click(root, 'ai-ignore-${removal.finding.id}');
    _require(
      task.visibleChanges.isEmpty && _text(session) == _advertisement,
      'Ignoring removal changed the manuscript.',
    );
    await _click(root, 'ai-restore-ignored');
    await _click(root, 'ai-change-${removal.id}', requireUnchecked: true);
    await _click(root, 'ai-apply-selected');
    await _until(() => task.phase == AiProofreadingPhase.applied);
    _require(
      session.book!.chapters.length == 2 &&
          session.activeChapter!.blocks.isEmpty &&
          session.book!.chapters.last.blocks.single.plainText == '未修改的后续章节。',
      'Removal did not preserve the empty chapter and sibling content.',
    );
    await session.undo();
    _require(_text(session) == _advertisement, 'Block removal undo failed.');
    await session.redo();
    _require(
      session.activeChapter!.blocks.isEmpty,
      'Block removal redo failed.',
    );
    await session.flush();
    await session.undo();
    session.editBlockText('synthetic-block', _renameOriginal);
    returnRename = true;
    await _click(root, 'ai-intent-missingChapter');
    await _click(root, 'ai-prepare');
    await _until(() => task.phase == AiProofreadingPhase.awaitingConsent);
    await _click(root, 'ai-run');
    await _until(() => task.phase == AiProofreadingPhase.completed);
    _require(
      requests == 5 &&
          task.changes.length == 1 &&
          task.splitChanges.isEmpty &&
          session.activeChapter!.title == '第一章 合成数据' &&
          _text(session) == _renameOriginal,
      'Title correction changed the manuscript before selection.',
    );
    final rename = task.changes.single;
    await _click(root, 'ai-change-${rename.id}', requireUnchecked: true);
    final titleImpact = _element('ai-rename-chapter-impact-${rename.id}');
    _require(titleImpact != null, 'Title correction impact is missing.');
    await Scrollable.ensureVisible(titleImpact!, alignment: .5);
    await _phase(root, 'rename-chapter-impact-light-1280');
    appearance.value = (true, 1.6);
    window.setSize(const Size(820, 900).toNative(), false);
    await _settle();
    await Scrollable.ensureVisible(titleImpact, alignment: .5);
    await _phase(root, 'rename-chapter-impact-dark-scaled-820');
    appearance.value = (false, 1);
    window.setSize(const Size(1280, 900).toNative(), false);
    await _click(root, 'ai-ignore-${rename.finding.id}');
    _require(
      task.visibleChanges.isEmpty && session.activeChapter!.title == '第一章 合成数据',
      'Ignoring title correction wrote the manuscript.',
    );
    await _click(root, 'ai-restore-ignored');
    await _click(root, 'ai-change-${rename.id}', requireUnchecked: true);
    await _click(root, 'ai-apply-selected');
    await _until(() => task.phase == AiProofreadingPhase.applied);
    _require(
      session.activeChapter!.title == _renameTitle &&
          _text(session) == _renameOriginal &&
          session.book!.chapters.length == 2,
      'Title correction rewrote text or changed chapter structure.',
    );
    await session.undo();
    _require(
      session.activeChapter!.title == '第一章 合成数据' &&
          _text(session) == _renameOriginal,
      'Title correction undo failed.',
    );
    await session.redo();
    await session.flush();
    final reloaded = (await repository.loadBook('synthetic-book'))!;
    _require(
      reloaded.chapters.first.title == _renameTitle &&
          (await repository.loadChapter(
                'synthetic-book',
                'synthetic-chapter',
              ))!.blocks.single.plainText ==
              _renameOriginal,
      'Title correction redo or persistence failed.',
    );
    _require(
      _callbackAutomation || pointerEvents.isNotEmpty,
      'No native pointer events were delivered.',
    );
    _require(errors.isEmpty, 'Framework errors: ${errors.join('; ')}');
    result.addAll({
      'passed': true,
      'requests': requests,
      'credentialReads': credentials.reads,
      'disconnectedResponses': disconnectedResponses,
      'pointerEvents': pointerEvents,
      'renderedViewports': _viewports,
      'frameworkErrors': errors,
      'verified': [
        'no-send-before-confirmation',
        'exact-scope',
        'explicit-selection',
        'ignore-restore-without-selection-or-manuscript-write',
        'ignore-restore-chapter-split',
        'precise-apply',
        'undo-redo',
        'explicit-chapter-split-and-undo-redo',
        'explicit-whole-block-removal-ignore-restore-and-undo-redo',
        'explicit-title-correction-ignore-restore-undo-redo-and-persistence',
        'stale-consent',
        _callbackAutomation ? 'widget-callback-cancel' : 'native-cancel',
        'light-dark-narrow-scaled-rendering',
      ],
    });
  } catch (error, stack) {
    result.addAll({
      'passed': false,
      'error': error.toString(),
      'stack': stack.toString(),
      'phase': taskCreated ? task.phase.name : null,
      'failure': taskCreated ? task.failure?.message : null,
      'pointerEvents': pointerEvents,
      'frameworkErrors': errors,
    });
  } finally {
    final gate = responseGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    runApp(const SizedBox.shrink());
    await _settle();
    container.dispose();
    await session.close();
    await database.close();
    await server.close(force: true);
    await subscription.cancel();
    await File('${root.path}/native-ai-task-result.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    exit(result['passed'] == true ? 0 : 1);
  }
}

String _text(EditorSession session) => session.activeChapter!.blocks
    .whereType<TextBlock>()
    .singleWhere((block) => block.id == 'synthetic-block')
    .text;

Map<String, Object> _response() => {
  'schema_version': 1,
  'findings': [
    {
      'id': 'finding',
      'category': 'advertisement',
      'assessment': 'advertisement',
      'chapter_id': 'synthetic-chapter',
      'block_id': 'synthetic-block',
      'original': _advertisement,
      'before': '',
      'after': '',
      'reason': '合成站点推广，不属于剧情。',
    },
  ],
  'proposals': [
    {
      'id': 'change',
      'finding_id': 'finding',
      'action': 'delete_text',
      'chapter_id': 'synthetic-chapter',
      'block_id': 'synthetic-block',
      'original': _advertisement,
      'before': '',
      'after': '',
      'replacement': '',
      'reason': '仅删除合成推广，保留两侧正文。',
    },
  ],
  'rule_proposals': <Object>[
    if (_jointRules)
      {
        'schema_version': 1,
        'name': '合成联合广告规则',
        'kind': 'advertisement',
        'target': 'body_line',
        'match': {
          'mode': 'literal',
          'pattern': _advertisement,
          'case_sensitive': true,
        },
        'action': 'exact_deletion',
        'positive_examples': [_advertisement],
        'negative_examples': <String>[],
        'reason': '只匹配明确的合成推广样例，保存与正文修改分别确认。',
      },
  ],
};

Map<String, Object> _removeResponse() {
  final response = _response();
  final proposals = response['proposals']! as List;
  final proposal = proposals.single as Map<String, Object>;
  proposal['action'] = 'remove_block';
  proposal['reason'] = '整块合成站点推广，没有需要保留的块内正文。';
  return response;
}

Map<String, Object> _renameResponse() {
  final response = _response();
  final finding = (response['findings']! as List).single as Map<String, Object>;
  finding['category'] = 'missing_chapter';
  finding['assessment'] = 'missed_heading';
  finding['original'] = _renameTitle;
  finding['reason'] = '原文起始独立标题与当前目录标题不一致。';
  final proposal =
      (response['proposals']! as List).single as Map<String, Object>;
  proposal['action'] = 'rename_chapter';
  proposal['original'] = _renameTitle;
  proposal['replacement'] = _renameTitle;
  proposal['original_title'] = '第一章 合成数据';
  proposal['reason'] = '按原文起始标题修正目录，保留正文中的标题行。';
  return response;
}

Map<String, Object> _splitResponse() => {
  'schema_version': 1,
  'findings': [
    {
      'id': 'split-finding',
      'category': 'missing_chapter',
      'assessment': 'missed_heading',
      'chapter_id': 'synthetic-chapter',
      'block_id': 'synthetic-block',
      'original': _splitTitle,
      'before': '',
      'after': '',
      'reason': '合成书稿正文中存在独立标题行。',
    },
  ],
  'proposals': [
    {
      'id': 'split-change',
      'finding_id': 'split-finding',
      'action': 'split_chapter',
      'chapter_id': 'synthetic-chapter',
      'block_id': 'synthetic-block',
      'original': _splitTitle,
      'before': '',
      'after': '',
      'title': _splitTitle,
      'remove_title_line': true,
      'reason': '按精确标题边界恢复合成章节。',
    },
  ],
  'rule_proposals': <Object>[],
};

class _Credentials implements AiCredentialStore {
  int reads = 0;
  @override
  Future<String?> read(String reference) async {
    reads++;
    return 'synthetic-only';
  }

  @override
  Future<void> write(String reference, String value) async =>
      throw StateError('Read-only probe.');
  @override
  Future<void> delete(String reference) async =>
      throw StateError('Read-only probe.');
}

Book _fixture() {
  final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return Book(
    id: 'synthetic-book',
    meta: BookMeta(title: '合成 AI 书稿', author: '测试'),
    chapters: [
      if (_splitImpact)
        const Chapter(
          id: 'synthetic-volume',
          bookId: 'synthetic-book',
          title: '第一卷 合成卷',
          level: 1,
        ),
      Chapter(
        id: 'synthetic-chapter',
        bookId: 'synthetic-book',
        title: '第一章 合成数据',
        parentId: _splitImpact ? 'synthetic-volume' : null,
        order: _splitImpact ? 1 : 0,
        blocks: [
          if (_splitImpact) ...[
            const ImageBlock(
              id: 'synthetic-before-image',
              assetId: 'synthetic-image-asset',
              caption: '仅本地图注：前图',
            ),
            const FootnoteBlock(
              id: 'synthetic-before-note',
              text: '仅本地脚注：前注',
              marker: '①',
            ),
            const DividerBlock(id: 'synthetic-before-divider'),
          ],
          if (_advertisementSelection)
            const TextBlock(id: 'synthetic-before', text: '只读相邻前段。'),
          TextBlock(
            id: 'synthetic-block',
            text: _splitImpact ? _splitOriginal : _original,
          ),
          if (_splitImpact) ...[
            const ImageBlock(
              id: 'synthetic-after-image',
              assetId: 'synthetic-image-asset',
              caption: '仅本地图注：后图',
              alt: '后图替代文字',
            ),
            const FootnoteBlock(
              id: 'synthetic-after-note',
              text: '仅本地脚注：后注',
              marker: '②',
            ),
            const DividerBlock(id: 'synthetic-after-divider'),
            const TextBlock(id: 'synthetic-after-text', text: '后续完整正文段。'),
          ],
          if (_advertisementSelection)
            const TextBlock(id: 'synthetic-after', text: '只读相邻后段。'),
        ],
      ),
      Chapter(
        id: 'synthetic-next',
        bookId: 'synthetic-book',
        title: '第三章 合成后文',
        parentId: _splitImpact ? 'synthetic-volume' : null,
        order: _splitImpact ? 2 : 1,
        blocks: const [
          TextBlock(id: 'synthetic-next-block', text: '未修改的后续章节。'),
        ],
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

List<Map<String, num>> _scrollState() {
  final states = <Map<String, num>>[];
  void visit(Element element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      final position = (element.state as ScrollableState).position;
      states.add({
        'pixels': position.pixels,
        'max': position.maxScrollExtent,
        'viewport': position.viewportDimension,
      });
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return states;
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 650));
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _until(bool Function() predicate) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Owned native task did not reach the expected phase.');
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

Element? _textElement(String text) {
  Element? found;
  void visit(Element element) {
    final widget = element.widget;
    if (found == null &&
        widget is Text &&
        (widget.data?.contains(text) ?? false)) {
      found = element;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<void> _click(
  Directory root,
  String key, {
  bool requireUnchecked = false,
}) async {
  await _settle();
  var element = _element(key);
  for (var attempt = 0; element == null && attempt < 20; attempt++) {
    void scroll(Element candidate) {
      if (candidate is StatefulElement && candidate.state is ScrollableState) {
        final position = (candidate.state as ScrollableState).position;
        if (position.hasContentDimensions && position.maxScrollExtent > 0) {
          final next = position.pixels + position.viewportDimension * .7;
          position.jumpTo(next > position.maxScrollExtent ? 0 : next);
        }
      }
      candidate.visitChildren(scroll);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(scroll);
    await _settle();
    element = _element(key);
  }
  if (element == null) throw StateError('Missing native action $key.');
  if (requireUnchecked) {
    final widget = element.widget;
    _require(
      widget is Checkbox && widget.value == false,
      'Restoring an ignored result restored its selection.',
    );
  }
  await Scrollable.ensureVisible(element, alignment: .5);
  await _settle();
  if (_callbackAutomation) {
    final widget = element.widget;
    if (widget is ButtonStyleButton && widget.onPressed != null) {
      widget.onPressed!();
    } else if (widget is IconButton && widget.onPressed != null) {
      widget.onPressed!();
    } else if (widget is ChoiceChip && widget.onSelected != null) {
      widget.onSelected!(true);
    } else if (widget is Checkbox &&
        widget.onChanged != null &&
        key == 'ai-request-rules') {
      widget.onChanged!(!(widget.value ?? false));
    } else if (widget is Checkbox && widget.onChanged != null) {
      Element? tile;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is ExpansionTile) {
          tile = ancestor;
          return false;
        }
        return true;
      });
      ExpansibleController? controller;
      void findController(Element candidate) {
        final candidateWidget = candidate.widget;
        if (candidateWidget is Expansible) {
          controller = candidateWidget.controller;
          return;
        }
        candidate.visitChildren(findController);
      }

      tile?.visitChildren(findController);
      _require(controller != null, 'Change preview controller is missing.');
      controller!.expand();
      await _phase(root, 'expanded-change-light-1280');
      _require(controller!.isExpanded, 'Change preview did not expand.');
      widget.onChanged!(!(widget.value ?? false));
    } else {
      throw StateError('Action is disabled or not supported: $key.');
    }
    await _settle();
    return;
  }
  final render = element.findRenderObject()! as RenderBox;
  final position = render.localToGlobal(render.size.center(Offset.zero));
  final ratio = View.of(element).devicePixelRatio;
  await File('${root.path}/click-$key.ready').writeAsString(
    jsonEncode({
      'x': position.dx * ratio,
      'y': position.dy * ratio,
      'devicePixelRatio': ratio,
    }),
  );
  await _until(() => File('${root.path}/click-$key.ack').existsSync());
  await File('${root.path}/click-$key.ack').delete();
  await File('${root.path}/click-$key.ready').delete();
}

bool get _callbackAutomation =>
    Platform.environment['BOOKLOOM_NATIVE_CALLBACK_AUTOMATION'] == '1';

bool get _auditHandoff =>
    Platform.environment['BOOKLOOM_NATIVE_AUDIT_HANDOFF'] == '1';

bool get _advertisementSelection =>
    _jointRules || Platform.environment['BOOKLOOM_NATIVE_AD_SELECTION'] == '1';

bool get _jointRules =>
    Platform.environment['BOOKLOOM_NATIVE_JOINT_RULES'] == '1';

bool get _splitImpact =>
    Platform.environment['BOOKLOOM_NATIVE_SPLIT_IMPACT'] == '1';

Future<void> _expandTile(String key) async {
  Element? tile;
  for (var attempt = 0; attempt < 20 && tile == null; attempt++) {
    tile = _element(key);
    if (tile != null) break;
    void scroll(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (position.hasContentDimensions) {
          final next = position.pixels + 500;
          position.jumpTo(
            next.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
        }
      }
      element.visitChildren(scroll);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(scroll);
    await _settle();
  }
  if (tile == null) throw StateError('Missing joint rule tile $key.');
  await Scrollable.ensureVisible(tile, alignment: .5);
  ExpansibleController? controller;
  void findController(Element element) {
    if (element.widget is Expansible) {
      controller = (element.widget as Expansible).controller;
      return;
    }
    element.visitChildren(findController);
  }

  tile.visitChildren(findController);
  _require(controller != null, 'Joint rule expansion controller missing.');
  controller!.expand();
  await _settle();
}

Future<void> _phase(Directory root, String phase) async {
  if (phase.contains('dark') || phase.contains('light')) {
    final expectedTheme = phase.contains('dark')
        ? AppTheme.dark()
        : AppTheme.light();
    var settled = false;
    for (var frame = 0; frame < 150; frame++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final panel =
          _element('native-ai-panel') ?? _element('native-workbench-panel');
      if (panel != null &&
          Theme.of(panel).textTheme.bodyMedium?.color ==
              expectedTheme.textTheme.bodyMedium?.color &&
          Theme.of(panel).colorScheme.surface ==
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
  };
  final ready = File('${root.path}/phase-$phase.ready');
  final acknowledgement = File('${root.path}/phase-$phase.ack');
  if (await acknowledgement.exists()) await acknowledgement.delete();
  await ready.writeAsString('ready');
  await _until(acknowledgement.existsSync);
  await acknowledgement.delete();
  await ready.delete();
}
