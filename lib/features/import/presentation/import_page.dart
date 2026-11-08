import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../app/workbench_providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/model/block.dart';
import '../../../core/model/parse_options.dart';
import '../../../core/model/parse_result.dart';
import '../../../core/platform/background_jobs.dart';
import '../../../core/platform/files.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import '../application/import_service.dart';
import 'parse_options_fields.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  late final ImportService _service;
  Completer<void>? _preparingDone;
  DialogRoute<void>? _taskRoute;
  ValueNotifier<_ImportTaskStatus>? _taskStatus;

  PickedInput? _input;
  PreparedImport? _prepared;
  ParseOptions _parseOptions = const ParseOptions();
  bool get _isTxt =>
      _input == null || p.extension(_input!.name).toLowerCase() == '.txt';
  bool _working = false;
  bool _committing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = ref.read(importServiceProvider);
  }

  @override
  void dispose() {
    if (!_committing) _service.cancel();
    _closeTaskDialog(deferRemoval: true);
    final selected = _input;
    final pending = _preparingDone?.future;
    unawaited(() async {
      await pending;
      await selected?.release();
    }());
    final prepared = _prepared;
    if (prepared != null && !_committing) {
      unawaited(_service.discard(prepared).catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPage(
      scrollable: false,
      // A task flow, not a data page: the cards read best in a narrow column.
      maxContentWidth: 760,
      child: ListView(
        shrinkWrap: false,
        children: [
          _DropZone(
            enabled: !_working,
            onDropped: _handleDroppedFiles,
            child: _selectionCard(l10n),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: TextStyle(color: context.colors.danger)),
          ],
          if (_prepared != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _reviewCard(l10n),
          ] else if (_input != null && !_working) ...[
            // Auto-parsing was cancelled or never ran; let the user start it.
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _prepare,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.importAnalyze),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _selectionCard(AppLocalizations l10n) {
    final colors = context.colors;
    final input = _input;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: input == null
            ? _emptyImportDrop(l10n)
            : _selectedFileRow(l10n, input),
      ),
    );
  }

  /// Empty state: one centered drop well, one muted format line, one batch
  /// link — nothing else competes for attention.
  Widget _emptyImportDrop(AppLocalizations l10n) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _working ? null : _pick,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xxl,
              horizontal: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceSunken.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.5
                    : 0.7,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.hairline),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.file_open_outlined,
                  size: 30,
                  color: colors.inkSecondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _working ? l10n.importStagePrepare : l10n.importSelectTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.importDropHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'TXT · EPUB · DOCX',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.inkMuted,
              ),
            ),
            TextButton.icon(
              onPressed: _working ? null : () => context.push('/batch'),
              icon: const Icon(Icons.queue_outlined, size: 18),
              label: Text(l10n.workbenchOpenBatch),
            ),
          ],
        ),
      ],
    );
  }

  /// A file is selected: one compact row (name + size + re-choose). The parse
  /// result and the commit actions live in the review card below.
  Widget _selectedFileRow(AppLocalizations l10n, PickedInput input) {
    final colors = context.colors;
    final meta = '${p
        .extension(input.name)
        .replaceFirst('.', '')
        .toUpperCase()} · '
        '${l10n.importFileSize(
          input.size == null ? l10n.importSizeUnknown : _formatBytes(input.size!),
        )}';
    return Row(
      children: [
        Icon(
          Icons.description_outlined,
          size: 22,
          color: colors.inkSecondary,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                input.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        IconButton(
          tooltip: l10n.importChooseAnother,
          onPressed: _working ? null : _pick,
          icon: const Icon(Icons.folder_open_outlined, size: 20),
        ),
        TextButton(
          onPressed: _working ? null : _reset,
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }

  /// Review card: parse result on top, tweakable options at the bottom.
  /// Changing an option discards the prepared data and re-parses
  /// automatically, so "one screen" stays true from preview to commit.
  Widget _reviewCard(AppLocalizations l10n) {
    final colors = context.colors;
    final result = _prepared!.result;
    final firstText = result.chapters
        .expand((chapter) => chapter.blocks)
        .whereType<TextBlock>()
        .map((block) => block.text.trim())
        .where((text) => text.isNotEmpty)
        .firstOrNull;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.importReviewTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              result.suggestedMeta.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.importReviewStats(result.chapters.length, _prepared!.wordCount),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (result.format == ImportFormat.txt)
                  Text(
                    l10n.importActualEncoding(
                      result.actualEncoding ?? l10n.importSizeUnknown,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final warning in result.warnings)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs, top: 2),
                      child: Icon(
                        Icons.warning_amber_outlined,
                        size: 16,
                        color: colors.warning,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _warningLabel(warning, l10n),
                        style: TextStyle(color: colors.warning),
                      ),
                    ),
                  ],
                ),
            ],
            if (firstText != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.surfaceSunken.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.35
                        : 0.55,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  String.fromCharCodes(firstText.runes.take(360)),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              childrenPadding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(
                l10n.importOptions,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              children: [
                ParseOptionsFields(
                  options: _parseOptions,
                  enabled: !_working,
                  isTxt: _isTxt,
                  files: ref.read(fileServiceProvider),
                  cacheDirectory: Directory(
                    p.join(ref.read(appPathsProvider).cache.path, 'workbench'),
                  ),
                  onChanged: (value) =>
                      _changeOptions(() => _parseOptions = value),
                ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                FilledButton(
                  onPressed: _working ? null : _commit,
                  child: Text(l10n.importAddToLibrary),
                ),
                OutlinedButton(
                  onPressed: _working ? null : _reset,
                  child: Text(l10n.commonCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- ingestion ----

  Future<void> _pick() async {
    try {
      final selected = await ref
          .read(fileServiceProvider)
          .pickImports(
            multiple: false,
            extensions: const ['txt', 'epub', 'docx'],
          );
      if (!mounted) {
        for (final input in selected) {
          await input.release();
        }
        return;
      }
      if (selected.isEmpty) return;
      await _adoptInput(selected.first);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = _failureLabel(
            AppLocalizations.of(context).importPickFailed,
            error,
          ),
        );
      }
    }
  }

  void _handleDroppedFiles(DropDoneDetails detail) {
    if (_working) return;
    final paths = <String>[for (final file in detail.files) file.path];
    final usable = paths
        .where(
          (path) => const [
            '.txt',
            '.epub',
            '.docx',
          ].contains(p.extension(path).toLowerCase()),
        )
        .toList();
    if (usable.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).importDropUnsupported,
      );
      return;
    }
    unawaited(
      () async {
        final file = File(usable.first);
        try {
          final size = await file.length();
          final input = PickedInput(
            name: p.basename(file.path),
            size: size,
            openRead: file.openRead,
          );
          if (!mounted) return;
          await _adoptInput(input);
        } on Object {
          if (mounted) {
            setState(
              () => _error = AppLocalizations.of(context).importPickFailed,
            );
          }
        }
      }(),
    );
  }

  /// Swaps the active input (releasing the previous one), then parses with
  /// the current options without further clicks.
  Future<void> _adoptInput(PickedInput input) async {
    final previous = _prepared;
    if (previous != null) {
      await ref.read(importServiceProvider).discard(previous);
    }
    await _input?.release();
    if (!mounted) {
      await input.release();
      return;
    }
    setState(() {
      _input = input;
      if (!_isTxt) {
        _parseOptions = ParseOptions(convertMode: _parseOptions.convertMode);
      }
      _prepared = null;
      _error = null;
    });
    unawaited(_prepare());
  }

  void _changeOptions(VoidCallback change) {
    final prepared = _prepared;
    if (prepared != null) {
      unawaited(_service.discard(prepared).catchError((Object _) {}));
    }
    setState(() {
      change();
      _prepared = null;
      _error = null;
    });
    // Options changed after a preview exists — parse again right away so the
    // preview always reflects what would be committed.
    if (_input != null) unawaited(_prepare());
  }

  // ---- tasks ----

  Future<void> _prepare() async {
    final input = _input;
    if (input == null || _working) return;
    final service = _service;
    final completed = Completer<void>();
    _preparingDone = completed;
    setState(() {
      _working = true;
      _error = null;
    });
    final task = _openTaskDialog(committing: false);
    try {
      final prepared = await service.prepare(
        input,
        options: _parseOptions,
        onProgress: (JobProgress progress) {
          if (mounted &&
              identical(_taskStatus, task) &&
              !task.value.cancelling) {
            task.value = _ImportTaskStatus(
              committing: false,
              stage: progress.stage,
            );
          }
        },
      );
      if (!mounted) {
        await service.discard(prepared);
        return;
      }
      setState(() => _prepared = prepared);
    } on TaskCancelled {
      // Cancellation leaves the selected input available for another attempt.
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = _failureLabel(
            AppLocalizations.of(context).importAnalyzeFailed,
            error,
          ),
        );
      }
    } finally {
      completed.complete();
      if (identical(_preparingDone, completed)) _preparingDone = null;
      _closeTaskDialog();
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _commit() async {
    final prepared = _prepared;
    if (prepared == null || _working) return;
    setState(() {
      _working = true;
      _committing = true;
      _error = null;
    });
    final task = _openTaskDialog(committing: true);
    try {
      final book = await _service.commit(
        prepared,
        onProgress: (JobProgress progress) {
          if (mounted && identical(_taskStatus, task)) {
            task.value = _ImportTaskStatus(
              committing: true,
              fraction: progress.fraction,
              stage: progress.stage,
            );
          }
        },
      );
      _closeTaskDialog();
      try {
        await _input?.release();
      } on Object {
        debugPrint('Import source lease cleanup deferred.');
      }
      if (!mounted) return;
      setState(() {
        _prepared = null;
        _input = null;
      });
      ref.invalidate(libraryBooksProvider);
      try {
        await ref.read(fileServiceProvider).clearTemporaryFiles();
      } on Object {
        // The committed book is complete; picker cache cleanup can be retried.
      }
      if (mounted) unawaited(context.push('/books/${book.id}'));
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = _failureLabel(
            AppLocalizations.of(context).importSaveFailed,
            error,
          ),
        );
      } else {
        unawaited(_service.discard(prepared).catchError((Object _) {}));
      }
    } finally {
      _closeTaskDialog();
      if (mounted) {
        setState(() {
          _working = false;
          _committing = false;
        });
      }
    }
  }

  /// Full reset from the preview: discards the prepared data and the selected
  /// file, returning to the empty drop state.
  Future<void> _reset() async {
    final prepared = _prepared;
    if (prepared != null) {
      setState(() => _working = true);
      try {
        await _service.discard(prepared);
      } on Object catch (error) {
        if (mounted) {
          setState(
            () => _error = _failureLabel(
              AppLocalizations.of(context).importDiscardFailed,
              error,
            ),
          );
          return;
        }
      } finally {
        if (mounted) setState(() => _working = false);
      }
    }
    await _input?.release();
    if (mounted) {
      setState(() {
        _prepared = null;
        _input = null;
        _error = null;
      });
    }
  }

  ValueNotifier<_ImportTaskStatus> _openTaskDialog({required bool committing}) {
    final task = ValueNotifier<_ImportTaskStatus>(
      _ImportTaskStatus(
        committing: committing,
        fraction: committing ? 0 : null,
      ),
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !committing) _cancelPrepare(task);
        },
        child: ValueListenableBuilder<_ImportTaskStatus>(
          valueListenable: task,
          builder: (context, status, _) => _ImportProgressDialog(
            status: status,
            onCancel: committing ? null : () => _cancelPrepare(task),
          ),
        ),
      ),
    );
    _taskStatus = task;
    _taskRoute = route;
    unawaited(navigator.push(route));
    return task;
  }

  void _cancelPrepare(ValueNotifier<_ImportTaskStatus> task) {
    if (!identical(_taskStatus, task) || task.value.cancelling) return;
    task.value = _ImportTaskStatus(committing: false, cancelling: true);
    _service.cancel();
  }

  void _closeTaskDialog({bool deferRemoval = false}) {
    final route = _taskRoute;
    final task = _taskStatus;
    _taskRoute = null;
    _taskStatus = null;
    void remove() {
      if (route?.isActive ?? false) route!.navigator?.removeRoute(route);
      task?.dispose();
    }

    if (deferRemoval) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
    } else {
      remove();
    }
  }

  String _warningLabel(ParseWarning warning, AppLocalizations l10n) =>
      switch (warning.code) {
        'low_encoding_confidence' => l10n.importWarningEncoding,
        'no_headings' => l10n.importWarningNoHeadings,
        'many_chapters' => l10n.importWarningManyChapters,
        _ => l10n.importWarningGeneric(warning.code),
      };

  String _formatBytes(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

  String _failureLabel(String summary, Object error) => error is AppFailure
      ? '$summary ${error.message}${error.hint == null ? '' : ' ${error.hint}'}'
      : summary;
}

/// Drop target chrome for the selection card: a drag-over accent ring around
/// the card and drag-done routing. Files arrive as plain local paths, which
/// wrap cleanly into [PickedInput] streams without touching the picker lease
/// machinery.
class _DropZone extends StatefulWidget {
  const _DropZone({
    required this.child,
    required this.onDropped,
    this.enabled = true,
  });

  final Widget child;
  final void Function(DropDoneDetails details) onDropped;
  final bool enabled;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: widget.enabled ? (_) => setState(() => _over = true) : null,
      onDragExited: widget.enabled ? (_) => setState(() => _over = false) : null,
      onDragDone: widget.enabled
          ? (details) {
              setState(() => _over = false);
              widget.onDropped(details);
            }
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: _over
              ? Border.all(color: context.colors.accent, width: 2)
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ImportTaskStatus {
  const _ImportTaskStatus({
    required this.committing,
    this.fraction,
    this.stage,
    this.cancelling = false,
  });

  final bool committing;
  final double? fraction;
  final String? stage;
  final bool cancelling;
}

class _ImportProgressDialog extends StatelessWidget {
  const _ImportProgressDialog({required this.status, required this.onCancel});

  final _ImportTaskStatus status;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fraction = status.fraction;
    final stage = switch (status.stage) {
      'decode' => l10n.importStageDecode,
      'parse' => l10n.importStageParse,
      'convert' => l10n.importStageConvert,
      'ready' => l10n.importStageReady,
      'save_prepare' => l10n.importStageSavePrepare,
      'save_chapters' => l10n.importStageSaveChapters,
      'save_blocks' => l10n.importStageSaveBlocks,
      'save_finalize' => l10n.importStageSaveFinalize,
      _ => status.committing ? l10n.importSaving : l10n.importStagePrepare,
    };
    return AlertDialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      scrollable: true,
      title: Text(l10n.importTaskTitle),
      content: SizedBox(
        width: AppLayout.bottomBarMaxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(status.cancelling ? l10n.importCancelling : stage),
            const SizedBox(height: AppSpacing.lg),
            LinearProgressIndicator(value: fraction),
            if (!status.cancelling) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                fraction == null
                    ? l10n.importPreparing
                    : l10n.importProgressPercent(
                        (fraction * 100).floor().clamp(
                          0,
                          fraction < 1 ? 99 : 100,
                        ),
                      ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
            if (status.committing) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.importSavingNotice,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
      actions: onCancel == null
          ? null
          : [
              TextButton(
                onPressed: status.cancelling ? null : onCancel,
                child: Text(l10n.commonCancel),
              ),
            ],
    );
  }
}
