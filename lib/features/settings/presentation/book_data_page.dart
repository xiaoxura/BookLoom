import 'dart:async';
import 'dart:io';

import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/window/window_controls.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/app_info.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/platform/job_cache.dart';
import 'package:bookloom/core/storage/book_backup.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/components/app_page.dart';
import 'package:bookloom/features/export/presentation/library_export_panel.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class BookDataPage extends ConsumerStatefulWidget {
  const BookDataPage({super.key});

  @override
  ConsumerState<BookDataPage> createState() => _BookDataPageState();
}

class _BookDataPageState extends ConsumerState<BookDataPage> {
  final _budget = TextEditingController(text: '2048');
  final Set<String> _selected = {};
  List<BookSummary> _books = [];
  CachedJob? _lease;
  RestorePreview? _preview;
  BookBackup? _backup;
  Future<void>? _operation;
  Future<void>? _releasing;
  VoidCallback? _detachClose;
  RestoreConflictPolicy _policy = RestoreConflictPolicy.copy;
  bool _includeSources = true;
  bool _busy = false;
  bool _cancelled = false;
  String? _message;
  String? _error;
  int? _supportBytes;
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _refresh();
    _detachClose = WindowControls.guardClose(() async {
      _cancel();
      await _operation;
      await _release();
    });
  }

  @override
  void dispose() {
    _detachClose?.call();
    _budget.dispose();
    _cancel();
    final pending = _operation;
    unawaited(() async {
      try {
        await pending;
      } on Object {
        /* Reported by _run. */
      }
      await _release();
    }());
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final books = await ref.read(bookRepositoryProvider).listSummaries();
      final paths = ref.read(appPathsProvider);
      final support = await _directoryBytes(paths.support);
      final cache = p.isWithin(paths.support.path, paths.cache.path)
          ? 0
          : await _directoryBytes(paths.cache);
      if (mounted) {
        setState(() {
          _books = books;
          _selected
            ..removeWhere((id) => !books.any((book) => book.id == id))
            ..addAll(books.map((book) => book.id));
          _supportBytes = support;
          _cacheBytes = cache;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PopScope(
      canPop: !_busy,
      child: AppPage(
        title: AppLocalizations.of(context).dataWorkbenchBackupTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: Text(
                  AppLocalizations.of(context).dataWorkbenchBackupBack,
                ),
              ),
            ),
            if (_supportBytes != null)
              Text(
                AppLocalizations.of(context).dataWorkbenchBackupStorage(
                  _size(_supportBytes!),
                  _size(_cacheBytes ?? 0),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).dataWorkbenchBackupCurrentBooks,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context).dataWorkbenchBackupIncludes),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                AppLocalizations.of(context).dataWorkbenchBackupIncludeSources,
              ),
              subtitle: Text(
                AppLocalizations.of(context).dataWorkbenchBackupWithoutSources,
              ),
              value: _includeSources,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _includeSources = value),
            ),
            for (final book in _books)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(book.title),
                subtitle: Text(book.author),
                value: _selected.contains(book.id),
                onChanged: _busy
                    ? null
                    : (selected) => setState(() {
                        if (selected == true) {
                          _selected.add(book.id);
                        } else {
                          _selected.remove(book.id);
                        }
                      }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy || _selected.isEmpty
                    ? null
                    : () => _run(_export),
                icon: const Icon(Icons.save_alt),
                label: Text(
                  AppLocalizations.of(context).dataWorkbenchBackupSaveFile,
                ),
              ),
            ),
            const SizedBox(height: 24),
            LibraryExportPanel(
              bookIds: _selected.toList(),
              titlesById: {for (final book in _books) book.id: book.title},
              service: ref.read(libraryExportServiceProvider),
            ),
            const SizedBox(height: 32),
            Text(
              AppLocalizations.of(context).dataWorkbenchBackupRestore,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _budget,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)
                    .dataWorkbenchBackupMaxData,
                helperMaxLines: 4,
                helperText: AppLocalizations.of(context)
                    .dataWorkbenchBackupMaxDataHelp,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_prepareRestore),
                icon: const Icon(Icons.folder_open),
                label: Text(
                  AppLocalizations.of(context).dataWorkbenchBackupChooseInspect,
                ),
              ),
            ),
            if (preview != null) ...[
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).dataWorkbenchBackupValidated(
                  preview.books.length,
                  _size(preview.actualBytes),
                ),
              ),
              Text(
                AppLocalizations.of(context).dataWorkbenchBackupEstimatedSpace(
                  _size(preview.estimatedRequiredBytes),
                ),
              ),
              for (final book in preview.books)
                Text(
                  AppLocalizations.of(context).dataWorkbenchBackupPreviewBook(
                    book.title,
                    book.chapterCount,
                    book.wordCount,
                  ),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<RestoreConflictPolicy>(
                initialValue: _policy,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)
                      .dataWorkbenchBackupConflictPolicy,
                ),
                items: [
                  DropdownMenuItem(
                    value: RestoreConflictPolicy.copy,
                    child: Text(
                      AppLocalizations.of(context).dataWorkbenchBackupKeepBoth,
                    ),
                  ),
                  DropdownMenuItem(
                    value: RestoreConflictPolicy.skip,
                    child: Text(
                      AppLocalizations.of(context)
                          .dataWorkbenchBackupSkipConflicts,
                    ),
                  ),
                  DropdownMenuItem(
                    value: RestoreConflictPolicy.overwrite,
                    child: Text(
                      AppLocalizations.of(context)
                          .dataWorkbenchBackupOverwriteConflicts,
                    ),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _policy = value ?? _policy),
              ),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context).dataWorkbenchBackupCommitHelp),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => _run(_applyRestore),
                    child: Text(
                      AppLocalizations.of(context)
                          .dataWorkbenchBackupConfirmRestore,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _run(_release),
                    child: Text(
                      AppLocalizations.of(context)
                          .dataWorkbenchBackupDiscardPreview,
                    ),
                  ),
                ],
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              TextButton(
                onPressed: _cancel,
                child: Text(
                  _backup?.isCommitting == true
                      ? AppLocalizations.of(context)
                            .dataWorkbenchBackupCancelAfterCommit
                      : AppLocalizations.of(context)
                            .dataWorkbenchBackupCancelTask,
                ),
              ),
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText(_message!),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _newBackup() async {
    final l10n = AppLocalizations.of(context);
    await _release();
    if (_cancelled) throw const TaskCancelled();
    if (ref.read(backgroundJobsProvider).isBusy ||
        ref.read(batchServiceProvider).isRunning ||
        ref.read(libraryExportServiceProvider).isRunning) {
      throw ValidationFailure(l10n.dataWorkbenchBackupAnotherTaskRunning);
    }
    final paths = ref.read(appPathsProvider);
    final lease = await JobCache(
      Directory(p.join(paths.cache.path, 'workbench')),
    ).create('import');
    _lease = lease;
    _backup = BookBackup(
      ref.read(bookRepositoryProvider),
      scratchDirectory: lease.directory,
      appVersion: AppInfo.version,
      jobs: ref.read(backgroundJobsProvider),
    );
  }

  Future<void> _export() async {
    await _newBackup();
    try {
      final output = await _backup!.exportBooks(
        _selected.toList(),
        p.join(_lease!.directory.path, 'library.bookloom'),
        includeSources: _includeSources,
      );
      if (_cancelled) throw const TaskCancelled();
      final result = await ref
          .read(fileServiceProvider)
          .savePreparedFile(
            output,
            suggestedName:
                'bookloom-${DateTime.now().toIso8601String().substring(0, 10)}.bookloom',
            mimeType: 'application/zip',
          );
      if (mounted && result is SaveSaved) {
        setState(
          () =>
              _message = AppLocalizations.of(context).dataWorkbenchBackupSaved,
        );
      }
    } finally {
      await _release();
    }
  }

  Future<void> _prepareRestore() async {
    final l10n = AppLocalizations.of(context);
    final mib = int.tryParse(_budget.text.trim());
    if (mib == null || mib <= 0 || mib > 1024 * 1024) {
      throw ValidationFailure(l10n.dataWorkbenchBackupInvalidBudget);
    }
    final inputs = await ref
        .read(fileServiceProvider)
        .pickImports(multiple: false, extensions: const ['bookloom']);
    if (inputs.isEmpty) return;
    final input = inputs.single;
    try {
      await _newBackup();
      final maxBytes = mib * 1024 * 1024;
      final file = File(p.join(_lease!.directory.path, 'restore.bookloom'));
      try {
        if ((input.size ?? 0) > maxBytes) {
          throw ImportFailure(l10n.dataWorkbenchBackupFileTooLarge);
        }
        final sink = file.openWrite();
        var size = 0;
        try {
          await for (final chunk in input.openRead()) {
            if (_cancelled) throw const TaskCancelled();
            size += chunk.length;
            if (size > maxBytes) {
              throw ImportFailure(l10n.dataWorkbenchBackupActualSizeTooLarge);
            }
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      } finally {
        await input.release();
      }
      final preview = await _backup!.prepareRestore(
        file.path,
        maxOutputBytes: maxBytes,
      );
      if (mounted) setState(() => _preview = preview);
    } on Object {
      await _release();
      rethrow;
    } finally {
      await input.release();
    }
  }

  Future<void> _applyRestore() async {
    final preview = _preview;
    if (preview == null) return;
    if (_policy == RestoreConflictPolicy.overwrite) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            AppLocalizations.of(context).dataWorkbenchBackupOverwriteTitle,
          ),
          content: Text(
            AppLocalizations.of(context).dataWorkbenchBackupOverwriteBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                AppLocalizations.of(context)
                    .dataWorkbenchBackupOverwriteRestore,
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      final result = await _backup!.applyRestore(preview, policy: _policy);
      if (mounted) {
        setState(
          () => _message = [
            AppLocalizations.of(context)
                .dataWorkbenchBackupRestored(result.restoredIds.length),
            AppLocalizations.of(context)
                .dataWorkbenchBackupSkipped(result.skippedIds.length),
            AppLocalizations.of(context)
                .dataWorkbenchBackupCancelled(result.cancelledIds.length),
            ?result.cleanupWarning,
            for (final entry in result.failures.entries)
              '${entry.key}: ${entry.value}',
          ].join('\n'),
        );
      }
      ref.invalidate(libraryBooksProvider);
      await _refresh();
    } finally {
      await _release();
    }
  }

  void _cancel() {
    _cancelled = true;
    _backup?.cancel();
  }

  Future<void> _release() =>
      _releasing ??= _doRelease().whenComplete(() => _releasing = null);

  Future<void> _doRelease() async {
    final preview = _preview;
    _preview = null;
    await preview?.dispose();
    final lease = _lease;
    _lease = null;
    _backup = null;
    await lease?.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _message = null;
    });
    final task = action();
    _operation = task;
    try {
      await task;
    } on TaskCancelled {
      if (mounted) {
        setState(
          () =>
              _message = AppLocalizations.of(context)
                  .dataWorkbenchBackupTaskCancelled,
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error is AppFailure ? error.message : '$error');
      }
    } finally {
      _operation = null;
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

Future<int> _directoryBytes(Directory directory) async {
  if (!await directory.exists()) return 0;
  var bytes = 0;
  await for (final entry in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entry is File) bytes += await entry.length();
  }
  return bytes;
}
