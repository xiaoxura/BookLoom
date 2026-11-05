import 'dart:async';

import 'package:bookloom/app/providers.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/settings/workbench_preferences.dart';
import 'package:bookloom/design/theme/app_tokens.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/export/application/library_export_service.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Embed beside the book selection on BookDataPage. The caller owns [service]
/// so a page rebuild cannot abandon an active queue or its private outputs.
class LibraryExportPanel extends ConsumerStatefulWidget {
  const LibraryExportPanel({
    super.key,
    required this.bookIds,
    required this.service,
    this.titlesById = const <String, String>{},
  });

  final List<String> bookIds;
  final Map<String, String> titlesById;
  final LibraryExportService service;

  @override
  ConsumerState<LibraryExportPanel> createState() => _LibraryExportPanelState();
}

class _LibraryExportPanelState extends ConsumerState<LibraryExportPanel> {
  ExportFormat _format = ExportFormat.epub3;
  bool _formatLoaded = false;
  bool _formatTouched = false;
  String? _error;

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
      debugPrint('Library export default format unavailable: $error');
      if (mounted) setState(() => _formatLoaded = true);
    }
  }

  @override
  void didUpdateWidget(covariant LibraryExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service == widget.service) return;
    oldWidget.service.removeListener(_refresh);
    widget.service.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.service.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = widget.service;
    final items = service.items;
    final success = items
        .where((item) => item.status == LibraryExportStatus.success)
        .length;
    final failed = items
        .where((item) => item.status == LibraryExportStatus.failed)
        .length;
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
              AppLocalizations.of(context).dataWorkbenchLibraryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppLocalizations.of(context)
                  .dataWorkbenchLibrarySelected(widget.bookIds.length),
            ),
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
              onChanged: service.isRunning
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _formatTouched = true;
                        _format = value;
                      });
                    },
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed:
                      service.isRunning ||
                          !_formatLoaded ||
                          widget.bookIds.isEmpty
                      ? null
                      : _start,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(
                    AppLocalizations.of(context)
                        .dataWorkbenchLibraryExportSelected,
                  ),
                ),
                if (service.isRunning)
                  OutlinedButton.icon(
                    onPressed: service.isCommitting ? null : service.cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      service.isCommitting
                          ? AppLocalizations.of(context)
                                .dataWorkbenchLibraryFinishingSave
                          : AppLocalizations.of(context)
                                .dataWorkbenchLibraryCancelRemaining,
                    ),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: colors.danger)),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppLocalizations.of(context)
                    .dataWorkbenchLibrarySummary(success, failed, items.length),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final item in items) _itemRow(item),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: service.isRunning || failed == 0 ? null : _retry,
                    child: Text(
                      AppLocalizations.of(context).dataWorkbenchRetryFailedOnly,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: service.canSaveZip ? _save : null,
                    icon: const Icon(Icons.save_alt),
                    label: Text(
                      AppLocalizations.of(context)
                          .dataWorkbenchLibrarySaveSuccessfulZip,
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
                      .dataWorkbenchLibrarySaveCancelled,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemRow(LibraryExportItem item) {
    final colors = context.colors;
    final name = widget.titlesById[item.bookId] ?? item.title ?? item.bookId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _status(item.status),
                style: TextStyle(
                  color: item.status == LibraryExportStatus.failed
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
          if (item.outputName != null) Text(item.outputName!),
          if (item.error != null)
            Text(item.error!, style: TextStyle(color: colors.danger)),
          Divider(color: colors.hairline),
        ],
      ),
    );
  }

  String _formatLabel(ExportFormat format) => switch (format) {
    ExportFormat.epub3 => 'EPUB 3',
    ExportFormat.epub2 => 'EPUB 2',
    ExportFormat.docx => 'DOCX',
    ExportFormat.html => 'HTML',
    ExportFormat.txt => 'TXT',
    ExportFormat.markdown => 'Markdown',
  };

  String _status(LibraryExportStatus status) => switch (status) {
    LibraryExportStatus.waiting => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusWaiting,
    LibraryExportStatus.processing => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusProcessing,
    LibraryExportStatus.success => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusSuccess,
    LibraryExportStatus.failed => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusFailed,
    LibraryExportStatus.cancelled => AppLocalizations.of(
      context,
    ).dataWorkbenchStatusCancelled,
  };

  Future<void> _start() async {
    try {
      setState(() => _error = null);
      await widget.service.enqueue(widget.bookIds, format: _format);
      await widget.service.start();
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = AppLocalizations.of(context)
                  .dataWorkbenchLibraryStartFailed,
        );
      }
    }
  }

  Future<void> _retry() async {
    try {
      setState(() => _error = null);
      await widget.service.retryFailed();
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _save() async {
    try {
      setState(() => _error = null);
      await widget.service.saveZip();
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = AppLocalizations.of(context).dataWorkbenchZipSaveFailed,
        );
      }
    }
  }
}
