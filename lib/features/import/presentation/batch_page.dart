import 'dart:async';

import 'package:bookloom/app/providers.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/settings/workbench_preferences.dart';
import 'package:bookloom/design/components/app_page.dart';
import 'package:bookloom/design/theme/app_tokens.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/import/application/batch_service.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// The shell owns [service]; leaving this page does not discard a running job.
class BatchPage extends ConsumerStatefulWidget {
  const BatchPage({super.key, required this.service});

  final BatchService service;

  @override
  ConsumerState<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends ConsumerState<BatchPage> {
  List<PickedInput> _selected = const [];
  BatchMode _mode = BatchMode.addToLibrary;
  ExportFormat _format = ExportFormat.epub3;
  bool _formatLoaded = false;
  bool _formatTouched = false;
  String _encoding = 'auto';
  ConvertMode _convertMode = ConvertMode.none;
  bool _filterAds = true;
  bool _picking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_refresh);
    unawaited(_loadDefaultFormat());
  }

  Future<void> _loadDefaultFormat() async {
    try {
      final defaults = await WorkbenchPreferences.read(
        ref.read(settingsStoreProvider),
      );
      if (!mounted) return;
      setState(() {
        if (!_formatTouched) _format = defaults.exportFormat;
        _formatLoaded = true;
      });
    } on Object catch (error) {
      debugPrint('Batch default format unavailable: $error');
      if (mounted) setState(() => _formatLoaded = true);
    }
  }

  @override
  void didUpdateWidget(covariant BatchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service == widget.service) return;
    oldWidget.service.removeListener(_refresh);
    final previous = _selected;
    _selected = const [];
    unawaited(
      _releaseUnqueued(oldWidget.service, previous).catchError(
        (Object error) => debugPrint('Batch picker cleanup failed: $error'),
      ),
    );
    widget.service.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.service.removeListener(_refresh);
    unawaited(
      _releaseUnqueued(widget.service, _selected).catchError(
        (Object error) => debugPrint('Batch picker cleanup failed: $error'),
      ),
    );
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final colors = context.colors;
    final locked = service.isRunning || _picking;
    final items = service.items;
    final success = items
        .where((item) => item.status == BatchItemStatus.success)
        .length;
    final failed = items
        .where((item) => item.status == BatchItemStatus.failed)
        .length;
    return AppPage(
      title: AppLocalizations.of(context).dataWorkbenchBatchTitle,
      subtitle: AppLocalizations.of(context).dataWorkbenchBatchSubtitle,
      // Pushed above the shell, so it carries its own way back — same header
      // affordance as the other pushed pages.
      leading: BackButton(onPressed: () => context.pop()),
      scrollable: false,
      child: ListView(
        children: [
          _surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dataWorkbenchBatchSettings,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<BatchMode>(
                  initialValue: _mode,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)
                        .dataWorkbenchBatchAction,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: BatchMode.addToLibrary,
                      child: Text(
                        AppLocalizations.of(context)
                            .dataWorkbenchBatchAddToLibrary,
                      ),
                    ),
                    DropdownMenuItem(
                      value: BatchMode.convertFiles,
                      child: Text(
                        AppLocalizations.of(context)
                            .dataWorkbenchBatchConvertFiles,
                      ),
                    ),
                  ],
                  onChanged: locked
                      ? null
                      : (value) => setState(() => _mode = value ?? _mode),
                ),
                if (_mode == BatchMode.convertFiles) ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<ExportFormat>(
                    initialValue: _format,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)
                          .dataWorkbenchOutputFormat,
                    ),
                    items: [
                      for (final format in ExportFormat.values)
                        DropdownMenuItem(
                          value: format,
                          child: Text(_formatLabel(format)),
                        ),
                    ],
                    onChanged: locked
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _formatTouched = true;
                              _format = value;
                            });
                          },
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _encoding,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)
                        .dataWorkbenchBatchTxtEncoding,
                  ),
                  items: _encodingItems(),
                  onChanged: locked
                      ? null
                      : (value) => setState(() => _encoding = value ?? 'auto'),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<ConvertMode>(
                  initialValue: _convertMode,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)
                        .dataWorkbenchBatchChineseConversion,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: ConvertMode.none,
                      child: Text(
                        AppLocalizations.of(context)
                            .dataWorkbenchBatchNoConversion,
                      ),
                    ),
                    DropdownMenuItem(
                      value: ConvertMode.simplified,
                      child: Text(
                        AppLocalizations.of(context)
                            .dataWorkbenchBatchSimplified,
                      ),
                    ),
                    DropdownMenuItem(
                      value: ConvertMode.taiwan,
                      child: Text(
                        AppLocalizations.of(context)
                            .dataWorkbenchBatchTaiwanTraditional,
                      ),
                    ),
                  ],
                  onChanged: locked
                      ? null
                      : (value) => setState(
                          () => _convertMode = value ?? _convertMode,
                        ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    AppLocalizations.of(context).dataWorkbenchBatchFilterAds,
                  ),
                  value: _filterAds,
                  onChanged: locked
                      ? null
                      : (value) => setState(() => _filterAds = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: locked ? null : _pick,
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(
                        AppLocalizations.of(context)
                            .dataWorkbenchBatchChooseFiles,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed:
                          locked ||
                              (_mode == BatchMode.convertFiles &&
                                  !_formatLoaded) ||
                              _selected.isEmpty
                          ? null
                          : _start,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        AppLocalizations.of(context).dataWorkbenchBatchStart,
                      ),
                    ),
                    if (service.isRunning)
                      OutlinedButton.icon(
                        onPressed: service.cancel,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(
                          service.isCommitting
                              ? AppLocalizations.of(context)
                                    .dataWorkbenchBatchCancelAfterSave
                              : AppLocalizations.of(context)
                                    .dataWorkbenchBatchCancelRemaining,
                        ),
                      ),
                  ],
                ),
                if (_selected.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppLocalizations.of(context)
                        .dataWorkbenchBatchSelectedFiles(_selected.length),
                  ),
                ],
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_message!, style: TextStyle(color: colors.danger)),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).dataWorkbenchBatchQueue,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).dataWorkbenchBatchSummary(success, failed, items.length),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final item in items) _itemRow(item),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton(
                        onPressed: locked || failed == 0 ? null : _retry,
                        child: Text(
                          AppLocalizations.of(context)
                              .dataWorkbenchRetryFailedOnly,
                        ),
                      ),
                      if (service.mode == BatchMode.convertFiles)
                        FilledButton.icon(
                          onPressed: service.canSaveZip ? _saveZip : null,
                          icon: const Icon(Icons.archive_outlined),
                          label: Text(
                            AppLocalizations.of(context)
                                .dataWorkbenchBatchSaveZip,
                          ),
                        ),
                    ],
                  ),
                  if (service.saveOutcome case SaveSaved()) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(AppLocalizations.of(context).dataWorkbenchZipSaved),
                  ] else if (service.saveOutcome case SaveCancelled()) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppLocalizations.of(context)
                          .dataWorkbenchBatchSaveCancelled,
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _surface({required Widget child}) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }

  Widget _itemRow(BatchItem item) {
    final colors = context.colors;
    final isTxt = p.extension(item.input.name).toLowerCase() == '.txt';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.input.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _status(item.status),
                style: TextStyle(
                  color: item.status == BatchItemStatus.failed
                      ? colors.danger
                      : colors.inkSecondary,
                ),
              ),
            ],
          ),
          if (item.progress != null) ...[
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(value: item.progress),
          ],
          if (item.error != null)
            Text(item.error!, style: TextStyle(color: colors.danger)),
          if (item.outputName != null) Text(item.outputName!),
          if (item.status == BatchItemStatus.failed && isTxt) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: widget.service.retryOptionsFor(item.index).encoding,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)
                    .dataWorkbenchBatchRetryEncoding,
              ),
              items: _encodingItems(),
              onChanged: widget.service.isRunning
                  ? null
                  : (value) {
                      if (value == null) return;
                      widget.service.setRetryOptions(
                        item.index,
                        widget.service
                            .retryOptionsFor(item.index)
                            .copyWith(encoding: value),
                      );
                    },
            ),
          ],
          Divider(color: colors.hairline),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _encodingItems() => [
    DropdownMenuItem(
      value: 'auto',
      child: Text(AppLocalizations.of(context).dataWorkbenchBatchAuto),
    ),
    const DropdownMenuItem(value: 'utf-8', child: Text('UTF-8')),
    const DropdownMenuItem(value: 'gb18030', child: Text('GB18030 / GBK')),
    const DropdownMenuItem(value: 'big5', child: Text('Big5')),
    const DropdownMenuItem(value: 'utf-16le', child: Text('UTF-16 LE')),
    const DropdownMenuItem(value: 'utf-16be', child: Text('UTF-16 BE')),
  ];

  String _formatLabel(ExportFormat format) => switch (format) {
    ExportFormat.epub3 => 'EPUB 3',
    ExportFormat.epub2 => 'EPUB 2',
    ExportFormat.docx => 'DOCX',
    ExportFormat.html => 'HTML',
    ExportFormat.txt => 'TXT',
    ExportFormat.markdown => 'Markdown',
  };

  String _status(BatchItemStatus status) => switch (status) {
    BatchItemStatus.waiting => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusWaiting,
    BatchItemStatus.processing => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusProcessing,
    BatchItemStatus.success => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusSuccess,
    BatchItemStatus.failed => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusFailed,
    BatchItemStatus.cancelled => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusCancelled,
  };

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _message = null;
    });
    try {
      final selected = await widget.service.selectFiles();
      if (!mounted) {
        await _releaseUnqueued(widget.service, selected);
        return;
      }
      if (selected.isNotEmpty) {
        final previous = _selected;
        setState(() => _selected = selected);
        await _releaseUnqueued(widget.service, previous, retaining: selected);
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _message = AppLocalizations.of(context)
                  .dataWorkbenchBatchPickFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _releaseUnqueued(
    BatchService service,
    Iterable<PickedInput> selected, {
    Iterable<PickedInput> retaining = const [],
  }) async {
    final keep = Set<PickedInput>.identity()
      ..addAll(retaining)
      ..addAll(service.items.map((item) => item.input));
    final released = Set<PickedInput>.identity();
    for (final input in selected) {
      if (!keep.contains(input) && released.add(input)) await input.release();
    }
    await service.files.clearTemporaryFiles();
  }

  Future<void> _start() async {
    try {
      setState(() => _message = null);
      await widget.service.enqueue(
        _selected,
        mode: _mode,
        format: _format,
        options: ParseOptions(
          encoding: _encoding,
          filterAds: _filterAds,
          convertMode: _convertMode,
        ),
      );
      await widget.service.start();
    } on AppFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _message = AppLocalizations.of(context)
                  .dataWorkbenchBatchStartFailed,
        );
      }
    }
  }

  Future<void> _retry() async {
    try {
      setState(() => _message = null);
      await widget.service.retryFailed();
    } on AppFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _saveZip() async {
    try {
      setState(() => _message = null);
      await widget.service.saveZip();
    } on AppFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _message = AppLocalizations.of(context)
                  .dataWorkbenchZipSaveFailed,
        );
      }
    }
  }
}
