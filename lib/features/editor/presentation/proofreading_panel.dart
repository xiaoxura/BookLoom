import 'package:bookloom/app/offline_dictionaries.dart';
import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Book-wide checks and previewed edits. The session owns the background job,
/// revision check and the single undo entry for each applied preview.
class ProofreadingPanel extends StatefulWidget {
  const ProofreadingPanel({
    super.key,
    required this.session,
    required this.onLocate,
  });

  final EditorSession session;
  final Future<void> Function(String chapterId, String? blockId) onLocate;

  @override
  State<ProofreadingPanel> createState() => _ProofreadingPanelState();
}

class _ProofreadingPanelState extends State<ProofreadingPanel> {
  final _find = TextEditingController();
  final _replacement = TextEditingController();
  AuditReport? _audit;
  List<MissedChapterCandidate>? _missed;
  ToolPreview? _preview;
  String? _previewLabel;
  String? _error;
  bool _working = false;
  bool _regex = false;
  bool _caseSensitive = false;
  ReplaceScope _scope = ReplaceScope.all;
  ConvertMode _convertMode = ConvertMode.simplified;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _find.dispose();
    _replacement.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (_preview?.baseRevision != null &&
        _preview!.baseRevision != widget.session.saveSeq) {
      _preview = null;
    }
    setState(() {});
  }

  void _dropPreview() {
    if (_preview != null) setState(() => _preview = null);
  }

  String _failure(Object error) {
    if (error is AppFailure) {
      return [error.message, if (error.hint != null) error.hint!].join(' ');
    }
    return AppLocalizations.of(context).editorWorkbenchToolFailed;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on TaskCancelled {
      // The user asked to stop the active background job.
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _locate(String chapterId, String? blockId) async {
    try {
      await widget.onLocate(chapterId, blockId);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    }
  }

  Future<void> _applyPreview() => _run(() async {
    final preview = _preview;
    if (preview == null) return;
    await widget.session.applyToolPreview(preview);
    if (mounted) {
      setState(() {
        _preview = null;
        _audit = null;
        _missed = null;
      });
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = widget.session.toolProgress;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Text(
          l10n.editorWorkbenchTools,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.editorWorkbenchToolsIntro),
        if (_working || widget.session.isToolRunning) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(value: progress?.fraction),
          Text(progress?.stage ?? l10n.editorWorkbenchPreparingBook),
          if (widget.session.isToolRunning)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.session.cancelTool,
                child: Text(l10n.editorWorkbenchCancelTask),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        ExpansionTile(
          title: Text(l10n.editorWorkbenchAuditTitle),
          subtitle: Text(l10n.editorWorkbenchAuditDesc),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _working
                    ? null
                    : () => _run(() async {
                        final report = await widget.session.auditBook();
                        if (mounted) setState(() => _audit = report);
                      }),
                child: Text(l10n.editorWorkbenchAuditRun),
              ),
            ),
            if (_audit case final report?) ...[
              ListTile(
                title: Text(l10n.editorWorkbenchAuditTotal(report.total)),
              ),
              for (final kind in AuditIssueKind.values)
                if ((report.counts[kind] ?? 0) > 0)
                  ListTile(
                    dense: true,
                    title: Text(
                      l10n.editorWorkbenchIssueCount(
                        _kindLabel(l10n, kind),
                        report.counts[kind]!,
                      ),
                    ),
                  ),
              for (final issue in report.issues)
                ListTile(
                  dense: true,
                  title: Text(issue.chapterTitle),
                  subtitle: Text(issue.message),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _locate(issue.chapterId, issue.blockId),
                ),
              if (report.total > report.issues.length)
                ListTile(title: Text(l10n.editorWorkbenchAuditLimit)),
            ],
          ],
        ),
        ExpansionTile(
          title: Text(l10n.editorWorkbenchMissedTitle),
          subtitle: Text(l10n.editorWorkbenchMissedDesc),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _working
                    ? null
                    : () => _run(() async {
                        final found = await widget.session
                            .findMissedChapterCandidates();
                        if (mounted) setState(() => _missed = found);
                      }),
                child: Text(l10n.editorWorkbenchMissedRun),
              ),
            ),
            if (_missed case final items?) ...[
              ListTile(
                title: Text(l10n.editorWorkbenchMissedCount(items.length)),
              ),
              for (final item in items.take(100))
                ListTile(
                  dense: true,
                  title: Text(item.text, maxLines: 2),
                  subtitle: Text(
                    l10n.editorWorkbenchMissedLocation(
                      item.chapterIndex + 1,
                      item.blockIndex + 1,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _locate(item.chapterId, item.blockId),
                ),
              if (items.length > 100)
                ListTile(title: Text(l10n.editorWorkbenchMissedLimit)),
            ],
          ],
        ),
        ExpansionTile(
          title: Text(l10n.editorWorkbenchFindReplace),
          children: [
            TextField(
              controller: _find,
              readOnly: _working,
              maxLength: replaceFindLimit,
              decoration: InputDecoration(
                labelText: l10n.editorWorkbenchFindText,
              ),
              onChanged: (_) => _dropPreview(),
            ),
            TextField(
              controller: _replacement,
              readOnly: _working,
              maxLength: replaceTextLimit,
              decoration: InputDecoration(
                labelText: l10n.editorWorkbenchReplaceWith,
              ),
              onChanged: (_) => _dropPreview(),
            ),
            DropdownButtonFormField<ReplaceScope>(
              initialValue: _scope,
              decoration: InputDecoration(labelText: l10n.editorWorkbenchScope),
              items: [
                DropdownMenuItem(
                  value: ReplaceScope.all,
                  child: Text(l10n.editorWorkbenchScopeAll),
                ),
                DropdownMenuItem(
                  value: ReplaceScope.title,
                  child: Text(l10n.editorWorkbenchScopeTitle),
                ),
                DropdownMenuItem(
                  value: ReplaceScope.body,
                  child: Text(l10n.editorWorkbenchScopeBody),
                ),
              ],
              onChanged: _working
                  ? null
                  : (value) => setState(() {
                      _scope = value ?? ReplaceScope.all;
                      _preview = null;
                    }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.editorWorkbenchRegex),
              value: _regex,
              onChanged: _working
                  ? null
                  : (value) => setState(() {
                      _regex = value;
                      _preview = null;
                    }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.editorWorkbenchCaseSensitive),
              value: _caseSensitive,
              onChanged: _working
                  ? null
                  : (value) => setState(() {
                      _caseSensitive = value;
                      _preview = null;
                    }),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _working
                    ? null
                    : () => _run(() async {
                        final result = await widget.session.previewReplace(
                          ReplaceOptions(
                            find: _find.text,
                            replace: _replacement.text,
                            scope: _scope,
                            regex: _regex,
                            caseSensitive: _caseSensitive,
                          ),
                        );
                        if (mounted) {
                          setState(() {
                            _preview = result;
                            _previewLabel = l10n.editorWorkbenchReplaceLabel;
                          });
                        }
                      }),
                child: Text(l10n.editorWorkbenchPreviewReplace),
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text(l10n.editorWorkbenchRenumberTitle),
          children: [
            ListTile(title: Text(l10n.editorWorkbenchRenumberDesc)),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _working
                    ? null
                    : () => _run(() async {
                        final result = await widget.session.previewRenumber();
                        if (mounted) {
                          setState(() {
                            _preview = result;
                            _previewLabel = l10n.editorWorkbenchRenumberLabel;
                          });
                        }
                      }),
                child: Text(l10n.editorWorkbenchPreviewRenumber),
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text(l10n.editorWorkbenchConvertTitle),
          subtitle: Text(l10n.editorWorkbenchConvertDesc),
          children: [
            DropdownButtonFormField<ConvertMode>(
              initialValue: _convertMode,
              decoration: InputDecoration(
                labelText: l10n.editorWorkbenchConvertDirection,
              ),
              items: [
                DropdownMenuItem(
                  value: ConvertMode.simplified,
                  child: Text(l10n.editorWorkbenchConvertSimplified),
                ),
                DropdownMenuItem(
                  value: ConvertMode.taiwan,
                  child: Text(l10n.editorWorkbenchConvertTraditional),
                ),
              ],
              onChanged: _working
                  ? null
                  : (value) => setState(() {
                      _convertMode = value ?? ConvertMode.simplified;
                      _preview = null;
                    }),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _working
                    ? null
                    : () => _run(() async {
                        final dictionaries = await loadOfflineDictionaries();
                        final result = await widget.session.previewConvert(
                          _convertMode,
                          dictionaries,
                        );
                        if (mounted) {
                          setState(() {
                            _preview = result;
                            _previewLabel = l10n.editorWorkbenchConvertLabel;
                          });
                        }
                      }),
                child: Text(l10n.editorWorkbenchPreviewConvert),
              ),
            ),
          ],
        ),
        if (_preview case final preview?) ...[
          const Divider(height: AppSpacing.xxl),
          Text(
            l10n.editorWorkbenchPreviewTitle(
              _previewLabel ?? l10n.editorWorkbenchBatchEdit,
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            l10n.editorWorkbenchPreviewStats(
              preview.hits,
              preview.patches.length,
            ),
          ),
          for (final sample in preview.samples)
            ListTile(
              dense: true,
              title: Text(sample.chapterTitle),
              subtitle: Text(
                '${sample.before}【${sample.match}】${sample.after}',
                maxLines: 3,
              ),
              onTap: () => _locate(sample.chapterId, sample.blockId),
            ),
          if (preview.samples.isEmpty)
            for (final patch in preview.patches.take(20))
              ListTile(
                dense: true,
                title: Text(
                  patch.blockId == null
                      ? l10n.editorChapterTitle
                      : l10n.editorWorkbenchBodyParagraph,
                ),
                subtitle: Text('${patch.before} → ${patch.after}', maxLines: 3),
                onTap: () => _locate(patch.chapterId, patch.blockId),
              ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _working || preview.patches.isEmpty
                ? null
                : _applyPreview,
            child: Text(l10n.editorWorkbenchApplyOneUndo),
          ),
        ],
      ],
    );
  }
}

String _kindLabel(AppLocalizations l10n, AuditIssueKind kind) => switch (kind) {
  AuditIssueKind.missingNumber => l10n.editorWorkbenchIssueMissingNumber,
  AuditIssueKind.duplicateNumber => l10n.editorWorkbenchIssueDuplicateNumber,
  AuditIssueKind.emptyChapter => l10n.editorWorkbenchIssueEmptyChapter,
  AuditIssueKind.duplicateTitle => l10n.editorWorkbenchIssueDuplicateTitle,
  AuditIssueKind.tooLong => l10n.editorWorkbenchIssueTooLong,
  AuditIssueKind.tooShort => l10n.editorWorkbenchIssueTooShort,
  AuditIssueKind.emptyVolume => l10n.editorWorkbenchIssueEmptyVolume,
  AuditIssueKind.adLeftover => l10n.editorWorkbenchIssueAdLeftover,
};
