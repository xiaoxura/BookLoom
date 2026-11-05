import 'dart:async';
import 'dart:io';

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

  @override
  void initState() {
    super.initState();
    _service = ref.read(importServiceProvider);
  }

  PickedInput? _input;
  PreparedImport? _prepared;
  ParseOptions _parseOptions = const ParseOptions();
  bool get _isTxt =>
      _input == null || p.extension(_input!.name).toLowerCase() == '.txt';
  bool _working = false;
  bool _committing = false;
  double? _progress;
  String? _stage;
  String? _error;

  @override
  void dispose() {
    _service.cancel();
    final selected = _input;
    final pending = _preparingDone?.future;
    unawaited(() async {
      await pending;
      await selected?.release();
    }());
    final prepared = _prepared;
    if (prepared != null) {
      unawaited(_service.discard(prepared).catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return AppPage(
      scrollable: false,
      child: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.importSelectTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.importTxtReady,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _working ? null : _pick,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(
                    _input == null
                        ? l10n.importChooseFile
                        : l10n.importChooseAnother,
                  ),
                ),
                if (_input != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _input!.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    p
                        .extension(_input!.name)
                        .replaceFirst('.', '')
                        .toUpperCase(),
                  ),
                  Text(
                    l10n.importFileSize(
                      _input!.size == null
                          ? l10n.importSizeUnknown
                          : _formatBytes(_input!.size!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_input != null) _options(l10n),
          if (_working) ...[
            const SizedBox(height: AppSpacing.lg),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: AppSpacing.sm),
            Text(_committing ? l10n.importSaving : _stageLabel(l10n)),
            const SizedBox(height: AppSpacing.sm),
            if (!_committing)
              OutlinedButton(
                onPressed: () => ref.read(importServiceProvider).cancel(),
                child: Text(l10n.commonCancel),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(_error!, style: TextStyle(color: colors.danger)),
          ],
          if (_prepared != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _review(_prepared!, l10n),
          ] else if (_input != null && !_working) ...[
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _prepare,
                child: Text(l10n.importAnalyze),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _working ? null : () => context.push('/batch'),
              icon: const Icon(Icons.queue_outlined),
              label: Text(l10n.workbenchOpenBatch),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _formatStatus(l10n),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _options(AppLocalizations l10n) {
    final colors = context.colors;
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
              l10n.importOptions,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ParseOptionsFields(
              options: _parseOptions,
              enabled: !_working,
              isTxt: _isTxt,
              files: ref.read(fileServiceProvider),
              cacheDirectory: Directory(
                p.join(ref.read(appPathsProvider).cache.path, 'workbench'),
              ),
              onChanged: (value) => _changeOptions(() => _parseOptions = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _review(PreparedImport prepared, AppLocalizations l10n) {
    final result = prepared.result;
    final colors = context.colors;
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
            const SizedBox(height: AppSpacing.sm),
            Text(result.suggestedMeta.title),
            Text(
              l10n.importReviewStats(
                result.chapters.length,
                prepared.wordCount,
              ),
            ),
            if (result.format == ImportFormat.txt)
              Text(
                l10n.importActualEncoding(
                  result.actualEncoding ?? l10n.importSizeUnknown,
                ),
              ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.importWarnings,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final warning in result.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _warningLabel(warning, l10n),
                    style: TextStyle(color: colors.warning),
                  ),
                ),
            ],
            if (firstText != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.importExcerpt,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(String.fromCharCodes(firstText.runes.take(360))),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton(
                  onPressed: _working ? null : _commit,
                  child: Text(l10n.importAddToLibrary),
                ),
                OutlinedButton(
                  onPressed: _working ? null : _discard,
                  child: Text(l10n.commonCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatStatus(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10n.importFormatsTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(l10n.importFormatAvailable(l10n.importFormatTxt)),
      Text(
        l10n.importFormatTxtDesc,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(l10n.importFormatAvailable(l10n.importFormatEpub)),
      Text(
        l10n.importFormatEpubDesc,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(l10n.importFormatAvailable(l10n.importFormatDocx)),
      Text(
        l10n.importFormatDocxDesc,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

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
  }

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
      final previous = _prepared;
      if (previous != null) {
        await ref.read(importServiceProvider).discard(previous);
      }
      await _input?.release();
      if (!mounted) {
        for (final input in selected) {
          await input.release();
        }
        return;
      }
      setState(() {
        _input = selected.first;
        if (!_isTxt) {
          _parseOptions = ParseOptions(convertMode: _parseOptions.convertMode);
        }
        _prepared = null;
        _error = null;
        _progress = null;
      });
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

  Future<void> _prepare() async {
    final input = _input;
    if (input == null) return;
    final service = _service;
    final completed = Completer<void>();
    _preparingDone = completed;
    setState(() {
      _working = true;
      _progress = null;
      _stage = null;
      _error = null;
    });
    try {
      final prepared = await service.prepare(
        input,
        options: _parseOptions,
        onProgress: (JobProgress progress) {
          if (mounted) {
            setState(() {
              _progress = progress.fraction;
              _stage = progress.stage;
            });
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
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _commit() async {
    final prepared = _prepared;
    if (prepared == null) return;
    setState(() {
      _working = true;
      _committing = true;
      _error = null;
    });
    try {
      final selected = _input;
      final book = await _service.commit(prepared);
      await selected?.release();
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
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _committing = false;
        });
      }
    }
  }

  Future<void> _discard() async {
    final prepared = _prepared;
    if (prepared == null) return;
    setState(() => _working = true);
    try {
      await _service.discard(prepared);
      if (mounted) {
        setState(() {
          _prepared = null;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = _failureLabel(
            AppLocalizations.of(context).importDiscardFailed,
            error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _stageLabel(AppLocalizations l10n) => switch (_stage) {
    'decode' => l10n.importStageDecode,
    'parse' => l10n.importStageParse,
    'ready' => l10n.importStageReady,
    _ => l10n.importStagePrepare,
  };

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
