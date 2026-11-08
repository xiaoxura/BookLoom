import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../app/ai_providers.dart';
import '../../../app/rule_providers.dart';
import '../../../app/window/window_controls.dart';
import '../../../app/workbench_providers.dart';
import '../../../core/editing/proofreading_rule.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/model/block.dart';
import '../../../core/model/chapter.dart';
import '../../../core/platform/files.dart';
import '../../../design/components/app_page.dart';
import '../../../design/components/empty_state.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../l10n/app_localizations.dart';
import '../application/ai_advertisement_request.dart';
import '../application/ai_rule_creation_task.dart';
import '../application/book_assets.dart';
import '../application/editor_session.dart';
import 'ai_proofreading_panel.dart';
import 'ai_rule_creation_panel.dart';
import 'book_settings_panel.dart';
import 'chapter_management_dialogs.dart';
import 'proofreading_panel.dart';
import 'reparse_panel.dart';
import 'rule_workbench_panel.dart';

typedef ExportBook = Future<SaveOutcome> Function(String bookId);
typedef ShareBook = Future<void> Function(String bookId);
typedef CloseGuardRegistrar = VoidCallback Function(
  Future<void> Function() beforeClose, {
  void Function(Object)? onError,
});

/// The pushed, native editing workspace. The router supplies [onExport] once
/// an export implementation is available; a missing exporter is never success.
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({
    super.key,
    required this.bookId,
    this.onExport,
    this.onShare,
    this.closeGuardRegistrar,
  });

  final String bookId;
  final ExportBook? onExport;

  /// Opens the platform share panel after the current visible edit is saved.
  /// The callback owns result messaging; opening a panel is not delivery.
  final ShareBook? onShare;

  /// Allows a widget test to request the same guarded close as native chrome.
  final CloseGuardRegistrar? closeGuardRegistrar;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage>
    with WidgetsBindingObserver {
  late final EditorSession _session;
  late final BookAssets _assets;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _treeSearch = TextEditingController();
  final _treeSearchFocus = FocusNode();
  final _collapsedVolumes = <String>{};
  final _bodyScroll = ScrollController();
  final _locatedRow = GlobalKey();
  String? _locatedBlockId;
  bool _loading = true;
  bool _leaving = false;
  bool _allowPop = false;
  bool _drawerOpen = false;
  bool _composing = false;
  bool _disposing = false;
  bool _assetCleanupNeeded = false;
  String? _observedBookId;
  String? _observedCoverId;
  String? _observedFontId;
  String? _loadError;
  VoidCallback? _detachCloseGuard;
  Future<void>? _opening;
  VoidCallback? _finishParagraphComposition;
  ({String blockId, String text})? _pendingComposedDraft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_changed);
    _session = EditorSession(
      repository: ref.read(bookRepositoryProvider),
      jobs: ref.read(backgroundJobsProvider),
    );
    _assets = BookAssets(
      repository: ref.read(bookRepositoryProvider),
      files: ref.read(fileServiceProvider),
    );
    _session.addListener(_changed);
    _opening = _open();
  }

  Future<void> _open() async {
    try {
      await _session.open(widget.bookId);
      if (mounted) {
        _detachCloseGuard =
            (widget.closeGuardRegistrar ?? WindowControls.guardClose)(
              _flushForClose,
              onError: (_) {
                if (mounted) {
                  _notice(AppLocalizations.of(context).editorSaveFailedStay);
                }
              },
            );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _loadError = AppLocalizations.of(context).editorOpenFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    final book = _session.book;
    if (book != null) {
      if (_observedBookId == book.id) {
        if (_observedCoverId != book.coverAssetId ||
            _observedFontId != book.layout.embeddedFontAssetId) {
          _assetCleanupNeeded = true;
        }
      }
      _observedBookId = book.id;
      _observedCoverId = book.coverAssetId;
      _observedFontId = book.layout.embeddedFontAssetId;
    }
    if (mounted && !_disposing) setState(() {});
  }

  void _setComposing(bool composing, VoidCallback finish) {
    _finishParagraphComposition = composing ? finish : null;
    if (_disposing) {
      _composing = composing;
    } else if (mounted && _composing != composing) {
      setState(() => _composing = composing);
    }
  }

  void _captureComposedDraft(String blockId, String? text) {
    if (text != null) {
      _pendingComposedDraft = (blockId: blockId, text: text);
    } else if (_pendingComposedDraft?.blockId == blockId) {
      _pendingComposedDraft = null;
    }
  }

  void _paragraphDisposed(String blockId) {
    if (_pendingComposedDraft?.blockId == blockId) {
      // An externally removed paragraph must not leave a callback to its
      // already disposed TextEditingController.
      _finishParagraphComposition = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposing) _commitPendingDraft();
      });
    }
  }

  void _commitPendingDraft() {
    final draft = _pendingComposedDraft;
    if (draft == null) return;
    _pendingComposedDraft = null;
    _finishParagraphComposition = null;
    _composing = false;
    _session.editBlockText(draft.blockId, draft.text);
    if (mounted && !_disposing) setState(() {});
  }

  void _commitVisibleComposition() => _finishParagraphComposition?.call();

  Future<void> _flushForClose() async {
    if (_composing) {
      // A native close or lifecycle pause need not produce a final onChanged.
      // Keep the text currently visible in the control before flushing.
      FocusManager.instance.primaryFocus?.unfocus();
      _commitVisibleComposition();
      _commitPendingDraft();
    }
    await _session.flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_flushForClose().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _disposing = true;
    // Flutter unmounts descendants first, so their controllers are already
    // gone here. A route reset still preserves the last visible IME draft.
    _commitPendingDraft();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_changed);
    _detachCloseGuard?.call();
    _treeSearch.dispose();
    _treeSearchFocus.dispose();
    _bodyScroll.dispose();
    _session.removeListener(_changed);
    // A navigation guard flushes before normal exits. An external route reset
    // still makes a best effort to save before releasing the session.
    final bookId = _session.book?.id;
    if (_session.dirty) {
      unawaited(
        () async {
          var saved = false;
          try {
            await _session.flush();
            saved = true;
          } on Object {
            // The route was already removed; never clean resources while a
            // failed save may still reference them only in memory.
          } finally {
            _session.dispose();
          }
          if (saved && _assetCleanupNeeded && bookId != null) {
            await _cleanupAssets(bookId);
          }
        }().catchError((Object _) {}),
      );
    } else {
      _session.dispose();
      if (_assetCleanupNeeded && bookId != null) {
        unawaited(_cleanupAssets(bookId));
      }
    }
    super.dispose();
  }

  Future<void> _cleanupAssets(String bookId) async {
    try {
      await _assets.cleanupUnreferenced(bookId);
    } on Object {
      // A later editor close can retry this optional orphan cleanup.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session.book != null) {
      ref.watch(aiProofreadingTaskProvider(_session).select((task) => null));
      ref.watch(ruleWorkbenchTaskProvider(_session).select((task) => null));
    }
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 960;
    final wide = width >= 1280;
    final compactBody = width < AppLayout.editorCompactBreakpoint;
    return PopScope(
      canPop: _allowPop || _drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_leaving) {
          if (_drawerOpen) {
            _scaffoldKey.currentState?.closeDrawer();
          } else {
            unawaited(_leave());
          }
        }
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            unawaited(_retrySave());
          },
          const SingleActivator(
            LogicalKeyboardKey.keyE,
            control: true,
            shift: true,
          ): () {
            unawaited(_export());
          },
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.transparent,
            onDrawerChanged: (open) => setState(() => _drawerOpen = open),
            drawer: mobile
                ? Drawer(child: SafeArea(child: _chapterPane(l10n)))
                : null,
            body: AppPage(
              scrollable: false,
              maxContentWidth: double.infinity,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? Center(
                      child: EmptyState(
                        title: _loadError!,
                        actions: [
                          OutlinedButton(
                            onPressed: _leave,
                            child: Text(l10n.editorBack),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _toolbar(l10n, mobile),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: Row(
                            children: [
                              if (!mobile) ...[
                                SizedBox(width: 232, child: _chapterPane(l10n)),
                                const SizedBox(width: AppSpacing.md),
                              ],
                              Expanded(child: _bodyPane(l10n, compactBody)),
                              if (wide) ...[
                                const SizedBox(width: AppSpacing.md),
                                SizedBox(width: 320, child: _settingsPane()),
                              ],
                            ],
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

  Widget _toolbar(AppLocalizations l10n, bool mobile) {
    final book = _session.book!;
    final colors = context.colors;
    final compactActions = MediaQuery.sizeOf(context).width < 420;
    final platform = Theme.of(context).platform;
    final phone =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (!phone)
              IconButton(
                tooltip: l10n.editorBack,
                onPressed: _leaving ? null : _leave,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.meta.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    _saveLabel(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _session.saveError == null
                          ? colors.inkMuted
                          : colors.danger,
                    ),
                  ),
                ],
              ),
            ),
            if (mobile)
              IconButton(
                tooltip: l10n.editorChapters,
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.toc_rounded),
              ),
            if (compactActions)
              PopupMenuButton<String>(
                tooltip: l10n.editorWorkbenchMoreActions,
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (value) {
                  switch (value) {
                    case 'settings':
                      _showMetadata(l10n);
                    case 'proofreading':
                      _showProofreading();
                    case 'reparse':
                      _showReparse();
                    case 'share':
                      unawaited(_share());
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'settings',
                    enabled: !_composing && !_leaving,
                    child: Text(l10n.editorBookInfo),
                  ),
                  PopupMenuItem(
                    value: 'proofreading',
                    enabled: !_composing && !_leaving,
                    child: Text(l10n.editorWorkbenchTools),
                  ),
                  PopupMenuItem(
                    value: 'reparse',
                    enabled: !_composing && !_leaving,
                    child: Text(l10n.editorWorkbenchReparse),
                  ),
                  if (Platform.isAndroid && widget.onShare != null)
                    PopupMenuItem(
                      value: 'share',
                      enabled: !_leaving,
                      child: Text(l10n.editorWorkbenchShare),
                    ),
                ],
              ),
            if (!compactActions && MediaQuery.sizeOf(context).width < 1280)
              IconButton(
                tooltip: l10n.editorBookInfo,
                onPressed: _composing ? null : () => _showMetadata(l10n),
                icon: const Icon(Icons.tune_rounded),
              ),
            if (!compactActions) ...[
              IconButton(
                tooltip: l10n.editorWorkbenchTools,
                onPressed: _composing ? null : _showProofreading,
                icon: const Icon(Icons.fact_check_outlined),
              ),
              IconButton(
                tooltip: l10n.editorWorkbenchReparse,
                onPressed: _composing ? null : _showReparse,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
            IconButton(
              tooltip: l10n.editorExport,
              onPressed: widget.onExport == null || _leaving ? null : _export,
              icon: const Icon(Icons.ios_share_outlined),
            ),
            if (!compactActions && Platform.isAndroid && widget.onShare != null)
              IconButton(
                tooltip: l10n.editorWorkbenchShare,
                onPressed: _leaving ? null : _share,
                icon: const Icon(Icons.share_outlined),
              ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.editorUndo,
                    onPressed: (_session.canUndo || _composing) && !_leaving
                        ? () => _run(() => _undoRedo(redo: false))
                        : null,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  IconButton(
                    tooltip: l10n.editorRedo,
                    onPressed: _session.canRedo && !_composing && !_leaving
                        ? () => _run(() => _undoRedo(redo: true))
                        : null,
                    icon: const Icon(Icons.redo_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_session.saveError != null)
          TextButton(onPressed: _retrySave, child: Text(l10n.commonRetry)),
        if (_session.saveError case final failure?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              [
                failure.message,
                if (failure.hint != null) failure.hint!,
              ].join(' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.danger),
            ),
          ),
      ],
    );
  }

  String _saveLabel(AppLocalizations l10n) {
    if (_session.saveError != null) return l10n.editorSaveFailed;
    if (_session.isSaving) return l10n.editorSaving;
    if (_session.dirty) return l10n.editorUnsaved;
    return l10n.editorSaved;
  }

  bool get _textInputFocused {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<void> _undoRedo({required bool redo}) async {
    _commitVisibleComposition();
    _commitPendingDraft();
    FocusManager.instance.primaryFocus?.unfocus();
    if (redo ? !_session.canRedo : !_session.canUndo) return;
    if (redo) {
      await _session.redo();
    } else {
      await _session.undo();
    }
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      _notice(redo ? l10n.editorRedoDone : l10n.editorUndoDone);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        !_composing &&
        _scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        !_composing &&
        _treeSearchFocus.hasFocus) {
      _treeSearchFocus.unfocus();
      _treeSearch.clear();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (!_canNavigateByKeyboard) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        if (keyboard.isShiftPressed) {
          _redoShortcut();
        } else {
          _undoShortcut();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _redoShortcut();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (keyboard.isAltPressed || keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.arrowDown) {
      _nextChapter();
    } else if (key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.arrowUp) {
      _previousChapter();
    } else if (key == LogicalKeyboardKey.slash) {
      _focusChapterSearch();
    } else if (key == LogicalKeyboardKey.escape) {
      _escape();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool get _canNavigateByKeyboard =>
      !_loading && !_leaving && !_composing && !_textInputFocused;

  void _nextChapter() => _stepChapter(1);
  void _previousChapter() => _stepChapter(-1);
  void _undoShortcut() {
    if (!_canNavigateByKeyboard || !_session.canUndo) return;
    unawaited(_run(_session.undo));
  }

  void _redoShortcut() {
    if (!_canNavigateByKeyboard || !_session.canRedo) return;
    unawaited(_run(_session.redo));
  }

  void _stepChapter(int offset) {
    if (!_canNavigateByKeyboard) return;
    final chapters =
        _session.book?.chapters
            .where((chapter) => !chapter.isVolume)
            .toList() ??
        const <Chapter>[];
    if (chapters.isEmpty) return;
    final at = chapters.indexWhere(
      (item) => item.id == _session.activeChapterId,
    );
    final next = (at + offset).clamp(0, chapters.length - 1);
    if (next == at) return;
    unawaited(_selectChapter(chapters[next].id));
  }

  void _focusChapterSearch() {
    if (!_canNavigateByKeyboard) return;
    if (_scaffoldKey.currentState?.hasDrawer == true &&
        MediaQuery.sizeOf(context).width < 960) {
      _scaffoldKey.currentState?.openDrawer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _treeSearchFocus.requestFocus();
      });
    } else {
      _treeSearchFocus.requestFocus();
    }
  }

  void _escape() {
    if (_composing || _textInputFocused) return;
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    if (_treeSearch.text.isNotEmpty) {
      _treeSearch.clear();
      setState(() {});
    }
  }

  List<Chapter> _matchingChapters(List<Chapter> chapters, String query) {
    if (query.isEmpty) return chapters;
    var chapterNumber = 0;
    final matched = <String>{};
    for (final chapter in chapters) {
      if (!chapter.isVolume) chapterNumber++;
      if (chapter.title.toLowerCase().contains(query) ||
          (!chapter.isVolume && chapterNumber.toString() == query)) {
        matched.add(chapter.id);
        if (chapter.parentId != null) matched.add(chapter.parentId!);
        if (chapter.isVolume) {
          matched.addAll(
            chapters
                .where((child) => child.parentId == chapter.id)
                .map((child) => child.id),
          );
        }
      }
    }
    return chapters.where((chapter) => matched.contains(chapter.id)).toList();
  }

  void _chapterSearchChanged(String value) {
    setState(() {
      final query = value.trim().toLowerCase();
      if (query.isNotEmpty) {
        final chapters = _session.book?.chapters ?? const <Chapter>[];
        _collapsedVolumes.removeAll(
          _matchingChapters(
            chapters,
            query,
          ).where((chapter) => chapter.isVolume).map((chapter) => chapter.id),
        );
      }
    });
  }

  Widget _chapterPane(AppLocalizations l10n) {
    final colors = context.colors;
    final chapters = _session.book?.chapters ?? const <Chapter>[];
    final firstChapterId = chapters
        .where((chapter) => !chapter.isVolume)
        .firstOrNull
        ?.id;
    final query = _treeSearch.text.trim().toLowerCase();
    final shown = _matchingChapters(chapters, query)
        .where(
          (chapter) =>
              chapter.isVolume || !_collapsedVolumes.contains(chapter.parentId),
        )
        .toList();
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.editorChapters,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.editorChapterActions,
                  icon: const Icon(Icons.add_rounded),
                  enabled: !_composing && !_leaving,
                  onSelected: (action) {
                    switch (action) {
                      case 'volume':
                        unawaited(_newVolume());
                      case 'chapter':
                        unawaited(_newChapter());
                      case 'move':
                        unawaited(_moveChapters());
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'volume',
                      child: Text(l10n.editorNewVolume),
                    ),
                    PopupMenuItem(
                      value: 'chapter',
                      child: Text(l10n.editorNewChapter),
                    ),
                    PopupMenuItem(
                      value: 'move',
                      enabled: chapters.any((chapter) => !chapter.isVolume),
                      child: Text(l10n.editorMoveChapters),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _treeSearch,
              focusNode: _treeSearchFocus,
              onChanged: _chapterSearchChanged,
              onTapOutside: (_) => _treeSearchFocus.unfocus(),
              decoration: InputDecoration(
                hintText: l10n.editorSearchChapters,
                prefixIcon: const Icon(Icons.search_outlined),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text(l10n.editorNoChapters))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, index) {
                      final chapter = shown[index];
                      final expanded = !_collapsedVolumes.contains(chapter.id);
                      final selected = chapter.id == _session.activeChapterId;
                      return Semantics(
                        expanded: chapter.isVolume ? expanded : null,
                        child: ListTile(
                          dense: true,
                          minLeadingWidth: 18,
                          horizontalTitleGap: AppSpacing.xs,
                          contentPadding: EdgeInsets.only(
                            left: chapter.isVolume
                                ? AppSpacing.md
                                : AppSpacing.xl,
                            right: AppSpacing.xs,
                          ),
                          selected: selected,
                          selectedTileColor: colors.accentSoft,
                          selectedColor: colors.accent,
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  chapter.title,
                                  style: selected
                                      ? const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        )
                                      : null,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (chapter.isVolume) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Icon(
                                  expanded
                                      ? Icons.expand_more_rounded
                                      : Icons.chevron_right_rounded,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                          leading: Icon(
                            chapter.isVolume
                                ? Icons.folder_outlined
                                : Icons.article_outlined,
                            size: 18,
                          ),
                          onTap: chapter.isVolume
                              ? () => setState(() {
                                  if (expanded) {
                                    _collapsedVolumes.add(chapter.id);
                                  } else {
                                    _collapsedVolumes.remove(chapter.id);
                                  }
                                })
                              : _composing
                              ? null
                              : () => _selectChapter(chapter.id),
                          trailing: PopupMenuButton<String>(
                            tooltip: l10n.editorChapterActions,
                            onSelected: (action) =>
                                _chapterAction(chapter, action),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text(
                                  chapter.isVolume
                                      ? l10n.editorRenameVolume
                                      : l10n.editorRenameChapter,
                                ),
                              ),
                              if (!chapter.isVolume &&
                                  chapter.id != firstChapterId)
                                PopupMenuItem(
                                  value: 'merge',
                                  child: Text(l10n.editorMergePrevious),
                                ),
                              if (chapter.isVolume) ...[
                                PopupMenuItem(
                                  value: 'newChapter',
                                  child: Text(l10n.editorNewChapter),
                                ),
                                PopupMenuItem(
                                  value: 'move',
                                  child: Text(l10n.editorMoveChapters),
                                ),
                              ],
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  chapter.isVolume
                                      ? l10n.editorDeleteVolume
                                      : l10n.editorDeleteChapter,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _bodyPane(AppLocalizations l10n, bool compact) {
    final colors = context.colors;
    final chapter = _session.activeChapter;
    final locatedBlockId = _locatedBlockId;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: chapter == null
          ? Center(child: EmptyState(title: l10n.editorNoChapters))
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(
                    compact ? AppSpacing.md : AppSpacing.lg,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      chapter.title,
                      style: compact
                          ? Theme.of(context).textTheme.headlineSmall
                          : Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ),
                Divider(height: 1, color: colors.hairline),
                if (locatedBlockId != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location_outlined, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(_locationLabel(chapter))),
                        if (chapter.blocks.any(
                          (block) =>
                              block.id == locatedBlockId && block is TextBlock,
                        ))
                          PopupMenuButton<String>(
                            tooltip: l10n.editorParagraphActions,
                            onSelected: (action) => _paragraphAction(
                              chapter.id,
                              locatedBlockId,
                              action,
                            ),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'split',
                                child: Text(l10n.editorSplitHere),
                              ),
                              PopupMenuItem(
                                value: 'title',
                                child: Text(l10n.editorSetAsTitle),
                              ),
                            ],
                          ),
                        IconButton(
                          tooltip: l10n.editorWorkbenchCloseLocation,
                          onPressed: () =>
                              setState(() => _locatedBlockId = null),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: chapter.blocks.isEmpty
                      ? Center(child: Text(l10n.editorEmptyChapter))
                      : ListView.builder(
                          key: ValueKey(chapter.id),
                          controller: _bodyScroll,
                          padding: EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            compact ? AppSpacing.md : AppSpacing.lg,
                            AppSpacing.lg,
                            compact ? AppSpacing.xl : AppSpacing.xxxl,
                          ),
                          itemCount: chapter.blocks.length,
                          itemBuilder: (_, index) => KeyedSubtree(
                            key: chapter.blocks[index].id == locatedBlockId
                                ? _locatedRow
                                : ValueKey(chapter.blocks[index].id),
                            child: _blockRow(
                              chapter,
                              chapter.blocks[index],
                              l10n,
                              compact,
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _blockRow(
    Chapter chapter,
    Block block,
    AppLocalizations l10n,
    bool compact,
  ) {
    if (block is DividerBlock) return const Divider();
    if (block is ImageBlock) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(l10n.editorImageBlock),
      );
    }
    final text = block.plainText;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? AppSpacing.md : AppSpacing.lg),
      child: block is! TextBlock
          ? SelectableText(
              text,
              style: AppTypography.reading(context.colors, compact: compact),
            )
          : _ParagraphField(
              key: ValueKey(block.id),
              text: text,
              compact: compact,
              onTextChanged: (value) => _session.editBlockText(block.id, value),
              onComposingChanged: _setComposing,
              onComposedDraftChanged: (value) =>
                  _captureComposedDraft(block.id, value),
              onDisposed: () => _paragraphDisposed(block.id),
              onParagraphAction: (action) =>
                  unawaited(_paragraphAction(chapter.id, block.id, action)),
              onCreateRule: (start, end, original, kind) => _showRuleCreation(
                AiRuleSelection(
                  chapterId: chapter.id,
                  blockId: block.id,
                  startUtf16: start,
                  endUtf16: end,
                  original: original,
                ),
                kind,
              ),
              onAnalyzeAdvertisement: (start, end, original) =>
                  _showAdvertisementSelection(
                    chapter.id,
                    block.id,
                    start,
                    end,
                    original,
                  ),
            ),
    );
  }

  Widget _settingsPane() => BookSettingsPanel(
    session: _session,
    repository: ref.read(bookRepositoryProvider),
    files: ref.read(fileServiceProvider),
  );

  void _showMetadata(AppLocalizations l10n) {
    _showWorkbenchPanel((_) => _settingsPane());
  }

  void _showProofreading() {
    if (_composing) return;
    _showWorkbenchPanel(
      (dialog) => ProofreadingPanel(
        session: _session,
        onUseRule: (rule) => _openJointRuleWorkbench(rule, dialog),
        onLocate: (chapterId, blockId) async {
          Navigator.of(dialog).pop();
          await _locate(chapterId, blockId);
        },
      ),
    );
  }

  void _showRuleCreation(AiRuleSelection selection, ProofreadingRuleKind kind) {
    if (_composing) return;
    _showWorkbenchPanel(
      (dialog) => AiRuleCreationPanel(
        session: _session,
        selection: selection,
        initialKind: kind,
        onUseRule: (rule) {
          final sessionId = _session.sessionId;
          final saveSeq = _session.saveSeq;
          Navigator.of(dialog).pop();
          _showWorkbenchPanel(
            (workbench) => RuleWorkbenchPanel(
              session: _session,
              initialRule: rule,
              initialSessionId: sessionId,
              initialSaveSeq: saveSeq,
              onLocate: (chapterId, blockId) async {
                Navigator.of(workbench).pop();
                await _locate(chapterId, blockId);
              },
              onAnalyzeAdvertisement: (request) async {
                Navigator.of(workbench).pop();
                _openAdvertisementPanel(request);
              },
            ),
          );
        },
      ),
    );
  }

  void _showAdvertisementSelection(
    String chapterId,
    String blockId,
    int startUtf16,
    int endUtf16,
    String original,
  ) {
    if (_composing) return;
    final book = _session.book;
    final sessionId = _session.sessionId;
    if (book == null || sessionId == null) return;
    try {
      final request = AiAdvertisementRequest.fromSelection(
        book: book,
        sessionId: sessionId,
        sessionRevision: _session.saveSeq,
        chapterId: chapterId,
        blockId: blockId,
        startUtf16: startUtf16,
        endUtf16: endUtf16,
        original: original,
      );
      _openAdvertisementPanel(request);
    } on Object {
      _notice(AppLocalizations.of(context).aiAdvertisementSelectionExpired);
    }
  }

  void _openAdvertisementPanel(AiAdvertisementRequest request) {
    if (!mounted) return;
    _showWorkbenchPanel(
      (dialog) => AiProofreadingPanel(
        session: _session,
        initialAdvertisementSelection: request,
        onUseRule: (rule) => _openJointRuleWorkbench(rule, dialog),
        onLocate: (chapterId, blockId) async {
          Navigator.of(dialog).pop();
          await _locate(chapterId, blockId);
        },
      ),
    );
  }

  void _openJointRuleWorkbench(ProofreadingRule rule, BuildContext source) {
    if (!mounted) return;
    final sessionId = _session.sessionId;
    final saveSeq = _session.saveSeq;
    _showWorkbenchPanel(
      (workbench) => RuleWorkbenchPanel(
        session: _session,
        initialRule: rule,
        initialSessionId: sessionId,
        initialSaveSeq: saveSeq,
        onLocate: (chapterId, blockId) async {
          Navigator.of(workbench).pop();
          if (source.mounted) Navigator.of(source).pop();
          await _locate(chapterId, blockId);
        },
        onAnalyzeAdvertisement: (request) async {
          Navigator.of(workbench).pop();
          _openAdvertisementPanel(request);
        },
      ),
    );
  }

  void _showReparse() {
    if (_composing) return;
    _showWorkbenchPanel(
      (_) => ReparsePanel(
        session: _session,
        service: ref.read(importServiceProvider),
        files: ref.read(fileServiceProvider),
      ),
    );
  }

  void _showWorkbenchPanel(WidgetBuilder builder) {
    showDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.workbenchDialogMaxWidth,
          ),
          child: SizedBox(
            width: double.infinity,
            height:
                MediaQuery.sizeOf(dialog).height *
                AppLayout.workbenchDialogHeightFraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: CloseButton(
                    onPressed: () => Navigator.of(dialog).pop(),
                  ),
                ),
                Expanded(child: builder(dialog)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _locationLabel(Chapter chapter) {
    final l10n = AppLocalizations.of(context);
    final index = chapter.blocks.indexWhere(
      (block) => block.id == _locatedBlockId,
    );
    if (index < 0) return l10n.editorWorkbenchLocationChanged;
    final text = chapter.blocks[index].plainText.trim();
    return l10n.editorWorkbenchLocationAt(
      index + 1,
      text.length > 70 ? '${text.substring(0, 70)}…' : text,
    );
  }

  Future<void> _locate(String chapterId, String? blockId) async {
    await _session.selectChapter(chapterId);
    if (!mounted) return;
    _treeSearch.clear();
    setState(() => _locatedBlockId = blockId);
    if (blockId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_bodyScroll.hasClients) return;
      final chapter = _session.activeChapter;
      final index =
          chapter?.blocks.indexWhere((block) => block.id == blockId) ?? -1;
      if (index < 0) return;
      _bodyScroll.jumpTo(
        (index * 72.0).clamp(0, _bodyScroll.position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _locatedRow.currentContext;
        if (row != null) {
          unawaited(
            Scrollable.ensureVisible(
              row,
              duration: const Duration(milliseconds: 180),
            ),
          );
        }
      });
    });
  }

  Future<void> _selectChapter(String id) async {
    if (_composing) return;
    if (_session.book?.chapters.any(
          (chapter) => chapter.id == id && chapter.isVolume,
        ) ==
        true) {
      return;
    }
    try {
      await _session.selectChapter(id);
      if (mounted) {
        _locatedBlockId = null;
        _scaffoldKey.currentState?.closeDrawer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _bodyScroll.hasClients) _bodyScroll.jumpTo(0);
        });
      }
    } on Object catch (error) {
      if (mounted) {
        _noticeFailure(
          error,
          AppLocalizations.of(context).editorSaveFailedStay,
        );
      }
    }
  }

  Future<void> _newVolume() async {
    if (_composing || _leaving) return;
    final title = await showNewVolumeDialog(context);
    if (title == null || !mounted) return;
    await _run(() async {
      final id = await _session.createVolume(title);
      if (mounted) {
        setState(() {
          _collapsedVolumes.remove(id);
          _treeSearch.clear();
        });
      }
    });
  }

  Future<void> _newChapter({String? volumeId}) async {
    if (_composing || _leaving) return;
    final request = await showNewChapterDialog(
      context,
      chapters: _session.book!.chapters,
      activeChapterId: _session.activeChapterId,
      initialVolumeId: volumeId,
    );
    if (request == null || !mounted) return;
    await _run(() async {
      await _session.createChapter(
        request.title,
        volumeId: request.volumeId,
        beforeChapterId: request.beforeChapterId,
        afterChapterId: request.afterChapterId,
      );
      if (!mounted) return;
      setState(() {
        _locatedBlockId = null;
        _treeSearch.clear();
        _collapsedVolumes.remove(request.volumeId);
      });
      _scaffoldKey.currentState?.closeDrawer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _bodyScroll.hasClients) _bodyScroll.jumpTo(0);
      });
    });
  }

  Future<void> _moveChapters({String? volumeId}) async {
    if (_composing || _leaving) return;
    final request = await showMoveChaptersDialog(
      context,
      chapters: _session.book!.chapters,
      initialVolumeId: volumeId,
    );
    if (request == null || !mounted) return;
    await _run(() async {
      await _session.moveChaptersToVolume(
        request.chapterIds,
        volumeId: request.volumeId,
      );
      if (mounted) {
        setState(() {
          _treeSearch.clear();
          _collapsedVolumes.remove(request.volumeId);
        });
      }
    });
  }

  Future<void> _chapterAction(Chapter chapter, String action) async {
    if (_composing) return;
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case 'rename':
        var draft = chapter.title;
        final title = await showDialog<String>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(
              chapter.isVolume
                  ? l10n.editorRenameVolume
                  : l10n.editorRenameChapter,
            ),
            content: TextFormField(
              initialValue: chapter.title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: chapter.isVolume
                    ? l10n.editorVolumeTitle
                    : l10n.editorChapterTitle,
              ),
              onChanged: (value) => draft = value,
              onFieldSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(dialog, value.trim());
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  if (draft.trim().isNotEmpty) {
                    Navigator.pop(dialog, draft.trim());
                  }
                },
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        );
        if (title != null && mounted) {
          _runSync(() => _session.editChapterTitle(chapter.id, title));
        }
        return;
      case 'merge':
        await _run(() => _session.mergeWithPrevious(chapter.id));
        return;
      case 'newChapter':
        await _newChapter(volumeId: chapter.id);
        return;
      case 'move':
        await _moveChapters(volumeId: chapter.id);
        return;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(
              chapter.isVolume
                  ? l10n.editorDeleteVolume
                  : l10n.editorDeleteChapter,
            ),
            content: Text(
              chapter.isVolume
                  ? l10n.editorWorkbenchDeleteVolumeConfirm(chapter.title)
                  : l10n.editorDeleteChapterConfirm(chapter.title),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(
                  chapter.isVolume
                      ? l10n.editorDeleteVolume
                      : l10n.editorDeleteChapter,
                ),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _run(() => _session.deleteChapter(chapter.id));
        }
        return;
    }
  }

  Future<void> _paragraphAction(
    String chapterId,
    String blockId,
    String action,
  ) async {
    _commitVisibleComposition();
    _commitPendingDraft();
    FocusManager.instance.primaryFocus?.unfocus();
    if (action == 'split') {
      await _run(() async {
        await _session.splitAtParagraph(chapterId, blockId);
      });
    }
    if (action == 'title') {
      await _run(() => _session.setParagraphAsTitle(chapterId, blockId));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        _noticeFailure(error, AppLocalizations.of(context).editorActionFailed);
      }
    }
  }

  void _runSync(VoidCallback action) {
    try {
      action();
    } on Object catch (error) {
      if (mounted) {
        _noticeFailure(error, AppLocalizations.of(context).editorActionFailed);
      }
    }
  }

  Future<void> _retrySave() async {
    try {
      await _flushForClose();
      if (mounted) ref.invalidate(libraryBooksProvider);
    } on Object {
      if (mounted) _notice(AppLocalizations.of(context).editorSaveFailed);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      if (_loading) await _opening;
      if (!mounted) return;
      if (_session.book != null) {
        await _flushForClose();
        if (!mounted) return;
        ref.invalidate(libraryBooksProvider);
      }
      _popAfterSave();
    } on Object {
      if (mounted) _notice(AppLocalizations.of(context).editorSaveFailedStay);
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  void _popAfterSave() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  Future<void> _export() async {
    final export = widget.onExport;
    if (export == null) return;
    try {
      await _flushForClose();
      if (!mounted) return;
      final result = await export(widget.bookId);
      if (!mounted) return;
      if (result is SaveSaved) {
        _notice(AppLocalizations.of(context).editorExportSaved);
      }
    } on Object {
      if (mounted) {
        _notice(
          _session.saveError == null
              ? AppLocalizations.of(context).editorExportFailed
              : AppLocalizations.of(context).editorSaveFailedStay,
        );
      }
    }
  }

  Future<void> _share() async {
    final share = widget.onShare;
    if (share == null) return;
    try {
      await _flushForClose();
      if (!mounted) return;
      await share(widget.bookId);
    } on Object {
      if (mounted) {
        _notice(
          _session.saveError == null
              ? AppLocalizations.of(context).editorWorkbenchShareFailed
              : AppLocalizations.of(context).editorSaveFailedStay,
        );
      }
    }
  }

  void _notice(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _noticeFailure(Object error, String fallback) {
    if (error is AppFailure) {
      _notice([error.message, if (error.hint != null) error.hint!].join(' '));
    } else {
      _notice(fallback);
    }
  }
}

/// Keeps the same TextEditingController and selection across session updates.
class _ParagraphField extends StatefulWidget {
  const _ParagraphField({
    super.key,
    required this.text,
    required this.compact,
    required this.onTextChanged,
    required this.onComposingChanged,
    required this.onComposedDraftChanged,
    required this.onDisposed,
    required this.onParagraphAction,
    required this.onCreateRule,
    required this.onAnalyzeAdvertisement,
  });
  final String text;
  final bool compact;
  final ValueChanged<String> onTextChanged;
  final void Function(bool composing, VoidCallback finish) onComposingChanged;
  final ValueChanged<String?> onComposedDraftChanged;
  final VoidCallback onDisposed;
  final ValueChanged<String> onParagraphAction;
  final void Function(
    int startUtf16,
    int endUtf16,
    String original,
    ProofreadingRuleKind kind,
  )
  onCreateRule;
  final void Function(int startUtf16, int endUtf16, String original)
  onAnalyzeAdvertisement;

  @override
  State<_ParagraphField> createState() => _ParagraphFieldState();
}

class _ParagraphFieldState extends State<_ParagraphField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  late String _lastPublishedText = widget.text;
  bool _wasComposing = false;
  bool _applyingExternalValue = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onValueChanged);
  }

  void _onValueChanged() {
    final composing = _isComposing;
    widget.onComposedDraftChanged(composing ? _controller.text : null);
    if (composing != _wasComposing) {
      _wasComposing = composing;
      widget.onComposingChanged(composing, _finishComposition);
    }
    if (composing || _applyingExternalValue) return;
    final text = _controller.text;
    if (text == _lastPublishedText) return;
    _lastPublishedText = text;
    widget.onTextChanged(text);
  }

  void _finishComposition() {
    if (!_isComposing) return;
    _controller.value = _controller.value.copyWith(composing: TextRange.empty);
  }

  @override
  void didUpdateWidget(covariant _ParagraphField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _controller.text && !_isComposing) {
      final selection = _controller.selection;
      _applyingExternalValue = true;
      try {
        _lastPublishedText = widget.text;
        _controller.value = TextEditingValue(
          text: widget.text,
          selection: TextSelection.collapsed(
            offset: selection.baseOffset.clamp(0, widget.text.length),
          ),
        );
      } finally {
        _applyingExternalValue = false;
      }
    }
  }

  bool get _isComposing =>
      _controller.value.composing.isValid &&
      !_controller.value.composing.isCollapsed;

  @override
  void dispose() {
    widget.onDisposed();
    _controller.removeListener(_onValueChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLines: null,
    minLines: 1,
    keyboardType: TextInputType.multiline,
    style: AppTypography.reading(context.colors, compact: widget.compact),
    contextMenuBuilder: (context, editableText) {
      final l10n = AppLocalizations.of(context);
      final selection = _controller.selection;
      final source = _controller.text;
      final selected = selection.isValid && !selection.isCollapsed
          ? selection.textInside(source)
          : '';
      final canCreateRule =
          !_isComposing &&
          selected.trim().isNotEmpty &&
          selected.length <= ProofreadingRule.maxExampleUtf16 &&
          !selected.contains('\n') &&
          !selected.contains('\r');
      final canAnalyzeAdvertisement =
          !_isComposing &&
          selected.trim().isNotEmpty &&
          selected.length <= 8192;
      void action(String value) {
        ContextMenuController.removeAny();
        widget.onParagraphAction(value);
      }

      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableText.contextMenuAnchors,
        buttonItems: [
          ContextMenuButtonItem(
            label: l10n.editorSplitHere,
            onPressed: () => action('split'),
          ),
          ContextMenuButtonItem(
            label: l10n.editorSetAsTitle,
            onPressed: () => action('title'),
          ),
          if (canCreateRule)
            for (final kind in ProofreadingRuleKind.values)
              ContextMenuButtonItem(
                label: kind == ProofreadingRuleKind.chapter
                    ? l10n.editorAiCreateChapterRule
                    : l10n.editorAiCreateAdvertisementRule,
                onPressed: () {
                  ContextMenuController.removeAny();
                  widget.onCreateRule(
                    selection.start,
                    selection.end,
                    selected,
                    kind,
                  );
                },
              ),
          if (canAnalyzeAdvertisement)
            ContextMenuButtonItem(
              label: l10n.editorAiAnalyzeAdvertisement,
              onPressed: () {
                ContextMenuController.removeAny();
                widget.onAnalyzeAdvertisement(
                  selection.start,
                  selection.end,
                  selected,
                );
              },
            ),
          ...editableText.contextMenuButtonItems,
        ],
      );
    },
    decoration: const InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      filled: false,
      contentPadding: EdgeInsets.zero,
      isDense: true,
      isCollapsed: true,
    ),
  );
}
